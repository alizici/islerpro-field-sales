-- =============================================================================
-- 0026 · trg_refresh_balance düzeltmesi
--
-- HATA: tek bir CASE ifadesi içinde üç farklı tablonun alanları okunuyordu:
--
--   case tg_table_name
--     when 'shipment_items'      then (... new.shipment_id ...)
--     when 'payment_allocations' then (... new.payment_id  ...)
--     when 'return_items'        then (... new.return_id   ...)
--   end
--
-- plpgsql bu ifadeyi TEK bir sorgu olarak hazırlar ve NEW kaydının TÜM
-- alanlarını çözmeye çalışır. shipment_items üzerinde tetiklendiğinde
-- `new.payment_id` diye bir alan olmadığı için:
--
--   ERROR: record "new" has no field "payment_id"
--
-- Sonucu: hiçbir teslimat, tahsilat veya iade bakiyeyi güncelleyemiyordu.
-- Bugüne kadar görünmedi çünkü ilk gerçek sevkiyat şimdi yazıldı.
--
-- Düzeltme: her tablo AYRI bir dalda, ayrı sorgu olarak çözülür.
-- =============================================================================

create or replace function trg_refresh_balance() returns trigger
language plpgsql as $$
declare v_account uuid;
begin
  if tg_table_name = 'shipment_items' then
    select s.account_id into v_account from shipments s
    where s.id = coalesce(new.shipment_id, old.shipment_id);
  elsif tg_table_name = 'payment_allocations' then
    select p.account_id into v_account from payments p
    where p.id = coalesce(new.payment_id, old.payment_id);
  elsif tg_table_name = 'return_items' then
    select r.account_id into v_account from returns r
    where r.id = coalesce(new.return_id, old.return_id);
  end if;

  if v_account is not null then
    perform refresh_account_balance(v_account);
  end if;
  return null;
end $$;
