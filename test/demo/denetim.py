#!/usr/bin/env python3
"""Demo verisinin KAPSAMINI denetler.

"Her ekran açılıyor" ile "her ekran işini yapabiliyor" aynı şey değil. Bu
denetim ikincisini sorar: yaşlandırmanın dört kovası dolu mu, limitini aşan
cari var mı, gecikmiş talep var mı, çekin her durumu temsil ediliyor mu.
"""
import os, sys, pathlib, psycopg2

KOK = pathlib.Path(__file__).resolve().parents[2]
env = {}
for dosya in (".env.local", ".env"):
    p = KOK / dosya
    if p.exists():
        for satir in p.read_text(encoding="utf-8").splitlines():
            if "=" in satir and not satir.strip().startswith("#"):
                k, v = satir.split("=", 1)
                env.setdefault(k.strip(), v.strip())
ref = env["SUPABASE_URL"].removeprefix("https://").removesuffix(".supabase.co")
c = psycopg2.connect(
    "host=aws-0-eu-central-1.pooler.supabase.com port=6543 dbname=postgres "
    f"user=postgres.{ref} password={env['SUPABASE_DB_PASSWORD']} sslmode=require")
cur = c.cursor()
cur.execute("select id, tenant_id from stores where ad = 'Karaköprü Şube'")
r = cur.fetchone()
if not r:
    print("Demo dükkanı yok — önce demo_veri.py çalıştırın."); sys.exit(1)
SID, TID = r

