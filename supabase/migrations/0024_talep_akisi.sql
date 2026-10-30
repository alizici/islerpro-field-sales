-- =============================================================================
-- 0024 · Faz 3 · Talep akışı — ürünün kalbi
-- Kararlar: K5 K19 K22 K25 K28 K36 K37 K41 · V7
--
-- İki kural bu dosyanın omurgası:
--   K37 · Kalem bazında kısmi onay. 5 kalemin 3'ü onaylanıp 2'si
--         reddedilebilir; en az bir onaylı kalem varsa sipariş doğar.
--   K41 · Bildirim carinin PORTFÖY SAHİBİNE gider — kurumun değil. Aynı okulda
--         kurumsal işi başka, öğretmen işini başka pazarlamacı yürütebilir.
-- =============================================================================

-- ── Bildirim yazan tek yer ────────────────────────────────────────────────
create or replace function notify_user(
  p_tenant uuid, p_user uuid, p_olay text, p_baslik text,
  p_govde text default null, p_hedef_tur text default null,
  p_hedef_id uuid default null) returns void
language sql security definer set search_path = public as $$
  insert into notifications (tenant_id, user_id, olay, baslik, govde,
                             hedef_tur, hedef_id)
  select p_tenant, p_user, p_olay, p_baslik, p_govde, p_hedef_tur, p_hedef_id
  where p_user is not null;
$$;

-- Carinin portföy sahibi (aktif dönem). K41 bildirimlerinin adresi budur.
create or replace function account_owner(p_account uuid) returns uuid
language sql stable security definer set search_path = public as $$
  select a.user_id from assignments a
  join periods p on p.id = a.period_id
  where a.account_id = p_account and a.aktif and p.status = 'aktif'
  order by a.created_at desc limit 1;
$$;

-- ---------------------------------------------------------------------------
-- MUHATAP SEÇİMİ (K5 · K19)
-- Öğretmen okul adına yetkili değilse kurumsal cari seçeneği HİÇ ÇIKMAZ.
-- ---------------------------------------------------------------------------
create or replace function my_request_accounts() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', a.id, 'tip', a.tip, 'unvan', a.unvan,
           'kurum_ad', i.ad, 'ilce', i.ilce,
           'store_id', a.store_id,
           'kendi', a.user_id = auth.uid()) order by a.tip, a.unvan), '[]'::jsonb)
  from accounts a
  join institutions i on i.id = a.institution_id
  where a.id in (select auth_visible_accounts()) and a.durum = 'aktif';
$$;

