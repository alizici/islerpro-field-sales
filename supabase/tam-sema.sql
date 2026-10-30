-- İşlerPro · tam şema · K1–K51
-- SQL Editor'e tek seferde yapıştırılabilir. Sıra önemlidir.


-- ══════════════════════════════════════════════════════════
-- 0001_enums.sql
-- ══════════════════════════════════════════════════════════
-- =============================================================================
-- 0001 · Uzantılar ve enum tipleri
-- Kararlar: K5 K8 K11 K13 K15 K18 K26 K34 K37 K47 K48 K49
-- =============================================================================
create extension if not exists "pgcrypto";
create extension if not exists "pg_trgm";      -- ürün/kurum adı benzerlik araması

-- Organizasyon ------------------------------------------------------------
create type app_role      as enum ('platform_admin','isletme_sahibi','dukkan_muduru',
                                   'pazarlamaci','hazirlik');
create type member_status as enum ('davet_edildi','onay_bekliyor','aktif','pasif');

-- Kurum dizini (K18) ------------------------------------------------------
create type kurum_tipi    as enum ('okul','kurs_merkezi','diger');
create type kademe_tipi   as enum ('anaokulu','ilkokul','ortaokul','lise');

-- Cari (K5) ---------------------------------------------------------------
create type account_tipi   as enum ('kurum','ogretmen','diger');
create type account_durum  as enum ('aktif','pasif','tahsilatta','kapali');

-- Dönem (K8) — üç durum; sayım aşaması yoktur (K45)
create type period_durum   as enum ('planlandi','aktif','kapali');

-- Katalog (K15) -----------------------------------------------------------
create type katalog_tipi   as enum ('kitap','deneme');

-- Talep (K37) -------------------------------------------------------------
create type request_durum      as enum ('taslak','gonderildi','incelemede',
                                        'karara_baglandi','tamamen_reddedildi','iptal');
create type request_item_durum as enum ('beklemede','onaylandi','reddedildi');

-- Sipariş (K46) -----------------------------------------------------------
create type order_tipi  as enum ('satis','konsinye','numune');
create type order_durum  as enum ('olusturuldu','onay_bekliyor','reddedildi',
                                  'hazirlaniyor','hazir','sevk_edildi',
                                  'kismi_teslim','teslim_edildi','kapandi','iptal');

-- Teslimat (K34 · C-1) ----------------------------------------------------
create type shipment_tipi   as enum ('teslimat','konsinye_satis','numune');
create type shipment_kaynak as enum ('depo','elden');

-- Tahsilat (K48) ve çek (K11) --------------------------------------------
create type odeme_yontem as enum ('nakit','havale','kart','cek','senet');
create type cek_tipi     as enum ('cek','senet');
create type cek_durum    as enum ('portfoyde','tahsilde','tahsil_edildi',
                                  'ciro_edildi','karsiliksiz','iade_edildi');

-- Deneme (K20 · K47) ------------------------------------------------------
create type deneme_turu     as enum ('takvim','turkiye_geneli','deneme_kulubu','resmi_sinav');
create type exam_prog_modu  as enum ('takvim_bagli','serbest_periyot');
create type exam_teslim_durum as enum ('planlandi','ertelendi','hazirlaniyor',
                                       'teslim_edildi','uygulandi','kapandi','iptal');

-- Toplu aktarma (K49) -----------------------------------------------------
create type import_turu  as enum ('urun','fiyat_iskonto','stok','kurum',
                                  'deneme_takvimi','acilis_bakiyesi');
create type import_durum as enum ('hazirlaniyor','onaylandi','geri_alindi','hatali');

-- ══════════════════════════════════════════════════════════
-- 0002_org.sql
-- ══════════════════════════════════════════════════════════
-- =============================================================================
-- 0002 · Kimlik, organizasyon ve dönem
-- Kararlar: K1 K3 K8 K19 K35 K44
-- =============================================================================

-- Kullanıcı: auth.users'a 1:1 profil. Telefon birincil (K3 · TR OTP).
create table profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  ad_soyad     text not null,
  telefon      text unique,
  eposta       text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

-- İşletme (tenant). Katalog, deneme takvimi ve ürün kimliği buraya aittir (K21).
create table tenants (
  id           uuid primary key default gen_random_uuid(),
  unvan        text not null,
  vergi_no     text,
  vergi_dairesi text,
  created_at   timestamptz not null default now()
);

-- Dükkan (store). Fiyat, iskonto, stok, cari ve portföy buraya aittir (K12).
create table stores (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid not null references tenants(id) on delete cascade,
  ad           text not null,
  il           text,
  ilce         text,
  adres        text,
  aktif        boolean not null default true,
  created_at   timestamptz not null default now()
);
create index on stores(tenant_id);

-- Üyelik: bir kullanıcı birden çok rolde olabilir (K19).
-- store_id NULL → tenant geneli yetki (sahip, platform admin).
create table memberships (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references profiles(id) on delete cascade,
  tenant_id    uuid not null references tenants(id) on delete cascade,
  store_id     uuid references stores(id) on delete cascade,
  role         app_role not null,
  status       member_status not null default 'aktif',
  -- Pazarlamacı pasife alınırken portföy devri zorunludur (K34 · W-2);
  -- devralan kullanıcı burada saklanır, assignments yeni satır alır.
  devralan_user_id uuid references profiles(id),
  pasife_alindi_at timestamptz,
  created_at   timestamptz not null default now(),
  unique (user_id, tenant_id, store_id, role)
);
create index on memberships(tenant_id, store_id, role) where status = 'aktif';
create index on memberships(user_id) where status = 'aktif';

-- Dönem (K8): yarıyıl. term smallint'tir, CHECK konmaz — yıl başına dönem
-- sayısı ileride değiştirilebilsin (ör. yaz dönemi eklemek yalnızca satır ekler).
create table periods (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references tenants(id) on delete cascade,
  academic_year text not null,                 -- '2026-2027'
  term          smallint not null,             -- 1, 2, (3 = yaz, ileride)
  ad            text not null,                 -- '2026-2027 / 1. Dönem'
  starts_on     date not null,
  ends_on       date not null,
  status        period_durum not null default 'planlandi',
  created_at    timestamptz not null default now(),
  unique (tenant_id, academic_year, term),
  check (ends_on > starts_on)
);
create index on periods(tenant_id, status);

-- Davet (K3): pazarlamacı öğretmeni davet eder; kod kurumu ve dükkanı taşır.
create table invites (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references tenants(id) on delete cascade,
  store_id       uuid not null references stores(id) on delete cascade,
  institution_id uuid not null,                -- FK 0003'te eklenir
  kod            text not null unique,
  telefon        text,
  gonderen_user_id uuid not null references profiles(id),
  expires_at     timestamptz not null,
  kullanildi_at  timestamptz,
  kullanan_user_id uuid references profiles(id),
  created_at     timestamptz not null default now()
);
create index on invites(tenant_id, store_id);

-- KVKK (K44): aydınlatma metni onayı ilk girişte alınır ve kaydedilir.
create table consents (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references profiles(id) on delete cascade,
  tenant_id   uuid not null references tenants(id) on delete cascade,
  metin_surum text not null,
  onaylandi_at timestamptz not null default now(),
  unique (user_id, tenant_id, metin_surum)
);

