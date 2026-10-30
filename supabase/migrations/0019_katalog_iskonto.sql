-- =============================================================================
-- 0019 · Katalog aramaları + K25 iskonto çözümlemesinin düzeltilmesi
-- Kararlar: K9 K12 K14 K15 K16 K23 K24 K25 K31 · V6 V8
--
-- 0008'deki resolve_discount iki hata taşıyordu:
--   H1. v_tier okunuyor ama sorguda KULLANILMIYORDU → "cari kademesi ezer"
--       kuralı fiilen çalışmıyor, her kademe aynı sonucu alıyordu.
--   H2. 2. basamaktaki `select ... into v_rule` eşleşme bulamayınca v_rule'u
--       NULL'a çekiyordu → discount_tier'ı dolu olan cari, 1. basamakta
--       bulunmuş kuralı KAYBEDİYORDU ve varsayılana düşüyordu.
--   H3. discount_rules'ta tier sütunu yoktu; kademe hiç ifade edilemiyordu.
-- =============================================================================

-- ── Türkçe büyük harf (Dart tarafındaki TurkceMetin.buyuk ile aynı kural) ───
create or replace function tr_upper(p text) returns text
language sql immutable as $$
  select upper(translate(coalesce(p, ''), 'iı', 'İI'));
$$;

create or replace function tr_normalize(p text) returns text
language sql immutable as $$
  select regexp_replace(tr_upper(p), '[^A-Z0-9ÇĞİÖŞÜ]', '', 'g');
$$;

-- ---------------------------------------------------------------------------
-- YAYINEVİ · normalize_ad ile mükerrer engellenir ('BES KURUMSAL' = 'Bes Kurumsal')
-- ---------------------------------------------------------------------------
create or replace function upsert_publisher(p_ad text) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_norm text;
begin
  v_norm := tr_normalize(p_ad);
  if v_norm = '' then return null; end if;
  select id into v_id from publishers where normalize_ad = v_norm;
  if v_id is not null then return v_id; end if;
  insert into publishers (ad, normalize_ad) values (trim(p_ad), v_norm)
  on conflict (normalize_ad) do update set ad = publishers.ad
  returning id into v_id;
  return v_id;
end $$;

create or replace function list_publishers(p_store_id uuid default null)
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', pub.id, 'ad', pub.ad,
           'urun_sayisi', c.n, 'fiyatli_sayisi', c.f) order by pub.ad), '[]'::jsonb)
  from publishers pub
  join lateral (
    select count(*) as n,
           count(*) filter (
             where p_store_id is not null and exists (
               select 1 from store_products sp
               where sp.product_id = p.id and sp.store_id = p_store_id and sp.aktif)) as f
    from products p
    where p.publisher_id = pub.id and p.merged_into_id is null and not p.arsivlendi
  ) c on true
  where c.n > 0;
$$;

-- ── H3 · kademe sütunu ─────────────────────────────────────────────────────
alter table discount_rules add column if not exists tier text;
alter table discount_rules add column if not exists ad text;
create index if not exists discount_rules_tier_idx
  on discount_rules(store_id, tier) where tier is not null;

create index if not exists products_urun_kod_idx on products(urun_kod)
  where urun_kod is not null;
create index if not exists store_products_product_idx on store_products(product_id);

-- ---------------------------------------------------------------------------
-- K25 · İSKONTO ÇÖZÜMLEMESİ — tek doğru sıra, gerekçesiyle birlikte
--
--   1. Cariye kademe (discount_tier) tanımlıysa ve o kademe için kural varsa
--      → EZER. Kademe, bir cariyle yapılmış özel anlaşmadır.
--   2. Yoksa genel kurallar (tier is null) — en spesifik olan kazanır:
--        oncelik ↑ → ürün kuralı → yayınevi kuralı → cari tipi kuralı → adet ↓
--   3. Hiç kural yoksa store_products.varsayilan_iskonto
--   4. O da yoksa 0
--
-- Taban HER ZAMAN store_products.satis_fiyat'tır; etiket_fiyat hesaba girmez.
-- Dönüş jsonb'dir: pazarlamacı ekranda "%20 — neden?" sorusunun cevabını görür.
-- ---------------------------------------------------------------------------
create or replace function resolve_discount_detail(
  p_store uuid, p_account uuid, p_product uuid, p_adet integer default 1)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_tip account_tipi; v_tier text; v_pub uuid;
  v_id uuid; v_oran numeric; v_ad text; v_default numeric;