-- ---------------------------------------------------------------------------
-- K22 · ADET ÖNERİSİ — 4 KADEMELİ YEDEK ZİNCİR
-- Adet alanı her zaman bir değerle gelir; nereden geldiği etiketle görünür.
-- Öneri hiçbir koşulda tıkanmaz.
-- ---------------------------------------------------------------------------
create or replace function suggest_quantity(
  p_account_id uuid, p_product_id uuid, p_period_id uuid default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_sinif smallint[]; v_pub uuid; v_period uuid; v_onceki uuid;
  v_adet integer; v_tenant uuid;
begin
  select sinif, publisher_id into v_sinif, v_pub
  from products where id = p_product_id;
  select tenant_id into v_tenant from accounts where id = p_account_id;

  v_period := coalesce(p_period_id,
    (select id from periods where tenant_id = v_tenant and status = 'aktif'
     order by starts_on desc limit 1));

  -- 1) Bu dönemin sınıf mevcutları — kurum bildirdi
  select sum(e.ogrenci_sayisi) into v_adet
  from account_enrollments e
  where e.account_id = p_account_id and e.period_id = v_period
    and (v_sinif is null or e.sinif = any(v_sinif));
  if v_adet is not null and v_adet > 0 then
    return jsonb_build_object('adet', v_adet, 'kaynak', 'kurum_bildirdi',
                              'etiket', 'kurum bildirdi');
  end if;

  -- 2) Geçen dönemin mevcutları — sınıf mevcutları yıldan yıla büyük ölçüde sabit
  select p2.id into v_onceki
  from periods p2
  join periods pc on pc.id = v_period
  where p2.tenant_id = pc.tenant_id and p2.starts_on < pc.starts_on
  order by p2.starts_on desc limit 1;

  if v_onceki is not null then
    select sum(e.ogrenci_sayisi) into v_adet
    from account_enrollments e
    where e.account_id = p_account_id and e.period_id = v_onceki
      and (v_sinif is null or e.sinif = any(v_sinif));
    if v_adet is not null and v_adet > 0 then
      return jsonb_build_object('adet', v_adet, 'kaynak', 'gecen_donem',
                                'etiket', 'geçen dönem');
    end if;
  end if;

  -- 3) Aynı yayınevinin bu cariye önceki siparişindeki adet — "geçen sefer"
  if v_pub is not null then
    select oi.adet into v_adet
    from order_items oi
    join orders o on o.id = oi.order_id
    join products pr on pr.id = oi.product_id
    where o.account_id = p_account_id and pr.publisher_id = v_pub
    order by o.created_at desc limit 1;
    if v_adet is not null and v_adet > 0 then
      return jsonb_build_object('adet', v_adet, 'kaynak', 'gecen_sefer',
                                'etiket', 'geçen sefer');
    end if;
  end if;

  -- 4) Hiçbiri yoksa boş — elle yazılır. Tıkanma yok, sadece boş alan.
  return jsonb_build_object('adet', null, 'kaynak', 'yok', 'etiket', null);
end $$;