-- ══════════════════════════════════════════════════════════
-- 0003_directory.sql
-- ══════════════════════════════════════════════════════════
-- =============================================================================
-- 0003 · Kurum dizini, kişiler, yayınevleri
-- Kararlar: K4 K18 K19 K30 · A12
-- =============================================================================

-- Kurum (K18): okul VE özel kurs merkezi tek dizinde. tenant_id YOKTUR —
-- dizin ortaktır (K4). Ticari veri accounts üzerinden tenant'a bağlanır.
create table institutions (
  id            uuid primary key default gen_random_uuid(),
  kurum_tipi    kurum_tipi not null default 'okul',
  ad            text not null,
  parent_id     uuid references institutions(id),        -- kurum zinciri (K18)
  il            text,
  ilce          text,
  adres         text,
  meb_kodu      text,                                     -- A12: host'taki 63 kayıt buraya
  host          text unique,                              -- mevcut veriden gelen slug
  latitude      double precision,
  longitude     double precision,
  kademe        kademe_tipi,                              -- yalnızca kurum_tipi = okul
  tur           text,                                     -- Anadolu/Fen/İHL/dershane/etüt…
  hedef_sinavlar text[],                                  -- yalnızca kurs_merkezi
  ogrenci_sayisi integer,
  dogrulandi    boolean not null default false,           -- Platform Admin doğrular (Ö-8)
  ekleyen_tenant_id uuid references tenants(id),          -- doğrulanana dek yalnızca ona görünür
  merged_into_id uuid references institutions(id),        -- mükerrer birleştirme (Ö-8)
  created_at    timestamptz not null default now(),
  check (kademe is null or kurum_tipi = 'okul'),
  check (hedef_sinavlar is null or kurum_tipi = 'kurs_merkezi')
);
create index on institutions(il, ilce);
create index on institutions(kurum_tipi) where merged_into_id is null;
create index on institutions using gin (ad gin_trgm_ops);   -- benzerlik araması
create unique index on institutions(meb_kodu) where meb_kodu is not null;

alter table invites add constraint invites_institution_fk
  foreign key (institution_id) references institutions(id) on delete cascade;

-- Kurumdaki kişiler. tenant_id ZORUNLU (K30): kurum dizini ortaktır ama
-- kişi kayıtları, telefonlar ve notlar ortak DEĞİLDİR — rakibe sızmasın.
create table institution_contacts (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references tenants(id) on delete cascade,
  institution_id uuid not null references institutions(id) on delete cascade,
  ad_soyad       text not null,
  telefon        text,
  brans          text,
  gorev          text,                                    -- öğretmen / müdür yrd. / rehber
  user_id        uuid references profiles(id),            -- uygulama hesabı varsa
  not_metni      text,
  aktif          boolean not null default true,
  created_at     timestamptz not null default now()
);
create index on institution_contacts(tenant_id, institution_id);
create index on institution_contacts(user_id) where user_id is not null;

-- Kurum ↔ dükkan ticari ilişkisi. accounts.store_id'den TÜRETİLMEZ (H-7):
-- link "bu dükkan bu kurumla çalışıyor" der; cari "burada hesap var" der.
create table institution_store_links (
  id             uuid primary key default gen_random_uuid(),
  institution_id uuid not null references institutions(id) on delete cascade,
  store_id       uuid not null references stores(id) on delete cascade,
  aktif          boolean not null default true,
  created_at     timestamptz not null default now(),
  unique (institution_id, store_id)
);

-- Kurum üyeliği (K19): bir kişi birden çok kurumda çalışabilir.
create table institution_memberships (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references profiles(id) on delete cascade,
  institution_id uuid not null references institutions(id) on delete cascade,
  brans          text,
  gorev          text,
  -- Kurum adına talep açma yetkisi. Kim verdi/ne zaman audit_logs'a yazılır (Y-15).
  can_order_for_institution boolean not null default false,
  status         member_status not null default 'onay_bekliyor',
  created_at     timestamptz not null default now(),
  unique (user_id, institution_id)
);
create index on institution_memberships(institution_id) where status = 'aktif';

-- Yayınevi: ortak dizin, kitap ve deneme kataloğu paylaşır (K21).
create table publishers (
  id         uuid primary key default gen_random_uuid(),
  ad         text not null,
  normalize_ad text not null,                   -- 'BESKURUMSAL' — birleştirme adayı bulmak için
  created_at timestamptz not null default now()
);
create unique index on publishers(normalize_ad);

-- ══════════════════════════════════════════════════════════
-- 0004_accounts.sql
-- ══════════════════════════════════════════════════════════
-- =============================================================================
-- 0004 · Cari (accounts) — modelin merkezi soyutlaması
-- Kararlar: K5 K6 K7 K19 K22 K25 K29 · V2
-- =============================================================================

-- Talep, sipariş, teslimat, tahsilat, iade, konsinye ve deneme programı —
-- hepsi institution_id'ye DEĞİL account_id'ye bağlanır (K5).
create table accounts (
  id                 uuid primary key default gen_random_uuid(),
  tenant_id          uuid not null references tenants(id) on delete cascade,
  store_id           uuid not null references stores(id) on delete cascade,
  tip                account_tipi not null,
  -- Her iki tipte de dolu. BAĞLAM bağıdır (navigasyon, ziyaret, cari taşıma);
  -- mali toplama için DEĞİLDİR (K7).
  institution_id     uuid not null references institutions(id),
  -- Öğretmen carisinde dolu. Uygulama hesabı OLMASA DA cari açılabilir (K5).
  institution_contact_id uuid references institution_contacts(id),
  user_id            uuid references profiles(id),
  unvan              text not null,
  -- Fatura kimliği (V2). TCKN zorunlu DEĞİLDİR — yalnızca şahıs belgesi
  -- kesilecekse istenir; kişi eşleştirmesi user_id üzerinden yapılır (Y-14).
  invoice_title      text,
  tax_id             text,
  tax_office         text,
  discount_tier      text,                       -- K25 çözümleme sırasında ikinci basamak
  credit_limit       numeric(12,2) not null default 0,
  -- Türetilmiş değer (K29). Yazan tek yer bir DB fonksiyonudur; uygulama kodu
  -- bu alana ASLA doğrudan yazmaz.
  balance_cache      numeric(12,2) not null default 0,
  durum              account_durum not null default 'aktif',
  created_at         timestamptz not null default now(),
  check (tip <> 'ogretmen' or (institution_contact_id is not null or user_id is not null))
);
create index on accounts(tenant_id, store_id) where durum = 'aktif';
create index on accounts(institution_id);
create index on accounts(user_id) where user_id is not null;
-- Aynı kişinin farklı kurumlardaki carilerini bulmak için (K19 risk uyarısı)
create index on accounts(tenant_id, user_id) where user_id is not null;

-- Cari taşıma günlüğü (K6). Hiçbir hareket silinmez.
create table account_transfers (
  id                    uuid primary key default gen_random_uuid(),
  account_id            uuid not null references accounts(id) on delete cascade,
  from_institution_id   uuid not null references institutions(id),
  to_institution_id     uuid not null references institutions(id),
  gerekce               text,
  yapan_user_id         uuid not null references profiles(id),
  created_at            timestamptz not null default now()
);
create index on account_transfers(account_id);

