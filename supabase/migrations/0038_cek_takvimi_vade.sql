-- Vade takvimi çeklerinde VADE TARİHİ eksikti.
--
-- `cheque_calendar` iki yerde çek nesnesi kuruyor: gecikmişler ve gün
-- gruplarındakiler. Gecikmişlerde `due_date` var, gün gruplarında YOK —
-- gün başlığı zaten tarihi taşıdığı için gereksiz görünmüş. Ama çek
-- diyaloğu tek bir çeki gösterirken kendi vadesini yazıyor ve istemci
-- `due_date`'i zorunlu alan olarak okuyor: 90 günlük pencerede tek bir
-- çek olduğu anda ekranın tamamı
--   "type 'Null' is not a subtype of type 'String' in type cast"
-- ile boş kalıyordu.
--
-- Doğru yer burası: gün başlığının tarihi, çekin vadesi DEĞİLDİR — aynı
-- güne düşmeleri bir tesadüf değil ama aynı OLGU da değil. İstemcinin
-- tarihi gün başlığından "tahmin etmesi" hem kırılgan hem yanlış.
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
                     -- Eksik olan alan buydu.
                     'due_date', due_date,
                     'gun', (due_date - current_date),
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

grant execute on function cheque_calendar(uuid, date, date, cek_durum)
  to authenticated;
