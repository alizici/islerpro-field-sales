# Test Stratejisi

> Tek komut: `./dogrula.sh --hepsi`

## Dört katman

| Katman | Ne doğrular | Nerede | Süre |
|---|---|---|---|
| **Statik analiz** | Tip, lint, ölü kod | `flutter analyze` | ~2 sn |
| **Birim + widget** | İş kuralları, ekran davranışı | `test/` | ~3 sn |
| **API + RLS** | Veritabanı fonksiyonları, yetki sınırları | `test/e2e/dogrula.py` | ~30 sn |
| **Uçtan uca** | Gerçek uygulama, gerçek backend | `integration_test/` | ~1 dk |

### Neden `integration_test` seçildi

"Web ve mobil farketmeksizin" şartını **tek başına** karşılayan seçenek buydu:

| | Web | Mobil | Dil | Ek araç |
|---|---|---|---|---|
| **`integration_test`** | ✅ | ✅ | Dart | yok |
| Patrol | ❌ | ✅ | Dart | yok |
| Maestro | kısmi | ✅ | YAML | Java + CLI |
| Playwright / Cypress | ✅ | ❌ | JS | Node |

`integration_test/akis_test.dart` **aynı dosya** olarak Chrome'da, iOS
simülatöründe, Android emülatöründe ve masaüstünde çalışır.

## Widget kimlikleri

Testler metne göre arama yapmaz — etiket değişince test kırılmasın diye
widget'lara sabit kimlik verilir. Hepsi tek dosyada: `lib/core/test_keys.dart`.

```dart
await t.tap(find.byKey(K.girisGonder));     // etiketten bağımsız
```

Yazım hatası derleme zamanında yakalanır; `find.text('Kod gönder')` gibi
kırılgan bağlar oluşmaz.

## Yerleşim farkı

Mobilde ilk 4 sekmeden sonrası "Daha fazla" panelindedir. Aynı test her
platformda çalışsın diye bu farkı **test değil yardımcı** çözer:

```dart
await gitEkrana(t, 'Ayarlar');   // masaüstünde doğrudan, mobilde panelden
```

## Çalıştırma

```bash
./dogrula.sh              # analiz + birim/widget          (~5 sn, her commit)
./dogrula.sh --e2e        # + API/RLS                      (~30 sn, şema değişince)
./dogrula.sh --web        # + tarayıcı akışı               (~1 dk)
./dogrula.sh --ios        # + iOS simülatörü               (~1 dk)
./dogrula.sh --hepsi      # hepsi                          (~2 dk, sürüm öncesi)
```

### chromedriver

Web akış testleri Chrome ile **aynı ana sürüm** chromedriver ister.
`brew install --cask chromedriver` her zaman en yeniyi kurar ve uyuşmayabilir.
Eşleşen sürüm:

```bash
CV=$(/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome --version | grep -oE '[0-9.]+')
# chrome-for-testing'den aynı ana sürümü indirip /tmp/chromedriver151 olarak koy
```

`dogrula.sh` önce `/tmp/chromedriver151`'e bakar, yoksa PATH'tekini kullanır.

### iOS

`ios/Podfile` ve Xcode hedefi **iOS 15.0**'a yükseltildi (`file_picker_darwin`
en az 14.0 istiyor). İlk derleme uzun sürer, sonrakiler hızlıdır.

## Bu testlerin bulduğu gerçek hatalar

Bu bölüm tutulur — hangi katmanın işe yaradığını gösterir.

