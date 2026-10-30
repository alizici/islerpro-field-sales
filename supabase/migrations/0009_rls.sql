-- =============================================================================
-- 0009 · Satır düzeyi güvenlik (RLS)
-- Yetki kuralı: her sorgu tenant_id ile filtrelenir; pazarlamacı ek olarak
-- assignments'taki CARİ listesiyle sınırlanır; öğretmen kendi carisini görür.
-- Kararlar: K4 K5 K9 K19 K30
-- =============================================================================

-- ---- Yardımcı fonksiyonlar ------------------------------------------------
create or replace function auth_tenant_ids() returns setof uuid
language sql stable security definer set search_path = public as $$
  select distinct tenant_id from memberships
  where user_id = auth.uid() and status = 'aktif';
$$;

create or replace function auth_store_ids() returns setof uuid
language sql stable security definer set search_path = public as $$
  -- store_id NULL olan üyelik (sahip) → tenant'ın TÜM dükkanları
  select s.id from stores s
  where s.tenant_id in (select tenant_id from memberships
                        where user_id = auth.uid() and status='aktif' and store_id is null)
  union
  select store_id from memberships
  where user_id = auth.uid() and status = 'aktif' and store_id is not null;
$$;

create or replace function auth_has_role(p_roles app_role[]) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from memberships
                 where user_id = auth.uid() and status='aktif' and role = any(p_roles));
$$;

-- Pazarlamacının portföyündeki cariler (aktif dönem)
create or replace function auth_assigned_accounts() returns setof uuid
language sql stable security definer set search_path = public as $$
  select a.account_id from assignments a
  join periods p on p.id = a.period_id
  where a.user_id = auth.uid() and a.aktif and p.status <> 'kapali';
$$;

-- Öğretmenin kendi carileri (K19: birden çok olabilir)
create or replace function auth_own_accounts() returns setof uuid
language sql stable security definer set search_path = public as $$
  select ac.id from accounts ac
  where ac.user_id = auth.uid()
  union
  -- kurum adına yetkiliyse kurumsal cari de görünür (K3)
  select ac.id from accounts ac
  join institution_memberships im
    on im.institution_id = ac.institution_id and im.user_id = auth.uid()
  where ac.tip = 'kurum' and im.can_order_for_institution and im.status = 'aktif';
$$;

-- Kullanıcının erişebildiği TÜM cariler
create or replace function auth_visible_accounts() returns setof uuid
language sql stable security definer set search_path = public as $$
  select id from accounts where store_id in (select auth_store_ids())
    and auth_has_role(array['isletme_sahibi','dukkan_muduru','hazirlik']::app_role[])
  union
  select auth_assigned_accounts()
  union
  select auth_own_accounts();
$$;

-- ---- Politikalar ----------------------------------------------------------
alter table profiles      enable row level security;
drop policy if exists p_self on profiles;
create policy p_self on profiles for select using (id = auth.uid());
drop policy if exists p_self_upd on profiles;
create policy p_self_upd on profiles for update using (id = auth.uid());

alter table tenants enable row level security;
drop policy if exists t_read on tenants;
create policy t_read on tenants for select using (id in (select auth_tenant_ids()));

alter table stores enable row level security;
drop policy if exists s_read on stores;
create policy s_read on stores for select using (tenant_id in (select auth_tenant_ids()));

alter table memberships enable row level security;
drop policy if exists m_read on memberships;
create policy m_read on memberships for select
  using (user_id = auth.uid() or tenant_id in (select auth_tenant_ids()));

alter table periods enable row level security;
drop policy if exists pr_read on periods;
create policy pr_read on periods for select using (tenant_id in (select auth_tenant_ids()));

-- K4 · Kurum dizini ORTAKTIR: doğrulanmış kayıtlar herkese açık.
-- Doğrulanmamış kayıt yalnızca ekleyen işletmeye görünür (Ö-8).
alter table institutions enable row level security;
drop policy if exists i_read on institutions;
create policy i_read on institutions for select
  using (dogrulandi or ekleyen_tenant_id in (select auth_tenant_ids()));

-- K30 · Kişi kayıtları ORTAK DEĞİLDİR — rakibe sızmasın.
alter table institution_contacts enable row level security;
drop policy if exists ic_all on institution_contacts;
create policy ic_all on institution_contacts for all
  using (tenant_id in (select auth_tenant_ids()))
  with check (tenant_id in (select auth_tenant_ids()));

alter table institution_store_links enable row level security;
drop policy if exists isl_all on institution_store_links;
create policy isl_all on institution_store_links for all
  using (store_id in (select auth_store_ids()))
  with check (store_id in (select auth_store_ids()));

alter table institution_memberships enable row level security;
drop policy if exists im_read on institution_memberships;
create policy im_read on institution_memberships for select
  using (user_id = auth.uid()
         or institution_id in (select institution_id from accounts
                               where store_id in (select auth_store_ids())));

alter table publishers enable row level security;
drop policy if exists pub_read on publishers;
create policy pub_read on publishers for select using (auth.uid() is not null);

-- K9 · Katalog hibrit: ortak (tenant_id NULL) + işletmeye özel
alter table products enable row level security;
drop policy if exists prod_read on products;
create policy prod_read on products for select
  using (tenant_id is null or tenant_id in (select auth_tenant_ids()));
