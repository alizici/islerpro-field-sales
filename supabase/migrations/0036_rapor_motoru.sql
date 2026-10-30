-- =============================================================================
-- 0036 · Rapor motoru (K50)
--
-- "Tüm raporlar TEK BİR MOTORDAN üretilir: aynı filtre çerçevesi, aynı kırılım
--  mantığı, aynı dışa aktarma. Rapor eklemek yeni ekran değil, KATALOG KAYDI
--  YAZMAKTIR."  (docs/04-raporlama.md)
--
-- Bu yüzden katalog bir jsonb sabiti değil, gerçek bir TABLO: yeni rapor bir
-- `insert` satırıdır, kod değişikliği değil. Boyut ve ölçü ifadeleri de
-- tabloda durur — motor onları kullanıcıdan DEĞİL bu beyaz listeden okur.
--
-- Kararlar: K7 K8 K26 K28 K45 K50
-- =============================================================================

-- ---------------------------------------------------------------------------
-- OLGU GÖRÜNÜMLERİ
--
-- Her görünüm bir "olgu" tablosudur ve yetki için gereken anahtarları taşır:
-- motor `security definer` çalıştığı için RLS devre dışıdır, süzme AÇIKÇA
-- yapılır (bkz. `sync_reference` ile aynı desen).
-- ---------------------------------------------------------------------------

-- K26 · Ciro SİPARİŞTEN DEĞİL TESLİMATTAN doğar: fiilen verilen maldır.
-- K28 · Fiyat ve maliyet satıra damgalıdır; geçmiş rapor sonradan değişmez.
create or replace view report_satis as
select
  si.id                                as satir_id,
  s.store_id, s.tenant_id, s.account_id, s.institution_id, s.period_id,
  s.teslim_edildi_at                   as tarih,
  s.tip                                as sevk_tipi,
  s.borclandirir,
  si.product_id,
  si.adet,
  si.birim_fiyat,
  si.iskonto_orani,
  si.birim_maliyet,
  si.satir_tutari,
  si.satir_tutari - coalesce(si.birim_maliyet, 0) * si.adet as kar,
  a.tip                                as cari_tipi,
  a.unvan                              as cari_unvan,
  i.ad                                 as kurum_ad,
  i.kurum_tipi::text                   as kurum_tipi,
  i.kademe::text                       as kademe,
  i.il, i.ilce,
  p.ad                                 as urun_ad,
  p.katalog::text                      as katalog,
  p.kategori, p.ders, p.sinav_tipi, p.sinif,
  coalesce(pub.ad, '(yayınevi yok)')   as yayinevi,
  st.ad                                as dukkan_ad,
  asg.user_id                          as pazarlamaci_id,
  pr.ad_soyad                          as pazarlamaci_ad
from shipment_items si
join shipments s     on s.id = si.shipment_id
join accounts a      on a.id = s.account_id
join institutions i  on i.id = s.institution_id
join products p      on p.id = si.product_id
join stores st       on st.id = s.store_id
left join publishers pub on pub.id = p.publisher_id
left join assignments asg on asg.account_id = s.account_id
                         and asg.period_id = s.period_id and asg.aktif
left join profiles pr on pr.id = asg.user_id;

create or replace view report_tahsilat as
select
  pay.id                               as satir_id,
  pay.store_id, pay.tenant_id, pay.account_id, pay.institution_id, pay.period_id,
  pay.tarih::timestamptz               as tarih,
  pay.tutar,
  pay.yontem::text                     as yontem,
  a.tip                                as cari_tipi,
  a.unvan                              as cari_unvan,
  i.ad                                 as kurum_ad,
  i.kurum_tipi::text                   as kurum_tipi,
  i.kademe::text                       as kademe,
  i.il, i.ilce,
  st.ad                                as dukkan_ad,
  pay.alan_user_id                     as pazarlamaci_id,
  pr.ad_soyad                          as pazarlamaci_ad
from payments pay
join accounts a     on a.id = pay.account_id
join institutions i on i.id = pay.institution_id
join stores st      on st.id = pay.store_id
left join profiles pr on pr.id = pay.alan_user_id;

-- Cari DURUMU — anlık fotoğraf, akış değil. Bu yüzden tarih süzgeci yoktur.
-- K7 · Bu görünümün ÖLÇÜLERİ malidir; kurum kırılımı motorda engellenir.
create or replace view report_cari as
select
  a.id                                 as satir_id,
  a.store_id, a.tenant_id, a.id as account_id, a.institution_id,
  null::uuid                           as period_id,
  a.created_at                         as tarih,
  a.unvan                              as cari_unvan,
  a.tip                                as cari_tipi,
  a.durum::text                        as cari_durum,
  a.discount_tier                      as kademe_iskonto,
  a.credit_limit                       as kredi_limiti,
  a.balance_cache                      as bakiye,
  account_total_risk(a.id)             as risk,
  open_consignment(a.id)               as acik_konsinye,
  i.ad                                 as kurum_ad,
  i.kurum_tipi::text                   as kurum_tipi,
  i.kademe::text                       as kademe,
  i.il, i.ilce,
  st.ad                                as dukkan_ad,
  asg.user_id                          as pazarlamaci_id,
  pr.ad_soyad                          as pazarlamaci_ad,
  -- Borcun YAŞI, borcun DOĞDUĞU ana göre ölçülür: teslimat (K26).
  (select min(s.teslim_edildi_at) from shipments s
    where s.account_id = a.id and s.borclandirir)  as en_eski_borc
from accounts a
join institutions i on i.id = a.institution_id
join stores st      on st.id = a.store_id
left join assignments asg on asg.account_id = a.id and asg.aktif
left join profiles pr on pr.id = asg.user_id;

-- K10 · Ziyaretin ölçütü konum değil ÇIKTIDIR: talep, teslimat, tahsilat.
create or replace view report_ziyaret as
select
  v.id                                 as satir_id,
  v.store_id, v.tenant_id, v.institution_id, v.period_id,
  null::uuid                           as account_id,
  v.checked_in_at                      as tarih,
  v.sonuc,
  case when v.checked_out_at is null then null
       else extract(epoch from v.checked_out_at - v.checked_in_at) / 60 end
                                       as dakika,
  (select count(*) from requests  r where r.visit_id = v.id) as talep,
  (select count(*) from orders    o where o.visit_id = v.id) as siparis,
  (select count(*) from shipments s where s.visit_id = v.id) as teslimat,
  (select count(*) from payments  p where p.visit_id = v.id) as tahsilat_adet,
  coalesce((select sum(p.tutar) from payments p where p.visit_id = v.id), 0)
                                       as tahsilat_tutar,
  i.ad                                 as kurum_ad,
  i.kurum_tipi::text                   as kurum_tipi,
  i.kademe::text                       as kademe,
  i.il, i.ilce,
  st.ad                                as dukkan_ad,
  v.user_id                            as pazarlamaci_id,
  pr.ad_soyad                          as pazarlamaci_ad