-- ---------------------------------------------------------------------------
-- TALEP AÇ
-- p_items: [{"product_id": "...", "adet": 30, "not_metni": "..."}, …]
-- K36 · product_id ZORUNLUDUR; serbest metin kalem yoktur.
-- K43 · client_key ile idempotent (offline senkron aynı talebi iki kez açmasın).
-- ---------------------------------------------------------------------------
create or replace function create_request(
  p_account_id uuid,
  p_items jsonb,
  p_not_metni text default null,
  p_istenen_tarih date default null,
  p_gonder boolean default true,
  p_client_key text default null,
  p_visit_id uuid default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_tenant uuid; v_store uuid; v_inst uuid; v_period uuid; v_id uuid;
  v_kaynak text; v_sahip uuid; it jsonb; v_n int := 0; v_unvan text;
begin
  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'Talepte en az bir kalem olmalı';
  end if;

  select a.tenant_id, a.store_id, a.institution_id, a.unvan
    into v_tenant, v_store, v_inst, v_unvan
  from accounts a where a.id = p_account_id;
  if v_tenant is null then raise exception 'Cari bulunamadı'; end if;
  if p_account_id not in (select auth_visible_accounts()) then
    raise exception 'Bu cari adına talep açamazsınız';
  end if;

  -- Idempotency: aynı client_key ikinci kez gelirse mevcut talep döner.
  if p_client_key is not null then
    select id into v_id from requests
    where tenant_id = v_tenant and client_key = p_client_key;
    if v_id is not null then
      return jsonb_build_object('id', v_id, 'yeni', false);
    end if;
  end if;

  select id into v_period from periods
  where tenant_id = v_tenant and status = 'aktif'
  order by starts_on desc limit 1;
  if v_period is null then raise exception 'Aktif dönem yok'; end if;

  v_kaynak := case when auth_has_role(array['pazarlamaci']::app_role[])
                   then 'pazarlamaci' else 'ogretmen' end;

  insert into requests (tenant_id, store_id, account_id, institution_id,
                        period_id, visit_id, kaynak, acan_user_id, durum,
                        istenen_tarih, not_metni, client_key)
  values (v_tenant, v_store, p_account_id, v_inst, v_period, p_visit_id,
          v_kaynak, auth.uid(),
          case when p_gonder then 'gonderildi' else 'taslak' end::request_durum,
          p_istenen_tarih, nullif(trim(coalesce(p_not_metni, '')), ''),
          p_client_key)
  returning id into v_id;

  for it in select * from jsonb_array_elements(p_items) loop
    if (it->>'product_id') is null then
      raise exception 'Kalem ürüne bağlı olmalı — serbest metin talep yoktur';
    end if;
    if coalesce((it->>'adet')::int, 0) <= 0 then
      raise exception 'Adet sıfırdan büyük olmalı';
    end if;
    insert into request_items (request_id, product_id, adet)
    values (v_id, (it->>'product_id')::uuid, (it->>'adet')::int);
    v_n := v_n + 1;
  end loop;

  -- K41 · Bildirim CARİNİN portföy sahibine gider, kurumun değil.
  if p_gonder then
    v_sahip := account_owner(p_account_id);
    if v_sahip is not null and v_sahip <> auth.uid() then
      perform notify_user(v_tenant, v_sahip, 'talep_acildi',
        'Yeni talep: ' || v_unvan,
        v_n || ' kalem', 'request', v_id);
    end if;
  end if;

  insert into audit_logs (tenant_id, user_id, eylem, tablo, kayit_id, detay)
  values (v_tenant, auth.uid(), 'create_request', 'requests', v_id,
          jsonb_build_object('account_id', p_account_id, 'kalem', v_n));

  return jsonb_build_object('id', v_id, 'yeni', true, 'kalem', v_n,
                            'durum', case when p_gonder then 'gonderildi'
                                          else 'taslak' end);
end $$;

create or replace function submit_request(p_request_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_tenant uuid; v_durum request_durum; v_acc uuid; v_sahip uuid;
        v_unvan text; v_n int;
begin
  select r.tenant_id, r.durum, r.account_id into v_tenant, v_durum, v_acc
  from requests r where r.id = p_request_id;
  if v_tenant is null or v_acc not in (select auth_visible_accounts()) then
    raise exception 'Talep bulunamadı veya yetkiniz yok';
  end if;
  if v_durum <> 'taslak' then
    raise exception 'Yalnızca taslak talep gönderilebilir (şu an: %)', v_durum;
  end if;
  select count(*) into v_n from request_items where request_id = p_request_id;
  if v_n = 0 then raise exception 'Boş talep gönderilemez'; end if;

  update requests set durum = 'gonderildi', updated_at = now()
  where id = p_request_id;

  select unvan into v_unvan from accounts where id = v_acc;
  v_sahip := account_owner(v_acc);
  if v_sahip is not null and v_sahip <> auth.uid() then
    perform notify_user(v_tenant, v_sahip, 'talep_acildi',
      'Yeni talep: ' || v_unvan, v_n || ' kalem', 'request', p_request_id);
  end if;
  return jsonb_build_object('durum', 'gonderildi');
end $$;

-- Pazarlamacı talebe dokunur: gonderildi → incelemede
create or replace function claim_request(p_request_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_durum request_durum; v_acc uuid;
begin
  select durum, account_id into v_durum, v_acc
  from requests where id = p_request_id;
  if v_acc is null or v_acc not in (select auth_visible_accounts()) then
    raise exception 'Talep bulunamadı veya yetkiniz yok';
  end if;
  if v_durum <> 'gonderildi' then
    raise exception 'Bu talep zaten ele alınmış (%)', v_durum;
  end if;
  update requests set durum = 'incelemede', updated_at = now()
  where id = p_request_id;
  return jsonb_build_object('durum', 'incelemede');
end $$;

-- ---------------------------------------------------------------------------
-- K37 · KALEM BAZINDA KARAR
-- p_kararlar: [{"item_id":"…","durum":"onaylandi"},
--              {"item_id":"…","durum":"reddedildi","red_nedeni":"stokta yok"}]
-- Bekleyen kalem kalmayınca talep kendiliğinden sonuçlanır:
--   en az bir onaylı varsa  → karara_baglandi (sipariş doğabilir)
--   hiç onaylı yoksa        → tamamen_reddedildi
-- ---------------------------------------------------------------------------
create or replace function decide_request_items(
  p_request_id uuid, p_kararlar jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_tenant uuid; v_acc uuid; v_durum request_durum; v_acan uuid; v_unvan text;
  k jsonb; v_bekleyen int; v_onayli int; v_red int; v_yeni request_durum;
begin
  select r.tenant_id, r.account_id, r.durum, r.acan_user_id
    into v_tenant, v_acc, v_durum, v_acan
  from requests r where r.id = p_request_id;
  if v_tenant is null or v_acc not in (select auth_visible_accounts()) then
    raise exception 'Talep bulunamadı veya yetkiniz yok';
  end if;
  if v_durum in ('karara_baglandi','tamamen_reddedildi','iptal') then
    raise exception 'Bu talep zaten sonuçlanmış (%)', v_durum;
  end if;
  if not auth_has_role(array['pazarlamaci','dukkan_muduru','isletme_sahibi']::app_role[]) then
    raise exception 'Talebi karara bağlama yetkiniz yok';
  end if;

  for k in select * from jsonb_array_elements(p_kararlar) loop
    if (k->>'durum') not in ('onaylandi','reddedildi') then
      raise exception 'Geçersiz kalem kararı: %', k->>'durum';
    end if;
    if k->>'durum' = 'reddedildi'
       and coalesce(trim(k->>'red_nedeni'), '') = '' then
      raise exception 'Reddedilen kalem için gerekçe zorunludur';
    end if;
    update request_items set
      durum = (k->>'durum')::request_item_durum,
      red_nedeni = nullif(trim(coalesce(k->>'red_nedeni', '')), '')
    where id = (k->>'item_id')::uuid and request_id = p_request_id;
  end loop;

  select count(*) filter (where durum = 'beklemede'),
         count(*) filter (where durum = 'onaylandi'),
         count(*) filter (where durum = 'reddedildi')
    into v_bekleyen, v_onayli, v_red
  from request_items where request_id = p_request_id;

  if v_bekleyen > 0 then
    -- Kısmi karar: talep incelemede kalır, kapanmaz.
    update requests set durum = 'incelemede', updated_at = now()
    where id = p_request_id;
    return jsonb_build_object('durum', 'incelemede', 'bekleyen', v_bekleyen,
                              'onaylanan', v_onayli, 'reddedilen', v_red);
  end if;

  v_yeni := case when v_onayli > 0 then 'karara_baglandi'
                 else 'tamamen_reddedildi' end::request_durum;
  update requests set durum = v_yeni, updated_at = now()
  where id = p_request_id;

  -- K41 · Talebi AÇAN kişiye bildirim
  select unvan into v_unvan from accounts where id = v_acc;
  if v_acan <> auth.uid() then
    perform notify_user(v_tenant, v_acan, 'talep_karara_baglandi',
      case when v_onayli > 0 then 'Talebiniz karara bağlandı'
           else 'Talebiniz reddedildi' end,
      v_unvan || ' · ' || v_onayli || ' onaylandı, ' || v_red || ' reddedildi',
      'request', p_request_id);
  end if;

  insert into audit_logs (tenant_id, user_id, eylem, tablo, kayit_id, detay)
  values (v_tenant, auth.uid(), 'decide_request', 'requests', p_request_id,
          jsonb_build_object('onaylanan', v_onayli, 'reddedilen', v_red));

  return jsonb_build_object('durum', v_yeni, 'bekleyen', 0,
                            'onaylanan', v_onayli, 'reddedilen', v_red);
end $$;

create or replace function cancel_request(p_request_id uuid, p_gerekce text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_tenant uuid; v_acc uuid; v_durum request_durum; v_acan uuid;
begin
  select tenant_id, account_id, durum, acan_user_id
    into v_tenant, v_acc, v_durum, v_acan
  from requests where id = p_request_id;
  if v_tenant is null or v_acc not in (select auth_visible_accounts()) then
    raise exception 'Talep bulunamadı veya yetkiniz yok';
  end if;
  if v_durum in ('karara_baglandi','tamamen_reddedildi','iptal') then
    raise exception 'Sonuçlanmış talep iptal edilemez (%)', v_durum;
  end if;
  update requests set durum = 'iptal', updated_at = now() where id = p_request_id;
  insert into audit_logs (tenant_id, user_id, eylem, tablo, kayit_id, detay)
  values (v_tenant, auth.uid(), 'cancel_request', 'requests', p_request_id,
          jsonb_build_object('gerekce', p_gerekce));
  return jsonb_build_object('durum', 'iptal');
end $$;

-- ---------------------------------------------------------------------------
-- GELEN KUTUSU
-- ---------------------------------------------------------------------------
create or replace function list_requests(
  p_store_id uuid default null,
  p_durum request_durum default null,
  p_account_id uuid default null,
  p_sadece_bekleyen boolean default false,
  p_limit integer default 50,
  p_offset integer default 0
) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x order by x->>'created_at' desc), '[]'::jsonb)
  from (
    select jsonb_build_object(
      'id', r.id, 'durum', r.durum, 'kaynak', r.kaynak,
      'created_at', r.created_at, 'istenen_tarih', r.istenen_tarih,
      'not_metni', r.not_metni,
      'account_id', r.account_id, 'unvan', a.unvan, 'tip', a.tip,
      'kurum_ad', i.ad,
      'acan', pr.ad_soyad,
      'kalem_sayisi', (select count(*) from request_items ri
                       where ri.request_id = r.id),
      'bekleyen', (select count(*) from request_items ri
                   where ri.request_id = r.id and ri.durum = 'beklemede'),
      'toplam_adet', (select coalesce(sum(ri.adet), 0) from request_items ri
                      where ri.request_id = r.id),
      -- V7 · 24 saattir dokunulmamış mı
      'gecikmis', r.durum = 'gonderildi'
                  and r.created_at < now() - interval '24 hours'
    ) as x
    from requests r
    join accounts a on a.id = r.account_id
    join institutions i on i.id = r.institution_id
    join profiles pr on pr.id = r.acan_user_id
    where r.account_id in (select auth_visible_accounts())
      and (p_store_id is null or r.store_id = p_store_id)
      and (p_durum is null or r.durum = p_durum)
      and (p_account_id is null or r.account_id = p_account_id)
      and (not p_sadece_bekleyen or r.durum in ('gonderildi','incelemede'))
    order by r.created_at desc
    limit p_limit offset p_offset
  ) t;
$$;

-- Kalemler + K25 iskonto önizlemesi. Pazarlamacı karar verirken tutarı görür.
create or replace function request_detail(p_request_id uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', r.id, 'durum', r.durum, 'kaynak', r.kaynak,
    'created_at', r.created_at, 'istenen_tarih', r.istenen_tarih,
    'not_metni', r.not_metni,
    'acan', pr.ad_soyad,
    'cari', jsonb_build_object('id', a.id, 'unvan', a.unvan, 'tip', a.tip,
                               'bakiye', a.balance_cache,
                               'credit_limit', a.credit_limit,
                               'risk', account_total_risk(a.id)),
    'kurum', jsonb_build_object('id', i.id, 'ad', i.ad, 'ilce', i.ilce),
    'kalemler', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', ri.id, 'product_id', ri.product_id,
        'ad', p.ad, 'barkod', p.barkod, 'yayinevi', pub.ad,
        'baski_etiketi', p.baski_etiketi,
        'adet', ri.adet, 'durum', ri.durum, 'red_nedeni', ri.red_nedeni,
        'satis_fiyat', sp.satis_fiyat,
        'iskonto', (resolve_discount_detail(r.store_id, r.account_id,
                                            ri.product_id, ri.adet)->>'oran')::numeric,
        'iskonto_kaynak', resolve_discount_detail(r.store_id, r.account_id,
                                                  ri.product_id, ri.adet)->>'kaynak_ad',
        'satir_tutari', line_total(
            sp.satis_fiyat,
            (resolve_discount_detail(r.store_id, r.account_id,
                                     ri.product_id, ri.adet)->>'oran')::numeric,
            ri.adet),
        -- K23 · eski baskı seçilmişse sessiz kalınmaz
        'baski_uyarisi', edition_warning(ri.product_id, r.store_id)
      ) order by p.ad)
      from request_items ri
      join products p on p.id = ri.product_id
      left join publishers pub on pub.id = p.publisher_id
      left join store_products sp
             on sp.product_id = ri.product_id and sp.store_id = r.store_id
      where ri.request_id = r.id), '[]'::jsonb)
  )
  from requests r
  join accounts a on a.id = r.account_id
  join institutions i on i.id = r.institution_id
  join profiles pr on pr.id = r.acan_user_id
  where r.id = p_request_id
    and r.account_id in (select auth_visible_accounts());
