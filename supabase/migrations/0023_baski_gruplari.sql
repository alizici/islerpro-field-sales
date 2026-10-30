-- =============================================================================
-- 0023 · K23 · Baskı grupları
--
-- Baskı ilişkisi TAHMİN EDİLMEZ, İNSAN SÖYLER. Addaki yıl bir yazım
-- alışkanlığıdır (%46'sında var, kalıpları tutarsız); oradan üretilen gruplama
-- doğruluğu asla garanti edilemeyecek bir tahmindir.
--
-- Gruplar tam da doğru anda doğar: yeni baskı eklenirken.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- YENİ BASKI EKLE
--
-- Her baskı BAĞIMSIZ bir products satırıdır; hiçbir alan referansla
-- paylaşılmaz. Kopyalama yalnızca yazım kolaylığıdır.
--
--   Kopyalanır : ad · yayınevi · kategori · sinif[] · ders · sinav_tipi
--                + varsayilan_iskonto (aynı yayıneviyle anlaşma sürer)
--   Boş gelir  : barkod (ürünün KİMLİĞİDİR, asla kopyalanmaz)
--                baski_etiketi · etiket_fiyat · satış/alış fiyatı
--                (yeni baskı fiyatı farklıdır — ölçüm: medyan 1.40x)
--   Taşınmaz   : stok · açık sipariş · konsinye · iade · geçmiş satış
-- ---------------------------------------------------------------------------
create or replace function add_edition(
  p_store_id uuid,
  p_kaynak_product_id uuid,
  p_baski_etiketi text,
  p_barkod text default null,
  p_etiket_fiyat numeric default null,
  p_eski_arsivle boolean default false
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_tenant uuid; v_grup uuid; v_sira smallint; v_yeni uuid;
  k products%rowtype; v_stok integer; v_iskonto numeric;
begin
  if coalesce(trim(p_baski_etiketi), '') = '' then
    raise exception 'Baskı etiketi zorunludur (örn. 2026-27 veya 3. Baskı)';
  end if;
  select tenant_id into v_tenant from stores where id = p_store_id;
  if v_tenant is null or v_tenant not in (select auth_tenant_ids()) then
    raise exception 'Bu dükkana yetkiniz yok';
  end if;

  select * into k from products where id = p_kaynak_product_id;
  if k.id is null then raise exception 'Kaynak ürün bulunamadı'; end if;

  -- K24 · barkod benzersizdir; çakışırsa yeni kayıt AÇILMAZ
  if coalesce(trim(p_barkod), '') <> '' then
    if exists (select 1 from products
               where barkod = trim(p_barkod) and merged_into_id is null) then
      raise exception 'Bu barkod katalogda zaten kayıtlı';
    end if;
  end if;

  -- Grup yoksa ŞİMDİ doğar; eski ürün de gruba alınır.
  v_grup := k.baski_grubu_id;
  if v_grup is null then
    v_grup := gen_random_uuid();
    update products set baski_grubu_id = v_grup,
                        baski_sirasi = coalesce(baski_sirasi, 1)
    where id = k.id;
  end if;

  select coalesce(max(baski_sirasi), 0) + 1 into v_sira
  from products where baski_grubu_id = v_grup;

  insert into products (tenant_id, katalog, ad, publisher_id, barkod,
                        kategori, sinif, ders, sinav_tipi,
                        etiket_fiyat, baski_etiketi, baski_sirasi, baski_grubu_id)
  values (v_tenant, k.katalog, k.ad, k.publisher_id,
          nullif(trim(coalesce(p_barkod, '')), ''),
          k.kategori, k.sinif, k.ders, k.sinav_tipi,
          p_etiket_fiyat,                 -- kopyalanmaz, kullanıcı girer
          trim(p_baski_etiketi), v_sira, v_grup)
  returning id into v_yeni;

  -- K12 · fiyat katmanı: iskonto anlaşması sürer, FİYAT sürmez.
  select varsayilan_iskonto into v_iskonto
  from store_products where store_id = p_store_id and product_id = k.id;
  if v_iskonto is not null then
    insert into store_products (store_id, product_id, varsayilan_iskonto)
    values (p_store_id, v_yeni, v_iskonto)
    on conflict (store_id, product_id) do nothing;
  end if;

  -- Eski baskıyı arşivleme: stoğu varsa arşivlenmez, uyarı verilir.
  if p_eski_arsivle then
    select coalesce(stok_adedi, 0) into v_stok
    from store_products where store_id = p_store_id and product_id = k.id;
    if coalesce(v_stok, 0) > 0 then
      raise exception 'Eski baskıda % adet stok var — arşivlenemez. Önce eritin veya "satışta kalsın" seçin.',
        v_stok;
    end if;
    update products set arsivlendi = true where id = k.id;
  end if;

  insert into audit_logs (tenant_id, user_id, eylem, tablo, kayit_id, detay)
  values (v_tenant, auth.uid(), 'add_edition', 'products', v_yeni,
          jsonb_build_object('kaynak', k.id, 'grup', v_grup,
                             'sira', v_sira, 'etiket', trim(p_baski_etiketi)));

  return jsonb_build_object('id', v_yeni, 'grup_id', v_grup, 'sira', v_sira,
                            'eski_arsivlendi', p_eski_arsivle);
end $$;

-- ---------------------------------------------------------------------------
-- GERİYE DÖNÜK BAĞLAMA · Pazarlamacı eski bir baskıyla karşılaştığında
-- tek seferde düzeltir.
-- ---------------------------------------------------------------------------
create or replace function link_edition(
  p_product_id uuid, p_hedef_product_id uuid, p_sira smallint default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_tenant uuid; v_grup uuid; v_sira smallint; v_hedef_grup uuid;
begin
  if p_product_id = p_hedef_product_id then
    raise exception 'Ürün kendisine bağlanamaz';
  end if;
  select tenant_id into v_tenant from memberships
  where user_id = auth.uid() and status = 'aktif' limit 1;
  if v_tenant is null then raise exception 'İşletme üyeliğiniz yok'; end if;
  if not auth_has_role(array['isletme_sahibi','dukkan_muduru']::app_role[]) then
    raise exception 'Baskı grubunu yalnızca sahip veya müdür düzenleyebilir';
  end if;

  select baski_grubu_id into v_grup from products where id = p_hedef_product_id;
  select baski_grubu_id into v_hedef_grup from products where id = p_product_id;
  if v_hedef_grup is not null and v_grup is not null and v_hedef_grup <> v_grup then
    raise exception 'Bu ürün başka bir baskı grubunda. Önce oradan çıkarın.';
  end if;

  if v_grup is null then
    v_grup := gen_random_uuid();
    update products set baski_grubu_id = v_grup,
                        baski_sirasi = coalesce(baski_sirasi, 1)
    where id = p_hedef_product_id;
  end if;

  v_sira := p_sira;
  if v_sira is null then
    select coalesce(max(baski_sirasi), 0) + 1 into v_sira
    from products where baski_grubu_id = v_grup;
  end if;

  update products set baski_grubu_id = v_grup, baski_sirasi = v_sira
  where id = p_product_id;

  insert into audit_logs (tenant_id, user_id, eylem, tablo, kayit_id, detay)
  values (v_tenant, auth.uid(), 'link_edition', 'products', p_product_id,
          jsonb_build_object('grup', v_grup, 'sira', v_sira));

  return jsonb_build_object('grup_id', v_grup, 'sira', v_sira);
end $$;

create or replace function unlink_edition(p_product_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_grup uuid; v_kalan int;
begin
  if not auth_has_role(array['isletme_sahibi','dukkan_muduru']::app_role[]) then
    raise exception 'Baskı grubunu yalnızca sahip veya müdür düzenleyebilir';
  end if;
  select baski_grubu_id into v_grup from products where id = p_product_id;
  if v_grup is null then raise exception 'Bu ürün bir baskı grubunda değil'; end if;

  update products set baski_grubu_id = null, baski_sirasi = null
  where id = p_product_id;

  -- Tek ürün kalan grup grup değildir; bağı da kaldır.
  select count(*) into v_kalan from products where baski_grubu_id = v_grup;
  if v_kalan <= 1 then
    update products set baski_grubu_id = null, baski_sirasi = null
    where baski_grubu_id = v_grup;
  end if;

  return jsonb_build_object('grup_id', v_grup, 'kalan', v_kalan - 1);
end $$;

-- ---------------------------------------------------------------------------
-- GRUP GÖRÜNÜMÜ
-- Güncel baskı = en yüksek baski_sirasi. Tarih ayrıştırmasıyla DEĞİL,
-- açık sırayla belirlenir.
-- ---------------------------------------------------------------------------
create or replace function edition_group(p_product_id uuid, p_store_id uuid)
returns jsonb
language sql stable security definer set search_path = public as $$
  with grup as (
    select baski_grubu_id as g from products where id = p_product_id
  )
  select case when (select g from grup) is null then '[]'::jsonb
  else coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', p.id, 'ad', p.ad,
             'baski_etiketi', p.baski_etiketi,
             'baski_sirasi', p.baski_sirasi,
             'barkod', p.barkod,
             'etiket_fiyat', p.etiket_fiyat,
             'satis_fiyat', sp.satis_fiyat,
             'stok_adedi', case when sp.stok_takibi then sp.stok_adedi end,
             'arsivlendi', p.arsivlendi,
             'guncel', p.baski_sirasi = (select max(x.baski_sirasi) from products x
                                         where x.baski_grubu_id = (select g from grup)),
             'secili', p.id = p_product_id)
           order by p.baski_sirasi desc)
    from products p
    left join store_products sp
           on sp.product_id = p.id and sp.store_id = p_store_id
    where p.baski_grubu_id = (select g from grup)
      and p.merged_into_id is null), '[]'::jsonb)
  end
  where p_store_id in (select auth_store_ids());
