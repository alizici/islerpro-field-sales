#!/usr/bin/env bash
# İşlerPro · doğrulama
#
#   ./dogrula.sh              analiz + birim/widget testleri        (~5 sn)
#   ./dogrula.sh --e2e        + gerçek Supabase'e karşı API testleri (~30 sn)
#   ./dogrula.sh --web        + tarayıcıda uçtan uca akış testleri   (~1 dk)
#   ./dogrula.sh --ios        + iOS simülatöründe akış testleri      (~5 dk)
#   ./dogrula.sh --macos      + macOS'ta akış testleri  (KISMİ — bkz. docs/01)
#   ./dogrula.sh --hepsi      hepsi
set -uo pipefail
cd "$(dirname "$0")"
export PATH="/opt/homebrew/bin:$PATH"
hata=0
arg="${1:-}"
# `--macos` bilerek `--hepsi` dışında: o adım henüz tam yeşil değil ve
# `--hepsi`'yi kırmızıya boyamak, yeşil olması gereken adımların sinyalini
# öldürür.
calistir() {
  [ "$arg" = "$1" ] || { [ "$arg" = "--hepsi" ] && [ "$1" != "--macos" ]; }
}

set -a; [ -f .env ] && source .env; set +a


# Chrome ile chromedriver ana sürümü UYUŞMAK ZORUNDA. Homebrew hep en yeniyi
# kurduğu için Chrome bir sürüm geride kaldığında web testleri sessizce
# çalışmaz. Bu yüzden eşleşen sürücüyü .tools/ altında kendimiz tutuyoruz.
surucu_hazirla() {
  local chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
  [ -x "$chrome" ] || { echo "  ✗ Chrome bulunamadı"; return 1; }
  local major; major=$("$chrome" --version | sed 's/[^0-9]*\([0-9]*\).*/\1/')

  if [ -x .tools/chromedriver ] &&
     [ "$(.tools/chromedriver --version | sed 's/[^0-9]*\([0-9]*\).*/\1/')" = "$major" ]; then
    return 0
  fi

  echo "  · Chrome $major için chromedriver indiriliyor (chrome-for-testing)"
  local ver
  ver=$(curl -s https://googlechromelabs.github.io/chrome-for-testing/latest-patch-versions-per-build-with-downloads.json \
    | python3 -c "
import sys, json
d = json.load(sys.stdin)['builds']
c = [v for k, v in d.items() if k.startswith('$major.')
     and any(x['platform']=='mac-arm64' for x in v['downloads'].get('chromedriver', []))]
c.sort(key=lambda v: [int(x) for x in v['version'].split('.')])
print(c[-1]['version'] if c else '')
")
  [ -n "$ver" ] || { echo "  ✗ $major için sürücü bulunamadı"; return 1; }
  mkdir -p .tools
  curl -sL -o .tools/cd.zip \
    "https://storage.googleapis.com/chrome-for-testing-public/$ver/mac-arm64/chromedriver-mac-arm64.zip" || return 1
  unzip -oq .tools/cd.zip -d .tools/ && mv -f .tools/chromedriver-mac-arm64/chromedriver .tools/chromedriver
  rm -rf .tools/chromedriver-mac-arm64 .tools/cd.zip
  xattr -d com.apple.quarantine .tools/chromedriver 2>/dev/null
  chmod +x .tools/chromedriver
  echo "  · chromedriver $ver hazır"
}

baslik() { printf "\n\033[1m── %s %s\033[0m\n" "$1" "$(printf '─%.0s' $(seq $((44-${#1}))))"; }

baslik "Statik analiz"
flutter analyze || hata=1

baslik "Birim ve widget testleri"
flutter test || hata=1

if calistir --e2e; then
  baslik "API + RLS (gerçek Supabase)"
  REF=$(grep SUPABASE_URL .env | sed 's|.*//||;s|\.supabase\.co||')
  SR=$(supabase projects api-keys --project-ref "$REF" -o json 2>/dev/null \
       | python3 -c "import sys,json;print(next(k['api_key'] for k in json.load(sys.stdin) if k.get('name')=='service_role'))" 2>/dev/null)
  if [ -z "$SR" ]; then
    echo "  ✗ service_role anahtarı alınamadı — 'supabase login' gerekli"; hata=1
  else
    SUPABASE_SERVICE_KEY="$SR" python3 test/e2e/dogrula.py || hata=1
  fi
fi

# Anahtarlar tek yerden: `--dart-define-from-file` .env'i olduğu gibi okuyor.
# Tek tek tanım yazmak, .env'e yeni bir anahtar eklendiğinde burada
# unutulmasına yol açıyordu.
DEFS=(--dart-define-from-file=.env --dart-define=DEV_LOGIN=true)

if calistir --web; then
  baslik "Uçtan uca · web"
  if ! surucu_hazirla; then
    echo "  ✗ chromedriver hazırlanamadı — bkz. docs/06-test-stratejisi.md"; hata=1
  else
    pkill -f chromedriver 2>/dev/null; sleep 1
    (.tools/chromedriver --port=4444 >/tmp/cd.log 2>&1 &)
    until curl -s http://localhost:4444/status >/dev/null 2>&1; do sleep 1; done
    flutter drive --driver=test_driver/integration_test.dart \
      --target=integration_test/akis_test.dart \
      -d web-server --browser-name=chrome --headless "${DEFS[@]}" || hata=1
    pkill -f chromedriver 2>/dev/null
  fi
fi

if calistir --ios; then
  baslik "Uçtan uca · iOS simülatörü"
  # flutter yalnızca AÇIK simülatörleri görür. "available" listesinden ilk
  # iPhone'u seçmek, kapalı bir cihazın kimliğini vermeye ve testin
  # "no supported devices" ile düşmesine yol açıyordu — önce açığı ara.
  SIM=$(xcrun simctl list devices booted -j 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)['devices']
for rt,ds in d.items():
    for x in ds:
        if 'iPhone' in x['name']: print(x['udid']); raise SystemExit" )
  if [ -z "$SIM" ]; then
    SIM=$(xcrun simctl list devices available -j 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)['devices']
en=None
for rt,ds in d.items():
    if 'iOS' not in rt: continue
    for x in ds:
        if 'iPhone' in x['name']: en=(rt,x['udid'])
print(en[1] if en else '')")
    [ -n "$SIM" ] && { xcrun simctl boot "$SIM" 2>/dev/null; open -a Simulator; sleep 8; }
  fi
  if [ -z "$SIM" ]; then
    echo "  ✗ iPhone simülatörü bulunamadı"; hata=1
  else
    flutter test integration_test/akis_test.dart -d "$SIM" "${DEFS[@]}" || hata=1
  fi
fi

if calistir --macos; then
  baslik "Uçtan uca · macOS"
  # UYARI: akış testleri mobil için yazıldı; masaüstü yerleşimine uyarlanması
  # sürüyor ve bu adım HENÜZ TAM YEŞİL DEĞİL (docs/01 · "Masaüstünün durumu").
  # `--hepsi` bu yüzden onu kapsamıyor; ayrıca çağrılır.
  flutter test integration_test/akis_test.dart -d macos --timeout 180s \
    "${DEFS[@]}" || hata=1
fi

echo
[ $hata -eq 0 ] && echo -e "\033[32m✓ Tümü geçti\033[0m" || echo -e "\033[31m✗ Başarısız adımlar var\033[0m"
exit $hata
