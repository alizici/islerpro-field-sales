-- =============================================================================
-- 0032 · K43 senkron sözleşmesi · K42 cihaz güvenliği (Faz 7)
--
-- Sözleşmenin tamamı dört kuralda kapanır ve bu dosya üçünü sunucu tarafında
-- karşılar (dördüncüsü — kalıcı kuyruk — istemcidedir):
--
--   1. YAZMALAR APPEND-ONLY. Kuyruktaki her işlem yeni kayıt üretir; mevcut
--      kaydı değiştirmez. Bu yüzden ÇAKIŞMA DOĞMAZ — çözülecek tek şey sıradır.
--   2. İDEMPOTENCY. Her yazma `client_id + local_seq` taşır. Ağ koptuğunda
--      tekrar gönderilen istek çift kayıt üretmez; sunucu ilk sonucu döndürür.
--   3. SAAT KAYMASI. Cihaz saati yalnızca sıralama ipucudur. Raporlar
--      `created_at` (sunucu) okur; ziyaret süresi gibi cihazın ÖLÇTÜĞÜ şeyler
--      cihaz saatinden gelir.
--
-- Neden makbuz tablosuna yalnızca BAŞARILI işlemler yazılıyor:
-- başarısız işlem de kaydedilseydi, geçici bir hata (zaman aşımı, kilit)
-- kalıcı bir "bu işlem hep başarısız" kaydına dönüşür ve kullanıcının kaydı
-- bir daha asla yüklenemezdi. Hata istemcinin kuyruğunda durur — orası zaten
-- kalıcıdır — ve kullanıcıya listelenir.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- K42 · Cihazlar. Sahibin görebildiği, iptal edebildiği kayıt.
-- ---------------------------------------------------------------------------
create table if not exists devices (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references tenants(id) on delete cascade,
  user_id        uuid not null references profiles(id) on delete cascade,
  client_id      text not null,
  ad             text,
  platform       text,
  uygulama_surumu text,
  ilk_gorulme    timestamptz not null default now(),
  son_gorulme    timestamptz not null default now(),
  iptal_at       timestamptz,
  -- İptal edilen cihaz ilk bağlanışında yerel veriyi siler. Bayrak, cihaz
  -- silmeyi ONAYLAYANA kadar açık kalır — "sildim" demeden kapanmaz.
  silinsin       boolean not null default false,
  created_at     timestamptz not null default now(),
  unique (user_id, client_id)
);
create index if not exists devices_tenant_idx on devices(tenant_id, son_gorulme desc);

alter table devices enable row level security;
drop policy if exists devices_self on devices;
create policy devices_self on devices for all
  using (user_id = auth.uid()
         or (tenant_id in (select auth_tenant_ids())
             and auth_has_role(array['isletme_sahibi','dukkan_muduru']::app_role[])))
  with check (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- K43 · İdempotency makbuzları. Yalnızca BAŞARILI işlemler (yukarıdaki not).
-- ---------------------------------------------------------------------------
create table if not exists sync_receipts (
  client_id  text   not null,
  local_seq  bigint not null,
  user_id    uuid   not null references profiles(id) on delete cascade,
  fn         text   not null,
  sonuc      jsonb,
  created_at timestamptz not null default now(),
  primary key (client_id, local_seq)
);
create index if not exists sync_receipts_user_idx on sync_receipts(user_id, created_at desc);

alter table sync_receipts enable row level security;
drop policy if exists sync_receipts_self on sync_receipts;
create policy sync_receipts_self on sync_receipts for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Cihaz kaydı. Her açılışta çağrılır; cevabı istemcinin ne yapacağını söyler.
-- ---------------------------------------------------------------------------
create or replace function register_device(
  p_client_id text,
  p_ad text default null,
  p_platform text default null,
  p_surum text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_tenant uuid; v_id uuid; v_iptal timestamptz; v_sil boolean;
begin
  if coalesce(trim(p_client_id), '') = '' then
    raise exception 'Cihaz kimliği boş olamaz';
  end if;
  select tenant_id into v_tenant from memberships
  where user_id = auth.uid() and status = 'aktif' limit 1;
  if v_tenant is null then raise exception 'Aktif üyelik yok'; end if;

  insert into devices (tenant_id, user_id, client_id, ad, platform,
                       uygulama_surumu)
  values (v_tenant, auth.uid(), p_client_id, p_ad, p_platform, p_surum)
  on conflict (user_id, client_id) do update
    set son_gorulme = now(),
        ad = coalesce(excluded.ad, devices.ad),
        platform = coalesce(excluded.platform, devices.platform),
        uygulama_surumu = coalesce(excluded.uygulama_surumu,
                                   devices.uygulama_surumu)
  returning id, iptal_at, silinsin into v_id, v_iptal, v_sil;

  return jsonb_build_object('device_id', v_id, 'iptal', v_iptal is not null,
                            'silinsin', v_sil);
end $$;

-- İstemci yerel veriyi sildiğini bildirir; bayrak ancak o zaman kapanır.
create or replace function confirm_wipe(p_client_id text) returns void
language sql security definer set search_path = public as $$
  update devices set silinsin = false
  where user_id = auth.uid() and client_id = p_client_id;
$$;

-- K42 · Cihaz kayıtları sahibe görünür.
create or replace function list_devices(p_store_id uuid default null)
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', d.id, 'user_id', d.user_id, 'ad_soyad', p.ad_soyad,
      'cihaz', coalesce(d.ad, d.platform, 'bilinmeyen cihaz'),
      'platform', d.platform, 'surum', d.uygulama_surumu,
      'ilk_gorulme', d.ilk_gorulme, 'son_gorulme', d.son_gorulme,
      'iptal', d.iptal_at is not null, 'silinsin', d.silinsin,
      'gun', extract(day from now() - d.son_gorulme)::int,
      'bekleyen', (select count(*) from sync_receipts sr
                   where sr.client_id = d.client_id
                     and sr.created_at > now() - interval '7 days'))
    order by d.son_gorulme desc), '[]'::jsonb)
  from devices d
  left join profiles p on p.id = d.user_id
  where d.tenant_id in (select auth_tenant_ids())
    and (d.user_id = auth.uid()
         or auth_has_role(array['isletme_sahibi','dukkan_muduru']::app_role[]));