begin
  select tip, discount_tier into v_tip, v_tier from accounts where id = p_account;
  select publisher_id into v_pub from products where id = p_product;

  -- 1) Kademe kuralı — varsa her şeyi ezer
  if v_tier is not null then
    select r.id, r.iskonto_orani, r.ad into v_id, v_oran, v_ad
    from discount_rules r
    where r.store_id = p_store
      and r.tier = v_tier
      and (r.account_tip  is null or r.account_tip  = v_tip)
      and (r.product_id   is null or r.product_id   = p_product)
      and (r.publisher_id is null or r.publisher_id = v_pub)
      and r.min_adet <= p_adet
    order by r.oncelik asc,
             (r.product_id   is not null) desc,
             (r.publisher_id is not null) desc,
             r.min_adet desc
    limit 1;

    if v_oran is not null then
      return jsonb_build_object(
        'oran', v_oran, 'kaynak', 'kademe',
        'kaynak_ad', coalesce(v_ad, 'Cari kademesi: ' || v_tier),
        'kural_id', v_id);
    end if;
  end if;

  -- 2) Genel kurallar
  select r.id, r.iskonto_orani, r.ad into v_id, v_oran, v_ad
  from discount_rules r
  where r.store_id = p_store
    and r.tier is null
    and (r.account_tip  is null or r.account_tip  = v_tip)
    and (r.product_id   is null or r.product_id   = p_product)
    and (r.publisher_id is null or r.publisher_id = v_pub)
    and r.min_adet <= p_adet
  order by r.oncelik asc,
           (r.product_id   is not null) desc,
           (r.publisher_id is not null) desc,
           (r.account_tip  is not null) desc,
           r.min_adet desc
  limit 1;

  if v_oran is not null then
    return jsonb_build_object(
      'oran', v_oran, 'kaynak', 'kural',
      'kaynak_ad', coalesce(v_ad, 'İskonto kuralı'),
      'kural_id', v_id);
  end if;

  -- 3) Dükkan varsayılanı
  select varsayilan_iskonto into v_default
  from store_products where store_id = p_store and product_id = p_product;

  if coalesce(v_default, 0) > 0 then
    return jsonb_build_object('oran', v_default, 'kaynak', 'dukkan_varsayilani',
                              'kaynak_ad', 'Ürünün dükkan varsayılanı', 'kural_id', null);
  end if;

  return jsonb_build_object('oran', 0, 'kaynak', 'yok',
                            'kaynak_ad', 'Tanımlı iskonto yok', 'kural_id', null);
end $$;

-- Skaler sarmalayıcı — mevcut çağıranlar için imza korunuyor.
create or replace function resolve_discount(
  p_store uuid, p_account uuid, p_product uuid, p_adet integer)
returns numeric
language sql stable security definer set search_path = public as $$
  select (resolve_discount_detail(p_store, p_account, p_product, p_adet)->>'oran')::numeric;
$$;

-- ---------------------------------------------------------------------------
-- K25 · TAVAN · Pazarlamacı elle indirim yaparsa tavanı aşamaz; aşarsa
-- sipariş onaya düşer (engellenmez — saha kararı yok edilmez, görünür kılınır).
-- ---------------------------------------------------------------------------
create or replace function check_discount_cap(
  p_store uuid, p_iskonto numeric, p_user uuid default null)
returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'tavan', t.tavan,
    'asildi', t.tavan is not null and p_iskonto > t.tavan,
    'onay_gerekir', t.tavan is not null and p_iskonto > t.tavan)
  from (
    select (select tavan from discount_caps
            where store_id = p_store
              and user_id is not distinct from coalesce(p_user, auth.uid())
            union all
            select tavan from discount_caps
            where store_id = p_store and user_id is null
            limit 1) as tavan
  ) t;
$$;

