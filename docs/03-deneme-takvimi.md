# Deneme Takvimi — Analiz ve Ekran Tasarımı

> Kaynak: `2025-2026 İŞLER ORTAOKUL/LİSE DENEME TAKVİMİ AYLIK.xlsx`
> **267 deneme / yıl** — ortaokul 91, lise 176

---

## 1. Veri yapısı

Excel sütunları: `AY · STOK TARİHİ · UYGULAMA TARİHİ · YAYINEVİ · DENEME TÜRÜ ·
DÜZEY · DENEME ADI · KAPSAM`

### BULGU A — İki farklı tarih, iki farklı anlam

| Tarih | Ne demek | Doluluk | Kime lazım |
|---|---|---|---|
| **STOK TARİHİ** | Kitapçıklar dükkâna geliyor | **267/267 (%100)** | Depo, pazarlamacı, sipariş planı |
| **UYGULAMA TARİHİ** | Sınav kurumda uygulanıyor | 146/267 (%55) | Kurum, öğretmen, sevkiyat |

Stok tarihi **tek eksiksiz eksen** — takvimin omurgası bu olmalı.
Stok → uygulama farkı **en sık 7 gün** (49 kayıt), aralık 5-8 gün.

### BULGU B — Deneme türü, tarihin dolu olup olmadığını belirliyor

| Deneme türü | Tarihli | Tarihsiz | Anlamı |
|---|---|---|---|
| **TÜRKİYE GENELİ** | 47 | **0** | Ulusal, sabit tarih — tüm kurumlar **aynı gün** |
| **TAKVİM** | 75 | 97 | Yayınevi serisi — **kurum kendi programına göre** uygular |
| **DENEME KULÜBÜ** | 22 | 24 | Abonelik — kısmen sabit |
| ÖZEL ÖĞRETİM BURSLULUK / İOKBS | 2 | 0 | Resmî sınav, sabit tarih |

> Bu, ekran tasarımının temel kuralı:
> **Türkiye Geneli takvimde çivilenmiş bir etkinliktir** (kaçırılırsa telafisi yok).
> **Takvim denemesi ise bir "stokta olacak" bildirimidir** — uygulama tarihini kurum seçer.

### BULGU C — Tarih aralıkları

121 kayıtta uygulama tarihi tek gün değil **aralık**:
`29 Eylül-3 Ekim 2025` · `15-18 OCAK 2026` · `27 Nisan-1 Mayıs 2026`

Model bunu tek alanla karşılayamaz → `uygulama_baslangic` + `uygulama_bitis`
(tek günse ikisi eşit) + ham metin (`uygulama_metin`) sadakat için saklanır.

### BULGU D — Diğer eksenler

- **43 yayınevi**: BES (43) · ULTİ (23) · HIZ VE RENK (11) · İŞLEYEN ZEKA (10) ·
  FULL (10) · YAYIN DENİZİ (10) · MOZAİK (9) · ÇAP (9) — **kitap kataloğundaki
  yayınevleriyle aynı**, `publishers` tablosu ortak
- **Düzey**: TYT-AYT 69 · TYT 58 · `5-6-7-8. SINIF` 44 · `8. SINIF` 42 ·
  `9-10-11. SINIF` 27 · AYT 19 · MSÜ 2
- **Kapsam**: GENEL 139 · TARAMA 120 · konu bazlı 2
- **Aylık yoğunluk** (stok tarihi): Tem 3 · Ağu 11 · Eyl 17 · Eki 25 · **Kas 30** ·
  Ara 28 · Oca 20 · **Şub 33 · Mar 34 · Nis 33 · May 33**

Yani yoğun dönemde **ayda ~33 deneme**, güne ortalama 1-2 ama kümelenmeli.

---

## 2. Modele etkisi

### K17 revize — deneme kataloğu import edilir

"Az sayıda, elle girilir" varsayımı **yanlıştı**: yılda 267 kalem. Bu iki Excel
her yıl yeniden üretiliyor → **yıllık import** akışı gerekir, elle giriş yalnızca
sonradan eklenen/değişen kalemler için kalır.

### Yeni alanlar — `deneme_details` (K15'teki 1:1 yan tablo)