from visits v
join institutions i on i.id = v.institution_id
join stores st      on st.id = v.store_id
left join profiles pr on pr.id = v.user_id;

-- K47 · Teslim edilmek ile UYGULANMAK ayrı sayılır; raporun varlık sebebi bu.
create or replace view report_deneme as
select
  ed.id                                as satir_id,
  ep.store_id, ep.tenant_id, ep.account_id, ep.period_id,
  a.institution_id,
  ed.planlanan_tarih::timestamptz      as tarih,
  ed.durum::text                       as teslim_durum,
  ed.adet,
  coalesce(ep.birim_fiyat, 0) * ed.adet as tutar,
  (ed.durum = 'planlandi')::int        as planlanan,
  (ed.durum in ('teslim_edildi','uygulandi'))::int as teslim_edilen,
  (ed.durum = 'uygulandi')::int        as uygulanan,
  (ed.onceki_tarih is not null)::int   as ertelenen,
  ed.ertelendi_notu,
  p.ad                                 as deneme_ad,
  coalesce(pub.ad, '(yayınevi yok)')   as yayinevi,
  a.unvan                              as cari_unvan,
  a.tip                                as cari_tipi,
  i.ad                                 as kurum_ad,
  i.kurum_tipi::text                   as kurum_tipi,
  i.kademe::text                       as kademe,
  i.il, i.ilce,
  st.ad                                as dukkan_ad,
  asg.user_id                          as pazarlamaci_id,
  pr.ad_soyad                          as pazarlamaci_ad
from exam_deliveries ed
join exam_programs ep on ep.id = ed.exam_program_id
join accounts a       on a.id = ep.account_id
join institutions i   on i.id = a.institution_id
join products p       on p.id = ed.product_id
join stores st        on st.id = ep.store_id
left join publishers pub on pub.id = p.publisher_id
left join assignments asg on asg.account_id = ep.account_id
                         and asg.period_id = ep.period_id and asg.aktif
left join profiles pr on pr.id = asg.user_id;

-- K13 · Stok bir SAYAÇTIR. K23 · Eski baskı kararı bu görünümden çıkar.
create or replace view report_stok as
select
  sp.id                                as satir_id,
  sp.store_id,
  st.tenant_id,
  null::uuid                           as account_id,
  null::uuid                           as period_id,
  p.created_at                         as tarih,
  p.id                                 as product_id,
  p.ad                                 as urun_ad,
  p.katalog::text                      as katalog,
  p.kategori, p.ders, p.sinav_tipi, p.sinif,
  p.baski_etiketi, p.baski_sirasi,
  coalesce(pub.ad, '(yayınevi yok)')   as yayinevi,
  st.ad                                as dukkan_ad,
  null::uuid                           as pazarlamaci_id,
  null::uuid                           as institution_id,
  sp.stok_adedi,
  sp.stok_takibi,
  sp.satis_fiyat,
  sp.alis_fiyat,
  sp.stok_adedi * coalesce(sp.alis_fiyat, 0) as stok_degeri,
  -- Dönem sınırı YOK: "hiç satılmadı" mutlak bir iddiadır, dönemle daralırsa
  -- yanlış olur.
  coalesce((select sum(si.adet) from shipment_items si
            join shipments s on s.id = si.shipment_id
            where si.product_id = p.id and s.store_id = sp.store_id), 0) as satilan,
  -- K23 · Aynı baskı grubunda DAHA YENİ baskı var mı?
  (p.baski_grubu_id is not null and exists (
      select 1 from products p2
      where p2.baski_grubu_id = p.baski_grubu_id
        and coalesce(p2.baski_sirasi, 0) > coalesce(p.baski_sirasi, 0)
        and not p2.arsivlendi))::int   as eski_baski,
  -- Grubun EN GÜNCEL baskısının etiketi. Raporun değeri karşılaştırmada:
  -- "elde 2024-25'ten 40 adet var, oysa 2025-26 çıkmış".
  (select p3.baski_etiketi from products p3
    where p3.baski_grubu_id = p.baski_grubu_id and not p3.arsivlendi
    order by coalesce(p3.baski_sirasi, 0) desc limit 1) as guncel_baski
from store_products sp
join products p on p.id = sp.product_id
join stores st  on st.id = sp.store_id
left join publishers pub on pub.id = p.publisher_id
where sp.aktif and not p.arsivlendi;

-- ---------------------------------------------------------------------------
-- KATALOG · boyutlar, ölçüler, raporlar
--
-- Motor SQL parçalarını buradan okur; kullanıcıdan gelen tek şey ANAHTARDIR.
-- Bu yüzden dinamik SQL güvenlidir: anahtar tabloda yoksa istek reddedilir.
-- ---------------------------------------------------------------------------
create table if not exists report_dims (
  kaynak  text not null,
  anahtar text not null,
  ad      text not null,
  ifade   text not null,
  sira    smallint not null default 0,
  primary key (kaynak, anahtar)
);

create table if not exists report_measures (
  kaynak  text not null,
  anahtar text not null,
  ad      text not null,
  ifade   text not null,
  tip     text not null default 'sayi',       -- para · sayi · oran
  -- K7 · "mali" ölçü, kurum kırılımında toplanamaz.
  mali    boolean not null default false,
  sira    smallint not null default 0,
  primary key (kaynak, anahtar)
);

create table if not exists report_defs (
  kod                text primary key,
  ad                 text not null,
  aciklama           text,
  grup               text not null,
  kaynak             text not null,
  boyutlar           text[] not null,
  varsayilan_kirilim text[] not null,
  olculer            text[] not null,
  varsayilan_sirala  text,
  -- Rapora özel sabit süzgeç: katalog satırında durur, kullanıcı değiştiremez.
  sabit_suzgec       jsonb not null default '{}',
  sira               smallint not null default 0
);

alter table report_dims     enable row level security;
alter table report_measures enable row level security;
alter table report_defs     enable row level security;
drop policy if exists rd_read on report_dims;
drop policy if exists rm_read on report_measures;
drop policy if exists rf_read on report_defs;
-- Katalog işletmeye özel değil, ürünün parçası: herkes okur, kimse yazamaz.
create policy rd_read on report_dims     for select using (true);
create policy rm_read on report_measures for select using (true);
create policy rf_read on report_defs     for select using (true);

truncate report_dims, report_measures, report_defs;

