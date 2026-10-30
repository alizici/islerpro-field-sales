-- =============================================================================
-- 0030 · Açılış ekranları: Panel (sahip) ve Bugün (pazarlamacı)
-- Kararlar: K5 K7 K11 K26 K37 K45 K48 · V7
--
-- Her ikisi de TEK ÇAĞRIDA döner. Sunucu ~340 ms uzakta; açılış ekranı için
-- sekiz ayrı istek atmak uygulamayı ilk saniyede yavaş gösterir.
--
-- K7 · Buradaki tek toplam DÜKKANIN kendi açık alacağıdır — bir kurumun
-- borcu değildir. Kurum düzeyinde toplam hâlâ üretilmiyor.
-- =============================================================================

create or replace function dashboard_owner(
  p_store_id uuid, p_period_id uuid default null) returns jsonb
language sql stable security definer set search_path = public as $$
  with donem as (
    select coalesce(p_period_id,
      (select pe.id from periods pe
       join stores s on s.tenant_id = pe.tenant_id
       where s.id = p_store_id and pe.status = 'aktif'
       order by pe.starts_on desc limit 1)) as id
  )
  select jsonb_build_object(
    -- ── İş kuyruğu: "bugün neye bakmalıyım" ────────────────────────────
    'bekleyen_talep', (select count(*) from requests r
                       where r.store_id = p_store_id
                         and r.durum in ('gonderildi','incelemede')),
    -- V7 · 24 saattir dokunulmamış
    'gecikmis_talep', (select count(*) from requests r
                       where r.store_id = p_store_id and r.durum = 'gonderildi'
                         and r.created_at < now() - interval '24 hours'),
    'onay_bekleyen_siparis', (select count(*) from orders o
                              where o.store_id = p_store_id
                                and o.durum = 'onay_bekliyor'),
    -- K46 · hazırlanacaklar kutusu
    'hazirlanacak_siparis', (select count(*) from orders o
                             where o.store_id = p_store_id
                               and o.durum in ('olusturuldu','hazirlaniyor','hazir')),
    -- W-2 · portföysüz cari = kimsenin kutusuna düşmeyen talep
    'portfoysuz_cari', (select count(*) from accounts a
                        where a.store_id = p_store_id and a.durum = 'aktif'
                          and not exists (select 1 from assignments asg
                                          where asg.account_id = a.id
                                            and asg.period_id = (select id from donem)
                                            and asg.aktif)),

    -- ── Para ───────────────────────────────────────────────────────────
    -- K7 · Bu DÜKKANIN açık alacağıdır, bir kurumun borcu değildir.
    'acik_alacak', (select coalesce(sum(a.balance_cache), 0) from accounts a
                    where a.store_id = p_store_id and a.balance_cache > 0),
    'borclu_cari', (select count(*) from accounts a
                    where a.store_id = p_store_id and a.balance_cache > 0),
    'gecikmis_borc', (select coalesce(sum(a.balance_cache), 0) from accounts a
                      where a.store_id = p_store_id and a.balance_cache > 0
                        and exists (select 1 from shipments s
                                    where s.account_id = a.id and s.borclandirir
                                      and s.teslim_edildi_at < now() - interval '60 days'
                                      and shipment_payment_status(s.id) <> 'odendi')),
    -- K26 · ciro TESLİMATTAN okunur, siparişten değil
    'donem_ciro', (select coalesce(sum(si.satir_tutari), 0)
                   from shipments s join shipment_items si on si.shipment_id = s.id
                   where s.store_id = p_store_id and s.borclandirir
                     and s.period_id = (select id from donem)),
    'donem_tahsilat', (select coalesce(sum(p.tutar), 0) from payments p
                       where p.store_id = p_store_id
                         and p.period_id = (select id from donem)
                         and p.yontem not in ('cek','senet')),
    -- K11 · çek ödeme değil vaattir; ayrı gösterilir
    'portfoydeki_cek', (select coalesce(sum(c.tutar), 0) from cheques c
                        where c.store_id = p_store_id and c.durum = 'portfoyde'),

    -- ── K37 · Talep hunisi: açılan → karara bağlanan → siparişe dönen ──
    'huni', (
      select jsonb_build_object(
        'acilan', count(*),
        'karara_baglanan', count(*) filter (where r.durum = 'karara_baglandi'),
        'reddedilen', count(*) filter (where r.durum = 'tamamen_reddedildi'),
        'siparise_donen', count(*) filter (
          where exists (select 1 from orders o
                        where o.request_id = r.id and o.durum <> 'iptal')))
      from requests r
      where r.store_id = p_store_id and r.period_id = (select id from donem)),

    'pazarlamacilar', coalesce((
      select jsonb_agg(jsonb_build_object(
               'user_id', pr.id, 'ad_soyad', pr.ad_soyad,
               'cari_sayisi', c.n, 'acik_talep', c.t) order by c.n desc)
      from profiles pr
      join lateral (
        select count(distinct asg.account_id) as n,
               (select count(*) from requests r
                join assignments a2 on a2.account_id = r.account_id
                where a2.user_id = pr.id and a2.aktif
                  and r.durum in ('gonderildi','incelemede')) as t
        from assignments asg
        join accounts a on a.id = asg.account_id
        where asg.user_id = pr.id and asg.aktif
          and asg.period_id = (select id from donem)
          and a.store_id = p_store_id
      ) c on true
      where c.n > 0), '[]'::jsonb),

    'donem_ad', (select ad from periods where id = (select id from donem))
  )
  where p_store_id in (select auth_store_ids());
