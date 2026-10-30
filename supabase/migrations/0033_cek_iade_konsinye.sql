-- =============================================================================
-- 0033 · Ticari: çek/senet yaşam döngüsü, iade kayıtları, konsinye kapatma
-- Kararlar: K11 K26 K29 K45 K48 · Y-13
--
-- ÇEKİN BAKİYEYE NE ZAMAN DOKUNDUĞU bu dosyanın merkezindeki sorudur.
--
-- K11: "çek ödeme değil ödeme VAADİDİR." `create_payment` çek alındığında bir
-- `payments` satırı yazıyor ama `calc_account_balance` onu saymıyordu — yani
-- vaat bakiyeyi düşürmüyordu, doğrusu buydu. Eksik olan ikinci yarısıydı:
-- çek TAHSİL EDİLDİĞİNDE bakiyenin düşmesi. Bugüne kadar hiçbir çek bakiyeyi
-- kapatamıyordu; müşteri parayı ödese de borcu ekranda duruyordu.
--
-- Ciro edilen çek de bakiyeyi düşürür. Doküman bu noktayı açık bırakmıştı;
-- karar şu gerekçeyle verildi: çeki yayınevine ciro ettiğimizde ONUN
-- karşılığını almış oluyoruz — müşteri borcunu bir enstrümanla kapatmıştır.
-- Karşılıksız çıkarsa `karsiliksiz` yazılır ve borç GERİ DÖNER; bu yüzden
-- ciro→karsiliksiz geçişi de açık.
--
-- İade edilen çek bakiyeye dokunmaz: müşteriye geri verdik, borç yerinde.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Bakiye · çekin tahsil edilen yarısı eklendi
-- ---------------------------------------------------------------------------
create or replace function calc_account_balance(p_account uuid)
returns numeric language sql stable as $$
  select coalesce((
      -- Borç: yalnızca borçlandıran teslimatlar (K26)
      select sum(si.satir_tutari)
      from shipments s join shipment_items si on si.shipment_id = s.id
      where s.account_id = p_account and s.borclandirir
  ),0)
  - coalesce((
      -- Tahsilat: mahsup edilsin edilmesin TAMAMI düşer (K48 · avans)
      -- Çek/senet HARİÇ — onlar vaattir (K11)
      select sum(p.tutar)
      from payments p
      where p.account_id = p_account and p.yontem not in ('cek','senet')
  ),0)
  - coalesce((
      -- K11 · Vaadin karşılığı alındıysa bakiye ŞİMDİ düşer.
      -- `karsiliksiz` ve `iade_edildi` bu listede yok: ikisinde de borç durur.
      select sum(c.tutar) from cheques c
      where c.account_id = p_account
        and c.durum in ('tahsil_edildi','ciro_edildi')
  ),0)
  - coalesce((
      select sum(ri.satir_tutari)
      from returns r join return_items ri on ri.return_id = r.id
      where r.account_id = p_account and r.bakiyeyi_azaltir
  ),0);
$$;

-- Çek durumu değişince bakiye de değişir; tetikleyici olmadan `balance_cache`
-- sessizce eskiyordu.
create or replace function trg_refresh_balance_cheque() returns trigger
language plpgsql as $$
begin
  perform refresh_account_balance(coalesce(new.account_id, old.account_id));
  return null;
end $$;

drop trigger if exists t_bal_cheque on cheques;
create trigger t_bal_cheque after insert or update or delete on cheques
  for each row execute function trg_refresh_balance_cheque();

-- ---------------------------------------------------------------------------
-- K11 · ÇEK YAŞAM DÖNGÜSÜ
--
-- Geçiş tablosu AÇIK yazıldı. "Hangi durumdan hangisine gidilebilir" sorusu
-- kodun içine dağılırsa, bir gün biri `tahsil_edildi` çeki tekrar `portfoyde`
-- yapar ve bakiye sessizce bozulur.
--
--   portfoyde ──► tahsilde ──► tahsil_edildi
--        │            └──────► karsiliksiz
--        ├──► ciro_edildi ───► karsiliksiz   (ciro edilen çek geri dönebilir)
--        └──► iade_edildi                    (müşteriye geri verildi)
-- ---------------------------------------------------------------------------
create or replace function cheque_transition_ok(
  p_eski cek_durum, p_yeni cek_durum) returns boolean
