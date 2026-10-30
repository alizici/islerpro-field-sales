-- =============================================================================
-- 0027 · Bakiye avansı görmüyordu + konsinye tip tutarlılığı
--
-- HATA 1 · calc_account_balance mahsupları (payment_allocations) çıkarıyordu,
-- ÖDEMELERİ değil. Sonucu: hiçbir teslimata bağlanmayan tahsilat (avans) ve
-- borçtan fazla ödeme bakiyeye HİÇ yansımıyordu.
--
--   400 ₺ borç, 450 ₺ tahsilat  →  eski: 0 ₺   ·  doğrusu: −50 ₺ (alacak)
--
-- §4.3 bunu açıkça söylüyor: "Serbest tahsilat (avans)… allocations boş kalır,
-- cari bakiyesinden düşer. Borçtan fazla ödeme de aynı yolla alacak bakiye
-- olarak durur."
--
-- Mahsup (allocations) TESLİMAT DÜZEYİ ödeme durumu içindir (odenmedi/kismi/
-- odendi); CARİ DÜZEYİ bakiye için değil. İkisi ayrı sorulardır.
--
-- K11 · Çek/senet ödeme değil ödeme VAADİDİR: bakiyeyi düşürmez, yalnızca
-- account_total_risk'e girer. Bu yüzden yöntem bazında dışarıda bırakılıyor.
-- =============================================================================

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
      -- Çek/senet HARİÇ — onlar vaattir, tahsil edilince ödemeye dönüşür (K11)
      select sum(p.tutar)
      from payments p
      where p.account_id = p_account and p.yontem not in ('cek','senet')
  ),0)
  - coalesce((
      select sum(ri.satir_tutari)
      from returns r join return_items ri on ri.return_id = r.id
      where r.account_id = p_account and r.bakiyeyi_azaltir
  ),0);
$$;

-- Bakiye artık payments'a da bağlı; tahsilat eklenince/silinince tazelensin.
create or replace function trg_refresh_balance_payment() returns trigger
language plpgsql as $$
begin
  perform refresh_account_balance(coalesce(new.account_id, old.account_id));
  return null;
end $$;

drop trigger if exists t_bal_payment on payments;
create trigger t_bal_payment after insert or update or delete on payments
  for each row execute function trg_refresh_balance_payment();

-- ---------------------------------------------------------------------------
-- HATA 2 · create_shipment tutarsız kombinasyona izin veriyordu.
--
-- tip ve borclandirir BAĞIMSIZ alanlardır (C-1) ama her bileşim anlamlı
-- değildir:
--   teslimat        + borclandirir=true   → normal satış teslimatı
--   teslimat        + borclandirir=false  → KONSİNYE BIRAKMA (mülkiyet dükkanda)
--   konsinye_satis  + borclandirir=true   → konsinyeden satıldı, borç doğar
--   konsinye_satis  + borclandirir=false  → ANLAMSIZ: satış hem gerçekleşmiş
--                                           hem borç doğurmamış olamaz
--   numune          + borclandirir=true   → ANLAMSIZ: numune borç doğurmaz
--
-- Yanlış bileşim open_consignment'ı ters çevirir: konsinye bakiyesi eksiye
-- düşer ve "kalan konsinye" anlamsızlaşır.
-- ---------------------------------------------------------------------------
create or replace function check_shipment_coherence(
  p_tip shipment_tipi, p_borclandirir boolean) returns void
language plpgsql immutable as $$
begin
  if p_tip = 'konsinye_satis' and not p_borclandirir then
    raise exception 'Konsinyeden satış borç doğurmalıdır. Kitapları konsinye '
                    'BIRAKMAK için tip=teslimat + borclandirir=false kullanın.';
  end if;
  if p_tip = 'numune' and p_borclandirir then
    raise exception 'Numune çıkışı borç doğurmaz (K38)';
  end if;
end $$;

grant execute on function check_shipment_coherence(shipment_tipi, boolean) to authenticated;

