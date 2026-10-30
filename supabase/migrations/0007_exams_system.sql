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
