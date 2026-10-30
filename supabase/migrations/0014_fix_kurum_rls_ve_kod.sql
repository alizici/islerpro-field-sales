-- =============================================================================
-- 0014 · İki hata düzeltmesi (e2e test paketi tarafından bulundu)
--
-- HATA 1 · institutions'a INSERT politikası yoktu.
--   `i_read` yalnızca SELECT için tanımlıydı; hiç kimse kurum ekleyemiyordu.
--   tenants'taki bootstrap açığının aynısı — Faz 2 bunun üstüne oturuyor.
--
-- HATA 2 · Davet kodunda `I` çıkabiliyordu (örn. WR9I4NJJ).
--   translate() küçük harf `i`'yi silmiyordu, upper() sonradan `I` yapıyordu.
--   Sıra düzeltildi: önce upper, sonra translate.
-- =============================================================================

-- ---- HATA 1 ---------------------------------------------------------------
-- Ö-8 · Dükkan kullanıcısı kurum ekleyebilir; kayıt `dogrulandi = false`
-- başlar ve yalnızca ekleyen işletmeye görünür. Platform Admin doğrulayınca
-- ortak dizine geçer.
drop policy if exists i_insert on institutions;
create policy i_insert on institutions for insert
  with check (
    ekleyen_tenant_id in (select auth_tenant_ids())
    and dogrulandi = false
  );

-- Kendi eklediği doğrulanmamış kaydı düzeltebilir; doğrulanmışa dokunamaz.
drop policy if exists i_update on institutions;
create policy i_update on institutions for update
  using (ekleyen_tenant_id in (select auth_tenant_ids()) and not dogrulandi)
  with check (ekleyen_tenant_id in (select auth_tenant_ids()) and not dogrulandi);

-- ---- HATA 2 ---------------------------------------------------------------
-- Kod alfabesinden karıştırılabilir karakterler gerçekten çıkarılıyor:
--   O ↔ 0 · I ↔ 1 ↔ l
create or replace function invite_kodu() returns text
language sql volatile security definer set search_path = public, extensions as $$
  select substr(
    translate(upper(encode(gen_random_bytes(16), 'base64')), '+/=OI01', ''),
    1, 8);
$$;

create or replace function create_invite(
  p_institution_id uuid, p_store_id uuid, p_telefon text default null,
  p_gun integer default 14
) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_tenant uuid; v_kod text; v_id uuid;
begin
  select tenant_id into v_tenant from stores where id = p_store_id;
  if v_tenant is null or v_tenant not in (select auth_tenant_ids()) then
    raise exception 'Bu dükkana yetkiniz yok';
  end if;
  v_kod := invite_kodu();
  insert into invites (tenant_id, store_id, institution_id, kod, telefon,
                       gonderen_user_id, expires_at)
  values (v_tenant, p_store_id, p_institution_id, v_kod, p_telefon,
          auth.uid(), now() + (p_gun || ' days')::interval)
  returning id into v_id;
  return jsonb_build_object('id', v_id, 'kod', v_kod);
end $$;

create or replace function create_staff_invite(
  p_store_id uuid, p_role app_role, p_ad_soyad text default null,
  p_telefon text default null, p_gun integer default 14
) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_tenant uuid; v_kod text; v_id uuid;
begin
  if p_role in ('platform_admin','isletme_sahibi') then
    raise exception 'Bu rol davetle verilemez';
  end if;
  select tenant_id into v_tenant from stores where id = p_store_id;
  if v_tenant is null or v_tenant not in (select auth_tenant_ids()) then
    raise exception 'Bu dükkana yetkiniz yok';
  end if;
  if not auth_has_role(array['isletme_sahibi','dukkan_muduru']::app_role[]) then
    raise exception 'Davet göndermek için sahip veya müdür olmalısınız';
  end if;
  v_kod := invite_kodu();
  insert into invites (tenant_id, store_id, institution_id, kod, telefon,
                       role, ad_soyad, gonderen_user_id, expires_at)
  values (v_tenant, p_store_id, null, v_kod, p_telefon, p_role, p_ad_soyad,
          auth.uid(), now() + (p_gun || ' days')::interval)
  returning id into v_id;
  insert into audit_logs (tenant_id, user_id, eylem, tablo, kayit_id, detay)
  values (v_tenant, auth.uid(), 'create_staff_invite', 'invites', v_id,
          jsonb_build_object('role', p_role, 'store_id', p_store_id));
  return jsonb_build_object('id', v_id, 'kod', v_kod);
end $$;

grant execute on function invite_kodu, create_invite, create_staff_invite to authenticated;
