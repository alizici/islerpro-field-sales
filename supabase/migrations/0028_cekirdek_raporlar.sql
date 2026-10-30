-- =============================================================================
-- 0028 · Faz 4 kalanı · Çekirdek raporlar + makbuz + dönem kilidi
-- Kararlar: K7 K8 K11 K26 K28 K45 K48 K50 · B1
--
-- "Pilot bunlarsız çalışmaz" denen dört rapor: borçlu cariler (0025'te),
-- yaşlandırma, tahsilat özeti, basit ciro.
--
-- K7 · Hiçbiri kurum düzeyinde bakiye toplamı üretmez. Ciro raporu kurum
-- kırılımı verir ama etiketi ALACAK değil HACİMDİR.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- YAŞLANDIRMA · Borç yaşı kovaları: 0-30 · 31-60 · 61-90 · 90+
-- Yaş, borcun doğduğu ana göre ölçülür: teslimat tarihi (K26).
-- ---------------------------------------------------------------------------
create or replace function aging_report(
  p_store_id uuid, p_pazarlamaci uuid default null) returns jsonb
language sql stable security definer set search_path = public as $$
  with acik as (
    select
      s.account_id,
      s.teslim_edildi_at,
      (select coalesce(sum(si.satir_tutari), 0)
       from shipment_items si where si.shipment_id = s.id)
      - (select coalesce(sum(pa.tutar), 0)
         from payment_allocations pa where pa.shipment_id = s.id) as kalan,
      extract(day from now() - s.teslim_edildi_at)::int as yas
    from shipments s
    where s.borclandirir
      and s.account_id in (select auth_visible_accounts())
      and s.store_id = p_store_id
  ),
  kova as (
    select a.account_id,
           sum(a.kalan) filter (where a.yas <= 30)              as k0,
           sum(a.kalan) filter (where a.yas between 31 and 60)  as k31,
           sum(a.kalan) filter (where a.yas between 61 and 90)  as k61,
           sum(a.kalan) filter (where a.yas > 90)               as k90,
           sum(a.kalan) as toplam,
           max(a.yas) filter (where a.kalan > 0) as en_eski_gun
    from acik a
    where a.kalan > 0.005
    group by a.account_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', ac.id, 'unvan', ac.unvan, 'tip', ac.tip,
           'kurum_ad', i.ad,
           'pazarlamaci', pr.ad_soyad,
           'gun_0_30',  coalesce(k.k0, 0),
           'gun_31_60', coalesce(k.k31, 0),
           'gun_61_90', coalesce(k.k61, 0),
           'gun_90_ust', coalesce(k.k90, 0),
           'toplam', k.toplam,
           'en_eski_gun', k.en_eski_gun)
         order by k.k90 desc nulls last, k.toplam desc), '[]'::jsonb)
  from kova k
  join accounts ac on ac.id = k.account_id
  join institutions i on i.id = ac.institution_id
  left join lateral (
    select asg.user_id from assignments asg
    where asg.account_id = ac.id and asg.aktif limit 1) a2 on true
  left join profiles pr on pr.id = a2.user_id
  where p_pazarlamaci is null or a2.user_id = p_pazarlamaci;
$$;

-- ---------------------------------------------------------------------------
-- TAHSİLAT ÖZETİ · yöntem × pazarlamacı × ay
-- K11 · Çek/senet ayrı gösterilir; henüz TAHSİLAT DEĞİL, vaattir.
-- ---------------------------------------------------------------------------
create or replace function collection_summary(
  p_store_id uuid,
  p_baslangic date default null,
  p_bitis date default null,
  p_period_id uuid default null
) returns jsonb
language sql stable security definer set search_path = public as $$
  with p as (
    select pm.*, pr.ad_soyad as alan_ad
    from payments pm
    left join profiles pr on pr.id = pm.alan_user_id
    where pm.store_id = p_store_id
      and pm.account_id in (select auth_visible_accounts())
      and (p_period_id is null or pm.period_id = p_period_id)
      and (p_baslangic is null or pm.tarih >= p_baslangic)
      and (p_bitis is null or pm.tarih <= p_bitis)
  )
  select jsonb_build_object(
    'tahsil_edilen', coalesce((select sum(tutar) from p
                               where yontem not in ('cek','senet')), 0),
    'vaat', coalesce((select sum(tutar) from p
                      where yontem in ('cek','senet')), 0),
    'adet', (select count(*) from p),
    'yonteme_gore', coalesce((
      select jsonb_agg(jsonb_build_object(
               'yontem', yontem, 'adet', n, 'tutar', t,
               'vaat', yontem in ('cek','senet')) order by t desc)
      from (select yontem, count(*) n, sum(tutar) t from p group by yontem) x
    ), '[]'::jsonb),
    'pazarlamaciya_gore', coalesce((
      select jsonb_agg(jsonb_build_object(
               'ad_soyad', alan_ad, 'adet', n, 'tutar', t) order by t desc)
      from (select alan_ad, count(*) n, sum(tutar) t from p
            where yontem not in ('cek','senet')
            group by alan_ad) y
    ), '[]'::jsonb),
    'aya_gore', coalesce((
      select jsonb_agg(jsonb_build_object('ay', ay, 'tutar', t) order by ay)
      from (select to_char(tarih, 'YYYY-MM') ay, sum(tutar) t from p
            where yontem not in ('cek','senet')
            group by 1) z
    ), '[]'::jsonb)
  );
