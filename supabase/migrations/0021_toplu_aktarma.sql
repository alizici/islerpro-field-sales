-- =============================================================================
-- 0021 · K49 · Toplu aktarma motoru
--
-- Tek akış, altı veri türü. Tasarımın iki taşıyıcı fikri:
--
--   1. ÖNİZLEME İLE UYGULAMA AYNI KODDUR. `p_kuru_kosu` yalnızca yazmayı
--      kapatır; yeni/güncelleme/hata kararı aynı yerde verilir. Ayrı bir
--      önizleme kodu olsaydı, önizlemenin doğru olduğu garanti edilemezdi.
--   2. GERİ ALMA SATIR BAZLIDIR. Dokunulan her kaydın ÖNCEKİ HÂLİ
--      import_batch_rows'a yazılır; geri alma insert'i siler, update'i
--      eski değerine döndürür. 400 satırlık yanlış yükleme elle düzeltilemez.
-- =============================================================================

-- ── Sayı okuma · Dart tarafındaki Fmt.sayiOku ile AYNI kural ───────────────
-- Excel'den gelen "26,0" ile "1.250,50" ve "100.00" birlikte gelebiliyor.
create or replace function tr_sayi(p text) returns numeric
language plpgsql immutable as $$
declare t text; n int; v int; parca text[];
begin
  t := regexp_replace(coalesce(p, ''), '[\s₺]', '', 'g');
  if t = '' then return null; end if;
  n := case when strpos(t, '.') > 0 then length(t) + 1 - strpos(reverse(t), '.') else 0 end;
  v := case when strpos(t, ',') > 0 then length(t) + 1 - strpos(reverse(t), ',') else 0 end;
  if n > 0 and v > 0 then
    -- İkisi de varsa sonuncusu ondalık ayracıdır.
    t := case when v > n then replace(replace(t, '.', ''), ',', '.')
              else replace(t, ',', '') end;
  elsif v > 0 then
    t := replace(t, ',', '.');
  elsif n > 0 then
    -- Yalnızca nokta belirsiz: 1.250 binlik, 100.00 ondalık.
    parca := string_to_array(t, '.');
    if array_length(parca, 1) > 1
       and (select bool_and(length(x) = 3) from unnest(parca[2:]) x) then
      t := replace(t, '.', '');
    end if;
  end if;
  return t::numeric;
exception when others then return null;
end $$;

-- '8' · '5,6,7,8' · '5-8. SINIF' → smallint[]
create or replace function tr_sinif(p text) returns smallint[]
language sql immutable as $$
  select case when coalesce(p, '') = '' then null else (
    select array_agg(distinct x::smallint order by x::smallint)
    from regexp_split_to_table(p, '[^0-9]+') x
    where x <> '' and x::int between 1 and 13
  ) end;
$$;

-- ---------------------------------------------------------------------------
-- BATCH AÇ
-- ---------------------------------------------------------------------------
create or replace function create_import_batch(
  p_store_id uuid, p_tur import_turu,
  p_dosya_adi text default null, p_satir_sayisi integer default 0
) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_tenant uuid; v_id uuid;
begin
  select tenant_id into v_tenant from stores where id = p_store_id;
  if v_tenant is null or v_tenant not in (select auth_tenant_ids()) then
    raise exception 'Bu dükkana yetkiniz yok';
  end if;
  if not auth_has_role(array['isletme_sahibi','dukkan_muduru']::app_role[]) then
    raise exception 'Toplu aktarma için sahip veya müdür olmalısınız';
  end if;

  insert into import_batches (tenant_id, store_id, tur, dosya_adi,
                              satir_sayisi, yapan_user_id)
  values (v_tenant, p_store_id, p_tur, p_dosya_adi, p_satir_sayisi, auth.uid())
  returning id into v_id;
  return v_id;
end $$;