```
product_id           → products (katalog = deneme)
period_id            → K8 dönem damgası
deneme_turu          → takvim | turkiye_geneli | deneme_kulubu | resmi_sinav
kademe               → ortaokul | lise           (hangi Excel'den geldiği)
duzey                → "5-6-7-8. SINIF" | "TYT-AYT" | "8. SINIF" …
sinif[]              → [5,6,7,8]  (duzey'den ayrıştırılır, filtre için)
sinav_tipi           → LGS | TYT | AYT | MSÜ | —
kapsam               → genel | tarama | konu_bazli
stok_tarihi          → ZORUNLU (takvimin omurgası)
uygulama_baslangic   → nullable
uygulama_bitis       → nullable
uygulama_metin       → ham metin ("29 Eylül-3 Ekim 2025")
```

### Yeni tablo — `account_enrollments` (K22)

Takvimden **adet önerebilmek** için kurumun sınıf bazlı öğrenci sayısı gerekir:

```
account_id · period_id · sinif · ogrenci_sayisi
```

**Kurum değil cari bazlı** — kurumsal cari için okulun sınıf mevcutları,
öğretmen carisi için o öğretmenin kendi şube mevcutları. Böylece adet önerisi
her iki muhatap tipinde de çalışır (K5).

Örnek: `8. SINIF` denemesi için okulun 8. sınıf mevcudu → talep adedi otomatik
gelir. Bu olmadan pazarlamacı her deneme için adedi elle yazar; 33 deneme × 20 kurum
= ayda 660 manuel giriş demektir.

> `institutions.ogrenci_sayisi` tek sayı olarak kalır (kaba filtre için),
> kırılım bu tabloda tutulur.

---

## 3. Deneme Takvimi ekranı

### 3.1 Ana görünüm

```
┌─────────────────────────────────────────────────────────────┐
│  Deneme Takvimi          [ Stok tarihi ▾ ]  ‹ Kasım 2025 ›  │
│  ◉ Ortaokul  ◉ Lise   [Düzey ▾] [Yayınevi ▾] [Tür ▾]        │
│  [✓] Sadece portföyüme uygun                                │
├─────────────────────────────────────────────────────────────┤
│  Pzt   Sal   Çar   Per   Cum   Cmt   Paz                    │
│                                                             │
│    3     4     5     6     7     8     9                    │
│         ●●    ●          ▲●                                 │
│                                                             │
│   10    11    12    13    14    15    16                    │
│    ●          ▲▲●         ●●                                │
│                                            ▲ Türkiye Geneli │
│   17    18    19    20    21    22    23   ● Takvim         │
│         ●●●         ●                      ◆ Deneme Kulübü  │
└─────────────────────────────────────────────────────────────┘
```

- **Eksen değiştirici**: `Stok tarihi` ⇄ `Uygulama tarihi` (BULGU A)
- Türkiye Geneli rozetleri **her zaman öne** çıkar (kaçırılamaz)
- **Sadece portföyüme uygun**: pazarlamacının kurumlarının düzeyine uymayan
  denemeler gizlenir — ayda 33 kalemi ~10'a indirir

### 3.2 Gün detayı (mobilde alt panel, webde sağ panel)

```
┌─ 13 Kasım 2025 ─────────────────────────────────────────────┐
│  ▲ TÜRKİYE GENELİ · ALAN · TÜRKİYE GENELİ-2 · 8. SINIF      │
│    Stok: 6 Kas   Uygulama: 13-14 Kas                        │
│    ⚠ Sabit tarih — kaçırılamaz          [ Kurumlara öner ]  │
│                                                             │
│  ● TAKVİM · İŞLEYEN ZEKA · 5-6-7-8. SINIF-2                 │
│    Stok: 13 Kas   Uygulama: kurum belirler                  │
│                                        [ Kurumlara öner ]   │
└─────────────────────────────────────────────────────────────┘
```

### 3.3 "Kurumlara öner" — toplu talep oluşturma

Ekranın asıl işi bu. Bir denemeden **tek hamlede çok kuruma** talep açılır:

```
┌─ PREMİUM-2 · AV PREMİUM · 8. SINIF ─────────────────────────┐
│  Kime?                        [ Tümünü seç ]  [ Geçen sefer]│
│  ─────────────────────────────────────────────────────────  │
│  ☑ Y Lisesi — Kurumsal            8.sınıf: 180   adet [180] │
│  ☑ X Dershanesi — Kurumsal        8.sınıf:  90   adet [ 90] │
│  ☑ Ahmet Öğr. (Y Lisesi)          3 şube        adet [ 60] │
│  ☐ Z Ortaokulu — Kurumsal         8.sınıf: 120   adet [   ] │
│  ─────────────────────────────────────────────────────────  │
│  Teslim: 13 Kas   Toplam: 330 adet · 3 cari                 │
│                          [ Taslak kaydet ]  [ Talep aç → ]  │
└─────────────────────────────────────────────────────────────┘
```

