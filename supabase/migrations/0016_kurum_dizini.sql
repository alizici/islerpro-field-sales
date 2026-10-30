-- =============================================================================
-- 0016 · Kurum dizini: arama, benzerlik kontrolü, detay
-- Kararlar: K4 K18 K30 · Ö-8 (mükerrer kayıt) · A12
-- =============================================================================

-- Arama hızlansın: ad + ilçe üzerinde trigram
create index if not exists institutions_ad_trgm on institutions using gin (ad gin_trgm_ops);
create index if not exists institutions_ilce_idx on institutions (ilce);

-- ---------------------------------------------------------------------------
-- ARAMA · Ortak dizinde (K4) + kendi eklediklerinde
-- ---------------------------------------------------------------------------
create or replace function search_institutions(
  p_q text default null,
  p_il text default null,
  p_ilce text default null,
  p_kurum_tipi kurum_tipi default null,
  p_limit integer default 50
) returns jsonb
language sql stable security definer set search_path = public, extensions as $$
  select coalesce(jsonb_agg(x order by (x->>'benzerlik')::float desc, x->>'ad'), '[]'::jsonb)
  from (
    select jsonb_build_object(
      'id', i.id, 'ad', i.ad, 'kurum_tipi', i.kurum_tipi,
      'kademe', i.kademe, 'tur', i.tur, 'il', i.il, 'ilce', i.ilce,
      'meb_kodu', i.meb_kodu, 'ogrenci_sayisi', i.ogrenci_sayisi,
      'dogrulandi', i.dogrulandi,
      'benzerlik', case when p_q is null then 1
                        else similarity(i.ad, p_q) end,
      -- Bu dükkanla ticari bağı var mı (K4)
      'bagli', exists (select 1 from institution_store_links l
                       where l.institution_id = i.id
                         and l.store_id in (select auth_store_ids())),
      'cari_sayisi', (select count(*) from accounts a
                      where a.institution_id = i.id
                        and a.store_id in (select auth_store_ids()))
    ) as x
    from institutions i
    where i.merged_into_id is null
      and (i.dogrulandi or i.ekleyen_tenant_id in (select auth_tenant_ids()))
      and (p_il is null or i.il = p_il)
      and (p_ilce is null or i.ilce = p_ilce)
      and (p_kurum_tipi is null or i.kurum_tipi = p_kurum_tipi)
      and (p_q is null or p_q = '' or i.ad ilike '%' || p_q || '%'
           or similarity(i.ad, p_q) > 0.2)
    limit p_limit
  ) t;
$$;

-- ---------------------------------------------------------------------------
-- Ö-8 · MÜKERRER KONTROLÜ
-- Kurum eklerken ad + ilçe benzerliğine bakılır; muhtemel eşleşmeler
-- kullanıcıya gösterilir. Dizin ortak olduğu için (K4) mükerrer kayıt
-- yalnızca bu işletmeyi değil herkesi etkiler.
-- ---------------------------------------------------------------------------
create or replace function similar_institutions(p_ad text, p_ilce text default null)
returns jsonb
language sql stable security definer set search_path = public, extensions as $$
  select coalesce(jsonb_agg(x order by (x->>'benzerlik')::float desc), '[]'::jsonb)
  from (
    select jsonb_build_object(
      'id', i.id, 'ad', i.ad, 'ilce', i.ilce, 'kurum_tipi', i.kurum_tipi,
      'dogrulandi', i.dogrulandi,
      'benzerlik', round(similarity(i.ad, p_ad)::numeric, 2)
    ) as x
    from institutions i
    where i.merged_into_id is null
      and (i.dogrulandi or i.ekleyen_tenant_id in (select auth_tenant_ids()))
      and (p_ilce is null or i.ilce is null or i.ilce = p_ilce)
      and similarity(i.ad, p_ad) > 0.35
    limit 5
  ) t;
$$;

