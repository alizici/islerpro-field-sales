-- =============================================================================
-- 0012 · Organizasyon yönetimi: ekip daveti, dönem açma, üye pasifleştirme
-- Kararlar: K3 K8 K19 K34 (W-2 portföy devri) · Y-15
-- =============================================================================

-- Davet artık ekip üyeleri için de kullanılıyor: institution_id opsiyonel oldu.
alter table invites alter column institution_id drop not null;
alter table invites add column if not exists role app_role;
alter table invites add column if not exists ad_soyad text;

-- ---------------------------------------------------------------------------
-- EKİP DAVETİ · Pazarlamacı / müdür / hazırlık kullanıcısı çağırma
-- ---------------------------------------------------------------------------
create or replace function create_staff_invite(
  p_store_id uuid, p_role app_role, p_ad_soyad text default null,
  p_telefon text default null, p_gun integer default 14
) returns jsonb
language plpgsql security definer set search_path = public as $$
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

  v_kod := upper(substr(translate(encode(gen_random_bytes(9),'base64'),'+/=OI01lo',''),1,8));
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

-- Davet kodu kullanımı: ekip daveti ise üyelik, kurum daveti ise onay bekleyen
-- kurum üyeliği açar. Tek giriş noktası — kullanıcı hangi tip olduğunu bilmez.
create or replace function accept_invite(p_kod text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_inst uuid; v_store uuid; v_tenant uuid; v_exp timestamptz; v_role app_role;
begin
  select institution_id, store_id, tenant_id, expires_at, role
    into v_inst, v_store, v_tenant, v_exp, v_role
  from invites where kod = upper(p_kod) and kullanildi_at is null;

  if v_tenant is null then raise exception 'Davet kodu geçersiz veya kullanılmış'; end if;
  if v_exp < now() then raise exception 'Davet kodunun süresi dolmuş'; end if;

  if v_role is not null then
    -- Ekip üyesi: doğrudan aktif (daveti zaten yetkili gönderdi)
    insert into memberships (user_id, tenant_id, store_id, role, status)
    values (auth.uid(), v_tenant, v_store, v_role, 'aktif')
    on conflict (user_id, tenant_id, store_id, role) do update set status = 'aktif';
  else
    -- Öğretmen: ONAY BEKLER (K3). Onaysız hesap katalog ve fiyat göremez.
    insert into institution_memberships (user_id, institution_id, status)
    values (auth.uid(), v_inst, 'onay_bekliyor')
    on conflict (user_id, institution_id) do nothing;
  end if;

  update invites set kullanildi_at = now(), kullanan_user_id = auth.uid()
   where kod = upper(p_kod);

  return jsonb_build_object('tip', case when v_role is not null then 'ekip' else 'ogretmen' end,
                            'role', v_role, 'institution_id', v_inst);
end $$;

-- ---------------------------------------------------------------------------
-- EKİP LİSTESİ · dükkan bazlı, portföy sayısıyla
-- ---------------------------------------------------------------------------
create or replace function list_staff(p_store_id uuid default null) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x order by x->>'ad_soyad'), '[]'::jsonb) from (
    select jsonb_build_object(
      'user_id', m.user_id, 'ad_soyad', p.ad_soyad, 'telefon', p.telefon,
      'eposta', p.eposta, 'role', m.role, 'status', m.status,
      'store_id', m.store_id, 'store_ad', s.ad,
      'portfoy', (select count(*) from assignments a
                  join periods pe on pe.id = a.period_id
                  where a.user_id = m.user_id and a.aktif and pe.status = 'aktif')
    ) as x
    from memberships m
    join profiles p on p.id = m.user_id
    left join stores s on s.id = m.store_id
    where m.tenant_id in (select auth_tenant_ids())
      and (p_store_id is null or m.store_id = p_store_id or m.store_id is null)
  ) t;
$$;

-- Bekleyen öğretmen onayları (K3)
create or replace function list_pending_teachers() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x), '[]'::jsonb) from (
    select jsonb_build_object(
      'user_id', im.user_id, 'ad_soyad', p.ad_soyad, 'telefon', p.telefon,
      'institution_id', im.institution_id, 'institution_ad', i.ad,
      'institution_ilce', i.ilce, 'created_at', im.created_at
    ) as x
    from institution_memberships im
    join profiles p on p.id = im.user_id
    join institutions i on i.id = im.institution_id
    where im.status = 'onay_bekliyor'
      and im.institution_id in (
        select institution_id from institution_store_links
        where store_id in (select auth_store_ids())
        union
        select institution_id from invites
        where tenant_id in (select auth_tenant_ids()))
  ) t;
$$;

