# Demo veri seti

Canlı Supabase'e, **mevcut işletmenin içine** yeni bir dükkan kurar ve tüm
akışlarda gerçek kayıt bırakır. Amaç: uygulamayı elle gezerken her ekranın
dolu olması.

```bash
REF=$(grep SUPABASE_URL ../../.env | sed 's|.*//||;s|\.supabase\.co||')
export SUPABASE_SERVICE_KEY=$(supabase projects api-keys --project-ref "$REF" \
  -o json | python3 -c "import sys,json;print(next(k['api_key'] for k in json.load(sys.stdin) if k['name']=='service_role'))")

python3 test/demo/demo_veri.py          # kurar (tekrar çalıştırılabilir)
python3 test/demo/demo_veri.py --sil    # geri alır
```

Hesaplar `demo-hesaplar.md` dosyasına yazılır — **gitignore'da**, parola içerir.
Giriş: VS Code'da F5 (ya da `flutter run --dart-define-from-file=.env --dart-define=DEV_LOGIN=true`) → e-posta + parola yolu.

## Neden ayrı işletme değil

Ürünler işletmeye bağlı: 24.630 kalem "İşler Yayınları Kitap"ta. Ayrı bir demo
işletmesi kurulsaydı **katalog boş kalırdı** ve demo gerçekçi olmazdı. Kurum
dizini ise ortak (K4), o yüzden gerçek 755 okuldan seçiliyor.

## Neden RPC ile

Kayıtlar doğrudan `insert` ile de üretilebilirdi. Üretilmiyor: `insert`
satırları yazar ama iş kurallarını atlar — K25 iskonto çözümlemesi, K26 borcun
teslimattan doğması, K48 FIFO mahsup, K7'nin kurum toplamı yasağı. Böyle bir
demo ürünün gerçekte üretmeyeceği bir veriyle dolar ve **tam orada yalan
söylemeye başlar.**

Aynı sebeple talebi cariyi görebilen pazarlamacı açar (RLS gerçekten denenir),
ve ziyaretler boş açılıp kapanmaz: Y-18 damgası yalnızca ziyaret açıkken
yazılan kayıtlara vurulur.

## Kapsam denetimi

```bash
python3 test/demo/denetim.py
```

68 noktada "veri var mı" diye sorar ve eksikse **çıkış kodu 1** verir. Denetimin
sorduğu şey "ekran açılıyor mu" değil: yaşlandırmanın dört kovası da dolu mu,
limitini aşan cari var mı, çekin her durumu temsil ediliyor mu, çıktısız ziyaret
var mı. Boş kovalı bir yaşlandırma raporu "çalışıyor" demek değildir.

Bu denetim iki gerçek boşluk yakaladı:

* **İskonto kuralları hiç yazılmıyordu.** PostgREST toplu eklemede tüm
  satırların aynı anahtarları taşımasını şart koşuyor; eksik anahtarlı satır
  400 veriyordu ve **dönüş kontrol edilmediği için** demo "kuruldu" diyordu.
  Sessiz başarısızlık, olmayan veriyi var sanmaktır — yazmalar artık
  kontrol ediliyor.
* **Her şey bugüne aitti.** Yaşlandırmanın dört kovasının üçü boştu. Teslim
  tarihi RPC parametresi değil (ve olmamalı: sahada geriye kayıt girmek
  istismara açık), o yüzden tarihler kayıt oluştuktan sonra doğrudan
  veritabanında kaydırılıyor — bunu yalnızca demo verisi yapar, ürün kodu
  yapmaz.

## Öğretmen ne görür (K3 · K19 · K7)

Öğretmen hesabıyla girildiğinde "Taleplerim" listesi **kendi carilerinin** ve
**talep yetkisi ONAYLANMIŞ kurumların** taleplerini gösterir — bunları
pazarlamacı açmış olsa bile. Kural `auth_own_accounts()`:

```
kendi carileri (accounts.user_id = ben)
  ∪  kurumsal cariler — YALNIZCA can_order_for_institution ve status='aktif' ise
```

Demoda Fatma Öz'ün bir kurumda onaylı yetkisi, bir kurumda **onay bekleyen**
üyeliği var: ikincisinin kurumsal carisi listede **görünmez**. Yetki
kapısının çalıştığını görmenin yolu bu.

Bu ekran bir kez yanlış göründü ve sebebi ikisi de DEMO VERİSİYDİ:

* Öğretmenin girişi **başkasının carisine** bağlanmıştı. `p_user_id` ilk
  öğretmen carisine veriliyordu; o carinin unvanı ise rastgele bir yetkilinin
  adı. Ekranda "Ömer Kaya (Türkçe)" carisi Fatma'nınmış gibi duruyordu.
  Artık öğretmene kendi adına kişi ve cari açılıyor.
* **Kurum üyelikleri `--sil` ile temizlenmiyordu.** Üyelik dükkana bağlı
  değil (K3: öğretmen kuruma bağlanır), o yüzden dükkan silinince gitmiyordu.
  Eski satırlar duruyor, yeni yazma tekillik kısıtına takılıp **sessizce**
  düşüyor ve "onay bekleyen" diye kurgulanan üyelik aktif görünüyordu — yani
  uygulama hak edilmemiş erişim veriyormuş gibi. Vermiyordu; veri yanlıştı.

İkisinin ortak dersi aynı: **kontrol edilmeyen yazma, olmayan veriyi var
sandırıyor.** Demodaki bütün toplu yazmalar artık `zorunlu()` ile kontrol
ediliyor.

## Bilerek eksik bırakılanlar

Demo "her şey yolunda" göstermek için değil, **ekranların işini yapıp
yapmadığını** görmek için:

| Ne | Neden |
|---|---|
| Bir kısım cari ATANMAMIŞ | "atanmamış cari" süzgeci ve portföy boşluğu raporu boş listede denenemez |
| Bir kısım borç ÖDENMEMİŞ | yaşlandırma ve borçlu cariler raporu dolu olmalı |
| Bazı ziyaretler ÇIKTISIZ | K10'un ölçütü tam olarak budur |
| Bazı talepler BEKLİYOR | gelen kutusu boş olmamalı |
| Eski baskılar depoda | K23 · "yeni çıktı ama eskisi elde" karşılaştırması |
| Çekler vadesi geçmiş / yakın / uzak | vade takvimi tek renk görünmesin |
