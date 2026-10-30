-- =============================================================================
-- 0034 · Deneme takvimi (Faz 9)
-- Kararlar: K5 K15 K20 K21 K22 K36 K37 K41 · V4
--
-- K20 · Deneme takvimi bir VERİ KÜMESİDİR, ekran değil. Yılda 267 kalem
-- (ortaokul 91 + lise 176) Excel'den iner; ekran o verinin görünümüdür.
--
-- Omurga STOK TARİHİDİR: 267/267 dolu. Uygulama tarihi yalnızca %55 dolu ve
-- türe bağlı — Türkiye Geneli'nde her zaman var (sabit, kaçırılamaz), Takvim
-- türünde çoğu zaman yok (uygulama gününü kurum seçer). Takvimi uygulama
-- tarihine göre kurmak, kalemlerin yarısını görünmez yapardı.
--
-- V4 · Öğrenci adı/kimliği HİÇBİR ZAMAN tutulmaz. `account_enrollments`
-- yalnızca sınıf başına ADET tutar (K40 ile birlikte kalıcı).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- TÜRKÇE TARİH OKUMA
--
-- Excel'den gelen tarih üç ayrı biçimde çıkabiliyor: `13.11.2025`, ISO metni,
-- ya da Excel'in seri numarası (`45974`). Üçü de aynı sütunda karışık gelir;
-- ayrı ayrı ele almak yerine tek okuyucu.
-- ---------------------------------------------------------------------------
create or replace function tr_tarih(p text) returns date
language plpgsql immutable as $$
declare t text; v_gun int; v_ay int; v_yil int; m text[];
begin
  t := trim(coalesce(p, ''));
  if t = '' then return null; end if;

  -- Excel seri numarası: 1899-12-30 sıfır günüdür.
  if t ~ '^\d{1,6}([.,]0+)?$' then
    return date '1899-12-30' + (split_part(replace(t, ',', '.'), '.', 1))::int;
  end if;

  -- ISO: 2025-11-13
  if t ~ '^\d{4}-\d{1,2}-\d{1,2}' then
    return substring(t from 1 for 10)::date;
  end if;

  -- 13.11.2025 · 13/11/2025 · 13-11-2025
  m := regexp_match(t, '^(\d{1,2})[./-](\d{1,2})[./-](\d{2,4})');
  if m is not null then
    v_gun := m[1]::int; v_ay := m[2]::int; v_yil := m[3]::int;
    if v_yil < 100 then v_yil := 2000 + v_yil; end if;
    return make_date(v_yil, v_ay, v_gun);
  end if;

  -- 13 Kasım 2025
  m := regexp_match(tr_upper(t), '(\d{1,2})\s+([A-ZÇĞİÖŞÜ]+)\s+(\d{4})');
  if m is not null then
    v_ay := tr_ay(m[2]);
    if v_ay is not null then return make_date(m[3]::int, v_ay, m[1]::int); end if;
  end if;

  return null;
exception when others then
  -- Bozuk tarih içeri girmesin; ham metin `uygulama_metin`'de saklanıyor.
  return null;
end $$;

create or replace function tr_ay(p text) returns smallint
language sql immutable as $$
  select case left(tr_upper(trim(coalesce(p, ''))), 3)
    when 'OCA' then 1  when 'ŞUB' then 2  when 'SUB' then 2
    when 'MAR' then 3  when 'NİS' then 4  when 'NIS' then 4
    when 'MAY' then 5  when 'HAZ' then 6  when 'TEM' then 7
    when 'AĞU' then 8  when 'AGU' then 8  when 'EYL' then 9
    when 'EKİ' then 10 when 'EKI' then 10 when 'KAS' then 11
    when 'ARA' then 12 else null end::smallint;
$$;

