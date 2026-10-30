-- =============================================================================
-- 0015 · Eksik yazma politikaları (e2e test paketi tarafından bulundu)
--
-- 0009'da bazı tablolara yalnızca SELECT politikası yazılmıştı. Bir kısmı
-- bilinçliydi (yazma security definer RPC'den geçiyor), bir kısmı hataydı.
--
-- BİLİNÇLİ — yazma yalnızca RPC'den (politika eklenmez):
--   memberships              → accept_invite · deactivate_member
--   periods                  → bootstrap_tenant · create_next_period · set_period_status
--   institution_memberships  → accept_invite · approve_teacher
--   account_transfers        → cari taşıma sihirbazı (Faz 8)
--
-- HATA — uygulama doğrudan yazıyor ama politika yoktu:
--   stores · assignments · publishers · deneme_details · bundle_items
-- =============================================================================

-- ---- stores: sahip dükkan açar/düzenler ----------------------------------
drop policy if exists s_insert on stores;
create policy s_insert on stores for insert
  with check (tenant_id in (select auth_tenant_ids())
              and auth_has_role(array['isletme_sahibi']::app_role[]));

drop policy if exists s_update on stores;
create policy s_update on stores for update
  using (tenant_id in (select auth_tenant_ids())
         and auth_has_role(array['isletme_sahibi','dukkan_muduru']::app_role[]))
  with check (tenant_id in (select auth_tenant_ids()));

-- ---- tenants: sahip kendi işletme künyesini düzeltebilir ------------------
drop policy if exists t_update on tenants;
create policy t_update on tenants for update
  using (id in (select auth_tenant_ids())
         and auth_has_role(array['isletme_sahibi']::app_role[]))
  with check (id in (select auth_tenant_ids()));

-- ---- assignments: portföy ataması (K5) -----------------------------------
-- Pazarlamacı kendine cari atayamaz; yalnızca sahip ve müdür dağıtır.
drop policy if exists asg_write on assignments;
create policy asg_write on assignments for insert
  with check (store_id in (select auth_store_ids())
              and auth_has_role(array['isletme_sahibi','dukkan_muduru']::app_role[]));

drop policy if exists asg_update on assignments;
create policy asg_update on assignments for update
  using (store_id in (select auth_store_ids())
         and auth_has_role(array['isletme_sahibi','dukkan_muduru']::app_role[]))
  with check (store_id in (select auth_store_ids()));

drop policy if exists asg_delete on assignments;
create policy asg_delete on assignments for delete
  using (store_id in (select auth_store_ids())
         and auth_has_role(array['isletme_sahibi','dukkan_muduru']::app_role[]));

-- ---- publishers: ortak dizin (K21) ---------------------------------------
-- Yayınevi listesi kitap ve deneme kataloğunda paylaşılır; oturumu olan
-- herkes ekleyebilir, kimse silemez.
drop policy if exists pub_insert on publishers;
create policy pub_insert on publishers for insert
  with check (auth.uid() is not null);

-- ---- deneme_details: katalog = deneme yan tablosu (K15) -------------------
drop policy if exists dd_write on deneme_details;
create policy dd_write on deneme_details for all
  using (product_id in (select id from products
                        where tenant_id in (select auth_tenant_ids())))
  with check (product_id in (select id from products
                             where tenant_id in (select auth_tenant_ids())));

-- ---- bundle_items: set içeriği -------------------------------------------
drop policy if exists bi_write on bundle_items;
create policy bi_write on bundle_items for all
  using (parent_id in (select id from products
                       where tenant_id in (select auth_tenant_ids())))
  with check (parent_id in (select id from products
                            where tenant_id in (select auth_tenant_ids())));
