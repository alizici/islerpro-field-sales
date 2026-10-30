-- =============================================================================
-- 0008 · Türetme fonksiyonları ve tetikleyiciler
-- Kararlar: K8 K11 K25 K29 K45 K48 · V6 V8
-- =============================================================================

-- ---------------------------------------------------------------------------
-- K29 · BAKİYE TÜRETİLMİŞTİR, YAZILMAZ
-- Yazan tek yer burasıdır; uygulama kodu balance_cache'e asla dokunmaz.
-- ---------------------------------------------------------------------------
create or replace function calc_account_balance(p_account uuid)
returns numeric language sql stable as $$
  select coalesce((
      select sum(si.satir_tutari)
      from shipments s join shipment_items si on si.shipment_id = s.id
      where s.account_id = p_account and s.borclandirir
  ),0)
  - coalesce((
      select sum(pa.tutar)
      from payment_allocations pa join payments p on p.id = pa.payment_id
      where p.account_id = p_account
  ),0)
  - coalesce((
      select sum(ri.satir_tutari)
      from returns r join return_items ri on ri.return_id = r.id
      where r.account_id = p_account and r.bakiyeyi_azaltir
  ),0);
$$;

create or replace function refresh_account_balance(p_account uuid)
returns void language sql as $$
  update accounts set balance_cache = calc_account_balance(p_account)
  where id = p_account;
$$;

create or replace function trg_refresh_balance() returns trigger
language plpgsql as $$
declare v_account uuid;
begin
  v_account := coalesce(
    (case tg_table_name
       when 'shipment_items'      then (select account_id from shipments where id = coalesce(new.shipment_id, old.shipment_id))
       when 'payment_allocations' then (select account_id from payments  where id = coalesce(new.payment_id,  old.payment_id))
       when 'return_items'        then (select account_id from returns   where id = coalesce(new.return_id,   old.return_id))
     end));
  if v_account is not null then perform refresh_account_balance(v_account); end if;
  return null;
end $$;

create trigger t_bal_ship  after insert or update or delete on shipment_items
  for each row execute function trg_refresh_balance();
create trigger t_bal_pay   after insert or update or delete on payment_allocations
  for each row execute function trg_refresh_balance();
create trigger t_bal_ret   after insert or update or delete on return_items
  for each row execute function trg_refresh_balance();

-- ---------------------------------------------------------------------------
-- K11 · TOPLAM RİSK = bakiye + portföydeki vadesi gelmemiş çek
-- Limit kontrolü BUNA bakar. Konsinye GİRMEZ (Y-13) — mülkiyet hâlâ dükkanda.
-- ---------------------------------------------------------------------------
create or replace function account_total_risk(p_account uuid)
returns numeric language sql stable as $$
  select (select balance_cache from accounts where id = p_account)
       + coalesce((select sum(tutar) from cheques
                   where account_id = p_account and durum in ('portfoyde','tahsilde')),0);
$$;

-- K45 · Kalan konsinye TÜRETİLİR — defteri yoktur.
--   bırakılan (tip=teslimat, borclandirir=false) − satılan (tip=konsinye_satis) − iade
create or replace function open_consignment(p_account uuid, p_product uuid default null)
returns numeric language sql stable as $$
  select coalesce((
      select sum(si.adet) from shipments s join shipment_items si on si.shipment_id = s.id
      where s.account_id = p_account and s.tip = 'teslimat' and not s.borclandirir
        and (p_product is null or si.product_id = p_product)),0)
  - coalesce((
      select sum(si.adet) from shipments s join shipment_items si on si.shipment_id = s.id
      where s.account_id = p_account and s.tip = 'konsinye_satis'
        and (p_product is null or si.product_id = p_product)),0)
  - coalesce((
      select sum(ri.adet) from returns r join return_items ri on ri.return_id = r.id
      where r.account_id = p_account and not r.bakiyeyi_azaltir
        and (p_product is null or ri.product_id = p_product)),0);
$$;

-- ---------------------------------------------------------------------------
-- K25 · İSKONTO ÇÖZÜMLEME SIRASI
--   discount_rules → accounts.discount_tier ezer → (elle) → tavan kontrolü
--   store_products.varsayilan_iskonto YALNIZCA kural yoksa devreye girer.
-- Taban her zaman store_products.satis_fiyat'tır; etiket_fiyat hesaba girmez.
-- ---------------------------------------------------------------------------
create or replace function resolve_discount(
  p_store uuid, p_account uuid, p_product uuid, p_adet integer)
returns numeric language plpgsql stable as $$
declare
  v_tip account_tipi; v_tier text; v_pub uuid; v_rule numeric; v_default numeric;
