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