$$;

-- ---------------------------------------------------------------------------
-- ÖDEME DURUMU DAĞILIMI (K48) — teslimat sayısı ve tutarı
-- ---------------------------------------------------------------------------
create or replace function payment_status_distribution(p_store_id uuid)
returns jsonb
language sql stable security definer set search_path = public as $$
  with s as (
    select sh.id,
           shipment_payment_status(sh.id) as durum,
           (select coalesce(sum(si.satir_tutari), 0)
            from shipment_items si where si.shipment_id = sh.id) as tutar
    from shipments sh
    where sh.store_id = p_store_id and sh.borclandirir
      and sh.account_id in (select auth_visible_accounts())
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'durum', durum, 'adet', n, 'tutar', t) order by durum), '[]'::jsonb)
  from (select durum, count(*) n, sum(tutar) t from s group by durum) x;
$$;

-- ---------------------------------------------------------------------------
-- ÇEK RAPORU (K11) · vadesi yaklaşan ve geçen
-- ---------------------------------------------------------------------------
create or replace function cheque_report(
  p_store_id uuid, p_gun integer default 30) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', c.id, 'unvan', a.unvan, 'kesideci', c.kesideci,
           'banka', c.banka, 'cheque_no', c.cheque_no,
           'due_date', c.due_date, 'tutar', c.tutar, 'durum', c.durum,
           'tip', c.tip,
           'kalan_gun', (c.due_date - current_date))
         order by c.due_date), '[]'::jsonb)
  from cheques c
  join accounts a on a.id = c.account_id
  where c.store_id = p_store_id
    and c.account_id in (select auth_visible_accounts())
    and c.durum = 'portfoyde'
    and c.due_date <= current_date + p_gun;
$$;

-- ---------------------------------------------------------------------------
-- AÇIK KONSİNYE RAPORU (K45) · türetilmiş, defteri yok
-- ---------------------------------------------------------------------------
create or replace function consignment_report(p_store_id uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', a.id, 'unvan', a.unvan, 'kurum_ad', i.ad,
           'kalan_adet', open_consignment(a.id),
           'pazarlamaci', (select pr.ad_soyad from assignments asg
                           join profiles pr on pr.id = asg.user_id
                           where asg.account_id = a.id and asg.aktif limit 1))
         order by open_consignment(a.id) desc), '[]'::jsonb)
  from accounts a
  join institutions i on i.id = a.institution_id
  where a.store_id = p_store_id
    and a.id in (select auth_visible_accounts())
    and open_consignment(a.id) > 0;
$$;

-- ---------------------------------------------------------------------------
-- CİRO · K7 · Kurum kırılımı verir ama etiketi ALACAK DEĞİL HACİMDİR.
-- Ciro TESLİMATTAN okunur (borç doğuran olay), siparişten değil.
-- ---------------------------------------------------------------------------
create or replace function revenue_report(
  p_store_id uuid,
  p_baslangic date default null,
  p_bitis date default null,
  p_kirilim text default 'pazarlamaci'   -- pazarlamaci | kurum | cari_tipi | ay
) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_sonuc jsonb;
begin
  if p_kirilim not in ('pazarlamaci','kurum','cari_tipi','ay','yayinevi') then
    raise exception 'Geçersiz kırılım: %', p_kirilim;
  end if;

  with h as (
    select s.id, s.institution_id, s.teslim_edildi_at, s.account_id,
           a.tip as cari_tipi,
           si.product_id, si.satir_tutari,
           si.birim_maliyet * si.adet as maliyet
    from shipments s
    join shipment_items si on si.shipment_id = s.id
    join accounts a on a.id = s.account_id
    where s.store_id = p_store_id and s.borclandirir
      and s.account_id in (select auth_visible_accounts())
      and (p_baslangic is null or s.teslim_edildi_at::date >= p_baslangic)
      and (p_bitis is null or s.teslim_edildi_at::date <= p_bitis)
  )
  select jsonb_build_object(
    'hacim', coalesce(sum(h.satir_tutari), 0),
    -- K28 · maliyet damgası sayesinde kârlılık geçmişe dönük doğru
    'maliyet', coalesce(sum(h.maliyet), 0),
    'kar', coalesce(sum(h.satir_tutari) - sum(h.maliyet), 0),
    'satir', count(*),
    'kirilim', p_kirilim,
    'satirlar', coalesce((
      select jsonb_agg(jsonb_build_object('etiket', etiket, 'hacim', v,
                                          'kar', k) order by v desc)
      from (
        select case p_kirilim
                 when 'kurum' then (select i.ad from institutions i
                                    where i.id = h2.institution_id)
                 when 'cari_tipi' then h2.cari_tipi::text
                 when 'ay' then to_char(h2.teslim_edildi_at, 'YYYY-MM')
                 when 'yayinevi' then coalesce((select pub.ad from products p
                                                join publishers pub on pub.id = p.publisher_id
                                                where p.id = h2.product_id), '—')
                 else coalesce((select pr.ad_soyad from assignments asg
                                join profiles pr on pr.id = asg.user_id
                                where asg.account_id = h2.account_id and asg.aktif
                                limit 1), '— portföysüz —')
               end as etiket,
               sum(h2.satir_tutari) as v,
               sum(h2.satir_tutari) - coalesce(sum(h2.maliyet), 0) as k
        from h h2 group by 1
      ) g), '[]'::jsonb)
  ) into v_sonuc from h;

  return v_sonuc;