-- ---------------------------------------------------------------------------
-- PARÇA İŞLE
--
-- p_rows: [{"_satir":1, "ad":"...", "barkod":"...", ...}, …]
-- p_politika: 'guncelle' | 'atla' | 'hata'   ← anahtar eşleşince ne yapılacak
-- p_kuru_kosu: true ise hiçbir şey yazılmaz, yalnızca sonuç sayılır
--
-- 24.632 satır tek istekte gönderilemez; istemci 500'erlik parçalar hâlinde
-- aynı batch'e yollar.
-- ---------------------------------------------------------------------------
create or replace function import_chunk(
  p_batch_id uuid,
  p_rows jsonb,
  p_politika text default 'guncelle',
  p_kuru_kosu boolean default false
) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_tenant uuid; v_store uuid; v_tur import_turu; v_durum import_durum;
  r jsonb; v_satir integer;
  v_yeni int := 0; v_guncel int := 0; v_atlanan int := 0; v_hatali int := 0;
  v_hatalar jsonb := '[]'::jsonb;
  v_id uuid; v_pub uuid; v_onceki jsonb; v_islem text; v_tablo text;
  v_sebep text;
begin
  select b.tenant_id, b.store_id, b.tur, b.durum
    into v_tenant, v_store, v_tur, v_durum
  from import_batches b where b.id = p_batch_id;

  if v_tenant is null or v_tenant not in (select auth_tenant_ids()) then
    raise exception 'Aktarma kaydı bulunamadı veya yetkiniz yok';
  end if;
  if v_durum <> 'hazirlaniyor' then
    raise exception 'Bu aktarma zaten sonuçlanmış (%)', v_durum;
  end if;
  if jsonb_array_length(p_rows) > 1000 then
    raise exception 'Tek parçada en fazla 1000 satır gönderilebilir';
  end if;
  if p_politika not in ('guncelle', 'atla', 'hata') then
    raise exception 'Geçersiz çakışma politikası: %', p_politika;
  end if;
  if v_tur in ('deneme_takvimi', 'acilis_bakiyesi') then
    raise exception 'Bu tür henüz desteklenmiyor: %', v_tur;
  end if;

  for r in select * from jsonb_array_elements(p_rows) loop
    v_satir := coalesce((r->>'_satir')::int, 0);
    v_id := null; v_onceki := null; v_islem := null; v_sebep := null;

    begin
      -- ══ ÜRÜN ══════════════════════════════════════════════════════════
      if v_tur = 'urun' then
        v_tablo := 'products';
        if coalesce(trim(r->>'ad'), '') = '' then
          raise exception 'Ürün adı boş';
        end if;

        v_pub := case when coalesce(trim(r->>'yayinevi'), '') = '' then null
                      else upsert_publisher(r->>'yayinevi') end;

        -- Anahtar barkoddur (K24). Barkod yoksa ad+yayınevi ile eşleştirilir,
        -- yoksa aynı dosya iki kez yüklenince katalog ikiye katlanır.
        if coalesce(trim(r->>'barkod'), '') <> '' then
          select id into v_id from products
          where barkod = trim(r->>'barkod') and merged_into_id is null;
        else
          select id into v_id from products
          where merged_into_id is null
            and tenant_id = v_tenant
            and tr_normalize(ad) = tr_normalize(r->>'ad')
            and publisher_id is not distinct from v_pub;
        end if;

        if v_id is not null then
          if p_politika = 'atla' then
            v_atlanan := v_atlanan + 1; continue;
          elsif p_politika = 'hata' then
            raise exception 'Bu ürün katalogda zaten var';
          end if;
          v_islem := 'update';
          if not p_kuru_kosu then
            select to_jsonb(t) into v_onceki from products t where t.id = v_id;
            update products set
              ad            = trim(r->>'ad'),
              publisher_id  = coalesce(v_pub, publisher_id),
              urun_kod      = coalesce(nullif(trim(r->>'urun_kod'), ''), urun_kod),
              kategori      = coalesce(nullif(trim(r->>'kategori'), ''), kategori),
              ders          = coalesce(nullif(trim(r->>'ders'), ''), ders),
              sinav_tipi    = coalesce(nullif(trim(r->>'sinav_tipi'), ''), sinav_tipi),
              sinif         = coalesce(tr_sinif(r->>'sinif'), sinif),
              etiket_fiyat  = coalesce(tr_sayi(r->>'etiket_fiyat'), etiket_fiyat),
              baski_etiketi = coalesce(nullif(trim(r->>'baski_etiketi'), ''), baski_etiketi)
            where id = v_id;
          end if;
          v_guncel := v_guncel + 1;
        else
          v_islem := 'insert';
          if not p_kuru_kosu then
            insert into products (tenant_id, katalog, ad, publisher_id, barkod,
                                  urun_kod, kategori, ders, sinif, sinav_tipi,
                                  etiket_fiyat, baski_etiketi)
            values (v_tenant,
                    coalesce(nullif(trim(r->>'katalog'), ''), 'kitap')::katalog_tipi,
                    trim(r->>'ad'), v_pub,
                    nullif(trim(r->>'barkod'), ''),
                    nullif(trim(r->>'urun_kod'), ''),
                    nullif(trim(r->>'kategori'), ''),
                    nullif(trim(r->>'ders'), ''),
                    tr_sinif(r->>'sinif'),
                    nullif(trim(r->>'sinav_tipi'), ''),
                    tr_sayi(r->>'etiket_fiyat'),
                    nullif(trim(r->>'baski_etiketi'), ''))
            returning id into v_id;
          end if;
          v_yeni := v_yeni + 1;
        end if;

      -- ══ FİYAT & İSKONTO · STOK ════════════════════════════════════════
      elsif v_tur in ('fiyat_iskonto', 'stok') then
        v_tablo := 'store_products';
        select id into v_id from products
        where merged_into_id is null
          and ((coalesce(trim(r->>'barkod'), '') <> '' and barkod = trim(r->>'barkod'))
            or (coalesce(trim(r->>'barkod'), '') = ''
                and coalesce(trim(r->>'urun_kod'), '') <> ''
                and tr_upper(urun_kod) = tr_upper(r->>'urun_kod')))
        limit 1;

        if v_id is null then
          raise exception 'Katalogda bu barkod/ürün kodu yok';
        end if;
        if v_tur = 'fiyat_iskonto'
           and tr_sayi(r->>'varsayilan_iskonto') is not null
           and (tr_sayi(r->>'varsayilan_iskonto') < 0
                or tr_sayi(r->>'varsayilan_iskonto') >= 1) then
          raise exception 'İskonto 0 ile 1 arasında bir oran olmalı (0,20 = %%20)';
        end if;

        declare v_sp uuid;
        begin
          select id into v_sp from store_products
          where store_id = v_store and product_id = v_id;

          if v_sp is not null then
            if p_politika = 'atla' then
              v_atlanan := v_atlanan + 1; continue;
            elsif p_politika = 'hata' then
              raise exception 'Bu ürünün bu dükkanda fiyatı zaten var';
            end if;
            v_islem := 'update';
            if not p_kuru_kosu then
              select to_jsonb(t) into v_onceki from store_products t where t.id = v_sp;
              if v_tur = 'stok' then
                -- C-2 · stok bir SAYAÇTIR: mutabakat anında sıfırdan yazılır.
                update store_products
                  set stok_adedi = coalesce(tr_sayi(r->>'stok_adedi')::int, stok_adedi)
                where id = v_sp;
              else
                update store_products set
                  satis_fiyat = coalesce(tr_sayi(r->>'satis_fiyat'), satis_fiyat),
                  alis_fiyat  = coalesce(tr_sayi(r->>'alis_fiyat'), alis_fiyat),
                  varsayilan_iskonto =
                    coalesce(tr_sayi(r->>'varsayilan_iskonto'), varsayilan_iskonto)
                where id = v_sp;
              end if;
            end if;
            v_guncel := v_guncel + 1;
          else
            v_islem := 'insert';
            if not p_kuru_kosu then
              insert into store_products (store_id, product_id, satis_fiyat,
                                          alis_fiyat, varsayilan_iskonto, stok_adedi)
              values (v_store, v_id, tr_sayi(r->>'satis_fiyat'),
                      tr_sayi(r->>'alis_fiyat'),
                      coalesce(tr_sayi(r->>'varsayilan_iskonto'), 0),
                      coalesce(tr_sayi(r->>'stok_adedi')::int, 0))
              returning id into v_sp;
            end if;
            v_yeni := v_yeni + 1;
          end if;
          v_id := v_sp;
        end;

      -- ══ KURUM ═════════════════════════════════════════════════════════
      elsif v_tur = 'kurum' then
        v_tablo := 'institutions';
        if coalesce(trim(r->>'ad'), '') = '' then
          raise exception 'Kurum adı boş';
        end if;

        -- Anahtar önce MEB kodu, yoksa ad + ilçe (K4 · ortak dizin)
        if coalesce(trim(r->>'meb_kodu'), '') <> '' then
          select id into v_id from institutions
          where meb_kodu = trim(r->>'meb_kodu') and merged_into_id is null;
        else
          select id into v_id from institutions
          where merged_into_id is null
            and tr_normalize(ad) = tr_normalize(r->>'ad')
            and coalesce(tr_upper(ilce), '') = coalesce(tr_upper(r->>'ilce'), '');
        end if;

        if v_id is not null then
          if p_politika = 'atla' then
            v_atlanan := v_atlanan + 1; continue;
          elsif p_politika = 'hata' then
            raise exception 'Bu kurum dizinde zaten var';
          end if;
          v_islem := 'update';
          if not p_kuru_kosu then
            select to_jsonb(t) into v_onceki from institutions t where t.id = v_id;
            update institutions set
              meb_kodu = coalesce(nullif(trim(r->>'meb_kodu'), ''), meb_kodu),
              il       = coalesce(nullif(trim(r->>'il'), ''), il),
              ilce     = coalesce(nullif(trim(r->>'ilce'), ''), ilce),
              tur      = coalesce(nullif(trim(r->>'tur'), ''), tur),
              ogrenci_sayisi = coalesce(tr_sayi(r->>'ogrenci_sayisi')::int, ogrenci_sayisi)
            where id = v_id;
          end if;
          v_guncel := v_guncel + 1;
        else
          v_islem := 'insert';
          if not p_kuru_kosu then
            insert into institutions (ad, kurum_tipi, kademe, tur, il, ilce,
                                      meb_kodu, ogrenci_sayisi, ekleyen_tenant_id)
            values (trim(r->>'ad'),
                    coalesce(nullif(trim(r->>'kurum_tipi'), ''), 'okul')::kurum_tipi,
                    nullif(trim(r->>'kademe'), '')::kademe_tipi,
                    nullif(trim(r->>'tur'), ''),
                    nullif(trim(r->>'il'), ''),
                    nullif(trim(r->>'ilce'), ''),
                    nullif(trim(r->>'meb_kodu'), ''),
                    tr_sayi(r->>'ogrenci_sayisi')::int,
                    v_tenant)
            returning id into v_id;
          end if;
          v_yeni := v_yeni + 1;
        end if;
      end if;

      -- Geri alma günlüğü
      if not p_kuru_kosu and v_islem is not null then
        insert into import_batch_rows (batch_id, satir_no, tablo, kayit_id,
                                       islem, onceki_deger)
        values (p_batch_id, v_satir, v_tablo, v_id, v_islem, v_onceki);
      end if;

    exception when others then
      v_hatali := v_hatali + 1;
      v_sebep := sqlerrm;
      v_hatalar := v_hatalar || jsonb_build_object(
        'satir', v_satir, 'sebep', v_sebep,
        'deger', coalesce(r->>'ad', r->>'barkod', r->>'urun_kod', ''));
      if not p_kuru_kosu then
        insert into import_batch_rows (batch_id, satir_no, tablo, islem, hata)
        values (p_batch_id, v_satir, coalesce(v_tablo, '?'), 'error', v_sebep);
      end if;
    end;
  end loop;

  if not p_kuru_kosu then
    update import_batches set
      eklenen     = eklenen + v_yeni,
      guncellenen = guncellenen + v_guncel,
      hatali      = hatali + v_hatali
    where id = p_batch_id;
  end if;

  return jsonb_build_object(
    'yeni', v_yeni, 'guncelleme', v_guncel,
    'atlanan', v_atlanan, 'hatali', v_hatali,
    'hatalar', v_hatalar);
