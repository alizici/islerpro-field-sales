#!/usr/bin/env python3
"""
İşlerPro · uçtan uca doğrulama

Gerçek Supabase'e karşı çalışır ve PostgREST + RLS yolunu test eder —
yani uygulamanın gerçekte kullandığı yolu. Her koşuda kendi izole test
verisini kurar, sonunda temizler.

Kullanım:  python3 test/e2e/dogrula.py
Gerekli :  .env (SUPABASE_URL, SUPABASE_ANON_KEY) + SUPABASE_SERVICE_KEY
"""
import datetime, json, os, sys, time, urllib.request, urllib.error, urllib.parse, uuid

# ── Altyapı ────────────────────────────────────────────────────────────────
ENV = {}
for line in open(os.path.join(os.path.dirname(__file__), "..", "..", ".env"), encoding="utf-8"):
    if "=" in line and not line.strip().startswith("#"):
        k, v = line.strip().split("=", 1)
        ENV[k] = v
URL = ENV["SUPABASE_URL"]
ANON = ENV["SUPABASE_ANON_KEY"]
SERVICE = os.environ.get("SUPABASE_SERVICE_KEY", "")

gecti, kaldi = [], []

def http(path, method="GET", token=None, body=None, key=None):
    req = urllib.request.Request(URL + path, method=method)
    req.add_header("apikey", key or ANON)
    req.add_header("Authorization", "Bearer " + (token or key or ANON))
    req.add_header("Content-Type", "application/json")
    data = json.dumps(body).encode() if body is not None else None
    try:
        with urllib.request.urlopen(req, data) as r:
            t = r.read().decode()
            return r.status, (json.loads(t) if t.strip() else None)
    except urllib.error.HTTPError as e:
        t = e.read().decode()
        try:
            return e.code, json.loads(t)
        except Exception:
            return e.code, {"raw": t}

def rpc(fn, token=None, **params):
    return http(f"/rest/v1/rpc/{fn}", "POST", token, params)

def sec(baslik):
    print(f"\n\033[1m{baslik}\033[0m")

def kontrol(ad, kosul, detay=""):
    if kosul:
        gecti.append(ad); print(f"  \033[32m✓\033[0m {ad}")
    else:
        kaldi.append(ad); print(f"  \033[31m✗\033[0m {ad}  {detay}")

def kullanici(etiket):
    """Doğrulanmış test kullanıcısı üretir, token döndürür."""
    eposta = f"e2e-{etiket}-{uuid.uuid4().hex[:8]}@islerpro.test"
    st, r = http("/auth/v1/admin/users", "POST", key=SERVICE, body={
        "email": eposta, "password": "E2e-Test-1234", "email_confirm": True,
        "user_metadata": {"ad_soyad": f"E2E {etiket}"}})
    assert st == 200, f"kullanıcı açılamadı: {r}"
    uid = r["id"]
    st, r = http("/auth/v1/token?grant_type=password", "POST",
                 body={"email": eposta, "password": "E2e-Test-1234"})
    assert st == 200, f"giriş yapılamadı: {r}"
    return uid, r["access_token"], eposta

# Koşu boyunca üretilen ve kendiliğinden silinmeyen kayıtlar.
# Kurum dizini ORTAKTIR (K4) — test kurumu bırakırsak herkesin dizinini kirletir.
cop = {"institutions": [], "publishers": [], "tenants": []}

def temizle(uidler):
    """FK döngüsünü açarak siler:
       institutions.ekleyen_tenant_id → tenants  (ON DELETE yok)
       accounts.institution_id        → institutions (ON DELETE yok)
    Bu yüzden sıra: bağı kopar → tenant (cascade) → kurum → yayınevi → kullanıcı."""
    sorun = []
    # Ticari hareketler ÖNCE silinir. products silinirken request_items hâlâ
    # duruyorsa cascade sırası yüzünden hata verir — üstelik bu FK üretimde
    # DOĞRUDUR: talebe girmiş bir ürün silinemez.
    for t_ in cop["tenants"]:
        for tablo in ("payment_allocations", "cheques", "payments", "returns",
                      "shipments", "orders", "requests", "import_batches",
                      # exam_deliveries shipments'tan SONRA silinir:
                      # shipments.exam_delivery_id ona bakıyor.
                      "exam_deliveries", "exam_programs"):
            if tablo == "exam_deliveries":
                # tenant_id taşımıyor; programlar üzerinden silinir
                st_, pl = http(
                    f"/rest/v1/exam_programs?select=id&tenant_id=eq.{t_}",
                    key=SERVICE)
                for pr in (pl or []):
                    http(f"/rest/v1/exam_deliveries?exam_program_id=eq.{pr['id']}",
                         "DELETE", key=SERVICE)
                continue
            if tablo == "payment_allocations":
                # tenant_id taşımıyor; ödemeler üzerinden silinir
                st_, pl = http(f"/rest/v1/payments?select=id&tenant_id=eq.{t_}",
                               key=SERVICE)
                for pay in (pl or []):
                    http(f"/rest/v1/payment_allocations?payment_id=eq.{pay['id']}",
                         "DELETE", key=SERVICE)
                continue
            st_, r_ = http(f"/rest/v1/{tablo}?tenant_id=eq.{t_}", "DELETE",
                           key=SERVICE)
            if st_ >= 400:
                sorun.append(f"{tablo} (tenant {t_[:8]}): {r_}")
    # Saha (0031): visits ↔ institution_contacts FK'si İKİ YÖNLÜDÜR
    # (visits.gorusulen_contact_id ve institution_contacts.visit_id). Hangisini
    # önce silersek silelim diğeri engeller — bu yüzden önce bağlar koparılır.
    for t_ in cop["tenants"]:
        # Deneme kalemleri ürün tablosunda durur; talepler silindikten sonra
        # gidebilirler (request_items FK'si).
        http(f"/rest/v1/products?tenant_id=eq.{t_}&katalog=eq.deneme",
             "DELETE", key=SERVICE)
        http(f"/rest/v1/institution_contacts?tenant_id=eq.{t_}&visit_id=not.is.null",
             "PATCH", key=SERVICE, body={"visit_id": None})
        http(f"/rest/v1/visits?tenant_id=eq.{t_}&gorusulen_contact_id=not.is.null",
             "PATCH", key=SERVICE, body={"gorusulen_contact_id": None})
        for tablo in ("devices", "visit_plans", "visits"):
            st_, r_ = http(f"/rest/v1/{tablo}?tenant_id=eq.{t_}", "DELETE",
                           key=SERVICE)
            if st_ >= 400:
                sorun.append(f"{tablo} (tenant {t_[:8]}): {r_}")

    for i in cop["institutions"]:
        http(f"/rest/v1/institutions?id=eq.{i}", "PATCH", key=SERVICE,
             body={"ekleyen_tenant_id": None})
    for tablo in ("tenants", "institutions", "publishers"):
        for i in cop[tablo]:
            st, r = http(f"/rest/v1/{tablo}?id=eq.{i}", "DELETE", key=SERVICE)
            if st >= 400:
                sorun.append(f"{tablo}/{i}: {r}")
    for u in uidler:
        http(f"/auth/v1/admin/users/{u}", "DELETE", key=SERVICE)
    if sorun:
        print("\n  \033[33m! temizlenemeyen kayıtlar\033[0m")
        for x in sorun:
            print(f"    · {x}")
    return sorun