-- ---------------------------------------------------------------------------
-- UYGULAMA TARİHİ ARALIĞI
--
-- 121 kayıtta uygulama tarihi tek gün DEĞİL aralıktır:
--   '29 Eylül-3 Ekim 2025' · '15-18 OCAK 2026' · '27 Nisan-1 Mayıs 2026'
-- Tek alan bunu karşılayamaz. Ham metin her hâlükârda saklanır: çözülemeyen
-- bir yazım, sessizce boş tarihe dönüşmek yerine olduğu gibi görünür.
-- ---------------------------------------------------------------------------
create or replace function tr_tarih_araligi(p text)
returns table (baslangic date, bitis date)
language plpgsql immutable as $$
declare t text; m text[]; v_yil int; v_ay1 int; v_ay2 int;
begin
  t := trim(coalesce(p, ''));
  if t = '' then return; end if;

  -- '29 Eylül-3 Ekim 2025' — iki ay adı
  m := regexp_match(tr_upper(t),
       '(\d{1,2})\s*([A-ZÇĞİÖŞÜ]+)\s*[-–]\s*(\d{1,2})\s*([A-ZÇĞİÖŞÜ]+)\s*(\d{4})');
  if m is not null then
    v_ay1 := tr_ay(m[2]); v_ay2 := tr_ay(m[4]); v_yil := m[5]::int;
    if v_ay1 is not null and v_ay2 is not null then
      baslangic := make_date(v_yil, v_ay1, m[1]::int);
      bitis     := make_date(v_yil, v_ay2, m[3]::int);
      return next; return;
    end if;
  end if;

  -- '15-18 OCAK 2026' — tek ay adı
  m := regexp_match(tr_upper(t),
       '(\d{1,2})\s*[-–]\s*(\d{1,2})\s*([A-ZÇĞİÖŞÜ]+)\s*(\d{4})');
  if m is not null then
    v_ay1 := tr_ay(m[3]); v_yil := m[4]::int;
    if v_ay1 is not null then
      baslangic := make_date(v_yil, v_ay1, m[1]::int);
      bitis     := make_date(v_yil, v_ay1, m[2]::int);
      return next; return;
    end if;
  end if;

  -- Tek gün
  baslangic := tr_tarih(t);
  bitis := baslangic;
  if baslangic is not null then return next; end if;
end $$;

grant execute on function tr_ay(text) to authenticated, anon;
grant execute on function tr_tarih(text) to authenticated, anon;
grant execute on function tr_tarih_araligi(text) to authenticated, anon;

-- Aynı takvim iki kez yüklenince kalem çiftlenmesin. Doğal anahtar:
-- işletme + ad + stok tarihi. Barkod yok — denemenin barkodu olmaz.
create unique index if not exists deneme_dogal_anahtar
  on deneme_details(product_id);
create index if not exists deneme_details_stok_idx
  on deneme_details(stok_tarihi, deneme_turu);
create index if not exists deneme_details_uygulama_idx
  on deneme_details(uygulama_baslangic) where uygulama_baslangic is not null;

-- ---------------------------------------------------------------------------
-- K49 · İçe aktarma: deneme takvimi
--
-- `import_turu` enum'unda `deneme_takvimi` en baştan vardı ama `import_chunk`
-- içinde dalı yoktu; ekranda seçilebilseydi sessizce hiçbir şey yapmazdı.
-- ---------------------------------------------------------------------------
create or replace function import_deneme_satiri(
  p_tenant uuid, p_period uuid, r jsonb, p_kuru_kosu boolean)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_pub uuid; v_id uuid; v_islem text; v_stok date;
  v_bas date; v_bit date; v_ad text; v_onceki jsonb;
begin
  v_ad := trim(coalesce(r->>'ad', ''));
  if v_ad = '' then raise exception 'Deneme adı boş olamaz'; end if;

  v_stok := tr_tarih(r->>'stok_tarihi');
  if v_stok is null then
    -- Stok tarihi takvimin OMURGASIDIR; tarihsiz kalem takvime giremez.
    raise exception 'Stok tarihi okunamadı: %', coalesce(r->>'stok_tarihi', '(boş)');
  end if;

  select baslangic, bitis into v_bas, v_bit
  from tr_tarih_araligi(r->>'uygulama_tarihi');

  if coalesce(trim(r->>'yayinevi'), '') <> '' then
    v_pub := upsert_publisher(trim(r->>'yayinevi'));
  end if;

  select p.id into v_id
  from products p join deneme_details d on d.product_id = p.id
  where p.tenant_id = p_tenant and p.merged_into_id is null
    and tr_upper(p.ad) = tr_upper(v_ad)
    and d.stok_tarihi = v_stok;

  if v_id is not null then
    v_islem := 'update';
    if not p_kuru_kosu then
      select to_jsonb(t) into v_onceki from deneme_details t where t.product_id = v_id;
      update products set
        publisher_id = coalesce(v_pub, publisher_id),
        sinif = coalesce(tr_sinif(r->>'duzey'), sinif),
        sinav_tipi = coalesce(nullif(trim(r->>'sinav_tipi'), ''), sinav_tipi)
      where id = v_id;
      update deneme_details set
        deneme_turu = coalesce(nullif(trim(r->>'deneme_turu'), ''),
                               deneme_turu::text)::deneme_turu,
        kademe = coalesce(nullif(trim(r->>'kademe'), ''), kademe),
        duzey  = coalesce(nullif(trim(r->>'duzey'), ''), duzey),
        kapsam = coalesce(nullif(trim(r->>'kapsam'), ''), kapsam),
        uygulama_baslangic = coalesce(v_bas, uygulama_baslangic),
        uygulama_bitis = coalesce(v_bit, uygulama_bitis),
        uygulama_metin = coalesce(nullif(trim(r->>'uygulama_tarihi'), ''),
                                  uygulama_metin),
        period_id = coalesce(p_period, period_id)
      where product_id = v_id;
    end if;
  else
    v_islem := 'insert';
    if not p_kuru_kosu then
      -- K15 · Deneme de katalogdadır; ayrı tablo yok.
      insert into products (tenant_id, katalog, ad, publisher_id, sinif,
                            sinav_tipi, kategori)
      values (p_tenant, 'deneme', v_ad, v_pub, tr_sinif(r->>'duzey'),
              nullif(trim(r->>'sinav_tipi'), ''),
              nullif(trim(r->>'kapsam'), ''))
      returning id into v_id;

      insert into deneme_details (product_id, period_id, deneme_turu, kademe,
                                  duzey, kapsam, stok_tarihi,
                                  uygulama_baslangic, uygulama_bitis,
                                  uygulama_metin)
      values (v_id, p_period,
              coalesce(nullif(trim(r->>'deneme_turu'), ''), 'takvim')::deneme_turu,
              nullif(trim(r->>'kademe'), ''),
              nullif(trim(r->>'duzey'), ''),
              nullif(trim(r->>'kapsam'), ''),
              v_stok, v_bas, v_bit,
              nullif(trim(r->>'uygulama_tarihi'), ''));
    end if;
  end if;

  return jsonb_build_object('islem', v_islem, 'id', v_id, 'tablo', 'products',
                            'onceki', v_onceki);