-- Sınıf mevcutları (K22). KURUM değil CARİ bazlı: kurumsal cari → okulun
-- sınıf mevcutları; öğretmen carisi → o öğretmenin kendi şube mevcutları.
create table account_enrollments (
  id          uuid primary key default gen_random_uuid(),
  account_id  uuid not null references accounts(id) on delete cascade,
  period_id   uuid not null references periods(id) on delete cascade,
  sinif       smallint not null,
  ogrenci_sayisi integer not null,
  bildiren_user_id uuid references profiles(id),
  created_at  timestamptz not null default now(),
  unique (account_id, period_id, sinif)
);

-- Portföy (K5): pazarlamacı ↔ CARİ, dönem bazlı. Geçmiş dönemler korunur.
create table assignments (
  id          uuid primary key default gen_random_uuid(),
  account_id  uuid not null references accounts(id) on delete cascade,
  store_id    uuid not null references stores(id) on delete cascade,
  user_id     uuid not null references profiles(id),      -- pazarlamacı
  period_id   uuid not null references periods(id),
  aktif       boolean not null default true,
  created_at  timestamptz not null default now(),
  unique (account_id, period_id, user_id)
);
create index on assignments(user_id, period_id) where aktif;
create index on assignments(account_id) where aktif;

-- ══════════════════════════════════════════════════════════
-- 0005_catalog.sql
-- ══════════════════════════════════════════════════════════
-- =============================================================================
-- 0005 · Katalog: ürünler, baskılar, dükkan fiyat katmanı, iskonto
-- Kararlar: K9 K12 K13 K14 K15 K16 K20 K21 K23 K24 K25 K27 K31 · V6
-- =============================================================================

-- İki katalog, tek tablo (K15): katalog = kitap | deneme.
-- tenant_id NULL → ortak katalog; dolu → İŞLETMEYE özel (K9 · Y-11).
-- KDV alanı YOKTUR (K31) — fiyat tek sayıdır.
create table products (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references tenants(id) on delete cascade,
  katalog       katalog_tipi not null default 'kitap',
  ad            text not null,
  publisher_id  uuid references publishers(id),
  barkod        text,                              -- ISBN. Benzersiz (K24)
  urun_kod      text,                              -- benzersiz DEĞİL (70 mükerrer) — anahtar olarak kullanılmaz
  kategori      text,                              -- mevcut urun_tipi olduğu gibi taşınır (K16)
  sinif         smallint[],                        -- 1-12, 13 = mezun
  ders          text,
  sinav_tipi    text,                              -- TYT/AYT/YDT/YKS/LGS/KPSS/DGS/ALES
  etiket_fiyat  numeric(12,2),                     -- yayınevi listesi — REFERANS, hesaba girmez (K25)
  -- Baskı (K23): üçü de ELLE doldurulur, addan/tarihten türetilmez.
  baski_etiketi text,                              -- '2025-26', '3. Baskı'
  baski_sirasi  smallint,
  baski_grubu_id uuid,                             -- aynı eserin baskıları
  merged_into_id uuid references products(id),     -- mükerrer birleştirme (K9)
  arsivlendi    boolean not null default false,    -- K14
  created_at    timestamptz not null default now()
);
create unique index on products(barkod) where barkod is not null;   -- K24
create index on products(tenant_id, katalog) where not arsivlendi and merged_into_id is null;
create index on products(publisher_id);
create index on products(baski_grubu_id) where baski_grubu_id is not null;
create index on products using gin (ad gin_trgm_ops);

-- Deneme'ye özel alanlar (K15 · K20). 1:1 yan tablo — 24.632 kitap satırında
-- NULL sütun taşımamak için.
create table deneme_details (
  product_id         uuid primary key references products(id) on delete cascade,
  period_id          uuid references periods(id),
  deneme_turu        deneme_turu not null,
  kademe             text,                          -- ortaokul | lise (hangi takvimden geldi)
  duzey              text,                          -- '5-6-7-8. SINIF', 'TYT-AYT'
  kapsam             text,                          -- genel | tarama | konu_bazli
  stok_tarihi        date not null,                 -- takvimin omurgası (267/267 dolu)
  uygulama_baslangic date,
  uygulama_bitis     date,
  uygulama_metin     text                           -- ham metin: '29 Eylül-3 Ekim 2025'
);
create index on deneme_details(stok_tarihi);
create index on deneme_details(period_id, deneme_turu);

-- Set içeriği
create table bundle_items (
  id          uuid primary key default gen_random_uuid(),
  parent_id   uuid not null references products(id) on delete cascade,
  child_id    uuid not null references products(id),
  adet        integer not null default 1,
  unique (parent_id, child_id)
);

-- DÜKKANA özel ticari katman (K12). Ürün kimliği paylaşılır, ticari koşullar
-- paylaşılmaz. stok_adedi SAYAÇTIR, defter değildir (K27 · C-2).
create table store_products (
  id                  uuid primary key default gen_random_uuid(),
  store_id            uuid not null references stores(id) on delete cascade,
  product_id          uuid not null references products(id) on delete cascade,
  alis_fiyat          numeric(12,2),
  satis_fiyat         numeric(12,2),              -- iskonto TABANI (K25)
  varsayilan_iskonto  numeric(5,4) not null default 0,   -- 0.2000 = %20
  stok_adedi          integer not null default 0,
  stok_takibi         boolean not null default true,     -- K13: false → adet gösterilmez
  aktif               boolean not null default true,
  created_at          timestamptz not null default now(),
  unique (store_id, product_id)
);
create index on store_products(store_id) where aktif;

-- İskonto kuralları (K25). Çözümleme sırası:
--   discount_rules → accounts.discount_tier ezer → pazarlamacı elle → tavan kontrolü
--   store_products.varsayilan_iskonto yalnızca kural yoksa devreye girer.
create table discount_rules (
  id            uuid primary key default gen_random_uuid(),
  store_id      uuid not null references stores(id) on delete cascade,
  account_tip   account_tipi,                     -- NULL = hepsi
  publisher_id  uuid references publishers(id),   -- NULL = hepsi
  product_id    uuid references products(id),     -- NULL = hepsi
  min_adet      integer not null default 1,
  iskonto_orani numeric(5,4) not null,
  oncelik       smallint not null default 100,    -- küçük olan önce
  created_at    timestamptz not null default now()
);
create index on discount_rules(store_id, account_tip, min_adet);

-- Pazarlamacı iskonto tavanı (K25). Aşılırsa sipariş onaya düşer.
create table discount_caps (
  id        uuid primary key default gen_random_uuid(),
  store_id  uuid not null references stores(id) on delete cascade,
  user_id   uuid references profiles(id),         -- NULL = dükkan geneli
  tavan     numeric(5,4) not null,
  unique (store_id, user_id)
);

-- ══════════════════════════════════════════════════════════
-- 0006_commerce.sql
-- ══════════════════════════════════════════════════════════
-- =============================================================================
-- 0006 · Saha, talep, sipariş, teslimat, iade, tahsilat, çek
-- Kararlar: K6 K10 K11 K26 K28 K32 K33 K34 K36 K37 K38 K43 K45 K46 K48 · V6 V8
-- =============================================================================