# ── Testler ────────────────────────────────────────────────────────────────
def main():
    if not SERVICE:
        print("SUPABASE_SERVICE_KEY ortam değişkeni gerekli.", file=sys.stderr)
        return 2

    uidler = []
    try:
        # ---- Kurulum: iki AYRI işletme -------------------------------------
        sec("Kurulum · iki izole işletme")
        uidA, tokA, _ = kullanici("sahipA"); uidler.append(uidA)
        uidB, tokB, _ = kullanici("sahipB"); uidler.append(uidB)

        st, rA = rpc("bootstrap_tenant", tokA, p_unvan="A İşletme",
                     p_dukkan_ad="A Şube", p_il="Şanlıurfa", p_ilce="HALİLİYE")
        kontrol("A işletmesi kuruldu", st == 200 and "tenant_id" in (rA or {}), rA)
        st, rB = rpc("bootstrap_tenant", tokB, p_unvan="B İşletme", p_dukkan_ad="B Şube")
        kontrol("B işletmesi kuruldu", st == 200 and "tenant_id" in (rB or {}), rB)
        for r_ in (rA, rB):
            if r_ and r_.get("tenant_id"):
                cop["tenants"].append(r_["tenant_id"])

        st, r = rpc("bootstrap_tenant", tokA, p_unvan="A tekrar", p_dukkan_ad="X")
        kontrol("aynı sahip ikinci kez kuramaz", st >= 400, r)

        st, sesA = rpc("my_session", tokA)
        kontrol("my_session tek çağrıda dolu döner",
                len(sesA["memberships"]) == 1 and len(sesA["stores"]) == 1
                and len(sesA["active_periods"]) == 1, sesA)
        kontrol("K8 · iki yarıyıl açıldı", len(rA["period_ids"]) == 2)

        storeA = sesA["stores"][0]["id"]; tenantA = sesA["memberships"][0]["tenant_id"]

        # ---- RLS · tenant izolasyonu (en kritik) ---------------------------
        sec("RLS · işletmeler birbirini görmüyor (K4)")
        for tablo in ("tenants", "stores", "periods"):
            st, a = http(f"/rest/v1/{tablo}?select=id", token=tokA)
            st2, b = http(f"/rest/v1/{tablo}?select=id", token=tokB)
            ida = {x["id"] for x in a}; idb = {x["id"] for x in b}
            kontrol(f"{tablo}: A ve B kesişmiyor", ida and idb and not (ida & idb),
                    f"A={len(ida)} B={len(idb)} kesişim={len(ida & idb)}")

        st, anon = http("/rest/v1/tenants?select=id")
        kontrol("anonim hiçbir tenant görmüyor", anon == [], anon)
        st, r = http("/rest/v1/tenants", "POST", body={"unvan": "sahte"})
        kontrol("anonim yazamıyor", st >= 400, r)

        # ---- K30 · kişi kayıtları sızmıyor ---------------------------------
        sec("K30 · kişi kayıtları işletmeye özel")
        st, kurum = http("/rest/v1/institutions", "POST", token=tokA,
                         body={"ad": f"E2E Test Lisesi {uuid.uuid4().hex[:6]}",
                               "kurum_tipi": "okul", "il": "Şanlıurfa",
                               "ilce": "HALİLİYE", "ekleyen_tenant_id": tenantA})
        kontrol("kurum eklenebiliyor", st in (200, 201), kurum)
        st, kl = http("/rest/v1/institutions?select=id&order=created_at.desc&limit=1", token=tokA)
        kurumId = kl[0]["id"] if kl else None
        if kurumId:
            cop["institutions"].append(kurumId)
        if kurumId:
            st, _ = http("/rest/v1/institution_contacts", "POST", token=tokA, body={
                "tenant_id": tenantA, "institution_id": kurumId,
                "ad_soyad": "Gizli Öğretmen", "telefon": "05320000000"})
            kontrol("A kişi kaydı ekledi", st in (200, 201))
            st, bkis = http("/rest/v1/institution_contacts?select=ad_soyad", token=tokB)
            kontrol("B, A'nın kişilerini GÖREMİYOR", bkis == [], bkis)

        # ---- Yazma yüzeyi · her tabloya yazılabiliyor mu --------------------
        sec("Yazma yüzeyi (0015 regresyonu)")
        st, _ = http("/rest/v1/stores", "POST", token=tokA, body={
            "tenant_id": tenantA, "ad": "E2E İkinci Şube", "il": "Şanlıurfa"})
        kontrol("sahip dükkan ekleyebiliyor", st in (200, 201), st)
        st, r = http("/rest/v1/stores", "POST", token=tokB, body={
            "tenant_id": tenantA, "ad": "Sızma denemesi"})
        kontrol("B, A'nın işletmesine dükkan ekleyemiyor", st >= 400, r)

        yad = f"E2E Yayınevi {uuid.uuid4().hex[:6]}"
        st, _ = http("/rest/v1/publishers", "POST", token=tokA, body={
            "ad": yad, "normalize_ad": f"E2EYAYINEVI{uuid.uuid4().hex[:6].upper()}"})
        kontrol("yayınevi eklenebiliyor (ortak dizin)", st in (200, 201), st)
        st, pl = http("/rest/v1/publishers?select=id&ad=eq."
                      + urllib.parse.quote(yad), key=SERVICE)
        if pl:
            cop["publishers"].append(pl[0]["id"])

        st, _ = http("/rest/v1/products", "POST", token=tokA, body={
            "tenant_id": tenantA, "katalog": "kitap",
            "ad": "E2E Test Kitabı", "barkod": f"E2E{uuid.uuid4().hex[:10]}"})
        kontrol("ürün eklenebiliyor", st in (200, 201), st)

        # ---- K3 · davet akışı ----------------------------------------------
        sec("K3 · davet akışı")
        st, dv = rpc("create_staff_invite", tokA, p_store_id=storeA,
                     p_role="pazarlamaci", p_ad_soyad="E2E Pazarlamacı")
        kontrol("davet kodu üretildi", st == 200 and len(dv.get("kod", "")) == 8, dv)
        kod = dv.get("kod", "")
        kontrol("kodda karıştırılabilir karakter yok",
                not (set(kod) & set("OI01lo")), kod)

        st, r = rpc("create_staff_invite", tokA, p_store_id=storeA, p_role="isletme_sahibi")
        kontrol("sahiplik davetle verilemiyor", st >= 400, r)
        st, r = rpc("create_staff_invite", tokB, p_store_id=storeA, p_role="pazarlamaci")
        kontrol("B, A'nın dükkanına davet gönderemiyor", st >= 400, r)

        uidP, tokP, _ = kullanici("pazarlamaci"); uidler.append(uidP)
        st, ses = rpc("my_session", tokP)
        kontrol("yeni kullanıcı üyeliksiz", ses["memberships"] == [])
        st, r = rpc("accept_invite", tokP, p_kod=kod)
        kontrol("kod kabul edildi", st == 200 and r.get("role") == "pazarlamaci", r)
        st, r = rpc("accept_invite", tokP, p_kod=kod)
        kontrol("kod ikinci kez kullanılamıyor", st >= 400, r)
        st, sesP = rpc("my_session", tokP)
        kontrol("pazarlamacı doğru dükkana bağlandı",
                any(m["role"] == "pazarlamaci" and m["store_id"] == storeA
                    for m in sesP["memberships"]), sesP["memberships"])

        # Rol yetkisi testleri için KALICI aktif pazarlamacı.
        # tokP birazdan K34 testinde pasife alınacak; onunla yapılan yetki
        # kontrolleri "rol yetersiz" değil "üyelik pasif" yüzünden geçer —
        # yani yanlış sebeple. tokPA hiçbir zaman pasife alınmıyor.
        uidPA, tokPA, _ = kullanici("pazarlamaci-aktif"); uidler.append(uidPA)
        st, dvA = rpc("create_staff_invite", tokA, p_store_id=storeA,
                      p_role="pazarlamaci", p_ad_soyad="E2E Aktif Pazarlamacı")
        st, r = rpc("accept_invite", tokPA, p_kod=dvA.get("kod", ""))
        kontrol("ikinci pazarlamacı aktif üye oldu",
                st == 200 and r.get("role") == "pazarlamaci", r)

        # ---- K34/W-2 · portföy devri zorunlu -------------------------------
        sec("K34 · portföy devri zorunlu")
        periodA = sesA["active_periods"][0]["id"]
        st, acc = http("/rest/v1/accounts", "POST", token=tokA, body={
            "tenant_id": tenantA, "store_id": storeA, "tip": "kurum",
            "institution_id": kurumId, "unvan": "E2E Test Okulu Kurumsal"})
        st, al = http("/rest/v1/accounts?select=id&limit=1", token=tokA)
        accId = al[0]["id"] if al else None
        kontrol("cari açıldı", accId is not None)
        if accId:
            st, _ = http("/rest/v1/assignments", "POST", token=tokA, body={
                "account_id": accId, "store_id": storeA,
                "user_id": uidP, "period_id": periodA})
            kontrol("portföy atandı", st in (200, 201))
            st, r = rpc("deactivate_member", tokA, p_user_id=uidP)
            kontrol("portföy devredilmeden pasife alınamıyor", st >= 400, r)
            kontrol("hata mesajı cari sayısını söylüyor",
                    "cari" in str(r.get("message", "")), r)
            st, r = rpc("deactivate_member", tokA, p_user_id=uidP,
                        p_devralan_user_id=uidA)
            kontrol("devirle pasife alınabiliyor",
                    st == 200 and r.get("devredilen_cari", 0) >= 1, r)

        # ---- K8 · dönem ------------------------------------------------------
        sec("K8 · dönem yaşam döngüsü")
        st, r = rpc("create_next_period", tokA, p_tenant_id=tenantA)
        kontrol("sonraki dönem açıldı", st == 200 and "period_id" in (r or {}), r)
        st, dl = http("/rest/v1/periods?select=ad,starts_on,ends_on,term,status"
                      "&order=academic_year,term", token=tokA)
        kontrol("üç dönem var", len(dl) == 3, [d["ad"] for d in dl])
        d1 = next((d for d in dl if d["term"] == 1), None)
        kontrol("1. dönem 1 Eylül–31 Ocak",
                d1 and d1["starts_on"].endswith("-09-01") and d1["ends_on"].endswith("-01-31"), d1)
        d2 = next((d for d in dl if d["term"] == 2), None)
        kontrol("2. dönem 1 Şubat–31 Ağustos (yaz satışı dönemsiz kalmıyor)",
                d2 and d2["starts_on"].endswith("-02-01") and d2["ends_on"].endswith("-08-31"), d2)
        kontrol("tam bir aktif dönem var",
                sum(1 for d in dl if d["status"] == "aktif") == 1,
                [(d["ad"], d["status"]) for d in dl])

        st, r = rpc("create_next_period", tokB, p_tenant_id=tenantA)
        kontrol("B, A'nın dönemini açamıyor", st >= 400, r)

        # ---- Türetme fonksiyonları -----------------------------------------
        sec("Türetme fonksiyonları (K29 · K45 · V6 · V8)")
        st, r = rpc("line_total", tokA, p_fiyat=100, p_iskonto=0.20, p_adet=5)
        kontrol("V6 · 100 × %20 × 5 = 400,00", float(r) == 400.00, r)
        st, r = rpc("line_total", tokA, p_fiyat=37.45, p_iskonto=0.17, p_adet=7)
        kontrol("V8 · ara sonuç yuvarlanmıyor (217,58 ≠ 217,56)", float(r) == 217.58, r)
        st, r = rpc("line_total", tokA, p_fiyat=10, p_iskonto=0, p_adet=3)
        kontrol("iskontosuz satır", float(r) == 30.00, r)
        if accId:
            st, r = rpc("calc_account_balance", tokA, p_account=accId)
            kontrol("K29 · boş carinin bakiyesi 0", float(r) == 0, r)
            st, r = rpc("open_consignment", tokA, p_account=accId)
            kontrol("K45 · kalan konsinye 0 (türetilmiş)", float(r) == 0, r)
            st, r = rpc("account_total_risk", tokA, p_account=accId)
            kontrol("K11 · toplam risk 0", float(r) == 0, r)

        # ---- K25 · iskonto çözümleme zinciri --------------------------------
        # 0008'deki hâli iki hata taşıyordu; bu bölüm ikisinin de regresyonudur.
        sec("K25 · iskonto çözümleme sırası")
        # Ad koşuya özel olmalı: sabit olursa upsert önceki koşunun kaydını
        # döndürür, ona bağlı eski ürünler de temizliği kilitler.
        yeni_yv = f"E2E Bes Kurumsal {uuid.uuid4().hex[:6]}"
        st, yv = rpc("upsert_publisher", tokA, p_ad=yeni_yv)
        pubId = yv if st == 200 else None
        kontrol("yayınevi upsert edildi", pubId is not None, yv)
        if pubId:
            cop["publishers"].append(pubId)
        st, yv2 = rpc("upsert_publisher", tokA, p_ad="  " + yeni_yv.lower() + " ")
        kontrol("normalize: boşluk ve küçük harf aynı yayınevi sayılıyor",
                yv2 == pubId, f"{yv2} != {pubId}")

        prodBarkod = f"978{uuid.uuid4().int % 10**10:010d}"
        st, pr = rpc("add_product", tokA, p_store_id=storeA, p_ad="E2E İskonto Kitabı",
                     p_barkod=prodBarkod, p_yayinevi=yeni_yv, p_etiket_fiyat=150)
        prodId = pr.get("id") if st == 200 else None
        kontrol("add_product ürün açtı", prodId and pr.get("yeni") is True, pr)

        # K24 · aynı barkod ikinci kez YENİ kayıt açmamalı; mevcudu döndürmeli
        st, pr2 = rpc("add_product", tokA, p_store_id=storeA,
                      p_ad="Bambaşka bir ad", p_barkod=prodBarkod)
        kontrol("K24 · barkod çakışınca mükerrer ürün açılmıyor",
                st == 200 and pr2.get("yeni") is False and pr2.get("id") == prodId,
                pr2)
        st, sp = rpc("upsert_store_product", tokA, p_store_id=storeA,
                     p_product_id=prodId, p_satis_fiyat=100,
                     p_varsayilan_iskonto=0.10)
        kontrol("K12 · dükkan fiyat katmanı yazıldı", st == 200, sp)
        st, r = rpc("upsert_store_product", tokA, p_store_id=storeA,
                    p_product_id=prodId, p_varsayilan_iskonto=1.5)
        kontrol("iskonto oranı 1'i geçemiyor", st >= 400, r)

        def iskonto(adet=1, tok=None):
            st, r = rpc("resolve_discount_detail", tok or tokA, p_store=storeA,
                        p_account=accId, p_product=prodId, p_adet=adet)
            return r if st == 200 else {"hata": r}

        r = iskonto()
        kontrol("kural yokken dükkan varsayılanı (%10)",
                float(r.get("oran", -1)) == 0.10 and r.get("kaynak") == "dukkan_varsayilani", r)

        # Yayınevi kuralı — varsayılanı ezer
        http("/rest/v1/discount_rules", "POST", token=tokA, body={
            "store_id": storeA, "publisher_id": pubId, "iskonto_orani": 0.20,
            "oncelik": 100, "ad": "Bes Kurumsal anlaşması"})
        r = iskonto()
        kontrol("yayınevi kuralı varsayılanı ezdi (%20)",
                float(r.get("oran", -1)) == 0.20 and r.get("kaynak") == "kural", r)
        kontrol("kaynak adı ekranda gösterilebilir",
                r.get("kaynak_ad") == "Bes Kurumsal anlaşması", r)

        # Ürün kuralı daha spesifik — yayınevi kuralını ezer
        http("/rest/v1/discount_rules", "POST", token=tokA, body={
            "store_id": storeA, "product_id": prodId, "iskonto_orani": 0.25,
            "oncelik": 100, "ad": "Ürüne özel"})
        r = iskonto()
        kontrol("ürün kuralı yayınevi kuralını ezdi (%25)",
                float(r.get("oran", -1)) == 0.25, r)

        # Adet kademesi
        http("/rest/v1/discount_rules", "POST", token=tokA, body={
            "store_id": storeA, "product_id": prodId, "iskonto_orani": 0.35,
            "min_adet": 50, "oncelik": 100, "ad": "50+ kademe"})
        kontrol("10 adette kademe açılmıyor (%25)", float(iskonto(10).get("oran", -1)) == 0.25)
        kontrol("100 adette kademe açılıyor (%35)", float(iskonto(100).get("oran", -1)) == 0.35)

        # H1 · cari kademesi (discount_tier) gerçekten çalışıyor mu
        http(f"/rest/v1/accounts?id=eq.{accId}", "PATCH", token=tokA,
             body={"discount_tier": "A"})
        http("/rest/v1/discount_rules", "POST", token=tokA, body={
            "store_id": storeA, "tier": "A", "iskonto_orani": 0.30,
            "oncelik": 100, "ad": "A kademesi"})
        r = iskonto()
        kontrol("H1 · cari kademesi kuralı ezdi (%30)",
                float(r.get("oran", -1)) == 0.30 and r.get("kaynak") == "kademe", r)

        # H2 · kademesi olup o kademeye kural OLMAYAN cari, genel kuralı KAYBETMEMELİ
        http(f"/rest/v1/accounts?id=eq.{accId}", "PATCH", token=tokA,
             body={"discount_tier": "Z"})
        r = iskonto()
        kontrol("H2 · kademe kuralı yoksa genel kurala düşüyor (%25, varsayılana DEĞİL)",
                float(r.get("oran", -1)) == 0.25 and r.get("kaynak") == "kural", r)
        http(f"/rest/v1/accounts?id=eq.{accId}", "PATCH", token=tokA,
             body={"discount_tier": None})

        # Skaler sarmalayıcı eski imzayı koruyor
        st, r = rpc("resolve_discount", tokA, p_store=storeA, p_account=accId,
                    p_product=prodId, p_adet=1)
        kontrol("resolve_discount skaleri hâlâ çalışıyor", float(r) == 0.25, r)

        # Tavan
        http("/rest/v1/discount_caps", "POST", token=tokA,
             body={"store_id": storeA, "tavan": 0.30})
        st, r = rpc("check_discount_cap", tokA, p_store=storeA, p_iskonto=0.25)
        kontrol("%25 tavanın altında", st == 200 and r.get("asildi") is False, r)
        st, r = rpc("check_discount_cap", tokA, p_store=storeA, p_iskonto=0.40)
        kontrol("%40 tavanı aşıyor → onaya düşer", r.get("asildi") is True, r)

        # ---- Katalog araması -------------------------------------------------
        sec("Katalog araması (K12 · K15 · K24)")
        st, r = rpc("search_products", tokA, p_store_id=storeA, p_q="İskonto Kitabı")
        bulunan = next((x for x in (r or []) if x["id"] == prodId), None)
        kontrol("ürün adla bulunuyor", bulunan is not None, len(r or []))
        kontrol("fiyat katmanı aynı satırda geliyor",
                bulunan and float(bulunan.get("satis_fiyat") or 0) == 100.0
                and bulunan.get("fiyatli") is True, bulunan)
        kontrol("etiket fiyat ayrı alanda (hesaba girmez · K25)",
                bulunan and float(bulunan.get("etiket_fiyat") or 0) == 150.0, bulunan)
        kontrol("yayınevi adı çözümlenmiş geliyor",
                bulunan and bulunan.get("yayinevi") == yeni_yv, bulunan)

        st, r = rpc("product_by_barcode", tokA, p_store_id=storeA,
                    p_barkod=bulunan["barkod"] if bulunan else "yok")
        kontrol("K24 · barkod tek ürün getiriyor",
                isinstance(r, dict) and r.get("id") == prodId, r)

        st, r = rpc("search_products", tokB, p_store_id=storeA, p_q="İskonto")
        kontrol("B, A'nın dükkanında arama yapamıyor", r in ([], None), r)

        st, r = rpc("search_products", tokA, p_store_id=storeA, p_q="İskonto Kitabı",
                    p_katalog="deneme")
        kontrol("K15 · katalog süzgeci çalışıyor (kitap ≠ deneme)", r == [], r)

        # ---- K23 · baskı grupları -------------------------------------------
        sec("K23 · baskı grupları")

        st, e1 = rpc("add_edition", tokA, p_store_id=storeA,
                     p_kaynak_product_id=prodId, p_baski_etiketi="2026-27",
                     p_barkod=f"978{uuid.uuid4().int % 10**10:010d}",
                     p_etiket_fiyat=210)
        yeniBaski = e1.get("id") if st == 200 else None
        kontrol("yeni baskı eklendi", yeniBaski is not None, e1)
        kontrol("grup TAM DA ŞİMDİ doğdu", e1.get("grup_id") is not None, e1)
        kontrol("sıra 2 verildi", e1.get("sira") == 2, e1)

        st, r = rpc("add_edition", tokA, p_store_id=storeA,
                    p_kaynak_product_id=prodId, p_baski_etiketi="")
        kontrol("baskı etiketi zorunlu", st >= 400, r)

        st, grup = rpc("edition_group", tokA, p_product_id=prodId,
                       p_store_id=storeA)
        kontrol("grupta iki baskı var", len(grup or []) == 2, grup)
        guncel = next((x for x in (grup or []) if x["guncel"]), None)
        kontrol("güncel baskı en yüksek sıradaki (tarihten DEĞİL)",
                guncel and guncel["baski_etiketi"] == "2026-27", guncel)
        eski = next((x for x in (grup or []) if x["id"] == prodId), None)
        kontrol("eski baskı hâlâ ayrı ürün ve kendi barkodunu koruyor",
                eski and eski["barkod"] == prodBarkod, eski)
        kontrol("yeni baskıya barkod KOPYALANMADI",
                guncel and guncel["barkod"] != prodBarkod, guncel)
        kontrol("yeni baskıya satış fiyatı kopyalanmadı",
                guncel and guncel["satis_fiyat"] is None, guncel)

        # Sipariş uyarısı iki yönlü: eski baskı seçilince güncel gösterilir
        st, u = rpc("edition_warning", tokA, p_product_id=prodId,
                    p_store_id=storeA)
        kontrol("eski baskı seçilince uyarı çıkıyor", u.get("uyari") is True, u)
        kontrol("uyarıda güncel baskının etiketi var",
                (u.get("guncel") or {}).get("baski_etiketi") == "2026-27", u)
        st, u2 = rpc("edition_warning", tokA, p_product_id=yeniBaski,
                     p_store_id=storeA)
        kontrol("güncel baskı seçilince uyarı ÇIKMIYOR",
                u2.get("uyari") is False, u2)

        # Stoğu olan eski baskı arşivlenemez
        rpc("upsert_store_product", tokA, p_store_id=storeA,
            p_product_id=prodId, p_satis_fiyat=120, p_stok_takibi=True)
        http(f"/rest/v1/store_products?store_id=eq.{storeA}&product_id=eq.{prodId}",
             "PATCH", key=SERVICE, body={"stok_adedi": 40})
        st, r = rpc("add_edition", tokA, p_store_id=storeA,
                    p_kaynak_product_id=prodId, p_baski_etiketi="2027-28",
                    p_eski_arsivle=True)
        kontrol("stoğu olan eski baskı arşivlenemiyor", st >= 400, r)
        kontrol("hata kaç adet kaldığını söylüyor",
                "40" in str((r or {}).get("message", "")), r)

        st, eritme = rpc("stale_editions", tokA, p_store_id=storeA)
        kontrol("eritme raporu eski baskıyı listeliyor",
                any(x["id"] == prodId and x["stok_adedi"] == 40
                    for x in (eritme or [])), eritme)
        kontrol("raporda güncel baskının etiketi de var",
                any(x.get("guncel_etiket") == "2026-27" for x in (eritme or [])),
                eritme)

        # Geriye dönük bağlama
        st, ek = rpc("add_product", tokA, p_store_id=storeA,
                     p_ad="E2E İskonto Kitabı Eski",
                     p_barkod=f"978{uuid.uuid4().int % 10**10:010d}")
        eskiUrun = ek.get("id")
        st, lk = rpc("link_edition", tokA, p_product_id=eskiUrun,
                     p_hedef_product_id=prodId)
        kontrol("mevcut ürün gruba bağlandı",
                st == 200 and lk.get("grup_id") == e1.get("grup_id"), lk)
        st, grup2 = rpc("edition_group", tokA, p_product_id=prodId,
                        p_store_id=storeA)
        kontrol("grupta artık üç baskı var", len(grup2 or []) == 3, len(grup2 or []))

        st, r = rpc("link_edition", tokA, p_product_id=prodId,
                    p_hedef_product_id=prodId)
        kontrol("ürün kendisine bağlanamıyor", st >= 400, r)
        st, r = rpc("link_edition", tokPA, p_product_id=eskiUrun,
                    p_hedef_product_id=prodId)
        kontrol("pazarlamacı baskı grubunu düzenleyemiyor", st >= 400, r)

        st, ul = rpc("unlink_edition", tokA, p_product_id=eskiUrun)
        kontrol("gruptan çıkarılabiliyor", st == 200, ul)
        st, grup3 = rpc("edition_group", tokA, p_product_id=prodId,
                        p_store_id=storeA)
        kontrol("çıkarılan ürün grupta görünmüyor", len(grup3 or []) == 2,
                len(grup3 or []))

        # Stok fikstürünü temizle (sonraki testler sıfır bekliyor)
        http(f"/rest/v1/store_products?store_id=eq.{storeA}&product_id=eq.{prodId}",
             "PATCH", key=SERVICE, body={"stok_adedi": 0})

        # ---- K49 · toplu aktarma -------------------------------------------
        sec("K49 · toplu aktarma motoru")

        # tr_sayi, Dart'taki Fmt.sayiOku ile AYNI cevabı vermeli — aksi hâlde
        # önizlemedeki fiyatla kaydedilen fiyat farklı olur.
        for metin, beklenen in [("37,45", 37.45), ("37.45", 37.45),
                                ("100.00", 100.0), ("1.250", 1250),
                                ("1.250,50", 1250.50), ("1,250.50", 1250.50),
                                (" 26,0 ₺ ", 26.0)]:
            st, r = rpc("tr_sayi", tokA, p=metin)
            kontrol(f"tr_sayi('{metin}') = {beklenen}",
                    r is not None and float(r) == beklenen, r)
        st, r = rpc("tr_sinif", tokA, p="5,6,7,8")
        kontrol("tr_sinif '5,6,7,8' → [5,6,7,8]", r == [5, 6, 7, 8], r)

        bar = lambda i: f"999{uuid.uuid4().int % 10**10:010d}"[:13]
        b1, b2, b3 = bar(1), bar(2), bar(3)
        satirlar = [
            {"_satir": 1, "ad": "AKTARMA Kitap Bir", "barkod": b1,
             "yayinevi": yeni_yv, "etiket_fiyat": "26,0", "sinif": "8"},
            {"_satir": 2, "ad": "AKTARMA Kitap İki", "barkod": b2,
             "yayinevi": yeni_yv, "etiket_fiyat": "1.250,50"},
            {"_satir": 3, "ad": "", "barkod": b3},          # hatalı: ad boş
        ]

        st, bid = rpc("create_import_batch", tokA, p_store_id=storeA,
                      p_tur="urun", p_dosya_adi="e2e.xlsx", p_satir_sayisi=3)
        kontrol("aktarma kaydı açıldı", st == 200 and bid, bid)

        # 1) KURU KOŞU — hiçbir şey yazmamalı
        st, kuru = rpc("import_chunk", tokA, p_batch_id=bid, p_rows=satirlar,
                       p_politika="guncelle", p_kuru_kosu=True)
        kontrol("kuru koşu: 2 yeni · 1 hatalı",
                st == 200 and kuru.get("yeni") == 2 and kuru.get("hatali") == 1, kuru)
        kontrol("hatalı satır numarasıyla bildiriliyor",
                (kuru.get("hatalar") or [{}])[0].get("satir") == 3, kuru.get("hatalar"))
        st, kontrol_ = rpc("search_products", tokA, p_store_id=storeA, p_q="AKTARMA")
        kontrol("kuru koşudan sonra katalog BOŞ", kontrol_ == [], kontrol_)

        # 2) GERÇEK KOŞU — kuru koşuyla aynı sayıları vermeli
        st, gercek = rpc("import_chunk", tokA, p_batch_id=bid, p_rows=satirlar,
                         p_politika="guncelle")
        kontrol("gerçek koşu kuru koşuyla AYNI sonucu verdi",
                gercek.get("yeni") == kuru.get("yeni")
                and gercek.get("hatali") == kuru.get("hatali"), (kuru, gercek))
        st, katalog = rpc("search_products", tokA, p_store_id=storeA, p_q="AKTARMA")
        kontrol("iki ürün katalogda", len(katalog or []) == 2, len(katalog or []))
        bir = next((x for x in (katalog or []) if x["barkod"] == b1), None)
        kontrol("Türkçe sayı doğru okundu (26,0 → 26.00)",
                bir and float(bir["etiket_fiyat"]) == 26.0, bir)
        iki = next((x for x in (katalog or []) if x["barkod"] == b2), None)
        kontrol("binlik ayracı doğru okundu (1.250,50 → 1250.50)",
                iki and float(iki["etiket_fiyat"]) == 1250.50, iki)
        kontrol("sınıf dizisi çözümlendi", bir and bir["sinif"] == [8], bir)

        # 3) AYNI DOSYA TEKRAR — katalog ikiye katlanmamalı (K24)
        st, tekrar = rpc("import_chunk", tokA, p_batch_id=bid, p_rows=satirlar,
                         p_politika="guncelle")
        kontrol("aynı dosya tekrar: 0 yeni, 2 güncelleme",
                tekrar.get("yeni") == 0 and tekrar.get("guncelleme") == 2, tekrar)
        st, katalog2 = rpc("search_products", tokA, p_store_id=storeA, p_q="AKTARMA")
        kontrol("katalog hâlâ 2 ürün (mükerrer yok)", len(katalog2 or []) == 2,
                len(katalog2 or []))

        # 4) ATLA politikası
        st, atla = rpc("import_chunk", tokA, p_batch_id=bid, p_rows=satirlar,
                       p_politika="atla")
        kontrol("atla politikası çakışanları atlıyor",
                atla.get("atlanan") == 2 and atla.get("guncelleme") == 0, atla)

        # 5) HATA politikası
        st, hata_p = rpc("import_chunk", tokA, p_batch_id=bid, p_rows=satirlar,
                         p_politika="hata")
        kontrol("hata politikası çakışanı hata sayıyor",
                hata_p.get("hatali") == 3, hata_p)

        # 6) FİYAT AKTARIMI — anahtar barkod, ürün yoksa hata
        st, fid = rpc("create_import_batch", tokA, p_store_id=storeA,
                      p_tur="fiyat_iskonto", p_dosya_adi="fiyat.xlsx")
        st, fs = rpc("import_chunk", tokA, p_batch_id=fid, p_rows=[
            {"_satir": 1, "barkod": b1, "satis_fiyat": "120,00",
             "varsayilan_iskonto": "0,25"},
            {"_satir": 2, "barkod": f"111{uuid.uuid4().int % 10**10:010d}",
             "satis_fiyat": "10"},   # katalogda YOK
            {"_satir": 3, "barkod": b2, "varsayilan_iskonto": "1,5"},
        ])
        kontrol("fiyat aktarımı: 1 yeni · 2 hatalı",
                fs.get("yeni") == 1 and fs.get("hatali") == 2, fs)
        kontrol("katalogda olmayan barkod sebebiyle birlikte bildiriliyor",
                any("Katalogda" in (h.get("sebep") or "")
                    for h in (fs.get("hatalar") or [])), fs.get("hatalar"))
        # NOT: .lower() kullanılmıyor — Python'da 'İ'.lower() birleşen noktalı
        # 'i̇' üretir ve "iskonto" araması tutmaz. Türkçe büyük harf tuzağının
        # test tarafındaki hâli.
        kontrol("geçersiz iskonto reddediliyor",
                any("0 ile 1 arasında" in (h.get("sebep") or "")
                    for h in (fs.get("hatalar") or [])), fs.get("hatalar"))

        st, kat3 = rpc("search_products", tokA, p_store_id=storeA, p_q="AKTARMA")
        fiyatli = next((x for x in (kat3 or []) if x["barkod"] == b1), None)
        kontrol("fiyat katmanı yazıldı (120,00 · %25)",
                fiyatli and float(fiyatli["satis_fiyat"]) == 120.0
                and float(fiyatli["varsayilan_iskonto"]) == 0.25, fiyatli)

        # 7) GERİ ALMA — insert siler, update eski hâline döner
        st, _ = rpc("finish_import_batch", tokA, p_batch_id=fid)
        st, geri = rpc("undo_import", tokA, p_batch_id=fid)
        kontrol("fiyat aktarımı geri alındı",
                st == 200 and geri.get("silinen") == 1, geri)
        st, kat4 = rpc("search_products", tokA, p_store_id=storeA, p_q="AKTARMA")
        geriAlinan = next((x for x in (kat4 or []) if x["barkod"] == b1), None)
        kontrol("fiyat katmanı silindi, ürün kimliği DURUYOR",
                geriAlinan is not None and geriAlinan["satis_fiyat"] is None,
                geriAlinan)

        st, r = rpc("undo_import", tokA, p_batch_id=fid)
        kontrol("iki kez geri alınamıyor", st >= 400, r)

        # Ürün batch'i: 2 insert + güncellemeler → geri alınca ürünler gitmeli
        st, _ = rpc("finish_import_batch", tokA, p_batch_id=bid)
        st, geri2 = rpc("undo_import", tokA, p_batch_id=bid)
        kontrol("ürün aktarımı geri alındı",
                st == 200 and geri2.get("silinen", 0) >= 2, geri2)
        st, kat5 = rpc("search_products", tokA, p_store_id=storeA, p_q="AKTARMA")
        kontrol("geri almadan sonra katalog temiz", kat5 == [], kat5)

        # 8) Yetki ve şablon
        st, r = rpc("create_import_batch", tokPA, p_store_id=storeA, p_tur="urun")
        kontrol("pazarlamacı toplu aktarma açamıyor", st >= 400, r)
        st, r = rpc("create_import_batch", tokB, p_store_id=storeA, p_tur="urun")
        kontrol("B, A'nın dükkanına aktarma açamıyor", st >= 400, r)

        st, tid = rpc("save_import_template", tokA, p_tur="urun",
                      p_ad="Aktif Ürünler.xls",
                      p_eslesme={"Barkod": "barkod", "Ürün Adı": "ad"})
        kontrol("sütun eşleme şablonu kaydedildi", st == 200 and tid, tid)
        st, tl = rpc("list_import_templates", tokA, p_tur="urun")
        kontrol("şablon geri okunuyor",
                any(x["ad"] == "Aktif Ürünler.xls" for x in (tl or [])), tl)

        st, gecmis = rpc("list_import_batches", tokA, p_store_id=storeA)
        kontrol("aktarma geçmişi listeleniyor", len(gecmis or []) >= 2, len(gecmis or []))
        kontrol("geri alınanlar durumuyla görünüyor",
                all(x["durum"] == "geri_alindi" for x in (gecmis or [])[:2]),
                [(x["tur"], x["durum"]) for x in (gecmis or [])[:2]])

        # ---- Cari yönetimi ve portföy (0022) --------------------------------
        sec("K5 · K6 · K7 · cari yönetimi")

        st, ac2 = rpc("create_account", tokA, p_store_id=storeA,
                      p_institution_id=kurumId, p_tip="ogretmen",
                      p_unvan="E2E Ayşe Öğretmen", p_contact_id=None,
                      p_user_id=uidA, p_credit_limit=5000)
        ogrCari = ac2.get("id") if st == 200 else None
        kontrol("K5 · öğretmen carisi açıldı", ogrCari is not None, ac2)

        st, r = rpc("create_account", tokA, p_store_id=storeA,
                    p_institution_id=kurumId, p_tip="ogretmen",
                    p_unvan="Kişisiz Öğretmen")
        kontrol("K5 · öğretmen carisi kişiye bağlanmadan açılamıyor", st >= 400, r)

        st, r = rpc("create_account", tokA, p_store_id=storeA,
                    p_institution_id=kurumId, p_tip="ogretmen",
                    p_unvan="e2e  AYŞE  öğretmen", p_user_id=uidA)
        kontrol("mükerrer cari engelleniyor (bakiye ikiye bölünmesin)",
                st >= 400, r)

        # ── K7 · TOPLAM YOK ──────────────────────────────────────────────
        # Kurumsal cari 45.000, öğretmen carisi 12.000 olsa bile bu ikisi
        # HİÇBİR YERDE toplanmaz. K29 gereği bakiye türetilmiştir; burada
        # yalnızca test fikstürü olarak service_role ile yazılıyor.
        http(f"/rest/v1/accounts?id=eq.{accId}", "PATCH", key=SERVICE,
             body={"balance_cache": 45000})
        http(f"/rest/v1/accounts?id=eq.{ogrCari}", "PATCH", key=SERVICE,
             body={"balance_cache": 12000})

        st, det = rpc("account_detail", tokA, p_account_id=accId)
        kontrol("cari detayı geliyor", st == 200 and det.get("unvan"), det)
        kardes = det.get("kardes_cariler") or []
        kontrol("K7 · kardeş cariler AYRI satır olarak listeleniyor",
                any(k["id"] == ogrCari and float(k["bakiye"]) == 12000
                    for k in kardes), kardes)
        kontrol("K7 · detayda kurum toplamı ALANI YOK",
                not any("toplam" in k for k in det.keys()), list(det.keys()))
        kontrol("K7 · carinin kendi bakiyesi kardeşinkini içermiyor",
                float(det["bakiye"]) == 0,
                f'bakiye={det["bakiye"]} (calc_account_balance türetir, cache 45000)')

        st, kd = rpc("institution_detail", tokA, p_id=kurumId)
        kontrol("K7 · kurum detayında da toplam alanı yok",
                not any("toplam" in k or "bakiye" == k for k in (kd or {}).keys()),
                list((kd or {}).keys()))

        # ── Durum geçişleri ──────────────────────────────────────────────
        st, r = rpc("set_account_status", tokA, p_account_id=ogrCari,
                    p_durum="kapali")
        kontrol("bakiyeli cari KAPATILAMIYOR", st >= 400, r)
        st, r = rpc("set_account_status", tokA, p_account_id=ogrCari,
                    p_durum="pasif")
        kontrol("bakiyeli cari pasif değil TAHSİLATTA oluyor",
                st == 200 and r.get("durum") == "tahsilatta", r)

        # Fikstürü temizle: sonraki testler sıfır bakiye bekliyor
        for a_ in (accId, ogrCari):
            http(f"/rest/v1/accounts?id=eq.{a_}", "PATCH", key=SERVICE,
                 body={"balance_cache": 0, "durum": "aktif"})

        # ── Yetki ────────────────────────────────────────────────────────
        st, r = rpc("update_account", tokPA, p_account_id=accId,
                    p_credit_limit=999999)
        kontrol("pazarlamacı kredi limitini değiştiremiyor", st >= 400, r)
        kontrol("engel ROLDEN kaynaklanıyor (üyelik pasifliğinden değil)",
                "sahip veya müdür" in str((r or {}).get("message", "")), r)
        st, r = rpc("update_account", tokPA, p_account_id=accId,
                    p_discount_tier="VIP")
        kontrol("pazarlamacı iskonto kademesini değiştiremiyor", st >= 400, r)
        st, r = rpc("update_account", tokA, p_account_id=accId,
                    p_discount_tier="A", p_credit_limit=50000)
        kontrol("sahip kademe ve limiti değiştirebiliyor", st == 200, r)

        # ── Arama ve süzgeçler ───────────────────────────────────────────
        st, liste = rpc("search_accounts", tokA, p_store_id=storeA)
        kontrol("cari araması çalışıyor", len(liste or []) >= 2, len(liste or []))
        st, liste2 = rpc("search_accounts", tokA, p_store_id=storeA,
                         p_tip="ogretmen")
        kontrol("tip süzgeci çalışıyor",
                all(x["tip"] == "ogretmen" for x in (liste2 or [])), liste2)
        st, sayi = rpc("count_accounts", tokA, p_store_id=storeA)
        kontrol("cari sayımı arama ile tutarlı", sayi >= len(liste or []), sayi)
        st, bos = rpc("search_accounts", tokB, p_store_id=storeA)
        kontrol("B, A'nın carilerini aramıyor", bos in ([], None), bos)

        # ── Portföy (W-2) ────────────────────────────────────────────────
        st, at = rpc("assign_accounts", tokA, p_account_ids=[accId, ogrCari],
                     p_user_id=uidPA, p_period_id=periodA)
        kontrol("toplu portföy ataması yapıldı",
                st == 200 and at.get("atanan") == 2, at)

        st, ps = rpc("portfolio_summary", tokA, p_store_id=storeA,
                     p_period_id=periodA)
        kontrol("portföy özeti pazarlamacıyı gösteriyor",
                any(x["user_id"] == uidPA and x["cari_sayisi"] == 2
                    for x in (ps or {}).get("pazarlamacilar", [])), ps)
        kontrol("atanmamış cari sayısı raporlanıyor",
                "atanmamis" in (ps or {}), ps)

        st, at2 = rpc("assign_accounts", tokA, p_account_ids=[accId],
                      p_user_id=uidA, p_period_id=periodA)
        kontrol("yeniden atama önceki atamayı devralıyor",
                at2.get("atanan") == 1 and at2.get("devralinan") == 1, at2)

        st, r = rpc("assign_accounts", tokPA, p_account_ids=[accId],
                    p_user_id=uidPA, p_period_id=periodA)
        kontrol("pazarlamacı portföy atayamıyor", st >= 400, r)

        # ── K6 · cari taşıma ─────────────────────────────────────────────
        st, k2 = http("/rest/v1/institutions", "POST", token=tokA,
                      body={"ad": f"E2E Hedef Okulu {uuid.uuid4().hex[:6]}",
                            "kurum_tipi": "okul", "ilce": "SİVEREK",
                            "ekleyen_tenant_id": tenantA})
        st, kl2 = http("/rest/v1/institutions?select=id&order=created_at.desc&limit=1",
                       token=tokA)
        hedefKurum = kl2[0]["id"] if kl2 else None
        if hedefKurum:
            cop["institutions"].append(hedefKurum)

        st, tc = rpc("transfer_account_check", tokA, p_account_id=ogrCari)
        kontrol("taşıma öncesi kapı özeti geliyor",
                st == 200 and "acik_konsinye" in (tc or {}), tc)

        st, r = rpc("transfer_account", tokA, p_account_id=ogrCari,
                    p_to_institution_id=hedefKurum, p_gerekce="")
        kontrol("K6 · gerekçesiz taşıma reddediliyor", st >= 400, r)
        st, r = rpc("transfer_account", tokPA, p_account_id=ogrCari,
                    p_to_institution_id=hedefKurum, p_gerekce="deneme")
        kontrol("pazarlamacı cari taşıyamıyor", st >= 400, r)
        kontrol("hata mesajı doğru yolu söylüyor",
                "talebi" in str((r or {}).get("message", "")), r)

        st, r = rpc("transfer_account", tokA, p_account_id=ogrCari,
                    p_to_institution_id=hedefKurum,
                    p_gerekce="Öğretmen Siverek'e tayin oldu")
        kontrol("K6 · cari yeni kuruma taşındı", st == 200, r)

        st, det2 = rpc("account_detail", tokA, p_account_id=ogrCari)
        kontrol("taşıma günlüğe geçti, gerekçesiyle",
                any("tayin" in (t.get("gerekce") or "")
                    for t in det2.get("tasimalar", [])), det2.get("tasimalar"))
        kontrol("cari artık yeni kurumda",
                det2["kurum"]["id"] == hedefKurum, det2["kurum"])

        st, r = rpc("transfer_account", tokA, p_account_id=ogrCari,
                    p_to_institution_id=hedefKurum, p_gerekce="tekrar")
        kontrol("aynı kuruma tekrar taşınamıyor", st >= 400, r)

        # ---- Faz 3 · talep akışı (0024) --------------------------------------
        sec("K36 · K37 · K41 · talep akışı")

        # Talebi PA'nın portföyündeki cariye açalım ki bildirim ona düşsün
        rpc("assign_accounts", tokA, p_account_ids=[accId],
            p_user_id=uidPA, p_period_id=periodA)

        st, ma = rpc("my_request_accounts", tokA)
        kontrol("muhatap listesi geliyor", len(ma or []) >= 1, len(ma or []))

        st, tal = rpc("create_request", tokA, p_account_id=accId, p_items=[
            {"product_id": prodId, "adet": 30},
            {"product_id": yeniBaski, "adet": 12},
        ], p_not_metni="8. sınıflar için")
        talepId = tal.get("id") if st == 200 else None
        kontrol("talep açıldı", talepId and tal.get("kalem") == 2, tal)
        kontrol("gönderildi durumunda", tal.get("durum") == "gonderildi", tal)

        # K36 · serbest metin kalem yok
        st, r = rpc("create_request", tokA, p_account_id=accId,
                    p_items=[{"adet": 5}])
        kontrol("K36 · ürünsüz kalem reddediliyor", st >= 400, r)
        st, r = rpc("create_request", tokA, p_account_id=accId, p_items=[])
        kontrol("boş talep açılamıyor", st >= 400, r)
        st, r = rpc("create_request", tokA, p_account_id=accId,
                    p_items=[{"product_id": prodId, "adet": 0}])
        kontrol("sıfır adet reddediliyor", st >= 400, r)

        # K43 · idempotency
        ck = f"e2e-{uuid.uuid4().hex[:8]}"
        st, i1 = rpc("create_request", tokA, p_account_id=accId,
                     p_items=[{"product_id": prodId, "adet": 5}], p_client_key=ck)
        st, i2 = rpc("create_request", tokA, p_account_id=accId,
                     p_items=[{"product_id": prodId, "adet": 5}], p_client_key=ck)
        kontrol("K43 · aynı client_key ikinci talep AÇMIYOR",
                i1.get("id") == i2.get("id") and i2.get("yeni") is False, (i1, i2))
        rpc("cancel_request", tokA, p_request_id=i1.get("id"))

        # K41 · bildirim carinin PORTFÖY SAHİBİNE gitti mi
        st, bildirim = rpc("my_notifications", tokPA)
        kontrol("K41 · portföy sahibine bildirim düştü",
                any(b["olay"] == "talep_acildi" and b["hedef_id"] == talepId
                    for b in (bildirim or [])), bildirim)
        kontrol("bildirim derin bağlantı taşıyor",
                any(b["hedef_tur"] == "request" for b in (bildirim or [])),
                bildirim)
        st, bosB = rpc("my_notifications", tokB)
        kontrol("B'ye bildirim sızmıyor", bosB in ([], None), bosB)

        # Gelen kutusu
        st, kutu = rpc("list_requests", tokPA, p_sadece_bekleyen=True)
        satir = next((x for x in (kutu or []) if x["id"] == talepId), None)
        kontrol("talep gelen kutusunda", satir is not None, len(kutu or []))
        kontrol("kalem ve adet özeti doğru",
                satir and satir["kalem_sayisi"] == 2
                and satir["toplam_adet"] == 42, satir)

        st, det = rpc("request_detail", tokPA, p_request_id=talepId)
        kalemler = det.get("kalemler") or []
        kontrol("detayda kalemler geliyor", len(kalemler) == 2, len(kalemler))
        k30 = next((x for x in kalemler if x["adet"] == 30), None)
        kontrol("K25 · iskonto kalem bazında çözümlenmiş",
                k30 and k30.get("iskonto") is not None, k30)
        kontrol("K25 · iskontonun gerekçesi de geliyor",
                k30 and k30.get("iskonto_kaynak"), k30)
        kontrol("satır tutarı hesaplanmış",
                k30 and k30.get("satir_tutari") is not None, k30)
        kontrol("K23 · eski baskı için uyarı kalemde taşınıyor",
                k30 and (k30.get("baski_uyarisi") or {}).get("uyari") is True,
                k30.get("baski_uyarisi") if k30 else None)
        kontrol("K7 · detayda carinin KENDİ riski var, kurum toplamı yok",
                "risk" in (det.get("cari") or {})
                and not any("toplam" in x for x in det.keys()), list(det.keys()))

        # Dokunma
        st, c = rpc("claim_request", tokPA, p_request_id=talepId)
        kontrol("talep incelemeye alındı", c.get("durum") == "incelemede", c)
        st, r = rpc("claim_request", tokPA, p_request_id=talepId)
        kontrol("ikinci kez ele alınamıyor", st >= 400, r)

        # ── K37 · KALEM BAZINDA KISMİ ONAY ───────────────────────────────
        i30 = next(x["id"] for x in kalemler if x["adet"] == 30)
        i12 = next(x["id"] for x in kalemler if x["adet"] == 12)

        st, r = rpc("decide_request_items", tokPA, p_request_id=talepId,
                    p_kararlar=[{"item_id": i12, "durum": "reddedildi"}])
        kontrol("K37 · gerekçesiz red reddediliyor", st >= 400, r)

        st, d1 = rpc("decide_request_items", tokPA, p_request_id=talepId,
                     p_kararlar=[{"item_id": i12, "durum": "reddedildi",
                                  "red_nedeni": "Stokta yok"}])
        kontrol("K37 · kısmi kararda talep KAPANMIYOR",
                d1.get("durum") == "incelemede" and d1.get("bekleyen") == 1, d1)

        st, d2 = rpc("decide_request_items", tokPA, p_request_id=talepId,
                     p_kararlar=[{"item_id": i30, "durum": "onaylandi"}])
        kontrol("K37 · son kalem karara bağlanınca talep sonuçlanıyor",
                d2.get("durum") == "karara_baglandi", d2)
        kontrol("onaylanan ve reddedilen sayıları doğru",
                d2.get("onaylanan") == 1 and d2.get("reddedilen") == 1, d2)

        st, det2 = rpc("request_detail", tokPA, p_request_id=talepId)
        red = next((x for x in det2["kalemler"] if x["durum"] == "reddedildi"), None)
        kontrol("red gerekçesi kalemde duruyor",
                red and red["red_nedeni"] == "Stokta yok", red)

        st, bildirim2 = rpc("my_notifications", tokA)
        kontrol("K41 · talebi açana sonuç bildirimi gitti",
                any(b["olay"] == "talep_karara_baglandi" and b["hedef_id"] == talepId
                    for b in (bildirim2 or [])), bildirim2)

        st, r = rpc("decide_request_items", tokPA, p_request_id=talepId,
                    p_kararlar=[{"item_id": i30, "durum": "onaylandi"}])
        kontrol("sonuçlanmış talep yeniden karara bağlanamıyor", st >= 400, r)

        # Tamamen reddedilme yolu
        st, t2 = rpc("create_request", tokA, p_account_id=accId,
                     p_items=[{"product_id": prodId, "adet": 7}])
        st, det3 = rpc("request_detail", tokPA, p_request_id=t2["id"])
        st, d3 = rpc("decide_request_items", tokPA, p_request_id=t2["id"],
                     p_kararlar=[{"item_id": det3["kalemler"][0]["id"],
                                  "durum": "reddedildi",
                                  "red_nedeni": "Bu dönem basılmıyor"}])
        kontrol("hiç onaylı kalem yoksa TAMAMEN REDDEDİLDİ",
                d3.get("durum") == "tamamen_reddedildi", d3)

        # ── V7 · SLA eskalasyonu ─────────────────────────────────────────
        st, t3 = rpc("create_request", tokA, p_account_id=accId,
                     p_items=[{"product_id": prodId, "adet": 3}])
        http(f"/rest/v1/requests?id=eq.{t3['id']}", "PATCH", key=SERVICE,
             body={"created_at": "2020-01-01T00:00:00Z"})
        st, esk = rpc("escalate_stale_requests", tokA, p_saat=24)
        kontrol("V7 · gecikmiş talep eskale edildi",
                esk.get("eskale_edilen", 0) >= 1, esk)
        st, bild3 = rpc("my_notifications", tokA)
        kontrol("eskalasyon sahibe bildirim gönderdi",
                any(b["olay"] == "talep_sla" for b in (bild3 or [])), bild3)
        st, esk2 = rpc("escalate_stale_requests", tokA, p_saat=24)
        kontrol("aynı talep iki kez eskale edilmiyor",
                esk2.get("eskale_edilen") == 0, esk2)

        st, kutu2 = rpc("list_requests", tokPA, p_sadece_bekleyen=True)
        kontrol("gelen kutusu gecikmişi işaretliyor",
                any(x["gecikmis"] for x in (kutu2 or [])), kutu2)

        # ── K22 · adet önerisi 4 kademeli zincir ─────────────────────────
        st, o1 = rpc("suggest_quantity", tokA, p_account_id=accId,
                     p_product_id=prodId, p_period_id=periodA)
        kontrol("K22 · mevcut yokken öneri boş ama TIKANMIYOR",
                st == 200 and o1.get("adet") is None
                and o1.get("kaynak") == "yok", o1)

        http("/rest/v1/account_enrollments", "POST", key=SERVICE, body={
            "account_id": accId, "period_id": periodA, "sinif": 8,
            "ogrenci_sayisi": 120})
        st, o2 = rpc("suggest_quantity", tokA, p_account_id=accId,
                     p_product_id=prodId, p_period_id=periodA)
        kontrol("K22 · kurum bildirince öneri oradan geliyor",
                o2.get("adet") == 120 and o2.get("kaynak") == "kurum_bildirdi", o2)
        kontrol("önerinin kaynağı etiketle görünüyor",
                o2.get("etiket") == "kurum bildirdi", o2)

        # ── Yetki ────────────────────────────────────────────────────────
        st, r = rpc("create_request", tokB, p_account_id=accId,
                    p_items=[{"product_id": prodId, "adet": 1}])
        kontrol("B, A'nın carisine talep açamıyor", st >= 400, r)
        st, r = rpc("request_detail", tokB, p_request_id=talepId)
        kontrol("B talep detayını göremiyor", r is None, r)
        st, bosK = rpc("list_requests", tokB)
        kontrol("B'nin gelen kutusu boş", bosK in ([], None), bosK)

        # ---- Faz 4 · işlenmiş örnek (§4.2) ----------------------------------
        # Doküman bunu "şema yazarken kontrol noktası olarak kullanılacak TEK
        # örnek" diye tanımlıyor. Birebir uyguluyoruz.
        sec("§4.2 · para nasıl akıyor — işlenmiş örnek")

        st, ou = rpc("add_product", tokA, p_store_id=storeA,
                     p_ad="E2E Örnek Kitap",
                     p_barkod=f"978{uuid.uuid4().int % 10**10:010d}")
        ornekUrun = ou.get("id")
        rpc("upsert_store_product", tokA, p_store_id=storeA,
            p_product_id=ornekUrun, p_satis_fiyat=100, p_alis_fiyat=60,
            p_varsayilan_iskonto=0.20)
        st, oc = rpc("create_account", tokA, p_store_id=storeA,
                     p_institution_id=kurumId, p_tip="kurum",
                     p_unvan=f"E2E Y Lisesi {uuid.uuid4().hex[:6]}")
        ornekCari = oc.get("id")
        rpc("assign_accounts", tokA, p_account_ids=[ornekCari],
            p_user_id=uidPA, p_period_id=periodA)

        # 1-2) FİYAT 100,00 · İSKONTO %20
        st, isk = rpc("resolve_discount_detail", tokA, p_store=storeA,
                      p_account=ornekCari, p_product=ornekUrun, p_adet=5)
        kontrol("1-2 · fiyat 100 · iskonto %20",
                float(isk["oran"]) == 0.20, isk)

        # 3) SİPARİŞ SATIRI · 100 × 0,80 × 5 = 400,00 ₺ (K28 damga)
        st, t4 = rpc("create_request", tokA, p_account_id=ornekCari,
                     p_items=[{"product_id": ornekUrun, "adet": 5}])
        st, d4 = rpc("request_detail", tokA, p_request_id=t4["id"])
        rpc("decide_request_items", tokA, p_request_id=t4["id"],
            p_kararlar=[{"item_id": d4["kalemler"][0]["id"],
                         "durum": "onaylandi"}])
        st, sip = rpc("create_order_from_request", tokA, p_request_id=t4["id"])
        siparisId = sip.get("id")
        kontrol("3 · sipariş satırı 400,00 ₺",
                st == 200 and float(sip["toplam"]) == 400.00, sip)

        st, sd = rpc("order_detail", tokA, p_order_id=siparisId)
        kal = sd["kalemler"][0]
        kontrol("K28 · birim fiyat ve iskonto DAMGALANDI",
                float(kal["birim_fiyat"]) == 100.00
                and float(kal["iskonto_orani"]) == 0.20, kal)

        # ⚠ Sipariş HENÜZ borç değildir (K26)
        st, bak = rpc("calc_account_balance", tokA, p_account=ornekCari)
        kontrol("K26 · sipariş HENÜZ borç DEĞİL (bakiye 0)",
                float(bak) == 0, bak)

        st, r = rpc("create_order_from_request", tokA, p_request_id=t4["id"])
        kontrol("aynı talepten ikinci sipariş açılamıyor", st >= 400, r)

        # K46 · hazırlık akışı
        st, h1 = rpc("set_order_status", tokA, p_order_id=siparisId,
                     p_durum="hazirlaniyor")
        kontrol("K46 · hazırlamaya başlandı",
                h1.get("durum") == "hazirlaniyor", h1)
        st, r = rpc("set_order_status", tokA, p_order_id=siparisId,
                    p_durum="teslim_edildi")
        kontrol("tanımsız durum geçişi reddediliyor", st >= 400, r)
        st, h2 = rpc("set_order_status", tokA, p_order_id=siparisId,
                     p_durum="hazir")
        kontrol("K46 · hazır işaretlendi", h2.get("durum") == "hazir", h2)
        st, sd2 = rpc("order_detail", tokA, p_order_id=siparisId)
        kontrol("K46 · kim hazırladı ve ne zaman damgalandı",
                sd2.get("hazirlayan") and sd2.get("hazirlik_bitti_at"), sd2)

        # 4) TESLİMAT → BORÇ DOĞAR
        rpc("set_order_status", tokA, p_order_id=siparisId, p_durum="sevk_edildi")
        st, sev = rpc("create_shipment", tokA, p_account_id=ornekCari,
                      p_order_id=siparisId,
                      p_items=[{"order_item_id": kal["id"], "adet": 5}],
                      p_teslim_alan_ad="Müdür Yardımcısı")
        kontrol("4 · teslimat 400,00 ₺",
                st == 200 and float(sev["toplam"]) == 400.00, sev)
        st, bak2 = rpc("calc_account_balance", tokA, p_account=ornekCari)
        kontrol("K26 · TESLİMATLA borç doğdu (400,00)",
                float(bak2) == 400.00, bak2)
        st, sd3 = rpc("order_detail", tokA, p_order_id=siparisId)
        kontrol("sipariş teslim edildi durumuna geçti",
                sd3["durum"] == "teslim_edildi", sd3["durum"])
        kontrol("H-3 · backorder sıfır",
                sd3["kalemler"][0]["backorder"] == 0, sd3["kalemler"][0])

        # 5) TAHSİLAT 250 → bakiye 150, ödeme durumu kısmi
        st, tah = rpc("create_payment", tokA, p_account_id=ornekCari,
                      p_tutar=250, p_yontem="nakit")
        kontrol("5 · 250 ₺ tahsilat FIFO ile mahsup edildi",
                st == 200 and float(tah["dagitilan"]) == 250.00, tah)
        st, bak3 = rpc("calc_account_balance", tokA, p_account=ornekCari)
        kontrol("K48 · bakiye 150,00", float(bak3) == 150.00, bak3)
        st, od = rpc("shipment_payment_status", tokA, p_shipment=sev["id"])
        kontrol("K48 · ödeme durumu KISMİ (türetildi)", od == "kismi", od)

        # ── Varyant: 5 sipariş, 3 teslim → borç 240 ──────────────────────
        sec("§4.2 varyantları")
        st, oc2 = rpc("create_account", tokA, p_store_id=storeA,
                      p_institution_id=kurumId, p_tip="kurum",
                      p_unvan=f"E2E Kısmi Okul {uuid.uuid4().hex[:6]}")
        kismiCari = oc2["id"]
        st, t5 = rpc("create_request", tokA, p_account_id=kismiCari,
                     p_items=[{"product_id": ornekUrun, "adet": 5}])
        st, d5 = rpc("request_detail", tokA, p_request_id=t5["id"])
        rpc("decide_request_items", tokA, p_request_id=t5["id"],
            p_kararlar=[{"item_id": d5["kalemler"][0]["id"], "durum": "onaylandi"}])
        st, s5 = rpc("create_order_from_request", tokA, p_request_id=t5["id"])
        st, sd5 = rpc("order_detail", tokA, p_order_id=s5["id"])
        st, sev2 = rpc("create_shipment", tokA, p_account_id=kismiCari,
                       p_order_id=s5["id"],
                       p_items=[{"order_item_id": sd5["kalemler"][0]["id"],
                                 "adet": 3}])
        st, bak4 = rpc("calc_account_balance", tokA, p_account=kismiCari)
        kontrol("varyant · 3 teslim → borç 240,00", float(bak4) == 240.00, bak4)
        st, sd6 = rpc("order_detail", tokA, p_order_id=s5["id"])
        kontrol("H-3 · kalan 2 adet BACKORDER olarak türetildi",
                sd6["kalemler"][0]["backorder"] == 2, sd6["kalemler"][0])
        kontrol("sipariş kısmi teslim durumunda",
                sd6["durum"] == "kismi_teslim", sd6["durum"])
        st, r = rpc("create_shipment", tokA, p_account_id=kismiCari,
                    p_order_id=s5["id"],
                    p_items=[{"order_item_id": sd5["kalemler"][0]["id"],
                              "adet": 3}])
        kontrol("siparişten FAZLA sevk edilemiyor", st >= 400, r)

        # ── Varyant: konsinye → borç 0 ──────────────────────────────────
        st, oc3 = rpc("create_account", tokA, p_store_id=storeA,
                      p_institution_id=kurumId, p_tip="kurum",
                      p_unvan=f"E2E Konsinye Okul {uuid.uuid4().hex[:6]}")
        konsCari = oc3["id"]
        # Konsinye BIRAKMA: tip=teslimat + borclandirir=false (mülkiyet dükkanda)
        st, kons = rpc("create_shipment", tokA, p_account_id=konsCari,
                       p_items=[{"product_id": ornekUrun, "adet": 5}],
                       p_borclandirir=False, p_tip="teslimat")
        kontrol("konsinye bırakma yapıldı", st == 200, kons)
        st, r = rpc("create_shipment", tokA, p_account_id=konsCari,
                    p_items=[{"product_id": ornekUrun, "adet": 1}],
                    p_borclandirir=False, p_tip="konsinye_satis")
        kontrol("tutarsız bileşim reddediliyor (satış hem olmuş hem borçsuz)",
                st >= 400, r)
        st, bak5 = rpc("calc_account_balance", tokA, p_account=konsCari)
        kontrol("C-1 · konsinye BORÇ DOĞURMUYOR", float(bak5) == 0, bak5)
        st, kn = rpc("open_consignment", tokA, p_account=konsCari)
        kontrol("K45 · açık konsinye kayıtlardan TÜRETİLİYOR",
                float(kn) > 0, kn)

        # ── Varyant: fiyat değişse geçmiş sipariş oynamaz (K28) ─────────
        rpc("upsert_store_product", tokA, p_store_id=storeA,
            p_product_id=ornekUrun, p_satis_fiyat=120)
        st, sd7 = rpc("order_detail", tokA, p_order_id=siparisId)
        kontrol("K28 · fiyat 120 oldu ama sipariş 400,00 KALDI",
                float(sd7["toplam"]) == 400.00
                and float(sd7["kalemler"][0]["birim_fiyat"]) == 100.00, sd7)

        # ── Çek: ödeme değil ödeme VAADİ (K11) ──────────────────────────
        st, cek = rpc("create_payment", tokA, p_account_id=kismiCari,
                      p_tutar=100, p_yontem="cek", p_cek_vade="2027-01-15",
                      p_cek_banka="Ziraat")
        kontrol("K11 · çek kaydı açıldı", cek.get("cek") is True, cek)
        st, bak6 = rpc("calc_account_balance", tokA, p_account=kismiCari)
        kontrol("K11 · çek bakiyeyi DÜŞÜRMÜYOR", float(bak6) == 240.00, bak6)
        st, risk = rpc("account_total_risk", tokA, p_account=kismiCari)
        kontrol("K11 · ama TOPLAM RİSKE giriyor (240 + 100)",
                float(risk) == 340.00, risk)
        st, r = rpc("create_payment", tokA, p_account_id=kismiCari,
                    p_tutar=50, p_yontem="cek")
        kontrol("vadesiz çek reddediliyor", st >= 400, r)

        # ── Avans: borçtan fazla ödeme ─────────────────────────────────
        st, av = rpc("create_payment", tokA, p_account_id=ornekCari,
                     p_tutar=200, p_yontem="havale")
        kontrol("K48 · borçtan fazlası AVANS olarak duruyor",
                float(av["dagitilan"]) == 150.00 and float(av["avans"]) == 50.00,
                av)
        st, bak7 = rpc("calc_account_balance", tokA, p_account=ornekCari)
        kontrol("avans bakiyeyi alacağa çeviriyor", float(bak7) == -50.00, bak7)

        # ── Ekstre ve borçlu listesi ───────────────────────────────────
        st, eks = rpc("account_statement", tokA, p_account_id=ornekCari)
        kontrol("ekstre hareketleri listeliyor",
                len(eks.get("hareketler") or []) >= 3, eks)
        kontrol("ekstre bakiyeyi türetimle gösteriyor",
                float(eks["bakiye"]) == -50.00, eks["bakiye"])

        st, borc = rpc("open_debts", tokA, p_store_id=storeA)
        kontrol("borçlu cariler listeleniyor",
                any(x["id"] == kismiCari for x in (borc or [])), borc)
        kontrol("K7 · borçlu listesinde TOPLAM SATIRI yok",
                isinstance(borc, list), type(borc).__name__)

        # ── Yetki ──────────────────────────────────────────────────────
        st, r = rpc("create_shipment", tokB, p_account_id=ornekCari,
                    p_items=[{"product_id": ornekUrun, "adet": 1}])
        kontrol("B, A'nın carisine teslimat yapamıyor", st >= 400, r)
        st, r = rpc("create_payment", tokB, p_account_id=ornekCari,
                    p_tutar=10, p_yontem="nakit")
        kontrol("B, A'nın carisine tahsilat giremiyor", st >= 400, r)

        # ---- Faz 4 kalanı · çekirdek raporlar + dönem kilidi -----------------
        sec("K50 · çekirdek raporlar · B1 makbuz · K8 dönem kilidi")

        st, yas = rpc("aging_report", tokA, p_store_id=storeA)
        kismiSatir = next((x for x in (yas or []) if x["id"] == kismiCari), None)
        kontrol("yaşlandırma raporu borçlu cariyi listeliyor",
                kismiSatir is not None, len(yas or []))
        kontrol("borç 0-30 gün kovasında (bugün teslim edildi)",
                kismiSatir and float(kismiSatir["gun_0_30"]) == 240.00,
                kismiSatir)
        kontrol("90+ kovası boş", kismiSatir
                and float(kismiSatir["gun_90_ust"]) == 0, kismiSatir)
        kontrol("K7 · yaşlandırma CARİ bazlı, kurum toplamı yok",
                isinstance(yas, list)
                and all("kurum_toplam" not in x for x in yas), type(yas).__name__)

        st, ozet = rpc("collection_summary", tokA, p_store_id=storeA)
        kontrol("tahsilat özeti geliyor",
                st == 200 and "tahsil_edilen" in (ozet or {}), ozet)
        kontrol("K11 · çek TAHSİLAT değil VAAT olarak ayrılmış",
                float(ozet.get("vaat", 0)) == 100.00, ozet)
        kontrol("nakit + havale tahsil edilen olarak sayılmış",
                float(ozet.get("tahsil_edilen", 0)) == 450.00, ozet)
        kontrol("yönteme göre kırılım var",
                any(y["yontem"] == "nakit" for y in ozet.get("yonteme_gore", [])),
                ozet.get("yonteme_gore"))
        kontrol("çek kırılımda vaat işaretli",
                any(y["yontem"] == "cek" and y["vaat"] is True
                    for y in ozet.get("yonteme_gore", [])), ozet.get("yonteme_gore"))

        st, dag = rpc("payment_status_distribution", tokA, p_store_id=storeA)
        kontrol("K48 · ödeme durumu dağılımı türetiliyor",
                any(x["durum"] in ("odenmedi", "kismi", "odendi")
                    for x in (dag or [])), dag)

        st, cek = rpc("cheque_report", tokA, p_store_id=storeA, p_gun=1000)
        kontrol("K11 · çek raporu vadesiyle listeliyor",
                any(float(c["tutar"]) == 100.00 for c in (cek or [])), cek)

        st, kons2 = rpc("consignment_report", tokA, p_store_id=storeA)
        kontrol("K45 · açık konsinye raporu türetilmiş",
                any(x["id"] == konsCari and float(x["kalan_adet"]) == 5
                    for x in (kons2 or [])), kons2)

        st, ciro = rpc("revenue_report", tokA, p_store_id=storeA,
                       p_kirilim="pazarlamaci")
        kontrol("ciro raporu teslimattan okunuyor",
                st == 200 and float(ciro.get("hacim", 0)) == 640.00, ciro)
        kontrol("K28 · maliyet damgası sayesinde kâr hesaplanıyor",
                float(ciro.get("maliyet", 0)) > 0
                and float(ciro.get("kar", 0)) > 0, ciro)
        st, ciro2 = rpc("revenue_report", tokA, p_store_id=storeA,
                        p_kirilim="kurum")
        kontrol("K7 · kurum kırılımı HACİM verir (alacak değil)",
                ciro2.get("kirilim") == "kurum"
                and "bakiye" not in (ciro2 or {}), list((ciro2 or {}).keys()))
        st, r = rpc("revenue_report", tokA, p_store_id=storeA, p_kirilim="sacma")
        kontrol("geçersiz kırılım reddediliyor", st >= 400, r)

        # B1 · makbuz
        st, mak = rpc("receipt_data", tokA, p_payment_id=tah["id"])
        kontrol("B1 · makbuz verisi geliyor",
                st == 200 and float(mak.get("tutar", 0)) == 250.00, mak)
        kontrol("makbuz mahsup dökümünü taşıyor",
                len(mak.get("mahsuplar") or []) >= 1, mak.get("mahsuplar"))
        kontrol("makbuzda dükkan ve işletme bilgisi var",
                mak.get("isletme") and (mak.get("dukkan") or {}).get("ad"), mak)
        kontrol("makbuz sonrası kalan bakiye gösteriliyor",
                "kalan_bakiye" in (mak or {}), list((mak or {}).keys()))

        # K8 · dönem kilidi
        st, kap = rpc("period_close_check", tokA, p_period_id=periodA)
        kontrol("dönem kapatma özeti geliyor",
                st == 200 and "acik_siparis" in (kap or {}), kap)
        kontrol("açık konsinyesi olan cari bildiriliyor",
                kap.get("acik_konsinye_cari", 0) >= 1, kap)

        rpc("set_period_status", tokA, p_period_id=periodA, p_status="kapali")
        st, r = rpc("create_request", tokA, p_account_id=ornekCari,
                    p_items=[{"product_id": ornekUrun, "adet": 1}])
        kontrol("K8 · kapalı döneme talep GİRİLEMİYOR", st >= 400, r)
        st, r = rpc("create_payment", tokA, p_account_id=ornekCari,
                    p_tutar=10, p_yontem="nakit")
        kontrol("K8 · kapalı döneme tahsilat GİRİLEMİYOR", st >= 400, r)
        rpc("set_period_status", tokA, p_period_id=periodA, p_status="aktif")
        st, r = rpc("create_payment", tokA, p_account_id=ornekCari,
                    p_tutar=10, p_yontem="nakit")
        kontrol("dönem açılınca yeniden yazılabiliyor", st == 200, r)

        # ---- Açılış ekranları (0030) ----------------------------------------
        sec("Panel ve Bugün özetleri")

        st, pnl = rpc("dashboard_owner", tokA, p_store_id=storeA,
                      p_period_id=periodA)
        kontrol("panel özeti tek çağrıda geliyor",
                st == 200 and "bekleyen_talep" in (pnl or {}), pnl)
        kontrol("iş kuyruğu sayıları var",
                all(k in pnl for k in ("gecikmis_talep", "onay_bekleyen_siparis",
                                       "hazirlanacak_siparis", "portfoysuz_cari")),
                list((pnl or {}).keys()))
        kontrol("K26 · ciro teslimattan okunuyor",
                float(pnl.get("donem_ciro", 0)) == 640.00, pnl.get("donem_ciro"))
        kontrol("K11 · portföydeki çek ayrı gösteriliyor",
                float(pnl.get("portfoydeki_cek", 0)) == 100.00, pnl)
        kontrol("K7 · toplam DÜKKANIN alacağı, kurumun borcu değil",
                "acik_alacak" in pnl and not any("kurum" in k and "toplam" in k
                                                 for k in pnl.keys()),
                list(pnl.keys()))
        huni = pnl.get("huni") or {}
        kontrol("K37 · talep hunisi dört basamak veriyor",
                all(k in huni for k in ("acilan", "karara_baglanan",
                                        "reddedilen", "siparise_donen")), huni)
        kontrol("huni siparişe dönenleri sayıyor",
                huni.get("siparise_donen", 0) >= 2, huni)
        kontrol("pazarlamacı kırılımı geliyor",
                any(x["user_id"] == uidPA for x in pnl.get("pazarlamacilar", [])),
                pnl.get("pazarlamacilar"))

        # Borçlu cariyi PA'nın portföyüne ver ki hatırlatma anlamlı olsun
        rpc("assign_accounts", tokA, p_account_ids=[kismiCari],
            p_user_id=uidPA, p_period_id=periodA)
        st, bug = rpc("dashboard_marketer", tokPA, p_store_id=storeA,
                      p_period_id=periodA)
        kontrol("bugün özeti geliyor",
                st == 200 and "portfoy_cari" in (bug or {}), bug)
        kontrol("yalnızca KENDİ portföyünü sayıyor",
                bug.get("portfoy_cari", 0) >= 1, bug.get("portfoy_cari"))
        kontrol("tahsilat hatırlatmaları borçlu carileri listeliyor",
                any(x["id"] == kismiCari and float(x["bakiye"]) == 240.00
                    for x in bug.get("tahsilat_hatirlatmalari", [])),
                bug.get("tahsilat_hatirlatmalari"))
        kontrol("hatırlatmada borcun kaç gündür açık olduğu var",
                all(x.get("gun") is not None
                    for x in bug.get("tahsilat_hatirlatmalari", [])),
                bug.get("tahsilat_hatirlatmalari"))
        kontrol("K45 · açık konsinyesi olan cari sayılıyor",
                "acik_konsinye_cari" in (bug or {}), bug)

        st, bosP = rpc("dashboard_owner", tokB, p_store_id=storeA)
        kontrol("B, A'nın panelini göremiyor", bosP is None, bosP)

        # ---- Saha · ziyaret ve rota (0031) -----------------------------------
        # K10'un tamamı tek bir iddiaya dayanır: ziyaretin kanıtı ÇIKTISIDIR.
        # Bu yüzden buradaki asıl test, damganın kendiliğinden düşüp düşmediği.
        sec("K10 · Y-18 · ziyaret ve rota")

        st, z1 = rpc("start_visit", tokPA, p_institution_id=kurumId)
        ziyaretId = (z1 or {}).get("id")
        kontrol("ziyaret açıldı", st == 200 and ziyaretId, z1)

        st, acik = rpc("active_visit", tokPA)
        kontrol("açık ziyaret oturumdan okunuyor",
                (acik or {}).get("id") == ziyaretId, acik)

        st, z2 = rpc("start_visit", tokPA, p_institution_id=kurumId)
        kontrol("aynı kuruma ikinci giriş yeni ziyaret AÇMIYOR",
                z2.get("id") == ziyaretId and z2.get("yeni") is False, z2)

        st, r = rpc("start_visit", tokPA, p_institution_id=hedefKurum)
        kontrol("açık ziyaret varken başka kuruma giriş engelleniyor", st >= 400, r)
        kontrol("hata hangi ziyaretin açık olduğunu söylüyor",
                "açık" in str((r or {}).get("message", "")), r)

        ckz = f"e2e-z-{uuid.uuid4().hex[:8]}"
        rpc("end_visit", tokPA, p_visit_id=ziyaretId)
        st, i1 = rpc("start_visit", tokPA, p_institution_id=kurumId, p_client_key=ckz)
        st, i2 = rpc("start_visit", tokPA, p_institution_id=kurumId, p_client_key=ckz)
        kontrol("K43 · aynı client_key ikinci ziyaret AÇMIYOR",
                i1.get("id") == i2.get("id") and i2.get("yeni") is False, (i1, i2))
        ziyaretId = i1.get("id")

        # Y-18 · Damga otomatik düşmeli: talep açarken visit_id GÖNDERİLMİYOR.
        st, tz = rpc("create_request", tokPA, p_account_id=kismiCari,
                     p_items=[{"product_id": prodId, "adet": 3}])
        talepZ = (tz or {}).get("id")
        st, cik = rpc("visit_outputs", tokPA, p_visit=ziyaretId)
        kontrol("Y-18 · ziyaret açıkken açılan talep KENDİLİĞİNDEN damgalandı",
                (cik or {}).get("talep", 0) >= 1, cik)
        kontrol("çıktı toplamı damgalı kayıtları sayıyor",
                (cik or {}).get("toplam", 0) >= 1, cik)

        st, det = rpc("visit_detail", tokPA, p_visit_id=ziyaretId)
        kontrol("ziyaret detayı çıktıyı KALEM olarak listeliyor",
                any(x["tur"] == "talep" and x["id"] == talepZ
                    for x in (det or {}).get("satirlar", [])),
                (det or {}).get("satirlar"))

        st, kap = rpc("end_visit", tokPA, p_visit_id=ziyaretId,
                      p_not_metni="Mevcutlar alındı", p_sonuc="olumlu")
        kontrol("ziyaret kapandı ve süre döndü",
                st == 200 and kap.get("dakika") is not None, kap)
        kontrol("kapanışta çıktı özeti veriliyor",
                (kap.get("cikti") or {}).get("talep", 0) >= 1, kap)

        st, det2 = rpc("visit_detail", tokPA, p_visit_id=ziyaretId)
        cikis1 = det2.get("checked_out_at")
        rpc("end_visit", tokPA, p_visit_id=ziyaretId)
        st, det3 = rpc("visit_detail", tokPA, p_visit_id=ziyaretId)
        kontrol("K43 · ikinci kapatma çıkış saatini DEĞİŞTİRMİYOR",
                det3.get("checked_out_at") == cikis1,
                (cikis1, det3.get("checked_out_at")))

        st, cik2 = rpc("create_request", tokPA, p_account_id=kismiCari,
                       p_items=[{"product_id": prodId, "adet": 2}])
        st, sonCik = rpc("visit_outputs", tokPA, p_visit=ziyaretId)
        kontrol("ziyaret kapandıktan sonra açılan talep damgalanmıyor",
                sonCik.get("talep") == cik.get("talep"), (cik, sonCik))
        rpc("cancel_request", tokPA, p_request_id=(cik2 or {}).get("id"))

        st, acik2 = rpc("active_visit", tokPA)
        kontrol("kapanınca açık ziyaret kalmıyor", acik2 is None, acik2)

        # Rota
        st, plan = rpc("plan_visit", tokPA, p_institution_id=kurumId,
                       p_amac="tahsilat")
        kontrol("rotaya durak eklendi", st == 200 and plan, plan)
        st, rota = rpc("my_route", tokPA)
        durak = next((d for d in (rota or {}).get("duraklar", [])
                      if d["institution_id"] == kurumId), None)
        kontrol("rota durağı geliyor", durak is not None, rota)
        kontrol("durak kurumdaki İŞİ yanında taşıyor",
                durak and "borc" in durak and "bekleyen_talep" in durak, durak)
        kontrol("durağın amacı korunuyor", durak and durak["amac"] == "tahsilat",
                durak)
        kontrol("plansız yapılan ziyaretler de sayılıyor",
                (rota or {}).get("plansiz_ziyaret", 0) >= 1, rota)

        st, z3 = rpc("start_visit", tokPA, p_institution_id=kurumId)
        st, rota2 = rpc("my_route", tokPA)
        durak2 = next((d for d in (rota2 or {}).get("duraklar", [])
                       if d["institution_id"] == kurumId), None)
        kontrol("giriş yapılınca durak ziyaret_edildi oluyor",
                durak2 and durak2["durum"] == "ziyaret_edildi", durak2)
        kontrol("durak açılan ziyarete bağlanıyor",
                durak2 and durak2["visit_id"] == (z3 or {}).get("id"), durak2)
        rpc("end_visit", tokPA, p_visit_id=(z3 or {}).get("id"))

        st, oner = rpc("suggest_route", tokPA)
        kontrol("rota önerisi geliyor", st == 200 and isinstance(oner, list), oner)
        kontrol("her öneri GEREKÇESİNİ taşıyor",
                all(x.get("neden") for x in (oner or [])), oner)
        kontrol("rotada olan kurum planda diye işaretli",
                all(x["planda"] for x in (oner or [])
                    if x["institution_id"] == kurumId), oner)

        st, gec = rpc("list_visits", tokPA, p_store_id=storeA)
        kontrol("ziyaret geçmişi geliyor", st == 200 and len(gec or []) >= 2, gec)
        kontrol("geçmişte her ziyaretin çıktı sayısı var",
                all("cikti" in x for x in (gec or [])), gec)

        st, perf = rpc("visit_performance", tokA, p_store_id=storeA,
                       p_period_id=periodA)
        satir = next((x for x in (perf or []) if x["user_id"] == uidPA), None)
        kontrol("K10 · performans ÇIKTI üzerinden ölçülüyor",
                satir and satir["ziyaret"] >= 2 and "ort_cikti" in satir, perf)
        kontrol("K35 · prim/tahakkuk alanı YOK",
                satir and not any("prim" in k or "komisyon" in k for k in satir),
                list((satir or {}).keys()))

        # RLS
        st, sizma = rpc("visit_detail", tokB, p_visit_id=ziyaretId)
        kontrol("B, A'nın ziyaretini göremiyor", sizma is None, sizma)
        st, r = rpc("end_visit", tokB, p_visit_id=ziyaretId)
        kontrol("başkasının ziyareti kapatılamıyor", st >= 400, r)

        # ---- K43 · senkron sözleşmesi · K42 · cihaz (0032) --------------------
        # Sözleşmenin kalbi tek cümle: aynı (client_id, local_seq) İKİ KEZ
        # işlenmez. Buradaki testlerin çoğu bunun gerçekten böyle olduğunu ve
        # yarıda kalan kuyruğun geri kalanını taşıdığını doğrular.
        sec("K43 · offline senkron · K42 · cihaz güvenliği")

        cid = f"e2e-cihaz-{uuid.uuid4().hex[:8]}"
        st, dev = rpc("register_device", tokPA, p_client_id=cid,
                      p_ad="E2E iPhone", p_platform="ios", p_surum="1.0.0")
        kontrol("cihaz kaydedildi", st == 200 and dev.get("device_id"), dev)
        kontrol("yeni cihaz iptalli değil",
                dev.get("iptal") is False and dev.get("silinsin") is False, dev)
        st, dev2 = rpc("register_device", tokPA, p_client_id=cid)
        kontrol("aynı cihaz ikinci kez KAYIT AÇMIYOR",
                dev2.get("device_id") == dev.get("device_id"), (dev, dev2))

        # Kuyruk: ziyaret aç → talep gir → ziyaret kapat, TEK istekte.
        seq = int(time.time() * 1000) % 1000000
        ops = [
            {"local_seq": seq, "fn": "start_visit",
             "args": {"institution_id": kurumId, "client_key": f"{cid}-1"}},
            {"local_seq": seq + 1, "fn": "create_request",
             "args": {"account_id": kismiCari, "client_key": f"{cid}-2",
                      "items": [{"product_id": prodId, "adet": 4}]}},
        ]
        st, sp = rpc("sync_push", tokPA, p_client_id=cid, p_ops=ops)
        kontrol("kuyruk tek istekte yüklendi",
                st == 200 and sp.get("basarili") == 2, sp)
        kontrol("sunucu saati bildiriliyor (kural 4)",
                sp.get("sunucu_saati") is not None, sp)
        kuyrukZiyaret = next((x["sonuc"]["id"] for x in sp["sonuclar"]
                              if x["local_seq"] == seq), None)
        kuyrukTalep = next((x["sonuc"]["id"] for x in sp["sonuclar"]
                            if x["local_seq"] == seq + 1), None)
        kontrol("kuyruktan açılan ziyaret gerçekten var", kuyrukZiyaret, sp)

        st, cikK = rpc("visit_outputs", tokPA, p_visit=kuyrukZiyaret)
        kontrol("Y-18 · kuyruktan gelen talep de ziyarete damgalandı",
                cikK.get("talep", 0) >= 1, cikK)

        # Kural 2 · aynı anahtar ikinci kez İŞLENMEZ
        st, sp2 = rpc("sync_push", tokPA, p_client_id=cid, p_ops=ops)
        kontrol("K43 · tekrar gönderilen kuyruk YENİ KAYIT ÜRETMİYOR",
                sp2.get("tekrar") == 2 and sp2.get("basarili") == 0, sp2)
        kontrol("tekrar edilen işlem İLK sonucu döndürüyor",
                any(x["local_seq"] == seq and x["sonuc"]["id"] == kuyrukZiyaret
                    for x in sp2["sonuclar"]), sp2)
        st, cikK2 = rpc("visit_outputs", tokPA, p_visit=kuyrukZiyaret)
        kontrol("tekrar sonrası çıktı sayısı DEĞİŞMEDİ",
                cikK2.get("talep") == cikK.get("talep"), (cikK, cikK2))

        # Bir işlem düşerse diğerleri yüklenmeye devam eder
        st, sp3 = rpc("sync_push", tokPA, p_client_id=cid, p_ops=[
            {"local_seq": seq + 10, "fn": "create_request",
             "args": {"account_id": kismiCari, "items": []}},
            {"local_seq": seq + 11, "fn": "plan_visit",
             "args": {"institution_id": kurumId, "amac": "kuyruktan"}},
            {"local_seq": seq + 12, "fn": "olmayan_islem", "args": {}},
        ])
        kontrol("hatalı işlem kuyruğu DURDURMUYOR",
                sp3.get("basarili") == 1 and sp3.get("hatali") == 2, sp3)
        kontrol("hata sebebi işlem bazında dönüyor",
                all(x.get("hata") for x in sp3["sonuclar"]
                    if x["durum"] == "hata"), sp3)
        kontrol("bilinmeyen işlem adı reddediliyor",
                any("Bilinmeyen işlem" in (x.get("hata") or "")
                    for x in sp3["sonuclar"]), sp3)

        # Başarısız işlem MAKBUZ ALMAZ: düzeltilip aynı sırayla tekrar
        # gönderilebilmeli, yoksa geçici bir hata kaydı sonsuza dek reddederdi.
        st, sp4 = rpc("sync_push", tokPA, p_client_id=cid, p_ops=[
            {"local_seq": seq + 10, "fn": "create_request",
             "args": {"account_id": kismiCari,
                      "items": [{"product_id": prodId, "adet": 1}]}},
        ])
        kontrol("düzeltilen işlem aynı sırayla TEKRAR DENENEBİLİYOR",
                sp4.get("basarili") == 1 and sp4.get("tekrar") == 0, sp4)
        rpc("cancel_request", tokPA,
            p_request_id=sp4["sonuclar"][0]["sonuc"]["id"])
        rpc("cancel_request", tokPA, p_request_id=kuyrukTalep)
        rpc("end_visit", tokPA, p_visit_id=kuyrukZiyaret)

        # K34 · Elden teslim offline'da ANLIK KESİNLEŞİR. Zimmet bakiyesi
        # tutulmadığı için stok rezervasyonu sorusu hiç doğmuyor: mal fiziken
        # verildi, borç doğdu, kayıt senkronda yüklendi.
        st, bakOnce = http(
            f"/rest/v1/accounts?select=balance_cache&id=eq.{kismiCari}",
            token=tokPA)
        st, spT = rpc("sync_push", tokPA, p_client_id=cid, p_ops=[
            {"local_seq": seq + 30, "fn": "create_shipment",
             "args": {"account_id": kismiCari, "kaynak": "elden",
                      "borclandirir": True, "client_key": f"{cid}-30",
                      "belge_no": f"TEMP-{cid}-30",
                      "items": [{"product_id": prodId, "adet": 2}]}},
        ])
        kontrol("K34 · elden teslim kuyruktan yüklendi",
                spT.get("basarili") == 1, spT)
        st, bakSonra = http(
            f"/rest/v1/accounts?select=balance_cache&id=eq.{kismiCari}",
            token=tokPA)
        kontrol("K26 · kuyruktan gelen teslimat BORÇ DOĞURDU",
                float(bakSonra[0]["balance_cache"])
                > float(bakOnce[0]["balance_cache"]),
                (bakOnce, bakSonra))
        sevkId = spT["sonuclar"][0]["sonuc"]["id"]
        st, irs = http(f"/rest/v1/shipments?select=belge_no&id=eq.{sevkId}",
                       token=tokPA)
        kontrol("teslimatın TEMP belge numarası da kalıcıya çevrildi",
                not (irs[0].get("belge_no") or "TEMP-").startswith("TEMP-"),
                irs)

        # Kural 3 · geçici belge numarası sunucuda kalıcıya çevrilir
        st, sp5 = rpc("sync_push", tokPA, p_client_id=cid, p_ops=[
            {"local_seq": seq + 20, "fn": "create_payment",
             "args": {"account_id": kismiCari, "tutar": 10, "yontem": "nakit",
                      "makbuz_no": f"TEMP-{cid}-20",
                      "client_key": f"{cid}-20"}},
        ])
        odemeId = sp5["sonuclar"][0].get("sonuc", {}).get("id")
        st, mk = http(f"/rest/v1/payments?select=makbuz_no&id=eq.{odemeId}",
                      token=tokPA)
        kalici = (mk or [{}])[0].get("makbuz_no", "")
        kontrol("K43 · TEMP belge numarası sunucuda KALICIYA çevrildi",
                kalici and not kalici.startswith("TEMP-"), kalici)
        kontrol("kalıcı numara yıl-sıra biçiminde",
                len(kalici.split("-")) == 2 and kalici.split("-")[1].isdigit(),
                kalici)

        # Referans veri
        st, ref = rpc("sync_reference", tokPA, p_store_id=storeA)
        kontrol("referans veri tek çağrıda geliyor",
                st == 200 and "cariler" in (ref or {}), list((ref or {}).keys()))
        kontrol("portföydeki cariler bakiyesiyle iniyor",
                any(c["id"] == kismiCari and "bakiye" in c
                    for c in ref.get("cariler", [])), ref.get("cariler"))
        kontrol("aktif dönem referansta var",
                (ref.get("donem") or {}).get("id") == periodA, ref.get("donem"))
        kontrol("kural 4 · sunucu saati referansta bildiriliyor",
                ref.get("sunucu_saati") is not None, ref)
        st, refB = rpc("sync_reference", tokB, p_store_id=storeA)
        kontrol("B, A'nın referans verisini indiremiyor", refB is None, refB)

        # Katalog imleçli
        st, k1 = rpc("sync_catalog", tokA, p_store_id=storeA, p_limit=2)
        kontrol("katalog sayfası geliyor",
                st == 200 and isinstance(k1.get("satirlar"), list), k1)
        if k1.get("sayi", 0) == 2:
            kontrol("sayfa doluysa 'bitti' false", k1.get("bitti") is False, k1)
            st, k2 = rpc("sync_catalog", tokA, p_store_id=storeA, p_limit=2,
                         p_after=k1.get("son_id"))
            kontrol("imleç sonraki sayfaya geçiyor",
                    all(x["id"] > k1["son_id"] for x in k2.get("satirlar", [])),
                    (k1.get("son_id"), k2.get("satirlar")))
        st, k3 = rpc("sync_catalog", tokA, p_store_id=storeA,
                     p_since="2099-01-01T00:00:00Z")
        kontrol("delta · değişmeyen ürün yeniden İNMİYOR",
                k3.get("sayi") == 0, k3)

        # K14 · Arşivlenen ürün delta'da `aktif: false` olarak inmeli. Dışarıda
        # bırakılsaydı istemci onu hiç haber almaz, yerel katalogda sonsuza dek
        # satılabilir görünürdü.
        if prodId:
            http(f"/rest/v1/products?id=eq.{prodId}", "PATCH", token=tokA,
                 body={"arsivlendi": True})
            st, k4 = rpc("sync_catalog", tokA, p_store_id=storeA,
                         p_since="2020-01-01T00:00:00Z", p_limit=2000)
            satir = next((x for x in k4.get("satirlar", [])
                          if x["id"] == prodId), None)
            kontrol("K14 · arşivlenen ürün delta'da pasif olarak iniyor",
                    satir is not None and satir["aktif"] is False, satir)
            http(f"/rest/v1/products?id=eq.{prodId}", "PATCH", token=tokA,
                 body={"arsivlendi": False})

        # K42 · cihaz listesi ve iptali
        st, cl = rpc("list_devices", tokA)
        kontrol("K42 · cihaz kayıtları sahibe görünüyor",
                any(x["id"] == dev["device_id"] for x in (cl or [])), cl)
        st, clPA = rpc("list_devices", tokPA)
        kontrol("pazarlamacı yalnızca kendi cihazını görüyor",
                all(x["user_id"] == uidPA for x in (clPA or [])), clPA)
        st, r = rpc("revoke_device", tokB, p_device_id=dev["device_id"])
        kontrol("başka işletme cihaz iptal edemiyor", st >= 400, r)

        st, r = rpc("revoke_device", tokA, p_device_id=dev["device_id"])
        # void dönen fonksiyonda PostgREST 204 verir
        kontrol("sahip cihazı iptal edebiliyor", st in (200, 204), (st, r))
        st, dev3 = rpc("register_device", tokPA, p_client_id=cid)
        kontrol("iptal edilen cihaz bunu ilk bağlanışta ÖĞRENİYOR",
                dev3.get("iptal") is True and dev3.get("silinsin") is True, dev3)
        st, r = rpc("sync_push", tokPA, p_client_id=cid, p_ops=[])
        kontrol("iptal edilen cihazdan yazma KABUL EDİLMİYOR", st >= 400, r)
        rpc("confirm_wipe", tokPA, p_client_id=cid)
        st, dev4 = rpc("register_device", tokPA, p_client_id=cid)
        kontrol("silme onaylanınca bayrak kapanıyor",
                dev4.get("silinsin") is False, dev4)

        # K42 · üyelik pasife alınınca cihazlar da iptal olur (trigger)
        uidC, tokC, _ = kullanici("cihaz-sahibi"); uidler.append(uidC)
        st, dvC = rpc("create_staff_invite", tokA, p_store_id=storeA,
                      p_role="pazarlamaci", p_ad_soyad="E2E Cihaz Pazarlamacı")
        rpc("accept_invite", tokC, p_kod=dvC.get("kod", ""))
        cidC = f"e2e-cihaz-{uuid.uuid4().hex[:8]}"
        rpc("register_device", tokC, p_client_id=cidC, p_platform="android")
        rpc("deactivate_member", tokA, p_user_id=uidC, p_devralan_user_id=uidPA)
        st, devC = rpc("register_device", tokC, p_client_id=cidC)
        kontrol("K42 · pasife alınan üyenin cihazı kendiliğinden iptal oldu",
                st >= 400 or (devC.get("iptal") is True
                              and devC.get("silinsin") is True), devC)

        # ---- Faz 8 · Ticari (0033) -------------------------------------------
        # Kendi carisiyle çalışıyor: çek tahsili ve iade bakiyeyi değiştiriyor,
        # önceki bölümlerin varsaydığı tutarlar bozulmasın.
        sec("K11 · çek yaşam döngüsü · iade · konsinye kapatma")

        st, f8 = rpc("create_account", tokA, p_store_id=storeA,
                     p_institution_id=kurumId, p_tip="kurum",
                     p_unvan="E2E Faz8 Kurumsal", p_credit_limit=100000)
        f8Cari = f8.get("id") if st == 200 else None
        kontrol("Faz 8 test carisi açıldı", f8Cari is not None, f8)

        # 10 adet × 100 ₺ × (1 − 0,20) = 800 ₺ borç
        st, sv = rpc("create_shipment", tokA, p_account_id=f8Cari,
                     p_items=[{"product_id": ornekUrun, "adet": 10}],
                     p_kaynak="elden")
        st, b0 = rpc("calc_account_balance", tokA, p_account=f8Cari)
        kontrol("teslimat borç doğurdu", float(b0) > 0, b0)

        st, ck = rpc("create_payment", tokA, p_account_id=f8Cari,
                     p_tutar=300, p_yontem="cek", p_cek_vade="2026-09-10",
                     p_cek_banka="Ziraat", p_cek_no="0012345")
        st, cekList = http(
            f"/rest/v1/cheques?select=id,durum,tutar&account_id=eq.{f8Cari}",
            token=tokA)
        cekId = cekList[0]["id"] if cekList else None
        kontrol("çek kaydı açıldı", cekId is not None, cekList)

        st, b1 = rpc("calc_account_balance", tokA, p_account=f8Cari)
        kontrol("K11 · çek ALINIRKEN bakiye DEĞİŞMİYOR",
                float(b1) == float(b0), (b0, b1))

        # ---- Geçiş tablosu: ekran ile sunucu AYNI mı --------------------------
        # Dart tarafındaki `cekGecisleri` ile sunucudaki `cheque_transition_ok`
        # ayrı yerlerde duruyor. Ayrışırlarsa ekran, sunucunun reddedeceği bir
        # düğme gösterir. 36 çiftin hepsi karşılaştırılıyor.
        dartGecis = {
            "portfoyde": ["tahsilde", "ciro_edildi", "iade_edildi"],
            "tahsilde": ["tahsil_edildi", "karsiliksiz", "portfoyde"],
            "ciro_edildi": ["karsiliksiz"],
            "karsiliksiz": ["tahsilde", "tahsil_edildi"],
            "tahsil_edildi": [],
            "iade_edildi": [],
        }
        durumlar = list(dartGecis)
        ayrik = []
        for eski in durumlar:
            for yeni in durumlar:
                st, ok = rpc("cheque_transition_ok", tokA,
                             p_eski=eski, p_yeni=yeni)
                if bool(ok) != (yeni in dartGecis[eski]):
                    ayrik.append(f"{eski}→{yeni} sunucu={ok}")
        kontrol("ekran ve sunucu geçiş tablosu AYNI", not ayrik, ayrik)

        # ---- Yaşam döngüsü ---------------------------------------------------
        st, r = rpc("set_cheque_status", tokA, p_cheque_id=cekId,
                    p_durum="tahsil_edildi")
        kontrol("portföydeki çek DOĞRUDAN tahsil edilemez", st >= 400, r)

        st, r = rpc("set_cheque_status", tokA, p_cheque_id=cekId,
                    p_durum="tahsilde")
        kontrol("çek tahsile verildi", st == 200 and r.get("degisti"), r)
        st, b2 = rpc("calc_account_balance", tokA, p_account=f8Cari)
        kontrol("tahsile vermek bakiyeyi DEĞİŞTİRMİYOR",
                float(b2) == float(b0), (b0, b2))

        st, r = rpc("set_cheque_status", tokA, p_cheque_id=cekId,
                    p_durum="tahsil_edildi")
        kontrol("K11 · tahsil edilince bakiye DÜŞTÜ",
                st == 200 and float(r.get("bakiye", 0)) == float(b0) - 300,
                (b0, r))
        st, r = rpc("set_cheque_status", tokA, p_cheque_id=cekId,
                    p_durum="portfoyde")
        kontrol("tahsil edilmiş çek geri alınamıyor (terminal)", st >= 400, r)

        # ---- Karşılıksız: hiç tahsil edilmemiş çek ---------------------------
        # `karsiliksiz` bakiyeyi DÜŞÜRMEZ, çünkü zaten düşmemişti; asıl etkisi
        # cariyi 'tahsilatta' durumuna almak.
        st, ck2 = rpc("create_payment", tokA, p_account_id=f8Cari,
                      p_tutar=200, p_yontem="cek", p_cek_vade="2026-09-20")
        st, cl2 = http(
            f"/rest/v1/cheques?select=id&account_id=eq.{f8Cari}"
            f"&durum=eq.portfoyde", token=tokA)
        cek2 = cl2[0]["id"] if cl2 else None
        rpc("set_cheque_status", tokA, p_cheque_id=cek2, p_durum="tahsilde")

        st, r = rpc("set_cheque_status", tokA, p_cheque_id=cek2,
                    p_durum="karsiliksiz")
        kontrol("karşılıksız kaydı GEREKÇE istiyor", st >= 400, r)
        st, r = rpc("set_cheque_status", tokA, p_cheque_id=cek2,
                    p_durum="karsiliksiz", p_gerekce="Yetersiz bakiye")
        kontrol("hiç tahsil edilmemiş çekin karşılıksızlığı bakiyeyi "
                "DEĞİŞTİRMİYOR",
                st == 200 and float(r.get("bakiye", 0)) == float(b0) - 300,
                (b0, r))
        st, ah = http(f"/rest/v1/accounts?select=durum&id=eq.{f8Cari}",
                      token=tokA)
        kontrol("karşılıksız cari 'tahsilatta' durumuna aldı",
                ah[0]["durum"] == "tahsilatta", ah)

        # ---- Ciro: bakiyeyi düşürür, geri dönerse borç GERİ GELİR -------------
        st, ck3 = rpc("create_payment", tokA, p_account_id=f8Cari,
                      p_tutar=150, p_yontem="cek", p_cek_vade="2026-10-05")
        st, cl3 = http(
            f"/rest/v1/cheques?select=id&account_id=eq.{f8Cari}"
            f"&durum=eq.portfoyde", token=tokA)
        cek3 = cl3[0]["id"] if cl3 else None
        st, r = rpc("set_cheque_status", tokA, p_cheque_id=cek3,
                    p_durum="ciro_edildi")
        kontrol("ciro KİME yapıldığını istiyor", st >= 400, r)
        st, r = rpc("set_cheque_status", tokA, p_cheque_id=cek3,
                    p_durum="ciro_edildi", p_endorsed_to="Bes Yayınları")
        kontrol("ciro edilen çek de bakiyeyi düşürüyor",
                st == 200 and float(r.get("bakiye", 0)) == float(b0) - 450,
                (b0, r))
        st, r = rpc("set_cheque_status", tokA, p_cheque_id=cek3,
                    p_durum="karsiliksiz", p_gerekce="Yayınevinden geri döndü")
        kontrol("K11 · ciro edilen çek geri dönünce borç GERİ GELDİ",
                st == 200 and float(r.get("bakiye", 0)) == float(b0) - 300,
                (b0, r))
        st, r = rpc("set_cheque_status", tokA, p_cheque_id=cek3,
                    p_durum="ciro_edildi", p_endorsed_to="Bes")
        kontrol("karşılıksız çek yeniden ciro EDİLEMİYOR", st >= 400, r)

        st, r = rpc("set_cheque_status", tokPA, p_cheque_id=cek3,
                    p_durum="karsiliksiz", p_gerekce="deneme")
        kontrol("pazarlamacı çek durumunu değiştiremiyor", st >= 400, r)
        st, r = rpc("set_cheque_status", tokB, p_cheque_id=cekId,
                    p_durum="tahsilde")
        kontrol("B, A'nın çekine dokunamıyor", st >= 400, r)

        # ---- Vade takvimi ----------------------------------------------------
        st, tk = rpc("cheque_calendar", tokA, p_store_id=storeA)
        kontrol("vade takvimi geliyor",
                st == 200 and "gunler" in (tk or {}), list((tk or {}).keys()))
        kontrol("takvim gün gün gruplanıyor",
                all("tarih" in g and "cekler" in g
                    for g in (tk or {}).get("gunler", [])), tk.get("gunler"))
        kontrol("K11 · karşılıksız toplamı ayrı veriliyor",
                float(tk.get("karsiliksiz", 0)) == 350.00, tk)

        st, n1 = rpc("notify_due_cheques", tokA, p_gun=3650)
        st, n2 = rpc("notify_due_cheques", tokA, p_gun=3650)
        kontrol("K41 · çek vadesi bildirimi üretiliyor", n1 > 0, n1)
        kontrol("aynı çek için İKİNCİ bildirim üretilmiyor", n2 == 0, (n1, n2))

        # ---- İade ------------------------------------------------------------
        st, ie = rpc("returnable_items", tokA, p_account_id=f8Cari)
        kontrol("iade edilebilirler listeleniyor",
                any(x["product_id"] == ornekUrun and x["kalan"] == 10
                    for x in (ie or [])), ie)
        kontrol("kalemin borçlandırıp doğurmadığı bildiriliyor",
                all("borclandirdi" in x for x in (ie or [])), ie)

        st, b4 = rpc("calc_account_balance", tokA, p_account=f8Cari)
        st, r = rpc("create_return", tokA, p_account_id=f8Cari,
                    p_items=[{"product_id": ornekUrun, "adet": 20}])
        kontrol("çıkandan fazlası iade EDİLEMİYOR", st >= 400, r)
        kontrol("hata kaç adet iade edilebileceğini söylüyor",
                "10 adet" in str((r or {}).get("message", "")), r)

        # Fiyat değişse de iade ÇIKIŞIN fiyatından hesaplanır (K28)
        rpc("upsert_store_product", tokA, p_store_id=storeA,
            p_product_id=ornekUrun, p_satis_fiyat=500)
        st, iad = rpc("create_return", tokA, p_account_id=f8Cari,
                      p_items=[{"product_id": ornekUrun, "adet": 2}],
                      p_gerekce="Hatalı baskı")
        # Çıkış 120 ₺ damgaladı: 2 × 120 × (1 − 0,20) = 192 ₺.
        # Güncel fiyattan hesaplansaydı 2 × 500 × 0,80 = 800 ₺ çıkardı.
        kontrol("K28 · iade GÜNCEL fiyattan değil damgadan hesaplandı",
                st == 200 and float(iad.get("toplam", 0)) == 192.00, iad)
        st, b5 = rpc("calc_account_balance", tokA, p_account=f8Cari)
        kontrol("iade borcu düşürdü", float(b5) == float(b4) - 192, (b4, b5))
        rpc("upsert_store_product", tokA, p_store_id=storeA,
            p_product_id=ornekUrun, p_satis_fiyat=120)

        # ---- Konsinye kapatma ------------------------------------------------
        st, kd = rpc("open_consignment_detail", tokA, p_account_id=konsCari)
        kontrol("K45 · konsinye ürün ürün türetiliyor",
                any(x["kalan"] == 5 for x in (kd or [])), kd)
        kontrol("kapatma fiyatı çıkış damgasından geliyor",
                all(x.get("birim_fiyat") is not None for x in (kd or [])), kd)

        konsUrun = (kd or [{}])[0].get("product_id")
        st, kb0 = rpc("calc_account_balance", tokA, p_account=konsCari)
        st, kap = rpc("settle_consignment", tokA, p_account_id=konsCari,
                      p_satilan=[{"product_id": konsUrun, "adet": 3}],
                      p_iade=[{"product_id": konsUrun, "adet": 2}],
                      p_gerekce="Dönem sonu")
        kontrol("konsinye TEK çağrıda kapandı",
                st == 200 and kap.get("shipment_id") and kap.get("return_id"),
                kap)
        kontrol("K26 · satılan kısım borç doğurdu",
                float(kap.get("borc", 0)) > 0
                and float(kap.get("bakiye", 0)) == float(kb0) + float(kap["borc"]),
                (kb0, kap))
        kontrol("K45 · açık konsinye kapandı",
                float(kap.get("kalan_konsinye", -1)) == 0, kap)
        st, kd2 = rpc("open_consignment_detail", tokA, p_account_id=konsCari)
        kontrol("kapanan konsinye listeden düştü", kd2 in ([], None), kd2)

        st, r = rpc("settle_consignment", tokA, p_account_id=konsCari,
                    p_satilan=[], p_iade=[])
        kontrol("boş kapanış reddediliyor", st >= 400, r)

        # ---- Faz 9 · Deneme takvimi (0034) -----------------------------------
        sec("K20 · K22 · deneme takvimi")

        # Tarih okuma: Excel aynı sütunda üç ayrı biçim üretebiliyor.
        for metin, beklenen in [("13.11.2025", "2025-11-13"),
                                ("45974", "2025-11-13"),
                                ("2025-11-13", "2025-11-13"),
                                ("13 Kasım 2025", "2025-11-13")]:
            st, d = rpc("tr_tarih", tokA, p=metin)
            kontrol(f"tarih okundu: {metin}", d == beklenen, (metin, d))
        st, d = rpc("tr_tarih", tokA, p="bilinmiyor")
        kontrol("okunamayan tarih sessizce NULL", d is None, d)

        st, ar = rpc("tr_tarih_araligi", tokA, p="29 Eylül-3 Ekim 2025")
        kontrol("iki aylı aralık çözülüyor",
                ar and ar[0]["baslangic"] == "2025-09-29"
                and ar[0]["bitis"] == "2025-10-03", ar)
        st, ar = rpc("tr_tarih_araligi", tokA, p="15-18 OCAK 2026")
        kontrol("tek aylı aralık çözülüyor",
                ar and ar[0]["baslangic"] == "2026-01-15"
                and ar[0]["bitis"] == "2026-01-18", ar)

        # ---- K49 · takvim içe aktarma ----------------------------------------
        st, bt = rpc("create_import_batch", tokA, p_store_id=storeA,
                     p_tur="deneme_takvimi", p_dosya_adi="takvim.xlsx",
                     p_satir_sayisi=3)
        batchD = bt if st == 200 else None    # uuid döner, jsonb değil
        kontrol("deneme aktarım partisi açıldı", batchD is not None, bt)

        # Tarihler BUGÜNE GÖRE kurulur: "yaklaşanlar" ve T-10 bildirimi
        # geçmişe bakmaz, sabit 2025 tarihleriyle yazılan test bir yıl sonra
        # sessizce boş küme doğrular.
        AYLAR = ["Ocak", "Şubat", "Mart", "Nisan", "Mayıs", "Haziran",
                 "Temmuz", "Ağustos", "Eylül", "Ekim", "Kasım", "Aralık"]
        bugun = datetime.date.today()
        stokTG = bugun + datetime.timedelta(days=20)
        uygTG1 = stokTG + datetime.timedelta(days=7)
        uygTG2 = uygTG1 + datetime.timedelta(days=1)
        stokTakvim = stokTG + datetime.timedelta(days=3)
        # Aynı ayda kalsınlar: takvim ay ay sorgulanıyor.
        if stokTakvim.month != stokTG.month:
            stokTakvim = stokTG + datetime.timedelta(days=1)
        ayBasi = stokTG.replace(day=1).isoformat()
        uygMetin = (f"{uygTG1.day}-{uygTG2.day} "
                    f"{AYLAR[uygTG1.month - 1]} {uygTG1.year}"
                    if uygTG1.month == uygTG2.month else
                    f"{uygTG1.day} {AYLAR[uygTG1.month - 1]}-"
                    f"{uygTG2.day} {AYLAR[uygTG2.month - 1]} {uygTG2.year}")

        satirlar = [
            {"_satir": 2, "ad": "E2E TÜRKİYE GENELİ-2", "yayinevi": "E2E AV",
             "deneme_turu": "turkiye_geneli", "kademe": "ortaokul",
             "duzey": "8. SINIF", "kapsam": "genel",
             "stok_tarihi": stokTG.strftime("%d.%m.%Y"),
             "uygulama_tarihi": uygMetin},
            {"_satir": 3, "ad": "E2E TAKVİM-7", "yayinevi": "E2E AV",
             "deneme_turu": "takvim", "kademe": "ortaokul",
             "duzey": "5-6-7-8. SINIF",
             "stok_tarihi": stokTakvim.strftime("%d.%m.%Y")},
            {"_satir": 4, "ad": "E2E TARİHSİZ", "yayinevi": "E2E AV",
             "deneme_turu": "takvim", "stok_tarihi": ""},
        ]
        st, kuru = rpc("import_chunk_deneme", tokA, p_batch_id=batchD,
                       p_satirlar=satirlar, p_kuru_kosu=True)
        kontrol("kuru koşu: 2 yeni 1 hatalı",
                kuru.get("yeni") == 2 and kuru.get("hatali") == 1, kuru)
        kontrol("stok tarihsiz kalem REDDEDİLİYOR — takvimin omurgası o",
                any("Stok tarihi" in (h.get("sebep") or "")
                    for h in kuru.get("hatalar", [])), kuru.get("hatalar"))
        st, bosD = http(
            "/rest/v1/products?select=id&katalog=eq.deneme"
            "&ad=eq.E2E%20TAKV%C4%B0M-7", token=tokA)
        kontrol("kuru koşudan sonra takvim BOŞ", bosD in ([], None), bosD)

        st, ger = rpc("import_chunk_deneme", tokA, p_batch_id=batchD,
                      p_satirlar=satirlar, p_kuru_kosu=False)
        kontrol("gerçek koşu kuru koşuyla AYNI sonucu verdi",
                ger.get("yeni") == kuru.get("yeni")
                and ger.get("hatali") == kuru.get("hatali"), (kuru, ger))

        st, dl = http(
            "/rest/v1/deneme_details?select=product_id,deneme_turu,stok_tarihi,"
            "uygulama_baslangic,uygulama_bitis,uygulama_metin,duzey"
            f"&stok_tarihi=eq.{stokTG.isoformat()}", token=tokA)
        kontrol("Türkiye Geneli kaydı oluştu",
                dl and dl[0]["deneme_turu"] == "turkiye_geneli", dl)
        kontrol("uygulama ARALIĞI iki alana ayrıştı",
                dl and dl[0]["uygulama_baslangic"] == uygTG1.isoformat()
                and dl[0]["uygulama_bitis"] == uygTG2.isoformat(), dl)
        kontrol("ham metin sadakat için saklandı",
                dl and dl[0]["uygulama_metin"] == uygMetin, dl)
        tgId = dl[0]["product_id"] if dl else None

        st, pr = http(f"/rest/v1/products?select=sinif,katalog&id=eq.{tgId}",
                      token=tokA)
        kontrol("düzeyden sınıf dizisi türetildi",
                pr and pr[0]["sinif"] == [8], pr)
        kontrol("K15 · deneme de KATALOGDA duruyor",
                pr and pr[0]["katalog"] == "deneme", pr)

        # Aynı dosya ikinci kez: çiftlenme YOK
        st, tekrar = rpc("import_chunk_deneme", tokA, p_batch_id=batchD,
                         p_satirlar=satirlar, p_kuru_kosu=False)
        kontrol("aynı takvim ikinci kez YENİ kalem AÇMIYOR",
                tekrar.get("yeni") == 0 and tekrar.get("guncelleme") == 2,
                tekrar)

        # ---- Takvim ----------------------------------------------------------
        st, tk = rpc("exam_calendar", tokA, p_store_id=storeA, p_ay=ayBasi)
        kontrol("takvim ayı geliyor",
                st == 200 and tk.get("eksen") == "stok", tk)
        gunler = {g["tarih"]: g for g in tk.get("gunler", [])}
        kontrol("stok tarihine göre gün gruplandı",
                stokTG.isoformat() in gunler
                and stokTakvim.isoformat() in gunler, list(gunler))
        kontrol("K20 · Türkiye Geneli gün hücresinde AYRI sayılıyor",
                gunler.get(stokTG.isoformat(), {}).get("turkiye_geneli") == 1,
                gunler)

        st, tk2 = rpc("exam_calendar", tokA, p_store_id=storeA,
                      p_ay=uygTG1.replace(day=1).isoformat(),
                      p_eksen="uygulama")
        kontrol("uygulama ekseninde tarihi olan gün taşınıyor",
                any(g["tarih"] == uygTG1.isoformat()
                    for g in tk2.get("gunler", [])), tk2.get("gunler"))
        st, tk2b = rpc("exam_calendar", tokA, p_store_id=storeA, p_ay=ayBasi,
                       p_eksen="uygulama")
        kontrol("BULGU B · uygulama tarihi olmayan kalem KAYBOLMUYOR",
                any(x["ad"] == "E2E TAKVİM-7"
                    for x in tk2b.get("tarihsiz", [])), tk2b.get("tarihsiz"))

        st, tk3 = rpc("exam_calendar", tokA, p_store_id=storeA, p_ay=ayBasi,
                      p_turu="turkiye_geneli")
        kontrol("tür süzgeci çalışıyor", tk3.get("toplam") == 1, tk3)

        st, bosT = rpc("exam_calendar", tokB, p_store_id=storeA, p_ay=ayBasi)
        kontrol("B, A'nın takvimini göremiyor", bosT is None, bosT)

        # ---- K22 · sınıf mevcutları ------------------------------------------
        st, me = rpc("set_enrollments", tokA, p_account_id=kismiCari,
                     p_items=[{"sinif": 8, "ogrenci_sayisi": 180},
                              {"sinif": 7, "ogrenci_sayisi": 120}])
        kontrol("mevcutlar kaydedildi", me.get("toplam") == 300, me)
        st, r = rpc("set_enrollments", tokA, p_account_id=kismiCari,
                    p_items=[{"sinif": 99, "ogrenci_sayisi": 10}])
        kontrol("geçersiz sınıf reddediliyor", st >= 400, r)

        st, gm = rpc("get_enrollments", tokA, p_account_id=kismiCari)
        kontrol("mevcutlar okunuyor", gm.get("toplam") == 300, gm)
        kontrol("kimin bildirdiği tutuluyor",
                all(x.get("bildiren") for x in gm.get("siniflar", [])), gm)

        st, me2 = rpc("set_enrollments", tokA, p_account_id=kismiCari,
                      p_items=[{"sinif": 7, "ogrenci_sayisi": 0}])
        kontrol("sıfır girilince satır SİLİNİYOR — 'bilinmiyor' ile "
                "'0 öğrenci' aynı şey değil",
                me2.get("toplam") == 180, me2)

        # ---- Kurumlara öner --------------------------------------------------
        rpc("assign_accounts", tokA, p_account_ids=[kismiCari],
            p_user_id=uidPA, p_period_id=periodA)
        st, hd = rpc("exam_targets", tokPA, p_product_id=tgId,
                     p_store_id=storeA)
        hedef = next((x for x in (hd or []) if x["account_id"] == kismiCari), None)
        kontrol("K5 · hedefler PORTFÖYDEN geliyor", hedef is not None, hd)
        kontrol("K22 · adet önerisi sınıf mevcudundan doldu",
                hedef and hedef.get("mevcut") == 180, hedef)
        kontrol("önerinin KAYNAĞI bildiriliyor",
                hedef and (hedef.get("oneri") or {}).get("kaynak") is not None,
                hedef)

        st, bosH = rpc("exam_targets", tokB, p_product_id=tgId,
                       p_store_id=storeA)
        kontrol("B'nin hedef listesi boş", bosH in ([], None), bosH)

        # Takvim import'u ürünü açar ama FİYAT AÇMAZ (K12). Fiyatsız üründen
        # açılan talep siparişe dönemez; 20 ölü talep tek bir açık hatadan
        # çok daha kötü.
        st, r = rpc("bulk_request_from_exam", tokPA, p_product_id=tgId,
                    p_items=[{"account_id": kismiCari, "adet": 10}])
        kontrol("fiyatsız denemeden toplu talep AÇILMIYOR", st >= 400, r)
        kontrol("hata ne yapılacağını söylüyor",
                "fiyat girin" in str((r or {}).get("message", "")), r)
        st, fp = rpc("exam_priced", tokPA, p_product_id=tgId,
                     p_store_id=storeA)
        kontrol("fiyatsız deneme işaretli", fp is False, fp)

        rpc("upsert_store_product", tokA, p_store_id=storeA,
            p_product_id=tgId, p_satis_fiyat=25)
        st, fp2 = rpc("exam_priced", tokPA, p_product_id=tgId,
                      p_store_id=storeA)
        kontrol("fiyat girilince işaret düşüyor", fp2 is True, fp2)

        st, tt = rpc("bulk_request_from_exam", tokPA, p_product_id=tgId,
                     p_items=[{"account_id": kismiCari, "adet": 180}])
        kontrol("toplu talep açıldı",
                tt.get("acilan") == 1 and tt.get("toplam_adet") == 180, tt)
        talepD = tt["sonuclar"][0].get("request_id")
        st, td = rpc("request_detail", tokPA, p_request_id=talepD)
        kontrol("K37 · normal talep akışına girdi — durum makinesi bozulmadı",
                td and td.get("durum") == "gonderildi", td)
        kontrol("talep TEK cariye ait (K7)",
                td and td["cari"]["id"] == kismiCari, td)

        # Bir cari düşse de diğerleri açılır
        st, tt2 = rpc("bulk_request_from_exam", tokPA, p_product_id=tgId,
                      p_items=[{"account_id": kismiCari, "adet": 5},
                               {"account_id": kismiCari, "adet": 0}])
        kontrol("hatalı satır toplu işlemi DURDURMUYOR",
                tt2.get("acilan") == 1 and tt2.get("hatali") == 1, tt2)
        kontrol("hangi cariye açıldığı kalem kalem bildiriliyor",
                all("account_id" in x for x in tt2.get("sonuclar", [])), tt2)
        for s_ in tt2.get("sonuclar", []) + tt.get("sonuclar", []):
            if s_.get("request_id"):
                rpc("cancel_request", tokPA, p_request_id=s_["request_id"])

        # ---- Yaklaşanlar ve bildirim -----------------------------------------
        st, yk = rpc("exam_upcoming", tokA, p_store_id=storeA, p_gun=60)
        kontrol("yaklaşan denemeler şeridi geliyor",
                any(x["id"] == tgId for x in (yk or [])), yk)
        kontrol("sabit tarihli olanlar işaretli",
                any(x.get("sabit") is True for x in (yk or [])), yk)

        st, n1 = rpc("notify_upcoming_exams", tokA, p_gun=60)
        st, n2 = rpc("notify_upcoming_exams", tokA, p_gun=60)
        kontrol("K41 · Türkiye Geneli bildirimi üretiliyor", n1 > 0, n1)
        kontrol("aynı deneme için İKİNCİ bildirim üretilmiyor", n2 == 0,
                (n1, n2))

        # ---- Faz 9 · Abonelik programı (0035) --------------------------------
        sec("C-3 · K47 · deneme abonelik programı")

        # Denemenin dükkanda fiyatı olmalı: teslimat fiyat damgalıyor (K28).
        rpc("upsert_store_product", tokA, p_store_id=storeA,
            p_product_id=tgId, p_satis_fiyat=25)
        st, tkList = http(
            "/rest/v1/products?select=id&katalog=eq.deneme"
            "&ad=eq.E2E%20TAKV%C4%B0M-7", token=tokA)
        takvimId = tkList[0]["id"] if tkList else None
        if takvimId:
            rpc("upsert_store_product", tokA, p_store_id=storeA,
                p_product_id=takvimId, p_satis_fiyat=20)

        st, r = rpc("create_exam_program", tokA, p_account_id=kismiCari,
                    p_ogrenci_sayisi=0)
        kontrol("öğrencisiz program açılamıyor", st >= 400, r)
        st, r = rpc("create_exam_program", tokA, p_account_id=kismiCari,
                    p_modu="serbest_periyot", p_ogrenci_sayisi=200)
        kontrol("serbest periyot modunda periyot ZORUNLU", st >= 400, r)

        st, pg = rpc("create_exam_program", tokA, p_account_id=kismiCari,
                     p_modu="takvim_bagli", p_ogrenci_sayisi=200,
                     p_deneme_adedi=12)
        progId = pg.get("id") if st == 200 else None
        kontrol("program açıldı", progId is not None, pg)

        # ---- Geçiş tablosu: ekran ile sunucu AYNI mı -------------------------
        dartTeslim = {
            "planlandi": ["hazirlaniyor", "ertelendi", "iptal"],
            "ertelendi": ["planlandi", "hazirlaniyor", "iptal"],
            "hazirlaniyor": ["ertelendi", "iptal", "planlandi"],
            "teslim_edildi": ["uygulandi", "kapandi"],
            "uygulandi": ["kapandi"],
            "kapandi": [],
            "iptal": [],
        }
        ayrikT = []
        for eski in dartTeslim:
            for yeni in dartTeslim:
                st, ok = rpc("exam_transition_ok", tokA,
                             p_eski=eski, p_yeni=yeni)
                bekle_ = yeni in dartTeslim[eski]
                # `hazirlaniyor → teslim_edildi` sunucuda AÇIK ama ekranda YOK:
                # o geçiş yalnızca teslimat kaydından geçer (C-3).
                if eski == "hazirlaniyor" and yeni == "teslim_edildi":
                    bekle_ = True
                if bool(ok) != bekle_:
                    ayrikT.append(f"{eski}→{yeni} sunucu={ok}")
        kontrol("teslim geçiş tablosu ekranla AYNI", not ayrikT, ayrikT)

        # ---- Plan -----------------------------------------------------------
        st, pl = rpc("plan_exam_deliveries", tokA, p_program_id=progId,
                     p_items=[{"product_id": tgId},
                              {"product_id": takvimId}])
        kontrol("teslim planı kuruldu", pl.get("eklenen") == 2, pl)
        st, kl = http(
            f"/rest/v1/exam_deliveries?select=id,product_id,planlanan_tarih,"
            f"adet,durum&exam_program_id=eq.{progId}&order=planlanan_tarih",
            token=tokA)
        kontrol("Y-8 · takvime bağlı modda tarih TAKVİMDEN geldi",
                any(x["product_id"] == tgId
                    and x["planlanan_tarih"] == uygTG1.isoformat()
                    for x in (kl or [])), kl)
        kontrol("adet programın öğrenci sayısından doldu",
                all(x["adet"] == 200 for x in (kl or [])), kl)
        kalemTG = next((x["id"] for x in (kl or [])
                        if x["product_id"] == tgId), None)
        kalemTK = next((x["id"] for x in (kl or [])
                        if x["product_id"] == takvimId), None)

        st, pg2 = rpc("create_exam_program", tokA, p_account_id=kismiCari,
                      p_modu="serbest_periyot", p_ogrenci_sayisi=50,
                      p_periyot_gun=14)
        prog2 = pg2.get("id")
        st, r = rpc("plan_exam_deliveries", tokA, p_program_id=prog2,
                    p_items=[{"product_id": tgId}])
        kontrol("K20 · Türkiye Geneli serbest periyoda KONULAMIYOR",
                st >= 400, r)
        kontrol("sebep tarihinin sabit olması",
                "sabittir" in str((r or {}).get("message", "")), r)
        st, pl2 = rpc("plan_exam_deliveries", tokA, p_program_id=prog2,
                      p_items=[{"product_id": takvimId},
                               {"product_id": takvimId}],
                      p_baslangic=bugun.isoformat())
        st, kl2 = http(
            f"/rest/v1/exam_deliveries?select=planlanan_tarih"
            f"&exam_program_id=eq.{prog2}&order=planlanan_tarih", token=tokA)
        kontrol("serbest periyotta tarih PERİYOTTAN üretildi",
                len(kl2 or []) == 2
                and kl2[0]["planlanan_tarih"] == bugun.isoformat()
                and kl2[1]["planlanan_tarih"]
                    == (bugun + datetime.timedelta(days=14)).isoformat(), kl2)

        # ---- Durum makinesi --------------------------------------------------
        st, r = rpc("set_exam_delivery_status", tokA, p_delivery_id=kalemTG,
                    p_durum="teslim_edildi")
        kontrol("C-3 · plan ELLE teslim edildi yapılamıyor", st >= 400, r)
        kontrol("hata teslimat girilmesi gerektiğini söylüyor",
                "teslimat girin" in str((r or {}).get("message", "")), r)

        st, r = rpc("set_exam_delivery_status", tokA, p_delivery_id=kalemTG,
                    p_durum="ertelendi")
        kontrol("erteleme yeni TARİH istiyor", st >= 400, r)
        st, r = rpc("set_exam_delivery_status", tokA, p_delivery_id=kalemTG,
                    p_durum="ertelendi",
                    p_yeni_tarih=(uygTG1 + datetime.timedelta(days=7)).isoformat())
        kontrol("erteleme GEREKÇE istiyor", st >= 400, r)
        st, r = rpc("set_exam_delivery_status", tokA, p_delivery_id=kalemTG,
                    p_durum="ertelendi", p_not="Okul sınav haftası",
                    p_yeni_tarih=(uygTG1 + datetime.timedelta(days=7)).isoformat())
        kontrol("kalem ertelendi", st == 200 and r.get("degisti"), r)
        st, kk = http(
            f"/rest/v1/exam_deliveries?select=onceki_tarih,planlanan_tarih,"
            f"ertelendi_notu&id=eq.{kalemTG}", token=tokA)
        kontrol("erteleme GEÇMİŞİ tutuluyor",
                kk and kk[0]["onceki_tarih"] == uygTG1.isoformat(), kk)

        # ---- Teslimat: borç buradan doğar ------------------------------------
        st, b0 = rpc("calc_account_balance", tokA, p_account=kismiCari)
        st, tsl = rpc("deliver_exam", tokA, p_delivery_id=kalemTG)
        kontrol("teslimat kaydı üretildi",
                st == 200 and tsl.get("shipment_id"), tsl)
        kontrol("K26 · borç TESLİMATTAN doğdu",
                float(tsl.get("bakiye", 0)) == float(b0) + 200 * 25, (b0, tsl))
        st, sh = http(
            f"/rest/v1/shipments?select=exam_delivery_id"
            f"&id=eq.{tsl['shipment_id']}", token=tokA)
        kontrol("C-3 · teslimat plana BAĞLANDI",
                sh and sh[0]["exam_delivery_id"] == kalemTG, sh)
        st, r = rpc("deliver_exam", tokA, p_delivery_id=kalemTG)
        kontrol("aynı kalem iki kez teslim EDİLEMİYOR", st >= 400, r)

        st, r = rpc("set_exam_delivery_status", tokA, p_delivery_id=kalemTG,
                    p_durum="uygulandi")
        kontrol("K47 · uygulandı AYRI bir durum", st == 200, r)

        # ---- Ö-9 · öğrenci sayısı değişikliği ---------------------------------
        st, gu = rpc("update_exam_program", tokA, p_program_id=progId,
                     p_ogrenci_sayisi=250)
        kontrol("Ö-9 · değişiklik YALNIZCA teslim edilmemiş kaleme uygulandı",
                gu.get("guncellenen_kalem") == 1
                and gu.get("degismeyen_kalem") == 1, gu)
        st, kd = http(
            f"/rest/v1/exam_deliveries?select=id,adet"
            f"&exam_program_id=eq.{progId}", token=tokA)
        kontrol("K28 · teslim edilen kalemin adedi DEĞİŞMEDİ",
                any(x["id"] == kalemTG and x["adet"] == 200 for x in (kd or []))
                and any(x["id"] == kalemTK and x["adet"] == 250
                        for x in (kd or [])), kd)

        # ---- Detay ve özet ---------------------------------------------------
        st, pd = rpc("exam_program_detail", tokA, p_program_id=progId)
        kontrol("program detayı geliyor",
                st == 200 and len(pd.get("kalemler", [])) == 2, pd)
        kt = next((x for x in pd["kalemler"] if x["id"] == kalemTG), None)
        kontrol("K48 · ödeme durumu TÜRETİLİYOR",
                kt and kt.get("odeme_durumu") in ("odenmedi", "kismi", "odendi"),
                kt)
        kontrol("K47 · uygulanan teslim edilenden ayrı sayılıyor",
                pd["ozet"]["uygulanan"] == 1
                and pd["ozet"]["teslim_edilen"] == 1, pd["ozet"])

        st, oz = rpc("exam_program_summary", tokA, p_store_id=storeA,
                     p_period_id=periodA)
        kontrol("dönem özeti geliyor", st == 200 and oz.get("program") >= 2, oz)
        kontrol("planlanan ile uygulanan yan yana",
                oz.get("planlanan_kalem", 0) > oz.get("uygulanan", 0), oz)
        kontrol("en az bir kez ertelenen sayılıyor",
                oz.get("ertelenen", 0) >= 1, oz)

        st, n1 = rpc("notify_exam_deliveries", tokA, p_gun=60)
        st, n2 = rpc("notify_exam_deliveries", tokA, p_gun=60)
        kontrol("K41 · teslim hatırlatması üretiliyor", n1 > 0, n1)
        kontrol("aynı kalem için İKİNCİ hatırlatma yok", n2 == 0, (n1, n2))

        # ---- İptal ------------------------------------------------------------
        st, ip = rpc("cancel_exam_program", tokA, p_program_id=progId,
                     p_gerekce="Okul vazgeçti")
        kontrol("teslim edilmemiş kalem DÜŞTÜ",
                ip.get("dusen_kalem") == 1, ip)
        kontrol("teslim edilmiş kalem duruyor",
                ip.get("teslim_edilmis_kalem") == 1, ip)
        kontrol("teslim edilenin BORCU duruyor",
                float(ip.get("bakiye", 0)) == float(b0) + 200 * 25, (b0, ip))
        st, r = rpc("update_exam_program", tokA, p_program_id=progId,
                    p_ogrenci_sayisi=300)
        kontrol("kapalı program değiştirilemiyor", st >= 400, r)

        st, r = rpc("exam_program_detail", tokB, p_program_id=progId)
        kontrol("B, A'nın programını göremiyor", r is None, r)

        # ---- K50 · rapor motoru (Faz 10) -------------------------------------
        sec("K50 · rapor motoru")
        st, kat = rpc("report_catalog", tokA)
        kodlar = {r["kod"] for r in (kat or [])}
        kontrol("katalog rapor listesi dönüyor", len(kodlar) >= 15, len(kodlar))
        kontrol("çekirdek raporlar katalogda",
                {"ciro", "borclu_cariler", "yaslandirma", "tahsilat_ozeti"}
                <= kodlar, sorted(kodlar))
        kontrol("her rapor boyut ve ölçü tanımını taşıyor",
                all(r["boyutlar"] and r["olculer"] for r in (kat or [])),
                [r["kod"] for r in (kat or []) if not (r["boyutlar"] and r["olculer"])])

        # Katalogdaki HER rapor gerçekten koşuyor. Tanım yazıp sorgusu
        # patlayan bir rapor, katalogda görünüp tıklanınca hata veren rapordur.
        patlayan = []
        for r in (kat or []):
            st, _ = rpc("report_run", tokA, p_kod=r["kod"], p_store_id=storeA)
            if st != 200:
                patlayan.append(r["kod"])
        kontrol("katalogdaki HER rapor hatasız koşuyor", not patlayan, patlayan)

        st, ciro = rpc("report_run", tokA, p_kod="ciro", p_store_id=storeA)
        kontrol("ciro raporu satır üretiyor", ciro.get("satirlar"), ciro)
        kontrol("sütun tanımı sonuçla birlikte dönüyor",
                [c["anahtar"] for c in ciro["sutunlar"]][:1] == ["pazarlamaci"],
                ciro.get("sutunlar"))
        kontrol("K26 · ciro TESLİMATTAN geliyor (teslimat yoksa sıfır olurdu)",
                float(ciro["toplam"]["ciro"]) > 0, ciro["toplam"])

        # Toplam SAYFANIN değil RAPORUN toplamı: ilk-N gösterilse bile alttaki
        # rakam tüm kırılımı kapsamalı.
        st, tek = rpc("report_run", tokA, p_kod="ciro", p_store_id=storeA,
                      p_kirilim=["cari"], p_limit=1)
        kontrol("sayfalanan raporda toplam TÜM kırılımı kapsıyor",
                len(tek["satirlar"]) == 1
                and float(tek["toplam"]["ciro"]) >= float(
                    tek["satirlar"][0]["ciro"]),
                (tek["toplam"], tek["satirlar"]))
        kontrol("sayfa dışında kalan kırılım sayısı bildiriliyor",
                tek["kirilim_sayisi"] >= 1, tek.get("kirilim_sayisi"))

        # K7 · Motor kuralı UYGULUYOR, belgede yazmakla bırakmıyor.
        st, k7 = rpc("report_run", tokA, p_kod="borclu_cariler",
                     p_store_id=storeA, p_kirilim=["kurum"])
        kontrol("K7 · kurum kırılımı BAKİYE raporunda cariye çevriliyor",
                k7["kirilim"] == ["cari"], k7.get("kirilim"))
        kontrol("K7 · sebebi kullanıcıya SÖYLENİYOR",
                any("kefili değildir" in u for u in k7["uyarilar"]),
                k7.get("uyarilar"))
        st, hacim = rpc("report_run", tokA, p_kod="kurum_hacmi",
                        p_store_id=storeA, p_kirilim=["kurum"])
        kontrol("K7 · kurum kırılımı HACİM raporunda serbest",
                hacim["kirilim"] == ["kurum"] and not hacim["uyarilar"],
                (hacim.get("kirilim"), hacim.get("uyarilar")))

        # Çok seviyeli kırılım
        st, cok = rpc("report_run", tokA, p_kod="urun_satisi",
                      p_store_id=storeA, p_kirilim=["yayinevi", "urun"])
        kontrol("çok seviyeli kırılım çalışıyor",
                [c["anahtar"] for c in cok["sutunlar"]][:2]
                == ["yayinevi", "urun"], cok.get("sutunlar"))

        # Beyaz liste: anahtar katalogda yoksa istek reddedilir.
        st, r = rpc("report_run", tokA, p_kod="ciro", p_store_id=storeA,
                    p_kirilim=["'; drop table accounts; --"])
        kontrol("katalogda olmayan kırılım REDDEDİLİYOR", st >= 400, r)
        st, r = rpc("report_run", tokA, p_kod="olmayan", p_store_id=storeA)
        kontrol("bilinmeyen rapor kodu reddediliyor", st >= 400, r)
        st, hala = http("/rest/v1/accounts?select=id&limit=1", token=tokA)
        kontrol("enjeksiyon denemesi tabloyu ETKİLEMEDİ", st == 200, st)

        # Süzgeç
        st, suz = rpc("report_run", tokA, p_kod="ciro", p_store_id=storeA,
                      p_filtreler={"tarih_baslangic": "2000-01-01",
                                   "tarih_bitis": "2000-12-31"})
        kontrol("tarih süzgeci uygulanıyor",
                float(suz["toplam"]["ciro"]) == 0, suz["toplam"])

        # Yetki: B, A'nın verisini raporda göremiyor.
        st, bs = rpc("report_run", tokB, p_kod="ciro", p_store_id=storeA)
        kontrol("başka işletmenin dükkanı raporda BOŞ",
                st >= 400 or float(bs["toplam"]["ciro"]) == 0, bs)

        # Kaydedilmiş rapor (K50 §1.3)
        st, rid = rpc("save_report", tokA, p_ad="Aylık ciro", p_kod="ciro",
                      p_store_id=storeA, p_kirilim=["ay"],
                      p_filtreler={"cari_tipi": "kurum"}, p_paylasim="dukkan")
        kontrol("rapor kaydediliyor", st == 200 and rid, rid)
        st, kl = rpc("saved_reports_list", tokA, p_store_id=storeA)
        kayit = next((x for x in (kl or []) if x["id"] == rid), None)
        kontrol("kayıtlı rapor kırılımıyla geri geliyor",
                kayit and kayit["kirilim"] == ["ay"], kayit)
        kontrol("kayıtlı rapor süzgeciyle geri geliyor",
                kayit and kayit["filtreler"] == {"cari_tipi": "kurum"}, kayit)
        st, r = rpc("save_report", tokA, p_ad="", p_kod="ciro",
                    p_store_id=storeA)
        kontrol("adsız rapor kaydedilemiyor", st >= 400, r)
        st, r = rpc("delete_saved_report", tokPA, p_id=rid)
        kontrol("başkasının kaydı SİLİNEMİYOR", st >= 400, r)
        # `void` dönen RPC 204 verir; asıl iddia kaydın GERÇEKTEN gitmesi.
        st, r = rpc("delete_saved_report", tokA, p_id=rid)
        st2, kl2 = rpc("saved_reports_list", tokA, p_store_id=storeA)
        kontrol("kendi kaydı silinebiliyor",
                st < 300 and not any(x["id"] == rid for x in (kl2 or [])),
                (st, r))

        # K8 · Kapalı dönem özeti bir kez hesaplanır, saklanır.
        st, canli = rpc("report_run_cached", tokA, p_kod="ciro",
                        p_store_id=storeA,
                        p_filtreler={"donem": [periodA]})
        kontrol("açık dönemde önbellek KULLANILMIYOR",
                canli.get("kaynak_tipi") is None, canli.get("kaynak_tipi"))
        st, _ = rpc("set_period_status", tokA, p_period_id=periodA,
                    p_status="kapali")
        st, ilk = rpc("report_run_cached", tokA, p_kod="ciro",
                      p_store_id=storeA, p_filtreler={"donem": [periodA]})
        kontrol("kapalı dönem özeti işaretli",
                ilk.get("kaynak_tipi") == "kapali_donem_ozeti",
                ilk.get("kaynak_tipi"))
        st, ikinci_kez = rpc("report_run_cached", tokA, p_kod="ciro",
                             p_store_id=storeA, p_filtreler={"donem": [periodA]})
        kontrol("ikinci çağrı SAKLANAN özeti okuyor",
                ikinci_kez.get("uretildi_at") == ilk.get("uretildi_at"),
                (ilk.get("uretildi_at"), ikinci_kez.get("uretildi_at")))
        # Süzgeç eklenirse saklanan özet SORULAN SORUYA ait olmaz.
        st, suzgecli = rpc("report_run_cached", tokA, p_kod="ciro",
                           p_store_id=storeA,
                           p_filtreler={"donem": [periodA],
                                        "cari_tipi": "ogretmen"})
        kontrol("ek süzgeçli istek önbelleğe DÜŞMÜYOR",
                suzgecli.get("kaynak_tipi") is None,
                suzgecli.get("kaynak_tipi"))
        rpc("set_period_status", tokA, p_period_id=periodA, p_status="aktif")

        # ---- Dükkan pasifleştirme (0018) -------------------------------------
        # Artık GERÇEK borç var (§4.2 örneğinden), sentetik fikstüre gerek yok.
        sec("Dükkan pasifleştirme kapıları")
        st, sl = http(f"/rest/v1/stores?select=id,ad,aktif&tenant_id=eq.{tenantA}", token=tokA)
        ikinci = next((x["id"] for x in (sl or []) if x["id"] != storeA), None)
        kontrol("ikinci dükkan var", ikinci is not None, sl)

        st, ucuncu = http("/rest/v1/stores", "POST", token=tokA, body={
            "tenant_id": tenantA, "ad": "E2E Üçüncü Şube"})
        st, sl2 = http(f"/rest/v1/stores?select=id&ad=eq.E2E%20%C3%9C%C3%A7%C3%BCnc%C3%BC%20%C5%9Eube", token=tokA)
        ucuncuId = sl2[0]["id"] if sl2 else None

        st, etki = rpc("store_deactivation_check", tokA, p_store_id=storeA)
        kontrol("etki özeti dönüyor", st == 200 and "aktif_cari" in (etki or {}), etki)
        kontrol("borçlu cari sayısı gerçek veriden geliyor",
                etki.get("borclu_cari", 0) >= 1, etki)
        kontrol("askıda kalacak tutar da bildiriliyor",
                float(etki.get("borc_tutari", 0)) > 0, etki)

        # Kapı 1 · açık bakiye
        st, r = rpc("set_store_status", tokA, p_store_id=storeA, p_aktif=False)
        kontrol("bakiyesi kapanmamış cari varsa PASİFE ALINAMIYOR", st >= 400, r)
        kontrol("hata sebebi borç olduğunu söylüyor",
                "kapanmamış" in str((r or {}).get("message", "")), r)

        # Borçsuz dükkan pasife alınabiliyor
        st, r = rpc("set_store_status", tokA, p_store_id=ucuncuId, p_aktif=False)
        kontrol("borçsuz dükkan pasife alınabiliyor", st == 200, r)
        st, ses2 = rpc("my_session", tokA)
        kontrol("pasif dükkan oturumda görünmüyor",
                all(x["id"] != ucuncuId for x in ses2["stores"]), ses2["stores"])

        # Kapı 2 · son aktif dükkan
        rpc("set_store_status", tokA, p_store_id=ikinci, p_aktif=False)
        st, r = rpc("set_store_status", tokA, p_store_id=storeA, p_aktif=False)
        kontrol("son aktif dükkan pasife ALINAMIYOR", st >= 400, r)
        kontrol("hata sebebi son dükkan olduğunu söylüyor",
                "Son aktif dükkan" in str((r or {}).get("message", "")), r)

        st, r = rpc("set_store_status", tokA, p_store_id=ikinci, p_aktif=True)
        kontrol("geri açılabiliyor", st == 200, r)
        st, r = rpc("update_store", tokPA, p_store_id=storeA, p_ad="Sızma")
        kontrol("pazarlamacı dükkan adını değiştiremiyor", st >= 400, r)
        st, r = rpc("update_store", tokA, p_store_id=storeA, p_ad="   ")
        kontrol("boş ad reddediliyor", st >= 400, r)

        # ---- Yetki sınırları -------------------------------------------------
        sec("Yetki sınırları")
        st, r = rpc("set_period_status", tokPA, p_period_id=periodA, p_status="kapali")
        kontrol("pazarlamacı dönem kapatamıyor", st >= 400, r)
        st, r = rpc("list_staff", tokB)
        kontrol("B'nin ekip listesinde A'nın kişileri yok",
                all("E2E sahipA" not in (x.get("ad_soyad") or "") for x in (r or [])), r)

        # Pazarlamacı kendine cari atayamaz (asg_write yalnızca sahip/müdür)
        if accId:
            st, r = http("/rest/v1/assignments", "POST", token=tokPA, body={
                "account_id": accId, "store_id": storeA,
                "user_id": uidPA, "period_id": periodA})
            kontrol("pazarlamacı kendine portföy atayamıyor", st >= 400, r)

    finally:
        artik = temizle(uidler)
        kontrol("koşu kendi verisini temizledi", not artik, artik)

    # ── Özet ───────────────────────────────────────────────────────────────
    print(f"\n\033[1m{'─'*54}\033[0m")
    print(f"  geçti: \033[32m{len(gecti)}\033[0m   kaldı: "
          f"\033[{'31' if kaldi else '32'}m{len(kaldi)}\033[0m")
    if kaldi:
        print("\n  Başarısız:")
        for k in kaldi:
            print(f"    · {k}")
    return 1 if kaldi else 0

if __name__ == "__main__":
    sys.exit(main())