-- ---------------------------------------------------------------------------
-- K34 (W-2) · ÜYE PASİFLEŞTİRME — portföy devri ZORUNLU
-- Devredilmezse o carilerden gelen talepler hiçbir gelen kutusuna düşmez.
-- ---------------------------------------------------------------------------
create or replace function deactivate_member(
  p_user_id uuid, p_devralan_user_id uuid default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_tenant uuid; v_portfoy int; v_devir int := 0;
begin
  select tenant_id into v_tenant from memberships
   where user_id = p_user_id and tenant_id in (select auth_tenant_ids()) limit 1;
  if v_tenant is null then raise exception 'Bu kullanıcıya yetkiniz yok'; end if;
  if not auth_has_role(array['isletme_sahibi','dukkan_muduru']::app_role[]) then
    raise exception 'Yetkiniz yok';
  end if;

  select count(*) into v_portfoy from assignments a
   join periods pe on pe.id = a.period_id
   where a.user_id = p_user_id and a.aktif and pe.status = 'aktif';

  if v_portfoy > 0 and p_devralan_user_id is null then
    raise exception 'Bu pazarlamacının portföyünde % cari var. Devralacak kişiyi seçin.', v_portfoy;
  end if;

  if v_portfoy > 0 then
    -- Yeni satır açılır, eski kapanır: geçmiş dönemler bozulmaz (K8)
    insert into assignments (account_id, store_id, user_id, period_id, aktif)
    select a.account_id, a.store_id, p_devralan_user_id, a.period_id, true
      from assignments a join periods pe on pe.id = a.period_id
     where a.user_id = p_user_id and a.aktif and pe.status = 'aktif'
    on conflict (account_id, period_id, user_id) do update set aktif = true;
    get diagnostics v_devir = row_count;

    update assignments a set aktif = false
      from periods pe
     where pe.id = a.period_id and a.user_id = p_user_id
       and a.aktif and pe.status = 'aktif';
  end if;

  update memberships set status = 'pasif',
         devralan_user_id = p_devralan_user_id, pasife_alindi_at = now()
   where user_id = p_user_id and tenant_id = v_tenant;

  insert into audit_logs (tenant_id, user_id, eylem, tablo, kayit_id, detay)
  values (v_tenant, auth.uid(), 'deactivate_member', 'memberships', p_user_id,
          jsonb_build_object('devralan', p_devralan_user_id, 'devredilen_cari', v_devir));

  return jsonb_build_object('devredilen_cari', v_devir);
end $$;

-- ---------------------------------------------------------------------------
-- K8 · DÖNEM AÇMA — portföy otomatik kopyalanır
-- Aksi hâlde her yarıyıl pazarlamacılar portföyünü kaybeder.
-- exam_programs KOPYALANMAZ: her dönem yeniden anlaşma gerektirir.
-- ---------------------------------------------------------------------------
create or replace function create_next_period(p_tenant_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_son periods%rowtype; v_yeni uuid; v_yil text; v_term smallint;
        v_bas date; v_bit date; v_kopya int := 0;
begin
  if p_tenant_id not in (select auth_tenant_ids()) then
    raise exception 'Yetkiniz yok';
  end if;
  select * into v_son from periods where tenant_id = p_tenant_id
   order by academic_year desc, term desc limit 1;
  if v_son.id is null then raise exception 'Önce kurulum yapılmalı'; end if;

  if v_son.term = 1 then
    v_yil := v_son.academic_year; v_term := 2;
    v_bas := make_date(extract(year from v_son.ends_on)::int, 2, 1);
    v_bit := make_date(extract(year from v_son.ends_on)::int, 8, 31);
  else
    v_term := 1;
    v_bas := make_date(extract(year from v_son.ends_on)::int, 9, 1);
    v_bit := make_date(extract(year from v_son.ends_on)::int + 1, 1, 31);
    v_yil := extract(year from v_bas)::text || '-' || (extract(year from v_bas)::int + 1)::text;
  end if;

  insert into periods (tenant_id, academic_year, term, ad, starts_on, ends_on, status)
  values (p_tenant_id, v_yil, v_term, v_yil || ' / ' || v_term || '. Dönem',
          v_bas, v_bit, 'planlandi')
  returning id into v_yeni;

  -- Portföy taşınır; sahibi gözden geçirir.
  insert into assignments (account_id, store_id, user_id, period_id, aktif)
  select a.account_id, a.store_id, a.user_id, v_yeni, true
    from assignments a where a.period_id = v_son.id and a.aktif
  on conflict (account_id, period_id, user_id) do nothing;
  get diagnostics v_kopya = row_count;

  return jsonb_build_object('period_id', v_yeni, 'ad', v_yil || ' / ' || v_term || '. Dönem',
                            'kopyalanan_portfoy', v_kopya);
end $$;

-- Dönem durumu değiştirme (aktif / kapali)
create or replace function set_period_status(p_period_id uuid, p_status period_durum)
returns void language plpgsql security definer set search_path = public as $$
declare v_tenant uuid;
begin
  select tenant_id into v_tenant from periods where id = p_period_id;
  if v_tenant is null or v_tenant not in (select auth_tenant_ids()) then
    raise exception 'Yetkiniz yok';
  end if;
  if not auth_has_role(array['isletme_sahibi']::app_role[]) then
    raise exception 'Dönem durumunu yalnızca işletme sahibi değiştirebilir';
  end if;
  update periods set status = p_status where id = p_period_id;
  insert into audit_logs (tenant_id, user_id, eylem, tablo, kayit_id, detay)
  values (v_tenant, auth.uid(), 'set_period_status', 'periods', p_period_id,
          jsonb_build_object('status', p_status));
end $$;

grant execute on function create_staff_invite, accept_invite, list_staff,
  list_pending_teachers, deactivate_member, create_next_period,
  set_period_status to authenticated;
