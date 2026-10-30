-- =============================================================================
-- 0022 · Cari yönetimi ve portföy atama (Faz 2)
-- Kararlar: K5 K6 K7 K11 K19 K25 K29 · W-2
--
-- K7 BU DOSYANIN EN ÖNEMLİ KURALIDIR: hiçbir fonksiyon kurum düzeyinde
-- bakiye/risk TOPLAMI döndürmez. Kurumsal cari ile öğretmen carisi ayrı
-- satırlardır ve asla toplanmaz. Okulun temiz carisi, bir öğretmenin
-- gecikmesi yüzünden limit aşımına düşmemelidir.
-- =============================================================================

create index if not exists accounts_unvan_trgm
  on accounts using gin (unvan gin_trgm_ops);

-- ---------------------------------------------------------------------------
-- ARAMA · Cari + kurum bağlamı + portföy sahibi, tek satırda
-- ---------------------------------------------------------------------------
create or replace function search_accounts(
  p_store_id uuid,
  p_q text default null,
  p_tip account_tipi default null,
  p_durum account_durum default null,
  p_pazarlamaci uuid default null,        -- portföy sahibi süzgeci
  p_atanmamis boolean default false,      -- portföyü olmayanlar
  p_borclu boolean default false,         -- bakiyesi sıfırdan farklı olanlar
  p_period_id uuid default null,
  p_limit integer default 50,
  p_offset integer default 0
) returns jsonb
language sql stable security definer set search_path = public, extensions as $$
  select coalesce(jsonb_agg(x order by (x->>'skor')::float desc, x->>'unvan'), '[]'::jsonb)
  from (
    select jsonb_build_object(
      'id', a.id, 'tip', a.tip, 'unvan', a.unvan, 'durum', a.durum,
      'institution_id', a.institution_id, 'kurum_ad', i.ad, 'ilce', i.ilce,
      'discount_tier', a.discount_tier,
      'credit_limit', a.credit_limit,
      -- K29 · türetilmiş; bu alan yalnızca OKUNUR
      'bakiye', a.balance_cache,
      -- K11 · limit kontrolü toplam riske bakar (bakiye + vadesi gelmemiş çek)
      'risk', account_total_risk(a.id),
      'limit_asildi', a.credit_limit > 0 and account_total_risk(a.id) > a.credit_limit,
      'pazarlamaci_id', asg.user_id,
      'pazarlamaci', pr.ad_soyad,
      'skor', case when p_q is null or p_q = '' then 0
                   else greatest(similarity(a.unvan, p_q),
                                 similarity(coalesce(i.ad, ''), p_q)) end
    ) as x
    from accounts a
    join institutions i on i.id = a.institution_id
    left join lateral (
      select s.user_id from assignments s
      where s.account_id = a.id and s.aktif
        and (p_period_id is null or s.period_id = p_period_id)
      order by s.created_at desc limit 1
    ) asg on true
    left join profiles pr on pr.id = asg.user_id
    where a.store_id = p_store_id
      and a.id in (select auth_visible_accounts())
      and (p_tip is null or a.tip = p_tip)
      and (p_durum is null or a.durum = p_durum)
      and (p_pazarlamaci is null or asg.user_id = p_pazarlamaci)
      and (not p_atanmamis or asg.user_id is null)
      and (not p_borclu or a.balance_cache <> 0)
      and (p_q is null or p_q = ''
           or a.unvan ilike '%' || p_q || '%'
           or i.ad ilike '%' || p_q || '%'
           or similarity(a.unvan, p_q) > 0.2)
    limit p_limit offset p_offset
  ) t;
$$;

create or replace function count_accounts(
  p_store_id uuid, p_q text default null, p_tip account_tipi default null,
  p_durum account_durum default null, p_pazarlamaci uuid default null,
  p_atanmamis boolean default false, p_borclu boolean default false,
  p_period_id uuid default null
) returns integer
language sql stable security definer set search_path = public, extensions as $$
  select count(*)::integer
  from accounts a
  join institutions i on i.id = a.institution_id
  left join lateral (
    select s.user_id from assignments s
    where s.account_id = a.id and s.aktif
      and (p_period_id is null or s.period_id = p_period_id)
    order by s.created_at desc limit 1
  ) asg on true
  where a.store_id = p_store_id
    and a.id in (select auth_visible_accounts())
    and (p_tip is null or a.tip = p_tip)
    and (p_durum is null or a.durum = p_durum)
    and (p_pazarlamaci is null or asg.user_id = p_pazarlamaci)
    and (not p_atanmamis or asg.user_id is null)
    and (not p_borclu or a.balance_cache <> 0)
    and (p_q is null or p_q = ''
         or a.unvan ilike '%' || p_q || '%'
         or i.ad ilike '%' || p_q || '%'
         or similarity(a.unvan, p_q) > 0.2);
