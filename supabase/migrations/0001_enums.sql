-- =============================================================================
-- 0001 · Uzantılar ve enum tipleri
-- Kararlar: K5 K8 K11 K13 K15 K18 K26 K34 K37 K47 K48 K49
-- =============================================================================
create extension if not exists "pgcrypto";
create extension if not exists "pg_trgm";      -- ürün/kurum adı benzerlik araması

-- Organizasyon ------------------------------------------------------------
create type app_role      as enum ('platform_admin','isletme_sahibi','dukkan_muduru',
                                   'pazarlamaci','hazirlik');
create type member_status as enum ('davet_edildi','onay_bekliyor','aktif','pasif');

-- Kurum dizini (K18) ------------------------------------------------------
create type kurum_tipi    as enum ('okul','kurs_merkezi','diger');
create type kademe_tipi   as enum ('anaokulu','ilkokul','ortaokul','lise');

-- Cari (K5) ---------------------------------------------------------------
create type account_tipi   as enum ('kurum','ogretmen','diger');
create type account_durum  as enum ('aktif','pasif','tahsilatta','kapali');

-- Dönem (K8) — üç durum; sayım aşaması yoktur (K45)
create type period_durum   as enum ('planlandi','aktif','kapali');

-- Katalog (K15) -----------------------------------------------------------
create type katalog_tipi   as enum ('kitap','deneme');

-- Talep (K37) -------------------------------------------------------------
create type request_durum      as enum ('taslak','gonderildi','incelemede',
                                        'karara_baglandi','tamamen_reddedildi','iptal');
create type request_item_durum as enum ('beklemede','onaylandi','reddedildi');

-- Sipariş (K46) -----------------------------------------------------------
create type order_tipi  as enum ('satis','konsinye','numune');
create type order_durum  as enum ('olusturuldu','onay_bekliyor','reddedildi',
                                  'hazirlaniyor','hazir','sevk_edildi',
                                  'kismi_teslim','teslim_edildi','kapandi','iptal');

-- Teslimat (K34 · C-1) ----------------------------------------------------
create type shipment_tipi   as enum ('teslimat','konsinye_satis','numune');
create type shipment_kaynak as enum ('depo','elden');

-- Tahsilat (K48) ve çek (K11) --------------------------------------------
create type odeme_yontem as enum ('nakit','havale','kart','cek','senet');
create type cek_tipi     as enum ('cek','senet');
create type cek_durum    as enum ('portfoyde','tahsilde','tahsil_edildi',
                                  'ciro_edildi','karsiliksiz','iade_edildi');

-- Deneme (K20 · K47) ------------------------------------------------------
create type deneme_turu     as enum ('takvim','turkiye_geneli','deneme_kulubu','resmi_sinav');
create type exam_prog_modu  as enum ('takvim_bagli','serbest_periyot');
create type exam_teslim_durum as enum ('planlandi','ertelendi','hazirlaniyor',
                                       'teslim_edildi','uygulandi','kapandi','iptal');

-- Toplu aktarma (K49) -----------------------------------------------------
create type import_turu  as enum ('urun','fiyat_iskonto','stok','kurum',
                                  'deneme_takvimi','acilis_bakiyesi');
create type import_durum as enum ('hazirlaniyor','onaylandi','geri_alindi','hatali');