DENETIM = [
 ("CARİ", [
  ("cari",                "select count(*) from accounts where store_id=%(s)s"),
  ("kurumsal",            "select count(*) from accounts where store_id=%(s)s and tip='kurum'"),
  ("öğretmen (K7)",       "select count(*) from accounts where store_id=%(s)s and tip='ogretmen'"),
  ("pasif/tahsilatta",    "select count(*) from accounts where store_id=%(s)s and durum<>'aktif'"),
  ("atanmamış",           "select count(*) from accounts a where a.store_id=%(s)s and not exists (select 1 from assignments g where g.account_id=a.id and g.aktif)"),
  ("limitini aşan",       "select count(*) from accounts where store_id=%(s)s and credit_limit>0 and balance_cache>credit_limit"),
  ("borçlu",              "select count(*) from accounts where store_id=%(s)s and balance_cache>0"),
  ("kuruma taşınmış",     "select count(*) from account_transfers t join accounts a on a.id=t.account_id where a.store_id=%(s)s"),
 ]),
 ("TALEP · SİPARİŞ", [
  ("talep",               "select count(*) from requests where store_id=%(s)s"),
  ("bekleyen",            "select count(*) from requests where store_id=%(s)s and durum='gonderildi'"),
  ("24 saati geçen (V7)", "select count(*) from requests where store_id=%(s)s and durum='gonderildi' and created_at<now()-interval '24 hours'"),
  ("kısmi kararlı (K37)", "select count(distinct r.id) from requests r join request_items i on i.request_id=r.id where r.store_id=%(s)s and i.durum='reddedildi'"),
  ("iptal",               "select count(*) from requests where store_id=%(s)s and durum='iptal'"),
  ("sipariş",             "select count(*) from orders where store_id=%(s)s"),
  ("hazırlık kutusunda",  "select count(*) from orders where store_id=%(s)s and durum='olusturuldu'"),
  ("hazır (K46)",         "select count(*) from orders where store_id=%(s)s and durum='hazir'"),
  ("onay gerekçeli",      "select count(*) from orders where store_id=%(s)s and onay_gerekce is not null"),
 ]),
 ("TESLİMAT · BORÇ", [
  ("teslimat",            "select count(*) from shipments where store_id=%(s)s"),
  ("borçlandıran (K26)",  "select count(*) from shipments where store_id=%(s)s and borclandirir"),
  ("konsinye (C-1)",      "select count(*) from shipments where store_id=%(s)s and tip='teslimat' and not borclandirir"),
  ("numune (K38)",        "select count(*) from shipments where store_id=%(s)s and tip='numune'"),
  ("konsinye satış",      "select count(*) from shipments where store_id=%(s)s and tip='konsinye_satis'"),
  ("backorder kalan",     "select count(*) from order_items oi join orders o on o.id=oi.order_id where o.store_id=%(s)s and oi.adet>coalesce((select sum(si.adet) from shipment_items si where si.order_item_id=oi.id),0)"),
  ("iade",                "select count(*) from returns where store_id=%(s)s"),
 ]),
 ("YAŞLANDIRMA KOVALARI", [
  ("0-30 gün",   "select count(*) from shipments where store_id=%(s)s and borclandirir and teslim_edildi_at>=now()-interval '30 days'"),
  ("31-60 gün",  "select count(*) from shipments where store_id=%(s)s and borclandirir and teslim_edildi_at<now()-interval '30 days' and teslim_edildi_at>=now()-interval '60 days'"),
  ("61-90 gün",  "select count(*) from shipments where store_id=%(s)s and borclandirir and teslim_edildi_at<now()-interval '60 days' and teslim_edildi_at>=now()-interval '90 days'"),
  ("90+ gün",    "select count(*) from shipments where store_id=%(s)s and borclandirir and teslim_edildi_at<now()-interval '90 days'"),
 ]),
 ("TAHSİLAT · ÇEK", [
  ("tahsilat",            "select count(*) from payments where store_id=%(s)s"),
  ("nakit",               "select count(*) from payments where store_id=%(s)s and yontem='nakit'"),
  ("havale",              "select count(*) from payments where store_id=%(s)s and yontem='havale'"),
  ("çek/senet",           "select count(*) from payments where store_id=%(s)s and yontem in ('cek','senet')"),
  ("kısmi mahsup (K48)",  "select count(*) from payment_allocations pa join payments p on p.id=pa.payment_id where p.store_id=%(s)s"),
  ("çek · portföyde",     "select count(*) from cheques where store_id=%(s)s and durum='portfoyde'"),
  ("çek · tahsilde",      "select count(*) from cheques where store_id=%(s)s and durum='tahsilde'"),
  ("çek · tahsil edildi", "select count(*) from cheques where store_id=%(s)s and durum='tahsil_edildi'"),
  ("çek · karşılıksız",   "select count(*) from cheques where store_id=%(s)s and durum='karsiliksiz'"),
  ("çek · ciro edildi",   "select count(*) from cheques where store_id=%(s)s and durum='ciro_edildi'"),
  ("çek · vadesi geçmiş", "select count(*) from cheques where store_id=%(s)s and due_date<current_date and durum in ('portfoyde','tahsilde')"),
 ]),
 ("SAHA", [
  ("ziyaret",             "select count(*) from visits where store_id=%(s)s"),
  ("çıktılı ziyaret",     "select count(*) from visits v where v.store_id=%(s)s and (exists(select 1 from requests r where r.visit_id=v.id) or exists(select 1 from payments p where p.visit_id=v.id))"),
  ("çıktısız (K10)",      "select count(*) from visits v where v.store_id=%(s)s and not exists(select 1 from requests r where r.visit_id=v.id) and not exists(select 1 from payments p where p.visit_id=v.id)"),
  ("rota durağı",         "select count(*) from visit_plans where store_id=%(s)s"),
 ]),
 ("DENEME (Faz 9)", [
  ("program",             "select count(*) from exam_programs where store_id=%(s)s"),
  ("takvime bağlı",       "select count(*) from exam_programs where store_id=%(s)s and modu='takvim_bagli'"),
  ("serbest periyot",     "select count(*) from exam_programs where store_id=%(s)s and modu='serbest_periyot'"),
  ("plan kalemi",         "select count(*) from exam_deliveries e join exam_programs p on p.id=e.exam_program_id where p.store_id=%(s)s"),
  ("teslim edilmiş",      "select count(*) from exam_deliveries e join exam_programs p on p.id=e.exam_program_id where p.store_id=%(s)s and e.durum='teslim_edildi'"),
  ("uygulanmış (K47)",    "select count(*) from exam_deliveries e join exam_programs p on p.id=e.exam_program_id where p.store_id=%(s)s and e.durum='uygulandi'"),
  ("ertelenmiş",          "select count(*) from exam_deliveries e join exam_programs p on p.id=e.exam_program_id where p.store_id=%(s)s and e.onceki_tarih is not null"),
  ("takvim kaydı (K20)",  "select count(*) from deneme_details d join store_products sp on sp.product_id=d.product_id where sp.store_id=%(s)s"),
  ("Türkiye Geneli",      "select count(*) from deneme_details d join store_products sp on sp.product_id=d.product_id where sp.store_id=%(s)s and d.deneme_turu='turkiye_geneli'"),
  ("sınıf mevcudu (K22)", "select count(*) from account_enrollments e join accounts a on a.id=e.account_id where a.store_id=%(s)s"),
 ]),
 ("KATALOG · KURUM", [
  ("fiyatlı ürün (K12)",  "select count(*) from store_products where store_id=%(s)s and satis_fiyat is not null"),
  ("stoklu",              "select count(*) from store_products where store_id=%(s)s and stok_adedi>0"),
  ("stok takibi kapalı",  "select count(*) from store_products where store_id=%(s)s and not stok_takibi"),
  ("baskı grubu (K23)",   "select count(*) from products p join store_products sp on sp.product_id=p.id where sp.store_id=%(s)s and p.baski_grubu_id is not null"),
  ("bağlı kurum",         "select count(*) from institution_store_links where store_id=%(s)s"),
  ("zincir kurum (K18)",  "select count(*) from institutions where parent_id is not null"),
  ("kurum yetkilisi",     "select count(*) from institution_contacts where tenant_id=%(t)s"),
  ("öğretmen daveti",     "select count(*) from invites where store_id=%(s)s"),
  ("kurum üyeliği (K3)",  "select count(*) from institution_memberships"),
  ("onay bekleyen üye",   "select count(*) from institution_memberships where status='onay_bekliyor'"),
 ]),
 ("KURAL VE AYAR", [
  ("iskonto kuralı (K25)","select count(*) from discount_rules where store_id=%(s)s"),
  ("iskonto tavanı",      "select count(*) from discount_caps where store_id=%(s)s"),
  ("numune limiti (K38)", "select count(*) from sample_limits where store_id=%(s)s"),
  ("kayıtlı rapor (K50)", "select count(*) from saved_reports where store_id=%(s)s"),
  ("bildirim (K41)",      "select count(*) from notifications where tenant_id=%(t)s"),
  ("ekip üyesi",          "select count(*) from memberships where store_id=%(s)s"),
 ]),
]

eksik = []
for baslik, satirlar in DENETIM:
    print(f"\n\033[1m{baslik}\033[0m")
    for ad, q in satirlar:
        cur.execute(q, {"s": SID, "t": TID})
        n = cur.fetchone()[0]
        if n:
            print(f"  \033[32m✓\033[0m {ad:22} {n}")
        else:
            eksik.append(f"{baslik} · {ad}")
            print(f"  \033[31m✗\033[0m {ad:22} 0")

print(f"\n\033[1m{'─'*54}\033[0m")
if eksik:
    print(f"  \033[31mveri girilmemiş {len(eksik)} alan:\033[0m")
    for e in eksik:
        print(f"    · {e}")
else:
    print("  \033[32mher alanda veri var\033[0m")
c.close()
sys.exit(1 if eksik else 0)
