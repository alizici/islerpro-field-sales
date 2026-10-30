#!/usr/bin/env python3
"""Canlı demo veri seti — yeni dükkan, ekip ve TÜM akışlarda gerçek kayıtlar.

    SUPABASE_SERVICE_KEY=... python3 test/demo/demo_veri.py
    ... --sil          demo dükkanı ve ekibini geri alır

Kayıtlar **uygulamanın kendi RPC'leriyle** giriliyor. Doğrudan `insert` yapmak
satırları üretir ama iş kurallarını atlar (K25 iskonto çözümlemesi, K26 borcun
teslimattan doğması, K48 FIFO mahsup, K7…) ve ortaya ürünün gerçekte
üretmeyeceği bir veri çıkar — demo da tam olarak orada yalan söylemeye başlar.

Ürünler işletmeye bağlı (24.630 kalem "İşler Yayınları Kitap"ta), kurum dizini
ortak. Bu yüzden demo AYRI BİR İŞLETME DEĞİL, mevcut işletmede yeni bir
dükkandır: ayrı işletme kursak katalog boş kalırdı.
"""
import json, os, sys, random, datetime as dt
import urllib.request, urllib.error, urllib.parse

KOK = os.path.join(os.path.dirname(__file__), "..", "..")
ENV = {}
for satir in open(os.path.join(KOK, ".env"), encoding="utf-8"):
    if "=" in satir and not satir.strip().startswith("#"):
        k, v = satir.strip().split("=", 1)
        ENV[k] = v
URL, ANON = ENV["SUPABASE_URL"], ENV["SUPABASE_ANON_KEY"]
SERVICE = os.environ.get("SUPABASE_SERVICE_KEY", "")
PAROLA = "Demo-1234-Parola"
ISLETME = "İşler Yayınları Kitap"
DUKKAN = "Karaköprü Şube"

random.seed(20260827)          # aynı komut aynı veriyi üretsin


def http(path, method="GET", token=None, body=None, key=None, prefer=None):
    req = urllib.request.Request(URL + path, method=method)
    req.add_header("apikey", key or ANON)
    req.add_header("Authorization", "Bearer " + (token or key or ANON))
    req.add_header("Content-Type", "application/json")
    if prefer:
        req.add_header("Prefer", prefer)
    veri = json.dumps(body).encode() if body is not None else None
    try:
        with urllib.request.urlopen(req, veri) as r:
            m = r.read().decode()
            return r.status, (json.loads(m) if m.strip() else None)
    except urllib.error.HTTPError as e:
        m = e.read().decode()
        try:
            return e.code, json.loads(m)
        except Exception:
            return e.code, {"raw": m}


def rpc(fn, token=None, **p):
    return http(f"/rest/v1/rpc/{fn}", "POST", token, p)


def zorunlu(ad, st, r, kabul=(200, 201, 204)):
    if st not in kabul:
        print(f"  ✗ {ad}: {st} {json.dumps(r, ensure_ascii=False)[:200]}")
        sys.exit(1)
    return r


def bolum(b):
    print(f"\n\033[1m{b}\033[0m")


def satir(m):
    print(f"  · {m}")


# Mevcut sahip hesabının parolası DEĞİŞTİRİLMİYOR: demo verisi kurmak için
# birinin kimlik bilgilerini ezmek kabul edilebilir bir yan etki değil.
BILINEN_PAROLALAR = [PAROLA, "Test-1234-Parola"]


def giris(eposta):
    for p in BILINEN_PAROLALAR:
        st, r = http("/auth/v1/token?grant_type=password", "POST",
                     body={"email": eposta, "password": p})
        if st == 200:
            return r["access_token"]
    return None


# ── Ekip ────────────────────────────────────────────────────────────────────
EKIP = [
    ("demo-mudur@islerpro.local",       "Selim Doğan",  "dukkan_muduru"),
    ("demo-pazarlamaci1@islerpro.local","Emre Şahin",   "pazarlamaci"),
    ("demo-pazarlamaci2@islerpro.local","Zeynep Aydın", "pazarlamaci"),
    ("demo-hazirlik@islerpro.local",    "Murat Kılıç",  "hazirlik"),
    ("demo-ogretmen@islerpro.local",    "Fatma Öz",     "ogretmen"),
]


def _kullanicilari_getir():
    """Tam liste. `?filter=` bazen eşleşmiyor ve kullanıcı 'yok' sanılıp
    ikinci kez açılmaya çalışılıyordu."""
    hepsi, sayfa = [], 1
    while True:
        st, r = http(f"/auth/v1/admin/users?page={sayfa}&per_page=200",
                     key=SERVICE)
        parca = (r or {}).get("users", [])
        hepsi += parca
        if len(parca) < 200:
            return hepsi
        sayfa += 1


def kullanici_bul_ya_da_ac(eposta, ad):
    mevcut = next((u for u in _kullanicilari_getir()
                   if u["email"] == eposta), None)
    if mevcut:
        return mevcut["id"], False
    st, r = http("/auth/v1/admin/users", "POST", key=SERVICE, body={
        "email": eposta, "password": PAROLA, "email_confirm": True,
        "user_metadata": {"ad_soyad": ad}})
    zorunlu(f"kullanıcı {eposta}", st, r)
    return r["id"], True


def ekibi_kur(tenant_id, store_id, sahip_token):
    bolum("Ekip")
    kisiler = {}
    for eposta, ad, rol in EKIP:
        uid, yeni = kullanici_bul_ya_da_ac(eposta, ad)
        # Profil trigger'la açılıyor; ad_soyad'ı garantiye al.
        http(f"/rest/v1/profiles?id=eq.{uid}", "PATCH", key=SERVICE,
             body={"ad_soyad": ad})
        # Öğretmen işletme üyesi DEĞİLDİR (K3): kuruma bağlanır, aşağıda.
        if rol != "ogretmen":
            st, m = http(f"/rest/v1/memberships?user_id=eq.{uid}"
                         f"&tenant_id=eq.{tenant_id}", key=SERVICE)
            if not m:
                zorunlu(f"üyelik {ad}", *http(
                    "/rest/v1/memberships", "POST", key=SERVICE, body={
                        "user_id": uid, "tenant_id": tenant_id,
                        "store_id": store_id, "role": rol, "status": "aktif"}))
        kisiler[eposta] = uid
        satir(f"{ad:14} {rol:15} {'yeni' if yeni else 'zaten vardı'}")
    return kisiler


# ── Dükkan ve fiyatlar ──────────────────────────────────────────────────────
def dukkani_kur(tenant_id, sahip_token):
    bolum("Dükkan")
    st, r = http(f"/rest/v1/stores?tenant_id=eq.{tenant_id}"
                 f"&ad=eq.{urllib.parse.quote(DUKKAN)}&select=id", key=SERVICE)
    if r:
        satir(f"{DUKKAN} zaten var")
        return r[0]["id"]
    st, r = http("/rest/v1/stores", "POST", key=SERVICE,
                 prefer="return=representation", body={
                     "tenant_id": tenant_id, "ad": DUKKAN,
                     "il": "Şanlıurfa", "ilce": "Karaköprü",
                     "adres": "Atatürk Bulvarı No:118, Karaköprü"})
    zorunlu("dükkan", st, r)
    satir(f"{DUKKAN} açıldı")
    return r[0]["id"]


def fiyatlari_kur(store_id, sahip_token, adet=140):
    bolum("Katalog fiyatları")
    st, mevcut = http(f"/rest/v1/store_products?store_id=eq.{store_id}"
                      "&select=id&limit=1", key=SERVICE)
    if mevcut:
        st, say = http(f"/rest/v1/store_products?store_id=eq.{store_id}"
                       "&select=id", key=SERVICE, prefer="count=exact")
        satir(f"{len(say)} ürün zaten fiyatlı")
        return [x["id"] for x in say]

    # Gerçek katalogdan kitap seç: demo, uydurma ürünle değil GERÇEK adlarla
    # anlamlı olur ("TYT Matematik Soru Bankası" gibi).
    st, urunler = http(
        "/rest/v1/products?select=id,ad,etiket_fiyat,katalog"
        "&arsivlendi=eq.false&merged_into_id=is.null"
        f"&order=created_at.asc&limit={adet * 3}", key=SERVICE)
    zorunlu("ürün listesi", st, urunler)
    secilen = random.sample(urunler, min(adet, len(urunler)))

    govde = []
    for u in secilen:
        etiket = float(u["etiket_fiyat"] or 0) or random.choice(
            [120, 145, 180, 210, 250, 320])
        satis = round(etiket * random.uniform(0.85, 1.0), 2)
        govde.append({
            "store_id": store_id, "product_id": u["id"],
            "alis_fiyat": round(satis * random.uniform(0.52, 0.62), 2),
            "satis_fiyat": satis,
            "varsayilan_iskonto": random.choice([0.20, 0.25, 0.30, 0.35]),
            "stok_adedi": random.choice([0, 0, 12, 40, 90, 150, 260]),
            "stok_takibi": True, "aktif": True})
    st, r = http("/rest/v1/store_products", "POST", key=SERVICE,
                 prefer="return=representation", body=govde)
    zorunlu("fiyatlar", st, r)
    satir(f"{len(r)} ürün fiyatlandı (gerçek katalogdan)")
    return [x["id"] for x in r]


