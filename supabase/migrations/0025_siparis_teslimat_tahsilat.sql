-- =============================================================================
-- 0025 · Faz 4 · Sipariş, teslimat ve tahsilat
-- Kararlar: K11 K26 K28 K34 K37 K41 K45 K46 K48 · V6 V8 · H-3
--
-- Üç kural bu dosyanın omurgası:
--   K28 · Sipariş satırı fiyatı, iskontoyu VE maliyeti damgalar. store_products
--         sonradan değişse geçmiş sipariş oynamaz.
--   K26 · Borç faturayla değil TESLİMATLA doğar. Sipariş henüz borç değildir.
--   K48 · Ödeme parçalıdır; ödeme durumu hiçbir yerde yazılmaz, türetilir.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- TALEPTEN SİPARİŞE (K37 → K28)
-- Yalnızca ONAYLANMIŞ kalemler siparişe girer.
-- ---------------------------------------------------------------------------
create or replace function create_order_from_request(
  p_request_id uuid, p_tip order_tipi default 'satis') returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  r requests%rowtype; v_id uuid; v_n int := 0; v_toplam numeric := 0;
  it record; v_fiyat numeric; v_isk numeric; v_maliyet numeric; v_tutar numeric;
  v_tavan jsonb; v_onay text; v_risk numeric; v_limit numeric;
begin
  select * into r from requests where id = p_request_id;
  if r.id is null or r.account_id not in (select auth_visible_accounts()) then
    raise exception 'Talep bulunamadı veya yetkiniz yok';
  end if;
  if r.durum <> 'karara_baglandi' then
    raise exception 'Yalnızca karara bağlanmış talepten sipariş doğar (şu an: %)',
      r.durum;
  end if;
  if exists (select 1 from orders where request_id = p_request_id
                                    and durum <> 'iptal') then
    raise exception 'Bu talepten zaten sipariş oluşturulmuş';
  end if;

  insert into orders (tenant_id, store_id, account_id, institution_id,
                      period_id, request_id, visit_id, tip, durum,
                      olusturan_user_id)
  values (r.tenant_id, r.store_id, r.account_id, r.institution_id,
          r.period_id, r.id, r.visit_id, p_tip, 'olusturuldu', auth.uid())
  returning id into v_id;

  for it in
    select ri.product_id, ri.adet
    from request_items ri
    where ri.request_id = p_request_id and ri.durum = 'onaylandi'
  loop
    select sp.satis_fiyat, sp.alis_fiyat into v_fiyat, v_maliyet
    from store_products sp
    where sp.store_id = r.store_id and sp.product_id = it.product_id;
    if v_fiyat is null then
      raise exception 'Ürünün bu dükkanda satış fiyatı yok — sipariş satırı damgalanamaz';
    end if;

    -- K25 · iskonto sipariş ANINDA çözümlenir ve K28 gereği damgalanır
    v_isk := resolve_discount(r.store_id, r.account_id, it.product_id, it.adet);
    v_tutar := line_total(v_fiyat, v_isk, it.adet);

    insert into order_items (order_id, product_id, adet, birim_fiyat,
                             iskonto_orani, birim_maliyet, satir_tutari)
    values (v_id, it.product_id, it.adet, v_fiyat, v_isk, v_maliyet, v_tutar);

    v_toplam := v_toplam + v_tutar;
    v_n := v_n + 1;

    -- K25 · pazarlamacı tavanı aşıldıysa sipariş onaya düşer
    v_tavan := check_discount_cap(r.store_id, v_isk);
    if (v_tavan->>'asildi')::boolean then
      v_onay := 'İskonto tavanı aşıldı (%' || round(v_isk * 100) || ')';
    end if;
  end loop;

  if v_n = 0 then
    raise exception 'Talepte onaylanmış kalem yok';
  end if;

  -- K11 · limit kontrolü TOPLAM RİSKE bakar (bakiye + vadesi gelmemiş çek)
  select account_total_risk(r.account_id), credit_limit into v_risk, v_limit
  from accounts where id = r.account_id;
  if v_limit > 0 and (v_risk + v_toplam) > v_limit then
    v_onay := coalesce(v_onay || ' · ', '') || 'Kredi limiti aşılıyor';
  end if;

  if v_onay is not null then
    update orders set durum = 'onay_bekliyor', onay_gerekce = v_onay
    where id = v_id;
    perform notify_user(r.tenant_id, m.user_id, 'siparis_onay',
      'Sipariş onaya düştü', v_onay, 'order', v_id)
    from memberships m
    where m.tenant_id = r.tenant_id and m.role = 'isletme_sahibi'
      and m.status = 'aktif';
  else
    -- K46 · saha siparişi dükkanın "Hazırlanacak" kutusuna düşer
    perform notify_user(r.tenant_id, m.user_id, 'siparis_hazirlanacak',
      'Hazırlanacak sipariş', v_n || ' kalem', 'order', v_id)
    from memberships m
    where m.store_id = r.store_id and m.status = 'aktif'
      and m.role in ('hazirlik','dukkan_muduru');
  end if;

  insert into audit_logs (tenant_id, user_id, eylem, tablo, kayit_id, detay)
  values (r.tenant_id, auth.uid(), 'create_order', 'orders', v_id,
          jsonb_build_object('request_id', p_request_id, 'kalem', v_n,
                             'toplam', v_toplam, 'onay', v_onay));

  return jsonb_build_object('id', v_id, 'kalem', v_n, 'toplam', v_toplam,
                            'durum', coalesce(
                              case when v_onay is not null
                                   then 'onay_bekliyor' end, 'olusturuldu'),
                            'onay_gerekce', v_onay);
