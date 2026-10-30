-- =============================================================================
-- 0010 · Kimlik: profil tetikleyicisi, kurulum, davet akışı, oturum yükleme
-- Kararlar: K3 K8 K19 K44 · Y-15
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Yeni kullanıcı → profiles satırı
-- ---------------------------------------------------------------------------
create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, ad_soyad, telefon, eposta)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'ad_soyad', split_part(coalesce(new.email,''),'@',1), 'Kullanıcı'),
    new.phone,
    new.email
  )
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users for each row execute function handle_new_user();

-- ---------------------------------------------------------------------------
-- KURULUM · İlk kullanıcı kendini var eder.
-- RLS ile bootstrap yapılamaz (üyelik yoksa tenant görülemez, tenant yoksa
-- üyelik açılamaz). Bu döngü yalnızca security definer bir fonksiyonla kırılır.
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- OTURUM · Tek çağrıda her şey.
-- 341 ms gecikmede oturum yüklemek beş tur atmamalı (bkz. 05-supabase-kurulum).
-- ---------------------------------------------------------------------------
create or replace function my_session() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'user', (select jsonb_build_object('id', id, 'ad_soyad', ad_soyad,
                                       'telefon', telefon, 'eposta', eposta)
             from profiles where id = auth.uid()),
    'memberships', coalesce((
      select jsonb_agg(jsonb_build_object(
        'tenant_id', m.tenant_id, 'tenant_unvan', t.unvan,
        'store_id', m.store_id, 'store_ad', s.ad,
        'role', m.role, 'status', m.status))
      from memberships m
      join tenants t on t.id = m.tenant_id
      left join stores s on s.id = m.store_id
      where m.user_id = auth.uid() and m.status = 'aktif'), '[]'::jsonb),
    'institution_memberships', coalesce((
      select jsonb_agg(jsonb_build_object(
        'institution_id', im.institution_id, 'institution_ad', i.ad,
        'gorev', im.gorev, 'brans', im.brans,
        'can_order_for_institution', im.can_order_for_institution,
        'status', im.status))
      from institution_memberships im
      join institutions i on i.id = im.institution_id
      where im.user_id = auth.uid()), '[]'::jsonb),
    'stores', coalesce((
      select jsonb_agg(jsonb_build_object('id', s.id, 'ad', s.ad, 'tenant_id', s.tenant_id))
      from stores s where s.id in (select auth_store_ids())), '[]'::jsonb),
    'active_periods', coalesce((
      select jsonb_agg(jsonb_build_object('id', p.id, 'ad', p.ad, 'tenant_id', p.tenant_id,
                                          'starts_on', p.starts_on, 'ends_on', p.ends_on))
      from periods p
      where p.tenant_id in (select auth_tenant_ids()) and p.status = 'aktif'), '[]'::jsonb),
    'consent_ok', exists (select 1 from consents where user_id = auth.uid())
  );
$$;

-- ---------------------------------------------------------------------------
-- K3 · DAVET · Pazarlamacı öğretmeni davet eder; kod kurumu ve dükkanı taşır.
-- ---------------------------------------------------------------------------
create or replace function create_invite(
  p_institution_id uuid, p_store_id uuid, p_telefon text default null,
  p_gun integer default 14
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_tenant uuid; v_kod text; v_id uuid;
begin
  select tenant_id into v_tenant from stores where id = p_store_id;
  if v_tenant is null or v_tenant not in (select auth_tenant_ids()) then
    raise exception 'Bu dükkana yetkiniz yok';
  end if;
  -- Karıştırılabilir karakterler (0/O, 1/I) çıkarıldı — sahada sözlü okunuyor.
  v_kod := upper(substr(translate(encode(gen_random_bytes(9),'base64'),'+/=OI01lo',''), 1, 8));
  insert into invites (tenant_id, store_id, institution_id, kod, telefon,
                       gonderen_user_id, expires_at)
  values (v_tenant, p_store_id, p_institution_id, v_kod, p_telefon,
          auth.uid(), now() + (p_gun || ' days')::interval)
  returning id into v_id;
  return jsonb_build_object('id', v_id, 'kod', v_kod);
end $$;

-- Öğretmen kodu girer → kurum üyeliği açılır, ONAY BEKLER (K3).
-- Onaysız hesap katalog ve fiyat göremez.
create or replace function accept_invite(p_kod text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_inst uuid; v_store uuid; v_tenant uuid; v_exp timestamptz;
begin
  select institution_id, store_id, tenant_id, expires_at
    into v_inst, v_store, v_tenant, v_exp
  from invites where kod = upper(p_kod) and kullanildi_at is null;
  if v_inst is null then raise exception 'Davet kodu geçersiz veya kullanılmış'; end if;
  if v_exp < now() then raise exception 'Davet kodunun süresi dolmuş'; end if;

  insert into institution_memberships (user_id, institution_id, status)
  values (auth.uid(), v_inst, 'onay_bekliyor')
  on conflict (user_id, institution_id) do nothing;

  update invites set kullanildi_at = now(), kullanan_user_id = auth.uid()
   where kod = upper(p_kod);

  return jsonb_build_object('institution_id', v_inst, 'durum', 'onay_bekliyor');
end $$;

-- Dükkan onayı (K3) + yetki kaydı (Y-15): kim, ne zaman verdi audit'e yazılır.
create or replace function approve_teacher(
  p_user_id uuid, p_institution_id uuid, p_store_id uuid,
  p_can_order_for_institution boolean default false,
  p_unvan text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_tenant uuid; v_contact uuid; v_account uuid; v_ad text;
begin
  select tenant_id into v_tenant from stores where id = p_store_id;
  if v_tenant is null or v_tenant not in (select auth_tenant_ids()) then
    raise exception 'Bu dükkana yetkiniz yok';
  end if;

  update institution_memberships
     set status = 'aktif', can_order_for_institution = p_can_order_for_institution
   where user_id = p_user_id and institution_id = p_institution_id;

  select ad_soyad into v_ad from profiles where id = p_user_id;

  -- Kişi kaydı tenant'a özeldir (K30)
  insert into institution_contacts (tenant_id, institution_id, ad_soyad, user_id, gorev)
  values (v_tenant, p_institution_id, coalesce(v_ad,'Öğretmen'), p_user_id, 'öğretmen')
  returning id into v_contact;

  -- K5 · Onay anında öğretmen carisi açılır
  insert into accounts (tenant_id, store_id, tip, institution_id,
                        institution_contact_id, user_id, unvan)
  values (v_tenant, p_store_id, 'ogretmen', p_institution_id, v_contact, p_user_id,
          coalesce(p_unvan, v_ad, 'Öğretmen'))
  returning id into v_account;

  insert into audit_logs (tenant_id, user_id, eylem, tablo, kayit_id, detay)
  values (v_tenant, auth.uid(), 'approve_teacher', 'institution_memberships', p_user_id,
          jsonb_build_object('institution_id', p_institution_id,
                             'can_order_for_institution', p_can_order_for_institution,
                             'account_id', v_account));

  return jsonb_build_object('account_id', v_account, 'contact_id', v_contact);
end $$;

-- KVKK onayı (K44)
create or replace function record_consent(p_tenant_id uuid, p_surum text)
returns void language sql security definer set search_path = public as $$
  insert into consents (user_id, tenant_id, metin_surum)
  values (auth.uid(), p_tenant_id, p_surum)
  on conflict (user_id, tenant_id, metin_surum) do nothing;
$$;

grant execute on function bootstrap_tenant, my_session, create_invite,
  accept_invite, approve_teacher, record_consent to authenticated;