# ── Kurum, kişi, cari ───────────────────────────────────────────────────────
KURUM_SAYISI = 9
GOREVLER = ["Müdür", "Müdür Yardımcısı", "Zümre Başkanı", "Rehber Öğretmen"]
ADLAR = ["Ayşe Yıldız", "Mehmet Aslan", "Hatice Şen", "Ömer Kaya",
         "Elif Demir", "Burak Çetin", "Nurcan Ergün", "İsmail Tunç",
         "Sevgi Alkan", "Kadir Bozkurt", "Melike Yalçın", "Serkan Aksu"]
BRANSLAR = ["Matematik", "Türkçe", "Fen Bilimleri", "Sosyal Bilgiler",
            "İngilizce", "Fizik", "Kimya", "Biyoloji"]


def kurumlari_bagla(store_id, sahip_token):
    bolum("Kurumlar")
    # Dizin ORTAK (K4): yeni kurum uydurmuyoruz, gerçek 755 okuldan seçiyoruz.
    st, hepsi = http(
        "/rest/v1/institutions?select=id,ad,ilce,kademe,kurum_tipi,ogrenci_sayisi"
        "&dogrulandi=eq.true&il=ilike.*urfa*&merged_into_id=is.null"
        "&order=ad.asc&limit=400", key=SERVICE)
    zorunlu("kurum dizini", st, hepsi)
    # Kademesi belli, orta/lise ağırlıklı bir demet: deneme ve kitap satışı
    # oradan çıkıyor.
    uygun = [k for k in hepsi if k.get("kademe") in ("ortaokul", "lise")]
    secilen = random.sample(uygun, min(KURUM_SAYISI, len(uygun)))
    for k in secilen:
        rpc("link_institution", sahip_token,
            p_institution_id=k["id"], p_store_id=store_id, p_bagla=True)
    satir(f"{len(secilen)} kurum dükkana bağlandı (gerçek dizinden)")
    return secilen


def kisileri_ac(kurumlar, tenant_id):
    kisiler = {}
    for k in kurumlar:
        adet = random.randint(2, 3)
        govde = []
        for i in range(adet):
            govde.append({
                "tenant_id": tenant_id, "institution_id": k["id"],
                "ad_soyad": random.choice(ADLAR),
                "gorev": GOREVLER[i] if i < len(GOREVLER) else "Öğretmen",
                "brans": random.choice(BRANSLAR),
                "telefon": f"05{random.randint(300000000, 559999999)}",
                "aktif": True})
        st, r = http("/rest/v1/institution_contacts", "POST", key=SERVICE,
                     prefer="return=representation", body=govde)
        zorunlu("kişi", st, r)
        kisiler[k["id"]] = r
    satir(f"{sum(len(v) for v in kisiler.values())} kurum yetkilisi eklendi")
    return kisiler


def carileri_ac(store_id, kurumlar, kisiler, sahip_token, ogretmen_uid,
                tenant_id):
    bolum("Cariler")
    cariler = []
    # Uygulamaya giren öğretmenin carisi KENDİ ADINA açılır. Rastgele bir
    # yetkilinin carisine bağlamak, ekranda "başkasının carisi bende
    # görünüyor" gibi duruyor.
    st, kendi = http("/rest/v1/institution_contacts", "POST", key=SERVICE,
                     prefer="return=representation", body=[{
                         "tenant_id": tenant_id,
                         "institution_id": kurumlar[0]["id"],
                         "ad_soyad": "Fatma Öz", "gorev": "Zümre Başkanı",
                         "brans": "Matematik",
                         "telefon": "05321112233", "aktif": True}])
    zorunlu("öğretmen kişisi", st, kendi, kabul=(200, 201))
    st, r = rpc("create_account", sahip_token, p_store_id=store_id,
                p_institution_id=kurumlar[0]["id"], p_tip="ogretmen",
                p_unvan="Fatma Öz (Matematik)",
                p_contact_id=kendi[0]["id"], p_user_id=ogretmen_uid,
                p_credit_limit=5000)
    zorunlu("öğretmen carisi", st, r)
    cariler.append({"id": r["id"], "tip": "ogretmen", "kurum": kurumlar[0],
                    "unvan": "Fatma Öz"})

    for i, k in enumerate(kurumlar):
        # K5 · Muhatap caridir. Kurumsal cari her kurumda var.
        st, r = rpc("create_account", sahip_token,
                    p_store_id=store_id, p_institution_id=k["id"],
                    p_tip="kurum", p_unvan=f"{k['ad']} Kurumsal",
                    p_discount_tier=random.choice(["standart", "okul", None]),
                    p_credit_limit=random.choice([0, 25000, 50000, 75000]))
        zorunlu(f"cari {k['ad']}", st, r)
        cariler.append({"id": r["id"], "tip": "kurum", "kurum": k,
                        "unvan": f"{k['ad']} Kurumsal"})

        # K7 · Öğretmen carisi AYRI bir hesaptır; kuruma ROLL-UP YAPILMAZ.
        for kisi in kisiler[k["id"]][:random.randint(0, 2)]:
            st, r = rpc("create_account", sahip_token,
                        p_store_id=store_id, p_institution_id=k["id"],
                        p_tip="ogretmen",
                        p_unvan=f"{kisi['ad_soyad']} ({kisi['brans']})",
                        p_contact_id=kisi["id"],
                        # Diğer öğretmen carileri UYGULAMAYA BAĞLI DEĞİL
                        # (K5: uygulama hesabı olmadan da cari açılır).
                        p_credit_limit=random.choice([0, 5000, 10000]))
            if st == 200:
                cariler.append({"id": r["id"], "tip": "ogretmen",
                                "kurum": k, "unvan": kisi["ad_soyad"]})
    satir(f"{sum(1 for c in cariler if c['tip']=='kurum')} kurumsal + "
          f"{sum(1 for c in cariler if c['tip']=='ogretmen')} öğretmen carisi")
    return cariler


def portfoy_dagit(cariler, kisiler_map, period_id, sahip_token):
    bolum("Portföy")
    p1 = kisiler_map["demo-pazarlamaci1@islerpro.local"]
    p2 = kisiler_map["demo-pazarlamaci2@islerpro.local"]
    idler = [c["id"] for c in cariler]
    # Son beşte bir ATANMAMIŞ bırakılıyor: "atanmamış cari" süzgeci ve portföy
    # boşluğu raporu boş liste üzerinde denenemez.
    atanacak = len(idler) * 4 // 5
    yari = atanacak // 2
    zorunlu("atama 1", *rpc("assign_accounts", sahip_token,
            p_account_ids=idler[:yari], p_user_id=p1, p_period_id=period_id))
    zorunlu("atama 2", *rpc("assign_accounts", sahip_token,
            p_account_ids=idler[yari:atanacak], p_user_id=p2,
            p_period_id=period_id))
    satir(f"{atanacak} cari iki pazarlamacıya dağıtıldı, "
          f"{len(idler) - atanacak} tanesi ATANMAMIŞ bırakıldı")
    return {"demo-pazarlamaci1@islerpro.local": idler[:yari],
            "demo-pazarlamaci2@islerpro.local": idler[yari:atanacak]}


# ── Ticari akış ─────────────────────────────────────────────────────────────
# (ad, sınav tipi, tür, kademe, düzey) — tür K20 için önemli: Türkiye Geneli
# yalnızca takvime bağlı programda olabilir, tarihi ulusaldır.
DENEMELER = [
    ("TYT Deneme Sınavı - 1", "TYT", "takvim", "lise", "TYT"),
    ("TYT Deneme Sınavı - 2", "TYT", "takvim", "lise", "TYT"),
    ("TYT Türkiye Geneli - Kasım", "TYT", "turkiye_geneli", "lise", "TYT"),
    ("AYT Sayısal Deneme - 1", "AYT", "takvim", "lise", "AYT"),
    ("AYT Eşit Ağırlık Deneme - 1", "AYT", "takvim", "lise", "AYT"),
    ("LGS Deneme Sınavı - 1", "LGS", "takvim", "ortaokul", "8. SINIF"),
    ("LGS Deneme Sınavı - 2", "LGS", "takvim", "ortaokul", "8. SINIF"),
    ("LGS Türkiye Geneli - Aralık", "LGS", "turkiye_geneli", "ortaokul",
     "8. SINIF"),
]


