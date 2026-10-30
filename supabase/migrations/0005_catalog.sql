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