-- ZİYARET (K10): konum, imza ve fotoğraf sütunu YOKTUR — veri minimizasyonu.
create table visits (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references tenants(id) on delete cascade,
  store_id       uuid not null references stores(id) on delete cascade,
  institution_id uuid not null references institutions(id),
  user_id        uuid not null references profiles(id),
  period_id      uuid not null references periods(id),
  checked_in_at  timestamptz not null,
  checked_out_at timestamptz,
  gorusulen_contact_id uuid references institution_contacts(id),
  not_metni      text,
  sonuc          text,
  created_at     timestamptz not null default now()
);
create index on visits(user_id, checked_in_at desc);
create index on visits(institution_id, checked_in_at desc);

-- ---------------------------------------------------------------------------
-- TALEP (K36 · K37)
-- ---------------------------------------------------------------------------
create table requests (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references tenants(id) on delete cascade,
  store_id       uuid not null references stores(id) on delete cascade,
  account_id     uuid not null references accounts(id),
  institution_id uuid not null references institutions(id),   -- SNAPSHOT (K6)
  period_id      uuid not null references periods(id),        -- DAMGA (K8)
  visit_id       uuid references visits(id),                  -- Y-18
  kaynak         text not null,                               -- 'ogretmen' | 'pazarlamaci'
  acan_user_id   uuid not null references profiles(id),
  durum          request_durum not null default 'taslak',
  istenen_tarih  date,
  not_metni      text,
  sla_bildirildi boolean not null default false,              -- V7: 24 saat
  client_key     text,                                        -- idempotency (K43)
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create unique index on requests(tenant_id, client_key) where client_key is not null;
create index on requests(account_id, created_at desc);
create index on requests(store_id, durum) where durum in ('gonderildi','incelemede');

-- Kalem bazında durum (K37). product_id ZORUNLU — serbest metin yok (K36).
create table request_items (
  id         uuid primary key default gen_random_uuid(),
  request_id uuid not null references requests(id) on delete cascade,
  product_id uuid not null references products(id),
  adet       integer not null check (adet > 0),
  durum      request_item_durum not null default 'beklemede',
  red_nedeni text
);
create index on request_items(request_id);

-- ---------------------------------------------------------------------------
-- SİPARİŞ (K46)
-- ---------------------------------------------------------------------------
create table orders (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references tenants(id) on delete cascade,
  store_id       uuid not null references stores(id) on delete cascade,
  account_id     uuid not null references accounts(id),
  institution_id uuid not null references institutions(id),   -- SNAPSHOT (K6)
  period_id      uuid not null references periods(id),        -- DAMGA (K8)
  request_id     uuid references requests(id),
  visit_id       uuid references visits(id),
  tip            order_tipi not null default 'satis',
  durum          order_durum not null default 'olusturuldu',
  olusturan_user_id uuid not null references profiles(id),
  -- Hazırlık akışı (K46): kim hazırladı, ne zaman
  hazirlayan_user_id  uuid references profiles(id),
  hazirlik_basladi_at timestamptz,
  hazirlik_bitti_at   timestamptz,
  onay_gerekce   text,                                        -- iskonto tavanı / limit aşımı
  client_key     text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create unique index on orders(tenant_id, client_key) where client_key is not null;
create index on orders(store_id, durum);
create index on orders(account_id, created_at desc);

-- Fiyat VE maliyet damgalı (K28). store_products sonradan değişse geçmiş oynamaz.
-- KDV oranı yoktur (K31). Tutarlar numeric(12,2), ara sonuç yuvarlanmaz (V8).
create table order_items (
  id            uuid primary key default gen_random_uuid(),
  order_id      uuid not null references orders(id) on delete cascade,
  product_id    uuid not null references products(id),
  adet          integer not null check (adet > 0),
  birim_fiyat   numeric(12,2) not null,          -- damga
  iskonto_orani numeric(5,4)  not null default 0,-- damga
  birim_maliyet numeric(12,2),                   -- damga (W-9) — kârlılık için
  satir_tutari  numeric(12,2) not null           -- birim_fiyat*(1-iskonto)*adet, V6
);
create index on order_items(order_id);
create index on order_items(product_id);

-- ---------------------------------------------------------------------------
-- TESLİMAT (K26 · K32 · K33 · K34 · C-1)
-- ---------------------------------------------------------------------------
create table shipments (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references tenants(id) on delete cascade,
  store_id       uuid not null references stores(id) on delete cascade,
  account_id     uuid not null references accounts(id),
  institution_id uuid not null references institutions(id),   -- SNAPSHOT (K6)
  period_id      uuid not null references periods(id),        -- DAMGA (K8)
  order_id       uuid references orders(id),
  visit_id       uuid references visits(id),
  exam_delivery_id uuid,                                      -- FK 0007'de (C-3)
  -- tip ve borclandirir BAĞIMSIZ iki alandır (C-1):
  --   fiziksel hareket raporları → tip = 'teslimat'
  --   bakiye hesabı              → borclandirir
  tip            shipment_tipi not null default 'teslimat',
  borclandirir   boolean not null default true,
  kaynak         shipment_kaynak not null default 'depo',     -- K34: bilgi alanı
  teslim_alan_ad text,                                        -- K32: imza/foto YOK
  teslim_edildi_at timestamptz not null,
  belge_no       text,                                        -- K33: opsiyonel referans
  client_key     text,
  created_at_local  timestamptz,                              -- K43: cihaz saati
  created_at     timestamptz not null default now()           -- K43: sunucu saati (raporlar bunu kullanır)
);
create unique index on shipments(tenant_id, client_key) where client_key is not null;
create index on shipments(account_id, teslim_edildi_at desc);
create index on shipments(store_id, tip, teslim_edildi_at desc);

create table shipment_items (
  id            uuid primary key default gen_random_uuid(),
  shipment_id   uuid not null references shipments(id) on delete cascade,
  order_item_id uuid references order_items(id),
  product_id    uuid not null references products(id),
  adet          integer not null check (adet > 0),
  birim_fiyat   numeric(12,2) not null,          -- order_items'tan kopyalanır
  iskonto_orani numeric(5,4)  not null default 0,
  birim_maliyet numeric(12,2),
  satir_tutari  numeric(12,2) not null
);
create index on shipment_items(shipment_id);
create index on shipment_items(product_id);
create index on shipment_items(order_item_id);   -- backorder türetimi (H-3)

-- İADE. Borçlandıran teslimatın iadesi bakiyeyi azaltır; konsinye teslimatı
-- zaten borçlandırmadığı için iadesi bakiyeye dokunmaz (Y-12).
create table returns (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references tenants(id) on delete cascade,
  store_id       uuid not null references stores(id) on delete cascade,
  account_id     uuid not null references accounts(id),
  institution_id uuid not null references institutions(id),   -- SNAPSHOT (K6)
  period_id      uuid not null references periods(id),
  shipment_id    uuid references shipments(id),
  bakiyeyi_azaltir boolean not null default true,
  gerekce        text,
  alan_user_id   uuid not null references profiles(id),
  client_key     text,
  created_at     timestamptz not null default now()
);
create unique index on returns(tenant_id, client_key) where client_key is not null;
create index on returns(account_id, created_at desc);

create table return_items (
  id           uuid primary key default gen_random_uuid(),
  return_id    uuid not null references returns(id) on delete cascade,
  product_id   uuid not null references products(id),
  adet         integer not null check (adet > 0),
  birim_fiyat  numeric(12,2) not null,           -- damgalı fiyattan (güncel fiyattan değil)
  satir_tutari numeric(12,2) not null
);
create index on return_items(return_id);

-- ---------------------------------------------------------------------------
-- TAHSİLAT (K48) — taksit planı YOKTUR, parça parça ödeme kayıtla çözülür
-- ---------------------------------------------------------------------------
create table payments (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid not null references tenants(id) on delete cascade,
  store_id     uuid not null references stores(id) on delete cascade,
  account_id   uuid not null references accounts(id),
  institution_id uuid not null references institutions(id),   -- SNAPSHOT (K6)
  period_id    uuid not null references periods(id),
  visit_id     uuid references visits(id),
  tarih        date not null default current_date,
  tutar        numeric(12,2) not null check (tutar > 0),
  yontem       odeme_yontem not null,
  makbuz_no    text,
  alan_user_id uuid not null references profiles(id),
  not_metni    text,
  client_key   text,
  created_at   timestamptz not null default now()
);
create unique index on payments(tenant_id, client_key) where client_key is not null;
create index on payments(account_id, tarih desc);

-- Mahsup (K48): FIFO ile otomatik, elle değiştirilebilir.
-- shipment_id NULL → serbest tahsilat / avans.
create table payment_allocations (
  id          uuid primary key default gen_random_uuid(),
  payment_id  uuid not null references payments(id) on delete cascade,
  shipment_id uuid references shipments(id),
  tutar       numeric(12,2) not null check (tutar > 0)
);
create index on payment_allocations(payment_id);
create index on payment_allocations(shipment_id);

-- ÇEK / SENET (K11): ödeme değil ödeme VAADİDİR.
-- Bakiye tahsil edildiğinde düşer, çek alındığında değil.
create table cheques (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid not null references tenants(id) on delete cascade,
  store_id     uuid not null references stores(id) on delete cascade,
  account_id   uuid not null references accounts(id),
  payment_id   uuid references payments(id),
  period_id    uuid not null references periods(id),
  tip          cek_tipi not null default 'cek',
  kesideci     text,
  banka        text,
  sube         text,
  cheque_no    text,
  due_date     date not null,
  tutar        numeric(12,2) not null check (tutar > 0),
  durum        cek_durum not null default 'portfoyde',
  endorsed_to  text,
  created_at   timestamptz not null default now()
);
create index on cheques(store_id, durum, due_date);
create index on cheques(account_id);

-- Numune limiti (K38): pazarlamacı başına dönemsel
create table sample_limits (
  id         uuid primary key default gen_random_uuid(),
  store_id   uuid not null references stores(id) on delete cascade,
  user_id    uuid references profiles(id),        -- NULL = dükkan geneli
  period_id  uuid not null references periods(id),
  limit_adet integer,
  limit_tutar numeric(12,2),
  unique (store_id, user_id, period_id)
);

-- ══════════════════════════════════════════════════════════
-- 0007_exams_system.sql
-- ══════════════════════════════════════════════════════════
-- =============================================================================
-- 0007 · Deneme programları, sistem tabloları, toplu aktarma, raporlar
-- Kararlar: K20 K41 K43 K47 K49 K50 · C-3 · Y-8 · Ö-9
-- =============================================================================

-- Deneme programı (Y-8): iki modlu.
--   takvim_bagli    → kalemler import edilmiş takvimden, tarihler oradan
--   serbest_periyot → kendi periyodundan üretir
-- Türkiye Geneli denemeleri YALNIZCA takvim_bagli modda olabilir (K20).
create table exam_programs (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references tenants(id) on delete cascade,
  store_id       uuid not null references stores(id) on delete cascade,
  account_id     uuid not null references accounts(id),
  period_id      uuid not null references periods(id),
  modu           exam_prog_modu not null default 'takvim_bagli',
  ogrenci_sayisi integer,
  deneme_adedi   integer,
  periyot_gun    integer,                        -- serbest_periyot modunda
  birim_fiyat    numeric(12,2),
  aktif          boolean not null default true,
  created_at     timestamptz not null default now()
);
create index on exam_programs(account_id, period_id);

-- Teslim planı (C-3): YALNIZCA PLANDIR. Gerçekleştiğinde bir shipment üretir
-- ve shipments.exam_delivery_id ile ona bağlanır. Borç yalnızca shipments'tan
-- doğar — K26 tek kural olarak kalır.
create table exam_deliveries (
  id               uuid primary key default gen_random_uuid(),
  exam_program_id  uuid not null references exam_programs(id) on delete cascade,
  product_id       uuid not null references products(id),      -- katalog = deneme
  planlanan_tarih  date not null,
  adet             integer not null check (adet > 0),
  durum            exam_teslim_durum not null default 'planlandi',   -- K47
  ertelendi_notu   text,
  onceki_tarih     date,                                        -- erteleme geçmişi
  uygulandi_at     timestamptz,                                 -- K47: sınav yapıldı
  isaretleyen_user_id uuid references profiles(id),
  created_at       timestamptz not null default now()
);
create index on exam_deliveries(exam_program_id);
create index on exam_deliveries(planlanan_tarih, durum);

alter table shipments add constraint shipments_exam_delivery_fk
  foreign key (exam_delivery_id) references exam_deliveries(id);

-- ---------------------------------------------------------------------------
-- SİSTEM
-- ---------------------------------------------------------------------------
create table notifications (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references tenants(id) on delete cascade,
  user_id     uuid not null references profiles(id) on delete cascade,
  olay        text not null,                     -- K41 matrisindeki olay kodu
  baslik      text not null,
  govde       text,
  hedef_tur   text,                              -- deep link: 'request' | 'order' | …
  hedef_id    uuid,
  okundu_at   timestamptz,
  created_at  timestamptz not null default now()
);
create index on notifications(user_id, created_at desc) where okundu_at is null;

create table audit_logs (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references tenants(id) on delete cascade,
  user_id     uuid references profiles(id),
  eylem       text not null,
  tablo       text,
  kayit_id    uuid,
  detay       jsonb,
  created_at  timestamptz not null default now()
);
create index on audit_logs(tenant_id, created_at desc);
create index on audit_logs(tablo, kayit_id);

create table settings (
  tenant_id   uuid not null references tenants(id) on delete cascade,
  store_id    uuid references stores(id) on delete cascade,
  anahtar     text not null,
  deger       jsonb not null,
  primary key (tenant_id, store_id, anahtar)
);

-- ---------------------------------------------------------------------------
-- TOPLU AKTARMA (K49) — göç de bu yolla yapılır, ayrı script yazılmaz
-- ---------------------------------------------------------------------------
create table import_batches (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references tenants(id) on delete cascade,
  store_id       uuid references stores(id) on delete cascade,
  tur            import_turu not null,
  dosya_adi      text,
  satir_sayisi   integer not null default 0,
  eklenen        integer not null default 0,
  guncellenen    integer not null default 0,
  hatali         integer not null default 0,
  durum          import_durum not null default 'hazirlaniyor',
  yapan_user_id  uuid not null references profiles(id),
  geri_alindi_at timestamptz,
  created_at     timestamptz not null default now()
);
create index on import_batches(tenant_id, created_at desc);

-- Geri alma için: batch'in dokunduğu her kaydın önceki hâli
create table import_batch_rows (
  id          uuid primary key default gen_random_uuid(),
  batch_id    uuid not null references import_batches(id) on delete cascade,
  satir_no    integer not null,
  tablo       text not null,
  kayit_id    uuid,
  islem       text not null,                     -- 'insert' | 'update'
  onceki_deger jsonb,                            -- update ise eski hâli
  hata        text
);
create index on import_batch_rows(batch_id);

create table import_templates (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references tenants(id) on delete cascade,
  tur         import_turu not null,
  ad          text not null,
  eslesme     jsonb not null,                    -- {"Barkod":"barkod","Ürün Adı":"ad",…}
  created_at  timestamptz not null default now(),
  unique (tenant_id, tur, ad)
);

-- ---------------------------------------------------------------------------
-- RAPORLAMA (K50)
-- ---------------------------------------------------------------------------
create table saved_reports (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references tenants(id) on delete cascade,
  store_id    uuid references stores(id) on delete cascade,
  ad          text not null,
  rapor_kodu  text not null,                     -- katalogdaki rapor kimliği
  filtreler   jsonb not null default '{}',
  kirilim     jsonb not null default '[]',
  sutunlar    jsonb not null default '[]',
  paylasim    text not null default 'kisisel',   -- 'kisisel' | 'dukkan'
  olusturan_user_id uuid not null references profiles(id),
  created_at  timestamptz not null default now()
);
create index on saved_reports(tenant_id, rapor_kodu);

-- Kapalı dönem özetleri (K50 · K8): bir kez hesaplanır, kalıcı saklanır.
create table period_summaries (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references tenants(id) on delete cascade,
  store_id    uuid not null references stores(id) on delete cascade,
  period_id   uuid not null references periods(id) on delete cascade,
  rapor_kodu  text not null,
  ozet        jsonb not null,
  hesaplandi_at timestamptz not null default now(),
  unique (store_id, period_id, rapor_kodu)
);

-- ══════════════════════════════════════════════════════════
-- 0008_functions.sql
-- ══════════════════════════════════════════════════════════
-- =============================================================================
-- 0008 · Türetme fonksiyonları ve tetikleyiciler
-- Kararlar: K8 K11 K25 K29 K45 K48 · V6 V8
-- =============================================================================

-- ---------------------------------------------------------------------------
-- K29 · BAKİYE TÜRETİLMİŞTİR, YAZILMAZ
-- Yazan tek yer burasıdır; uygulama kodu balance_cache'e asla dokunmaz.
-- ---------------------------------------------------------------------------
create or replace function calc_account_balance(p_account uuid)
returns numeric language sql stable as $$
  select coalesce((
      select sum(si.satir_tutari)
      from shipments s join shipment_items si on si.shipment_id = s.id
      where s.account_id = p_account and s.borclandirir
  ),0)
  - coalesce((
      select sum(pa.tutar)
      from payment_allocations pa join payments p on p.id = pa.payment_id
      where p.account_id = p_account
  ),0)
  - coalesce((
      select sum(ri.satir_tutari)
      from returns r join return_items ri on ri.return_id = r.id
      where r.account_id = p_account and r.bakiyeyi_azaltir
  ),0);
$$;

create or replace function refresh_account_balance(p_account uuid)
returns void language sql as $$
  update accounts set balance_cache = calc_account_balance(p_account)
  where id = p_account;
$$;

create or replace function trg_refresh_balance() returns trigger
language plpgsql as $$
declare v_account uuid;
begin
  v_account := coalesce(
    (case tg_table_name
       when 'shipment_items'      then (select account_id from shipments where id = coalesce(new.shipment_id, old.shipment_id))
       when 'payment_allocations' then (select account_id from payments  where id = coalesce(new.payment_id,  old.payment_id))
       when 'return_items'        then (select account_id from returns   where id = coalesce(new.return_id,   old.return_id))
     end));
  if v_account is not null then perform refresh_account_balance(v_account); end if;
  return null;
end $$;

create trigger t_bal_ship  after insert or update or delete on shipment_items
  for each row execute function trg_refresh_balance();
create trigger t_bal_pay   after insert or update or delete on payment_allocations
  for each row execute function trg_refresh_balance();
create trigger t_bal_ret   after insert or update or delete on return_items
  for each row execute function trg_refresh_balance();

-- ---------------------------------------------------------------------------
-- K11 · TOPLAM RİSK = bakiye + portföydeki vadesi gelmemiş çek
-- Limit kontrolü BUNA bakar. Konsinye GİRMEZ (Y-13) — mülkiyet hâlâ dükkanda.
-- ---------------------------------------------------------------------------
create or replace function account_total_risk(p_account uuid)
returns numeric language sql stable as $$
  select (select balance_cache from accounts where id = p_account)
       + coalesce((select sum(tutar) from cheques
                   where account_id = p_account and durum in ('portfoyde','tahsilde')),0);
$$;

-- K45 · Kalan konsinye TÜRETİLİR — defteri yoktur.
--   bırakılan (tip=teslimat, borclandirir=false) − satılan (tip=konsinye_satis) − iade
create or replace function open_consignment(p_account uuid, p_product uuid default null)
returns numeric language sql stable as $$
  select coalesce((
      select sum(si.adet) from shipments s join shipment_items si on si.shipment_id = s.id
      where s.account_id = p_account and s.tip = 'teslimat' and not s.borclandirir
        and (p_product is null or si.product_id = p_product)),0)
  - coalesce((
      select sum(si.adet) from shipments s join shipment_items si on si.shipment_id = s.id
      where s.account_id = p_account and s.tip = 'konsinye_satis'
        and (p_product is null or si.product_id = p_product)),0)
  - coalesce((
      select sum(ri.adet) from returns r join return_items ri on ri.return_id = r.id
      where r.account_id = p_account and not r.bakiyeyi_azaltir
        and (p_product is null or ri.product_id = p_product)),0);
$$;

-- ---------------------------------------------------------------------------
-- K25 · İSKONTO ÇÖZÜMLEME SIRASI
--   discount_rules → accounts.discount_tier ezer → (elle) → tavan kontrolü
--   store_products.varsayilan_iskonto YALNIZCA kural yoksa devreye girer.
-- Taban her zaman store_products.satis_fiyat'tır; etiket_fiyat hesaba girmez.
-- ---------------------------------------------------------------------------
create or replace function resolve_discount(
  p_store uuid, p_account uuid, p_product uuid, p_adet integer)
returns numeric language plpgsql stable as $$
declare
  v_tip account_tipi; v_tier text; v_pub uuid; v_rule numeric; v_default numeric;
begin
  select tip, discount_tier into v_tip, v_tier from accounts where id = p_account;
  select publisher_id into v_pub from products where id = p_product;

  -- 1) Kural tabanı: en spesifik + en yüksek adet kademesi
  select r.iskonto_orani into v_rule
  from discount_rules r
  where r.store_id = p_store
    and (r.account_tip  is null or r.account_tip  = v_tip)
    and (r.product_id   is null or r.product_id   = p_product)
    and (r.publisher_id is null or r.publisher_id = v_pub)
    and r.min_adet <= p_adet
  order by r.oncelik asc,
           (r.product_id is not null) desc,
           (r.publisher_id is not null) desc,
           r.min_adet desc
  limit 1;

  -- 2) Cariye tanımlı kademe kuralı EZER
  if v_tier is not null then
    select r.iskonto_orani into v_rule
    from discount_rules r
    where r.store_id = p_store and r.min_adet <= p_adet
      and (r.product_id is null or r.product_id = p_product)
      and (r.publisher_id is null or r.publisher_id = v_pub)
      and r.oncelik = 0                       -- tier kuralları oncelik 0 ile tanımlanır
    order by r.min_adet desc limit 1;
  end if;

  if v_rule is not null then return v_rule; end if;

  -- 3) Kural yoksa ürünün dükkan varsayılanı
  select varsayilan_iskonto into v_default
  from store_products where store_id = p_store and product_id = p_product;
  return coalesce(v_default, 0);