language sql immutable as $$
  select case p_eski
    when 'portfoyde'     then p_yeni in ('tahsilde','ciro_edildi','iade_edildi')
    when 'tahsilde'      then p_yeni in ('tahsil_edildi','karsiliksiz','portfoyde')
    when 'ciro_edildi'   then p_yeni = 'karsiliksiz'
    when 'karsiliksiz'   then p_yeni in ('tahsilde','tahsil_edildi')
    else false      -- tahsil_edildi ve iade_edildi TERMİNAL
  end;
$$;

create or replace function set_cheque_status(
  p_cheque_id uuid,
  p_durum cek_durum,
  p_endorsed_to text default null,
  p_gerekce text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c cheques%rowtype; v_unvan text; v_sahip uuid;
begin
  select * into c from cheques where id = p_cheque_id;
  if c.id is null then raise exception 'Çek bulunamadı'; end if;
  if c.account_id not in (select auth_visible_accounts()) then
    raise exception 'Bu çek üzerinde yetkiniz yok';
  end if;
  if not auth_has_role(array['isletme_sahibi','dukkan_muduru']::app_role[]) then
    raise exception 'Çek durumu yalnızca sahip veya müdür tarafından '
                    'değiştirilebilir';
  end if;

  if c.durum = p_durum then
    return jsonb_build_object('id', c.id, 'durum', c.durum, 'degisti', false);
  end if;
  if not cheque_transition_ok(c.durum, p_durum) then
    raise exception '% durumundaki çek % yapılamaz', c.durum, p_durum;
  end if;
  if p_durum = 'ciro_edildi'
     and coalesce(trim(p_endorsed_to), '') = '' then
    raise exception 'Ciro edilen çekin kime ciro edildiği yazılmalı';
  end if;
  if p_durum = 'karsiliksiz' and coalesce(trim(p_gerekce), '') = '' then
    raise exception 'Karşılıksız kaydı gerekçe ister';
  end if;

  update cheques
     set durum = p_durum,
         endorsed_to = case when p_durum = 'ciro_edildi' then trim(p_endorsed_to)
                            else endorsed_to end
   where id = p_cheque_id;

  select a.unvan into v_unvan from accounts a where a.id = c.account_id;

  -- K11 · Karşılıksız çek cariyi TAHSİLATTA durumuna alır. Bu yalnızca bir
  -- etiket değil: cari listesinde ayrı süzülür, yeni sipariş açılırken görülür.
  if p_durum = 'karsiliksiz' then
    update accounts set durum = 'tahsilatta'
    where id = c.account_id and durum = 'aktif';

    v_sahip := account_owner(c.account_id);
    perform notify_user(c.tenant_id, v_sahip, 'cek_karsiliksiz',
      'Karşılıksız çek: ' || coalesce(v_unvan, ''),
      to_char(c.tutar, 'FM999G999G990D00') || ' ₺ · ' ||
      to_char(c.due_date, 'DD.MM.YYYY'), 'cheque', c.id);
  end if;

  insert into audit_logs (tenant_id, user_id, eylem, tablo, kayit_id, detay)
  values (c.tenant_id, auth.uid(), 'set_cheque_status', 'cheques', c.id,
          jsonb_build_object('eski', c.durum, 'yeni', p_durum,
                             'gerekce', p_gerekce,
                             'endorsed_to', p_endorsed_to));

  return jsonb_build_object('id', c.id, 'durum', p_durum, 'degisti', true,
                            'bakiye', (select balance_cache from accounts
                                       where id = c.account_id));
end $$;

-- ---------------------------------------------------------------------------
-- VADE TAKVİMİ (K11)
--
-- Rapor değil TAKVİMDİR: gün gün gruplanır, geçmiş vadeler ayrı toplanır.
-- "Bu hafta ne giriyor, ne gecikti" sorusu bir listeden okunmuyor.
-- ---------------------------------------------------------------------------
create or replace function cheque_calendar(
  p_store_id uuid,
  p_baslangic date default null,
  p_bitis date default null,
  p_durum cek_durum default null
) returns jsonb
language sql stable security definer set search_path = public as $$
  with aralik as (
    select coalesce(p_baslangic, current_date) as bas,
           coalesce(p_bitis, current_date + 90) as bit
  ),
  c as (
    select ch.*, a.unvan
    from cheques ch join accounts a on a.id = ch.account_id
    where ch.store_id = p_store_id
      and ch.account_id in (select auth_visible_accounts())
      and (p_durum is null or ch.durum = p_durum)
  )
  select jsonb_build_object(
    -- Vadesi geçmiş ve hâlâ tahsil edilmemiş olanlar takvimin dışında,
    -- ÜSTTE durur: takvimde aşağı kaydırılınca kaybolmasınlar.
    'gecikmis', coalesce((select jsonb_agg(jsonb_build_object(
          'id', id, 'unvan', unvan, 'tip', tip, 'tutar', tutar,
          'due_date', due_date, 'durum', durum, 'banka', banka,
          'kesideci', kesideci, 'cheque_no', cheque_no,
          'gun', (current_date - due_date))
        order by due_date)
      from c where durum in ('portfoyde','tahsilde')
        and due_date < current_date), '[]'::jsonb),
    'gecikmis_tutar', (select coalesce(sum(tutar),0) from c
                       where durum in ('portfoyde','tahsilde')
                         and due_date < current_date),

    'gunler', coalesce((select jsonb_agg(g order by g->>'tarih') from (
        select jsonb_build_object(
                 'tarih', due_date,
                 'gun', (due_date - current_date),
                 'tutar', sum(tutar),
                 'adet', count(*),
                 'cekler', jsonb_agg(jsonb_build_object(
                     'id', id, 'unvan', unvan, 'tip', tip, 'tutar', tutar,
                     'durum', durum, 'banka', banka, 'kesideci', kesideci,
                     'cheque_no', cheque_no) order by tutar desc)) as g
        from c, aralik
        where due_date between aralik.bas and aralik.bit
        group by due_date) x), '[]'::jsonb),

    'toplam', (select coalesce(sum(tutar),0) from c, aralik
               where due_date between aralik.bas and aralik.bit),
    -- K11 · Portföydeki çek RİSKTİR; ayrı gösterilir.
    'portfoyde', (select coalesce(sum(tutar),0) from c where durum = 'portfoyde'),
    'tahsilde', (select coalesce(sum(tutar),0) from c where durum = 'tahsilde'),
    'karsiliksiz', (select coalesce(sum(tutar),0) from c where durum = 'karsiliksiz'),
    'baslangic', (select bas from aralik),
    'bitis', (select bit from aralik))
  where p_store_id in (select auth_store_ids());
$$;

-- K41 · Çek vadesi yaklaştı → dükkan sahibine, vadeye 7 gün kala.
-- `escalate_stale_requests` ile aynı desende: dışarıdan zamanlanır,
-- aynı gün iki kez çalışsa da tek bildirim üretir.
create or replace function notify_due_cheques(p_gun integer default 7)
returns integer
language plpgsql security definer set search_path = public as $$
declare r record; v_n int := 0;
begin
  for r in
    select c.id, c.tenant_id, c.tutar, c.due_date, a.unvan, c.store_id
    from cheques c join accounts a on a.id = c.account_id
    where c.durum = 'portfoyde'
      and c.due_date between current_date and current_date + p_gun
      and not exists (select 1 from notifications n
                      where n.hedef_tur = 'cheque' and n.hedef_id = c.id
                        and n.olay = 'cek_vadesi')
  loop
    insert into notifications (tenant_id, user_id, olay, baslik, govde,
                               hedef_tur, hedef_id)
    select r.tenant_id, m.user_id, 'cek_vadesi',
           'Çek vadesi yaklaşıyor: ' || coalesce(r.unvan, ''),
           to_char(r.tutar, 'FM999G999G990D00') || ' ₺ · ' ||
           to_char(r.due_date, 'DD.MM.YYYY'),
           'cheque', r.id
    from memberships m
    where m.tenant_id = r.tenant_id and m.status = 'aktif'
      and m.role in ('isletme_sahibi','dukkan_muduru');
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;

-- ---------------------------------------------------------------------------
-- İADE (K26'nın tersi)
--
-- İki farklı olay aynı tabloda durur ve `bakiyeyi_azaltir` ile ayrılır:
--   satılan malın iadesi  → true  · borç düşer
--   konsinye malın geri alınması → false · borç zaten doğmamıştı, yalnızca
--                                   açık konsinye azalır (K45)
--
-- Fiyat GÜNCEL fiyattan değil, çıkışın DAMGALADIĞI fiyattan alınır (K28).
-- Aksi hâlde zamla birlikte iade, satıştan pahalıya dönerdi.
-- ---------------------------------------------------------------------------
create or replace function create_return(
  p_account_id uuid,
  p_items jsonb,                       -- [{product_id | shipment_item_id, adet}]
  p_shipment_id uuid default null,
  p_bakiyeyi_azaltir boolean default true,
  p_gerekce text default null,
  p_client_key text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  a accounts%rowtype; v_id uuid; v_period uuid; it jsonb;
  v_pid uuid; v_adet int; v_fiyat numeric; v_isk numeric;
  v_tutar numeric; v_toplam numeric := 0; v_n int := 0;
  v_cikan int; v_iade int; v_acik numeric;
begin
  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'İadede en az bir kalem olmalı';
  end if;
  select * into a from accounts where id = p_account_id;
  if a.id is null or a.id not in (select auth_visible_accounts()) then
    raise exception 'Cari bulunamadı veya yetkiniz yok';
  end if;

  if p_client_key is not null then
    select id into v_id from returns
    where tenant_id = a.tenant_id and client_key = p_client_key;
    if v_id is not null then
      return jsonb_build_object('id', v_id, 'yeni', false);
    end if;
  end if;

  select id into v_period from periods
  where tenant_id = a.tenant_id and status = 'aktif'
  order by starts_on desc limit 1;
  if v_period is null then raise exception 'Aktif dönem yok'; end if;

  insert into returns (tenant_id, store_id, account_id, institution_id,
                       period_id, shipment_id, bakiyeyi_azaltir, gerekce,
                       alan_user_id, client_key)
  values (a.tenant_id, a.store_id, p_account_id, a.institution_id, v_period,
          p_shipment_id, p_bakiyeyi_azaltir,
          nullif(trim(coalesce(p_gerekce, '')), ''), auth.uid(), p_client_key)
  returning id into v_id;

  for it in select * from jsonb_array_elements(p_items) loop
    v_adet := coalesce((it->>'adet')::int, 0);
    if v_adet <= 0 then raise exception 'Adet sıfırdan büyük olmalı'; end if;

    if (it->>'shipment_item_id') is not null then
      select si.product_id, si.birim_fiyat, si.iskonto_orani
        into v_pid, v_fiyat, v_isk
      from shipment_items si where si.id = (it->>'shipment_item_id')::uuid;
      if v_pid is null then raise exception 'Teslimat kalemi bulunamadı'; end if;
    else
      v_pid := (it->>'product_id')::uuid;
      if v_pid is null then raise exception 'Kalem ürüne bağlı olmalı'; end if;
      -- Ürünün bu cariye EN SON hangi fiyatla çıktığını bul (K28 damgası).
      select si.birim_fiyat, si.iskonto_orani into v_fiyat, v_isk
      from shipment_items si join shipments s on s.id = si.shipment_id
      where s.account_id = p_account_id and si.product_id = v_pid
      order by s.created_at desc limit 1;
      if v_fiyat is null then
        raise exception 'Bu ürün bu cariye hiç çıkmamış — iade edilemez';
      end if;
    end if;

    -- Çıkandan fazlası iade edilemez. Bu kontrol olmadan iade, borcu
    -- eksiye çevirip cariye alacak yazabilirdi.
    select coalesce(sum(si.adet), 0) into v_cikan
    from shipment_items si join shipments s on s.id = si.shipment_id
    where s.account_id = p_account_id and si.product_id = v_pid;

    select coalesce(sum(ri.adet), 0) into v_iade
    from return_items ri join returns r on r.id = ri.return_id
    where r.account_id = p_account_id and ri.product_id = v_pid
      and r.id <> v_id;

    if v_adet > v_cikan - v_iade then
      raise exception 'Bu üründen iade edilebilecek % adet var, % istendi',
        greatest(v_cikan - v_iade, 0), v_adet;
    end if;

    v_tutar := line_total(v_fiyat, v_isk, v_adet);
    insert into return_items (return_id, product_id, adet, birim_fiyat,
                              satir_tutari)
    values (v_id, v_pid, v_adet, v_fiyat, v_tutar);
    v_toplam := v_toplam + v_tutar;
    v_n := v_n + 1;
  end loop;

  -- K45 · Konsinye iadesi açık konsinyeden fazla olamaz.
  if not p_bakiyeyi_azaltir then
    v_acik := open_consignment(p_account_id);
    if v_acik < 0 then
      raise exception 'Konsinye iadesi açık konsinyeyi aşıyor';
    end if;
  end if;

  insert into audit_logs (tenant_id, user_id, eylem, tablo, kayit_id, detay)
  values (a.tenant_id, auth.uid(), 'create_return', 'returns', v_id,
          jsonb_build_object('kalem', v_n, 'toplam', v_toplam,
                             'bakiyeyi_azaltir', p_bakiyeyi_azaltir));

  return jsonb_build_object('id', v_id, 'yeni', true, 'kalem', v_n,
                            'toplam', v_toplam,
                            'bakiyeyi_azaltir', p_bakiyeyi_azaltir,
                            'bakiye', (select balance_cache from accounts
                                       where id = p_account_id));
end $$;

-- ---------------------------------------------------------------------------
-- KONSİNYE KAPATMA (K45)
--
-- Açık konsinye türetilir; defteri yoktur. Kapatmak iki kayıt demektir:
--   satılan → konsinye_satis teslimatı (borç doğar)
--   geri alınan → bakiyeyi azaltmayan iade
--
-- İkisi TEK ÇAĞRIDA yapılıyor: ayrı ayrı yapılsaydı, satış yazılıp iade
-- yazılamadığında cari hem borçlanmış hem konsinyesi açık kalırdı.
-- ---------------------------------------------------------------------------
create or replace function open_consignment_detail(p_account_id uuid)
returns jsonb
language sql stable security definer set search_path = public as $$
  with birakilan as (
    select si.product_id, sum(si.adet) as adet
    from shipments s join shipment_items si on si.shipment_id = s.id
    where s.account_id = p_account_id and s.tip = 'teslimat'
      and not s.borclandirir
    group by si.product_id
  ),
  satilan as (
    select si.product_id, sum(si.adet) as adet
    from shipments s join shipment_items si on si.shipment_id = s.id
    where s.account_id = p_account_id and s.tip = 'konsinye_satis'
    group by si.product_id
  ),
  iade as (
    select ri.product_id, sum(ri.adet) as adet
    from returns r join return_items ri on ri.return_id = r.id
    where r.account_id = p_account_id and not r.bakiyeyi_azaltir
    group by ri.product_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'product_id', b.product_id, 'ad', p.ad, 'barkod', p.barkod,
      'yayinevi', pub.ad,
      'birakilan', b.adet,
      'satilan', coalesce(s.adet, 0),
      'iade', coalesce(i.adet, 0),
      'kalan', b.adet - coalesce(s.adet, 0) - coalesce(i.adet, 0),
      -- Kapatırken kullanılacak fiyat: çıkışın damgaladığı fiyat (K28)
      'birim_fiyat', (select si.birim_fiyat
                      from shipment_items si join shipments sh on sh.id = si.shipment_id
                      where sh.account_id = p_account_id
                        and si.product_id = b.product_id and not sh.borclandirir
                      order by sh.created_at desc limit 1),
      'iskonto_orani', (select si.iskonto_orani
                        from shipment_items si join shipments sh on sh.id = si.shipment_id
                        where sh.account_id = p_account_id
                          and si.product_id = b.product_id and not sh.borclandirir
                        order by sh.created_at desc limit 1))
    order by p.ad), '[]'::jsonb)
  from birakilan b
  join products p on p.id = b.product_id
  left join publishers pub on pub.id = p.publisher_id
  left join satilan s on s.product_id = b.product_id
  left join iade i on i.product_id = b.product_id
  where b.adet - coalesce(s.adet, 0) - coalesce(i.adet, 0) > 0
    and p_account_id in (select auth_visible_accounts());
$$;

create or replace function settle_consignment(
  p_account_id uuid,
  p_satilan jsonb default '[]'::jsonb,   -- [{product_id, adet}]
  p_iade jsonb default '[]'::jsonb,      -- [{product_id, adet}]
  p_gerekce text default null,
  p_client_key text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  a accounts%rowtype; v_satis jsonb; v_iade jsonb;
  v_satis_id uuid; v_iade_id uuid; v_borc numeric := 0;
begin
  if (p_satilan is null or jsonb_array_length(p_satilan) = 0)
     and (p_iade is null or jsonb_array_length(p_iade) = 0) then
    raise exception 'Kapatılacak kalem yok';
  end if;
  select * into a from accounts where id = p_account_id;
  if a.id is null or a.id not in (select auth_visible_accounts()) then
    raise exception 'Cari bulunamadı veya yetkiniz yok';
  end if;

  if p_satilan is not null and jsonb_array_length(p_satilan) > 0 then
    v_satis := create_shipment(
      p_account_id, p_satilan, null, true, 'konsinye_satis',
      null, 'elden', null,
      case when p_client_key is null then null else p_client_key || '-s' end);
    v_satis_id := (v_satis->>'id')::uuid;
    v_borc := coalesce((v_satis->>'toplam')::numeric, 0);
  end if;

  if p_iade is not null and jsonb_array_length(p_iade) > 0 then
    v_iade := create_return(
      p_account_id, p_iade, null, false,
      coalesce(p_gerekce, 'Konsinye kapanışı'),
      case when p_client_key is null then null else p_client_key || '-i' end);
    v_iade_id := (v_iade->>'id')::uuid;
  end if;

  -- Kapanışın SONUCU dönüyor: pazarlamacı "kaç kaldı" sorusunu ekrandan
  -- tekrar sormasın.
  return jsonb_build_object(
    'shipment_id', v_satis_id, 'return_id', v_iade_id,
    'borc', v_borc,
    'kalan_konsinye', open_consignment(p_account_id),
    'bakiye', (select balance_cache from accounts where id = p_account_id));
end $$;

grant execute on function cheque_transition_ok(cek_durum, cek_durum) to authenticated;
grant execute on function set_cheque_status(uuid, cek_durum, text, text) to authenticated;
grant execute on function cheque_calendar(uuid, date, date, cek_durum) to authenticated;
grant execute on function notify_due_cheques(integer) to authenticated;
grant execute on function create_return(uuid, jsonb, uuid, boolean, text, text) to authenticated;
grant execute on function open_consignment_detail(uuid) to authenticated;
grant execute on function settle_consignment(uuid, jsonb, jsonb, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- İADE EDİLEBİLİRLER
--
-- "Bu cariye ne çıktı, ne kadarı geri geldi." Ekran, iade edilemeyecek bir
-- satırı hiç göstermemeli: kullanıcı adet yazıp reddedilmeyi öğrenmesin.
-- ---------------------------------------------------------------------------
create or replace function returnable_items(p_account_id uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  with cikan as (
    select si.product_id,
           sum(si.adet) as adet,
           bool_or(s.borclandirir) as borclandirdi,
           max(s.created_at) as son
    from shipments s join shipment_items si on si.shipment_id = s.id
    where s.account_id = p_account_id
    group by si.product_id
  ),
  iade as (
    select ri.product_id, sum(ri.adet) as adet
    from returns r join return_items ri on ri.return_id = r.id
    where r.account_id = p_account_id
    group by ri.product_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'product_id', c.product_id, 'ad', p.ad, 'barkod', p.barkod,
      'yayinevi', pub.ad,
      'cikan', c.adet, 'iade', coalesce(i.adet, 0),
      'kalan', c.adet - coalesce(i.adet, 0),
      -- Borçlandıran teslimattan geldiyse iade borcu DÜŞÜRÜR; konsinyeden
      -- geldiyse yalnızca açık konsinyeyi azaltır (K45).
      'borclandirdi', c.borclandirdi,
      'birim_fiyat', (select si.birim_fiyat
                      from shipment_items si join shipments sh on sh.id = si.shipment_id
                      where sh.account_id = p_account_id
                        and si.product_id = c.product_id
                      order by sh.created_at desc limit 1),
      'iskonto_orani', (select si.iskonto_orani
                        from shipment_items si join shipments sh on sh.id = si.shipment_id
                        where sh.account_id = p_account_id
                          and si.product_id = c.product_id
                        order by sh.created_at desc limit 1))
    order by c.son desc), '[]'::jsonb)
  from cikan c
  join products p on p.id = c.product_id
  left join publishers pub on pub.id = p.publisher_id
  left join iade i on i.product_id = c.product_id
  where c.adet - coalesce(i.adet, 0) > 0
    and p_account_id in (select auth_visible_accounts());
$$;

grant execute on function returnable_items(uuid) to authenticated;