end $$;

-- ---------------------------------------------------------------------------
-- B1 · MAKBUZ VERİSİ
-- Fatura değildir (K26). Tahsilatın belgesidir: kim, ne zaman, ne kadar,
-- hangi teslimatlara mahsup edildi.
-- ---------------------------------------------------------------------------
create or replace function receipt_data(p_payment_id uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', p.id, 'makbuz_no', p.makbuz_no, 'tarih', p.tarih,
    'tutar', p.tutar, 'yontem', p.yontem, 'not_metni', p.not_metni,
    'created_at', p.created_at,
    'alan', pr.ad_soyad,
    'dukkan', jsonb_build_object('ad', st.ad, 'il', st.il, 'ilce', st.ilce),
    'isletme', (select t.unvan from tenants t where t.id = p.tenant_id),
    'cari', jsonb_build_object('id', a.id, 'unvan', a.unvan, 'tip', a.tip,
                               'invoice_title', a.invoice_title,
                               'tax_id', a.tax_id, 'tax_office', a.tax_office),
    'kurum', (select i.ad from institutions i where i.id = p.institution_id),
    -- Mahsup dökümü: bu tahsilat hangi teslimatları ne kadar kapattı
    'mahsuplar', coalesce((
      select jsonb_agg(jsonb_build_object(
               'shipment_id', pa.shipment_id,
               'tarih', s.teslim_edildi_at,
               'tutar', pa.tutar,
               'durum', shipment_payment_status(s.id)) order by s.teslim_edildi_at)
      from payment_allocations pa
      join shipments s on s.id = pa.shipment_id
      where pa.payment_id = p.id), '[]'::jsonb),
    'dagitilmayan', p.tutar - coalesce((
      select sum(pa.tutar) from payment_allocations pa
      where pa.payment_id = p.id), 0),
    -- Makbuz sonrası kalan bakiye
    'kalan_bakiye', calc_account_balance(p.account_id)
  )
  from payments p
  join accounts a on a.id = p.account_id
  join stores st on st.id = p.store_id
  join profiles pr on pr.id = p.alan_user_id
  where p.id = p_payment_id
    and p.account_id in (select auth_visible_accounts());
$$;

-- ---------------------------------------------------------------------------
-- K8 · DÖNEM KİLİDİ · Kapalı döneme geriye dönük işlem GİRİLEMEZ.
-- Trigger 0008'de tanımlı; burada kapatma öncesi ÖZET veriliyor ki sahip
-- neyi kilitlediğini bilsin.
-- ---------------------------------------------------------------------------
create or replace function period_close_check(p_period_id uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'ad', pe.ad, 'starts_on', pe.starts_on, 'ends_on', pe.ends_on,
    'durum', pe.status,
    'bitti_mi', pe.ends_on < current_date,
    'acik_talep', (select count(*) from requests r
                   where r.period_id = p_period_id
                     and r.durum in ('gonderildi','incelemede')),
    'acik_siparis', (select count(*) from orders o
                     where o.period_id = p_period_id
                       and o.durum not in ('teslim_edildi','kapandi','iptal','reddedildi')),
    'acik_konsinye_cari', (select count(*) from accounts a
                           where a.tenant_id = pe.tenant_id
                             and open_consignment(a.id) > 0),
    'borclu_cari', (select count(*) from accounts a
                    where a.tenant_id = pe.tenant_id and a.balance_cache > 0)
  )
  from periods pe
  where pe.id = p_period_id and pe.tenant_id in (select auth_tenant_ids());
$$;

grant execute on function aging_report(uuid, uuid) to authenticated;
grant execute on function collection_summary(uuid, date, date, uuid) to authenticated;
grant execute on function payment_status_distribution(uuid) to authenticated;
grant execute on function cheque_report(uuid, integer) to authenticated;
grant execute on function consignment_report(uuid) to authenticated;
grant execute on function revenue_report(uuid, date, date, text) to authenticated;
grant execute on function receipt_data(uuid) to authenticated;
grant execute on function period_close_check(uuid) to authenticated;