end $$;

-- ---------------------------------------------------------------------------
-- K46 · SİPARİŞ DURUM MAKİNESİ
-- Geçişler açıkça tanımlıdır; "kim ve ne zaman" damgalanır.
-- ---------------------------------------------------------------------------
create or replace function set_order_status(
  p_order_id uuid, p_durum order_durum, p_gerekce text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare o orders%rowtype; v_izin boolean;
begin
  select * into o from orders where id = p_order_id;
  if o.id is null or o.account_id not in (select auth_visible_accounts()) then
    raise exception 'Sipariş bulunamadı veya yetkiniz yok';
  end if;

  v_izin := case
    when o.durum = 'olusturuldu'   then p_durum in ('hazirlaniyor','iptal')
    when o.durum = 'onay_bekliyor' then p_durum in ('olusturuldu','reddedildi','iptal')
    when o.durum = 'hazirlaniyor'  then p_durum in ('hazir','iptal')
    when o.durum = 'hazir'         then p_durum in ('sevk_edildi','hazirlaniyor','iptal')
    when o.durum = 'sevk_edildi'   then p_durum in ('kismi_teslim','teslim_edildi','iptal')
    when o.durum = 'kismi_teslim'  then p_durum in ('teslim_edildi','kapandi')
    when o.durum = 'teslim_edildi' then p_durum in ('kapandi')
    else false end;
  if not v_izin then
    raise exception '% → % geçişi tanımlı değil', o.durum, p_durum;
  end if;

  if p_durum = 'onay_bekliyor' or o.durum = 'onay_bekliyor' then
    if not auth_has_role(array['isletme_sahibi','dukkan_muduru']::app_role[]) then
      raise exception 'Onay bekleyen siparişi yalnızca sahip veya müdür ilerletebilir';
    end if;
  end if;

  if p_durum = 'hazirlaniyor' then
    update orders set durum = p_durum,
      hazirlayan_user_id = auth.uid(),
      hazirlik_basladi_at = coalesce(hazirlik_basladi_at, now()),
      updated_at = now()
    where id = p_order_id;
  elsif p_durum = 'hazir' then
    update orders set durum = p_durum, hazirlik_bitti_at = now(),
                      updated_at = now()
    where id = p_order_id;
    -- K46 · "Hazır" işaretlenince siparişi giren pazarlamacıya bildirim
    perform notify_user(o.tenant_id, o.olusturan_user_id, 'siparis_hazir',
      'Sipariş hazır', null, 'order', p_order_id);
  else
    update orders set durum = p_durum,
                      onay_gerekce = coalesce(p_gerekce, onay_gerekce),
                      updated_at = now()
    where id = p_order_id;
  end if;

  insert into audit_logs (tenant_id, user_id, eylem, tablo, kayit_id, detay)
  values (o.tenant_id, auth.uid(), 'order_status', 'orders', p_order_id,
          jsonb_build_object('from', o.durum, 'to', p_durum));

  return jsonb_build_object('durum', p_durum, 'onceki', o.durum);
end $$;

-- ---------------------------------------------------------------------------
-- SİPARİŞ LİSTESİ VE DETAYI
-- H-3 · Backorder AYRI KAYIT DEĞİLDİR — sevk edilmemiş adetten TÜRETİLİR.
-- ---------------------------------------------------------------------------
create or replace function list_orders(
  p_store_id uuid default null,
  p_durum order_durum default null,
  p_account_id uuid default null,
  p_hazirlik_kutusu boolean default false,
  p_limit integer default 50, p_offset integer default 0
) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x order by x->>'created_at' desc), '[]'::jsonb)
  from (
    select jsonb_build_object(
      'id', o.id, 'durum', o.durum, 'tip', o.tip,
      'created_at', o.created_at, 'onay_gerekce', o.onay_gerekce,
      'account_id', o.account_id, 'unvan', a.unvan, 'tip_cari', a.tip,
      'kurum_ad', i.ad,
      'olusturan', pr.ad_soyad,
      'hazirlayan', hz.ad_soyad,
      'kalem_sayisi', (select count(*) from order_items oi where oi.order_id = o.id),
      'toplam', (select coalesce(sum(oi.satir_tutari), 0)
                 from order_items oi where oi.order_id = o.id),
      -- H-3 · sevk edilmemiş adet
      'bekleyen_adet', (
        select coalesce(sum(oi.adet), 0) - coalesce((
          select sum(si.adet) from shipment_items si
          join shipments sh on sh.id = si.shipment_id
          where si.order_item_id in (select id from order_items where order_id = o.id)
        ), 0)
        from order_items oi where oi.order_id = o.id)
    ) as x
    from orders o
    join accounts a on a.id = o.account_id
    join institutions i on i.id = o.institution_id
    join profiles pr on pr.id = o.olusturan_user_id
    left join profiles hz on hz.id = o.hazirlayan_user_id
    where o.account_id in (select auth_visible_accounts())
      and (p_store_id is null or o.store_id = p_store_id)
      and (p_durum is null or o.durum = p_durum)
      and (p_account_id is null or o.account_id = p_account_id)
      and (not p_hazirlik_kutusu
           or o.durum in ('olusturuldu','hazirlaniyor','hazir'))
    order by o.created_at desc
    limit p_limit offset p_offset
  ) t;
