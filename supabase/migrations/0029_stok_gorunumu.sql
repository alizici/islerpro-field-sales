-- =============================================================================
-- 0029 · Hafif stok görünümü
-- Kararlar: K13 K27 K45 · K23 (eritme)
--
-- K45 · Stok DEFTERİ yoktur: stok_items/stock_movements/stock_counts yok.
-- store_products.stok_adedi bir SAYAÇTIR ve Excel'le beslenir (K27).
-- Bu fonksiyon o sayacı okur; hareket üretmez, mutabakat yapmaz.
-- K27 · Stok bilgi amaçlıdır, SİPARİŞİ ENGELLEMEZ.
-- =============================================================================

create or replace function stock_summary(
  p_store_id uuid, p_limit integer default 100) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'takipli_urun', (select count(*) from store_products sp
                     where sp.store_id = p_store_id and sp.aktif and sp.stok_takibi),
    'stoklu_urun',  (select count(*) from store_products sp
                     where sp.store_id = p_store_id and sp.aktif
                       and sp.stok_takibi and sp.stok_adedi > 0),
    'toplam_adet',  (select coalesce(sum(sp.stok_adedi), 0) from store_products sp
                     where sp.store_id = p_store_id and sp.aktif and sp.stok_takibi),
    -- K13 · stok takibi kapalı ürünler: adedi hiç gösterilmez
    'takipsiz_urun', (select count(*) from store_products sp
                      where sp.store_id = p_store_id and sp.aktif
                        and not sp.stok_takibi),
    'en_cok', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', p.id, 'ad', p.ad, 'barkod', p.barkod,
               'yayinevi', pub.ad, 'baski_etiketi', p.baski_etiketi,
               'stok_adedi', sp.stok_adedi, 'satis_fiyat', sp.satis_fiyat,
               'deger', sp.stok_adedi * coalesce(sp.satis_fiyat, 0))
             order by sp.stok_adedi desc)
      from (select * from store_products sp2
            where sp2.store_id = p_store_id and sp2.aktif and sp2.stok_takibi
              and sp2.stok_adedi > 0
            order by sp2.stok_adedi desc limit p_limit) sp
      join products p on p.id = sp.product_id
      left join publishers pub on pub.id = p.publisher_id), '[]'::jsonb)
  )
  where p_store_id in (select auth_store_ids());
$$;

grant execute on function stock_summary(uuid, integer) to authenticated;