end $$;

grant execute on function import_deneme_satiri(uuid, uuid, jsonb, boolean)
  to authenticated;

-- ---------------------------------------------------------------------------
-- K22 · SINIF MEVCUTLARI
--
-- Kurum bildirir. Girilmezse adet önerisi TIKANMAZ — `suggest_quantity`
-- dört kademeli yedek zincire düşer (0024). Bu tablo o zincirin birinci
-- basamağıdır, tek basamağı değil.
--
-- V4 · Yalnızca ADET. Öğrenci adı/kimliği hiçbir zaman tutulmaz.
-- ---------------------------------------------------------------------------
create or replace function set_enrollments(
  p_account_id uuid, p_items jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a accounts%rowtype; v_period uuid; it jsonb; v_n int := 0;
begin
  select * into a from accounts where id = p_account_id;
  if a.id is null or a.id not in (select auth_visible_accounts()) then
    raise exception 'Cari bulunamadı veya yetkiniz yok';
  end if;
  select id into v_period from periods
  where tenant_id = a.tenant_id and status = 'aktif'
  order by starts_on desc limit 1;
  if v_period is null then raise exception 'Aktif dönem yok'; end if;

  for it in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) loop
    if coalesce((it->>'sinif')::int, 0) not between 1 and 13 then
      raise exception 'Sınıf 1-13 arasında olmalı';
    end if;
    if coalesce((it->>'ogrenci_sayisi')::int, -1) < 0 then
      raise exception 'Öğrenci sayısı negatif olamaz';
    end if;
    -- Sıfır girilirse satır SİLİNİR: "0 öğrenci" ile "bilinmiyor" farkı
    -- önemli — sıfır yazılı kalsaydı yedek zincir devreye girmezdi.
    if (it->>'ogrenci_sayisi')::int = 0 then
      delete from account_enrollments
      where account_id = p_account_id and period_id = v_period
        and sinif = (it->>'sinif')::smallint;
    else
      insert into account_enrollments (account_id, period_id, sinif,
                                       ogrenci_sayisi, bildiren_user_id)
      values (p_account_id, v_period, (it->>'sinif')::smallint,
              (it->>'ogrenci_sayisi')::int, auth.uid())
      on conflict (account_id, period_id, sinif) do update
        set ogrenci_sayisi = excluded.ogrenci_sayisi,
            bildiren_user_id = excluded.bildiren_user_id;
    end if;
    v_n := v_n + 1;
  end loop;

  return jsonb_build_object('kaydedilen', v_n,
    'toplam', coalesce((select sum(ogrenci_sayisi) from account_enrollments
                        where account_id = p_account_id
                          and period_id = v_period), 0));
end $$;