-- ---------------------------------------------------------------------------
-- KATALOG ARAMASI · Ürün kimliği + o dükkanın ticari katmanı tek satırda (K12)
-- Ortak katalog (tenant_id null) + işletmeye özel ürünler birlikte gelir (K9).
-- Birleştirilmiş mükerrerler (merged_into_id) hiç görünmez.
-- ---------------------------------------------------------------------------
create or replace function search_products(
  p_store_id uuid,
  p_q text default null,
  p_katalog katalog_tipi default null,
  p_publisher_id uuid default null,
  p_sinif smallint default null,
  p_sadece_fiyatli boolean default false,
  p_arsiv boolean default false,
  p_limit integer default 50,
  p_offset integer default 0
) returns jsonb
language sql stable security definer set search_path = public, extensions as $$
  select coalesce(jsonb_agg(x order by (x->>'skor')::float desc, x->>'ad'), '[]'::jsonb)
  from (
    select jsonb_build_object(
      'id', p.id, 'ad', p.ad, 'katalog', p.katalog,
      'barkod', p.barkod, 'urun_kod', p.urun_kod,
      'yayinevi', pub.ad, 'publisher_id', p.publisher_id,
      'kategori', p.kategori, 'sinif', p.sinif, 'ders', p.ders,
      'sinav_tipi', p.sinav_tipi,
      'etiket_fiyat', p.etiket_fiyat,          -- yalnızca gösterim (K25)
      'baski_etiketi', p.baski_etiketi,
      'baski_grubu_id', p.baski_grubu_id,
      'arsivlendi', p.arsivlendi,
      'ozel', p.tenant_id is not null,          -- işletmeye özel mi
      -- Dükkanın ticari katmanı (K12). null → bu dükkanda fiyatlanmamış.
      'satis_fiyat', sp.satis_fiyat,
      'alis_fiyat', sp.alis_fiyat,
      'varsayilan_iskonto', sp.varsayilan_iskonto,
      'stok_adedi', case when sp.stok_takibi then sp.stok_adedi end,
      'stok_takibi', coalesce(sp.stok_takibi, true),
      'fiyatli', sp.id is not null and sp.aktif,
      'skor', case
                when p_q is null or p_q = '' then 0
                when p.barkod = p_q then 3
                when tr_upper(p.urun_kod) = tr_upper(p_q) then 2.5
                else similarity(p.ad, p_q) end
    ) as x
    from products p
    left join publishers pub on pub.id = p.publisher_id
    left join store_products sp
           on sp.product_id = p.id and sp.store_id = p_store_id
    where p.merged_into_id is null
      and (p.tenant_id is null or p.tenant_id in (select auth_tenant_ids()))
      and (p_arsiv or not p.arsivlendi)                          -- K14
      and (p_katalog is null or p.katalog = p_katalog)           -- K15
      and (p_publisher_id is null or p.publisher_id = p_publisher_id)
      and (p_sinif is null or p.sinif @> array[p_sinif])
      and (not p_sadece_fiyatli or (sp.id is not null and sp.aktif))
      and (p_q is null or p_q = ''
           or p.barkod = p_q
           or tr_upper(p.urun_kod) = tr_upper(p_q)
           or p.ad ilike '%' || p_q || '%'
           or similarity(p.ad, p_q) > 0.2)
      and p_store_id in (select auth_store_ids())
    limit p_limit offset p_offset
  ) t;
$$;

-- Barkod okuyucu için tek atış (mobile_scanner). Tam eşleşme, tek kayıt (K24).
create or replace function product_by_barcode(p_store_id uuid, p_barkod text)
returns jsonb
language sql stable security definer set search_path = public, extensions as $$
  select (search_products(p_store_id, p_barkod, null, null, null, false, true, 1, 0))->0;
$$;

