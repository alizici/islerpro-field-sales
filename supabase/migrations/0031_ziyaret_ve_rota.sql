-- =============================================================================
-- 0031 · Saha: ziyaret ve rota (Faz 7)
-- Kararlar: K10 K30 K41 K43 K45 · Y-18
--
-- K10 · Ziyarette KONUM YOKTUR. "Gerçekten gitti mi?" sorusunun cevabı
-- konumdan değil ÇIKTIDAN gelir: ziyaret açıkken oluşan talep, sipariş,
-- teslimat, tahsilat ve eklenen kişi ziyaretin kanıtıdır.
--
--     Ziyaret kalitesi = çıktı sayısı,  konum yakınlığı DEĞİL
--
-- Y-18 · Damgalama TRIGGER ile yapılır, ekranlar `visit_id` taşımaz.
-- Pazarlamacıya "ziyaretinizi seçin" diye ek bir alan çıkarsaydık alan
-- boş kalırdı ve ölçüt kendiliğinden çürürdü.
--
-- K43 · `checked_in_at` CİHAZ saatidir (ziyaretin ölçtüğü şey odur),
-- `created_at` SUNUCU saati. Süre cihazdan, sıralama ve mali raporlar
-- sunucudan okunur.
-- =============================================================================

alter table visits add column if not exists client_key text;
create unique index if not exists visits_client_key_uk
  on visits(tenant_id, client_key) where client_key is not null;
-- Açık ziyaret her yazmada sorgulanır — kullanıcı başına en fazla bir satır.
create index if not exists visits_acik_idx
  on visits(user_id) where checked_out_at is null;

-- Y-18 · Kişi kaydı da bir ziyaret çıktısıdır.
alter table institution_contacts add column if not exists visit_id uuid references visits(id);

-- ---------------------------------------------------------------------------
-- ROTA · Gün planı. Ziyaretin kendisi değil, NİYETİDİR.
-- Plan tutulmazsa "bugün nereye gideceğim" sorusu her sabah baştan sorulur.
-- ---------------------------------------------------------------------------
create table if not exists visit_plans (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references tenants(id) on delete cascade,
  store_id       uuid not null references stores(id) on delete cascade,
  user_id        uuid not null references profiles(id),
  period_id      uuid not null references periods(id),
  tarih          date not null,
  institution_id uuid not null references institutions(id),
  sira           integer not null default 0,
  amac           text,
  -- planlandi → ziyaret_edildi (ziyaret kapanınca otomatik) | ertelendi | iptal
  durum          text not null default 'planlandi',
  visit_id       uuid references visits(id),
  created_at     timestamptz not null default now(),
  unique (user_id, tarih, institution_id)
);
create index if not exists visit_plans_gun_idx on visit_plans(user_id, tarih);

alter table visit_plans enable row level security;
drop policy if exists visit_plans_all on visit_plans;
create policy visit_plans_all on visit_plans for all
  using (store_id in (select auth_store_ids()))
  with check (store_id in (select auth_store_ids()));

-- ---------------------------------------------------------------------------
-- Açık ziyaret
-- ---------------------------------------------------------------------------
create or replace function active_visit_id() returns uuid
language sql stable security definer set search_path = public as $$
  select id from visits
  where user_id = auth.uid() and checked_out_at is null
  order by checked_in_at desc limit 1;
$$;

-- Y-18 · Otomatik damga. Ziyaret açıkken oluşan her kayıt işaretlenir.
create or replace function trg_stamp_visit() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.visit_id is null then
    new.visit_id := active_visit_id();
  end if;
  return new;
end $$;