create or replace function get_enrollments(p_account_id uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'siniflar', coalesce((select jsonb_agg(jsonb_build_object(
          'sinif', e.sinif, 'ogrenci_sayisi', e.ogrenci_sayisi,
          'bildiren', pr.ad_soyad, 'tarih', e.created_at)
        order by e.sinif)
      from account_enrollments e
      left join profiles pr on pr.id = e.bildiren_user_id
      join periods p on p.id = e.period_id and p.status = 'aktif'
      where e.account_id = p_account_id), '[]'::jsonb),
    'toplam', coalesce((select sum(e.ogrenci_sayisi) from account_enrollments e
                        join periods p on p.id = e.period_id and p.status = 'aktif'
                        where e.account_id = p_account_id), 0))
  where p_account_id in (select auth_visible_accounts());
$$;

grant execute on function set_enrollments(uuid, jsonb) to authenticated;
grant execute on function get_enrollments(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- TAKVİM
--
-- Eksen değiştirilebilir (`stok` ⇄ `uygulama`) çünkü iki tarih iki farklı
-- soruya cevap veriyor: stok tarihi "kitapçıklar ne zaman dükkanda olacak"
-- (depo ve sipariş planı), uygulama tarihi "sınav kurumda ne zaman yapılacak"
-- (sevkiyat). Aynı ekranda iki ayrı takvim yapmak yerine tek eksen anahtarı.
--
-- Uygulama eksenine geçildiğinde tarihsiz kalemler LİSTEDEN DÜŞMEZ, ayrı
-- toplanır: "uygulama gününü kurum belirler" bir eksiklik değil, bir bilgidir.
-- ---------------------------------------------------------------------------
create or replace function exam_calendar(
  p_store_id uuid,
  p_ay date default null,                 -- ayın herhangi bir günü
  p_eksen text default 'stok',            -- stok | uygulama
  p_kademe text default null,             -- ortaokul | lise
  p_turu deneme_turu default null,
  p_publisher_id uuid default null,
  p_sadece_portfoy boolean default false
) returns jsonb
language sql stable security definer set search_path = public as $$
  with sinir as (
    select date_trunc('month', coalesce(p_ay, current_date))::date as bas,
           (date_trunc('month', coalesce(p_ay, current_date))
            + interval '1 month - 1 day')::date as bit
  ),
  benim_sinif as (
    -- Portföydeki carilerin bildirilmiş sınıfları (K22). Boşsa süzgeç
    -- uygulanmaz — "bilgi yok" ile "eşleşme yok" karıştırılmamalı.
    select array_agg(distinct e.sinif) as siniflar
    from account_enrollments e
    join accounts a on a.id = e.account_id
    join assignments asg on asg.account_id = a.id and asg.aktif
    join periods pe on pe.id = asg.period_id and pe.status = 'aktif'
    where asg.user_id = auth.uid() and a.store_id = p_store_id
  ),
  d as (
    select p.id, p.ad, p.sinif, p.sinav_tipi,
           pub.ad as yayinevi, pub.id as publisher_id,
           dd.deneme_turu, dd.kademe, dd.duzey, dd.kapsam,
           dd.stok_tarihi, dd.uygulama_baslangic, dd.uygulama_bitis,
           dd.uygulama_metin,
           -- K12 · Takvim import'u ürünü açar ama FİYAT açmaz. Fiyatsız
           -- denemeden talep açılamaz; ekran bunu önceden göstermeli.
           (sp.satis_fiyat is not null) as fiyatli,
           case when p_eksen = 'uygulama' then dd.uygulama_baslangic
                else dd.stok_tarihi end as eksen_tarih
    from products p
    join deneme_details dd on dd.product_id = p.id
    left join publishers pub on pub.id = p.publisher_id
    left join store_products sp on sp.product_id = p.id
                               and sp.store_id = p_store_id and sp.aktif
    where p.tenant_id in (select auth_tenant_ids())
      and p.katalog = 'deneme' and not p.arsivlendi and p.merged_into_id is null
      and (p_kademe is null or dd.kademe = p_kademe)
      and (p_turu is null or dd.deneme_turu = p_turu)
      and (p_publisher_id is null or p.publisher_id = p_publisher_id)
      and (not p_sadece_portfoy
           or (select siniflar from benim_sinif) is null
           or p.sinif && (select siniflar from benim_sinif))
  )
  select jsonb_build_object(
    'ay', (select bas from sinir),
    'eksen', p_eksen,
    'gunler', coalesce((select jsonb_agg(g order by g->>'tarih') from (
        select jsonb_build_object(
          'tarih', eksen_tarih,
          'adet', count(*),
          -- Türkiye Geneli takvimde ÇİVİLENMİŞ bir etkinliktir: kaçırılırsa
          -- telafisi yok. Gün hücresi bunu ayrı sayar ki rozet öne çıksın.
          'turkiye_geneli', count(*) filter (where deneme_turu = 'turkiye_geneli'),
          'denemeler', jsonb_agg(jsonb_build_object(
              'id', id, 'ad', ad, 'yayinevi', yayinevi,
              'deneme_turu', deneme_turu, 'duzey', duzey, 'kademe', kademe,
              'kapsam', kapsam, 'sinif', sinif, 'sinav_tipi', sinav_tipi,
              'fiyatli', fiyatli,
              'stok_tarihi', stok_tarihi,
              'uygulama_baslangic', uygulama_baslangic,
              'uygulama_bitis', uygulama_bitis,
              'uygulama_metin', uygulama_metin) order by deneme_turu, ad)) as g
        from d, sinir
        where eksen_tarih between sinir.bas and sinir.bit
        group by eksen_tarih) x), '[]'::jsonb),
    -- Uygulama ekseninde tarihi olmayanlar: eksik değil, "kurum belirler".
    'tarihsiz', case when p_eksen = 'uygulama' then coalesce((
        select jsonb_agg(jsonb_build_object(
            'id', id, 'ad', ad, 'yayinevi', yayinevi,
            'deneme_turu', deneme_turu, 'duzey', duzey,
            'stok_tarihi', stok_tarihi) order by stok_tarihi)
        from d, sinir
        where uygulama_baslangic is null
          and stok_tarihi between sinir.bas and sinir.bit), '[]'::jsonb)
      else '[]'::jsonb end,
    'toplam', (select count(*) from d, sinir
               where eksen_tarih between sinir.bas and sinir.bit))
  where p_store_id in (select auth_store_ids());
$$;

-- Ana sayfa şeridi: yaklaşan stok tarihleri + sabit tarihli Türkiye Geneli.
create or replace function exam_upcoming(
  p_store_id uuid, p_gun integer default 7) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', p.id, 'ad', p.ad, 'yayinevi', pub.ad,
      'deneme_turu', dd.deneme_turu, 'duzey', dd.duzey,
      'stok_tarihi', dd.stok_tarihi,
      'uygulama_baslangic', dd.uygulama_baslangic,
      'uygulama_metin', dd.uygulama_metin,
      'gun', (dd.stok_tarihi - current_date),
      -- Sıralama Türkiye Geneli'ni öne alır: sabit tarihli sınav kaçırılamaz.
      'sabit', dd.deneme_turu in ('turkiye_geneli','resmi_sinav'))
    order by dd.deneme_turu <> 'turkiye_geneli', dd.stok_tarihi), '[]'::jsonb)
  from products p
  join deneme_details dd on dd.product_id = p.id
  left join publishers pub on pub.id = p.publisher_id
  where p.tenant_id in (select auth_tenant_ids())
    and p.katalog = 'deneme' and not p.arsivlendi
    and dd.stok_tarihi between current_date and current_date + p_gun
    and p_store_id in (select auth_store_ids());