$$;

-- ---------------------------------------------------------------------------
-- V7 · SLA · 24 saattir dokunulmamış talep dükkan sahibine eskale olur.
-- Zamanlanmış görevden çağrılır; testte doğrudan da çağrılabilir.
-- ---------------------------------------------------------------------------
create or replace function escalate_stale_requests(p_saat integer default 24)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare r record; v_n int := 0;
begin
  for r in
    select rq.id, rq.tenant_id, a.unvan
    from requests rq
    join accounts a on a.id = rq.account_id
    where rq.durum = 'gonderildi'
      and not rq.sla_bildirildi
      and rq.created_at < now() - (p_saat || ' hours')::interval
      and rq.tenant_id in (select auth_tenant_ids())
  loop
    perform notify_user(r.tenant_id, m.user_id, 'talep_sla',
      'Talep ' || p_saat || ' saattir bekliyor', r.unvan, 'request', r.id)
    from memberships m
    where m.tenant_id = r.tenant_id and m.role = 'isletme_sahibi'
      and m.status = 'aktif';
    update requests set sla_bildirildi = true where id = r.id;
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('eskale_edilen', v_n);
end $$;

-- ---------------------------------------------------------------------------
-- BİLDİRİMLER
-- ---------------------------------------------------------------------------
create or replace function my_notifications(
  p_limit integer default 30, p_sadece_okunmamis boolean default false)
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', id, 'olay', olay, 'baslik', baslik, 'govde', govde,
           'hedef_tur', hedef_tur, 'hedef_id', hedef_id,
           'okundu', okundu_at is not null, 'created_at', created_at)
         order by created_at desc), '[]'::jsonb)
  from (
    select * from notifications
    where user_id = auth.uid()
      and (not p_sadece_okunmamis or okundu_at is null)
    order by created_at desc limit p_limit
  ) t;