insert into report_dims (kaynak, anahtar, ad, ifade, sira) values
  -- satış
  ('report_satis','dukkan',      'Dükkan',      'dukkan_ad', 1),
  ('report_satis','pazarlamaci', 'Pazarlamacı', $q$coalesce(pazarlamaci_ad,'(atanmamış)')$q$, 2),
  ('report_satis','cari',        'Cari',        'cari_unvan', 3),
  ('report_satis','kurum',       'Kurum',       'kurum_ad', 4),
  ('report_satis','cari_tipi',   'Cari tipi',   'cari_tipi::text', 5),
  ('report_satis','kurum_tipi',  'Kurum tipi',  'kurum_tipi', 6),
  ('report_satis','kademe',      'Kademe',      $q$coalesce(kademe,'—')$q$, 7),
  ('report_satis','ilce',        'İlçe',        $q$coalesce(ilce,'—')$q$, 8),
  ('report_satis','yayinevi',    'Yayınevi',    'yayinevi', 9),
  ('report_satis','urun',        'Ürün',        'urun_ad', 10),
  ('report_satis','kategori',    'Kategori',    $q$coalesce(kategori,'—')$q$, 11),
  ('report_satis','katalog',     'Katalog',     'katalog', 12),
  ('report_satis','ay',          'Ay',          $q$to_char(tarih,'YYYY-MM')$q$, 13),
  -- tahsilat
  ('report_tahsilat','dukkan',      'Dükkan',      'dukkan_ad', 1),
  ('report_tahsilat','pazarlamaci', 'Tahsil eden', $q$coalesce(pazarlamaci_ad,'—')$q$, 2),
  ('report_tahsilat','cari',        'Cari',        'cari_unvan', 3),
  ('report_tahsilat','kurum',       'Kurum',       'kurum_ad', 4),
  ('report_tahsilat','cari_tipi',   'Cari tipi',   'cari_tipi::text', 5),
  ('report_tahsilat','yontem',      'Yöntem',      'yontem', 6),
  ('report_tahsilat','ilce',        'İlçe',        $q$coalesce(ilce,'—')$q$, 7),
  ('report_tahsilat','ay',          'Ay',          $q$to_char(tarih,'YYYY-MM')$q$, 8),
  -- cari
  ('report_cari','dukkan',      'Dükkan',      'dukkan_ad', 1),
  ('report_cari','pazarlamaci', 'Pazarlamacı', $q$coalesce(pazarlamaci_ad,'(atanmamış)')$q$, 2),
  ('report_cari','cari',        'Cari',        'cari_unvan', 3),
  ('report_cari','kurum',       'Kurum',       'kurum_ad', 4),
  ('report_cari','cari_tipi',   'Cari tipi',   'cari_tipi::text', 5),
  ('report_cari','kurum_tipi',  'Kurum tipi',  'kurum_tipi', 6),
  ('report_cari','kademe',      'Kademe',      $q$coalesce(kademe,'—')$q$, 7),
  ('report_cari','ilce',        'İlçe',        $q$coalesce(ilce,'—')$q$, 8),
  ('report_cari','durum',       'Durum',       'cari_durum', 9),
  -- ziyaret
  ('report_ziyaret','dukkan',      'Dükkan',      'dukkan_ad', 1),
  ('report_ziyaret','pazarlamaci', 'Pazarlamacı', $q$coalesce(pazarlamaci_ad,'—')$q$, 2),
  ('report_ziyaret','kurum',       'Kurum',       'kurum_ad', 3),
  ('report_ziyaret','kurum_tipi',  'Kurum tipi',  'kurum_tipi', 4),
  ('report_ziyaret','ilce',        'İlçe',        $q$coalesce(ilce,'—')$q$, 5),
  ('report_ziyaret','sonuc',       'Sonuç',       $q$coalesce(sonuc,'—')$q$, 6),
  ('report_ziyaret','ay',          'Ay',          $q$to_char(tarih,'YYYY-MM')$q$, 7),
  -- deneme
  ('report_deneme','dukkan',      'Dükkan',      'dukkan_ad', 1),
  ('report_deneme','pazarlamaci', 'Pazarlamacı', $q$coalesce(pazarlamaci_ad,'(atanmamış)')$q$, 2),
  ('report_deneme','cari',        'Cari',        'cari_unvan', 3),
  ('report_deneme','kurum',       'Kurum',       'kurum_ad', 4),
  ('report_deneme','deneme',      'Deneme',      'deneme_ad', 5),
  ('report_deneme','yayinevi',    'Yayınevi',    'yayinevi', 6),
  ('report_deneme','durum',       'Durum',       'teslim_durum', 7),
  ('report_deneme','ay',          'Ay',          $q$to_char(tarih,'YYYY-MM')$q$, 8),
  -- stok
  ('report_stok','dukkan',    'Dükkan',   'dukkan_ad', 1),
  ('report_stok','yayinevi',  'Yayınevi', 'yayinevi', 2),
  ('report_stok','urun',      'Ürün',     'urun_ad', 3),
  ('report_stok','kategori',  'Kategori', $q$coalesce(kategori,'—')$q$, 4),
  ('report_stok','katalog',   'Katalog',  'katalog', 5),
  ('report_stok','baski',     'Baskı',    $q$coalesce(baski_etiketi,'—')$q$, 6),
  ('report_stok','guncel_baski','Güncel baskı',
     $q$coalesce(guncel_baski,'—')$q$, 7);