-- create_shipment tutarlılık kontrolüyle yeniden tanımlanıyor
create or replace function create_shipment(
  p_account_id uuid,
  p_items jsonb,
  p_order_id uuid default null,
  p_borclandirir boolean default true,
  p_tip shipment_tipi default 'teslimat',
  p_teslim_alan_ad text default null,
  p_kaynak shipment_kaynak default 'depo',
  p_belge_no text default null,
  p_client_key text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  a accounts%rowtype; v_id uuid; v_period uuid; it jsonb;
  v_pid uuid; v_adet int; v_fiyat numeric; v_isk numeric; v_maliyet numeric;
  v_tutar numeric; v_toplam numeric := 0; v_n int := 0; v_kalan int;
begin
  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'Teslimatta en az bir kalem olmalı';
  end if;
  perform check_shipment_coherence(p_tip, p_borclandirir);
  select * into a from accounts where id = p_account_id;
  if a.id is null or a.id not in (select auth_visible_accounts()) then
    raise exception 'Cari bulunamadı veya yetkiniz yok';
  end if;

  if p_client_key is not null then
    select id into v_id from shipments
    where tenant_id = a.tenant_id and client_key = p_client_key;
    if v_id is not null then
      return jsonb_build_object('id', v_id, 'yeni', false);
    end if;
  end if;

  select id into v_period from periods
  where tenant_id = a.tenant_id and status = 'aktif'
  order by starts_on desc limit 1;
  if v_period is null then raise exception 'Aktif dönem yok'; end if;

  insert into shipments (tenant_id, store_id, account_id, institution_id,
                         period_id, order_id, tip, borclandirir, kaynak,
                         teslim_alan_ad, teslim_edildi_at, belge_no, client_key)
  values (a.tenant_id, a.store_id, p_account_id, a.institution_id, v_period,
          p_order_id, p_tip, p_borclandirir, p_kaynak,
          nullif(trim(coalesce(p_teslim_alan_ad, '')), ''), now(),
          nullif(trim(coalesce(p_belge_no, '')), ''), p_client_key)
  returning id into v_id;

  for it in select * from jsonb_array_elements(p_items) loop
    v_adet := coalesce((it->>'adet')::int, 0);
    if v_adet <= 0 then raise exception 'Adet sıfırdan büyük olmalı'; end if;

    if (it->>'order_item_id') is not null then
      select oi.product_id, oi.birim_fiyat, oi.iskonto_orani, oi.birim_maliyet,
             oi.adet - coalesce((select sum(si.adet) from shipment_items si
                                 where si.order_item_id = oi.id), 0)
        into v_pid, v_fiyat, v_isk, v_maliyet, v_kalan
      from order_items oi where oi.id = (it->>'order_item_id')::uuid;
      if v_pid is null then raise exception 'Sipariş kalemi bulunamadı'; end if;
      -- H-3 · sipariştekinden fazla sevk edilemez
      if v_adet > v_kalan then
        raise exception 'Bu kalemde sevk edilebilecek % adet kaldı, % istendi',
          v_kalan, v_adet;
      end if;
    else
      v_pid := (it->>'product_id')::uuid;
      if v_pid is null then raise exception 'Kalem ürüne bağlı olmalı'; end if;
      -- Siparişsiz elden teslim: fiyat teslimat anında damgalanır (K28)
      select sp.satis_fiyat, sp.alis_fiyat into v_fiyat, v_maliyet
      from store_products sp
      where sp.store_id = a.store_id and sp.product_id = v_pid;
      if v_fiyat is null then
        raise exception 'Ürünün bu dükkanda satış fiyatı yok';
      end if;
      v_isk := resolve_discount(a.store_id, p_account_id, v_pid, v_adet);
    end if;

    v_tutar := line_total(v_fiyat, v_isk, v_adet);
    insert into shipment_items (shipment_id, order_item_id, product_id, adet,
                                birim_fiyat, iskonto_orani, birim_maliyet,
                                satir_tutari)
    values (v_id, (it->>'order_item_id')::uuid, v_pid, v_adet,
            v_fiyat, v_isk, v_maliyet, v_tutar);
    v_toplam := v_toplam + v_tutar;
    v_n := v_n + 1;
  end loop;

  -- Sipariş durumu: hepsi sevk edildiyse teslim_edildi, değilse kısmi
  if p_order_id is not null then
    select coalesce(sum(oi.adet), 0) - coalesce((
             select sum(si.adet) from shipment_items si
             where si.order_item_id in (select id from order_items
                                        where order_id = p_order_id)), 0)
      into v_kalan
    from order_items oi where oi.order_id = p_order_id;

    update orders set durum = case when v_kalan <= 0 then 'teslim_edildi'
                                   else 'kismi_teslim' end::order_durum,
                      updated_at = now()
    where id = p_order_id;
  end if;

  -- K41 · teslimat bildirimi carinin kişisine/portföy sahibine
  perform notify_user(a.tenant_id, account_owner(p_account_id), 'teslimat',
    'Teslimat yapıldı', a.unvan || ' · ' || v_n || ' kalem', 'shipment', v_id);

  insert into audit_logs (tenant_id, user_id, eylem, tablo, kayit_id, detay)
  values (a.tenant_id, auth.uid(), 'create_shipment', 'shipments', v_id,
          jsonb_build_object('borclandirir', p_borclandirir,
                             'kalem', v_n, 'toplam', v_toplam));

  return jsonb_build_object('id', v_id, 'yeni', true, 'kalem', v_n,
                            'toplam', v_toplam,
                            'borclandirir', p_borclandirir,
                            'kalan_adet', coalesce(v_kalan, 0));
end $$;

grant execute on function create_shipment(uuid, jsonb, uuid, boolean, shipment_tipi, text, shipment_kaynak, text, text) to authenticated;