do $$
declare t text;
begin
  foreach t in array array['requests','orders','shipments','payments',
                           'institution_contacts']
  loop
    execute format('drop trigger if exists stamp_visit on %I', t);
    execute format('create trigger stamp_visit before insert on %I
                    for each row execute function trg_stamp_visit()', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- K10 · Ziyaretin çıktıları — kanıt budur
-- ---------------------------------------------------------------------------
create or replace function visit_outputs(p_visit uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'talep',     (select count(*) from requests   where visit_id = p_visit),
    'siparis',   (select count(*) from orders     where visit_id = p_visit),
    'teslimat',  (select count(*) from shipments  where visit_id = p_visit),
    'tahsilat',  (select count(*) from payments   where visit_id = p_visit),
    'kisi',      (select count(*) from institution_contacts where visit_id = p_visit),
    'tutar',     (select coalesce(sum(tutar), 0) from payments where visit_id = p_visit),
    'toplam',    (select count(*) from requests  where visit_id = p_visit)
               + (select count(*) from orders    where visit_id = p_visit)
               + (select count(*) from shipments where visit_id = p_visit)
               + (select count(*) from payments  where visit_id = p_visit)
               + (select count(*) from institution_contacts where visit_id = p_visit)
  );
$$;

-- ---------------------------------------------------------------------------
-- Ziyaret aç
--
-- Aynı anda tek ziyaret açık kalabilir. Açık ziyaret varken başka bir kuruma
-- giriş yapılmak istenirse SESSİZCE KAPATMAYIZ — kapatılan ziyaretin süresi
-- yalan olur. Hangi kurumun açık olduğunu söyleyip kullanıcıya bırakırız.
-- ---------------------------------------------------------------------------
create or replace function start_visit(
  p_institution_id uuid,
  p_contact_id uuid default null,
  p_client_key text default null,
  p_checked_in_at timestamptz default null,
  p_store_id uuid default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_tenant uuid; v_store uuid; v_period uuid; v_id uuid;
  v_acik uuid; v_acik_kurum text; v_ad text;
begin
  select ad into v_ad from institutions where id = p_institution_id;
  if v_ad is null then raise exception 'Kurum bulunamadı'; end if;

  select m.tenant_id, m.store_id into v_tenant, v_store
  from memberships m
  where m.user_id = auth.uid() and m.status = 'aktif'
  order by (m.store_id is null) limit 1;
  if v_tenant is null then raise exception 'Aktif üyelik yok'; end if;
  v_store := coalesce(p_store_id, v_store, (select s from auth_store_ids() s limit 1));
  if v_store is null then raise exception 'Dükkan belirlenemedi'; end if;
  if v_store not in (select auth_store_ids()) then
    raise exception 'Bu dükkanda ziyaret açamazsınız';
  end if;

  -- K43 · Aynı client_key ikinci kez gelirse mevcut ziyaret döner.
  if p_client_key is not null then
    select id into v_id from visits
    where tenant_id = v_tenant and client_key = p_client_key;
    if v_id is not null then
      return jsonb_build_object('id', v_id, 'yeni', false, 'kurum_ad', v_ad);
    end if;
  end if;

  select v.id, i.ad into v_acik, v_acik_kurum
  from visits v join institutions i on i.id = v.institution_id
  where v.user_id = auth.uid() and v.checked_out_at is null
  order by v.checked_in_at desc limit 1;
  if v_acik is not null then
    if (select institution_id from visits where id = v_acik) = p_institution_id then
      return jsonb_build_object('id', v_acik, 'yeni', false, 'kurum_ad', v_ad);
    end if;
    raise exception '% ziyaretiniz hâlâ açık. Önce onu kapatın.', v_acik_kurum;
  end if;

  select id into v_period from periods
  where tenant_id = v_tenant and status = 'aktif'
  order by starts_on desc limit 1;
  if v_period is null then raise exception 'Aktif dönem yok'; end if;

  insert into visits (tenant_id, store_id, institution_id, user_id, period_id,
                      checked_in_at, gorusulen_contact_id, client_key)
  values (v_tenant, v_store, p_institution_id, auth.uid(), v_period,
          coalesce(p_checked_in_at, now()), p_contact_id, p_client_key)
  returning id into v_id;

  update visit_plans set durum = 'ziyaret_edildi', visit_id = v_id
  where user_id = auth.uid() and institution_id = p_institution_id
    and tarih = current_date and durum = 'planlandi';

  return jsonb_build_object('id', v_id, 'yeni', true, 'kurum_ad', v_ad);
end $$;

-- ---------------------------------------------------------------------------
-- Ziyaret kapat. Kapalı ziyaret ikinci kez kapatılmaz (idempotent) — offline
-- kuyruk aynı isteği tekrar gönderdiğinde süre uzamasın.
-- ---------------------------------------------------------------------------
create or replace function end_visit(
  p_visit_id uuid default null,
  p_not_metni text default null,
  p_sonuc text default null,
  p_checked_out_at timestamptz default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_in timestamptz; v_out timestamptz; v_kurum text;
begin
  v_id := coalesce(p_visit_id, active_visit_id());
  if v_id is null then raise exception 'Açık ziyaret yok'; end if;

  select v.checked_in_at, v.checked_out_at, i.ad into v_in, v_out, v_kurum
  from visits v join institutions i on i.id = v.institution_id
  where v.id = v_id and v.user_id = auth.uid();
  if v_in is null then raise exception 'Ziyaret bulunamadı'; end if;

  if v_out is null then
    v_out := coalesce(p_checked_out_at, now());
    -- Cihaz saati geri gitmişse süreyi negatif yapma.
    if v_out < v_in then v_out := v_in; end if;
    update visits set checked_out_at = v_out,
           not_metni = coalesce(nullif(trim(coalesce(p_not_metni, '')), ''), not_metni),
           sonuc = coalesce(nullif(trim(coalesce(p_sonuc, '')), ''), sonuc)
    where id = v_id;
  end if;

  return jsonb_build_object(
    'id', v_id, 'kurum_ad', v_kurum,
    'dakika', greatest(0, round(extract(epoch from v_out - v_in) / 60)::int),
    'cikti', visit_outputs(v_id));
end $$;

-- Açık ziyaret çubuğu için — uygulama her ekranda bunu gösterir.
create or replace function active_visit() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', v.id, 'institution_id', v.institution_id, 'kurum_ad', i.ad,
    'ilce', i.ilce, 'checked_in_at', v.checked_in_at,
    'dakika', greatest(0, round(extract(epoch from now() - v.checked_in_at) / 60)::int),
    'cikti', visit_outputs(v.id))
  from visits v join institutions i on i.id = v.institution_id
  where v.user_id = auth.uid() and v.checked_out_at is null
  order by v.checked_in_at desc limit 1;
$$;

-- ---------------------------------------------------------------------------
-- Ziyaret detayı: ne yapıldığı KALEM KALEM. Sayı değil, satır.
-- ---------------------------------------------------------------------------
create or replace function visit_detail(p_visit_id uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', v.id, 'kurum_ad', i.ad, 'ilce', i.ilce,
    'institution_id', v.institution_id,
    'pazarlamaci', p.ad_soyad,
    'checked_in_at', v.checked_in_at, 'checked_out_at', v.checked_out_at,
    'dakika', case when v.checked_out_at is null then null
              else greatest(0, round(extract(epoch from v.checked_out_at - v.checked_in_at) / 60)::int) end,
    'gorusulen', (select c.ad_soyad from institution_contacts c
                  where c.id = v.gorusulen_contact_id),
    'not_metni', v.not_metni, 'sonuc', v.sonuc,
    'cikti', visit_outputs(v.id),
    'satirlar', coalesce((
      select jsonb_agg(s order by s->>'tarih')
      from (
        select jsonb_build_object('tur','talep','id',r.id,'tarih',r.created_at,
                 'baslik', a.unvan,
                 'aciklama', (select count(*) from request_items ri where ri.request_id = r.id) || ' kalem') s
        from requests r join accounts a on a.id = r.account_id where r.visit_id = v.id
        union all
        select jsonb_build_object('tur','siparis','id',o.id,'tarih',o.created_at,
                 'baslik', a.unvan, 'aciklama', o.durum::text)
        from orders o join accounts a on a.id = o.account_id where o.visit_id = v.id
        union all
        select jsonb_build_object('tur','teslimat','id',sh.id,'tarih',sh.created_at,
                 'baslik', a.unvan,
                 'aciklama', (select coalesce(sum(si.adet),0) from shipment_items si
                              where si.shipment_id = sh.id) || ' adet')
        from shipments sh join accounts a on a.id = sh.account_id where sh.visit_id = v.id
        union all
        select jsonb_build_object('tur','tahsilat','id',pay.id,'tarih',pay.created_at,
                 'baslik', a.unvan, 'aciklama', pay.yontem::text, 'tutar', pay.tutar)
        from payments pay join accounts a on a.id = pay.account_id where pay.visit_id = v.id
        union all
        select jsonb_build_object('tur','kisi','id',c.id,'tarih',c.created_at,
                 'baslik', c.ad_soyad, 'aciklama', coalesce(c.gorev, c.brans, ''))
        from institution_contacts c where c.visit_id = v.id
      ) x), '[]'::jsonb))
  from visits v
  join institutions i on i.id = v.institution_id
  left join profiles p on p.id = v.user_id
  where v.id = p_visit_id and v.store_id in (select auth_store_ids());
$$;

-- ---------------------------------------------------------------------------
-- Ziyaret listesi. Çıktısı sıfır olan ziyaret gizlenmez — ölçüt budur.
-- ---------------------------------------------------------------------------
create or replace function list_visits(
  p_store_id uuid default null,
  p_user_id uuid default null,
  p_institution_id uuid default null,
  p_gun integer default 30,
  p_limit integer default 100
) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', v.id, 'kurum_ad', i.ad, 'ilce', i.ilce,
      'institution_id', v.institution_id,
      'pazarlamaci', pr.ad_soyad, 'user_id', v.user_id,
      'checked_in_at', v.checked_in_at, 'checked_out_at', v.checked_out_at,
      'dakika', case when v.checked_out_at is null then null
                else greatest(0, round(extract(epoch from v.checked_out_at - v.checked_in_at) / 60)::int) end,
      'sonuc', v.sonuc,
      'cikti', (visit_outputs(v.id)->>'toplam')::int)
    order by v.checked_in_at desc), '[]'::jsonb)
  from (
    select * from visits v2
    where v2.store_id in (select auth_store_ids())
      and (p_store_id is null or v2.store_id = p_store_id)
      and (p_user_id is null or v2.user_id = p_user_id)
      and (p_institution_id is null or v2.institution_id = p_institution_id)
      and v2.checked_in_at > now() - make_interval(days => p_gun)
    order by v2.checked_in_at desc limit p_limit
  ) v
  join institutions i on i.id = v.institution_id
  left join profiles pr on pr.id = v.user_id;