-- ---------------------------------------------------------------------------
-- KURUM EKLE · dogrulandi = false başlar, yalnızca ekleyene görünür (Ö-8)
-- ---------------------------------------------------------------------------
create or replace function add_institution(
  p_ad text,
  p_kurum_tipi kurum_tipi,
  p_il text default null,
  p_ilce text default null,
  p_kademe kademe_tipi default null,
  p_tur text default null,
  p_meb_kodu text default null,
  p_ogrenci_sayisi integer default null,
  p_store_id uuid default null
) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_tenant uuid; v_id uuid;
begin
  select tenant_id into v_tenant from memberships
   where user_id = auth.uid() and status = 'aktif' limit 1;
  if v_tenant is null then raise exception 'İşletme üyeliğiniz yok'; end if;
  if p_ad is null or length(trim(p_ad)) < 3 then
    raise exception 'Kurum adı en az 3 karakter olmalı';
  end if;

  insert into institutions (ad, kurum_tipi, il, ilce, kademe, tur, meb_kodu,
                            ogrenci_sayisi, dogrulandi, ekleyen_tenant_id)
  values (trim(p_ad), p_kurum_tipi, p_il, p_ilce,
          case when p_kurum_tipi = 'okul' then p_kademe end,
          p_tur, nullif(trim(coalesce(p_meb_kodu,'')), ''),
          p_ogrenci_sayisi, false, v_tenant)
  returning id into v_id;

  -- Dükkan belirtildiyse ticari bağı da kur (K4)
  if p_store_id is not null then
    insert into institution_store_links (institution_id, store_id)
    values (v_id, p_store_id) on conflict do nothing;
  end if;

  insert into audit_logs (tenant_id, user_id, eylem, tablo, kayit_id, detay)
  values (v_tenant, auth.uid(), 'add_institution', 'institutions', v_id,
          jsonb_build_object('ad', p_ad, 'ilce', p_ilce));

  return jsonb_build_object('id', v_id);
end $$;

-- Kurumu bu dükkanla ilişkilendir / ilişkiyi kaldır
create or replace function link_institution(p_institution_id uuid, p_store_id uuid,
                                            p_bagla boolean default true)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_store_id not in (select auth_store_ids()) then
    raise exception 'Bu dükkana yetkiniz yok';
  end if;
  if p_bagla then
    insert into institution_store_links (institution_id, store_id)
    values (p_institution_id, p_store_id)
    on conflict (institution_id, store_id) do update set aktif = true;
  else
    update institution_store_links set aktif = false
     where institution_id = p_institution_id and store_id = p_store_id;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- KURUM DETAYI · cariler, kişiler, zincir (K5 · K18 · K30)
-- ---------------------------------------------------------------------------
create or replace function institution_detail(p_id uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'kurum', (select jsonb_build_object(
        'id', i.id, 'ad', i.ad, 'kurum_tipi', i.kurum_tipi, 'kademe', i.kademe,
        'tur', i.tur, 'il', i.il, 'ilce', i.ilce, 'adres', i.adres,
        'meb_kodu', i.meb_kodu, 'ogrenci_sayisi', i.ogrenci_sayisi,
        'dogrulandi', i.dogrulandi, 'parent_id', i.parent_id)
      from institutions i where i.id = p_id),
    -- K18 · kurum zinciri (merkez + şubeler)
    'subeler', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'ad', c.ad))
      from institutions c where c.parent_id = p_id and c.merged_into_id is null), '[]'::jsonb),
    -- K5 · aynı kurumdaki tüm cariler. K7 gereği bakiyeler TOPLANMAZ.
    'cariler', coalesce((select jsonb_agg(jsonb_build_object(
        'id', a.id, 'tip', a.tip, 'unvan', a.unvan,
        'bakiye', a.balance_cache, 'limit', a.credit_limit, 'durum', a.durum,
        'portfoy_sahibi', (select p.ad_soyad from assignments asg
                           join profiles p on p.id = asg.user_id
                           join periods pe on pe.id = asg.period_id
                           where asg.account_id = a.id and asg.aktif
                             and pe.status = 'aktif' limit 1)))
      from accounts a
      where a.institution_id = p_id
        and a.store_id in (select auth_store_ids())), '[]'::jsonb),
    -- K30 · kişiler yalnızca kendi işletmesine görünür
    'kisiler', coalesce((select jsonb_agg(jsonb_build_object(
        'id', c.id, 'ad_soyad', c.ad_soyad, 'telefon', c.telefon,
        'brans', c.brans, 'gorev', c.gorev, 'hesabi_var', c.user_id is not null))
      from institution_contacts c
      where c.institution_id = p_id
        and c.tenant_id in (select auth_tenant_ids()) and c.aktif), '[]'::jsonb)
  );
$$;

-- İl/ilçe listesi — filtre açılırları için
create or replace function institution_regions() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x order by x->>'il', x->>'ilce'), '[]'::jsonb) from (
    select distinct jsonb_build_object('il', il, 'ilce', ilce) as x
    from institutions
    where merged_into_id is null and il is not null
      and (dogrulandi or ekleyen_tenant_id in (select auth_tenant_ids()))
  ) t;
$$;

grant execute on function search_institutions, similar_institutions, add_institution,
  link_institution, institution_detail, institution_regions to authenticated;