end $$;

-- V6 · Satır tutarı: satis_fiyat × (1 − iskonto) × adet. Ara sonuç yuvarlanmaz;
-- yalnızca yazılırken 2 haneye yuvarlanır (V8).
create or replace function line_total(p_fiyat numeric, p_iskonto numeric, p_adet integer)
returns numeric language sql immutable as $$
  select round(p_fiyat * (1 - coalesce(p_iskonto,0)) * p_adet, 2);
$$;

-- ---------------------------------------------------------------------------
-- K48 · FIFO MAHSUP — en eski açık borçtan başlar, elle değiştirilebilir.
-- Artan tutar dağıtılmadan kalır (avans) ve bakiyeden düşer.
-- ---------------------------------------------------------------------------
create or replace function allocate_payment_fifo(p_payment uuid)
returns void language plpgsql as $$
declare
  v_account uuid; v_kalan numeric; r record; v_acik numeric;
begin
  select account_id, tutar into v_account, v_kalan from payments where id = p_payment;
  delete from payment_allocations where payment_id = p_payment;

  for r in
    select s.id,
           (select coalesce(sum(si.satir_tutari),0) from shipment_items si where si.shipment_id = s.id) as tutar,
           (select coalesce(sum(pa.tutar),0) from payment_allocations pa where pa.shipment_id = s.id)   as odenen
    from shipments s
    where s.account_id = v_account and s.borclandirir
    order by s.teslim_edildi_at asc
  loop
    exit when v_kalan <= 0;
    v_acik := r.tutar - r.odenen;
    if v_acik > 0 then
      insert into payment_allocations(payment_id, shipment_id, tutar)
      values (p_payment, r.id, least(v_kalan, v_acik));
      v_kalan := v_kalan - least(v_kalan, v_acik);
    end if;
  end loop;
  perform refresh_account_balance(v_account);