insert into report_measures (kaynak, anahtar, ad, ifade, tip, mali, sira) values
  -- satış · K28 sayesinde geçmişe dönük DOĞRU: fiyat ve maliyet satıra damgalı.
  ('report_satis','ciro',    'Ciro',        'sum(satir_tutari)', 'para', false, 1),
  ('report_satis','adet',    'Adet',        'sum(adet)', 'sayi', false, 2),
  ('report_satis','maliyet', 'Maliyet',     'sum(coalesce(birim_maliyet,0) * adet)', 'para', false, 3),
  ('report_satis','kar',     'Kâr',         'sum(kar)', 'para', false, 4),
  ('report_satis','iskonto', 'Ort. iskonto',
     'case when sum(birim_fiyat * adet) = 0 then 0 else 1 - sum(satir_tutari) / sum(birim_fiyat * adet) end',
     'oran', false, 5),
  ('report_satis','satir',   'Satır',       'count(*)', 'sayi', false, 6),
  -- tahsilat
  ('report_tahsilat','tutar', 'Tahsilat', 'sum(tutar)', 'para', false, 1),
  ('report_tahsilat','sayi',  'Adet',     'count(*)', 'sayi', false, 2),
  -- cari · K7 · hepsi MALİ: kurum kırılımında toplanamaz.
  ('report_cari','bakiye',        'Bakiye',        'sum(bakiye)', 'para', true, 1),
  ('report_cari','risk',          'Risk',          'sum(risk)', 'para', true, 2),
  ('report_cari','kredi_limiti',  'Kredi limiti',  'sum(kredi_limiti)', 'para', true, 3),
  ('report_cari','acik_konsinye', 'Açık konsinye', 'sum(acik_konsinye)', 'para', true, 4),
  ('report_cari','sayi',          'Cari',          'count(*)', 'sayi', false, 5),
  ('report_cari','gun0_30',  '0-30 gün',
     $q$sum(case when en_eski_borc >= now() - interval '30 days' then bakiye else 0 end)$q$,
     'para', true, 6),
  ('report_cari','gun31_60', '31-60 gün',
     $q$sum(case when en_eski_borc < now() - interval '30 days' and en_eski_borc >= now() - interval '60 days' then bakiye else 0 end)$q$,
     'para', true, 7),
  ('report_cari','gun61_90', '61-90 gün',
     $q$sum(case when en_eski_borc < now() - interval '60 days' and en_eski_borc >= now() - interval '90 days' then bakiye else 0 end)$q$,
     'para', true, 8),
  ('report_cari','gun90',    '90+ gün',
     $q$sum(case when en_eski_borc < now() - interval '90 days' then bakiye else 0 end)$q$,
     'para', true, 9),
  -- ziyaret · K10'un ölçütü
  ('report_ziyaret','ziyaret',  'Ziyaret',  'count(*)', 'sayi', false, 1),
  ('report_ziyaret','talep',    'Talep',    'sum(talep)', 'sayi', false, 2),
  ('report_ziyaret','siparis',  'Sipariş',  'sum(siparis)', 'sayi', false, 3),
  ('report_ziyaret','teslimat', 'Teslimat', 'sum(teslimat)', 'sayi', false, 4),
  ('report_ziyaret','tahsilat', 'Tahsilat', 'sum(tahsilat_tutar)', 'para', false, 5),
  ('report_ziyaret','ciktisiz', 'Çıktısız',
     'count(*) filter (where talep + siparis + teslimat + tahsilat_adet = 0)',
     'sayi', false, 6),
  ('report_ziyaret','dakika',   'Ort. dakika', 'round(avg(dakika))', 'sayi', false, 7),
  -- deneme · K47
  ('report_deneme','planlanan',    'Planlanan',    'sum(planlanan)', 'sayi', false, 1),
  ('report_deneme','teslim',       'Teslim edilen','sum(teslim_edilen)', 'sayi', false, 2),
  ('report_deneme','uygulanan',    'Uygulanan',    'sum(uygulanan)', 'sayi', false, 3),
  ('report_deneme','uygulanmayan', 'Teslim edildi, uygulanmadı',
     'sum(teslim_edilen) - sum(uygulanan)', 'sayi', false, 4),
  ('report_deneme','ertelenen',    'Ertelenen',    'sum(ertelenen)', 'sayi', false, 5),
  ('report_deneme','adet',         'Deneme adedi', 'sum(adet)', 'sayi', false, 6),
  ('report_deneme','tutar',        'Tutar',        'sum(tutar)', 'para', false, 7),
  -- stok
  ('report_stok','stok',    'Stok',        'sum(stok_adedi)', 'sayi', false, 1),
  ('report_stok','deger',   'Stok değeri', 'sum(stok_degeri)', 'para', false, 2),
  ('report_stok','satilan', 'Satılan',     'sum(satilan)', 'sayi', false, 3),
  ('report_stok','kalem',   'Kalem',       'count(*)', 'sayi', false, 4),
  -- K13 · Stok takibi kapalı ürün AYRI gösterilir: onun sayacı yok, sıfır
  -- görünmesi "stok bitti" demek değil.
  ('report_stok','takipsiz','Takibi kapalı',
     'count(*) filter (where not stok_takibi)', 'sayi', false, 5);

-- ---------------------------------------------------------------------------
-- RAPOR KATALOĞU · docs/04 §2
-- Yeni rapor = buraya bir satır. Ekran yok, kod yok.
-- ---------------------------------------------------------------------------
insert into report_defs
  (kod, ad, aciklama, grup, kaynak, boyutlar, varsayilan_kirilim, olculer,
   varsayilan_sirala, sabit_suzgec, sira) values

-- § Cari ve tahsilat
('borclu_cariler','Borçlu cariler',
 'Bakiyesi olan tüm cariler. K7 · kurum düzeyinde TOPLANMAZ.',
 'cari','report_cari',
 -- `kurum` bilerek listede: K7 kilidi ancak seçilebilirse DEVREYE GİRER ve
 -- kullanıcıya sebebini söyler. Seçeneği gizlemek kuralı öğretmez.
 array['dukkan','pazarlamaci','cari','kurum','cari_tipi','kurum_tipi','kademe','ilce','durum'],
 array['cari'],
 array['bakiye','risk','kredi_limiti','acik_konsinye','sayi'],
 'bakiye','{"bakiyeli":true}',1),

('yaslandirma','Yaşlandırma',
 'Borç yaşı kovaları. Yaş, borcun DOĞDUĞU ana göre ölçülür — teslimat (K26).',
 'cari','report_cari',
 array['dukkan','pazarlamaci','cari','kurum','cari_tipi','kurum_tipi','ilce'],
 array['cari'],
 array['gun0_30','gun31_60','gun61_90','gun90','bakiye'],
 'bakiye','{"bakiyeli":true}',2),

('tahsilat_ozeti','Tahsilat özeti',
 'Dönem × yöntem × pazarlamacı.',
 'cari','report_tahsilat',
 array['dukkan','pazarlamaci','cari','kurum','cari_tipi','yontem','ilce','ay'],
 array['yontem'],
 array['tutar','sayi'],'tutar','{}',3),

('acik_konsinye','Açık konsinye',
 'Cari bazlı kalan konsinye — türetilmiş (K45), defteri yoktur.',
 'cari','report_cari',
 array['dukkan','pazarlamaci','cari','kurum','kurum_tipi','ilce'],
 array['cari'],
 array['acik_konsinye','bakiye','sayi'],
 'acik_konsinye','{"konsinyeli":true}',4),

-- § Satış ve kârlılık
('ciro','Ciro',
 'K26 · Ciro teslimattan doğar, siparişten değil.',
 'satis','report_satis',
 array['dukkan','pazarlamaci','cari','kurum','cari_tipi','kurum_tipi','kademe','ilce','yayinevi','urun','kategori','katalog','ay'],
 array['pazarlamaci'],
 array['ciro','adet','satir'],'ciro','{"borclandiran":true}',10),

('kurum_hacmi','Kurum bazlı iş hacmi',
 'Kurumdan çıkan toplam ciro. K7 · bu bir ALACAK DEĞİL, hacimdir.',
 'satis','report_satis',
 array['kurum','kurum_tipi','kademe','ilce','dukkan','pazarlamaci','ay'],
 array['kurum'],
 array['ciro','adet','satir'],'ciro','{"borclandiran":true}',11),