$$;

-- ---------------------------------------------------------------------------
-- CARİ AÇMA · K5 · Öğretmen carisi uygulama hesabı OLMADAN da açılabilir.
-- ---------------------------------------------------------------------------
create or replace function create_account(
  p_store_id uuid,
  p_institution_id uuid,
  p_tip account_tipi,
  p_unvan text,
  p_contact_id uuid default null,
  p_user_id uuid default null,
  p_discount_tier text default null,
  p_credit_limit numeric default 0,
  p_invoice_title text default null,
  p_tax_id text default null,
  p_tax_office text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_tenant uuid; v_id uuid;
begin
  if coalesce(trim(p_unvan), '') = '' then
    raise exception 'Cari unvanı boş olamaz';
  end if;
  select tenant_id into v_tenant from stores where id = p_store_id;
  if v_tenant is null or v_tenant not in (select auth_tenant_ids()) then
    raise exception 'Bu dükkana yetkiniz yok';
  end if;
  if not auth_has_role(array['isletme_sahibi','dukkan_muduru','pazarlamaci']::app_role[]) then
    raise exception 'Cari açma yetkiniz yok';
  end if;
  if p_tip = 'ogretmen' and p_contact_id is null and p_user_id is null then
    raise exception 'Öğretmen carisi bir kişi kaydına bağlanmalı';
  end if;
  -- Aynı kurumda aynı unvanla ikinci cari uyarısı yerine engelleme:
  -- mükerrer cari, bakiyeyi ikiye böler ve ikisi de yanlış görünür.
  if exists (select 1 from accounts
             where store_id = p_store_id and institution_id = p_institution_id
               and tr_normalize(unvan) = tr_normalize(p_unvan)
               and durum <> 'kapali') then
    raise exception 'Bu kurumda aynı unvanla açık bir cari zaten var';
  end if;

  insert into accounts (tenant_id, store_id, tip, institution_id,
                        institution_contact_id, user_id, unvan,
                        discount_tier, credit_limit,
                        invoice_title, tax_id, tax_office)
  values (v_tenant, p_store_id, p_tip, p_institution_id,
          p_contact_id, p_user_id, trim(p_unvan),
          nullif(trim(coalesce(p_discount_tier, '')), ''),
          coalesce(p_credit_limit, 0),
          nullif(trim(coalesce(p_invoice_title, '')), ''),
          nullif(trim(coalesce(p_tax_id, '')), ''),
          nullif(trim(coalesce(p_tax_office, '')), ''))
  returning id into v_id;

  -- Kurumun bu dükkanla bağı yoksa aç (K4)
  insert into institution_store_links (institution_id, store_id)
  values (p_institution_id, p_store_id)
  on conflict (institution_id, store_id) do nothing;

  insert into audit_logs (tenant_id, user_id, eylem, tablo, kayit_id, detay)
  values (v_tenant, auth.uid(), 'create_account', 'accounts', v_id,
          jsonb_build_object('tip', p_tip, 'unvan', trim(p_unvan)));

  return jsonb_build_object('id', v_id);
end $$;

create or replace function update_account(
  p_account_id uuid,
  p_unvan text default null,
  p_discount_tier text default null,
  p_credit_limit numeric default null,
  p_invoice_title text default null,
  p_tax_id text default null,
  p_tax_office text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_tenant uuid;
begin
  select tenant_id into v_tenant from accounts where id = p_account_id;
  if v_tenant is null or v_tenant not in (select auth_tenant_ids()) then
    raise exception 'Cari bulunamadı veya yetkiniz yok';
  end if;
  if p_credit_limit is not null and p_credit_limit < 0 then
    raise exception 'Kredi limiti negatif olamaz';
  end if;
  -- K25 · kademe ticari bir anlaşmadır; pazarlamacı tek başına değiştiremez.
  if p_discount_tier is not null
     and not auth_has_role(array['isletme_sahibi','dukkan_muduru']::app_role[]) then
    raise exception 'İskonto kademesini yalnızca sahip veya müdür değiştirebilir';
  end if;
  if p_credit_limit is not null
     and not auth_has_role(array['isletme_sahibi','dukkan_muduru']::app_role[]) then
    raise exception 'Kredi limitini yalnızca sahip veya müdür değiştirebilir';
  end if;

  update accounts set
    unvan         = coalesce(nullif(trim(coalesce(p_unvan, '')), ''), unvan),
    discount_tier = case when p_discount_tier is null then discount_tier
                         else nullif(trim(p_discount_tier), '') end,
    credit_limit  = coalesce(p_credit_limit, credit_limit),
    invoice_title = coalesce(nullif(trim(coalesce(p_invoice_title, '')), ''), invoice_title),
    tax_id        = coalesce(nullif(trim(coalesce(p_tax_id, '')), ''), tax_id),
    tax_office    = coalesce(nullif(trim(coalesce(p_tax_office, '')), ''), tax_office)
  where id = p_account_id;

  insert into audit_logs (tenant_id, user_id, eylem, tablo, kayit_id, detay)
  values (v_tenant, auth.uid(), 'update_account', 'accounts', p_account_id,
          jsonb_build_object('kademe', p_discount_tier, 'limit', p_credit_limit));

  return jsonb_build_object('id', p_account_id);
end $$;

-- K6 · "Cari asla silinmez." Bakiye varsa pasif değil TAHSİLATTA olur.
create or replace function set_account_status(
  p_account_id uuid, p_durum account_durum) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_tenant uuid; v_bakiye numeric; v_hedef account_durum;
begin
  select tenant_id, balance_cache into v_tenant, v_bakiye
  from accounts where id = p_account_id;
  if v_tenant is null or v_tenant not in (select auth_tenant_ids()) then
    raise exception 'Cari bulunamadı veya yetkiniz yok';
  end if;
  if not auth_has_role(array['isletme_sahibi','dukkan_muduru']::app_role[]) then
    raise exception 'Cari durumunu yalnızca sahip veya müdür değiştirebilir';
  end if;

  v_hedef := p_durum;
  -- Bakiyesi olan cari 'pasif' yapılırsa borç gözden kaybolur; 'tahsilatta'ya
  -- çevriliyor ki tahsilat listelerinde kalsın.
  if p_durum = 'pasif' and v_bakiye <> 0 then
    v_hedef := 'tahsilatta';
  end if;
  if p_durum = 'kapali' and v_bakiye <> 0 then
    raise exception 'Bakiyesi % ₺ olan cari kapatılamaz. Önce hesabı kapatın.',
      round(v_bakiye, 2);
  end if;

  update accounts set durum = v_hedef where id = p_account_id;
  if v_hedef <> 'aktif' then
    update assignments set aktif = false where account_id = p_account_id and aktif;
  end if;

  insert into audit_logs (tenant_id, user_id, eylem, tablo, kayit_id, detay)
  values (v_tenant, auth.uid(), 'account_status', 'accounts', p_account_id,
          jsonb_build_object('istenen', p_durum, 'uygulanan', v_hedef,
                             'bakiye', v_bakiye));

  return jsonb_build_object('durum', v_hedef, 'istenen', p_durum,
                            'bakiye', v_bakiye);
end $$;

-- ---------------------------------------------------------------------------
-- DETAY · K7 · Kardeş cariler LİSTELENİR ama TOPLANMAZ.
-- ---------------------------------------------------------------------------
create or replace function account_detail(p_account_id uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', a.id, 'tip', a.tip, 'unvan', a.unvan, 'durum', a.durum,
    'kurum', jsonb_build_object('id', i.id, 'ad', i.ad, 'ilce', i.ilce,
                                'kurum_tipi', i.kurum_tipi),
    'discount_tier', a.discount_tier,
    'credit_limit', a.credit_limit,
    'bakiye', calc_account_balance(a.id),
    'risk', account_total_risk(a.id),
    'acik_konsinye', open_consignment(a.id),
    'invoice_title', a.invoice_title, 'tax_id', a.tax_id,
    'tax_office', a.tax_office,
    'kisi', (select jsonb_build_object('ad_soyad', c.ad_soyad, 'telefon', c.telefon,
                                       'brans', c.brans)
             from institution_contacts c where c.id = a.institution_contact_id),
    'portfoy', coalesce((
      select jsonb_agg(jsonb_build_object(
               'user_id', s.user_id, 'ad_soyad', pr.ad_soyad,
               'period_id', s.period_id, 'period_ad', p.ad, 'aktif', s.aktif)
             order by p.starts_on desc)
      from assignments s
      join profiles pr on pr.id = s.user_id
      join periods p on p.id = s.period_id
      where s.account_id = a.id), '[]'::jsonb),
    -- K6 · taşıma günlüğü; hiçbir hareket silinmez
    'tasimalar', coalesce((
      select jsonb_agg(jsonb_build_object(
               'tarih', t.created_at, 'gerekce', t.gerekce,
               'nereden', fi.ad, 'nereye', ti.ad)
             order by t.created_at desc)
      from account_transfers t
      join institutions fi on fi.id = t.from_institution_id
      join institutions ti on ti.id = t.to_institution_id
      where t.account_id = a.id), '[]'::jsonb),
    -- K7 · aynı kurumdaki DİĞER cariler. Ayrı satırlar, TOPLAM YOK.
    'kardes_cariler', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', k.id, 'tip', k.tip, 'unvan', k.unvan,
               'bakiye', k.balance_cache, 'durum', k.durum))
      from accounts k
      where k.institution_id = a.institution_id and k.id <> a.id
        and k.store_id = a.store_id
        and k.id in (select auth_visible_accounts())), '[]'::jsonb)
  )
  from accounts a
  join institutions i on i.id = a.institution_id
  where a.id = p_account_id and a.id in (select auth_visible_accounts());
