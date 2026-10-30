-- K48 · Tahsilat girilirken paranın NEREYE gideceği önceden görünsün.
--
-- FIFO mahsubu `allocate_payment_fifo` yapıyor ve doğru yapıyor; ama
-- kullanıcı bunu ancak kaydettikten SONRA öğreniyor. "5.000 ₺ aldım, hangi
-- teslimat kapandı?" sorusu makbuzda cevaplanıyor — yani iş bittikten sonra.
--
-- Bu fonksiyon aynı sıralamayı OKUNUR biçimde döndürür: en eski açık borçtan
-- başlayarak, her teslimatın toplamı ve ne kadarının ödendiği. İstemci
-- girilen tutarı bu listeye kendisi dağıtıp önizleme çizer.
--
-- Sıralama `allocate_payment_fifo` ile BİREBİR aynı olmak zorunda
-- (`teslim_edildi_at asc`): farklı sıralarsa önizleme yalan söyler ve
-- kullanıcı yanlış bir şeyi onaylamış olur.
create or replace function account_open_shipments(p_account_id uuid)
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x order by x->>'tarih'), '[]'::jsonb)
  from (
    select jsonb_build_object(
             'id', s.id,
             'tarih', s.teslim_edildi_at,
             'tutar', t.tutar,
             'odenen', o.odenen,
             'kalan', t.tutar - o.odenen,
             'kalem', t.kalem) as x
    from shipments s
    cross join lateral (
      select coalesce(sum(si.satir_tutari), 0) as tutar,
             count(*)                          as kalem
      from shipment_items si where si.shipment_id = s.id
    ) t
    cross join lateral (
      select coalesce(sum(pa.tutar), 0) as odenen
      from payment_allocations pa where pa.shipment_id = s.id
    ) o
    where s.account_id = p_account_id
      and s.borclandirir
      -- Kapanmış teslimatı listelemek gürültü: mahsup ona hiç uğramayacak.
      and t.tutar - o.odenen > 0
      and s.account_id in (select auth_visible_accounts())
    order by s.teslim_edildi_at asc
  ) q;
$$;

grant execute on function account_open_shipments(uuid) to authenticated;
