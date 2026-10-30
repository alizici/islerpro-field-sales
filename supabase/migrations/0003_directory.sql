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