('urun_satisi','Ürün satışı',
 'Hangi kitap kaç adet, hangi yayınevi.',
 'satis','report_satis',
 array['urun','yayinevi','kategori','katalog','dukkan','pazarlamaci','ay'],
 array['urun'],
 array['adet','ciro','satir'],'adet','{"borclandiran":true}',12),

('karlilik','Kârlılık',
 'K28 · Maliyet satıra damgalı olduğu için geçmişe dönük doğru.',
 'satis','report_satis',
 array['yayinevi','urun','kategori','dukkan','pazarlamaci','cari','kurum','ay'],
 array['yayinevi'],
 array['ciro','maliyet','kar','adet'],'kar','{"borclandiran":true}',13),

('iskonto_analizi','İskonto analizi',
 'Ortalama iskonto: pazarlamacı × cari tipi × yayınevi.',
 'satis','report_satis',
 array['pazarlamaci','cari_tipi','yayinevi','cari','kurum','dukkan','ay'],
 array['pazarlamaci'],
 array['iskonto','ciro','adet'],'ciro','{"borclandiran":true}',14),

-- § Saha
('pazarlamaci_performansi','Pazarlamacı performansı',
 'Ciro · tahsilat · ziyaret. K35 · prim hesabı YOKTUR.',
 'saha','report_ziyaret',
 array['pazarlamaci','dukkan','ay'],
 array['pazarlamaci'],
 array['ziyaret','talep','siparis','teslimat','tahsilat'],'ziyaret','{}',20),

('ziyaret_verimliligi','Ziyaret verimliliği',
 'K10 · Ziyaretin ölçütü konum değil ÇIKTIDIR.',
 'saha','report_ziyaret',
 array['pazarlamaci','kurum','kurum_tipi','ilce','sonuc','ay','dukkan'],
 array['pazarlamaci'],
 array['ziyaret','ciktisiz','talep','teslimat','tahsilat','dakika'],'ziyaret','{}',21),

-- § Deneme
('takvim_gerceklesmesi','Takvim gerçekleşmesi',
 'K47 · Planlanan ile UYGULANAN ayrı sayılır; program yenilenir mi, buna bakılır.',
 'deneme','report_deneme',
 array['cari','kurum','deneme','yayinevi','pazarlamaci','dukkan','ay'],
 array['cari'],
 array['planlanan','teslim','uygulanan','uygulanmayan','adet'],'adet','{}',30),

('uygulanmayan_denemeler','Teslim edildi, uygulanmadı',
 'K47 · Ayrımı işe yarar kılan rapor.',
 'deneme','report_deneme',
 array['cari','kurum','deneme','pazarlamaci','ay','dukkan'],
 array['cari'],
 array['uygulanmayan','teslim','uygulanan'],'uygulanmayan','{}',31),

('ertelenen_denemeler','Ertelenen denemeler',
 'Hangi kurum, kaç kez.',
 'deneme','report_deneme',
 array['cari','kurum','deneme','pazarlamaci','ay','dukkan'],
 array['cari'],
 array['ertelenen','planlanan','adet'],'ertelenen','{"ertelenmis":true}',32),

('kurum_deneme_adedi','Kurum bazlı deneme adedi',
 'Dönem içinde kuruma giden toplam deneme.',
 'deneme','report_deneme',
 array['kurum','cari','deneme','ilce','dukkan'],
 array['kurum'],
 array['adet','teslim','uygulanan','tutar'],'adet','{}',33),

-- § Katalog ve stok
('eski_baski_stogu','Eski baskı stoğu',
 'K23 · Elde stoğu olan ve daha yeni baskısı bulunan ürünler — iskonto '
 'kararı için. "Güncel baskı" sütunu neyin çıktığını söyler.',
 'katalog','report_stok',
 array['urun','baski','guncel_baski','yayinevi','kategori','dukkan'],
 array['urun','baski','guncel_baski'],
 array['stok','deger','satilan'],'stok','{"eski_baski":true,"stoklu":true}',40),

('depo_sayaci','Depo sayacı',
 'K27 · K45 · Stok bir SAYAÇTIR, defter değildir: siparişi engellemez. '
 'K13 · Takibi kapalı üründe adet gösterilmez, sıfır görünmesi '
 '"stok bitti" demek değildir.',
 'katalog','report_stok',
 array['yayinevi','kategori','katalog','urun','dukkan'],
 array['yayinevi'],
 array['stok','deger','kalem','takipsiz'],'stok','{}',41),

('satilmayan_urunler','Hiç satılmayan ürünler',
 'Tek adet satılmamış kalemler. İddia mutlaktır — dönemle daraltılmaz.',
 'katalog','report_stok',
 array['yayinevi','kategori','katalog','urun','dukkan'],
 array['urun'],
 array['stok','deger','satilan'],'stok','{"satilmamis":true}',42);

-- ---------------------------------------------------------------------------
-- KAYNAK TANIMLARI
-- Hangi süzgeç hangi kaynakta anlamlı? "Dönem" cari fotoğrafında yok, stokta
-- da yok — desteklenmeyen süzgeci sessizce uygulamak boş liste üretirdi.
-- ---------------------------------------------------------------------------
create table if not exists report_sources (
  kaynak     text primary key,
  ad         text not null,
  suzgecler  text[] not null,
  cari_bazli boolean not null default true
);
alter table report_sources enable row level security;
drop policy if exists rs_read on report_sources;
create policy rs_read on report_sources for select using (true);

truncate report_sources;
insert into report_sources (kaynak, ad, suzgecler, cari_bazli) values
 ('report_satis','Teslimat satırları',
  array['donem','tarih','dukkan','pazarlamaci','cari','kurum','cari_tipi',
        'kurum_tipi','kademe','ilce','yayinevi','kategori','katalog'], true),
 ('report_tahsilat','Tahsilatlar',
  array['donem','tarih','dukkan','pazarlamaci','cari','kurum','cari_tipi',
        'kurum_tipi','ilce','yontem'], true),
 ('report_cari','Cari durumu',
  array['dukkan','pazarlamaci','cari','kurum','cari_tipi','kurum_tipi',
        'kademe','ilce','durum'], true),
 ('report_ziyaret','Ziyaretler',
  array['donem','tarih','dukkan','pazarlamaci','kurum','kurum_tipi','ilce'], false),
 ('report_deneme','Deneme teslimleri',
  array['donem','tarih','dukkan','pazarlamaci','cari','kurum','kurum_tipi',
        'ilce','yayinevi'], true),
 ('report_stok','Stok',
  array['dukkan','yayinevi','kategori','katalog'], false);