$$;

create or replace function order_detail(p_order_id uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', o.id, 'durum', o.durum, 'tip', o.tip,
    'created_at', o.created_at, 'onay_gerekce', o.onay_gerekce,
    'request_id', o.request_id,
    'olusturan', pr.ad_soyad, 'hazirlayan', hz.ad_soyad,
    'hazirlik_basladi_at', o.hazirlik_basladi_at,
    'hazirlik_bitti_at', o.hazirlik_bitti_at,
    'cari', jsonb_build_object('id', a.id, 'unvan', a.unvan, 'tip', a.tip,
                               'bakiye', a.balance_cache,
                               'risk', account_total_risk(a.id),
                               'credit_limit', a.credit_limit),
    'kurum', jsonb_build_object('id', i.id, 'ad', i.ad),
    'toplam', (select coalesce(sum(oi.satir_tutari), 0)
               from order_items oi where oi.order_id = o.id),
    'kalemler', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', oi.id, 'product_id', oi.product_id, 'ad', p.ad,
        'barkod', p.barkod, 'yayinevi', pub.ad,
        'adet', oi.adet,
        -- K28 · damgalanmış değerler; güncel fiyattan bağımsız
        'birim_fiyat', oi.birim_fiyat,
        'iskonto_orani', oi.iskonto_orani,
        'satir_tutari', oi.satir_tutari,
        'sevk_edilen', coalesce((select sum(si.adet) from shipment_items si
                                 where si.order_item_id = oi.id), 0),
        -- H-3 · backorder türetilir, ayrı kayıt açılmaz
        'backorder', oi.adet - coalesce((select sum(si.adet) from shipment_items si
                                         where si.order_item_id = oi.id), 0)
      ) order by p.ad)
      from order_items oi
      join products p on p.id = oi.product_id
      left join publishers pub on pub.id = p.publisher_id
      where oi.order_id = o.id), '[]'::jsonb)
  )
  from orders o
  join accounts a on a.id = o.account_id
  join institutions i on i.id = o.institution_id
  join profiles pr on pr.id = o.olusturan_user_id
  left join profiles hz on hz.id = o.hazirlayan_user_id
  where o.id = p_order_id and o.account_id in (select auth_visible_accounts());
$$;