end $$;

-- Teslimat düzeyinde ödeme durumu — TÜRETİLİR, saklanmaz (K48).
create or replace function shipment_payment_status(p_shipment uuid)
returns text language sql stable as $$
  select case
    when coalesce(sum(pa.tutar),0) <= 0 then 'odenmedi'
    when coalesce(sum(pa.tutar),0) >= (select coalesce(sum(satir_tutari),0)
                                       from shipment_items where shipment_id = p_shipment)
      then 'odendi'
    else 'kismi' end
  from payment_allocations pa where pa.shipment_id = p_shipment;
$$;

-- ---------------------------------------------------------------------------
-- K8 · KAPALI DÖNEME GERİYE DÖNÜK İŞLEM GİRİLEMEZ
-- Düzeltme, açık dönemde ters kayıtla yapılır.
-- ---------------------------------------------------------------------------
create or replace function trg_period_locked() returns trigger
language plpgsql as $$
declare v_status period_durum;
begin
  select status into v_status from periods where id = new.period_id;
  if v_status = 'kapali' then
    raise exception 'Kapalı döneme işlem girilemez (K8). Açık dönemde ters kayıt atın.';
  end if;
  return new;
end $$;

create trigger t_lock_req  before insert or update on requests
  for each row execute function trg_period_locked();
