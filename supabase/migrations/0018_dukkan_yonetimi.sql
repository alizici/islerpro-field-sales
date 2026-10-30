-- =============================================================================
-- 0018 · Dükkan yönetimi: düzenleme ve pasifleştirme (Faz 1 kapanışı)
-- Kararlar: K12 K29 K34 (W-2 ile aynı sınıf: kapatılan kap veriyi yetim bırakamaz)
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Pasif dükkan oturumda görünmemeli. my_session() bunu süzmüyordu: pasife
-- alınan dükkan hâlâ aktif dükkan olarak seçilebiliyordu.
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
      from stores s where s.id in (select auth_store_ids()) and s.aktif), '[]'::jsonb),
    'active_periods', coalesce((
      select jsonb_agg(jsonb_build_object('id', p.id, 'ad', p.ad, 'tenant_id', p.tenant_id,
                                          'starts_on', p.starts_on, 'ends_on', p.ends_on))
      from periods p
      where p.tenant_id in (select auth_tenant_ids()) and p.status = 'aktif'), '[]'::jsonb),
    'consent_ok', exists (select 1 from consents where user_id = auth.uid())
  );
$$;

-- ---------------------------------------------------------------------------
-- DÜKKAN DÜZENLEME · Yalnızca sahip. Ad boş bırakılamaz.
-- ---------------------------------------------------------------------------
create or replace function update_store(
  p_store_id uuid, p_ad text, p_il text default null,
  p_ilce text default null, p_adres text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_tenant uuid;
begin
  if coalesce(trim(p_ad), '') = '' then
    raise exception 'Dükkan adı boş olamaz';
  end if;
  select tenant_id into v_tenant from stores where id = p_store_id;
  if v_tenant is null or v_tenant not in (select auth_tenant_ids()) then
    raise exception 'Bu dükkana yetkiniz yok';
  end if;
  if not auth_has_role(array['isletme_sahibi']::app_role[]) then
    raise exception 'Dükkan bilgilerini yalnızca işletme sahibi değiştirebilir';
  end if;

  update stores set ad = trim(p_ad),
                    il = nullif(trim(coalesce(p_il,'')), ''),
                    ilce = nullif(trim(coalesce(p_ilce,'')), ''),
                    adres = nullif(trim(coalesce(p_adres,'')), '')
  where id = p_store_id;

  insert into audit_logs (tenant_id, user_id, eylem, tablo, kayit_id, detay)
  values (v_tenant, auth.uid(), 'update_store', 'stores', p_store_id,
          jsonb_build_object('ad', trim(p_ad), 'il', p_il, 'ilce', p_ilce));

  return jsonb_build_object('id', p_store_id, 'ad', trim(p_ad));
end $$;

-- ---------------------------------------------------------------------------
-- DÜKKAN PASİFLEŞTİRME
--
-- W-2 ile aynı sınıf hata: bir kabı kapatırken içindekiler yetim kalamaz.
-- Üç kapı:
--   1. Son aktif dükkan pasife alınamaz — oturumun dükkanı kalmaz.
--   2. Bakiyesi sıfır olmayan cari varsa engellenir — borç ekrandan
--      kaybolur ama tahsil edilmemiş olarak durur (K29).
--   3. Geçen carilerin ve portföy atamalarının kendisi de pasife alınır,
--      sayısı geri döner. Böylece hiçbir kayıt "aktif ama ulaşılamaz"
--      durumda kalmaz.
-- ---------------------------------------------------------------------------
create or replace function set_store_status(p_store_id uuid, p_aktif boolean)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_tenant uuid; v_kalan integer; v_borclu integer; v_tutar numeric;
  v_cari integer := 0; v_atama integer := 0;
begin
  select tenant_id into v_tenant from stores where id = p_store_id;
  if v_tenant is null or v_tenant not in (select auth_tenant_ids()) then
    raise exception 'Bu dükkana yetkiniz yok';
  end if;
  if not auth_has_role(array['isletme_sahibi']::app_role[]) then
    raise exception 'Dükkan durumunu yalnızca işletme sahibi değiştirebilir';
  end if;

  if p_aktif then
    update stores set aktif = true where id = p_store_id;
    insert into audit_logs (tenant_id, user_id, eylem, tablo, kayit_id, detay)
    values (v_tenant, auth.uid(), 'store_aktif', 'stores', p_store_id, '{}'::jsonb);
    return jsonb_build_object('aktif', true);
  end if;

  -- 1) Son aktif dükkan
  select count(*) into v_kalan
  from stores where tenant_id = v_tenant and aktif and id <> p_store_id;
  if v_kalan = 0 then
    raise exception 'Son aktif dükkan pasife alınamaz. Önce başka bir dükkan açın.';
  end if;

  -- 2) Açık bakiye
  select count(*), coalesce(sum(abs(balance_cache)), 0)
    into v_borclu, v_tutar
  from accounts
  where store_id = p_store_id and durum = 'aktif' and balance_cache <> 0;
  if v_borclu > 0 then
    raise exception
      'Bu dükkanda bakiyesi kapanmamış % cari var (toplam % ₺). Pasife almadan önce hesapları kapatın.',
      v_borclu, round(v_tutar, 2);
  end if;

  -- 3) İçerideki kayıtları da kapat
  update accounts set durum = 'pasif'
  where store_id = p_store_id and durum = 'aktif';
  get diagnostics v_cari = row_count;

  update assignments set aktif = false
  where store_id = p_store_id and aktif;
  get diagnostics v_atama = row_count;

  update stores set aktif = false where id = p_store_id;

  insert into audit_logs (tenant_id, user_id, eylem, tablo, kayit_id, detay)
  values (v_tenant, auth.uid(), 'store_pasif', 'stores', p_store_id,
          jsonb_build_object('kapanan_cari', v_cari, 'kapanan_atama', v_atama));

  return jsonb_build_object('aktif', false,
                            'kapanan_cari', v_cari,
                            'kapanan_atama', v_atama);
end $$;

-- Pasife almadan önce ekranda gösterilecek etki özeti.
create or replace function store_deactivation_check(p_store_id uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'son_dukkan', not exists (
      select 1 from stores s2
      where s2.tenant_id = (select tenant_id from stores where id = p_store_id)
        and s2.aktif and s2.id <> p_store_id),
    'borclu_cari', (select count(*) from accounts
                    where store_id = p_store_id and durum = 'aktif' and balance_cache <> 0),
    'borc_tutari', (select coalesce(sum(abs(balance_cache)), 0) from accounts
                    where store_id = p_store_id and durum = 'aktif' and balance_cache <> 0),
    'aktif_cari',  (select count(*) from accounts
                    where store_id = p_store_id and durum = 'aktif'),
    'aktif_atama', (select count(*) from assignments
                    where store_id = p_store_id and aktif)
  )
  where p_store_id in (select auth_store_ids())
     or (select tenant_id from stores where id = p_store_id) in (select auth_tenant_ids());
$$;

grant execute on function update_store(uuid, text, text, text, text) to authenticated;
grant execute on function set_store_status(uuid, boolean) to authenticated;
grant execute on function store_deactivation_check(uuid) to authenticated;