def denemeleri_ac(store_id, sahip_token):
    """K15 · Deneme ayrı tablo değil, katalogda `katalog='deneme'`.

    Gerçek katalogda (24.630 kalem) deneme YOK — henüz aktarılmadı. Demo
    denemesiz kalırsa Faz 9'un tamamı (takvim, program, K47 ayrımı)
    denenemez, o yüzden burada açılıyor.
    """
    bolum("Denemeler (K15)")
    st, mevcut = rpc("search_products", sahip_token, p_store_id=store_id,
                     p_katalog="deneme", p_fiyat_durumu="fiyatli", p_limit=5)
    if mevcut:
        satir(f"{len(mevcut)} fiyatlı deneme zaten var")
        return
    acilan = 0
    bugun = dt.date.today()
    for i, (ad, sinav, tur, kademe, duzey) in enumerate(DENEMELER):
        st, r = rpc("add_product", sahip_token, p_store_id=store_id, p_ad=ad,
                    p_katalog="deneme", p_yayinevi="İşler Yayınları",
                    p_sinav_tipi=sinav, p_etiket_fiyat=25,
                    p_kategori="Deneme")
        if st != 200 or not r:
            continue
        pid = r["id"] if isinstance(r, dict) else r
        rpc("upsert_store_product", sahip_token, p_store_id=store_id,
            p_product_id=pid, p_satis_fiyat=random.choice([18, 20, 22, 25]),
            p_alis_fiyat=11, p_varsayilan_iskonto=0.10, p_stok_takibi=False,
            p_aktif=True)
        # K20 · Deneme TAKVİMİ bir veri kümesidir: `deneme_details` olmadan
        # ürün "deneme kataloğunda" sayılmıyor ve programa kalem eklenemiyor.
        # Takvim ekranı da bu tablodan besleniyor — demoda ikisi birden lazım.
        stok = bugun + dt.timedelta(days=(i - 3) * 12)
        http("/rest/v1/deneme_details", "POST", key=SERVICE, body={
            "product_id": pid, "deneme_turu": tur, "kademe": kademe,
            "duzey": duzey, "kapsam": "genel",
            "stok_tarihi": str(stok),
            "uygulama_baslangic": str(stok + dt.timedelta(days=5)),
            "uygulama_bitis": str(stok + dt.timedelta(days=8)),
            "uygulama_metin": None})
        acilan += 1
    satir(f"{acilan} deneme açıldı, fiyatlandı ve TAKVİME işlendi "
          "(ikisi Türkiye Geneli)")


def baski_gruplari(store_id, sahip_token):
    """K23 · Baskı ilişkisi ELLE kurulur; addan ya da tarihten türetilmez.

    Eski baskı stoğu raporunun varlık sebebi karşılaştırma: "elde 2024-25'ten
    40 adet var, oysa 2025-26 çıkmış". Baskı grubu olmadan o rapor hep boş
    kalır ve K23'ün iskonto kararı denenemez.
    """
    bolum("Baskı grupları (K23)")
    st, urunler = rpc("search_products", sahip_token, p_store_id=store_id,
                      p_fiyat_durumu="fiyatli", p_limit=40)
    stoklu = [u for u in (urunler or []) if (u.get("stok_adedi") or 0) > 0][:3]
    kurulan = 0
    for u in stoklu:
        # Eski baskı ELDE KALIYOR (arşivlenmiyor): raporun göstereceği şey tam
        # olarak "yeni çıktı ama eskisi hâlâ depoda" durumudur.
        st, r = rpc("add_edition", sahip_token, p_store_id=store_id,
                    p_kaynak_product_id=u["id"], p_baski_etiketi="2026-27",
                    p_etiket_fiyat=round(float(u.get("satis_fiyat") or 200) * 1.15, 2),
                    p_eski_arsivle=False)
        if st == 200:
            kurulan += 1
    satir(f"{kurulan} üründe yeni baskı açıldı, eskisi depoda bırakıldı")


def urun_havuzu(store_id, sahip_token, adet=40):
    st, r = rpc("search_products", sahip_token, p_store_id=store_id,
                p_fiyat_durumu="fiyatli", p_limit=adet)
    zorunlu("ürün havuzu", st, r)
    return r


def talepler(cariler, urunler, tokenlar, portfoy):
    """K36 · K37 · Talep akışı — DÖRT durumu da bırakıyoruz.

    Yalnızca "karara bağlanmış" talep üretmek gelen kutusunu boş gösterir ve
    ekranın asıl işi (bekleyeni ayıklamak) denenemez.
    """
    bolum("Talepler (K36 · K37)")
    sahip = tokenlar["sahip"]
    sonuc = {"bekleyen": [], "karara_baglanan": [], "kismi": [], "iptal": [],
             "sahibi": {}}          # talep id → onu açan pazarlamacının jetonu

    # Talebi, cariyi GÖREBİLEN pazarlamacı açar. Sahip adına açmak kolaydı ama
    # o zaman "talebi kim açtı" alanı demoda hep aynı kişiyi gösterirdi ve
    # portföy/RLS davranışı hiç denenmemiş olurdu.
    isler = []
    for tur in range(2):          # iki tur: geçmiş + güncel hareket
        for eposta, idler in portfoy.items():
            for cid in idler:
                isler.append((cid, tokenlar[eposta]))
    random.shuffle(isler)

    for i, (cid, tok) in enumerate(isler):
        kalemler = [{"product_id": u["id"], "adet": random.choice([5, 10, 20, 30])}
                    for u in random.sample(urunler, random.randint(2, 4))]
        st, r = rpc("create_request", tok, p_account_id=cid,
                    p_items=kalemler, p_gonder=True,
                    p_not_metni=random.choice([
                        None, "Dönem başı ihtiyaç listesi",
                        "Zümre toplantısında karar alındı",
                        "Acil — kayıt haftasına yetişmeli"]))
        if st != 200:
            continue
        tid = r["id"]
        st, d = rpc("request_detail", sahip, p_request_id=tid)
        if st != 200 or not d:
            continue
        items = d.get("kalemler", [])

        sonuc["sahibi"][tid] = tok
        if i % 4 == 0:                      # bekliyor — gelen kutusu dolsun
            sonuc["bekleyen"].append(tid)
            continue
        if i % 4 == 1:                      # tamamı onay
            kararlar = [{"item_id": k["id"], "durum": "onaylandi"} for k in items]
            rpc("decide_request_items", sahip, p_request_id=tid,
                p_kararlar=kararlar)
            sonuc["karara_baglanan"].append(tid)
        elif i % 4 == 2:                    # K37 · KISMİ karar
            kararlar = []
            for j, k in enumerate(items):
                kararlar.append({"item_id": k["id"],
                                 "durum": "onaylandi" if j == 0 else "reddedildi",
                                 "red_nedeni": None if j == 0 else "Stokta yok"})
            rpc("decide_request_items", sahip, p_request_id=tid,
                p_kararlar=kararlar)
            sonuc["kismi"].append(tid)
        else:                               # iptal
            rpc("cancel_request", sahip, p_request_id=tid,
                p_gerekce="Kurum vazgeçti")
            sonuc["iptal"].append(tid)

    satir(f"{len(sonuc['bekleyen'])} bekliyor · "
          f"{len(sonuc['karara_baglanan'])} onaylandı · "
          f"{len(sonuc['kismi'])} kısmi (K37) · {len(sonuc['iptal'])} iptal")
    return sonuc


def siparisler(talep_sonuc, tokenlar):
    bolum("Siparişler (K46)")
    sahip = tokenlar["sahip"]
    hazirlik = tokenlar["demo-hazirlik@islerpro.local"]
    # Bir kısmı DAR TAVANLI pazarlamacı adına açılıyor: iskonto tavanını aşan
    # sipariş onaya düşer (K25) ve "onay bekleyen" kutusu boş kalmaz. Hepsini
    # sahip adına açmak tavanı hiç zorlamıyordu.
    olusan, onayli = [], 0
    hepsi = talep_sonuc["karara_baglanan"] + talep_sonuc["kismi"]
    for tid in hepsi:
        # Siparişi, talebi AÇAN pazarlamacı açar. Zeynep Aydın'ın iskonto
        # tavanı dar (%10), bu yüzden onun portföyündeki siparişler onaya
        # düşüyor — K25'in onay yolu ancak böyle denenebiliyor.
        tok = talep_sonuc["sahibi"].get(tid, sahip)
        st, r = rpc("create_order_from_request", tok, p_request_id=tid)
        if st != 200 or not r:
            st, r = rpc("create_order_from_request", sahip, p_request_id=tid)
        if st == 200 and r:
            olusan.append(r["id"])
            if r.get("onay_gerekce"):
                onayli += 1
    # K25 · Onaya düşen siparişin bir kısmı ONAYLANIR (sahip), bir kısmı
    # REDDEDİLİR, bir kısmı beklemede kalır. Hepsini onaylamak "onay bekleyen"
    # kutusunu boşaltıyor; hiçbirini onaylamamak da hazırlık akışını
    # başlatmıyor — ikisi de demoyu yarım bırakıyor.
    st, liste = rpc("list_orders", sahip, p_store_id=STORE_ID, p_limit=100)
    bekleyen = [o["id"] for o in (liste or [])
                if o.get("durum") == "onay_bekliyor"]
    onaylanan = reddedilen = 0
    for i, oid in enumerate(bekleyen):
        if i % 3 == 2:
            continue                                   # onayda beklesin
        durum = "reddedildi" if i % 3 == 1 else "olusturuldu"
        st, _ = rpc("set_order_status", sahip, p_order_id=oid, p_durum=durum,
                    p_gerekce="İskonto tavanı aşıldı — sahip kararı")
        if st == 200:
            if durum == "reddedildi":
                reddedilen += 1
            else:
                onaylanan += 1

    # Hazırlık akışının ÜÇ durağı da temsil edilsin: kutuda bekleyen,
    # hazırlanan, hazır olan.
    st, liste = rpc("list_orders", sahip, p_store_id=STORE_ID, p_limit=100)
    hazirlanabilir = [o["id"] for o in (liste or [])
                      if o.get("durum") == "olusturuldu"]
    for i, oid in enumerate(hazirlanabilir):
        if i % 3 == 0:
            continue                                   # kutuda bekliyor
        rpc("set_order_status", hazirlik, p_order_id=oid,
            p_durum="hazirlaniyor")
        if i % 3 == 1:
            rpc("set_order_status", hazirlik, p_order_id=oid, p_durum="hazir")
    satir(f"{len(olusan)} sipariş · {onayli} tanesi ONAYA düştü (K25 tavan) "
          f"→ {onaylanan} onaylandı, {reddedilen} reddedildi, kalanı beklemede")
    satir("hazırlık: bir kısmı kutuda, bir kısmı hazırlanıyor, bir kısmı hazır")
    return olusan