$$;

grant execute on function exam_calendar(uuid, date, text, text, deneme_turu, uuid, boolean) to authenticated;
grant execute on function exam_upcoming(uuid, integer) to authenticated;

-- ---------------------------------------------------------------------------
-- "KURUMLARA ÖNER" — ekranın asıl işi
--
-- Bir denemeden tek hamlede çok cariye talep açılır. Üç kural:
--   1. Liste PORTFÖYDEKİ carilerden gelir (K5) — kurumsal ve öğretmen.
--   2. Düzeyi tutmayan cari GÖSTERİLMEZ: 8. sınıf denemesi liseye önerilmez.
--   3. Adet `account_enrollments`'tan otomatik dolar (K22); yoksa dört
--      kademeli yedek zincir devreye girer, öneri hiçbir koşulda tıkanmaz.
-- ---------------------------------------------------------------------------
create or replace function exam_targets(p_product_id uuid, p_store_id uuid)
returns jsonb
language sql stable security definer set search_path = public as $$
  with d as (
    select p.sinif, dd.kademe, dd.duzey
    from products p join deneme_details dd on dd.product_id = p.id
    where p.id = p_product_id
  ),
  benim as (
    select a.id, a.unvan, a.tip, a.balance_cache, a.institution_id, i.ad as kurum_ad,
           i.kademe::text as kurum_kademe
    from accounts a
    join institutions i on i.id = a.institution_id
    join assignments asg on asg.account_id = a.id and asg.aktif
    join periods pe on pe.id = asg.period_id and pe.status = 'aktif'
    where asg.user_id = auth.uid() and a.store_id = p_store_id
      and a.durum = 'aktif'
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'account_id', b.id, 'unvan', b.unvan, 'tip', b.tip,
      'kurum_ad', b.kurum_ad, 'bakiye', b.balance_cache,
      'mevcut', (select sum(e.ogrenci_sayisi) from account_enrollments e
                 join periods pe on pe.id = e.period_id and pe.status = 'aktif'
                 where e.account_id = b.id
                   and ((select sinif from d) is null
                        or (select sinif from d) @> array[e.sinif])),
      'oneri', suggest_quantity(b.id, p_product_id, null))
    order by b.unvan), '[]'::jsonb)
  from benim b
  where p_store_id in (select auth_store_ids())
    -- Kural 2: denemenin sınıfları ile carinin bildirdiği sınıflar kesişmeli.
    -- Cari hiç bildirmemişse GÖSTERİLİR — bildirmemek eşleşmemek değildir.
    and ((select sinif from d) is null
         or not exists (select 1 from account_enrollments e
                        join periods pe on pe.id = e.period_id and pe.status = 'aktif'
                        where e.account_id = b.id)
         or exists (select 1 from account_enrollments e
                    join periods pe on pe.id = e.period_id and pe.status = 'aktif'
                    where e.account_id = b.id
                      and (select sinif from d) @> array[e.sinif]));