-- ---------------------------------------------------------------------------
-- ÜRÜN EKLEME · Barkod benzersizdir (K24). Çakışırsa mevcut ürünü döndürür ki
-- ekran "bu ürün zaten var, dükkanına fiyat mı eklemek istiyorsun?" diyebilsin.
-- ---------------------------------------------------------------------------
create or replace function add_product(
  p_store_id uuid,
  p_ad text,
  p_katalog katalog_tipi default 'kitap',
  p_barkod text default null,
  p_urun_kod text default null,
  p_yayinevi text default null,
  p_kategori text default null,
  p_ders text default null,
  p_sinif smallint[] default null,
  p_sinav_tipi text default null,
  p_etiket_fiyat numeric default null,
  p_baski_etiketi text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_tenant uuid; v_pub uuid; v_id uuid; v_mevcut uuid;
begin
  if coalesce(trim(p_ad), '') = '' then
    raise exception 'Ürün adı boş olamaz';
  end if;
  select tenant_id into v_tenant from stores where id = p_store_id;
  if v_tenant is null or v_tenant not in (select auth_tenant_ids()) then
    raise exception 'Bu dükkana yetkiniz yok';
  end if;

  if p_barkod is not null and trim(p_barkod) <> '' then
    select id into v_mevcut from products
    where barkod = trim(p_barkod) and merged_into_id is null;
    if v_mevcut is not null then
      return jsonb_build_object('id', v_mevcut, 'yeni', false,
                                'mesaj', 'Bu barkod katalogda zaten var');
    end if;
  end if;

  if p_yayinevi is not null and trim(p_yayinevi) <> '' then
    v_pub := upsert_publisher(p_yayinevi);
  end if;

  insert into products (tenant_id, katalog, ad, publisher_id, barkod, urun_kod,
                        kategori, sinif, ders, sinav_tipi, etiket_fiyat, baski_etiketi)
  values (v_tenant, p_katalog, trim(p_ad), v_pub,
          nullif(trim(coalesce(p_barkod,'')), ''),
          nullif(trim(coalesce(p_urun_kod,'')), ''),
          nullif(trim(coalesce(p_kategori,'')), ''),
          p_sinif, nullif(trim(coalesce(p_ders,'')), ''),
          nullif(trim(coalesce(p_sinav_tipi,'')), ''),
          p_etiket_fiyat, nullif(trim(coalesce(p_baski_etiketi,'')), ''))
  returning id into v_id;

  insert into audit_logs (tenant_id, user_id, eylem, tablo, kayit_id, detay)
  values (v_tenant, auth.uid(), 'add_product', 'products', v_id,
          jsonb_build_object('ad', trim(p_ad), 'barkod', p_barkod));

  return jsonb_build_object('id', v_id, 'yeni', true);
end $$;

-- ---------------------------------------------------------------------------
-- DÜKKAN FİYAT KATMANI (K12) · Ürün kimliği paylaşılır, fiyat paylaşılmaz.
-- ---------------------------------------------------------------------------
create or replace function upsert_store_product(
  p_store_id uuid,
  p_product_id uuid,
  p_satis_fiyat numeric default null,
  p_alis_fiyat numeric default null,
  p_varsayilan_iskonto numeric default null,
  p_stok_takibi boolean default null,
  p_aktif boolean default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if p_store_id not in (select auth_store_ids()) then
    raise exception 'Bu dükkana yetkiniz yok';
  end if;
  if p_varsayilan_iskonto is not null
     and (p_varsayilan_iskonto < 0 or p_varsayilan_iskonto >= 1) then
    raise exception 'İskonto 0 ile 1 arasında bir oran olmalı (0.20 = %%20)';
  end if;
  if p_satis_fiyat is not null and p_satis_fiyat < 0 then
    raise exception 'Satış fiyatı negatif olamaz';
  end if;

  insert into store_products (store_id, product_id, satis_fiyat, alis_fiyat,
                              varsayilan_iskonto, stok_takibi, aktif)
  values (p_store_id, p_product_id, p_satis_fiyat, p_alis_fiyat,
          coalesce(p_varsayilan_iskonto, 0), coalesce(p_stok_takibi, true),
          coalesce(p_aktif, true))
  on conflict (store_id, product_id) do update set
    satis_fiyat        = coalesce(excluded.satis_fiyat, store_products.satis_fiyat),
    alis_fiyat         = coalesce(excluded.alis_fiyat,  store_products.alis_fiyat),
    varsayilan_iskonto = case when p_varsayilan_iskonto is null
                              then store_products.varsayilan_iskonto
                              else p_varsayilan_iskonto end,
    stok_takibi        = case when p_stok_takibi is null
                              then store_products.stok_takibi else p_stok_takibi end,
    aktif              = case when p_aktif is null
                              then store_products.aktif else p_aktif end
  returning id into v_id;

  return jsonb_build_object('id', v_id);
end $$;

grant execute on function tr_upper(text) to authenticated, anon;
grant execute on function tr_normalize(text) to authenticated, anon;
grant execute on function resolve_discount_detail(uuid, uuid, uuid, integer) to authenticated;
grant execute on function check_discount_cap(uuid, numeric, uuid) to authenticated;
grant execute on function search_products(uuid, text, katalog_tipi, uuid, smallint, boolean, boolean, integer, integer) to authenticated;
grant execute on function product_by_barcode(uuid, text) to authenticated;
grant execute on function add_product(uuid, text, katalog_tipi, text, text, text, text, text, smallint[], text, numeric, text) to authenticated;
grant execute on function upsert_store_product(uuid, uuid, numeric, numeric, numeric, boolean, boolean) to authenticated;
grant execute on function upsert_publisher(text) to authenticated;
grant execute on function list_publishers(uuid) to authenticated;