-- ---------------------------------------------------------------------------
-- MOTOR
--
-- Dinamik SQL yalnızca KATALOGDAN gelen parçalarla kuruluyor; kullanıcıdan
-- gelen tek şey anahtardır ve anahtar katalogda yoksa istek reddedilir.
-- Değerler `format(%L)` ile bağlanır.
-- ---------------------------------------------------------------------------
create or replace function report_run(
  p_kod       text,
  p_store_id  uuid    default null,
  p_kirilim   text[]  default null,
  p_filtreler jsonb   default '{}',
  p_sirala    text    default null,
  p_artan     boolean default false,
  p_limit     integer default 100,
  p_offset    integer default 0
) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  d          report_defs%rowtype;
  src        report_sources%rowtype;
  f          jsonb;
  kirilim    text[];
  uyarilar   text[] := '{}';
  sutunlar   jsonb  := '[]'::jsonb;
  sec        text   := '';
  grp        text   := '';
  kosul      text   := '';
  sirala     text;
  sirali     text;
  sorgu      text;
  satirlar   jsonb;
  toplam     jsonb;
  sayi       integer;
  mali_var   boolean;
  x          text;
  dim        report_dims%rowtype;
  msr        report_measures%rowtype;
  i          integer := 0;
begin
  select * into d from report_defs where kod = p_kod;
  if d.kod is null then
    raise exception 'Bilinmeyen rapor: %', coalesce(p_kod, '(boş)');
  end if;
  select * into src from report_sources where kaynak = d.kaynak;

  -- Rapora özel sabit süzgeç kullanıcınınkini EZER: "borçlu cariler" raporu
  -- borçsuzları göstermemeli, kullanıcı ne isterse istesin.
  f := coalesce(p_filtreler, '{}'::jsonb) || d.sabit_suzgec;

  -- ── Kırılım ──────────────────────────────────────────────────────────────
  kirilim := coalesce(nullif(p_kirilim, '{}'), d.varsayilan_kirilim);
  foreach x in array kirilim loop
    if not (x = any(d.boyutlar)) then
      raise exception '"%" bu raporda kırılım olarak kullanılamaz (%)', x, d.ad;
    end if;
  end loop;

  -- K7 · Kurum, öğretmenin borcunun KEFİLİ DEĞİLDİR. Kurum kırılımında mali
  -- ölçü toplanırsa yanlış kredi kararı doğar. Motor bunu ENGELLER — belgede
  -- yazmakla bırakmaz — ve carileri ayrı satırlar olarak listeler.
  select exists (
    select 1 from report_measures m
    where m.kaynak = d.kaynak and m.anahtar = any(d.olculer) and m.mali
  ) into mali_var;
  if mali_var and 'kurum' = any(kirilim) then
    kirilim := array_replace(kirilim, 'kurum', 'cari');
    kirilim := (select array_agg(distinct e order by e) from unnest(kirilim) e);
    uyarilar := uyarilar || array[
      'K7 · Kurum kırılımında bakiye/risk TOPLANMAZ: kurum, öğretmenin '
      'borcunun kefili değildir. Cariler ayrı satırlar olarak listelendi.'];
  end if;

  -- ── Seçim listesi ────────────────────────────────────────────────────────
  foreach x in array kirilim loop
    select * into dim from report_dims where kaynak = d.kaynak and anahtar = x;
    if dim.anahtar is null then
      raise exception 'Boyut tanımı yok: % (%)', x, d.kaynak;
    end if;
    i := i + 1;
    sec := sec || format('%s as %I, ', dim.ifade, x);
    grp := grp || format('%s, ', dim.ifade);
    sutunlar := sutunlar || jsonb_build_object(
      'anahtar', x, 'ad', dim.ad, 'tip', 'metin', 'kirilim', true);
  end loop;

  foreach x in array d.olculer loop
    select * into msr from report_measures where kaynak = d.kaynak and anahtar = x;
    if msr.anahtar is null then
      raise exception 'Ölçü tanımı yok: % (%)', x, d.kaynak;
    end if;
    sec := sec || format('coalesce(%s, 0) as %I, ', msr.ifade, x);
    sutunlar := sutunlar || jsonb_build_object(
      'anahtar', x, 'ad', msr.ad, 'tip', msr.tip, 'kirilim', false);
  end loop;
  sec := left(sec, length(sec) - 2);
  grp := left(grp, length(grp) - 2);

  -- ── Yetki · motor security definer, süzme AÇIK ───────────────────────────
  kosul := format('store_id in (select auth_store_ids())');
  if src.cari_bazli then
    kosul := kosul || ' and account_id in (select auth_visible_accounts())';
  end if;
  if p_store_id is not null then
    kosul := kosul || format(' and store_id = %L', p_store_id);
  end if;

  -- ── Süzgeçler · yalnızca kaynağın desteklediği anahtarlar ────────────────
  if 'donem' = any(src.suzgecler) and f ? 'donem' then
    kosul := kosul || format(' and period_id = any(%L::uuid[])',
      (select array_agg(value::text) from jsonb_array_elements_text(f->'donem')));
  end if;
  if 'tarih' = any(src.suzgecler) and f ? 'tarih_baslangic' then
    kosul := kosul || format(' and tarih >= %L::date', f->>'tarih_baslangic');
  end if;
  if 'tarih' = any(src.suzgecler) and f ? 'tarih_bitis' then
    kosul := kosul || format(' and tarih < (%L::date + 1)', f->>'tarih_bitis');
  end if;
  if 'dukkan' = any(src.suzgecler) and f ? 'dukkan' then
    kosul := kosul || format(' and store_id = %L::uuid', f->>'dukkan');
  end if;
  if 'pazarlamaci' = any(src.suzgecler) and f ? 'pazarlamaci' then
    kosul := kosul || format(' and pazarlamaci_id = %L::uuid', f->>'pazarlamaci');
  end if;
  if 'cari' = any(src.suzgecler) and f ? 'cari' then
    kosul := kosul || format(' and account_id = %L::uuid', f->>'cari');
  end if;
  if 'kurum' = any(src.suzgecler) and f ? 'kurum' then
    kosul := kosul || format(' and institution_id = %L::uuid', f->>'kurum');
  end if;
  if 'cari_tipi' = any(src.suzgecler) and f ? 'cari_tipi' then
    kosul := kosul || format(' and cari_tipi::text = %L', f->>'cari_tipi');
  end if;
  if 'kurum_tipi' = any(src.suzgecler) and f ? 'kurum_tipi' then
    kosul := kosul || format(' and kurum_tipi = %L', f->>'kurum_tipi');
  end if;
  if 'kademe' = any(src.suzgecler) and f ? 'kademe' then
    kosul := kosul || format(' and kademe = %L', f->>'kademe');
  end if;
  if 'ilce' = any(src.suzgecler) and f ? 'ilce' then
    kosul := kosul || format(' and ilce = %L', f->>'ilce');
  end if;
  if 'yayinevi' = any(src.suzgecler) and f ? 'yayinevi' then
    kosul := kosul || format(' and yayinevi = %L', f->>'yayinevi');
  end if;
  if 'kategori' = any(src.suzgecler) and f ? 'kategori' then
    kosul := kosul || format(' and kategori = %L', f->>'kategori');
  end if;
  if 'katalog' = any(src.suzgecler) and f ? 'katalog' then
    kosul := kosul || format(' and katalog = %L', f->>'katalog');
  end if;
  if 'yontem' = any(src.suzgecler) and f ? 'yontem' then
    kosul := kosul || format(' and yontem = %L', f->>'yontem');
  end if;
  if 'durum' = any(src.suzgecler) and f ? 'durum' then
    kosul := kosul || format(' and cari_durum = %L', f->>'durum');
  end if;

  -- Rapora özel bayraklar
  if (f->>'bakiyeli')::boolean then kosul := kosul || ' and bakiye <> 0'; end if;
  if (f->>'konsinyeli')::boolean then
    kosul := kosul || ' and open_consignment(account_id) > 0';
  end if;
  if (f->>'borclandiran')::boolean then
    kosul := kosul || $q$ and borclandirir and sevk_tipi <> 'numune'$q$;
  end if;
  if (f->>'ertelenmis')::boolean then kosul := kosul || ' and ertelenen = 1'; end if;
  if (f->>'eski_baski')::boolean then kosul := kosul || ' and eski_baski = 1'; end if;
  if (f->>'stoklu')::boolean then kosul := kosul || ' and stok_adedi > 0'; end if;
  if (f->>'satilmamis')::boolean then kosul := kosul || ' and satilan = 0'; end if;

  -- ── Sıralama ─────────────────────────────────────────────────────────────
  sirala := coalesce(p_sirala, d.varsayilan_sirala, kirilim[1]);
  if not (sirala = any(d.olculer) or sirala = any(kirilim)) then
    sirala := coalesce(d.varsayilan_sirala, kirilim[1]);
  end if;
  sirali := format('%I %s', sirala, case when p_artan then 'asc' else 'desc' end);

  sorgu := format(
    'select coalesce(jsonb_agg(to_jsonb(t) order by %s), ''[]''::jsonb) '
    'from (select %s from %I where %s group by %s order by %s '
    'limit %s offset %s) t',
    sirali, sec, d.kaynak, kosul, grp, sirali,
    greatest(coalesce(p_limit, 100), 1), greatest(coalesce(p_offset, 0), 0));
  execute sorgu into satirlar;

  -- Toplam AYRI hesaplanır: sayfalanmış satırların toplamı, raporun toplamı
  -- değildir. "İlk 20 borçlu" sayfasının altındaki rakam tüm borcu göstermeli.
  execute format('select to_jsonb(t) from (select %s from %I where %s) t',
    (select string_agg(format('coalesce(%s, 0) as %I', m.ifade, m.anahtar), ', '
                       order by array_position(d.olculer, m.anahtar))
     from report_measures m
     where m.kaynak = d.kaynak and m.anahtar = any(d.olculer)),
    d.kaynak, kosul) into toplam;

  execute format('select count(*) from (select 1 from %I where %s group by %s) t',
    d.kaynak, kosul, grp) into sayi;

  return jsonb_build_object(
    'kod', d.kod, 'ad', d.ad, 'aciklama', d.aciklama, 'grup', d.grup,
    'kirilim', to_jsonb(kirilim),
    'boyutlar', (select coalesce(jsonb_agg(jsonb_build_object(
                    'anahtar', dm.anahtar, 'ad', dm.ad) order by dm.sira), '[]'::jsonb)
                 from report_dims dm
                 where dm.kaynak = d.kaynak and dm.anahtar = any(d.boyutlar)),
    'suzgecler', to_jsonb(src.suzgecler),
    'sutunlar', sutunlar,
    'satirlar', coalesce(satirlar, '[]'::jsonb),
    'toplam', coalesce(toplam, '{}'::jsonb),
    'kirilim_sayisi', sayi,
    'sirala', sirala, 'artan', p_artan,
    'uyarilar', to_jsonb(uyarilar),
    'uretildi_at', now()
  );