$$;

-- "Geçen sefer": aynı yayınevinin bir önceki denemesinde seçilen cari ve
-- adetler. Deneme satışı büyük ölçüde TEKRAR EDEN bir listedir; bu tek düğme
-- ayda yüzlerce dokunuş kazandırır.
create or replace function exam_last_time(p_product_id uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  with bu as (
    select p.publisher_id, dd.stok_tarihi, p.tenant_id
    from products p join deneme_details dd on dd.product_id = p.id
    where p.id = p_product_id
  ),
  onceki as (
    select p.id from products p
    join deneme_details dd on dd.product_id = p.id
    where p.tenant_id = (select tenant_id from bu)
      and p.katalog = 'deneme'
      and p.publisher_id is not distinct from (select publisher_id from bu)
      and dd.stok_tarihi < (select stok_tarihi from bu)
      and exists (select 1 from request_items ri where ri.product_id = p.id)
    order by dd.stok_tarihi desc limit 1
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'account_id', r.account_id, 'adet', ri.adet)), '[]'::jsonb)
  from requests r join request_items ri on ri.request_id = r.id
  where ri.product_id = (select id from onceki)
    and r.account_id in (select auth_visible_accounts());
$$;

-- ---------------------------------------------------------------------------
-- TOPLU TALEP
--
-- Her cari için AYRI bir `request` üretilir. Tek bir çok-carili talep
-- üretmek daha "verimli" görünürdü ama K37'nin kalem bazlı karar makinesini
-- ve K7'nin cari ayrımını birden bozardı: talep tek bir cariye aittir.
-- ---------------------------------------------------------------------------
create or replace function bulk_request_from_exam(
  p_product_id uuid,
  p_items jsonb,                      -- [{account_id, adet}]
  p_istenen_tarih date default null,
  p_not_metni text default null,
  p_client_key text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  it jsonb; v_sonuc jsonb := '[]'::jsonb; v_ad text;
  v_ok int := 0; v_hata int := 0; v_toplam int := 0; v_r jsonb;
begin
  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'En az bir cari seçilmeli';
  end if;
  select ad into v_ad from products where id = p_product_id
    and katalog = 'deneme';
  if v_ad is null then raise exception 'Deneme bulunamadı'; end if;

  for it in select * from jsonb_array_elements(p_items) loop
    begin
      if coalesce((it->>'adet')::int, 0) <= 0 then
        raise exception 'Adet sıfırdan büyük olmalı';
      end if;
      v_r := create_request(
        (it->>'account_id')::uuid,
        jsonb_build_array(jsonb_build_object(
            'product_id', p_product_id, 'adet', (it->>'adet')::int)),
        coalesce(p_not_metni, v_ad), p_istenen_tarih, true,
        case when p_client_key is null then null
             else p_client_key || '-' || (it->>'account_id') end,
        null);
      v_sonuc := v_sonuc || jsonb_build_object(
        'account_id', it->>'account_id', 'durum', 'ok',
        'request_id', v_r->>'id');
      v_ok := v_ok + 1;
      v_toplam := v_toplam + (it->>'adet')::int;
    exception when others then
      -- Bir cari düşerse diğerleri açılmaya devam eder: yarım kalan toplu
      -- işlem, kullanıcının hangi kurumlara talep açıldığını bilmemesi demek.
      v_sonuc := v_sonuc || jsonb_build_object(
        'account_id', it->>'account_id', 'durum', 'hata', 'hata', sqlerrm);
      v_hata := v_hata + 1;
    end;
  end loop;

  return jsonb_build_object('acilan', v_ok, 'hatali', v_hata,
                            'toplam_adet', v_toplam, 'sonuclar', v_sonuc,
                            'deneme', v_ad);
end $$;

-- K41 · Türkiye Geneli denemesi yaklaşıyor → portföy sahibi pazarlamacıya,
-- T-10 gün. Sabit tarihli sınav kaçırılamaz (K20).
create or replace function notify_upcoming_exams(p_gun integer default 10)
returns integer
language plpgsql security definer set search_path = public as $$
declare r record; v_n int := 0;
begin
  for r in
    select p.id, p.ad, p.tenant_id, dd.stok_tarihi, dd.uygulama_baslangic
    from products p join deneme_details dd on dd.product_id = p.id
    where p.katalog = 'deneme' and not p.arsivlendi
      and dd.deneme_turu in ('turkiye_geneli','resmi_sinav')
      and coalesce(dd.uygulama_baslangic, dd.stok_tarihi)
          between current_date and current_date + p_gun
      and not exists (select 1 from notifications n
                      where n.hedef_tur = 'product' and n.hedef_id = p.id
                        and n.olay = 'deneme_yaklasiyor')
  loop
    -- Bildirim PORTFÖY SAHİBİ pazarlamacılara gider (K41), kuruma değil.
    insert into notifications (tenant_id, user_id, olay, baslik, govde,
                               hedef_tur, hedef_id)
    select distinct r.tenant_id, asg.user_id, 'deneme_yaklasiyor',
           'Türkiye Geneli yaklaşıyor: ' || r.ad,
           'Stok ' || to_char(r.stok_tarihi, 'DD.MM.YYYY') ||
           coalesce(' · uygulama ' ||
                    to_char(r.uygulama_baslangic, 'DD.MM.YYYY'), ''),
           'product', r.id
    from assignments asg
    join periods pe on pe.id = asg.period_id and pe.status = 'aktif'
    join accounts a on a.id = asg.account_id and a.tenant_id = r.tenant_id
    where asg.aktif;
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;

grant execute on function exam_targets(uuid, uuid) to authenticated;
grant execute on function exam_last_time(uuid) to authenticated;
grant execute on function bulk_request_from_exam(uuid, jsonb, date, text, text) to authenticated;
grant execute on function notify_upcoming_exams(integer) to authenticated;

-- ---------------------------------------------------------------------------
-- `import_chunk`'a deneme dalı
--
-- Dalın gövdesi ayrı bir fonksiyonda (`import_deneme_satiri`): `import_chunk`
-- zaten 250 satır ve dört dallı; beşinciyi içine yazmak dosyayı okunmaz
-- yapardı. Önizleme/uygulama aynı kod kuralı korunuyor — `p_kuru_kosu`
-- yalnızca yazmayı kapatıyor.
-- ---------------------------------------------------------------------------
create or replace function import_chunk_deneme(
  p_batch_id uuid, p_satirlar jsonb, p_kuru_kosu boolean default false)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  b import_batches%rowtype; r jsonb; v_period uuid;
  v_yeni int := 0; v_guncel int := 0; v_hatali int := 0; v_satir int;
  v_hatalar jsonb := '[]'::jsonb; v_res jsonb;
begin
  select * into b from import_batches where id = p_batch_id;
  if b.id is null then raise exception 'Aktarım bulunamadı'; end if;
  if b.tenant_id not in (select auth_tenant_ids()) then
    raise exception 'Bu aktarım üzerinde yetkiniz yok';
  end if;
  if b.tur <> 'deneme_takvimi' then
    raise exception 'Bu aktarım deneme takvimi değil: %', b.tur;
  end if;

  select id into v_period from periods
  where tenant_id = b.tenant_id and status = 'aktif'
  order by starts_on desc limit 1;

  for r in select * from jsonb_array_elements(p_satirlar) loop
    v_satir := coalesce((r->>'_satir')::int, 0);
    begin
      v_res := import_deneme_satiri(b.tenant_id, v_period, r, p_kuru_kosu);
      if v_res->>'islem' = 'insert' then v_yeni := v_yeni + 1;
      else v_guncel := v_guncel + 1; end if;

      if not p_kuru_kosu then
        insert into import_batch_rows (batch_id, satir_no, tablo, kayit_id,
                                       islem, onceki_deger)
        values (p_batch_id, v_satir, 'products', (v_res->>'id')::uuid,
                v_res->>'islem', v_res->'onceki');
      end if;
    exception when others then
      v_hatali := v_hatali + 1;
      v_hatalar := v_hatalar || jsonb_build_object(
        'satir', v_satir, 'sebep', sqlerrm, 'deger', coalesce(r->>'ad', ''));
      if not p_kuru_kosu then
        insert into import_batch_rows (batch_id, satir_no, tablo, islem, hata)
        values (p_batch_id, v_satir, 'products', 'error', sqlerrm);
      end if;
    end;
  end loop;

  if not p_kuru_kosu then
    update import_batches set
      eklenen = eklenen + v_yeni,
      guncellenen = guncellenen + v_guncel,
      hatali = hatali + v_hatali
    where id = p_batch_id;
  end if;

  return jsonb_build_object('yeni', v_yeni, 'guncelleme', v_guncel,
                            'atlanan', 0, 'hatali', v_hatali,
                            'hatalar', v_hatalar);
end $$;

grant execute on function import_chunk_deneme(uuid, jsonb, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- FİYATSIZ DENEMEDEN TALEP AÇILMAZ
--
-- Takvim import'u ürünü katalogda açar ama FİYAT AÇMAZ (K12: fiyat dükkana
-- özeldir, ayrı bir aktarımla gelir). Fiyatsız üründen açılan talep siparişe
-- dönemez — 20 kuruma toplu talep açıp yirmisinin de sipariş aşamasında
-- düşmesi, tek bir açık hatadan çok daha kötüdür.
--
-- Aynı kural talep ekranında zaten var: ürün araması `fiyat_durumu=fiyatli`
-- süzgeciyle çalışıyor. Takvim yolu o süzgecin dışındaydı.
-- ---------------------------------------------------------------------------
create or replace function bulk_request_from_exam(
  p_product_id uuid,
  p_items jsonb,                      -- [{account_id, adet}]
  p_istenen_tarih date default null,
  p_not_metni text default null,
  p_client_key text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  it jsonb; v_sonuc jsonb := '[]'::jsonb; v_ad text;
  v_ok int := 0; v_hata int := 0; v_toplam int := 0; v_r jsonb;
  v_store uuid; v_fiyat numeric;
begin
  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'En az bir cari seçilmeli';
  end if;
  select ad into v_ad from products where id = p_product_id
    and katalog = 'deneme';
  if v_ad is null then raise exception 'Deneme bulunamadı'; end if;

  -- Seçilen carilerin dükkanında bu denemenin fiyatı var mı?
  select a.store_id into v_store from accounts a
  where a.id = ((p_items->0)->>'account_id')::uuid;
  select sp.satis_fiyat into v_fiyat from store_products sp
  where sp.store_id = v_store and sp.product_id = p_product_id and sp.aktif;
  if v_fiyat is null then
    raise exception 'Bu denemenin dükkanınızda fiyatı yok — fiyatsız üründen '
                    'açılan talep siparişe dönemez. Önce fiyat girin.';
  end if;

  for it in select * from jsonb_array_elements(p_items) loop
    begin
      if coalesce((it->>'adet')::int, 0) <= 0 then
        raise exception 'Adet sıfırdan büyük olmalı';
      end if;
      v_r := create_request(
        (it->>'account_id')::uuid,
        jsonb_build_array(jsonb_build_object(
            'product_id', p_product_id, 'adet', (it->>'adet')::int)),
        coalesce(p_not_metni, v_ad), p_istenen_tarih, true,
        case when p_client_key is null then null
             else p_client_key || '-' || (it->>'account_id') end,
        null);
      v_sonuc := v_sonuc || jsonb_build_object(
        'account_id', it->>'account_id', 'durum', 'ok',
        'request_id', v_r->>'id');
      v_ok := v_ok + 1;
      v_toplam := v_toplam + (it->>'adet')::int;
    exception when others then
      -- Bir cari düşerse diğerleri açılmaya devam eder: yarım kalan toplu
      -- işlem, kullanıcının hangi kurumlara talep açıldığını bilmemesi demek.
      v_sonuc := v_sonuc || jsonb_build_object(
        'account_id', it->>'account_id', 'durum', 'hata', 'hata', sqlerrm);
      v_hata := v_hata + 1;
    end;
  end loop;

  return jsonb_build_object('acilan', v_ok, 'hatali', v_hata,
                            'toplam_adet', v_toplam, 'sonuclar', v_sonuc,
                            'deneme', v_ad);
end $$;

-- Takvim ve şerit, fiyatsız denemeyi İŞARETLER: kullanıcı "Öner" düğmesine
-- basıp reddedilmeyi öğrenmesin.
create or replace function exam_priced(p_product_id uuid, p_store_id uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from store_products sp
                 where sp.store_id = p_store_id
                   and sp.product_id = p_product_id
                   and sp.aktif and sp.satis_fiyat is not null);
$$;

grant execute on function exam_priced(uuid, uuid) to authenticated;