def teslimatlar(siparis_idler, cariler, urunler, tokenlar):
    """K26 · BORÇ BURADA DOĞAR. C-1 · tip ile borclandirir bağımsızdır."""
    bolum("Teslimatlar (K26 · C-1)")
    p1 = tokenlar["demo-pazarlamaci1@islerpro.local"]
    sahip = tokenlar["sahip"]
    tam = kismi = 0
    for i, oid in enumerate(siparis_idler):
        st, d = rpc("order_detail", sahip, p_order_id=oid)
        if st != 200 or not d:
            continue
        kalemler = [k for k in d.get("kalemler", []) if (k.get("backorder") or 0) > 0]
        if not kalemler:
            continue
        # Her siparişe teslimat girilmiyor: bir kısmı hazırlık kutusunda
        # KALMALI, yoksa K46'nın kutusu boş görünüyor.
        if i % 4 == 3:
            continue
        if i % 3 == 2:
            # H-3 · KISMİ teslim: kalanı backorder olarak kendiliğinden türer.
            gonder = [{"order_item_id": kalemler[0]["id"],
                       "adet": max(1, kalemler[0]["backorder"] // 2)}]
            kismi += 1
        else:
            gonder = [{"order_item_id": k["id"], "adet": k["backorder"]}
                      for k in kalemler]
            tam += 1
        rpc("create_shipment", p1, p_account_id=d["cari"]["id"], p_order_id=oid,
            p_items=gonder, p_borclandirir=True, p_tip="teslimat",
            p_teslim_alan_ad=random.choice(ADLAR), p_kaynak="depo")

    # C-1 · Konsinye bırakma: fiziksel hareket VAR, borç YOK.
    konsinye = []
    # Cariyi GÖREBİLEN pazarlamacıyla bırakılıyor: rastgele cari seçmek
    # RLS'e takılıyor ve konsinye sessizce hiç oluşmuyordu.
    st, gorunen = rpc("search_accounts", p1, p_store_id=STORE_ID,
                      p_tip="kurum", p_limit=20)
    for c in random.sample(gorunen or [], min(3, len(gorunen or []))):
        kalem = [{"product_id": u["id"], "adet": random.choice([20, 40, 60])}
                 for u in random.sample(urunler, 2)]
        st, r = rpc("create_shipment", p1, p_account_id=c["id"],
                    p_items=kalem, p_borclandirir=False, p_tip="teslimat",
                    p_teslim_alan_ad=random.choice(ADLAR), p_kaynak="elden")
        if st == 200:
            konsinye.append(c)
    satir(f"{tam} tam · {kismi} kısmi (backorder türedi) · "
          f"{len(konsinye)} konsinye bırakma (borç doğurmadı)")
    return konsinye


def tahsilatlar(cariler, tokenlar):
    """K48 · Kısmi tahsilat, FIFO mahsup. K11 · Çek ödeme değil VAATTİR."""
    bolum("Tahsilat ve çek (K48 · K11)")
    p1 = tokenlar["demo-pazarlamaci1@islerpro.local"]
    sahip = tokenlar["sahip"]
    nakit = havale = cek = 0
    bugun = dt.date.today()

    st, liste = rpc("search_accounts", sahip, p_store_id=STORE_ID,
                    p_borclu=True, p_limit=50)
    liste = [c for c in (liste or []) if float(c.get("bakiye") or 0) > 0]
    # Beşte biri BİLEREK ödenmemiş kalıyor: yaşlandırma, borçlu cariler ve
    # gecikme raporları boş liste üzerinde denenemez.
    odenecek = liste[:max(1, len(liste) * 4 // 5)]
    for i, c in enumerate(odenecek):
        bakiye = float(c.get("bakiye") or 0)
        if i % 3 == 0:
            # K48 · Borcun TAMAMI değil bir kısmı: kısmi mahsup görünsün.
            rpc("create_payment", p1, p_account_id=c["id"],
                p_tutar=round(bakiye * 0.4, 2), p_yontem="nakit",
                p_tarih=str(bugun - dt.timedelta(days=random.randint(1, 20))))
            nakit += 1
        elif i % 3 == 1:
            rpc("create_payment", p1, p_account_id=c["id"],
                p_tutar=round(bakiye, 2), p_yontem="havale",
                p_tarih=str(bugun - dt.timedelta(days=random.randint(1, 10))))
            havale += 1
        else:
            # K11 · Çek alındığında bakiye DÜŞMEZ; vadesi gelmemiş çek riski
            # artırır. Vadeler bilerek dağıtıldı: biri geçmiş, biri yakın.
            vade = bugun + dt.timedelta(days=random.choice([-12, 4, 25, 70]))
            rpc("create_payment", p1, p_account_id=c["id"],
                p_tutar=round(bakiye * 0.8, 2), p_yontem="cek",
                p_cek_vade=str(vade),
                p_cek_banka=random.choice(["Ziraat", "Vakıfbank", "İş Bankası",
                                           "Halkbank", "Garanti"]),
                p_cek_no=f"{random.randint(100000, 999999)}")
            cek += 1
    satir(f"{nakit} kısmi nakit · {havale} havale · {cek} çek "
          "(vadeleri geçmiş/yakın/uzak)")


def cek_yasam_dongusu(tokenlar):
    """K11 · Çek bir VAAT: karşılığı alınınca bakiye ŞİMDİ düşer."""
    sahip = tokenlar["sahip"]
    st, takvim = rpc("cheque_calendar", sahip, p_store_id=STORE_ID)
    # Takvim GÜN GÜN geliyor; çekler günlerin içinde. Düz liste beklemek
    # sessizce boş küme veriyordu — yani "hiç çek yok" diye görünüyordu.
    cekler = [c for g in (takvim or {}).get("gunler", [])
              for c in g.get("cekler", [])]
    tahsil = karsiliksiz = 0
    for i, c in enumerate(cekler):
        if c.get("durum") != "portfoyde":
            continue
        if i % 4 == 0:
            rpc("set_cheque_status", sahip, p_cheque_id=c["id"],
                p_durum="tahsil_edildi")
            tahsil += 1
        elif i % 4 == 1:
            rpc("set_cheque_status", sahip, p_cheque_id=c["id"],
                p_durum="karsiliksiz", p_gerekce="Bankadan karşılıksız döndü")
            karsiliksiz += 1
        elif i % 4 == 2:
            rpc("set_cheque_status", sahip, p_cheque_id=c["id"],
                p_durum="tahsilde")
    satir(f"çek: {tahsil} tahsil edildi (bakiye düştü) · "
          f"{karsiliksiz} karşılıksız · kalanı portföyde")


def iade_ve_konsinye(konsinye_cariler, tokenlar):
    """K45 · Konsinye defterinin YOKTUR: kalan türetilir."""
    bolum("İade ve konsinye kapatma (K45 · Y-13)")
    sahip = tokenlar["sahip"]
    p1 = tokenlar["demo-pazarlamaci1@islerpro.local"]
    iade = kapanan = 0

    st, liste = rpc("consignment_report", sahip, p_store_id=STORE_ID)
    acik = (liste or []) if isinstance(liste, list) else []
    for c in acik[:3]:
        st, kalemler = rpc("open_consignment_detail", sahip,
                           p_account_id=c["id"])
        kalemler = kalemler or []
        if not kalemler:
            continue
        k = kalemler[0]
        kalan = int(k.get("kalan") or 0)
        if kalan < 4:
            continue
        # Bir kısmı SATILDI (borç doğar), bir kısmı İADE (borç doğmaz) —
        # ikisi tek çağrıda, çünkü sahada tek konuşmadır.
        rpc("settle_consignment", p1, p_account_id=c["id"],
            p_satilan=[{"product_id": k["product_id"], "adet": kalan // 2}],
            p_iade=[{"product_id": k["product_id"], "adet": kalan // 4}],
            p_gerekce="Dönem sonu sayım")
        kapanan += 1

    # Normal teslimattan iade: bakiyeyi AZALTIR.
    st, cariler = rpc("search_accounts", sahip, p_store_id=STORE_ID,
                      p_borclu=True, p_limit=10)
    for c in (cariler or [])[:3]:
        st, kalemler = rpc("returnable_items", sahip, p_account_id=c["id"])
        kalemler = [k for k in (kalemler or []) if int(k.get("kalan") or 0) >= 2]
        if not kalemler:
            continue
        k = kalemler[0]
        st, _ = rpc("create_return", p1, p_account_id=c["id"],
                    p_items=[{"product_id": k["product_id"],
                              "adet": max(1, int(k["kalan"]) // 3)}],
                    p_bakiyeyi_azaltir=True, p_gerekce="Hatalı baskı")
        if st == 200:
            iade += 1
    satir(f"{kapanan} konsinye kapatıldı (satış + iade) · {iade} iade kaydı")


def ziyaretler(kurumlar, tokenlar, urunler):
    """K10 · Ziyaretin ölçütü konum değil ÇIKTIDIR.

    Bu yüzden ziyaretler BOŞ AÇILIP KAPANMIYOR: Y-18 damgası yalnızca ziyaret
    AÇIKKEN yazılan kayıtlara vuruluyor. Önce hepsini açıp kapatan bir demo,
    ziyaret verimliliği raporunu "6 ziyaret, 6'sı çıktısız" diye gösteriyordu —
    yani modülün asıl ölçütünü hiç denemiyordu.
    """
    bolum("Ziyaret ve rota (K10 · Y-18)")
    p1 = tokenlar["demo-pazarlamaci1@islerpro.local"]
    sahip = tokenlar["sahip"]
    bugun = dt.date.today()
    acilan = planlanan = ciktili = 0

    st, gorunen = rpc("search_accounts", p1, p_store_id=STORE_ID, p_limit=30)
    kurum_cari = {}
    for c in (gorunen or []):
        kurum_cari.setdefault(c["institution_id"], []).append(c)

    for i, k in enumerate(kurumlar[:6]):
        giris = dt.datetime.now() - dt.timedelta(days=i + 1,
                                                 hours=random.randint(1, 6))
        st, r = rpc("start_visit", p1, p_institution_id=k["id"],
                    p_checked_in_at=giris.isoformat())
        if st != 200 or not r:
            continue
        vid = r["id"] if isinstance(r, dict) else r

        # Ziyaret AÇIKKEN iş yap: talep ve tahsilat ziyarete damgalanır (Y-18).
        muhataplar = kurum_cari.get(k["id"], [])
        if muhataplar and i % 3 != 2:      # üçte biri bilerek ÇIKTISIZ kalsın
            c = muhataplar[0]
            rpc("create_request", p1, p_account_id=c["id"],
                p_items=[{"product_id": u["id"], "adet": 10}
                         for u in random.sample(urunler, 2)],
                p_gonder=True, p_not_metni="Ziyarette alındı")
            bakiye = float(c.get("bakiye") or 0)
            if bakiye > 0:
                rpc("create_payment", p1, p_account_id=c["id"],
                    p_tutar=round(min(bakiye, 500), 2), p_yontem="nakit")
            ciktili += 1

        cikis = giris + dt.timedelta(minutes=random.randint(18, 65))
        rpc("end_visit", p1, p_visit_id=vid,
            p_not_metni=random.choice([
                "Zümre başkanıyla görüşüldü, deneme talebi alındı",
                "Müdür yoktu, yardımcısıyla konuşuldu",
                "Numune bırakıldı", None]),
            p_sonuc=random.choice(["olumlu", "takip", "olumsuz"]),
            p_checked_out_at=cikis.isoformat())
        acilan += 1

    # Rota: önümüzdeki günlere duraklar
    for k in kurumlar[3:8]:
        st, _ = rpc("plan_visit", p1, p_institution_id=k["id"],
                    p_tarih=str(bugun + dt.timedelta(days=random.randint(0, 4))),
                    p_amac=random.choice(["Tahsilat", "Deneme sunumu",
                                          "Yeni dönem görüşmesi"]))
        if st == 200:
            planlanan += 1
    satir(f"{acilan} kapanmış ziyaret ({ciktili} tanesi çıktılı, kalanı "
          f"K10'un ölçüsü görünsün diye ÇIKTISIZ) · {planlanan} rota durağı")


def deneme_programi(cariler, tokenlar, store_id):
    """C-3 · Plan borç doğurmaz. K47 · teslim ile uygulanan AYRI."""
    bolum("Deneme programı (C-3 · K47)")
    sahip = tokenlar["sahip"]
    p1 = tokenlar["demo-pazarlamaci1@islerpro.local"]
    st, denemeler = rpc("search_products", sahip, p_store_id=store_id,
                        p_katalog="deneme", p_fiyat_durumu="fiyatli", p_limit=12)
    denemeler = denemeler or []
    if not denemeler:
        satir("katalogda fiyatlı deneme yok — program kurulmadı (K12)")
        return
    # Modlar RASTGELE DEĞİL: Y-8'in iki modu da temsil edilmeli. Rastgele
    # seçimde bir koşuda üçü birden aynı moda düşüyor ve diğer mod hiç
    # denenemiyordu.
    kurulan = 0
    modlar = ["takvim_bagli", "takvim_bagli", "serbest_periyot"]
    for c, modu in zip([x for x in cariler if x["tip"] == "kurum"][:3], modlar):
        st, r = rpc("create_exam_program", sahip, p_account_id=c["id"],
                    p_modu=modu,
                    p_ogrenci_sayisi=random.choice([120, 180, 240, 300]),
                    p_deneme_adedi=random.choice([8, 10, 12]),
                    p_periyot_gun=14,
                    p_birim_fiyat=random.choice([18, 22, 25]))
        if st != 200 or not r:
            continue
        pid = r["id"] if isinstance(r, dict) else r
        # K20 · Türkiye Geneli yalnızca TAKVİME BAĞLI programda olabilir:
        # tarihi ulusaldır, program periyodu onu kaydıramaz. Sunucu bunu
        # reddediyor — demo da kuralı bilmeli, yoksa plan kalemleri sessizce
        # boş kalıyor.
        havuz = [d for d in denemeler
                 if modu == "takvim_bagli" or "Türkiye Geneli" not in d["ad"]]
        kalemler = [{"product_id": d["id"], "adet": 150}
                    for d in random.sample(havuz, min(4, len(havuz)))]
        rpc("plan_exam_deliveries", p1, p_program_id=pid, p_items=kalemler,
            p_baslangic=str(dt.date.today() - dt.timedelta(days=21)))
        st, det = rpc("exam_program_detail", sahip, p_program_id=pid)
        plan = (det or {}).get("kalemler", []) if isinstance(det, dict) else []
        for j, k in enumerate(plan):
            if j == 0:
                # K47 · Teslimat kaydı üretilir; plan elle işaretlenmez.
                rpc("deliver_exam", p1, p_delivery_id=k["id"], p_adet=150,
                    p_teslim_alan_ad=random.choice(ADLAR))
            elif j == 1:
                rpc("deliver_exam", p1, p_delivery_id=k["id"], p_adet=150,
                    p_teslim_alan_ad=random.choice(ADLAR))
                rpc("set_exam_delivery_status", p1, p_delivery_id=k["id"],
                    p_durum="uygulandi")
            elif j == 2:
                rpc("set_exam_delivery_status", p1, p_delivery_id=k["id"],
                    p_durum="ertelendi", p_not="Okul sınav haftası",
                    p_yeni_tarih=str(dt.date.today() + dt.timedelta(days=10)))
        kurulan += 1
    satir(f"{kurulan} program · teslim edilen, uygulanan ve ertelenen kalemler "
          "ayrı ayrı bırakıldı (K47)")


def kayitli_rapor(tokenlar, store_id):
    bolum("Kayıtlı raporlar (K50)")
    sahip = tokenlar["sahip"]
    for ad, kod, kirilim, paylasim in [
        ("Aylık ciro — pazarlamacı", "ciro", ["pazarlamaci"], "dukkan"),
        ("Yaşlandırma — cari bazlı", "yaslandirma", ["cari"], "dukkan"),
        ("Yayınevi kârlılığı", "karlilik", ["yayinevi"], "kisisel"),
    ]:
        rpc("save_report", sahip, p_ad=ad, p_kod=kod, p_store_id=store_id,
            p_kirilim=kirilim, p_filtreler={}, p_paylasim=paylasim)
    satir("3 kayıtlı rapor (ikisi dükkanla paylaşımlı)")


# ── Kenar durumlar ──────────────────────────────────────────────────────────
#
# İlk sürüm "her akıştan bir kayıt" bırakıyordu ve tüm ekranlar dolu
# görünüyordu. Ama yaşlandırma raporunun DÖRT kovasının üçü boştu, hiçbir cari
# limitini aşmıyordu, hiçbir talep gecikmemişti. Yani ekranlar açılıyordu ama
# ASIL İŞLERİNİ (eksiği, riski, gecikeni ayıklamak) yapıp yapmadıkları
# görünmüyordu. Buradaki kayıtlar tam olarak bunun içindir.


def iskonto_kurallari(store_id, kisiler_map, sahip_token):
    """K25 · İskonto çözümleme sırası: kural → kademe → elle → TAVAN."""
    bolum("İskonto kuralları ve tavan (K25)")
    st, yayin = rpc("list_publishers", sahip_token, p_store_id=store_id)
    yayin = (yayin or [])[:2]
    # PostgREST toplu eklemede TÜM satırların aynı anahtarları taşımasını
    # şart koşuyor ("All object keys must match"). Eksik anahtar bırakmak
    # 400 veriyordu ve hata kontrol edilmediği için kurallar SESSİZCE hiç
    # yazılmıyordu — demo "kuruldu" diyor, iskonto kuralı yok.
    def kural(tip=None, yayinevi=None, min_adet=1, oran=0.20, oncelik=100):
        return {"store_id": store_id, "account_tip": tip,
                "publisher_id": yayinevi, "product_id": None,
                "min_adet": min_adet, "iskonto_orani": oran,
                "oncelik": oncelik}

    kurallar = [
        # K25 · Küçük öncelik önce bakılır: toplu alım her şeyi ezer.
        kural(min_adet=200, oran=0.40, oncelik=5),
        kural(tip="kurum", min_adet=50, oran=0.35, oncelik=10),
        kural(tip="ogretmen", min_adet=1, oran=0.15, oncelik=20),
    ] + [kural(yayinevi=y["id"], min_adet=20, oran=0.30, oncelik=30)
         for y in yayin]
    st, r = http("/rest/v1/discount_rules", "POST", key=SERVICE,
                 prefer="return=representation", body=kurallar)
    zorunlu("iskonto kuralları", st, r, kabul=(200, 201))

    # Tavan: dükkan geneli %40, bir pazarlamacıya daha DAR tavan. Tavanı aşan
    # sipariş onaya düşer — o yolun denenmesi için farklı tavanlar şart.
    st, r = http("/rest/v1/discount_caps", "POST", key=SERVICE,
                 prefer="return=representation", body=[
        {"store_id": store_id, "user_id": None, "tavan": 0.40},
        {"store_id": store_id,
         "user_id": kisiler_map["demo-pazarlamaci2@islerpro.local"],
         # Bilerek DAR: katalogdaki varsayılan iskontoların altında kalıyor,
         # böylece onun açtığı siparişler onaya düşüyor ve K25'in onay yolu
         # demoda gerçekten var oluyor.
         "tavan": 0.10},
    ])
    zorunlu("iskonto tavanı", st, r, kabul=(200, 201))
    satir(f"{len(kurallar)} iskonto kuralı · dükkan tavanı %40, "
          "Zeynep Aydın'ınki %10 (onaya düşme yolu denenebilsin)")


def numune_limiti(store_id, period_id, kisiler_map, tokenlar, urunler, cariler):
    """K38 · Numune bedelsizdir ama SINIRSIZ değildir."""
    bolum("Numune (K38)")
    st, r = http("/rest/v1/sample_limits", "POST", key=SERVICE,
                 prefer="return=representation", body=[
        {"store_id": store_id, "user_id": None, "period_id": period_id,
         "limit_adet": 200, "limit_tutar": 15000},
        {"store_id": store_id,
         "user_id": kisiler_map["demo-pazarlamaci1@islerpro.local"],
         "period_id": period_id, "limit_adet": 40, "limit_tutar": 3000},
    ])
    zorunlu("numune limiti", st, r, kabul=(200, 201))
    p1 = tokenlar["demo-pazarlamaci1@islerpro.local"]
    st, gorunen = rpc("search_accounts", p1, p_store_id=store_id, p_limit=10)
    verilen = 0
    for c in (gorunen or [])[:3]:
        # C-1 · Numune fiziksel hareket üretir ama BORÇ DOĞURMAZ.
        st, _ = rpc("create_shipment", p1, p_account_id=c["id"],
                    p_items=[{"product_id": random.choice(urunler)["id"],
                              "adet": random.choice([2, 3, 5])}],
                    p_borclandirir=False, p_tip="numune",
                    p_teslim_alan_ad=random.choice(ADLAR), p_kaynak="elden")
        if st == 200:
            verilen += 1
    satir(f"2 numune limiti (biri kişiye özel) · {verilen} numune teslimatı")


def sinif_mevcutlari(cariler, tokenlar):
    """K22 · Sınıf mevcudu KURUMUN BEYANIDIR; adet önerisi buna dayanır."""
    bolum("Sınıf mevcutları (K22)")
    p1 = tokenlar["demo-pazarlamaci1@islerpro.local"]
    yazilan = 0
    st, gorunen = rpc("search_accounts", p1, p_store_id=STORE_ID,
                      p_tip="kurum", p_limit=20)
    # Hepsine yazılmıyor: K22'nin dört kademeli yedek zinciri, mevcudu
    # OLMAYAN kurumda devreye giriyor — o yol da denenmeli.
    for c in (gorunen or [])[:4]:
        satirlar = [{"sinif": s, "ogrenci_sayisi": random.randint(40, 120)}
                    for s in random.choice([[5, 6, 7, 8], [9, 10, 11, 12]])]
        st, _ = rpc("set_enrollments", p1, p_account_id=c["id"],
                    p_items=satirlar)
        if st == 200:
            yazilan += 1
    satir(f"{yazilan} kurumda sınıf mevcudu bildirildi, "
          "kalanı K22 yedek zinciri denensin diye BOŞ")


def ogretmen_daveti(kurumlar, store_id, tokenlar, kisiler_map):
    """K3 · Öğretmen kuruma bağlanır; kurum adına talep yetkisi ONAYLANIR."""
    bolum("Öğretmen daveti ve kurum yetkisi (K3)")
    sahip = tokenlar["sahip"]
    p1 = tokenlar["demo-pazarlamaci1@islerpro.local"]
    davet = 0
    for k in kurumlar[:3]:
        st, r = rpc("create_invite", p1, p_institution_id=k["id"],
                    p_store_id=store_id,
                    p_telefon=f"05{random.randint(300000000, 559999999)}")
        if st == 200:
            davet += 1

    # Biri ONAY BEKLİYOR bırakılıyor: "bekleyen öğretmen" ekranı boş listede
    # denenemez.
    uid = kisiler_map["demo-ogretmen@islerpro.local"]
    st, r = http("/rest/v1/institution_memberships", "POST", key=SERVICE,
                 prefer="return=representation", body=[
        {"user_id": uid, "institution_id": kurumlar[0]["id"],
         "brans": "Matematik", "gorev": "Zümre Başkanı",
         "can_order_for_institution": True, "status": "aktif"},
        {"user_id": uid, "institution_id": kurumlar[1]["id"],
         "brans": "Matematik", "gorev": "Öğretmen",
         "can_order_for_institution": False, "status": "onay_bekliyor"},
    ])
    zorunlu("kurum üyeliği", st, r, kabul=(200, 201))
    satir(f"{davet} davet kodu · 1 onaylı kurum yetkisi + 1 ONAY BEKLEYEN")


def zincir_kurum(kurumlar):
    """K18 · Şube zinciri: merkez altında gruplanır."""
    bolum("Kurum zinciri (K18)")
    if len(kurumlar) < 3:
        return
    merkez, s1, s2 = kurumlar[0], kurumlar[1], kurumlar[2]
    for sube in (s1, s2):
        http(f"/rest/v1/institutions?id=eq.{sube['id']}", "PATCH",
             key=SERVICE, body={"parent_id": merkez["id"]})
    satir(f"2 şube '{merkez['ad'][:24]}' merkezine bağlandı")


def cari_durumlari(tokenlar):
    """Pasif ve tahsilattaki cari olmadan durum süzgeçleri denenemez."""
    bolum("Cari durumları")
    sahip = tokenlar["sahip"]
    st, hepsi = rpc("search_accounts", sahip, p_store_id=STORE_ID, p_limit=50)
    borcsuz = [c for c in (hepsi or []) if float(c.get("bakiye") or 0) == 0]
    degisen = []
    for c, durum in zip(borcsuz[-3:], ["pasif", "tahsilatta", "pasif"]):
        st, r = rpc("set_account_status", sahip, p_account_id=c["id"],
                    p_durum=durum)
        if st == 200:
            degisen.append(durum)
    satir(f"durum değişikliği: {', '.join(degisen) or 'yapılamadı'} "
          "(borçlu cari pasife ALINAMAZ — kural denendi)")


def cari_tasima(cariler, kurumlar, tokenlar):
    """Öğretmen okul değiştirdi: cari taşınır, GEÇMİŞİ kendisiyle gider."""
    bolum("Cari taşıma")
    sahip = tokenlar["sahip"]
    st, hepsi = rpc("search_accounts", sahip, p_store_id=STORE_ID,
                    p_tip="ogretmen", p_limit=20)
    if not hepsi:
        satir("öğretmen carisi yok"); return
    c = hepsi[0]
    hedef = next((k for k in kurumlar if k["id"] != c["institution_id"]), None)
    if not hedef:
        return
    st, r = rpc("transfer_account", sahip, p_account_id=c["id"],
                p_to_institution_id=hedef["id"],
                p_gerekce="Öğretmen tayin oldu")
    satir("1 öğretmen carisi başka kuruma taşındı"
          if st == 200 else f"taşıma yapılamadı ({st})")


def zamanda_geriye():
    """Kayıtların bir kısmını GEÇMİŞE taşır.

    `create_shipment` teslim tarihini parametre almıyor ve almamalı: sahada
    "dün teslim ettim" diye geriye kayıt girmek istismara açık. Ama demo için
    her şeyin bugüne ait olması, yaşlandırma raporunun DÖRT kovasının üçünü
    boş bırakıyor ve rapor hiç denenemiyor.

    Bu yüzden tarihler kayıt oluştuktan SONRA, doğrudan veritabanında
    kaydırılıyor. Ürün kodu bunu yapmaz; yalnızca demo verisi yapar.
    """
    bolum("Zaman dağılımı")
    c = _db(); cur = c.cursor()
    cur.execute("select id from stores where ad = %s", (DUKKAN,))
    sid = cur.fetchone()[0]

    # Teslimatların yarısı geçmişe: 0-30, 31-60, 61-90 ve 90+ kovalarının
    # dördü de dolsun.
    cur.execute("""
      with s as (
        select id, row_number() over (order by created_at) n,
               count(*) over () t
        from shipments where store_id = %s and borclandirir)
      update shipments sh set
        teslim_edildi_at = sh.teslim_edildi_at - (case
          when s.n <= s.t * 0.35 then 0
          when s.n <= s.t * 0.55 then 45
          when s.n <= s.t * 0.75 then 75
          else 110 end || ' days')::interval,
        created_at = sh.created_at - (case
          when s.n <= s.t * 0.35 then 0
          when s.n <= s.t * 0.55 then 45
          when s.n <= s.t * 0.75 then 75
          else 110 end || ' days')::interval
      from s where s.id = sh.id""", (sid,))
    kaydirilan = cur.rowcount

    # V7 · 24 saati aşan talep: SLA uyarısı denenebilsin.
    cur.execute("""
      update requests set created_at = now() - interval '3 days'
      where store_id = %s and durum = 'gonderildi'
        and id in (select id from requests
                   where store_id = %s and durum = 'gonderildi' limit 3)""",
                (sid, sid))
    gecikmis = cur.rowcount

    # Ziyaretler haftaya yayılsın: rota ve "kaç gündür uğranmadı" ölçüsü
    # tek güne yığılmasın.
    cur.execute("""
      update visits set
        checked_in_at = checked_in_at - (id::text ~ '^[0-7]')::int * interval '9 days',
        checked_out_at = checked_out_at - (id::text ~ '^[0-7]')::int * interval '9 days'
      where store_id = %s""", (sid,))

    c.commit(); c.close()
    satir(f"{kaydirilan} teslimat 0/45/75/110 gün öncesine dağıtıldı "
          "(yaşlandırmanın dört kovası da dolsun)")
    satir(f"{gecikmis} talep 3 gün öncesine alındı (V7 · 24 saat SLA uyarısı)")


def daha_cok_cek(tokenlar):
    """Tek çek, vade takvimini ve çek yaşam döngüsünü göstermeye yetmiyor."""
    bolum("Çek portföyü (K11)")
    p1 = tokenlar["demo-pazarlamaci1@islerpro.local"]
    sahip = tokenlar["sahip"]
    bugun = dt.date.today()
    st, cariler = rpc("search_accounts", p1, p_store_id=STORE_ID, p_limit=30)
    acilan = 0
    # Vadeler bilerek dağıtıldı: geçmiş, bu hafta, bu ay, uzak. Takvim tek
    # renk görünürse "yaklaşan vade" uyarısı denenemez.
    vadeler = [-25, -6, 3, 9, 21, 48, 90]
    for c, gun in zip((cariler or [])[:7], vadeler):
        st, _ = rpc("create_payment", p1, p_account_id=c["id"],
                    p_tutar=round(random.uniform(1500, 9000), 2),
                    p_yontem=random.choice(["cek", "cek", "senet"]),
                    p_cek_vade=str(bugun + dt.timedelta(days=gun)),
                    p_cek_banka=random.choice(["Ziraat", "Vakıfbank",
                                               "İş Bankası", "Halkbank"]),
                    p_cek_no=f"{random.randint(100000, 999999)}")
        if st == 200:
            acilan += 1

    st, takvim = rpc("cheque_calendar", sahip, p_store_id=STORE_ID)
    cekler = [x for g in (takvim or {}).get("gunler", [])
              for x in g.get("cekler", []) if x.get("durum") == "portfoyde"]

    # Durum MAKİNESİ var: portföyde → tahsilde → tahsil_edildi/karşılıksız.
    # Doğrudan `tahsil_edildi` yazmak reddediliyor (ve doğru yapıyor) —
    # demo da makineyi izlemeli, yoksa hiçbir çek durum değiştirmiyordu.
    yollar = [
        ["tahsilde", "tahsil_edildi"],     # karşılığı alındı, bakiye düştü
        ["tahsilde", "karsiliksiz"],       # bankadan döndü
        ["tahsilde"],                      # bankada bekliyor
        ["ciro_edildi"],                   # başkasına ciro
        ["iade_edildi"],                   # keşideciye geri verildi
        [],                                # portföyde kalsın
    ]
    durumlar = {}
    for i, x in enumerate(cekler):
        for adim in yollar[i % len(yollar)]:
            st, _ = rpc("set_cheque_status", sahip, p_cheque_id=x["id"],
                        p_durum=adim,
                        p_endorsed_to="Anadolu Kırtasiye"
                        if adim == "ciro_edildi" else None,
                        p_gerekce="Bankadan karşılıksız döndü"
                        if adim == "karsiliksiz" else None)
            if st != 200:
                break
            durumlar[adim] = durumlar.get(adim, 0) + 1
    son = {k: v for k, v in durumlar.items() if k != "tahsilde"}
    satir(f"{acilan} çek/senet · " +
          (" · ".join(f"{v} {k}" for k, v in son.items()) or "hepsi portföyde"))


def limit_asimi(tokenlar):
    """Kredi limiti AŞILMIŞ cari olmadan limit uyarısı denenemez."""
    bolum("Kredi limiti")
    sahip = tokenlar["sahip"]
    st, cariler = rpc("search_accounts", sahip, p_store_id=STORE_ID,
                      p_borclu=True, p_limit=10)
    asan = 0
    for c in (cariler or [])[:2]:
        bakiye = float(c.get("bakiye") or 0)
        if bakiye <= 0:
            continue
        # Limiti bakiyenin ALTINA çekiyoruz: gerçek hayatta limit önce
        # konur, borç sonra büyür — sonuç aynı, kurulumu kısa.
        st, _ = rpc("update_account", sahip, p_account_id=c["id"],
                    p_credit_limit=round(bakiye * 0.6, 2))
        if st == 200:
            asan += 1
    satir(f"{asan} cari limitini AŞMIŞ durumda (uyarı ve onay yolu denensin)")


# ── Silme ───────────────────────────────────────────────────────────────────
# Dükkanı doğrudan silmek yetmiyor: `payment_allocations` gibi tablolar
# `shipments`'a CASCADE'siz bağlı ve silme 23503 ile düşüyor. Bağımlılık
# sırası elle veriliyor — "cascade herhâlde halleder" varsayımı, yarım silinmiş
# bir demo bırakıyordu ve ikinci koşu "cari zaten var" diye patlıyordu.
SILME_SIRASI = """
delete from payment_allocations pa using payments p
  where pa.payment_id = p.id and p.store_id = %(s)s;
delete from payment_allocations pa using shipments sh
  where pa.shipment_id = sh.id and sh.store_id = %(s)s;
delete from cheques c using payments p
  where c.payment_id = p.id and p.store_id = %(s)s;
delete from cheques where store_id = %(s)s;
delete from payments where store_id = %(s)s;
delete from return_items ri using returns r
  where ri.return_id = r.id and r.store_id = %(s)s;
delete from returns where store_id = %(s)s;
delete from shipment_items si using shipments sh
  where si.shipment_id = sh.id and sh.store_id = %(s)s;
delete from shipments where store_id = %(s)s;
delete from order_items oi using orders o
  where oi.order_id = o.id and o.store_id = %(s)s;
delete from orders where store_id = %(s)s;
delete from request_items ri using requests r
  where ri.request_id = r.id and r.store_id = %(s)s;
delete from requests where store_id = %(s)s;
delete from exam_deliveries ed using exam_programs ep
  where ed.exam_program_id = ep.id and ep.store_id = %(s)s;
delete from exam_programs where store_id = %(s)s;
delete from visit_plans where store_id = %(s)s;
delete from visits where store_id = %(s)s;
delete from assignments where store_id = %(s)s;
delete from account_enrollments ae using accounts a
  where ae.account_id = a.id and a.store_id = %(s)s;
delete from accounts where store_id = %(s)s;
delete from store_products where store_id = %(s)s;
delete from saved_reports where store_id = %(s)s;
delete from period_summaries where store_id = %(s)s;
delete from institution_store_links where store_id = %(s)s;
delete from account_transfers at using accounts a
  where at.account_id = a.id and a.store_id = %(s)s;
delete from sample_limits where store_id = %(s)s;
delete from discount_rules where store_id = %(s)s;
delete from discount_caps where store_id = %(s)s;
delete from invites where store_id = %(s)s;
delete from settings where store_id = %(s)s;
delete from import_batch_rows r using import_batches b
  where r.batch_id = b.id and b.store_id = %(s)s;
delete from import_batches where store_id = %(s)s;
delete from memberships where store_id = %(s)s;
delete from stores where id = %(s)s;
"""


def _db():
    import psycopg2
    yerel = os.path.join(KOK, ".env.local")
    if not os.path.exists(yerel):
        print("  ✗ .env.local yok — silme için veritabanı parolası gerekli")
        sys.exit(1)
    e = dict(ENV)
    for satir in open(yerel, encoding="utf-8"):
        if "=" in satir and not satir.strip().startswith("#"):
            k, v = satir.strip().split("=", 1)
            e[k] = v
    ref = URL.removeprefix("https://").removesuffix(".supabase.co")
    return psycopg2.connect(
        "host=aws-0-eu-central-1.pooler.supabase.com port=6543 "
        f"dbname=postgres user=postgres.{ref} "
        f"password={e['SUPABASE_DB_PASSWORD']} sslmode=require")


def sil():
    bolum("Demo verisi siliniyor")
    st, t = http(f"/rest/v1/tenants?unvan=eq.{urllib.parse.quote(ISLETME)}"
                 "&select=id", key=SERVICE)
    if not t:
        print("  işletme yok"); return
    st, s = http(f"/rest/v1/stores?tenant_id=eq.{t[0]['id']}"
                 f"&ad=eq.{urllib.parse.quote(DUKKAN)}&select=id,created_at",
                 key=SERVICE)
    if s:
        c = _db(); cur = c.cursor()
        for cumle in SILME_SIRASI.strip().split(";"):
            if cumle.strip():
                cur.execute(cumle, {"s": s[0]["id"]})
        # Kurum yetkilileri EN SONA kalıyor: öğretmen carisi kişiye bağlı
        # (accounts.institution_contact_id), önce silmek 23503 veriyor.
        # Demo koşusunda eklenenler dükkandan SONRA açılanlardır; dizin ortak
        # (K4), daha eskilerine dokunmak başkasının verisini siler.
        # Yalnızca HİÇBİR CARİNİN BAĞLI OLMADIĞI kişiler siliniyor. Tarih
        # süzgeci tek başına yetmedi: işletmenin başka dükkanındaki bir cari
        # de kişiye bağlıysa silme 23503 ile düşüyor ve İŞLEMİN TAMAMI geri
        # alınıyordu — yani "sildim" diyen komut hiçbir şey silmemiş oluyordu.
        cur.execute("""delete from institution_contacts ic
                       where ic.tenant_id = %s and ic.created_at >= %s
                         and not exists (select 1 from accounts a
                                         where a.institution_contact_id = ic.id)""",
                    (t[0]["id"], s[0]["created_at"]))
        silinen_kisi = cur.rowcount
        # Kurum üyelikleri DÜKKANA BAĞLI DEĞİL (K3: öğretmen kuruma bağlanır),
        # o yüzden dükkan silinince gitmiyorlardı. Kalan satırlar bir sonraki
        # koşuda tekillik kısıtına takılıp yeni yazmayı sessizce düşürüyor ve
        # "onay bekleyen" üyelik aktif görünüyordu.
        cur.execute("""delete from institution_memberships
                       where user_id in (select id from auth.users
                                         where email = any(%s))""",
                    ([e for e, _, _ in EKIP],))
        c.commit(); c.close()
        satir(f"{DUKKAN} ve bağlı tüm kayıtlar silindi "
              f"({silinen_kisi} kurum yetkilisi dâhil)")
    else:
        satir("dükkan yok")
    silinen = 0
    epostalar = {e for e, _, _ in EKIP}
    for u in _kullanicilari_getir():
        if u["email"] in epostalar:
            http(f"/auth/v1/admin/users/{u['id']}", "DELETE", key=SERVICE)
            silinen += 1
    satir(f"{silinen} demo kullanıcısı silindi")


# ── Ana akış ────────────────────────────────────────────────────────────────
STORE_ID = None


def main():
    global STORE_ID
    if not SERVICE:
        print("SUPABASE_SERVICE_KEY gerekli.", file=sys.stderr)
        return 2
    if "--sil" in sys.argv:
        sil(); return 0

    st, t = http(f"/rest/v1/tenants?unvan=eq.{urllib.parse.quote(ISLETME)}"
                 "&select=id", key=SERVICE)
    zorunlu("işletme", st, t)
    if not t:
        print(f"'{ISLETME}' bulunamadı."); return 1
    tenant_id = t[0]["id"]

    sahip_token = giris("test-sahip@islerpro.local")
    if not sahip_token:
        print("Sahip hesabıyla giriş yapılamadı — parolası farklı olabilir.")
        print("Demo, sahip hesabının parolasını DEĞİŞTİRMEZ; onun yerine")
        print("demo-mudur hesabı kullanılacak.")
    st, pe = http(f"/rest/v1/periods?tenant_id=eq.{tenant_id}"
                  "&status=eq.aktif&select=id,ad", key=SERVICE)
    zorunlu("dönem", st, pe)
    period_id = pe[0]["id"]

    store_id = dukkani_kur(tenant_id, sahip_token)
    STORE_ID = store_id
    kisiler_map = ekibi_kur(tenant_id, store_id, sahip_token)

    tokenlar = {"sahip": sahip_token}
    for eposta, _, _ in EKIP:
        tokenlar[eposta] = giris(eposta)
    if not sahip_token:
        tokenlar["sahip"] = tokenlar["demo-mudur@islerpro.local"]

    fiyatlari_kur(store_id, tokenlar["sahip"])
    denemeleri_ac(store_id, tokenlar["sahip"])
    baski_gruplari(store_id, tokenlar["sahip"])
    kurumlar = kurumlari_bagla(store_id, tokenlar["sahip"])
    kisiler = kisileri_ac(kurumlar, tenant_id)
    cariler = carileri_ac(store_id, kurumlar, kisiler, tokenlar["sahip"],
                          kisiler_map["demo-ogretmen@islerpro.local"],
                          tenant_id)
    portfoy = portfoy_dagit(cariler, kisiler_map, period_id, tokenlar["sahip"])

    urunler = urun_havuzu(store_id, tokenlar["sahip"])
    # Kurallar ve tavan siparişlerden ÖNCE: sipariş açılırken tavan yoksa
    # kontrol edilecek bir şey de yok, onay yolu hiç denenmiyordu.
    iskonto_kurallari(store_id, kisiler_map, tokenlar["sahip"])
    ts = talepler(cariler, urunler, tokenlar, portfoy)
    sip = siparisler(ts, tokenlar)
    konsinye = teslimatlar(sip, cariler, urunler, tokenlar)
    tahsilatlar(cariler, tokenlar)
    cek_yasam_dongusu(tokenlar)
    iade_ve_konsinye(konsinye, tokenlar)
    ziyaretler(kurumlar, tokenlar, urunler)
    deneme_programi(cariler, tokenlar, store_id)

    # Kenar durumlar: ekranların açıldığını değil, İŞLERİNİ YAPTIĞINI görmek
    # için. (Boş kovalı yaşlandırma raporu "çalışıyor" demek değildir.)
    numune_limiti(store_id, period_id, kisiler_map, tokenlar, urunler, cariler)
    sinif_mevcutlari(cariler, tokenlar)
    ogretmen_daveti(kurumlar, store_id, tokenlar, kisiler_map)
    zincir_kurum(kurumlar)
    daha_cok_cek(tokenlar)
    limit_asimi(tokenlar)
    cari_tasima(cariler, kurumlar, tokenlar)
    cari_durumlari(tokenlar)
    zamanda_geriye()

    kayitli_rapor(tokenlar, store_id)

    bolum("Hazır")
    print(f"  Dükkan   : {DUKKAN} ({ISLETME})")
    print(f"  Giriş    : VS Code'da F5 — DEV_LOGIN açık yapılandırma")
    print(f"  Hesaplar : demo-hesaplar.md")
    with open(os.path.join(KOK, "demo-hesaplar.md"), "w", encoding="utf-8") as f:
        f.write(f"# Demo hesapları — {DUKKAN}\n\n")
        f.write("Bu dosya **gitignore'da**. Parolalar yalnızca demo içindir.\n\n")
        f.write(f"Ortak parola: `{PAROLA}`\n\n")
        f.write("| Rol | E-posta | Ad |\n|---|---|---|\n")
        f.write("| İşletme sahibi | test-sahip@islerpro.local | Mahmut Kaya |\n")
        for eposta, ad, rol in EKIP:
            f.write(f"| {rol} | {eposta} | {ad} |\n")
        f.write("\nVS Code'da F5 ile (DEV_LOGIN açık) açıp "
                "e-posta+parola yolundan girin.\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