end $$;

-- ---------------------------------------------------------------------------
-- BATCH KAPAT
-- ---------------------------------------------------------------------------
create or replace function finish_import_batch(p_batch_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_tenant uuid; b import_batches;
begin
  select * into b from import_batches where id = p_batch_id;
  if b.tenant_id is null or b.tenant_id not in (select auth_tenant_ids()) then
    raise exception 'Aktarma kaydı bulunamadı veya yetkiniz yok';
  end if;

  update import_batches set durum = 'onaylandi' where id = p_batch_id;

  insert into audit_logs (tenant_id, user_id, eylem, tablo, kayit_id, detay)
  values (b.tenant_id, auth.uid(), 'import', 'import_batches', p_batch_id,
          jsonb_build_object('tur', b.tur, 'eklenen', b.eklenen,
                             'guncellenen', b.guncellenen, 'hatali', b.hatali));

  return jsonb_build_object('id', p_batch_id, 'tur', b.tur,
                            'eklenen', b.eklenen, 'guncellenen', b.guncellenen,
                            'hatali', b.hatali, 'durum', 'onaylandi');
end $$;

-- ---------------------------------------------------------------------------
-- GERİ AL · insert'i siler, update'i eski hâline döndürür.
-- Sütun listesi katalogdan üretilir; tablo eklendiğinde bu kod değişmez.
-- ---------------------------------------------------------------------------
create or replace function undo_import(p_batch_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_tenant uuid; v_durum import_durum;
  row_ record; v_silinen int := 0; v_geri int := 0; v_sorun jsonb := '[]'::jsonb;
  v_set text;
begin
  select tenant_id, durum into v_tenant, v_durum
  from import_batches where id = p_batch_id;
  if v_tenant is null or v_tenant not in (select auth_tenant_ids()) then
    raise exception 'Aktarma kaydı bulunamadı veya yetkiniz yok';
  end if;
  if not auth_has_role(array['isletme_sahibi','dukkan_muduru']::app_role[]) then
    raise exception 'Geri alma için sahip veya müdür olmalısınız';
  end if;
  if v_durum = 'geri_alindi' then
    raise exception 'Bu aktarma zaten geri alınmış';
  end if;

  -- Sondan başa: sonra eklenen önce silinsin.
  for row_ in
    select * from import_batch_rows
    where batch_id = p_batch_id and kayit_id is not null and islem in ('insert','update')
    order by satir_no desc
  loop
    begin
      if row_.islem = 'insert' then
        execute format('delete from %I where id = $1', row_.tablo) using row_.kayit_id;
        v_silinen := v_silinen + 1;
      else
        select string_agg(format('%I = s.%I', a.attname, a.attname), ', ')
          into v_set
        from pg_attribute a
        where a.attrelid = row_.tablo::regclass
          and a.attnum > 0 and not a.attisdropped;

        execute format(
          'update %I t set %s from jsonb_populate_record(null::%I, $1) s where t.id = $2',
          row_.tablo, v_set, row_.tablo)
        using row_.onceki_deger, row_.kayit_id;
        v_geri := v_geri + 1;
      end if;
    exception when others then
      v_sorun := v_sorun || jsonb_build_object(
        'satir', row_.satir_no, 'tablo', row_.tablo, 'sebep', sqlerrm);
    end;
  end loop;

  update import_batches
    set durum = 'geri_alindi', geri_alindi_at = now()
  where id = p_batch_id;

  insert into audit_logs (tenant_id, user_id, eylem, tablo, kayit_id, detay)
  values (v_tenant, auth.uid(), 'undo_import', 'import_batches', p_batch_id,
          jsonb_build_object('silinen', v_silinen, 'geri_alinan', v_geri));

  return jsonb_build_object('silinen', v_silinen, 'geri_alinan', v_geri,
                            'sorunlar', v_sorun);
end $$;

-- ---------------------------------------------------------------------------
-- GEÇMİŞ + ŞABLONLAR
-- ---------------------------------------------------------------------------
create or replace function list_import_batches(
  p_store_id uuid default null, p_limit integer default 25) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x order by x->>'created_at' desc), '[]'::jsonb)
  from (
    select jsonb_build_object(
      'id', b.id, 'tur', b.tur, 'dosya_adi', b.dosya_adi,
      'satir_sayisi', b.satir_sayisi, 'eklenen', b.eklenen,
      'guncellenen', b.guncellenen, 'hatali', b.hatali,
      'durum', b.durum, 'created_at', b.created_at,
      'geri_alindi_at', b.geri_alindi_at,
      'yapan', p.ad_soyad) as x
    from import_batches b
    left join profiles p on p.id = b.yapan_user_id
    where b.tenant_id in (select auth_tenant_ids())
      and (p_store_id is null or b.store_id = p_store_id)
    order by b.created_at desc
    limit p_limit
  ) t;