drop policy if exists prod_write on products;
create policy prod_write on products for all
  using (tenant_id in (select auth_tenant_ids()))
  with check (tenant_id in (select auth_tenant_ids()));

alter table deneme_details enable row level security;
drop policy if exists dd_read on deneme_details;
create policy dd_read on deneme_details for select
  using (product_id in (select id from products
         where tenant_id is null or tenant_id in (select auth_tenant_ids())));

-- K12 · Fiyat, iskonto ve stok DÜKKANA özeldir
alter table store_products enable row level security;
drop policy if exists sp_all on store_products;
create policy sp_all on store_products for all
  using (store_id in (select auth_store_ids()))
  with check (store_id in (select auth_store_ids()));

alter table discount_rules enable row level security;
drop policy if exists dr_all on discount_rules;
create policy dr_all on discount_rules for all
  using (store_id in (select auth_store_ids()))
  with check (store_id in (select auth_store_ids()));

alter table discount_caps enable row level security;
drop policy if exists dc_all on discount_caps;
create policy dc_all on discount_caps for all
  using (store_id in (select auth_store_ids()))
  with check (store_id in (select auth_store_ids()));

-- K5 · Cari erişimi: sahip/müdür → dükkanın tümü; pazarlamacı → portföyü;
-- öğretmen → kendi carisi (+ yetkiliyse kurumsal cari)
alter table accounts enable row level security;
drop policy if exists acc_read on accounts;
create policy acc_read on accounts for select using (id in (select auth_visible_accounts()));
drop policy if exists acc_write on accounts;
create policy acc_write on accounts for all
  using (store_id in (select auth_store_ids())
         and auth_has_role(array['isletme_sahibi','dukkan_muduru','pazarlamaci']::app_role[]))
  with check (store_id in (select auth_store_ids()));

alter table assignments enable row level security;
drop policy if exists asg_read on assignments;
create policy asg_read on assignments for select
  using (user_id = auth.uid() or store_id in (select auth_store_ids()));

alter table account_enrollments enable row level security;
drop policy if exists ae_all on account_enrollments;
create policy ae_all on account_enrollments for all
  using (account_id in (select auth_visible_accounts()))
  with check (account_id in (select auth_visible_accounts()));

alter table account_transfers enable row level security;
drop policy if exists at_read on account_transfers;
create policy at_read on account_transfers for select
  using (account_id in (select auth_visible_accounts()));

-- İşlem tabloları: hepsi cari görünürlüğüne bağlanır
do $$
declare t text;
begin
  foreach t in array array['requests','orders','shipments','returns','payments','visits','exam_programs']
  loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists %I_all on %I', t, t);
    if t = 'visits' then
      execute format($f$create policy %I_all on %I for all
        using (store_id in (select auth_store_ids()))
        with check (store_id in (select auth_store_ids()))$f$, t, t);
    else
      execute format($f$create policy %I_all on %I for all
        using (account_id in (select auth_visible_accounts()))
        with check (account_id in (select auth_visible_accounts()))$f$, t, t);
    end if;
  end loop;
end $$;

-- Kalem tabloları: üst kayıt üzerinden
do $$
declare r record;
begin
  for r in select * from (values
      ('request_items','requests','request_id'),
      ('order_items','orders','order_id'),
      ('shipment_items','shipments','shipment_id'),
      ('return_items','returns','return_id'),
      ('payment_allocations','payments','payment_id'),
      ('exam_deliveries','exam_programs','exam_program_id')
    ) as v(child, parent, fk)
  loop
    execute format('alter table %I enable row level security', r.child);
    execute format('drop policy if exists %I_all on %I', r.child, r.child);
    execute format($f$create policy %I_all on %I for all
      using (%I in (select id from %I))
      with check (%I in (select id from %I))$f$,
      r.child, r.child, r.fk, r.parent, r.fk, r.parent);
  end loop;
end $$;

-- Tenant'a bağlı sistem tabloları
do $$
declare t text;
begin
  foreach t in array array['cheques','invites','consents','notifications',
                           'audit_logs','settings','import_batches','import_templates',
                           'saved_reports','period_summaries']
  loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists %I_all on %I', t, t);
    execute format($f$create policy %I_all on %I for all
      using (tenant_id in (select auth_tenant_ids()))
      with check (tenant_id in (select auth_tenant_ids()))$f$, t, t);
  end loop;
end $$;

-- store_id taşıyan sistem tabloları (tenant_id yok)
do $$
declare t text;
begin
  foreach t in array array['sample_limits']
  loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists %I_all on %I', t, t);
    execute format($f$create policy %I_all on %I for all
      using (store_id in (select auth_store_ids()))
      with check (store_id in (select auth_store_ids()))$f$, t, t);
  end loop;
end $$;

alter table import_batch_rows enable row level security;
drop policy if exists ibr_all on import_batch_rows;
create policy ibr_all on import_batch_rows for all
  using (batch_id in (select id from import_batches))
  with check (batch_id in (select id from import_batches));

alter table bundle_items enable row level security;
drop policy if exists bi_read on bundle_items;
create policy bi_read on bundle_items for select
  using (parent_id in (select id from products));
