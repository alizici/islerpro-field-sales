-- =============================================================================
-- 0020 · Katalog: fiyat durumu süzgeci + sayım
--
-- 0019'daki p_sadece_fiyatli boolean'ı yetersizdi: "fiyatı OLMAYAN ürünler"
-- sorulamıyordu. Oysa 24.632 ürünlük göçün ilk sorusu tam olarak budur —
-- "hangilerine henüz fiyat girmedim?". Üç durumlu bir süzgece çevriliyor.
-- =============================================================================

drop function if exists search_products(uuid, text, katalog_tipi, uuid, smallint, boolean, boolean, integer, integer);
drop function if exists product_by_barcode(uuid, text);

create or replace function search_products(
  p_store_id uuid,
  p_q text default null,
  p_katalog katalog_tipi default null,
  p_publisher_id uuid default null,
  p_sinif smallint default null,
  p_fiyat_durumu text default null,        -- null = hepsi · 'fiyatli' · 'fiyatsiz'
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
      'ozel', p.tenant_id is not null,
      'satis_fiyat', sp.satis_fiyat,
      'alis_fiyat', sp.alis_fiyat,
      'varsayilan_iskonto', sp.varsayilan_iskonto,
      'stok_adedi', case when sp.stok_takibi then sp.stok_adedi end,
      'stok_takibi', coalesce(sp.stok_takibi, true),
      'fiyatli', sp.satis_fiyat is not null and coalesce(sp.aktif, false),
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
      and (p_fiyat_durumu is null
           or (p_fiyat_durumu = 'fiyatli'
               and sp.satis_fiyat is not null and coalesce(sp.aktif, false))
           or (p_fiyat_durumu = 'fiyatsiz'
               and (sp.satis_fiyat is null or not coalesce(sp.aktif, false))))
      and (p_q is null or p_q = ''
           or p.barkod = p_q
           or tr_upper(p.urun_kod) = tr_upper(p_q)
           or p.ad ilike '%' || p_q || '%'
           or similarity(p.ad, p_q) > 0.2)
      and p_store_id in (select auth_store_ids())
    limit p_limit offset p_offset
  ) t;
$$;

-- Aynı süzgeçlerle toplam sayı. Sonsuz kaydırma "3.412 üründen" diyebilsin,
-- ve göç sırasında "kaç ürünün fiyatı eksik" tek bakışta görünsün.
create or replace function count_products(
  p_store_id uuid,
  p_q text default null,
  p_katalog katalog_tipi default null,
  p_publisher_id uuid default null,
  p_sinif smallint default null,
  p_fiyat_durumu text default null,
  p_arsiv boolean default false
) returns integer
language sql stable security definer set search_path = public, extensions as $$
  select count(*)::integer
  from products p
  left join store_products sp
         on sp.product_id = p.id and sp.store_id = p_store_id
  where p.merged_into_id is null
    and (p.tenant_id is null or p.tenant_id in (select auth_tenant_ids()))
    and (p_arsiv or not p.arsivlendi)
    and (p_katalog is null or p.katalog = p_katalog)
    and (p_publisher_id is null or p.publisher_id = p_publisher_id)
    and (p_sinif is null or p.sinif @> array[p_sinif])
    and (p_fiyat_durumu is null
         or (p_fiyat_durumu = 'fiyatli'
             and sp.satis_fiyat is not null and coalesce(sp.aktif, false))
         or (p_fiyat_durumu = 'fiyatsiz'
             and (sp.satis_fiyat is null or not coalesce(sp.aktif, false))))
    and (p_q is null or p_q = ''
         or p.barkod = p_q
         or tr_upper(p.urun_kod) = tr_upper(p_q)
         or p.ad ilike '%' || p_q || '%'
         or similarity(p.ad, p_q) > 0.2)
    and p_store_id in (select auth_store_ids());
$$;

create or replace function product_by_barcode(p_store_id uuid, p_barkod text)
returns jsonb
language sql stable security definer set search_path = public, extensions as $$
  select (search_products(p_store_id => p_store_id, p_q => p_barkod,
                          p_arsiv => true, p_limit => 1))->0;
$$;

grant execute on function search_products(uuid, text, katalog_tipi, uuid, smallint, text, boolean, integer, integer) to authenticated;
grant execute on function count_products(uuid, text, katalog_tipi, uuid, smallint, text, boolean) to authenticated;
grant execute on function product_by_barcode(uuid, text) to authenticated;