$$;

create or replace function import_batch_errors(p_batch_id uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'satir', satir_no, 'hata', hata) order by satir_no), '[]'::jsonb)
  from import_batch_rows
  where batch_id = p_batch_id and islem = 'error'
    and batch_id in (select id from import_batches
                     where tenant_id in (select auth_tenant_ids()));
$$;

create or replace function save_import_template(
  p_tur import_turu, p_ad text, p_eslesme jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_tenant uuid; v_id uuid;
begin
  select tenant_id into v_tenant from memberships
  where user_id = auth.uid() and status = 'aktif' limit 1;
  if v_tenant is null then raise exception 'İşletme üyeliğiniz yok'; end if;

  insert into import_templates (tenant_id, tur, ad, eslesme)
  values (v_tenant, p_tur, trim(p_ad), p_eslesme)
  on conflict (tenant_id, tur, ad) do update set eslesme = excluded.eslesme
  returning id into v_id;
  return v_id;
end $$;

create or replace function list_import_templates(p_tur import_turu default null)
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', id, 'tur', tur, 'ad', ad, 'eslesme', eslesme) order by ad), '[]'::jsonb)
  from import_templates
  where tenant_id in (select auth_tenant_ids())
    and (p_tur is null or tur = p_tur);
$$;

grant execute on function tr_sayi(text) to authenticated, anon;
grant execute on function tr_sinif(text) to authenticated, anon;
grant execute on function create_import_batch(uuid, import_turu, text, integer) to authenticated;
grant execute on function import_chunk(uuid, jsonb, text, boolean) to authenticated;
grant execute on function finish_import_batch(uuid) to authenticated;
grant execute on function undo_import(uuid) to authenticated;
grant execute on function list_import_batches(uuid, integer) to authenticated;
grant execute on function import_batch_errors(uuid) to authenticated;
grant execute on function save_import_template(import_turu, text, jsonb) to authenticated;
grant execute on function list_import_templates(import_turu) to authenticated;