$$;

create or replace function revoke_device(p_device_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_tenant uuid; v_user uuid;
begin
  select tenant_id, user_id into v_tenant, v_user
  from devices where id = p_device_id;
  if v_tenant is null then raise exception 'Cihaz bulunamadı'; end if;
  if v_user <> auth.uid()
     and not (v_tenant in (select auth_tenant_ids())
              and auth_has_role(array['isletme_sahibi','dukkan_muduru']::app_role[]))
  then
    raise exception 'Cihaz iptali için sahip veya müdür olmalısınız';
  end if;

  update devices set iptal_at = now(), silinsin = true where id = p_device_id;

  insert into audit_logs (tenant_id, user_id, eylem, tablo, kayit_id, detay)
  values (v_tenant, auth.uid(), 'revoke_device', 'devices', p_device_id,
          jsonb_build_object('sahibi', v_user));
end $$;

-- K42 · Pazarlamacı pasife alınınca cihazları da iptal edilir ve ilk bağlanışta
-- yerel veri silinir. Bunu `deactivate_member` içine yazmak yerine TRIGGER
-- yaptık: üyeliği hangi yoldan pasife alınırsa alınsın kural işlesin.
create or replace function trg_revoke_devices() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'pasif' and coalesce(old.status::text, '') <> 'pasif' then
    update devices set iptal_at = now(), silinsin = true
    where user_id = new.user_id and iptal_at is null;
  end if;
  return new;
end $$;

drop trigger if exists revoke_devices on memberships;
create trigger revoke_devices after update on memberships
  for each row execute function trg_revoke_devices();

-- ---------------------------------------------------------------------------
-- K43 · Kuyruğu yükle
--
-- Kuyruğun TAMAMI tek istekte gider. Sahada bağlantı kısa aralıklarla açılır;
-- otuz kayıt için otuz tur atmak, tek turda otuz kayıt göndermekten çok daha
-- sık yarıda kalır.
--
-- Her işlem KENDİ alt-işleminde çalışır: biri hata verirse yalnızca o düşer,
-- diğerleri yüklenir. Yarıda kalan kuyruk kullanıcının en sinir bozucu hâlidir.
-- ---------------------------------------------------------------------------
create or replace function sync_push(p_client_id text, p_ops jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  op jsonb; a jsonb; v_seq bigint; v_fn text; v_res jsonb;
  v_out jsonb := '[]'::jsonb; v_onceki jsonb;
  v_ok int := 0; v_hata int := 0; v_tekrar int := 0;
begin
  if coalesce(trim(p_client_id), '') = '' then
    raise exception 'Cihaz kimliği boş olamaz';
  end if;
  if exists (select 1 from devices where user_id = auth.uid()
             and client_id = p_client_id and iptal_at is not null) then
    raise exception 'Bu cihaz iptal edilmiş. Yerel veri silinmeli.';
  end if;

  update devices set son_gorulme = now()
  where user_id = auth.uid() and client_id = p_client_id;

  for op in select * from jsonb_array_elements(coalesce(p_ops, '[]'::jsonb)) loop
    v_seq := (op->>'local_seq')::bigint;
    v_fn  := op->>'fn';
    a     := coalesce(op->'args', '{}'::jsonb);

    -- Kural 2 · aynı anahtar ikinci kez İŞLENMEZ, ilk sonuç döner.
    select jsonb_build_object('local_seq', local_seq, 'durum', 'ok',
                              'sonuc', sonuc, 'tekrar', true)
      into v_onceki from sync_receipts
     where client_id = p_client_id and local_seq = v_seq;
    if v_onceki is not null then
      v_out := v_out || v_onceki; v_tekrar := v_tekrar + 1; continue;
    end if;

    begin
      case v_fn
        when 'start_visit' then
          v_res := start_visit(
            (a->>'institution_id')::uuid, (a->>'contact_id')::uuid,
            a->>'client_key', (a->>'checked_in_at')::timestamptz, null);
        when 'end_visit' then
          v_res := end_visit((a->>'visit_id')::uuid, a->>'not_metni',
                             a->>'sonuc', (a->>'checked_out_at')::timestamptz);
        when 'plan_visit' then
          v_res := jsonb_build_object('id',
            plan_visit((a->>'institution_id')::uuid, (a->>'tarih')::date,
                       a->>'amac'));
        when 'create_request' then
          v_res := create_request(
            (a->>'account_id')::uuid, a->'items', a->>'not_metni',
            (a->>'istenen_tarih')::date, coalesce((a->>'gonder')::boolean, true),
            a->>'client_key', (a->>'visit_id')::uuid);
        when 'submit_request' then
          v_res := submit_request((a->>'request_id')::uuid);
        -- K34 · Elden teslim offline'da ANLIK kesinleşir: mal fiziken verildi,
        -- doğrulanacak bir zimmet bakiyesi yok.
        when 'create_shipment' then
          v_res := create_shipment(
            (a->>'account_id')::uuid, a->'items', (a->>'order_id')::uuid,
            coalesce((a->>'borclandirir')::boolean, true),
            coalesce(a->>'tip', 'teslimat')::shipment_tipi,
            a->>'teslim_alan_ad',
            coalesce(a->>'kaynak', 'depo')::shipment_kaynak,
            a->>'belge_no', a->>'client_key');
        when 'create_payment' then
          v_res := create_payment(
            (a->>'account_id')::uuid, (a->>'tutar')::numeric,
            (a->>'yontem')::odeme_yontem, (a->>'tarih')::date,
            a->>'makbuz_no', a->>'not_metni', a->>'client_key',
            (a->>'cek_vade')::date, a->>'cek_banka', a->>'cek_no');
        else
          raise exception 'Bilinmeyen işlem: %', coalesce(v_fn, '(boş)');
      end case;

      insert into sync_receipts (client_id, local_seq, user_id, fn, sonuc)
      values (p_client_id, v_seq, auth.uid(), v_fn, v_res);
      v_out := v_out || jsonb_build_object('local_seq', v_seq, 'durum', 'ok',
                                           'sonuc', v_res, 'tekrar', false);
      v_ok := v_ok + 1;
    exception when others then
      -- Makbuz YAZILMAZ: geçici hata kalıcı reddedilmeye dönüşmesin.
      v_out := v_out || jsonb_build_object('local_seq', v_seq, 'durum', 'hata',
                                           'fn', v_fn, 'hata', sqlerrm);
      v_hata := v_hata + 1;
    end;
  end loop;

  return jsonb_build_object(
    'sonuclar', v_out, 'basarili', v_ok, 'hatali', v_hata,
    'tekrar', v_tekrar, 'sunucu_saati', now());
end $$;

grant execute on function register_device(text, text, text, text) to authenticated;
grant execute on function confirm_wipe(text) to authenticated;
grant execute on function list_devices(uuid) to authenticated;
grant execute on function revoke_device(uuid) to authenticated;
grant execute on function sync_push(text, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- K43 · Kural 3 — BELGE NUMARASI
--
-- Offline üretilen kayıt geçici numara taşır (`TEMP-{client_id}-{seq}`).
-- Kalıcı numarayı SUNUCU atar; yoksa iki cihaz aynı makbuz numarasını üretir
-- ve iki farklı tahsilat aynı belgeyle anılır.
--
-- Trigger tercih edildi: kural hangi yoldan girilirse girilsin işlesin —
-- senkron kuyruğundan da, ekrandan da.
-- ---------------------------------------------------------------------------
create table if not exists document_counters (
  tenant_id uuid not null references tenants(id) on delete cascade,
  tur       text not null,               -- 'makbuz' | 'irsaliye'
  yil       smallint not null,
  sayac     bigint not null default 0,
  primary key (tenant_id, tur, yil)
);
alter table document_counters enable row level security;
drop policy if exists doc_counters_read on document_counters;
create policy doc_counters_read on document_counters for select
  using (tenant_id in (select auth_tenant_ids()));

create or replace function next_document_no(p_tenant uuid, p_tur text)
returns text
language plpgsql security definer set search_path = public as $$
declare v_yil smallint := extract(year from now())::smallint; v_n bigint;
begin
  insert into document_counters (tenant_id, tur, yil, sayac)
  values (p_tenant, p_tur, v_yil, 1)
  on conflict (tenant_id, tur, yil) do update
    set sayac = document_counters.sayac + 1
  returning sayac into v_n;
  return v_yil || '-' || lpad(v_n::text, 6, '0');
end $$;

-- İki tablo BİLEREK farklı davranıyor:
--   payments.makbuz_no  → BOŞSA DA numara alır. Makbuz müşteriye verilen
--                         belgedir (B1); numarasız makbuz zayıf bir kayıttır.
--   shipments.belge_no  → yalnızca TEMP- ile geleni değiştirir. O alan dış
--                         referanstır (K33) ve opsiyoneldir; boşsa boş kalır.
create or replace function trg_kalici_belge_no() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_table_name = 'payments' then
    if new.makbuz_no is null or new.makbuz_no like 'TEMP-%' then
      new.makbuz_no := next_document_no(new.tenant_id, 'makbuz');
    end if;
  elsif new.belge_no like 'TEMP-%' then
    new.belge_no := next_document_no(new.tenant_id, 'irsaliye');
  end if;
  return new;
end $$;

drop trigger if exists kalici_belge_no on payments;
create trigger kalici_belge_no before insert on payments
  for each row execute function trg_kalici_belge_no();
drop trigger if exists kalici_belge_no on shipments;
create trigger kalici_belge_no before insert on shipments
  for each row execute function trg_kalici_belge_no();

-- ---------------------------------------------------------------------------
-- REFERANS VERİ · senkronun ilk adımı
--
-- Katalog ayrı tutuldu: 24.623 ürün tek cevaba sığmaz ve sahada bağlantı
-- kısa aralıklarla açılır. Portföy, kurum ve kural verisi küçüktür — tek
-- çağrıda iner. Katalog imleçle sayfalanır (`sync_catalog`).
-- ---------------------------------------------------------------------------
alter table products add column if not exists updated_at timestamptz not null default now();
alter table store_products add column if not exists updated_at timestamptz not null default now();

create or replace function trg_touch() returns trigger
language plpgsql set search_path = public as $$
begin new.updated_at := now(); return new; end $$;

drop trigger if exists touch on products;
create trigger touch before update on products
  for each row execute function trg_touch();
drop trigger if exists touch on store_products;
create trigger touch before update on store_products
  for each row execute function trg_touch();

create index if not exists store_products_delta_idx
  on store_products(store_id, updated_at);

create or replace function sync_reference(p_store_id uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  with benim as (
    select a.* from accounts a
    where a.id in (select auth_visible_accounts()) and a.store_id = p_store_id
      and a.durum in ('aktif','tahsilatta')
  )
  select jsonb_build_object(
    -- Kural 4 · Rapor ve sıralama SUNUCU saatini kullanır; istemci sapmayı
    -- buradan ölçer.
    'sunucu_saati', now(),
    'donem', (select jsonb_build_object('id', pe.id, 'ad', pe.ad,
                       'starts_on', pe.starts_on, 'ends_on', pe.ends_on)
              from periods pe join stores s on s.tenant_id = pe.tenant_id
              where s.id = p_store_id and pe.status = 'aktif'
              order by pe.starts_on desc limit 1),
    'cariler', coalesce((select jsonb_agg(jsonb_build_object(
        'id', b.id, 'unvan', b.unvan, 'tip', b.tip, 'durum', b.durum,
        'institution_id', b.institution_id, 'bakiye', b.balance_cache,
        'credit_limit', b.credit_limit, 'discount_tier', b.discount_tier)
      order by b.unvan) from benim b), '[]'::jsonb),
    'kurumlar', coalesce((select jsonb_agg(jsonb_build_object(
        'id', i.id, 'ad', i.ad, 'ilce', i.ilce, 'il', i.il,
        'tip', i.kurum_tipi, 'kademe', i.kademe))
      from institutions i
      where i.id in (select distinct institution_id from benim)), '[]'::jsonb),
    -- K30 · Kişiler işletmeye özeldir; yalnızca kendi tenant'ının kayıtları.
    'kisiler', coalesce((select jsonb_agg(jsonb_build_object(
        'id', c.id, 'institution_id', c.institution_id,
        'ad_soyad', c.ad_soyad, 'gorev', c.gorev, 'brans', c.brans,
        'telefon', c.telefon))
      from institution_contacts c
      where c.tenant_id in (select auth_tenant_ids()) and c.aktif
        and c.institution_id in (select distinct institution_id from benim)),
      '[]'::jsonb),
    'iskonto_kurallari', coalesce((select jsonb_agg(to_jsonb(r))
      from discount_rules r where r.store_id = p_store_id), '[]'::jsonb),
    'iskonto_tavani', (select max(dc.tavan) from discount_caps dc
                       where dc.store_id = p_store_id
                         and (dc.user_id = auth.uid() or dc.user_id is null)),
    -- Teslim edilmeyi bekleyen siparişler: sahada teslimat offline yazılabilsin
    'hazir_siparisler', coalesce((select jsonb_agg(jsonb_build_object(
        'id', o.id, 'account_id', o.account_id, 'durum', o.durum,
        'kalemler', (select jsonb_agg(jsonb_build_object(
            'id', oi.id, 'product_id', oi.product_id, 'adet', oi.adet,
            -- H-3 · sevk edilen türetilir; order_items'ta sayaç yoktur
            'sevk_edilen', coalesce((select sum(si.adet) from shipment_items si
                                     where si.order_item_id = oi.id), 0)))
          from order_items oi where oi.order_id = o.id)))
      from orders o where o.account_id in (select id from benim)
        and o.durum in ('hazir','hazirlaniyor')), '[]'::jsonb)
  )
  where p_store_id in (select auth_store_ids());
$$;

-- İmleçli katalog. `p_since` verilirse yalnızca DEĞİŞENLER iner.
create or replace function sync_catalog(
  p_store_id uuid,
  p_since timestamptz default null,
  p_after uuid default null,
  p_limit integer default 500
) returns jsonb
language sql stable security definer set search_path = public as $$
  with sayfa as (
    select p.id, p.ad, p.barkod, p.katalog, p.kategori, p.ders, p.sinif,
           p.sinav_tipi, p.baski_etiketi, p.etiket_fiyat,
           pub.ad as yayinevi,
           sp.satis_fiyat, sp.varsayilan_iskonto, sp.stok_adedi,
           sp.stok_takibi,
           -- Arşivlenen ürün delta'da `aktif: false` olarak İNER. Dışarıda
           -- bırakılsaydı istemci onu hiç haber almaz, yerel katalogda
           -- sonsuza dek satılabilir görünürdü (K14).
           (sp.aktif and not p.arsivlendi) as aktif,
           greatest(p.updated_at, sp.updated_at) as degisti
    from store_products sp
    join products p on p.id = sp.product_id
    left join publishers pub on pub.id = p.publisher_id
    where sp.store_id = p_store_id
      and p.merged_into_id is null
      -- İlk tam indirmede arşivliyi hiç taşımaya gerek yok; delta turunda ise
      -- taşımak ZORUNLU (yukarıdaki not).
      and (p_since is not null or not p.arsivlendi)
      and (p_since is null or greatest(p.updated_at, sp.updated_at) > p_since)
      and (p_after is null or p.id > p_after)
    order by p.id
    limit greatest(1, least(coalesce(p_limit, 500), 2000))
  )
  select jsonb_build_object(
    'satirlar', coalesce((select jsonb_agg(to_jsonb(s) order by s.id)
                          from sayfa s), '[]'::jsonb),
    'son_id', (select max(id::text) from sayfa),
    'sayi', (select count(*) from sayfa),
    -- İstemci "bitti mi" sorusunu sayıya bakarak tahmin etmesin diye açıkça
    -- söyleniyor: sayfa doluysa devam vardır.
    'bitti', (select count(*) from sayfa) <
             greatest(1, least(coalesce(p_limit, 500), 2000)),
    'sunucu_saati', now())
  where p_store_id in (select auth_store_ids());
$$;

grant execute on function next_document_no(uuid, text) to authenticated;
grant execute on function sync_reference(uuid) to authenticated;
grant execute on function sync_catalog(uuid, timestamptz, uuid, integer) to authenticated;
