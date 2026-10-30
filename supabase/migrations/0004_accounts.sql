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