-- ---------------------------------------------------------------------------
-- K26 · TESLİMAT · BORÇ BURADA DOĞAR
-- p_items: [{"order_item_id":"…","adet":3}, …]  veya siparişsiz elden teslim:
--          [{"product_id":"…","adet":3}, …]
-- borclandirir=false → KONSİNYE: fiziksel hareket var, borç yok (C-1).
-- ---------------------------------------------------------------------------
create or replace function create_shipment(
  p_account_id uuid,
  p_items jsonb,
  p_order_id uuid default null,
  p_borclandirir boolean default true,
  p_tip shipment_tipi default 'teslimat',
  p_teslim_alan_ad text default null,
  p_kaynak shipment_kaynak default 'depo',
  p_belge_no text default null,
  p_client_key text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  a accounts%rowtype; v_id uuid; v_period uuid; it jsonb;
  v_pid uuid; v_adet int; v_fiyat numeric; v_isk numeric; v_maliyet numeric;
  v_tutar numeric; v_toplam numeric := 0; v_n int := 0; v_kalan int;
begin
  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'Teslimatta en az bir kalem olmalı';
  end if;
  select * into a from accounts where id = p_account_id;
  if a.id is null or a.id not in (select auth_visible_accounts()) then
    raise exception 'Cari bulunamadı veya yetkiniz yok';
  end if;

  if p_client_key is not null then
    select id into v_id from shipments
    where tenant_id = a.tenant_id and client_key = p_client_key;
    if v_id is not null then
      return jsonb_build_object('id', v_id, 'yeni', false);
    end if;
  end if;

  select id into v_period from periods
  where tenant_id = a.tenant_id and status = 'aktif'
  order by starts_on desc limit 1;
  if v_period is null then raise exception 'Aktif dönem yok'; end if;

  insert into shipments (tenant_id, store_id, account_id, institution_id,
                         period_id, order_id, tip, borclandirir, kaynak,
                         teslim_alan_ad, teslim_edildi_at, belge_no, client_key)
  values (a.tenant_id, a.store_id, p_account_id, a.institution_id, v_period,
          p_order_id, p_tip, p_borclandirir, p_kaynak,
          nullif(trim(coalesce(p_teslim_alan_ad, '')), ''), now(),
          nullif(trim(coalesce(p_belge_no, '')), ''), p_client_key)
  returning id into v_id;

  for it in select * from jsonb_array_elements(p_items) loop
    v_adet := coalesce((it->>'adet')::int, 0);
    if v_adet <= 0 then raise exception 'Adet sıfırdan büyük olmalı'; end if;

    if (it->>'order_item_id') is not null then
      select oi.product_id, oi.birim_fiyat, oi.iskonto_orani, oi.birim_maliyet,
             oi.adet - coalesce((select sum(si.adet) from shipment_items si
                                 where si.order_item_id = oi.id), 0)
        into v_pid, v_fiyat, v_isk, v_maliyet, v_kalan
      from order_items oi where oi.id = (it->>'order_item_id')::uuid;
      if v_pid is null then raise exception 'Sipariş kalemi bulunamadı'; end if;
      -- H-3 · sipariştekinden fazla sevk edilemez
      if v_adet > v_kalan then
        raise exception 'Bu kalemde sevk edilebilecek % adet kaldı, % istendi',
          v_kalan, v_adet;
      end if;
    else
      v_pid := (it->>'product_id')::uuid;
      if v_pid is null then raise exception 'Kalem ürüne bağlı olmalı'; end if;
      -- Siparişsiz elden teslim: fiyat teslimat anında damgalanır (K28)
      select sp.satis_fiyat, sp.alis_fiyat into v_fiyat, v_maliyet
      from store_products sp
      where sp.store_id = a.store_id and sp.product_id = v_pid;
      if v_fiyat is null then
        raise exception 'Ürünün bu dükkanda satış fiyatı yok';
      end if;
      v_isk := resolve_discount(a.store_id, p_account_id, v_pid, v_adet);
    end if;

    v_tutar := line_total(v_fiyat, v_isk, v_adet);
    insert into shipment_items (shipment_id, order_item_id, product_id, adet,
                                birim_fiyat, iskonto_orani, birim_maliyet,
                                satir_tutari)
    values (v_id, (it->>'order_item_id')::uuid, v_pid, v_adet,
            v_fiyat, v_isk, v_maliyet, v_tutar);
    v_toplam := v_toplam + v_tutar;
    v_n := v_n + 1;
  end loop;

  -- Sipariş durumu: hepsi sevk edildiyse teslim_edildi, değilse kısmi
  if p_order_id is not null then
    select coalesce(sum(oi.adet), 0) - coalesce((
             select sum(si.adet) from shipment_items si
             where si.order_item_id in (select id from order_items
                                        where order_id = p_order_id)), 0)
      into v_kalan
    from order_items oi where oi.order_id = p_order_id;

    update orders set durum = case when v_kalan <= 0 then 'teslim_edildi'
                                   else 'kismi_teslim' end::order_durum,
                      updated_at = now()
    where id = p_order_id;
  end if;

  -- K41 · teslimat bildirimi carinin kişisine/portföy sahibine
  perform notify_user(a.tenant_id, account_owner(p_account_id), 'teslimat',
    'Teslimat yapıldı', a.unvan || ' · ' || v_n || ' kalem', 'shipment', v_id);

  insert into audit_logs (tenant_id, user_id, eylem, tablo, kayit_id, detay)
  values (a.tenant_id, auth.uid(), 'create_shipment', 'shipments', v_id,
          jsonb_build_object('borclandirir', p_borclandirir,
                             'kalem', v_n, 'toplam', v_toplam));

  return jsonb_build_object('id', v_id, 'yeni', true, 'kalem', v_n,
                            'toplam', v_toplam,
                            'borclandirir', p_borclandirir,
                            'kalan_adet', coalesce(v_kalan, 0));
end $$;

-- ---------------------------------------------------------------------------
-- K48 · TAHSİLAT · FIFO mahsup, parçalı ödeme, avans
-- Çek ödeme değil ödeme VAADİDİR: cheques kaydı doğar, bakiye tahsil
-- edildiğinde düşer (K11).
-- ---------------------------------------------------------------------------
create or replace function create_payment(
  p_account_id uuid,
  p_tutar numeric,
  p_yontem odeme_yontem,
  p_tarih date default null,
  p_makbuz_no text default null,
  p_not_metni text default null,
  p_client_key text default null,
  p_cek_vade date default null,
  p_cek_banka text default null,
  p_cek_no text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a accounts%rowtype; v_id uuid; v_period uuid; v_dagitilan numeric;
begin
  if p_tutar is null or p_tutar <= 0 then
    raise exception 'Tahsilat tutarı sıfırdan büyük olmalı';
  end if;
  select * into a from accounts where id = p_account_id;
  if a.id is null or a.id not in (select auth_visible_accounts()) then
    raise exception 'Cari bulunamadı veya yetkiniz yok';
  end if;
  if p_yontem in ('cek','senet') and p_cek_vade is null then
    raise exception 'Çek/senet için vade tarihi zorunludur';
  end if;

  if p_client_key is not null then
    select id into v_id from payments
    where tenant_id = a.tenant_id and client_key = p_client_key;
    if v_id is not null then
      return jsonb_build_object('id', v_id, 'yeni', false);
    end if;
  end if;

  select id into v_period from periods
  where tenant_id = a.tenant_id and status = 'aktif'
  order by starts_on desc limit 1;

  insert into payments (tenant_id, store_id, account_id, institution_id,
                        period_id, tarih, tutar, yontem, makbuz_no,
                        alan_user_id, not_metni, client_key)
  values (a.tenant_id, a.store_id, p_account_id, a.institution_id, v_period,
          coalesce(p_tarih, current_date), p_tutar, p_yontem,
          nullif(trim(coalesce(p_makbuz_no, '')), ''), auth.uid(),
          nullif(trim(coalesce(p_not_metni, '')), ''), p_client_key)
  returning id into v_id;

  if p_yontem in ('cek','senet') then
    -- K11 · Ödeme vaadi. Bakiye HENÜZ düşmez; mahsup da yapılmaz.
    insert into cheques (tenant_id, store_id, account_id, payment_id,
                         period_id, tip, banka, cheque_no, due_date, tutar)
    values (a.tenant_id, a.store_id, p_account_id, v_id, v_period,
            case when p_yontem = 'cek' then 'cek' else 'senet' end::cek_tipi,
            p_cek_banka, p_cek_no, p_cek_vade, p_tutar);
    return jsonb_build_object('id', v_id, 'yeni', true, 'cek', true,
                              'dagitilan', 0,
                              'not', 'Çek portföye alındı; bakiye tahsil edilince düşer');
  end if;

  -- K48 · FIFO mahsup: en eski açık borçtan başlar
  perform allocate_payment_fifo(v_id);
  select coalesce(sum(tutar), 0) into v_dagitilan
  from payment_allocations where payment_id = v_id;

  insert into audit_logs (tenant_id, user_id, eylem, tablo, kayit_id, detay)
  values (a.tenant_id, auth.uid(), 'create_payment', 'payments', v_id,
          jsonb_build_object('tutar', p_tutar, 'yontem', p_yontem,
                             'dagitilan', v_dagitilan));

  return jsonb_build_object('id', v_id, 'yeni', true, 'cek', false,
                            'dagitilan', v_dagitilan,
                            'avans', p_tutar - v_dagitilan);
end $$;

-- ---------------------------------------------------------------------------
-- CARİ EKSTRESİ · Bakiye türetimini GÖRÜNÜR kılar (K29 · K48)
-- Her satır bir olay kaydıdır; yürüyen bakiye burada hesaplanır.
-- ---------------------------------------------------------------------------
create or replace function account_statement(
  p_account_id uuid, p_limit integer default 100) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'bakiye', calc_account_balance(p_account_id),
    'risk', account_total_risk(p_account_id),
    'acik_konsinye', open_consignment(p_account_id),
    'hareketler', coalesce((
      select jsonb_agg(x order by x->>'tarih' desc) from (
        -- Borçlandıran teslimat
        select jsonb_build_object(
          'tur', 'teslimat', 'id', s.id, 'tarih', s.teslim_edildi_at,
          'aciklama', case when s.borclandirir then 'Teslimat'
                           else 'Konsinye teslimat (borç doğmaz)' end,
          'borc', case when s.borclandirir then
                    (select coalesce(sum(si.satir_tutari), 0)
                     from shipment_items si where si.shipment_id = s.id)
                  else 0 end,
          'alacak', 0,
          'odeme_durumu', shipment_payment_status(s.id)) as x
        from shipments s where s.account_id = p_account_id
        union all
        -- Tahsilat
        select jsonb_build_object(
          'tur', 'tahsilat', 'id', p.id, 'tarih', p.created_at,
          'aciklama', 'Tahsilat · ' || p.yontem,
          'borc', 0, 'alacak', case when p.yontem in ('cek','senet') then 0
                                    else p.tutar end,
          'odeme_durumu', case when p.yontem in ('cek','senet')
                               then 'vaat' else null end)
        from payments p where p.account_id = p_account_id
        union all
        -- İade
        select jsonb_build_object(
          'tur', 'iade', 'id', rt.id, 'tarih', rt.created_at,
          'aciklama', 'İade' || coalesce(' · ' || rt.gerekce, ''),
          'borc', 0,
          'alacak', case when rt.bakiyeyi_azaltir then
                      (select coalesce(sum(ri.satir_tutari), 0)
                       from return_items ri where ri.return_id = rt.id)
                    else 0 end,
          'odeme_durumu', null)
        from returns rt where rt.account_id = p_account_id
        limit p_limit
      ) t), '[]'::jsonb)
  )
  where p_account_id in (select auth_visible_accounts());
$$;

-- Borçlu cariler — tahsilat ekranının omurgası. K7 · TOPLAM SATIRI YOK.
create or replace function open_debts(p_store_id uuid, p_limit integer default 100)
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', a.id, 'unvan', a.unvan, 'tip', a.tip,
           'kurum_ad', i.ad,
           'bakiye', a.balance_cache,
           'risk', account_total_risk(a.id),
           'credit_limit', a.credit_limit,
           'pazarlamaci', (select pr.ad_soyad from assignments asg
                           join profiles pr on pr.id = asg.user_id
                           where asg.account_id = a.id and asg.aktif limit 1),
           'en_eski_borc', (select min(s.teslim_edildi_at) from shipments s
                            where s.account_id = a.id and s.borclandirir
                              and shipment_payment_status(s.id) <> 'odendi'))
         order by a.balance_cache desc), '[]'::jsonb)
  from accounts a
  join institutions i on i.id = a.institution_id
  where a.store_id = p_store_id
    and a.id in (select auth_visible_accounts())
    and a.balance_cache > 0
  limit p_limit;
$$;

grant execute on function create_order_from_request(uuid, order_tipi) to authenticated;
grant execute on function set_order_status(uuid, order_durum, text) to authenticated;
grant execute on function list_orders(uuid, order_durum, uuid, boolean, integer, integer) to authenticated;
grant execute on function order_detail(uuid) to authenticated;
grant execute on function create_shipment(uuid, jsonb, uuid, boolean, shipment_tipi, text, shipment_kaynak, text, text) to authenticated;
grant execute on function create_payment(uuid, numeric, odeme_yontem, date, text, text, text, date, text, text) to authenticated;
grant execute on function account_statement(uuid, integer) to authenticated;
grant execute on function open_debts(uuid, integer) to authenticated;