end $$;

create or replace function report_catalog() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'kod', d.kod, 'ad', d.ad, 'aciklama', d.aciklama, 'grup', d.grup,
      'kaynak', d.kaynak,
      'boyutlar', (select coalesce(jsonb_agg(jsonb_build_object(
                      'anahtar', dm.anahtar, 'ad', dm.ad) order by dm.sira), '[]'::jsonb)
                   from report_dims dm
                   where dm.kaynak = d.kaynak and dm.anahtar = any(d.boyutlar)),
      'varsayilan_kirilim', to_jsonb(d.varsayilan_kirilim),
      'olculer', (select coalesce(jsonb_agg(jsonb_build_object(
                      'anahtar', m.anahtar, 'ad', m.ad, 'tip', m.tip,
                      'mali', m.mali) order by m.sira), '[]'::jsonb)
                  from report_measures m
                  where m.kaynak = d.kaynak and m.anahtar = any(d.olculer)),
      'suzgecler', (select to_jsonb(s.suzgecler) from report_sources s
                    where s.kaynak = d.kaynak)
    ) order by d.sira), '[]'::jsonb)
  from report_defs d;
$$;

grant execute on function report_run(text, uuid, text[], jsonb, text, boolean, integer, integer) to authenticated;
grant execute on function report_catalog() to authenticated;
grant select on report_dims, report_measures, report_defs, report_sources to authenticated;

-- ---------------------------------------------------------------------------
-- KAPALI DÖNEM ÖZETLERİ (K8 · K50 §4.2)
--
-- `kapali` dönemde veri DEĞİŞMEZ. O yüzden özet bir kez hesaplanır ve saklanır;
-- sonraki her çağrı hazır sonucu okur. Yıllar geçtikçe rapor yavaşlamaz — bu,
-- K8'in kapalı dönem kuralının doğrudan kazancı.
--
-- Önbellek KOŞULLUDUR ve koşullar dar: tek bir kapalı dönem seçili, başka
-- süzgeç yok, sayfalama varsayılan. Aksi hâlde saklanan özet sorulan soruya
-- ait olmaz — yanlış rakam, yavaş rapordan kötüdür.
-- ---------------------------------------------------------------------------
create or replace function report_cacheable(
  p_kod text, p_store_id uuid, p_filtreler jsonb,
  p_limit integer, p_offset integer)
returns uuid language plpgsql stable security definer set search_path = public as $$
declare
  d       report_defs%rowtype;
  fark    jsonb;
  donem   uuid;