begin
  select tip, discount_tier into v_tip, v_tier from accounts where id = p_account;
  select publisher_id into v_pub from products where id = p_product;

  -- 1) Kural tabanı: en spesifik + en yüksek adet kademesi
  select r.iskonto_orani into v_rule
  from discount_rules r
  where r.store_id = p_store
    and (r.account_tip  is null or r.account_tip  = v_tip)
    and (r.product_id   is null or r.product_id   = p_product)
    and (r.publisher_id is null or r.publisher_id = v_pub)
    and r.min_adet <= p_adet
  order by r.oncelik asc,
           (r.product_id is not null) desc,
           (r.publisher_id is not null) desc,
           r.min_adet desc
  limit 1;

  -- 2) Cariye tanımlı kademe kuralı EZER
  if v_tier is not null then
    select r.iskonto_orani into v_rule
    from discount_rules r
    where r.store_id = p_store and r.min_adet <= p_adet
      and (r.product_id is null or r.product_id = p_product)
      and (r.publisher_id is null or r.publisher_id = v_pub)
      and r.oncelik = 0                       -- tier kuralları oncelik 0 ile tanımlanır
    order by r.min_adet desc limit 1;
  end if;

  if v_rule is not null then return v_rule; end if;

  -- 3) Kural yoksa ürünün dükkan varsayılanı
  select varsayilan_iskonto into v_default
  from store_products where store_id = p_store and product_id = p_product;
  return coalesce(v_default, 0);
end $$;

-- V6 · Satır tutarı: satis_fiyat × (1 − iskonto) × adet. Ara sonuç yuvarlanmaz;
-- yalnızca yazılırken 2 haneye yuvarlanır (V8).
create or replace function line_total(p_fiyat numeric, p_iskonto numeric, p_adet integer)
returns numeric language sql immutable as $$
  select round(p_fiyat * (1 - coalesce(p_iskonto,0)) * p_adet, 2);
$$;

-- ---------------------------------------------------------------------------
-- K48 · FIFO MAHSUP — en eski açık borçtan başlar, elle değiştirilebilir.
-- Artan tutar dağıtılmadan kalır (avans) ve bakiyeden düşer.
-- ---------------------------------------------------------------------------
create or replace function allocate_payment_fifo(p_payment uuid)
returns void language plpgsql as $$
declare
  v_account uuid; v_kalan numeric; r record; v_acik numeric;
begin
  select account_id, tutar into v_account, v_kalan from payments where id = p_payment;
  delete from payment_allocations where payment_id = p_payment;

  for r in
    select s.id,
           (select coalesce(sum(si.satir_tutari),0) from shipment_items si where si.shipment_id = s.id) as tutar,
           (select coalesce(sum(pa.tutar),0) from payment_allocations pa where pa.shipment_id = s.id)   as odenen
    from shipments s
    where s.account_id = v_account and s.borclandirir
    order by s.teslim_edildi_at asc
  loop
    exit when v_kalan <= 0;
    v_acik := r.tutar - r.odenen;
    if v_acik > 0 then
      insert into payment_allocations(payment_id, shipment_id, tutar)
      values (p_payment, r.id, least(v_kalan, v_acik));
      v_kalan := v_kalan - least(v_kalan, v_acik);
    end if;
  end loop;
  perform refresh_account_balance(v_account);
end $$;

-- Teslimat düzeyinde ödeme durumu — TÜRETİLİR, saklanmaz (K48).
create or replace function shipment_payment_status(p_shipment uuid)
returns text language sql stable as $$
  select case
    when coalesce(sum(pa.tutar),0) <= 0 then 'odenmedi'
    when coalesce(sum(pa.tutar),0) >= (select coalesce(sum(satir_tutari),0)
                                       from shipment_items where shipment_id = p_shipment)
      then 'odendi'
    else 'kismi' end
  from payment_allocations pa where pa.shipment_id = p_shipment;
$$;

-- ---------------------------------------------------------------------------
-- K8 · KAPALI DÖNEME GERİYE DÖNÜK İŞLEM GİRİLEMEZ
-- Düzeltme, açık dönemde ters kayıtla yapılır.
-- ---------------------------------------------------------------------------
create or replace function trg_period_locked() returns trigger
language plpgsql as $$
declare v_status period_durum;
begin
  select status into v_status from periods where id = new.period_id;
  if v_status = 'kapali' then
    raise exception 'Kapalı döneme işlem girilemez (K8). Açık dönemde ters kayıt atın.';
  end if;
  return new;
end $$;

create trigger t_lock_req  before insert or update on requests
  for each row execute function trg_period_locked();
create trigger t_lock_ord  before insert or update on orders
  for each row execute function trg_period_locked();
create trigger t_lock_shp  before insert or update on shipments
  for each row execute function trg_period_locked();
create trigger t_lock_pay  before insert or update on payments
  for each row execute function trg_period_locked();
create trigger t_lock_ret  before insert or update on returns
  for each row execute function trg_period_locked();

-- C-2 · Teslimat depo SAYACINI düşürür (defter değil, sayaç).
-- Excel yüklemesi sayacı sıfırdan yazar — o bir mutabakat anıdır.
create or replace function trg_stok_sayac() returns trigger
language plpgsql as $$
declare v_store uuid; v_tip shipment_tipi;
begin
  select store_id, tip into v_store, v_tip from shipments
   where id = coalesce(new.shipment_id, old.shipment_id);
  if v_tip <> 'teslimat' then return null; end if;      -- yalnızca fiziksel hareket
  if tg_op = 'INSERT' then
    update store_products set stok_adedi = stok_adedi - new.adet
     where store_id = v_store and product_id = new.product_id and stok_takibi;
  elsif tg_op = 'DELETE' then
    update store_products set stok_adedi = stok_adedi + old.adet
     where store_id = v_store and product_id = old.product_id and stok_takibi;
  end if;
  return null;
end $$;

create trigger t_stok after insert or delete on shipment_items
  for each row execute function trg_stok_sayac();