$$;

-- ---------------------------------------------------------------------------
-- PORTFÖY · Toplu atama. Saha gerçeği: 300 cari tek tek atanmaz.
-- ---------------------------------------------------------------------------
create or replace function assign_accounts(
  p_account_ids uuid[], p_user_id uuid, p_period_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_tenant uuid; v_store uuid; v_n int := 0; v_devir int := 0;
begin
  if not auth_has_role(array['isletme_sahibi','dukkan_muduru']::app_role[]) then
    raise exception 'Portföy atamasını yalnızca sahip veya müdür yapabilir';
  end if;
  if p_user_id is not null and not exists (
       select 1 from memberships m
       where m.user_id = p_user_id and m.status = 'aktif'
         and m.tenant_id in (select auth_tenant_ids())) then
    raise exception 'Bu kullanıcı işletmenizin aktif üyesi değil';
  end if;

  -- Önce mevcut atamaları kapat (bir cari bir dönemde tek pazarlamacıya ait)
  update assignments set aktif = false
  where period_id = p_period_id and aktif
    and account_id = any(p_account_ids)
    and account_id in (select id from accounts where tenant_id in (select auth_tenant_ids()));
  get diagnostics v_devir = row_count;

  if p_user_id is not null then
    insert into assignments (account_id, store_id, user_id, period_id, aktif)
    select a.id, a.store_id, p_user_id, p_period_id, true
    from accounts a
    where a.id = any(p_account_ids)
      and a.tenant_id in (select auth_tenant_ids())
      and a.durum = 'aktif'
    on conflict (account_id, period_id, user_id)
      do update set aktif = true;
    get diagnostics v_n = row_count;
  end if;

  select tenant_id into v_tenant from accounts where id = p_account_ids[1];
  insert into audit_logs (tenant_id, user_id, eylem, tablo, kayit_id, detay)
  values (v_tenant, auth.uid(), 'assign_accounts', 'assignments', null,
          jsonb_build_object('user_id', p_user_id, 'period_id', p_period_id,
                             'atanan', v_n, 'devralinan', v_devir));

  return jsonb_build_object('atanan', v_n, 'devralinan', v_devir);
end $$;

create or replace function portfolio_summary(
  p_store_id uuid, p_period_id uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'pazarlamacilar', coalesce((
      select jsonb_agg(jsonb_build_object(
               'user_id', pr.id, 'ad_soyad', pr.ad_soyad,
               'cari_sayisi', c.n, 'bakiye', c.b) order by pr.ad_soyad)
      from profiles pr
      join lateral (
        select count(*) as n, coalesce(sum(a.balance_cache), 0) as b
        from assignments s
        join accounts a on a.id = s.account_id
        where s.user_id = pr.id and s.period_id = p_period_id and s.aktif
          and a.store_id = p_store_id
      ) c on true
      where c.n > 0), '[]'::jsonb),
    -- Atanmamış cari = kimsenin gelen kutusuna düşmeyen talep (W-2)
    'atanmamis', (
      select count(*) from accounts a
      where a.store_id = p_store_id and a.durum = 'aktif'
        and not exists (select 1 from assignments s
                        where s.account_id = a.id and s.period_id = p_period_id
                          and s.aktif))
  )
  where p_store_id in (select auth_store_ids());
$$;

-- ---------------------------------------------------------------------------
-- K6 · CARİ TAŞIMA
-- Kapılar önce gösterilir, sonra uygulanır — dükkan pasifleştirmeyle aynı desen.
-- ---------------------------------------------------------------------------
create or replace function transfer_account_check(p_account_id uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'acik_konsinye', open_consignment(p_account_id),
    'sevk_edilmemis_siparis', (
      select count(*) from orders o
      where o.account_id = p_account_id
        and o.durum in ('olusturuldu','onay_bekliyor','hazirlaniyor','hazir')),
    'bakiye', calc_account_balance(p_account_id),
    'kurum_ad', (select i.ad from accounts a
                 join institutions i on i.id = a.institution_id
                 where a.id = p_account_id)
  )
  where p_account_id in (select auth_visible_accounts());
$$;

create or replace function transfer_account(
  p_account_id uuid, p_to_institution_id uuid, p_gerekce text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_tenant uuid; v_store uuid; v_from uuid; v_konsinye numeric; v_siparis int;
begin
  select tenant_id, store_id, institution_id into v_tenant, v_store, v_from
  from accounts where id = p_account_id;
  if v_tenant is null or v_tenant not in (select auth_tenant_ids()) then
    raise exception 'Cari bulunamadı veya yetkiniz yok';
  end if;
  if not auth_has_role(array['isletme_sahibi','dukkan_muduru']::app_role[]) then
    raise exception 'Cari taşımayı yalnızca sahip veya müdür yapabilir. '
                    'Pazarlamacı yalnızca taşıma talebi açabilir.';
  end if;
  if coalesce(trim(p_gerekce), '') = '' then
    raise exception 'Taşıma gerekçesi zorunludur';
  end if;
  if v_from = p_to_institution_id then
    raise exception 'Cari zaten bu kurumda';
  end if;

  -- Kapı 1 · açık konsinye. Kitaplar fiziken eski okulda; taşımadan önce
  -- satıldı/iade kaydı girilmeli.
  v_konsinye := open_consignment(p_account_id);
  if v_konsinye > 0 then
    raise exception 'Açık konsinye var (% adet). Taşımadan önce satıldı/iade kaydı girilmeli.',
      v_konsinye;
  end if;

  -- Kapı 2 · sevk edilmemiş sipariş
  select count(*) into v_siparis from orders o
  where o.account_id = p_account_id
    and o.durum in ('olusturuldu','onay_bekliyor','hazirlaniyor','hazir');
  if v_siparis > 0 then
    raise exception 'Sevk edilmemiş % sipariş var. Önce sevk edin veya iptal edin.',
      v_siparis;
  end if;

  -- Kurumun bu dükkanla bağı yoksa açılır
  insert into institution_store_links (institution_id, store_id)
  values (p_to_institution_id, v_store)
  on conflict (institution_id, store_id) do nothing;

  -- Bakiye taşınır; GEÇMİŞ HAREKETLER eski kurumda kalır çünkü orders/shipments
  -- kendi institution_id snapshot'ını taşır (K6).
  update accounts set institution_id = p_to_institution_id where id = p_account_id;

  insert into account_transfers (account_id, from_institution_id,
                                 to_institution_id, gerekce, yapan_user_id)
  values (p_account_id, v_from, p_to_institution_id, trim(p_gerekce), auth.uid());

  insert into audit_logs (tenant_id, user_id, eylem, tablo, kayit_id, detay)
  values (v_tenant, auth.uid(), 'transfer_account', 'accounts', p_account_id,
          jsonb_build_object('from', v_from, 'to', p_to_institution_id,
                             'gerekce', trim(p_gerekce)));

  return jsonb_build_object('id', p_account_id, 'from', v_from,
                            'to', p_to_institution_id);
end $$;

grant execute on function search_accounts(uuid, text, account_tipi, account_durum, uuid, boolean, boolean, uuid, integer, integer) to authenticated;
grant execute on function count_accounts(uuid, text, account_tipi, account_durum, uuid, boolean, boolean, uuid) to authenticated;
grant execute on function create_account(uuid, uuid, account_tipi, text, uuid, uuid, text, numeric, text, text, text) to authenticated;
grant execute on function update_account(uuid, text, text, numeric, text, text, text) to authenticated;
grant execute on function set_account_status(uuid, account_durum) to authenticated;
grant execute on function account_detail(uuid) to authenticated;
grant execute on function assign_accounts(uuid[], uuid, uuid) to authenticated;
grant execute on function portfolio_summary(uuid, uuid) to authenticated;
grant execute on function transfer_account_check(uuid) to authenticated;
grant execute on function transfer_account(uuid, uuid, text) to authenticated;