create trigger t_lock_ord  before insert or update on orders
  for each row execute function trg_period_locked();
create trigger t_lock_shp  before insert or update on shipments
  for each row execute function trg_period_locked();
create trigger t_lock_pay  before insert or update on payments
  for each row execute function trg_period_locked();
create trigger t_lock_ret  before insert or update on returns
  for each row execute function trg_period_locked();

-- C-2 · Teslimat depo SAYACINI düşürür (defter değil, sayaç).
-- Excel yüklemesi sayacı sıfırdan yazar — o bir mutabakat anıdır.
create or replace function trg_stok_sayac() returns trigger
language plpgsql as $$
declare v_store uuid; v_tip shipment_tipi;
begin
  select store_id, tip into v_store, v_tip from shipments
   where id = coalesce(new.shipment_id, old.shipment_id);
  if v_tip <> 'teslimat' then return null; end if;      -- yalnızca fiziksel hareket
  if tg_op = 'INSERT' then
    update store_products set stok_adedi = stok_adedi - new.adet
     where store_id = v_store and product_id = new.product_id and stok_takibi;
  elsif tg_op = 'DELETE' then
    update store_products set stok_adedi = stok_adedi + old.adet
     where store_id = v_store and product_id = old.product_id and stok_takibi;
  end if;
  return null;
end $$;

create trigger t_stok after insert or delete on shipment_items
  for each row execute function trg_stok_sayac();

-- ══════════════════════════════════════════════════════════
-- 0009_rls.sql
-- ══════════════════════════════════════════════════════════
-- =============================================================================
-- 0009 · Satır düzeyi güvenlik (RLS)
-- Yetki kuralı: her sorgu tenant_id ile filtrelenir; pazarlamacı ek olarak
-- assignments'taki CARİ listesiyle sınırlanır; öğretmen kendi carisini görür.
-- Kararlar: K4 K5 K9 K19 K30
-- =============================================================================

-- ---- Yardımcı fonksiyonlar ------------------------------------------------
create or replace function auth_tenant_ids() returns setof uuid
language sql stable security definer set search_path = public as $$
  select distinct tenant_id from memberships
  where user_id = auth.uid() and status = 'aktif';
$$;

create or replace function auth_store_ids() returns setof uuid
language sql stable security definer set search_path = public as $$
  -- store_id NULL olan üyelik (sahip) → tenant'ın TÜM dükkanları
  select s.id from stores s
  where s.tenant_id in (select tenant_id from memberships
                        where user_id = auth.uid() and status='aktif' and store_id is null)
  union
  select store_id from memberships
  where user_id = auth.uid() and status = 'aktif' and store_id is not null;
$$;

create or replace function auth_has_role(p_roles app_role[]) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from memberships
                 where user_id = auth.uid() and status='aktif' and role = any(p_roles));
$$;

-- Pazarlamacının portföyündeki cariler (aktif dönem)
create or replace function auth_assigned_accounts() returns setof uuid
language sql stable security definer set search_path = public as $$
  select a.account_id from assignments a
  join periods p on p.id = a.period_id
  where a.user_id = auth.uid() and a.aktif and p.status <> 'kapali';
