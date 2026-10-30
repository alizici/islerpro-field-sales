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