$$;

grant execute on function active_visit_id() to authenticated;
grant execute on function active_visit() to authenticated;
grant execute on function visit_outputs(uuid) to authenticated;
grant execute on function start_visit(uuid, uuid, text, timestamptz, uuid) to authenticated;
grant execute on function end_visit(uuid, text, text, timestamptz) to authenticated;
grant execute on function visit_detail(uuid) to authenticated;
grant execute on function list_visits(uuid, uuid, uuid, integer, integer) to authenticated;

-- ---------------------------------------------------------------------------
-- ROTA ÖNERİSİ · "Bugün nereye gitmeliyim?"
--
-- Bu fonksiyon rotayı KURMAZ, gerekçe üretir. Her satır neden orada olduğunu
-- kendisi söyler; pazarlamacı listeyi görüp seçer. Sıralama gizli bir skor
-- değil, sayılabilir dört olgudur:
--   gecikmiş borç · gecikmiş talep · bekleyen hazır sipariş · açık konsinye
-- Bunların hiçbiri yoksa geriye tek ölçüt kalır: en uzun süredir uğranmamış.
-- ---------------------------------------------------------------------------
create or replace function suggest_route(p_limit integer default 15)
returns jsonb
language sql stable security definer set search_path = public as $$
  with benim as (
    select a.id, a.institution_id, a.balance_cache
    from accounts a
    join assignments asg on asg.account_id = a.id and asg.aktif
    join periods pe on pe.id = asg.period_id and pe.status = 'aktif'
    where asg.user_id = auth.uid() and a.durum = 'aktif'
      and a.institution_id is not null
  ),
  cari as (
    select b.institution_id,
      case when b.balance_cache > 0 then b.balance_cache else 0 end as borc,
      (select count(*) from requests r where r.account_id = b.id
         and r.durum in ('gonderildi','incelemede')
         and r.created_at < now() - interval '24 hours') as gecikmis_talep,
      (select count(*) from orders o where o.account_id = b.id
         and o.durum = 'hazir') as hazir_siparis,
      (case when exists (select 1 from shipments s
              where s.account_id = b.id and s.borclandirir
                and s.teslim_edildi_at < now() - interval '30 days'
                and shipment_payment_status(s.id) <> 'odendi') then 1 else 0 end) as gecikmis_borc,
      (case when open_consignment(b.id) > 0 then 1 else 0 end) as konsinye
    from benim b
  ),
  kurum as (
    select institution_id, count(*)::int as cari,
           sum(borc) as borc,
           sum(gecikmis_talep)::int as gecikmis_talep,
           sum(hazir_siparis)::int as hazir_siparis,
           sum(gecikmis_borc)::int as gecikmis_borc,
           sum(konsinye)::int as konsinye
    from cari group by institution_id
  ),
  z as (
    select k.*, i.ad as kurum_ad, i.ilce, i.kurum_tipi::text as tip,
      (select max(v.checked_in_at) from visits v
       where v.institution_id = k.institution_id and v.user_id = auth.uid()) as son_ziyaret,
      (select exists (select 1 from visit_plans vp
       where vp.user_id = auth.uid() and vp.institution_id = k.institution_id
         and vp.tarih = current_date and vp.durum <> 'iptal')) as planda
    from kurum k join institutions i on i.id = k.institution_id
  ),
  p as (
    select z.*,
      coalesce(extract(day from now() - son_ziyaret)::int, 999) as gun
    from z
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'institution_id', institution_id, 'kurum_ad', kurum_ad,
      'ilce', ilce, 'tip', tip, 'cari', cari, 'borc', borc,
      'gecikmis_borc', gecikmis_borc, 'gecikmis_talep', gecikmis_talep,
      'hazir_siparis', hazir_siparis, 'konsinye', konsinye,
      'son_ziyaret', son_ziyaret, 'gun', case when gun = 999 then null else gun end,
      'planda', planda,
      'neden', case
        when gecikmis_borc > 0 then 'Gecikmiş borç — 30 günü aşan ödenmemiş teslimat'
        when gecikmis_talep > 0 then gecikmis_talep || ' talep 24 saattir bekliyor'
        when hazir_siparis > 0 then hazir_siparis || ' sipariş hazır, teslim edilmedi'
        when konsinye > 0 then 'Açık konsinye var — satıldı/iade kaydı girilmeli'
        when son_ziyaret is null then 'Hiç ziyaret edilmemiş'
        else gun || ' gündür uğranmadı' end,
      'puan', gecikmis_borc * 40 + gecikmis_talep * 30 + hazir_siparis * 20
              + konsinye * 10 + least(gun, 90) / 2.0)
    order by (gecikmis_borc * 40 + gecikmis_talep * 30 + hazir_siparis * 20
              + konsinye * 10 + least(gun, 90) / 2.0) desc), '[]'::jsonb)
  from (select * from p order by
          (gecikmis_borc * 40 + gecikmis_talep * 30 + hazir_siparis * 20
           + konsinye * 10 + least(gun, 90) / 2.0) desc
        limit p_limit) q;