$$;

create or replace function mark_notifications_read(p_ids uuid[] default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_n int;
begin
  update notifications set okundu_at = now()
  where user_id = auth.uid() and okundu_at is null
    and (p_ids is null or id = any(p_ids));
  get diagnostics v_n = row_count;
  return jsonb_build_object('okunan', v_n);
end $$;

grant execute on function notify_user(uuid, uuid, text, text, text, text, uuid) to authenticated;
grant execute on function account_owner(uuid) to authenticated;
grant execute on function my_request_accounts() to authenticated;
grant execute on function suggest_quantity(uuid, uuid, uuid) to authenticated;
grant execute on function create_request(uuid, jsonb, text, date, boolean, text, uuid) to authenticated;
grant execute on function submit_request(uuid) to authenticated;
grant execute on function claim_request(uuid) to authenticated;
grant execute on function decide_request_items(uuid, jsonb) to authenticated;
grant execute on function cancel_request(uuid, text) to authenticated;
grant execute on function list_requests(uuid, request_durum, uuid, boolean, integer, integer) to authenticated;
grant execute on function request_detail(uuid) to authenticated;
grant execute on function escalate_stale_requests(integer) to authenticated;
grant execute on function my_notifications(integer, boolean) to authenticated;
grant execute on function mark_notifications_read(uuid[]) to authenticated;