Kurallar:
- Liste **portföydeki carilerden** gelir (K5) — kurumsal *ve* öğretmen carileri
- Düzey eşleşmeyen kurumlar gösterilmez (8. sınıf denemesi → lise listelenmez)
- Adet `account_enrollments`'tan **otomatik dolar** (K22'deki 4 kademeli yedek zincirle), elle değiştirilebilir
- **"Geçen sefer"** — aynı yayınevinin bir önceki denemesinde seçilen cari ve
  adetleri getirir. Deneme satışı büyük ölçüde tekrar eden bir listedir;
  bu tek düğme ayda yüzlerce dokunuş kazandırır
- Sonuç: her cari için **ayrı `request`** üretilir → normal talep akışına girer
  (durum makinesi bozulmaz), pazarlamacı toplu onaylayıp siparişe çevirir

### 3.4 Hız gereksinimleri

- **Tam offline** — 267 kayıt küçüktür, dönem başında tamamı cihaza indirilir
- Ay değiştirme yerel veriden, ağ beklemeden
- Ana sayfada **"Önümüzdeki 7 gün"** şeridi: yaklaşan stok tarihleri +
  sabit tarihli Türkiye Geneli uyarıları
- Türkiye Geneli için **T-10 gün bildirimi** — sabit tarihli sınav kaçırılamaz

---

## 4. Bu analizden doğan açık sorular

| # | Soru | Durum |
|---|---|---|
| A15 | Takvim her dükkâna aynı mı gelir? | **Kapatıldı → K21: dükkân bazlı.** Her dükkân kendi takvimini yükler |
| A16 | Sınıf mevcutları nereden gelir? | **Kapatıldı → K22: kurum bildirir** + 4 kademeli yedek zincir |
| A17 | Türkiye Geneli denemelerinde **sonuç/sıralama** bekleniyor mu? (A10 ile bağlantılı) | **Açık** — Faz 9 |


---

## 5. Uygulandığında netleşenler (Faz 9)

### Excel tarihi üç ayrı biçimde geliyor

Aynı sütunda `13.11.2025`, ISO metni ve Excel'in **seri numarası** (`45974`)
karışık çıkıyor. Üçü için ayrı kod yazmak yerine tek okuyucu (`tr_tarih`);
e2e üçünün de **aynı güne** çözüldüğünü doğruluyor. Çözülemeyen yazım sessizce
`null` olur ve ham metin `uygulama_metin`'de durur — sadakat kaybolmaz.

### Stok tarihi olmayan kalem takvime GİRMEZ

Omurga stok tarihi olduğu için tarihsiz kalemin takvimde yeri yok; import onu
hata olarak listeler. Kullanıcı satırı görür ve düzeltir — sessizce eksik bir
takvim üretmekten iyidir.

### Uygulama ekseninde tarihsizler kaybolmuyor

Uygulama tarihi yalnızca %55 dolu. Eksen "uygulama"ya çevrildiğinde tarihsiz
kalemler listeden düşmüyor, **ayrı toplanıyor**: "uygulama gününü kurum
belirler" bir eksiklik değil, BULGU B'nin ta kendisi.

### Sıfır mevcut ile bilinmeyen mevcut aynı şey değil

`set_enrollments`'ta bir sınıfa **0** yazılırsa satır **silinir**. Sıfır yazılı
kalsaydı K22'nin dört kademeli yedek zinciri devreye girmez, adet önerisi
"0 öğrenci" diye tıkanırdı.

### Hiç mevcut bildirmemiş cari öneri listesinde KALIR

Düzey süzgeci "bildirdiği sınıflar denemeyle kesişmeyen" cariyi gizler. Ama
hiç bildirmemiş cari gizlenmez — **bildirmemek eşleşmemek değildir**. Aksi
hâlde K22'yi doldurmayan kurumlar öneri listesinden kendiliğinden düşerdi.

### Toplu talep yarım kalabilir, ve bunu söyler

Bir cari düşerse (limit, kapalı cari) diğerleri açılmaya devam eder ve sonuç
**kalem kalem** gösterilir. "3 talep açıldı" demek hangi üçü olduğunu
söylemez.

