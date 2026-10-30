-- =============================================================================
-- 0013 · Davet kodu üretimi düzeltmesi
-- Hata: function gen_random_bytes(integer) does not exist
-- Sebep: Supabase pgcrypto'yu `extensions` şemasına kurar; fonksiyonların
--        search_path'i yalnızca `public` olduğu için bulunamıyordu.
-- Çözüm: search_path'e extensions eklendi (create_invite + create_staff_invite).
-- =============================================================================

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
  -- Karıştırılabilir karakterler (0/O, 1/I/l) çıkarıldı — sahada sözlü okunuyor.
  v_kod := upper(substr(translate(encode(gen_random_bytes(12),'base64'),'+/=OI01lo',''), 1, 8));
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

  v_kod := upper(substr(translate(encode(gen_random_bytes(12),'base64'),'+/=OI01lo',''),1,8));
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

grant execute on function create_invite, create_staff_invite to authenticated;