| Hata | Bulan katman |
|---|---|
| `institutions`'a INSERT politikası yok — kimse kurum ekleyemiyor | API/RLS |
| 5 tabloda daha yazma politikası eksik (`stores`, `assignments`, …) | API/RLS |
| Davet kodunda `I` çıkabiliyor (`upper()` sırası yanlış) | API/RLS |
| **Türkçe büyük harf**: `Aktif` → `AKTIF` olması gereken `AKTİF` | widget |
| "Daha fazla" paneli küçük ekranda 27px taşıyor | uçtan uca · iOS |
| **K25 · `discount_tier` sorguda kullanılmıyor** — her kademe aynı oranı alıyor | API/RLS |
| **K25 · kademe kuralı yoksa genel kural siliniyor** (`select into` NULL'a çekiyor) | API/RLS |
| **`100.00` → `10000`**: nokta binlik ayracı sanılıyor, fiyat 100 katına çıkıyor | widget |
| Fiyat önizleme satırı dar ekranda taşıyor | widget |
| E2E koşusu ortak kurum dizinine test verisi bırakıyor | API/RLS (kendi denetimi) |
| Türkçe CSV Windows-1254'tür; UTF-8 okununca `ı ş ğ` bozuluyor | birim (test yazarken) |
| Önizle butonu uzun ekranda görünür alanın dışında kalıyor | widget |
| Cari satırındaki rozetler `ListTile.trailing`'e sığmıyor (27px taşma) | widget |
| Portföy atama diyaloğu dar ekranda taşıyor (16px) | widget |
| **Yetki testleri yanlış sebeple geçiyordu** — aşağıya bak | e2e (gözden geçirme) |
| `AlertDialog.actions` içinde `Spacer` — `OverflowBar` ParentData hatası | widget |
| **Red gerekçesi yazılıyor ama buton açılmıyor** (`setState` yok) | widget |
| **Bakiye trigger'ı hiç çalışmıyordu** — aşağıya bak | e2e (§4.2 örneği) |
| **Bakiye avansı görmüyordu**: mahsupları topluyor, ödemeleri değil | e2e (§4.2 örneği) |
| `create_shipment` tutarsız bileşime izin veriyordu (satış hem olmuş hem borçsuz) | e2e |
| `SiparisDetay` cari id'sini taşımıyordu — teslimata sipariş id'si gidiyordu | analiz + gözden geçirme |
| Sipariş kaleminde rozetler `ListTile.trailing`'e sığmıyor (11px) | widget |
| Uzun ekranlarda test görüntü alanı — aşağıya bak | widget (yöntem) |
| Metin girilince buton aktifleşmiyor (controller dinleyicisi yok) | tarayıcıda elle |

Son satır özellikle önemli: o hata **testler değil elle tıklayarak** bulundu.
Bu paket tam olarak onun tekrarlanmaması için var.

### İki hatanın notu

**K25 iskonto zinciri** okunarak değil ölçülerek doğrulandı: eski gövde geçici
bir adla veritabanına konup aynı veriyle yan yana koşuldu. Eski hâli her iki
senaryoda da **%10** (dükkan varsayılanı) döndürüyordu — beklenen %30 ve %25
yerine. Yani anlaşılmış iskonto uygulanmıyor, müşteri fazla ödüyordu.

**`100.00 → 10000`** hatası, alanı `toStringAsFixed(2)` ile doldurup Türkçe
kuralla okumaktan çıkıyordu. Artık tek bir okuyucu var (`Fmt.sayiOku`) ve
gidiş-dönüş testi ona bağlı: `sayiOku(sayiYaz(v)) == v`.

### K8 · dönem kilidi de sınanıyor

"Kapalı döneme geriye dönük işlem girilemez" bir yorum değil, çalışan bir
trigger. E2E dönemi kapatıp yazma denemesi yapıyor:

```
✓ K8 · kapalı döneme talep GİRİLEMİYOR
✓ K8 · kapalı döneme tahsilat GİRİLEMİYOR
✓ dönem açılınca yeniden yazılabiliyor
```

### Dokümandaki işlenmiş örnek, testin kendisidir

`docs/01` §4.2 tek bir senaryoyu "şema yazarken kontrol noktası olarak
kullanılacak TEK örnek" diye tanımlıyor: Y Lisesi'ne 5 kitap, birim 100 ₺,
%20 iskonto. E2E bunu adım adım uyguluyor:

```
✓ 1-2 · fiyat 100 · iskonto %20
✓ 3 · sipariş satırı 400,00 ₺
✓ K26 · sipariş HENÜZ borç DEĞİL (bakiye 0)
✓ K26 · TESLİMATLA borç doğdu (400,00)
✓ K48 · bakiye 150,00          (250 ₺ tahsilat sonrası)
✓ K48 · ödeme durumu KISMİ (türetildi)
```

Varyantları da: kısmi teslim → 240 ₺ · konsinye → 0 ₺ · fiyat değişse damga
korunur · çek bakiyeyi düşürmez ama riske girer · avans alacak bakiye olur.

Bu örnek **iki ciddi hata** ortaya çıkardı:

**1. Bakiye trigger'ı hiç çalışmıyordu.** `trg_refresh_balance` üç tablonun
alanlarını tek bir `CASE` içinde okuyordu. plpgsql bu ifadeyi tek sorgu olarak
hazırlar ve `NEW`'in tüm alanlarını çözmeye çalışır:

```
ERROR: record "new" has no field "payment_id"
```

`shipment_items` üzerinde tetiklendiğinde `payment_allocations` dalı yüzünden
patlıyordu. Yani hiçbir teslimat, tahsilat veya iade bakiyeyi güncellemiyordu.
Bugüne kadar görünmedi çünkü ilk gerçek sevkiyat ancak Faz 4'te yazıldı.

**2. Bakiye avansı görmüyordu.** `calc_account_balance` mahsupları
(`payment_allocations`) çıkarıyordu, ödemeleri değil. Hiçbir teslimata
bağlanmayan tahsilat bakiyeye hiç yansımıyordu: 400 ₺ borca 450 ₺ ödeme
yapıldığında bakiye −50 yerine 0 çıkıyordu. Mahsup **teslimat düzeyi** ödeme
durumu içindir; **cari düzeyi** bakiye için değil — ikisi ayrı sorulardır.

### Aynı hata, ikinci kez

Projenin başında bulunan hata şuydu: *"metin girilince buton aktifleşmiyor —
controller dinleyicisi yok"*. O hata **elle tıklayarak** bulunmuştu ve bu test
paketinin var olma sebebiydi.

Talep karar ekranında aynı sınıf hata tekrar doğdu: red gerekçesi bir `Map`'e
yazılıyor ama `setState` çağrılmıyordu. Kullanıcı gerekçeyi yazar, buton kapalı
kalır, karar kaydedilemez. Bu sefer **elle değil, testle** yakalandı:

```
Expected: not null
  Actual: <null>     ← "Kararı kaydet" hâlâ kapalı
```

Paket amacına ulaştı: aynı hata ikinci kez üretime çıkmadı.

### Uzun ekranlarda test görüntü alanı

Widget testleri varsayılan 800×600'de koşar. `ListView` içindeki alt bölümler
o alanın dışında kalırsa **hiç kurulmaz** — ve `findsNothing` yanıltıcı biçimde
geçer. Yani test "bu şey yok" der, oysa yalnızca görünmüyordur.

Uzun ekranlarda görüntü alanı açıkça büyütülür:

```dart
t.view.physicalSize = const Size(1000, 2200);
t.view.devicePixelRatio = 1.0;
addTearDown(t.view.reset);
```

Alternatif `scrollUntilVisible`/`ensureVisible`; hangisi doğruysa o kullanılır —
ama sessizce geçen bir `findsNothing` bırakılmaz.

### Yanlış sebeple geçen test

E2E'de "pazarlamacı şunu yapamaz" testlerinin hepsi geçiyordu — ama yanlış
sebeple. Kullanılan pazarlamacı, daha önceki K34 testinde **pasife alınmıştı**;
yani engel *rol yetersizliği* değil *üyelik pasifliği*ydi. Rol kuralı hiç
sınanmamış oluyordu.

Fark bir hata mesajından çıktı: beklenen *"yalnızca sahip veya müdür…"* yerine
*"Cari bulunamadı veya yetkiniz yok"* dönüyordu.

Düzeltme iki parçalı:
1. Hiç pasife alınmayan ikinci bir pazarlamacı (`tokPA`) açıldı; tüm rol
   testleri ona bağlandı.
2. Yetki testleri artık yalnızca "engellendi mi" değil **engelin SEBEBİNİ** de
   doğruluyor:

```python
kontrol("pazarlamacı kredi limitini değiştiremiyor", st >= 400, r)
kontrol("engel ROLDEN kaynaklanıyor (üyelik pasifliğinden değil)",
        "sahip veya müdür" in str(r.get("message", "")), r)
```

Yanlış sebeple geçen test, geçmeyen testten daha tehlikelidir: yeşil görünür
ama hiçbir şeyi korumaz.

### K7'nin testle korunması

"Kurum düzeyinde toplam üretilmez" bir yorum satırı değil, denetlenen bir
kuraldır. Widget testi ekrandaki sayıları doğrudan sınar:

```dart
// 45.000 + 12.000 + 3.000 = 60.000 — bu sayı EKRANDA GÖRÜNMEMELİ
expect(find.textContaining('60.000,00'), findsNothing);
```

E2E tarafında da `account_detail` ve `institution_detail` çıktılarında
`toplam` adında bir alan olmadığı doğrulanıyor.

### Önizleme ile uygulamanın aynı kod olması

K49 aktarmasında `import_chunk` tek bir fonksiyondur; `p_kuru_kosu` yalnızca
**yazmayı** kapatır. Yeni/güncelleme/hata kararı her iki koşuda da aynı yerde
verilir. Ayrı bir önizleme kodu yazılsaydı, önizlemenin doğru olduğunu ancak
umut edebilirdik. E2E bunu doğrudan test eder:

```
✓ kuru koşu: 2 yeni · 1 hatalı
✓ kuru koşudan sonra katalog BOŞ
✓ gerçek koşu kuru koşuyla AYNI sonucu verdi
```

Aynı fikir istemci tarafında da var: `tr_sayi` (SQL) ile `Fmt.sayiOku` (Dart)
aynı kuralı uygular ve **iki tarafta aynı vaka tablosuyla** test edilir —
önizlemede 26,00 ₺ görünüp 2.600 ₺ kaydedilmesin diye.

## chromedriver sürüm eşleşmesi

Chrome ile chromedriver'ın **ana sürümü aynı olmak zorundadır**. Homebrew hep
en yeniyi kurar, Chrome ise bir sürüm geride kalabilir — bu durumda web
testleri sessizce başlamaz. `dogrula.sh` bunu kendisi çözer: Chrome'un ana
sürümünü okur, `.tools/chromedriver` eşleşmiyorsa Google'ın chrome-for-testing
dizininden doğrusunu indirir. `.tools/` gitignore'dadır.

## Uçtan uca testler cihazın geçmişine bağlı olamaz

Supabase oturumu **cihazda kalıcıdır**. Uygulama testte yeniden kurulsa da
oturum durur; ikinci testten itibaren uygulama doğrudan kabuğa düşer ve giriş
ekranını bekleyen testler "atlandı" olur. Sorun, testin *geçmesi* değil —
**cihazın hâline göre geçip kalması**.

`girisEkranina()` bunu kapatıyor: oturum, uygulama **kurulmadan önce** kapanır.
Ağaç ayaktayken kapatmak Riverpod'da "build sırasında setState" hatası
üretiyordu; sıra bu yüzden ağacın dışına alındı.

İkinci tuzak mobil yerleşimdi: dördüncüden sonraki ekranlar "Daha fazla"
panelindedir ve panel **kaydırılabilir** — listenin altındaki hedef ağaçta yok.
`gitEkrana()` artık hedefi görünene kadar kaydırıyor, bulamazsa panelde ne
olduğunu yazdırıyor.

## Pazarlamacı rolü ayrı bir yoldur

Uçtan uca testler yalnızca sahiple giriş yapıyordu; pazarlamacının gördüğü
ekranlar (Bugün, Rota) hiç açılmamıştı. Faz 7'nin tamamı o rolde olduğu için
`test-pazarlamaci@islerpro.local` hesabı eklendi. Portföyü **bilerek boştur**:
amaç ekranların gerçek oturumla açıldığını doğrulamak, veri üretmek değil.

## Çevrimdışı kuyruk bellekte test edilir

`test/offline/` drift'i `NativeDatabase.memory()` ile açar — gerçek dosya,
gerçek SQL, dosya sistemi yok. Sahte olan yalnızca sunucudur
(`SahteSenkronRepo`), ve o sahte **çağrı sırasını da kaydeder**: senkronun
"önce it, sonra çek" sırası bu modülün en kolay bozulan yanı, testi de tam
olarak onu tutuyor.

Widget testlerinde yerel veritabanı çoğunlukla `null` verilir; bu web'deki
gerçek yapılandırmanın aynısıdır (`ac_stub.dart`), yani test ortamı uydurma
değil.

## "Sunucu tarafı bitti" özelliğin bittiği anlamına gelmiyor

Faz 7'de `sync_push` talebi, teslimatı ve tahsilatı kabul ediyordu; uçtan uca
testler bunu belge numarası dönüşümüne kadar doğruluyordu. Buna rağmen **hiçbir
ekran o üç işlemi kuyruğa yazmıyordu** — `SahaKuyrugu` yalnızca ziyaret
akışında çağrılıyordu. Aynı biçimde cari/kurum/kişi kopyası cihaza iniyor,
okuyan yoktu. Belge de bunları "✅ kuyrukta" diye yazıyordu.

Boşluğun görünmemesinin sebebi belliydi: **hiçbir test ekranı çevrimdışı
koşturmuyordu.** Birim testi servisi tek başına doğruluyor, uçtan uca test
sunucuyu doğruluyor, ikisinin arasındaki tel hiç çekilmemiş oluyor.

`test/widgets/cevrimdisi_test.dart` tam olarak o teli sınıyor: sahte depo
`TimeoutException` fırlatıyor, gerçek bir bellek-içi drift veritabanı
`yerelDbProvider`'a veriliyor ve soru şu oluyor — **ekran yerel kopyaya düştü
mü, düştüğünü söyledi mi, kuyruğa gerçekten satır yazıldı mı?** Sahte depo
kodlu bir `PostgrestException` fırlattığında ise tersinin de doğrulanması
gerekiyor: kopya gösterilmemeli, kuyruğa yazılmamalı.

Kural olarak: bir sözleşmenin iki ucu ayrı katmanlarda test ediliyorsa,
**arada onları birbirine bağlayan bir test daha gerekir.**

## Üretilen kod

`lib/data/local/yerel_db.g.dart` drift tarafından üretilir ve **repoda durur**:
`dogrula.sh` kod üretimi çalıştırmaz, dosya olmadan `flutter test` derlenmez.
Şema değişirse yeniden üretmek gerekir:

```
dart run build_runner build
```

## Şifreleme testi pragma'ya değil dosyaya bakar

`PRAGMA cipher_version` gibi bir sorgunun cevabına güvenmek, kütüphanenin
sözüne güvenmektir. `test/offline/sifreleme_test.dart` bunun yerine **diski**
kontrol ediyor: anahtarlı yazılan dosyada `SQLite format 3\0` başlığı yok ve
ham baytlarda `Y Lisesi` da `create_payment` de geçmiyor. Ayrıca yanlış
anahtarla açılmadığı, doğru anahtarla kuyruğun geri geldiği de test ediliyor.

İlk yazımda başlık karşılaştırması METİNLE yapılmıştı ve son bayt (NUL)
yanlışlıkla boşlukla eşleştiriliyordu: kontrol **düz dosyayı "şifreli"
sayıyordu** — tam da uyarmak için var olduğu durumu kaçırıyordu. Karşılaştırma
artık bayt bazlı, ve "kontrolün kendisi çalışıyor mu" diye ayrı bir test var.

Aynı iddia gerçek cihazda da koşuyor: iOS uçtan uca testi Senkron ekranında
`ŞİFRELİ` rozetini arıyor.

## İki yerde duran tabloyu test yan yana koyar

Çekin durum geçişleri iki yerde tanımlı: sunucuda `cheque_transition_ok`,
ekranda `cekGecisleri`. Ayrışırlarsa uygulama, sunucunun reddedeceği bir
düğme gösterir — kullanıcı tıklar, hata alır, sebebini anlamaz.

E2E bu iki tabloyu **36 çiftin hepsinde** karşılaştırıyor:

```
✓ ekran ve sunucu geçiş tablosu AYNI
```

Aynı yaklaşım daha önce `tr_sayi` (SQL) ile `Fmt.sayiOku` (Dart) için de
kullanıldı. Kural iki yerde yaşamak zorundaysa, aynı olduklarını **test
söylemeli** — yorum satırı değil.

## Beklenen sayıyı testin kendisi hesaplamasın

Faz 8 e2e'si ilk koşuda üç yerde kaldı ve üçü de **testin beklediği sayı
yanlış olduğu** içindi: iadeyi 100 ₺ damgadan hesaplayacağını varsaymıştım,
oysa aynı ürünün fiyatı önceki bölümde 120 ₺'ye çıkarılmıştı. Fonksiyon
doğruydu.

Bunun dersi "sayıları testte hesaplama" değil — hesaplamak gerekiyor, yoksa
test hiçbir şey doğrulamaz. Dersi şu: **beklenen değerin nereden geldiğini
teste yazmak.** Artık satırın yanında duruyor:

```
# Çıkış 120 ₺ damgaladı: 2 × 120 × (1 − 0,20) = 192 ₺.
# Güncel fiyattan hesaplansaydı 2 × 500 × 0,80 = 800 ₺ çıkardı.
```

## Sabit tarih yazan test bir yıl sonra yalan söyler

Faz 9 e2e'si ilk koşuda üç yerde kaldı: takvim verisini `2025-11-06` gibi sabit
tarihlerle yazmıştım, "yaklaşan denemeler" ise bugünden ileriye bakıyor.
Fonksiyonlar doğruydu — test, yazıldığı gün geçerli olan bir varsayıma
dayanıyordu.

Tarihler artık **bugüne göre** kuruluyor (`bugun + 20 gün` gibi). Aynı tuzak
`notify_due_cheques` ve `escalate_stale_requests` için de geçerli: zamana bağlı
bir kuralı sabit tarihle test etmek, testi takvime bağlar.

## `pumpAndSettle`'ın ilk argümanı zaman aşımı DEĞİLDİR

Uçtan uca yardımcısı şöyleydi:

```dart
Future<void> ag(WidgetTester t) async =>
    t.pumpAndSettle(const Duration(seconds: 5));
```

O 5 saniye **kare aralığıdır**, zaman aşımı değil — gerçek zaman aşımı
varsayılan **10 dakika**. Sürekli dönen bir yükleniyor göstergesi varken tek
bir `ag()` çağrısı koşuyu on dakika kilitliyordu; testler yavaş sanılıyordu,
oysa takılıyordu.

Doğrusu: kısa aralık, **açık ve kısa zaman aşımı**, ve oturmadıysa devam et —
iddiayı zaten `bekle` kolluyor.

```dart
await t.pumpAndSettle(const Duration(milliseconds: 120),
    EnginePhase.sendSemanticsUpdate, const Duration(seconds: 8));
```

## Sahte veri gerçeğin biçimini taşımıyorsa hata görünmez

Rapor tablosunda her satırın anahtarı **ilk** kırılım sütunundan üretiliyordu.
Widget testinin sahte verisinde tek kırılım vardı ve değerleri farklıydı, o
yüzden test geçti. Gerçek cihazda `yayınevi → ürün` gibi çok seviyeli bir
kırılım açılınca aynı yayınevinin satırları aynı anahtarı aldı ve Flutter
tabloyu çizmeyi tamamen bıraktı.

Sahte veri "çalışan bir örnek" değil, **gerçeğin biçimini taşıyan** örnek
olmalı: kırılım çok seviyeli olabiliyorsa fikstürde de çok seviyeli bir satır
kümesi bulunmalı. Hata bulunduktan sonra tam olarak o biçimde bir fikstür
eklendi (`sonucCokSeviyeli`), ve düzeltme geri alınınca testin düştüğü
doğrulandı.

Aynı koşuda ikinci bir şey daha görüldü: uçtan uca test **veri dönen** bir
rapor üzerinden yazılmalı. İlk hâli `ciro` raporunu açıyordu; test kiracısında
teslimat olmadığı için rapor boştu ve test aslında "boş ekran" iddiasını
sınıyordu. `depo_sayaci` seçildi — o kiracıda 24.623 ürün var.

## Sabit süreli bekleme, iddiayı ağ hızına bağlar

Aynı hatanın ikinci yüzü: girişten sonra "giriş ekranı kayboldu mu" iddiası
sabit 8 saniyelik `ag()` ile yazılmıştı. Frankfurt turu 8 saniyeyi aştığında
test, uygulamada hiçbir şey bozuk olmadığı hâlde düşüyordu — ve düşen test
"kabuk açılmadı" diyordu, yani **yanlış yeri** gösteriyordu.

`bekle` bir hedefin gelmesini kolluyordu; eksik olan tersi. `bekleYok` bir
hedefin ağaçtan ÇIKMASINI bekliyor. Kural: **koşullu bekle, süreye güvenme.**
Süre yalnızca zaman aşımı sınırıdır, iddianın kendisi değil.

## Ağ hatası "widget bulunamadı" diye görünmesin

`signOut` yerel kapsamda bile sunucuya istek atıyor ve zaman aşımına
uğrayabiliyor. Yakalanmadığında test, giriş ekranı gelmediği için "widget
bulunamadı" diye düşüyor ve sebebini gizliyordu. Artık hata yakalanıp
oturumun gerçekten düştüğü doğrulanıyor; düşmediyse mesaj **ağ** diyor.
