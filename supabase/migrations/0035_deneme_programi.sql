-- =============================================================================
-- 0035 · Deneme programı — abonelik (Faz 9'un ikinci yarısı)
-- Kararlar: K8 K20 K26 K28 K47 K48 · C-3 · Y-8 · Ö-9
--
-- "12 deneme × 200 öğrenci × 2 haftada bir" bir ANLAŞMADIR; teslim takvimi o
-- anlaşmadan üretilir. Ama teslim planı BORÇ DOĞURMAZ:
--
--   C-3 · `exam_deliveries` YALNIZCA PLANDIR. Gerçekleştiğinde bir `shipment`
--   üretir ve `shipments.exam_delivery_id` ile ona bağlanır. Borç yalnızca
--   `shipments`'tan doğar — K26 tek kural olarak kalır.
--
-- Bu yüzden `teslim_edildi` durumu ELLE YAZILAMAZ: planı "teslim edildi"
-- işaretleyip teslimat kaydı üretmemek, borcu hiç doğmamış bir satış demek
-- olurdu. Durum ancak `deliver_exam` üzerinden geçer.
--
-- Y-8 · Program iki modludur ve teslim takvimini hangisinin ürettiği buradan
-- bellidir:
--   takvim_bagli    → kalemler import edilen takvimden, tarihler oradan
--   serbest_periyot → kalemler elle, tarihler programın periyodundan
-- Türkiye Geneli YALNIZCA takvim_bagli modda olabilir: tarihi ulusaldır,
-- program periyodu onu kaydıramaz (K20).
-- =============================================================================

create index if not exists exam_deliveries_program_durum_idx
  on exam_deliveries(exam_program_id, durum);

-- ---------------------------------------------------------------------------
-- K47 · Teslim kalemi durum makinesi
--
--   planlandi ──► hazirlaniyor ──► teslim_edildi ──► uygulandi ──► kapandi
--       │              │
--       └──► ertelendi ┘         yanal: iptal (her aşamada)
--
-- `uygulandi` AYRI bir durumdur: teslim edilmiş ama uygulanmamış deneme sık
-- görülür ve ikisini birleştirmek "kaç deneme gerçekten yapıldı" sorusunu
-- cevapsız bırakır.
-- ---------------------------------------------------------------------------
create or replace function exam_transition_ok(
  p_eski exam_teslim_durum, p_yeni exam_teslim_durum) returns boolean
language sql immutable as $$
  select case p_eski
    when 'planlandi'     then p_yeni in ('hazirlaniyor','ertelendi','iptal')
    when 'ertelendi'     then p_yeni in ('planlandi','hazirlaniyor','iptal')
    when 'hazirlaniyor'  then p_yeni in ('teslim_edildi','ertelendi','iptal',
                                         'planlandi')
    when 'teslim_edildi' then p_yeni in ('uygulandi','kapandi')
    when 'uygulandi'     then p_yeni = 'kapandi'
    else false      -- kapandi ve iptal TERMİNAL
  end;
$$;

-- ---------------------------------------------------------------------------
-- PROGRAM
-- ---------------------------------------------------------------------------
create or replace function create_exam_program(
  p_account_id uuid,
  p_modu exam_prog_modu default 'takvim_bagli',
  p_ogrenci_sayisi integer default null,
  p_deneme_adedi integer default null,
  p_periyot_gun integer default null,
  p_birim_fiyat numeric default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a accounts%rowtype; v_period uuid; v_id uuid;
begin
  select * into a from accounts where id = p_account_id;
  if a.id is null or a.id not in (select auth_visible_accounts()) then
    raise exception 'Cari bulunamadı veya yetkiniz yok';
  end if;
  if p_modu = 'serbest_periyot'
     and coalesce(p_periyot_gun, 0) <= 0 then
    raise exception 'Serbest periyot modunda periyot gün sayısı zorunludur';
  end if;
  if coalesce(p_ogrenci_sayisi, 0) <= 0 then
    raise exception 'Öğrenci sayısı sıfırdan büyük olmalı';
  end if;

  -- K8 · Program DÖNEME aittir. Yıllık anlaşma = iki program (her yarıyıl bir
  -- tane); `exam_programs` dönem geçişinde kopyalanmaz, yeniden anlaşılır.
  select id into v_period from periods
  where tenant_id = a.tenant_id and status = 'aktif'
  order by starts_on desc limit 1;
  if v_period is null then raise exception 'Aktif dönem yok'; end if;

  insert into exam_programs (tenant_id, store_id, account_id, period_id, modu,
                             ogrenci_sayisi, deneme_adedi, periyot_gun,
                             birim_fiyat)
  values (a.tenant_id, a.store_id, p_account_id, v_period, p_modu,
          p_ogrenci_sayisi, p_deneme_adedi, p_periyot_gun, p_birim_fiyat)
  returning id into v_id;

  insert into audit_logs (tenant_id, user_id, eylem, tablo, kayit_id, detay)
  values (a.tenant_id, auth.uid(), 'create_exam_program', 'exam_programs',
          v_id, jsonb_build_object('modu', p_modu,
                                   'ogrenci', p_ogrenci_sayisi,
                                   'adet', p_deneme_adedi));

  return jsonb_build_object('id', v_id, 'period_id', v_period,
                            'unvan', a.unvan);
end $$;

-- Ö-9 · Program `aktif` iken öğrenci sayısı değiştirilebilir; değişiklik
-- YALNIZCA henüz teslim edilmemiş kalemlere uygulanır. Teslim edilenler
-- damgalı kalır (K28) — geçmiş teslimatın adedi sonradan değişemez.
create or replace function update_exam_program(
  p_program_id uuid,
  p_ogrenci_sayisi integer default null,
  p_birim_fiyat numeric default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare p exam_programs%rowtype; v_etkilenen int := 0;
begin
  select * into p from exam_programs where id = p_program_id;
  if p.id is null or p.account_id not in (select auth_visible_accounts()) then
    raise exception 'Program bulunamadı veya yetkiniz yok';
  end if;
  if not p.aktif then raise exception 'Kapalı program değiştirilemez'; end if;

  update exam_programs set
    ogrenci_sayisi = coalesce(p_ogrenci_sayisi, ogrenci_sayisi),
    birim_fiyat = coalesce(p_birim_fiyat, birim_fiyat)
  where id = p_program_id;

  if p_ogrenci_sayisi is not null and p_ogrenci_sayisi <> p.ogrenci_sayisi then
    update exam_deliveries set adet = p_ogrenci_sayisi
    where exam_program_id = p_program_id
      and durum in ('planlandi','ertelendi','hazirlaniyor');
    get diagnostics v_etkilenen = row_count;
  end if;

  return jsonb_build_object('id', p_program_id, 'guncellenen_kalem', v_etkilenen,
                            'degismeyen_kalem',
                            (select count(*) from exam_deliveries
                             where exam_program_id = p_program_id
                               and durum not in ('planlandi','ertelendi',
                                                 'hazirlaniyor')));
end $$;

-- Program iptali: teslim edilmemiş kalemler DÜŞER, teslim edilenlerin borcu
-- DURUR. Borç `shipments`'tan doğdu; programı kapatmak onu silmez.
create or replace function cancel_exam_program(p_program_id uuid, p_gerekce text
  default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare p exam_programs%rowtype; v_dusen int; v_kalan int;
begin
  select * into p from exam_programs where id = p_program_id;
  if p.id is null or p.account_id not in (select auth_visible_accounts()) then
    raise exception 'Program bulunamadı veya yetkiniz yok';
  end if;

  update exam_deliveries set durum = 'iptal',
         ertelendi_notu = coalesce(p_gerekce, 'Program iptal edildi')
  where exam_program_id = p_program_id
    and durum in ('planlandi','ertelendi','hazirlaniyor');
  get diagnostics v_dusen = row_count;

  select count(*) into v_kalan from exam_deliveries
  where exam_program_id = p_program_id
    and durum in ('teslim_edildi','uygulandi','kapandi');

  update exam_programs set aktif = false where id = p_program_id;

  insert into audit_logs (tenant_id, user_id, eylem, tablo, kayit_id, detay)
  values (p.tenant_id, auth.uid(), 'cancel_exam_program', 'exam_programs',
          p_program_id, jsonb_build_object('dusen', v_dusen,
                                           'teslim_edilmis', v_kalan,
                                           'gerekce', p_gerekce));

  return jsonb_build_object('dusen_kalem', v_dusen,
                            'teslim_edilmis_kalem', v_kalan,
                            'bakiye', (select balance_cache from accounts
                                       where id = p.account_id));
end $$;

-- ---------------------------------------------------------------------------
-- TESLİM PLANI
--
-- takvim_bagli    → tarih takvimden gelir (`stok_tarihi`/`uygulama_baslangic`)
-- serbest_periyot → tarih programın periyodundan üretilir
--
-- İkisi tek fonksiyonda: mod farkı SADECE tarihin nereden geldiğidir, geri
-- kalan her şey aynı. Ayrı iki fonksiyon yazmak aynı kuralı iki yerde
-- tutmak olurdu.
-- ---------------------------------------------------------------------------
create or replace function plan_exam_deliveries(
  p_program_id uuid,
  p_items jsonb,                    -- [{product_id, tarih?, adet?}]
  p_baslangic date default null     -- serbest_periyot: ilk teslim
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  p exam_programs%rowtype; it jsonb; v_pid uuid; v_tarih date; v_adet int;
  v_n int := 0; v_sira int := 0; v_turu deneme_turu; v_stok date; v_uyg date;
begin
  select * into p from exam_programs where id = p_program_id;
  if p.id is null or p.account_id not in (select auth_visible_accounts()) then
    raise exception 'Program bulunamadı veya yetkiniz yok';
  end if;
  if not p.aktif then raise exception 'Kapalı programa kalem eklenemez'; end if;
  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'En az bir deneme seçilmeli';
  end if;

  for it in select * from jsonb_array_elements(p_items) loop
    v_pid := (it->>'product_id')::uuid;
    if v_pid is null then raise exception 'Kalem denemeye bağlı olmalı'; end if;

    select dd.deneme_turu, dd.stok_tarihi, dd.uygulama_baslangic
      into v_turu, v_stok, v_uyg
    from products pr join deneme_details dd on dd.product_id = pr.id
    where pr.id = v_pid and pr.katalog = 'deneme';
    if v_turu is null then
      raise exception 'Yalnızca deneme kataloğundan kalem seçilebilir';
    end if;

    -- K20 · Türkiye Geneli'nin tarihi ulusaldır; program periyodu onu kaydıramaz.
    if v_turu in ('turkiye_geneli','resmi_sinav')
       and p.modu = 'serbest_periyot' then
      raise exception 'Türkiye Geneli denemeleri yalnızca takvime bağlı '
                      'programda olabilir — tarihi sabittir';
    end if;

    if p.modu = 'takvim_bagli' then
      -- Uygulama tarihi varsa o, yoksa stok tarihi. Kurumun sınavı ne zaman
      -- yapacağı bilinmiyorsa kitapçığın geldiği gün planlanır.
      v_tarih := coalesce((it->>'tarih')::date, v_uyg, v_stok);
    else
      v_tarih := coalesce((it->>'tarih')::date,
                          coalesce(p_baslangic, current_date)
                            + (v_sira * p.periyot_gun));
    end if;

    v_adet := coalesce((it->>'adet')::int, p.ogrenci_sayisi);
    if coalesce(v_adet, 0) <= 0 then
      raise exception 'Adet sıfırdan büyük olmalı';
    end if;

    insert into exam_deliveries (exam_program_id, product_id, planlanan_tarih,
                                 adet)
    values (p_program_id, v_pid, v_tarih, v_adet);
    v_n := v_n + 1;
    v_sira := v_sira + 1;
  end loop;

  return jsonb_build_object('eklenen', v_n,
    'toplam_kalem', (select count(*) from exam_deliveries
                     where exam_program_id = p_program_id
                       and durum <> 'iptal'));
end $$;

-- ---------------------------------------------------------------------------
-- K47 · Durum değiştirme
--
-- `teslim_edildi` BU FONKSİYONDAN geçmez: planı teslim edildi işaretleyip
-- teslimat kaydı üretmemek, borcu hiç doğmamış bir satış demek olurdu (C-3).
-- ---------------------------------------------------------------------------
create or replace function set_exam_delivery_status(
  p_delivery_id uuid,
  p_durum exam_teslim_durum,
  p_not text default null,
  p_yeni_tarih date default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d exam_deliveries%rowtype; p exam_programs%rowtype;
begin
  select * into d from exam_deliveries where id = p_delivery_id;
  if d.id is null then raise exception 'Teslim kalemi bulunamadı'; end if;
  select * into p from exam_programs where id = d.exam_program_id;
  if p.account_id not in (select auth_visible_accounts()) then
    raise exception 'Bu kalem üzerinde yetkiniz yok';
  end if;

  if p_durum = 'teslim_edildi' then
    raise exception 'Teslim kaydı elle işaretlenemez — teslimat girin, '
                    'borç teslimattan doğar (K26)';
  end if;
  if d.durum = p_durum then
    return jsonb_build_object('id', d.id, 'durum', d.durum, 'degisti', false);
  end if;
  if not exam_transition_ok(d.durum, p_durum) then
    raise exception '% durumundaki kalem % yapılamaz', d.durum, p_durum;
  end if;
  if p_durum = 'ertelendi' then
    if p_yeni_tarih is null then
      raise exception 'Erteleme yeni tarih ister';
    end if;
    if coalesce(trim(p_not), '') = '' then
      raise exception 'Erteleme gerekçe ister';
    end if;
  end if;

  update exam_deliveries set
    durum = p_durum,
    -- Erteleme GEÇMİŞİ tutulur: kaçıncı kez ertelendiği görünmeden
    -- "bu okul hep erteliyor" bilgisi kaybolur.
    onceki_tarih = case when p_durum = 'ertelendi' then planlanan_tarih
                        else onceki_tarih end,
    planlanan_tarih = coalesce(p_yeni_tarih, planlanan_tarih),
    ertelendi_notu = coalesce(nullif(trim(p_not), ''), ertelendi_notu),
    uygulandi_at = case when p_durum = 'uygulandi' then now()
                        else uygulandi_at end,
    isaretleyen_user_id = auth.uid()
  where id = p_delivery_id;

  return jsonb_build_object('id', d.id, 'durum', p_durum, 'degisti', true,
                            'onceki_tarih', d.planlanan_tarih);
end $$;

-- ---------------------------------------------------------------------------
-- TESLİMAT — planı gerçeğe çeviren tek yol
--
-- C-3 · Burada bir `shipment` üretilir ve kalem ona bağlanır. Borç oradan
-- doğar; `exam_deliveries` hiçbir zaman borç üretmez.
-- ---------------------------------------------------------------------------
create or replace function deliver_exam(
  p_delivery_id uuid,
  p_adet integer default null,
  p_teslim_alan_ad text default null,
  p_client_key text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  d exam_deliveries%rowtype; p exam_programs%rowtype; v_sev jsonb; v_id uuid;
  v_adet int;
begin
  select * into d from exam_deliveries where id = p_delivery_id;
  if d.id is null then raise exception 'Teslim kalemi bulunamadı'; end if;
  select * into p from exam_programs where id = d.exam_program_id;
  if p.account_id not in (select auth_visible_accounts()) then
    raise exception 'Bu kalem üzerinde yetkiniz yok';
  end if;
  if d.durum in ('teslim_edildi','uygulandi','kapandi') then
    raise exception 'Bu kalem zaten teslim edilmiş';
  end if;
  if d.durum = 'iptal' then
    raise exception 'İptal edilmiş kalem teslim edilemez';
  end if;

  v_adet := coalesce(p_adet, d.adet);
  if v_adet <= 0 then raise exception 'Adet sıfırdan büyük olmalı'; end if;

  v_sev := create_shipment(
    p.account_id,
    jsonb_build_array(jsonb_build_object('product_id', d.product_id,
                                         'adet', v_adet)),
    null, true, 'teslimat', p_teslim_alan_ad, 'depo', null, p_client_key);
  v_id := (v_sev->>'id')::uuid;

  update shipments set exam_delivery_id = p_delivery_id where id = v_id;
  update exam_deliveries set durum = 'teslim_edildi', adet = v_adet,
                             isaretleyen_user_id = auth.uid()
  where id = p_delivery_id;

  return jsonb_build_object('shipment_id', v_id, 'delivery_id', p_delivery_id,
                            'adet', v_adet,
                            'tutar', v_sev->'toplam',
                            'bakiye', (select balance_cache from accounts
                                       where id = p.account_id));
end $$;

grant execute on function exam_transition_ok(exam_teslim_durum, exam_teslim_durum) to authenticated;
grant execute on function create_exam_program(uuid, exam_prog_modu, integer, integer, integer, numeric) to authenticated;
grant execute on function update_exam_program(uuid, integer, numeric) to authenticated;
grant execute on function cancel_exam_program(uuid, text) to authenticated;
grant execute on function plan_exam_deliveries(uuid, jsonb, date) to authenticated;
grant execute on function set_exam_delivery_status(uuid, exam_teslim_durum, text, date) to authenticated;
grant execute on function deliver_exam(uuid, integer, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- PROGRAM DETAYI
--
-- Her kalem İKİ rozet taşır: durum (K47) ve ÖDEME DURUMU. "Şu tarihte
-- yapılacak · ödendi" tek bakışta görünmeli. Ödeme durumu ayrı bir alan
-- değil, teslimatın mahsuplarından türetilir (K48).
-- ---------------------------------------------------------------------------
create or replace function exam_program_detail(p_program_id uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', p.id, 'account_id', p.account_id, 'unvan', a.unvan,
    'kurum_ad', i.ad, 'modu', p.modu, 'aktif', p.aktif,
    'ogrenci_sayisi', p.ogrenci_sayisi, 'deneme_adedi', p.deneme_adedi,
    'periyot_gun', p.periyot_gun, 'birim_fiyat', p.birim_fiyat,
    'donem', (select pe.ad from periods pe where pe.id = p.period_id),
    'kalemler', coalesce((select jsonb_agg(jsonb_build_object(
        'id', d.id, 'product_id', d.product_id, 'ad', pr.ad,
        'yayinevi', pub.ad,
        'deneme_turu', dd.deneme_turu,
        'planlanan_tarih', d.planlanan_tarih,
        'onceki_tarih', d.onceki_tarih,
        'adet', d.adet, 'durum', d.durum,
        'ertelendi_notu', d.ertelendi_notu,
        'uygulandi_at', d.uygulandi_at,
        'shipment_id', (select s.id from shipments s
                        where s.exam_delivery_id = d.id limit 1),
        -- K48 · ödeme durumu TÜRETİLİR
        'odeme_durumu', (select shipment_payment_status(s.id) from shipments s
                         where s.exam_delivery_id = d.id limit 1),
        'tutar', (select sum(si.satir_tutari)
                  from shipments s join shipment_items si on si.shipment_id = s.id
                  where s.exam_delivery_id = d.id))
      order by d.planlanan_tarih)
      from exam_deliveries d
      join products pr on pr.id = d.product_id
      left join deneme_details dd on dd.product_id = pr.id
      left join publishers pub on pub.id = pr.publisher_id
      where d.exam_program_id = p.id), '[]'::jsonb),
    'ozet', jsonb_build_object(
      'planlanan', (select count(*) from exam_deliveries d
                    where d.exam_program_id = p.id
                      and d.durum in ('planlandi','ertelendi','hazirlaniyor')),
      'teslim_edilen', (select count(*) from exam_deliveries d
                        where d.exam_program_id = p.id
                          and d.durum in ('teslim_edildi','uygulandi','kapandi')),
      -- K47 · uygulandı AYRI sayılır: teslim edilmiş ama uygulanmamış deneme
      -- sık görülür ve ikisini birleştirmek "kaç deneme gerçekten yapıldı"
      -- sorusunu cevapsız bırakır.
      'uygulanan', (select count(*) from exam_deliveries d
                    where d.exam_program_id = p.id
                      and d.durum in ('uygulandi','kapandi')),
      'ertelenen', (select count(*) from exam_deliveries d
                    where d.exam_program_id = p.id and d.durum = 'ertelendi'),
      'iptal', (select count(*) from exam_deliveries d
                where d.exam_program_id = p.id and d.durum = 'iptal'),
      'ciro', coalesce((select sum(si.satir_tutari)
                        from exam_deliveries d
                        join shipments s on s.exam_delivery_id = d.id
                        join shipment_items si on si.shipment_id = s.id
                        where d.exam_program_id = p.id), 0)))
  from exam_programs p
  join accounts a on a.id = p.account_id
  join institutions i on i.id = a.institution_id
  where p.id = p_program_id
    and p.account_id in (select auth_visible_accounts());
$$;

create or replace function list_exam_programs(
  p_store_id uuid, p_account_id uuid default null, boolean_aktif boolean default null)
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', p.id, 'account_id', p.account_id, 'unvan', a.unvan,
      'kurum_ad', i.ad, 'modu', p.modu, 'aktif', p.aktif,
      'ogrenci_sayisi', p.ogrenci_sayisi, 'deneme_adedi', p.deneme_adedi,
      'kalem', (select count(*) from exam_deliveries d
                where d.exam_program_id = p.id and d.durum <> 'iptal'),
      'teslim_edilen', (select count(*) from exam_deliveries d
                        where d.exam_program_id = p.id
                          and d.durum in ('teslim_edildi','uygulandi','kapandi')),
      'sonraki_teslim', (select min(d.planlanan_tarih) from exam_deliveries d
                         where d.exam_program_id = p.id
                           and d.durum in ('planlandi','ertelendi','hazirlaniyor')))
    order by p.aktif desc, a.unvan), '[]'::jsonb)
  from exam_programs p
  join accounts a on a.id = p.account_id
  join institutions i on i.id = a.institution_id
  where p.store_id = p_store_id
    and p.account_id in (select auth_visible_accounts())
    and (p_account_id is null or p.account_id = p_account_id)
    and (boolean_aktif is null or p.aktif = boolean_aktif)
    and p_store_id in (select auth_store_ids());
$$;

-- K41 · Her teslimden 3 gün önce depoya ve portföy sahibine hatırlatma.
create or replace function notify_exam_deliveries(p_gun integer default 3)
returns integer
language plpgsql security definer set search_path = public as $$
declare r record; v_n int := 0;
begin
  for r in
    select d.id, d.planlanan_tarih, d.adet, pr.ad as deneme_ad,
           p.tenant_id, p.account_id, a.unvan
    from exam_deliveries d
    join exam_programs p on p.id = d.exam_program_id
    join accounts a on a.id = p.account_id
    join products pr on pr.id = d.product_id
    where p.aktif and d.durum in ('planlandi','hazirlaniyor')
      and d.planlanan_tarih between current_date and current_date + p_gun
      and not exists (select 1 from notifications n
                      where n.hedef_tur = 'exam_delivery' and n.hedef_id = d.id
                        and n.olay = 'deneme_teslimi')
  loop
    -- Hem hazırlık yetkisi olanlara (depo) hem portföy sahibine gider:
    -- kitapçığı hazırlayan ile götüren farklı kişilerdir.
    insert into notifications (tenant_id, user_id, olay, baslik, govde,
                               hedef_tur, hedef_id)
    select distinct r.tenant_id, m.user_id, 'deneme_teslimi',
           'Deneme teslimi: ' || r.unvan,
           r.deneme_ad || ' · ' || r.adet || ' adet · ' ||
           to_char(r.planlanan_tarih, 'DD.MM.YYYY'),
           'exam_delivery', r.id
    from memberships m
    where m.tenant_id = r.tenant_id and m.status = 'aktif'
      and m.role in ('hazirlik','dukkan_muduru','isletme_sahibi');

    perform notify_user(r.tenant_id, account_owner(r.account_id),
      'deneme_teslimi', 'Deneme teslimi: ' || r.unvan,
      r.deneme_ad || ' · ' || r.adet || ' adet', 'exam_delivery', r.id);
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;

-- ---------------------------------------------------------------------------
-- DÖNEM SONU PROGRAM ÖZETİ
--
-- "Anlaşılan ile gerçekleşen" yan yana. Planlanan kalem sayısı ile uygulanan
-- kalem sayısı arasındaki fark, bir sonraki dönemin anlaşmasını belirleyen
-- tek sayıdır.
-- ---------------------------------------------------------------------------
create or replace function exam_program_summary(
  p_store_id uuid, p_period_id uuid default null) returns jsonb
language sql stable security definer set search_path = public as $$
  with donem as (
    select coalesce(p_period_id,
      (select pe.id from periods pe join stores s on s.tenant_id = pe.tenant_id
       where s.id = p_store_id and pe.status = 'aktif'
       order by pe.starts_on desc limit 1)) as id
  ),
  prog as (
    select p.*, a.unvan, i.ad as kurum_ad
    from exam_programs p
    join accounts a on a.id = p.account_id
    join institutions i on i.id = a.institution_id
    where p.store_id = p_store_id and p.period_id = (select id from donem)
      and p.account_id in (select auth_visible_accounts())
  )
  select jsonb_build_object(
    'donem', (select ad from periods where id = (select id from donem)),
    'program', (select count(*) from prog),
    'aktif_program', (select count(*) from prog where aktif),
    'ogrenci', (select coalesce(sum(ogrenci_sayisi), 0) from prog),
    'planlanan_kalem', (select count(*) from exam_deliveries d
                        where d.exam_program_id in (select id from prog)
                          and d.durum <> 'iptal'),
    'teslim_edilen', (select count(*) from exam_deliveries d
                      where d.exam_program_id in (select id from prog)
                        and d.durum in ('teslim_edildi','uygulandi','kapandi')),
    'uygulanan', (select count(*) from exam_deliveries d
                  where d.exam_program_id in (select id from prog)
                    and d.durum in ('uygulandi','kapandi')),
    'ertelenen', (select count(*) from exam_deliveries d
                  where d.exam_program_id in (select id from prog)
                    and d.onceki_tarih is not null),
    'ciro', coalesce((select sum(si.satir_tutari)
                      from exam_deliveries d
                      join shipments s on s.exam_delivery_id = d.id
                      join shipment_items si on si.shipment_id = s.id
                      where d.exam_program_id in (select id from prog)), 0),
    'programlar', coalesce((select jsonb_agg(jsonb_build_object(
        'id', pg.id, 'unvan', pg.unvan, 'kurum_ad', pg.kurum_ad,
        'aktif', pg.aktif, 'ogrenci_sayisi', pg.ogrenci_sayisi,
        'planlanan', (select count(*) from exam_deliveries d
                      where d.exam_program_id = pg.id and d.durum <> 'iptal'),
        'uygulanan', (select count(*) from exam_deliveries d
                      where d.exam_program_id = pg.id
                        and d.durum in ('uygulandi','kapandi')),
        'ciro', coalesce((select sum(si.satir_tutari)
                          from exam_deliveries d
                          join shipments s on s.exam_delivery_id = d.id
                          join shipment_items si on si.shipment_id = s.id
                          where d.exam_program_id = pg.id), 0))
      order by pg.unvan) from prog pg), '[]'::jsonb))
  where p_store_id in (select auth_store_ids());
$$;

grant execute on function exam_program_detail(uuid) to authenticated;
grant execute on function list_exam_programs(uuid, uuid, boolean) to authenticated;
grant execute on function notify_exam_deliveries(integer) to authenticated;
grant execute on function exam_program_summary(uuid, uuid) to authenticated;