$$;

-- Öğretmenin kendi carileri (K19: birden çok olabilir)
create or replace function auth_own_accounts() returns setof uuid
language sql stable security definer set search_path = public as $$
  select ac.id from accounts ac
  where ac.user_id = auth.uid()
  union
  -- kurum adına yetkiliyse kurumsal cari de görünür (K3)
  select ac.id from accounts ac
  join institution_memberships im
    on im.institution_id = ac.institution_id and im.user_id = auth.uid()
  where ac.tip = 'kurum' and im.can_order_for_institution and im.status = 'aktif';
$$;

-- Kullanıcının erişebildiği TÜM cariler
create or replace function auth_visible_accounts() returns setof uuid
language sql stable security definer set search_path = public as $$
  select id from accounts where store_id in (select auth_store_ids())
    and auth_has_role(array['isletme_sahibi','dukkan_muduru','hazirlik']::app_role[])
  union
  select auth_assigned_accounts()
  union
  select auth_own_accounts();
$$;

-- ---- Politikalar ----------------------------------------------------------
alter table profiles      enable row level security;
create policy p_self on profiles for select using (id = auth.uid());
create policy p_self_upd on profiles for update using (id = auth.uid());

alter table tenants enable row level security;
create policy t_read on tenants for select using (id in (select auth_tenant_ids()));

alter table stores enable row level security;
create policy s_read on stores for select using (tenant_id in (select auth_tenant_ids()));

alter table memberships enable row level security;
create policy m_read on memberships for select
  using (user_id = auth.uid() or tenant_id in (select auth_tenant_ids()));

alter table periods enable row level security;
create policy pr_read on periods for select using (tenant_id in (select auth_tenant_ids()));

-- K4 · Kurum dizini ORTAKTIR: doğrulanmış kayıtlar herkese açık.
-- Doğrulanmamış kayıt yalnızca ekleyen işletmeye görünür (Ö-8).
alter table institutions enable row level security;
create policy i_read on institutions for select
  using (dogrulandi or ekleyen_tenant_id in (select auth_tenant_ids()));

-- K30 · Kişi kayıtları ORTAK DEĞİLDİR — rakibe sızmasın.
alter table institution_contacts enable row level security;
create policy ic_all on institution_contacts for all
  using (tenant_id in (select auth_tenant_ids()))
  with check (tenant_id in (select auth_tenant_ids()));

alter table institution_store_links enable row level security;
create policy isl_all on institution_store_links for all
  using (store_id in (select auth_store_ids()))
  with check (store_id in (select auth_store_ids()));

alter table institution_memberships enable row level security;
create policy im_read on institution_memberships for select
  using (user_id = auth.uid()
         or institution_id in (select institution_id from accounts
                               where store_id in (select auth_store_ids())));

alter table publishers enable row level security;
create policy pub_read on publishers for select using (auth.uid() is not null);

-- K9 · Katalog hibrit: ortak (tenant_id NULL) + işletmeye özel
alter table products enable row level security;
create policy prod_read on products for select
  using (tenant_id is null or tenant_id in (select auth_tenant_ids()));
create policy prod_write on products for all
  using (tenant_id in (select auth_tenant_ids()))
  with check (tenant_id in (select auth_tenant_ids()));

alter table deneme_details enable row level security;
create policy dd_read on deneme_details for select
  using (product_id in (select id from products
         where tenant_id is null or tenant_id in (select auth_tenant_ids())));

-- K12 · Fiyat, iskonto ve stok DÜKKANA özeldir
alter table store_products enable row level security;
create policy sp_all on store_products for all
  using (store_id in (select auth_store_ids()))
  with check (store_id in (select auth_store_ids()));

alter table discount_rules enable row level security;
create policy dr_all on discount_rules for all
  using (store_id in (select auth_store_ids()))
  with check (store_id in (select auth_store_ids()));

alter table discount_caps enable row level security;
create policy dc_all on discount_caps for all
  using (store_id in (select auth_store_ids()))
  with check (store_id in (select auth_store_ids()));

-- K5 · Cari erişimi: sahip/müdür → dükkanın tümü; pazarlamacı → portföyü;
-- öğretmen → kendi carisi (+ yetkiliyse kurumsal cari)
alter table accounts enable row level security;
create policy acc_read on accounts for select using (id in (select auth_visible_accounts()));
create policy acc_write on accounts for all
  using (store_id in (select auth_store_ids())
         and auth_has_role(array['isletme_sahibi','dukkan_muduru','pazarlamaci']::app_role[]))
  with check (store_id in (select auth_store_ids()));

alter table assignments enable row level security;
create policy asg_read on assignments for select
  using (user_id = auth.uid() or store_id in (select auth_store_ids()));

alter table account_enrollments enable row level security;
create policy ae_all on account_enrollments for all
  using (account_id in (select auth_visible_accounts()))
  with check (account_id in (select auth_visible_accounts()));

alter table account_transfers enable row level security;
create policy at_read on account_transfers for select
  using (account_id in (select auth_visible_accounts()));

-- İşlem tabloları: hepsi cari görünürlüğüne bağlanır
do $$
declare t text;
begin
  foreach t in array array['requests','orders','shipments','returns','payments','visits','exam_programs']
  loop
    execute format('alter table %I enable row level security', t);
    if t = 'visits' then
      execute format($f$create policy %I_all on %I for all
        using (store_id in (select auth_store_ids()))
        with check (store_id in (select auth_store_ids()))$f$, t, t);
    else
      execute format($f$create policy %I_all on %I for all
        using (account_id in (select auth_visible_accounts()))
        with check (account_id in (select auth_visible_accounts()))$f$, t, t);
    end if;
  end loop;
end $$;

-- Kalem tabloları: üst kayıt üzerinden
do $$
declare r record;
begin
  for r in select * from (values
      ('request_items','requests','request_id'),
      ('order_items','orders','order_id'),
      ('shipment_items','shipments','shipment_id'),
      ('return_items','returns','return_id'),
      ('payment_allocations','payments','payment_id'),
      ('exam_deliveries','exam_programs','exam_program_id')
    ) as v(child, parent, fk)
  loop
    execute format('alter table %I enable row level security', r.child);
    execute format($f$create policy %I_all on %I for all
      using (%I in (select id from %I))
      with check (%I in (select id from %I))$f$,
      r.child, r.child, r.fk, r.parent, r.fk, r.parent);
  end loop;
end $$;

-- Tenant'a bağlı sistem tabloları
do $$
declare t text;
begin
  foreach t in array array['cheques','sample_limits','invites','consents','notifications',
                           'audit_logs','settings','import_batches','import_templates',
                           'saved_reports','period_summaries']
  loop
    execute format('alter table %I enable row level security', t);
    execute format($f$create policy %I_all on %I for all
      using (tenant_id in (select auth_tenant_ids()))
      with check (tenant_id in (select auth_tenant_ids()))$f$, t, t);
  end loop;
end $$;

alter table import_batch_rows enable row level security;
create policy ibr_all on import_batch_rows for all
  using (batch_id in (select id from import_batches))
  with check (batch_id in (select id from import_batches));

alter table bundle_items enable row level security;
create policy bi_read on bundle_items for select
  using (parent_id in (select id from products));
