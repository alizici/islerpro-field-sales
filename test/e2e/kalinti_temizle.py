#!/usr/bin/env python3
"""
İşlerPro · e2e kalıntı temizleyici (bir kereye mahsus)

dogrula.py 25 Ağustos'a kadar kendi verisini bırakıyordu; her koşu iki yetim
tenant + bir test kurumu + yayınevi + ürün üretiyordu. Kurum dizini ORTAK
olduğu için (K4) bu kalıntılar yalnızca bu işletmeyi değil dizini kirletir.
Temizlik dogrula.py içine alındı; bu betik yalnızca ESKİ kalıntılar içindir.

  python3 test/e2e/kalinti_temizle.py            → ne silineceğini LİSTELER
  python3 test/e2e/kalinti_temizle.py --uygula   → siler

Gerçek işletme ('İşler Yayınları Kitap') ve tohumlanan 755 okul hedeflenmez:
yalnızca e2e'nin ürettiği sabit adlar seçilir.
"""
import json, os, sys, urllib.request, urllib.error, urllib.parse

ENV = {}
for line in open(os.path.join(os.path.dirname(__file__), "..", "..", ".env"), encoding="utf-8"):
    if "=" in line and not line.strip().startswith("#"):
        k, v = line.strip().split("=", 1)
        ENV[k] = v
URL = ENV["SUPABASE_URL"]
SERVICE = os.environ.get("SUPABASE_SERVICE_KEY", "")

# e2e'nin ürettiği sabit adlar — başka hiçbir şey hedeflenmez.
HEDEF = [
    ("tenants",      "unvan",  "in.(\"A İşletme\",\"B İşletme\",\"A tekrar\")"),
    ("institutions", "ad",     "like.E2E %"),
    ("publishers",   "ad",     "like.E2E %"),
    ("products",     "ad",     "like.E2E %"),
]

def http(path, method="GET", body=None):
    req = urllib.request.Request(URL + path, method=method)
    req.add_header("apikey", SERVICE)
    req.add_header("Authorization", "Bearer " + SERVICE)
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

def main():
    if not SERVICE:
        print("SUPABASE_SERVICE_KEY gerekli.", file=sys.stderr)
        return 2
    uygula = "--uygula" in sys.argv

    print(f"\n\033[1mKalıntı taraması\033[0m  ({'SİLİNECEK' if uygula else 'yalnızca liste'})\n")
    plan = []
    for tablo, alan, kosul in HEDEF:
        q = f"/rest/v1/{tablo}?select=id,{alan}&{alan}={urllib.parse.quote(kosul, safe='.,()')}"
        st, rows = http(q)
        rows = rows or []
        print(f"  {tablo:14} {len(rows):4} kayıt")
        for r in rows[:3]:
            print(f"                  · {r[alan]}")
        if len(rows) > 3:
            print(f"                  · … {len(rows)-3} tane daha")
        plan.append((tablo, alan, kosul, rows))

    if not any(r for *_, r in plan):
        print("\n  Kalıntı yok.")
        return 0
    if not uygula:
        print("\n  Silmek için:  python3 test/e2e/kalinti_temizle.py --uygula")
        return 0

    # ── Silme sırası ────────────────────────────────────────────────────
    # Cascade tek başına yetmez: bazı FK'lerde ON DELETE yoktur ve bunlar
    # ÜRETİMDE DOĞRUDUR — talebe girmiş ürün, cariye bağlı kurum silinemez.
    #   request_items.product_id  → products    (ON DELETE yok)
    #   discount_rules.product_id → products    (ON DELETE yok)
    #   accounts.institution_id   → institutions(ON DELETE yok)
    # Bu yüzden önce ticari hareketler, sonra tenant, en sonda ortak dizin.
    print()
    for tablo, alan, kosul, rows in plan:
        if tablo != "tenants":
            continue
        for t in rows:
            tid = t["id"]
            # store_id taşıyan tablolar tenant'ın dükkanları üzerinden
            st, stores = http(f"/rest/v1/stores?select=id&tenant_id=eq.{tid}")
            for sto in (stores or []):
                for tb in ("discount_rules", "discount_caps", "store_products"):
                    http(f"/rest/v1/{tb}?store_id=eq.{sto['id']}", "DELETE")
            # payment_allocations tenant_id taşımaz; ödemeler üzerinden
            st, pays = http(f"/rest/v1/payments?select=id&tenant_id=eq.{tid}")
            for pay in (pays or []):
                http(f"/rest/v1/payment_allocations?payment_id=eq.{pay['id']}",
                     "DELETE")
            for tb in ("cheques", "payments", "returns", "shipments",
                       "orders", "requests", "import_batches",
                       "account_enrollments", "assignments"):
                http(f"/rest/v1/{tb}?tenant_id=eq.{tid}", "DELETE")
        print(f"  · {len(rows)} tenant'ın ticari kayıtları silindi")

    # Kurumun tenant bağı kopar (institutions.ekleyen_tenant_id → tenants)
    http("/rest/v1/institutions?ad=" + urllib.parse.quote("like.E2E %"),
         "PATCH", {"ekleyen_tenant_id": None})

    for tablo, alan, kosul, rows in plan:
        if not rows:
            continue
        st, r = http(f"/rest/v1/{tablo}?{alan}={urllib.parse.quote(kosul, safe='.,()')}",
                     "DELETE")
        işaret = "\033[32m✓\033[0m" if st < 400 else "\033[31m✗\033[0m"
        print(f"  {işaret} {tablo:14} {len(rows):4} kayıt" +
              ("" if st < 400 else f"  → {r}"))

    print("\n  Bitti. dogrula.py artık kendi verisini temizliyor; "
          "bu betiğe bir daha gerek olmamalı.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