$$;

-- ---------------------------------------------------------------------------
-- BUGÜN · Pazarlamacının günü
-- Yalnızca KENDİ PORTFÖYÜ. Rota ve ziyaret Faz 7'de gelecek; bu ekran şimdilik
-- "bugün neye bakmalıyım" sorusunu mevcut verilerle cevaplıyor.
-- ---------------------------------------------------------------------------
create or replace function dashboard_marketer(
  p_store_id uuid, p_period_id uuid default null) returns jsonb
language sql stable security definer set search_path = public as $$
  with donem as (
    select coalesce(p_period_id,
      (select pe.id from periods pe
       join stores s on s.tenant_id = pe.tenant_id
       where s.id = p_store_id and pe.status = 'aktif'
       order by pe.starts_on desc limit 1)) as id
  ),
  benim as (
    select a.id, a.unvan, a.tip, a.balance_cache, a.institution_id
    from accounts a
    join assignments asg on asg.account_id = a.id and asg.aktif
    where asg.user_id = auth.uid()
      and asg.period_id = (select id from donem)
      and a.store_id = p_store_id and a.durum = 'aktif'
  )
  select jsonb_build_object(
    'portfoy_cari', (select count(*) from benim),
    'bekleyen_talep', (select count(*) from requests r
                       where r.account_id in (select id from benim)
                         and r.durum in ('gonderildi','incelemede')),
    'gecikmis_talep', (select count(*) from requests r
                       where r.account_id in (select id from benim)
                         and r.durum = 'gonderildi'
                         and r.created_at < now() - interval '24 hours'),
    'hazir_siparis', (select count(*) from orders o
                      where o.account_id in (select id from benim)
                        and o.durum = 'hazir'),
    'borclu_cari', (select count(*) from benim where balance_cache > 0),
    'acik_alacak', (select coalesce(sum(balance_cache), 0) from benim
                    where balance_cache > 0),
    -- K45 · açık konsinye türetilir; hatırlatma buradan çıkar
    'acik_konsinye_cari', (select count(*) from benim b
                           where open_consignment(b.id) > 0),
    'donem_ciro', (select coalesce(sum(si.satir_tutari), 0)
                   from shipments s join shipment_items si on si.shipment_id = s.id
                   where s.account_id in (select id from benim) and s.borclandirir
                     and s.period_id = (select id from donem)),
    'donem_tahsilat', (select coalesce(sum(p.tutar), 0) from payments p
                       where p.account_id in (select id from benim)
                         and p.period_id = (select id from donem)
                         and p.yontem not in ('cek','senet')),

    -- En acil işler: gecikmiş talepler ve en eski borçlar
    'gecikmis_talepler', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', r.id, 'unvan', b.unvan, 'created_at', r.created_at,
               'kalem', (select count(*) from request_items ri
                         where ri.request_id = r.id),
               'saat', extract(epoch from now() - r.created_at) / 3600)
             order by r.created_at)
      from requests r join benim b on b.id = r.account_id
      where r.durum = 'gonderildi'
        and r.created_at < now() - interval '24 hours'
      limit 10), '[]'::jsonb),

    'tahsilat_hatirlatmalari', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', b.id, 'unvan', b.unvan, 'bakiye', b.balance_cache,
               'gun', (select extract(day from now() - min(s.teslim_edildi_at))::int
                       from shipments s
                       where s.account_id = b.id and s.borclandirir
                         and shipment_payment_status(s.id) <> 'odendi'))
             order by b.balance_cache desc)
      from benim b where b.balance_cache > 0
      limit 10), '[]'::jsonb),

    'donem_ad', (select ad from periods where id = (select id from donem))
  )
  where p_store_id in (select auth_store_ids());
$$;

grant execute on function dashboard_owner(uuid, uuid) to authenticated;
grant execute on function dashboard_marketer(uuid, uuid) to authenticated;