$$;

-- ---------------------------------------------------------------------------
-- SİPARİŞ UYARISI · İKİ YÖNLÜ
-- Bazen doğru olan eski baskıyla devam etmektir (stok eritmek), bazen yeni
-- müfredat gerekir. Karar kullanıcınındır; sistemin işi SESSİZ KALMAMAKTIR.
-- ---------------------------------------------------------------------------
create or replace function edition_warning(p_product_id uuid, p_store_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_grup uuid; v_sira smallint; v_max smallint; g jsonb; s jsonb;
begin
  select baski_grubu_id, baski_sirasi into v_grup, v_sira
  from products where id = p_product_id;
  if v_grup is null then return jsonb_build_object('uyari', false); end if;

  select max(baski_sirasi) into v_max from products
  where baski_grubu_id = v_grup and not arsivlendi and merged_into_id is null;
  if v_max is null or coalesce(v_sira, 0) >= v_max then
    return jsonb_build_object('uyari', false);
  end if;

  select jsonb_build_object(
           'id', p.id, 'baski_etiketi', p.baski_etiketi,
           'satis_fiyat', sp.satis_fiyat, 'stok_adedi', sp.stok_adedi)
    into g
  from products p
  left join store_products sp on sp.product_id = p.id and sp.store_id = p_store_id
  where p.baski_grubu_id = v_grup and p.baski_sirasi = v_max
  limit 1;

  select jsonb_build_object(
           'id', p.id, 'baski_etiketi', p.baski_etiketi,
           'satis_fiyat', sp.satis_fiyat, 'stok_adedi', sp.stok_adedi)
    into s
  from products p
  left join store_products sp on sp.product_id = p.id and sp.store_id = p_store_id
  where p.id = p_product_id;

  return jsonb_build_object('uyari', true, 'guncel', g, 'secili', s);
end $$;

-- Eski baskı eritme raporu: elde stoğu olan ve daha yenisi bulunanlar.
create or replace function stale_editions(p_store_id uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', p.id, 'ad', p.ad, 'baski_etiketi', p.baski_etiketi,
           'stok_adedi', sp.stok_adedi, 'satis_fiyat', sp.satis_fiyat,
           'guncel_etiket', (select x.baski_etiketi from products x
                             where x.baski_grubu_id = p.baski_grubu_id
                             order by x.baski_sirasi desc limit 1))
         order by sp.stok_adedi desc), '[]'::jsonb)
  from products p
  join store_products sp on sp.product_id = p.id and sp.store_id = p_store_id
  where p.baski_grubu_id is not null
    and sp.stok_takibi and sp.stok_adedi > 0
    and p.merged_into_id is null
    and p.baski_sirasi < (select max(x.baski_sirasi) from products x
                          where x.baski_grubu_id = p.baski_grubu_id
                            and not x.arsivlendi)
    and p_store_id in (select auth_store_ids());
$$;

grant execute on function add_edition(uuid, uuid, text, text, numeric, boolean) to authenticated;
grant execute on function link_edition(uuid, uuid, smallint) to authenticated;
grant execute on function unlink_edition(uuid) to authenticated;
grant execute on function edition_group(uuid, uuid) to authenticated;
grant execute on function edition_warning(uuid, uuid) to authenticated;
grant execute on function stale_editions(uuid) to authenticated;