begin
  select * into d from report_defs where kod = p_kod;
  if d.kod is null or p_store_id is null then return null; end if;
  if coalesce(p_offset, 0) <> 0 or coalesce(p_limit, 100) <> 100 then
    return null;
  end if;

  -- Raporun kendi sabit süzgeci sayılmaz; kullanıcının eklediği HER ŞEY sayılır.
  fark := coalesce(p_filtreler, '{}'::jsonb) - 'donem';
  if fark <> '{}'::jsonb then return null; end if;

  if jsonb_typeof(p_filtreler->'donem') <> 'array'
     or jsonb_array_length(p_filtreler->'donem') <> 1 then
    return null;
  end if;
  donem := (p_filtreler->'donem'->>0)::uuid;

  return (select pe.id from periods pe
          join stores s on s.tenant_id = pe.tenant_id
          where pe.id = donem and s.id = p_store_id and pe.status = 'kapali');
end $$;

create or replace function report_run_cached(
  p_kod       text,
  p_store_id  uuid    default null,
  p_kirilim   text[]  default null,
  p_filtreler jsonb   default '{}',
  p_sirala    text    default null,
  p_artan     boolean default false,
  p_limit     integer default 100,
  p_offset    integer default 0
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  donem   uuid;
  imza    text;
  hazir   jsonb;
  sonuc   jsonb;
  v_tenant uuid;
begin
  donem := report_cacheable(p_kod, p_store_id, p_filtreler, p_limit, p_offset);
  if donem is null then
    return report_run(p_kod, p_store_id, p_kirilim, p_filtreler, p_sirala,
                      p_artan, p_limit, p_offset);
  end if;

  -- İmza kırılımı ve sıralamayı da içerir: aynı dönemin farklı kırılımı
  -- farklı bir rapordur.
  imza := p_kod || ':' || coalesce(array_to_string(p_kirilim, ','), '-')
        || ':' || coalesce(p_sirala, '-') || ':' || p_artan::text;

  select ozet into hazir from period_summaries
  where store_id = p_store_id and period_id = donem and rapor_kodu = imza;
  if hazir is not null then
    return hazir || jsonb_build_object('kaynak_tipi', 'kapali_donem_ozeti');
  end if;

  sonuc := report_run(p_kod, p_store_id, p_kirilim, p_filtreler, p_sirala,
                      p_artan, p_limit, p_offset);
  select tenant_id into v_tenant from stores where id = p_store_id;
  insert into period_summaries (tenant_id, store_id, period_id, rapor_kodu, ozet)
  values (v_tenant, p_store_id, donem, imza, sonuc)
  on conflict (store_id, period_id, rapor_kodu) do update set
    ozet = excluded.ozet, hesaplandi_at = now();

  return sonuc || jsonb_build_object('kaynak_tipi', 'kapali_donem_ozeti');
end $$;

grant execute on function report_cacheable(text, uuid, jsonb, integer, integer) to authenticated;
grant execute on function report_run_cached(text, uuid, text[], jsonb, text, boolean, integer, integer) to authenticated;

-- ---------------------------------------------------------------------------
-- KAYDEDİLMİŞ RAPORLAR (K50 §1.3)
-- "Kullanıcı bir filtre + kırılım kombinasyonunu adlandırıp kaydeder; bir daha
--  kurmak zorunda kalmaz."
-- ---------------------------------------------------------------------------
create or replace function save_report(
  p_ad        text,
  p_kod       text,
  p_store_id  uuid,
  p_kirilim   text[]  default '{}',
  p_filtreler jsonb   default '{}',
  p_sutunlar  text[]  default '{}',
  p_paylasim  text    default 'kisisel',
  p_id        uuid    default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_tenant uuid; v_id uuid;
begin
  if coalesce(trim(p_ad), '') = '' then
    raise exception 'Rapor adı boş olamaz';
  end if;
  if p_paylasim not in ('kisisel','dukkan') then
    raise exception 'Paylaşım yalnızca kisisel veya dukkan olabilir';
  end if;
  if not exists (select 1 from report_defs where kod = p_kod) then
    raise exception 'Bilinmeyen rapor: %', p_kod;
  end if;
  if p_store_id not in (select auth_store_ids()) then
    raise exception 'Bu dükkana erişiminiz yok';
  end if;
  select tenant_id into v_tenant from stores where id = p_store_id;

  if p_id is not null then
    -- Başkasının kaydını düzenleyemezsin: paylaşılan rapor OKUNUR, sahibi
    -- olduğu kişinin elinde kalır.
    update saved_reports set
      ad = p_ad, rapor_kodu = p_kod, filtreler = p_filtreler,
      kirilim = to_jsonb(p_kirilim), sutunlar = to_jsonb(p_sutunlar),
      paylasim = p_paylasim
    where id = p_id and olusturan_user_id = auth.uid()
    returning id into v_id;
    if v_id is null then
      raise exception 'Kayıt bulunamadı veya sizin değil';
    end if;
    return v_id;
  end if;

  insert into saved_reports (tenant_id, store_id, ad, rapor_kodu, filtreler,
                             kirilim, sutunlar, paylasim, olusturan_user_id)
  values (v_tenant, p_store_id, p_ad, p_kod, p_filtreler,
          to_jsonb(p_kirilim), to_jsonb(p_sutunlar), p_paylasim, auth.uid())
  returning id into v_id;
  return v_id;
end $$;

create or replace function saved_reports_list(p_store_id uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', r.id, 'ad', r.ad, 'kod', r.rapor_kodu,
      'rapor_ad', (select d.ad from report_defs d where d.kod = r.rapor_kodu),
      'filtreler', r.filtreler, 'kirilim', r.kirilim, 'sutunlar', r.sutunlar,
      'paylasim', r.paylasim,
      'benim', r.olusturan_user_id = auth.uid(),
      'olusturan', (select p.ad_soyad from profiles p where p.id = r.olusturan_user_id),
      'created_at', r.created_at
    ) order by r.ad), '[]'::jsonb)
  from saved_reports r
  where r.store_id = p_store_id
    and r.store_id in (select auth_store_ids())
    -- Kişisel rapor yalnızca sahibinin; dükkan raporu herkesin.
    and (r.paylasim = 'dukkan' or r.olusturan_user_id = auth.uid());
$$;

create or replace function delete_saved_report(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  delete from saved_reports
  where id = p_id and olusturan_user_id = auth.uid();
  if not found then
    raise exception 'Kayıt bulunamadı veya sizin değil';
  end if;
end $$;

grant execute on function save_report(text, text, uuid, text[], jsonb, text[], text, uuid) to authenticated;
grant execute on function saved_reports_list(uuid) to authenticated;
grant execute on function delete_saved_report(uuid) to authenticated;