### A17 hâlâ açık

Türkiye Geneli denemelerinde sonuç/sıralama beklentisi — **K40 gereği kapsam
dışı**. Faz 9 bu soruyu kapatmadı, kapsam dışı bıraktı.

## 6. Abonelik programı (C-3 · K47)

### "Teslim edildi" ELLE yazılamaz

`exam_deliveries` **yalnızca plandır**. Bir kalemi elle "teslim edildi"
işaretleyip teslimat kaydı üretmemek, borcu hiç doğmamış bir satış demek
olurdu. Bu yüzden `set_exam_delivery_status` o durumu reddediyor ve
*"teslimat girin, borç teslimattan doğar"* diyor. Durum ancak `deliver_exam`
üzerinden geçer; o da bir `shipment` üretir ve `shipments.exam_delivery_id`
ile plana bağlar. **K26 tek kural olarak kalıyor.**

### Y-8 · Mod, tarihin nereden geldiğini belirler

| Mod | Kalemler | Tarihler |
|---|---|---|
| `takvim_bagli` | Takvimden seçilir | Takvimin `uygulama_baslangic`'ı, yoksa `stok_tarihi` |
| `serbest_periyot` | Elle | `baslangic + sıra × periyot_gun` |

Türkiye Geneli **yalnızca `takvim_bagli`** modda olabilir: tarihi ulusaldır,
program periyodu onu kaydıramaz (K20). Sunucu bunu reddediyor ve sebebini
söylüyor.

### Ö-9 · Öğrenci sayısı değişikliği geriye işlemez

Program aktifken öğrenci sayısı değiştirilebilir; değişiklik **yalnızca henüz
teslim edilmemiş** kalemlere uygulanır. Teslim edilmiş kalemin adedi damgalı
kalır (K28) — geçmiş teslimatın adedi sonradan değişemez.

### İptal: plan düşer, borç durur

Program iptal edilirse teslim edilmemiş kalemler `iptal` olur; teslim
edilmişlerin borcu **durur**, çünkü o borç `shipments`'tan doğdu. Programı
kapatmak teslimatı silmez.

### Erteleme geçmişi tutulur

`onceki_tarih` + gerekçe saklanıyor. Kaçıncı kez ertelendiği görünmeden
"bu okul hep erteliyor" bilgisi kaybolurdu; dönem özeti *en az bir kez
ertelenen* kalemleri ayrı sayıyor.

### Dönem sonu özeti: anlaşılan ile gerçekleşen

`planlanan_kalem` · `teslim_edilen` · **`uygulanan`** yan yana. Üçüncüsü ayrı
duruyor çünkü K47 onu ayrı bir durum yapıyor: teslim edilmiş ama uygulanmamış
deneme sık görülür ve ikisini birleştirmek *"kaç deneme gerçekten yapıldı"*
sorusunu cevapsız bırakır. Planlanan ile uygulanan arasındaki fark, bir
sonraki dönemin anlaşmasını belirleyen tek sayıdır.

### Fiyatsız denemeden talep açılmaz

Takvim import'u ürünü katalogda açar ama **fiyat açmaz** — fiyat dükkana
özeldir (K12) ve ayrı bir aktarımla gelir. Fiyatsız üründen açılan talep
siparişe dönemez.

Bu, "Kurumlara öner" ekranında sessiz bir tuzaktı: 20 kuruma toplu talep
açılabiliyor, yirmisi de sipariş aşamasında düşüyordu. Artık iki yerde
kapatıldı:

- **Sunucu** toplu talebi reddediyor ve ne yapılacağını söylüyor:
  *"Bu denemenin dükkanınızda fiyatı yok — fiyatsız üründen açılan talep
  siparişe dönemez. Önce fiyat girin."*
- **Takvim** fiyatsız denemeyi işaretliyor ve "Öner" düğmesini kapatıyor —
  kullanıcı basıp reddedilmeyi öğrenmesin.

Aynı kural talep ekranında zaten vardı (`fiyat_durumu=fiyatli` süzgeci);
takvim yolu o süzgecin dışında kalmıştı.

## 7. Faz 9'da yapılmayanlar

`exam_results` — **kapsam dışı** (K40): optik okuma, sıralama ve karne
yapılmayacak. A17 bu yüzden kapatılmadı, kapsam dışı bırakıldı.
