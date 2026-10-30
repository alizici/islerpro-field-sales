-- =============================================================================
-- 0011 · bootstrap_tenant düzeltmesi
-- Hata: column "status" is of type period_durum but expression is of type text
-- Sebep: CASE ifadesi text döndürüyor, enum'a cast gerekiyor.
-- =============================================================================

create or replace function bootstrap_tenant(
  p_unvan text,
  p_dukkan_ad text,
  p_il text default null,
  p_ilce text default null,
  p_academic_year text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_user uuid := auth.uid();
  v_tenant uuid; v_store uuid; v_p1 uuid; v_p2 uuid;
  v_yil text; v_bas int;
begin
  if v_user is null then raise exception 'Oturum yok'; end if;
  if exists (select 1 from memberships where user_id = v_user and role = 'isletme_sahibi') then
    raise exception 'Bu kullanıcının zaten bir işletmesi var';
  end if;

  insert into tenants (unvan) values (p_unvan) returning id into v_tenant;
  insert into stores (tenant_id, ad, il, ilce) values (v_tenant, p_dukkan_ad, p_il, p_ilce)
    returning id into v_store;
  -- store_id NULL → tenant geneli yetki (sahip tüm dükkanları görür)
  insert into memberships (user_id, tenant_id, store_id, role, status)
    values (v_user, v_tenant, null, 'isletme_sahibi', 'aktif');

  -- K8 · Dönem = yarıyıl. 1 Eylül–31 Ocak · 1 Şubat–31 Ağustos.
  v_bas := case when extract(month from current_date) >= 9
                then extract(year from current_date)::int
                else extract(year from current_date)::int - 1 end;
  v_yil := coalesce(p_academic_year, v_bas || '-' || (v_bas + 1));

  insert into periods (tenant_id, academic_year, term, ad, starts_on, ends_on, status)
  values (v_tenant, v_yil, 1, v_yil || ' / 1. Dönem',
          make_date(v_bas, 9, 1), make_date(v_bas + 1, 1, 31),
          (case when current_date <= make_date(v_bas+1,1,31) then 'aktif' else 'kapali' end)::period_durum)
  returning id into v_p1;

  insert into periods (tenant_id, academic_year, term, ad, starts_on, ends_on, status)
  values (v_tenant, v_yil, 2, v_yil || ' / 2. Dönem',
          make_date(v_bas + 1, 2, 1), make_date(v_bas + 1, 8, 31),
          (case when current_date > make_date(v_bas+1,1,31) then 'aktif' else 'planlandi' end)::period_durum)
  returning id into v_p2;

  insert into audit_logs (tenant_id, user_id, eylem, tablo, kayit_id)
    values (v_tenant, v_user, 'bootstrap_tenant', 'tenants', v_tenant);

  return jsonb_build_object('tenant_id', v_tenant, 'store_id', v_store,
                            'period_ids', jsonb_build_array(v_p1, v_p2));
end $$;

grant execute on function bootstrap_tenant to authenticated;