$$;

-- ---------------------------------------------------------------------------
-- Gün planı
-- ---------------------------------------------------------------------------
create or replace function plan_visit(
  p_institution_id uuid,
  p_tarih date default null,
  p_amac text default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_tenant uuid; v_store uuid; v_period uuid; v_id uuid; v_tarih date;
begin
  v_tarih := coalesce(p_tarih, current_date);
  select m.tenant_id, m.store_id into v_tenant, v_store
  from memberships m where m.user_id = auth.uid() and m.status = 'aktif'
  order by (m.store_id is null) limit 1;
  if v_tenant is null then raise exception 'Aktif üyelik yok'; end if;
  v_store := coalesce(v_store, (select s from auth_store_ids() s limit 1));

  select id into v_period from periods
  where tenant_id = v_tenant and status = 'aktif'
  order by starts_on desc limit 1;
  if v_period is null then raise exception 'Aktif dönem yok'; end if;

  insert into visit_plans (tenant_id, store_id, user_id, period_id, tarih,
                           institution_id, amac,
                           sira)
  values (v_tenant, v_store, auth.uid(), v_period, v_tarih, p_institution_id,
          nullif(trim(coalesce(p_amac, '')), ''),
          coalesce((select max(sira) + 1 from visit_plans
                    where user_id = auth.uid() and tarih = v_tarih), 0))
  on conflict (user_id, tarih, institution_id) do update
    set amac = coalesce(excluded.amac, visit_plans.amac),
        durum = case when visit_plans.durum = 'iptal' then 'planlandi'
                     else visit_plans.durum end
  returning id into v_id;
  return v_id;
end $$;

-- Plan bir NİYETTİR, kayıt değil: iptal edilen plan silinir, iz bırakmaz.
create or replace function remove_plan(p_plan_id uuid) returns void
language sql security definer set search_path = public as $$
  delete from visit_plans
  where id = p_plan_id and user_id = auth.uid() and visit_id is null;
$$;

create or replace function set_plan_status(p_plan_id uuid, p_durum text)
returns void
language sql security definer set search_path = public as $$
  update visit_plans set durum = p_durum
  where id = p_plan_id and user_id = auth.uid()
    and p_durum in ('planlandi','ertelendi','iptal','ziyaret_edildi');
$$;

create or replace function reorder_plan(p_ids uuid[]) returns void
language sql security definer set search_path = public as $$
  update visit_plans vp set sira = x.i
  from (select unnest(p_ids) as id, generate_subscripts(p_ids, 1) as i) x
  where vp.id = x.id and vp.user_id = auth.uid();
$$;

-- ---------------------------------------------------------------------------
-- Bugünün rotası. Duraklar plandan gelir, bağlam CARİDEN gelir:
-- pazarlamacı okula girerken "burada ne var" sorusunun cevabını yanında taşır.
-- ---------------------------------------------------------------------------
create or replace function my_route(p_tarih date default null) returns jsonb
language sql stable security definer set search_path = public as $$
  with gun as (select coalesce(p_tarih, current_date) as t),
  benim as (
    select a.id, a.institution_id, a.unvan, a.balance_cache
    from accounts a
    join assignments asg on asg.account_id = a.id and asg.aktif
    join periods pe on pe.id = asg.period_id and pe.status = 'aktif'
    where asg.user_id = auth.uid() and a.durum = 'aktif'
  )
  select jsonb_build_object(
    'tarih', (select t from gun),
    'duraklar', coalesce((
      select jsonb_agg(jsonb_build_object(
          'plan_id', vp.id, 'institution_id', vp.institution_id,
          'kurum_ad', i.ad, 'ilce', i.ilce, 'tip', i.kurum_tipi::text,
          'sira', vp.sira, 'amac', vp.amac, 'durum', vp.durum,
          'visit_id', vp.visit_id,
          'cari', (select count(*) from benim b where b.institution_id = vp.institution_id),
          'borc', (select coalesce(sum(b.balance_cache), 0) from benim b
                   where b.institution_id = vp.institution_id and b.balance_cache > 0),
          'bekleyen_talep', (select count(*) from requests r
                             join benim b on b.id = r.account_id
                             where b.institution_id = vp.institution_id
                               and r.durum in ('gonderildi','incelemede')),
          'hazir_siparis', (select count(*) from orders o
                            join benim b on b.id = o.account_id
                            where b.institution_id = vp.institution_id
                              and o.durum = 'hazir'),
          'son_ziyaret', (select max(v.checked_in_at) from visits v
                          where v.institution_id = vp.institution_id
                            and v.user_id = auth.uid()))
        order by vp.sira, i.ad)
      from visit_plans vp join institutions i on i.id = vp.institution_id
      where vp.user_id = auth.uid() and vp.tarih = (select t from gun)
        and vp.durum <> 'iptal'), '[]'::jsonb),
    'tamamlanan', (select count(*) from visit_plans vp
                   where vp.user_id = auth.uid() and vp.tarih = (select t from gun)
                     and vp.durum = 'ziyaret_edildi'),
    'planlanan', (select count(*) from visit_plans vp
                  where vp.user_id = auth.uid() and vp.tarih = (select t from gun)
                    and vp.durum <> 'iptal'),
    -- Plansız yapılan ziyaretler de rotanın parçasıdır; saha planı takip etmez.
    'plansiz_ziyaret', (select count(*) from visits v
                        where v.user_id = auth.uid()
                          and v.checked_in_at::date = (select t from gun)
                          and not exists (select 1 from visit_plans vp
                                          where vp.visit_id = v.id))
  );
$$;

-- ---------------------------------------------------------------------------
-- K10 · Ziyaret performansı — ölçüt ÇIKTIDIR.
-- K35 · Prim hesaplanmaz; bu yalnızca rapordur.
-- ---------------------------------------------------------------------------
create or replace function visit_performance(
  p_store_id uuid, p_period_id uuid default null, p_user_id uuid default null)
returns jsonb
language sql stable security definer set search_path = public as $$
  with donem as (
    select coalesce(p_period_id,
      (select pe.id from periods pe join stores s on s.tenant_id = pe.tenant_id
       where s.id = p_store_id and pe.status = 'aktif'
       order by pe.starts_on desc limit 1)) as id
  ),
  z as (
    select v.id, v.user_id,
           (visit_outputs(v.id)->>'toplam')::int as cikti,
           case when v.checked_out_at is null then null
                else extract(epoch from v.checked_out_at - v.checked_in_at) / 60 end as dk
    from visits v
    where v.store_id = p_store_id and v.period_id = (select id from donem)
      and (p_user_id is null or v.user_id = p_user_id)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'user_id', user_id, 'ad_soyad', ad_soyad,
      'ziyaret', ziyaret, 'cikti', cikti, 'bos_ziyaret', bos,
      'ort_cikti', case when ziyaret = 0 then 0
                   else round(cikti::numeric / ziyaret, 1) end,
      'ort_dakika', ort_dk,
      -- Ziyaretten doğan ciro: teslimat ziyaret damgası taşıyorsa sayılır (K26).
      'ciro', ciro)
    order by cikti desc), '[]'::jsonb)
  from (
    select z.user_id, pr.ad_soyad,
           count(*)::int as ziyaret,
           coalesce(sum(z.cikti), 0)::int as cikti,
           count(*) filter (where z.cikti = 0)::int as bos,
           round(avg(z.dk))::int as ort_dk,
           coalesce((select sum(si.satir_tutari)
                     from shipments s join shipment_items si on si.shipment_id = s.id
                     where s.visit_id in (select id from z z2 where z2.user_id = z.user_id)
                       and s.borclandirir), 0) as ciro
    from z left join profiles pr on pr.id = z.user_id
    group by z.user_id, pr.ad_soyad
  ) q
  where p_store_id in (select auth_store_ids());
$$;

grant execute on function suggest_route(integer) to authenticated;
grant execute on function plan_visit(uuid, date, text) to authenticated;
grant execute on function remove_plan(uuid) to authenticated;
grant execute on function set_plan_status(uuid, text) to authenticated;
grant execute on function reorder_plan(uuid[]) to authenticated;
grant execute on function my_route(date) to authenticated;
grant execute on function visit_performance(uuid, uuid, uuid) to authenticated;
