# Raporlama ve İstatistik (K50)

> Tüm raporlar **tek bir motordan** üretilir: aynı filtre çerçevesi, aynı kırılım
> mantığı, aynı dışa aktarma. Rapor eklemek yeni ekran değil, katalog kaydı yazmaktır.

---

## 1. Rapor motoru

### 1.1 Ortak filtre çerçevesi

Her rapor aynı filtre setinden kendisine uyanları gösterir:

| Filtre | Değer |
|---|---|
| **Dönem** | `periods` — çoklu seçim, varsayılan aktif dönem |
| **Tarih aralığı** | Dönemden bağımsız serbest aralık |
| **Dükkan** | Sahip birden çok dükkana sahipse |
| **Pazarlamacı** | Portföy sahibi |
| **Cari tipi** | `kurum` \| `ogretmen` (K5) |
| **Kurum tipi** | `okul` \| `kurs_merkezi` · kademe · il/ilçe (K18) |
| **Ürün** | Yayınevi · kategori · sınıf · sınav tipi · katalog (kitap/deneme) |
| **Durum** | Sipariş durumu · ödeme durumu · deneme durumu |

### 1.2 Kırılım, sütun, sıralama

- **Kırılım (group by):** kullanıcı seçer — dükkan · pazarlamacı · cari · kurum ·
  yayınevi · ürün · ay · dönem. Çok seviyeli olabilir (*yayınevi → ürün*).
- **Sütunlar:** açılıp kapanabilir; seçim rapor kaydına yazılır.
- **Sıralama ve ilk-N:** *"en çok borçlu 20 cari"* gibi.

### 1.3 Kaydedilmiş raporlar

Kullanıcı bir filtre + kırılım + sütun kombinasyonunu **adlandırıp kaydeder**;
bir daha kurmak zorunda kalmaz. Kaydedilmiş rapor dükkanla paylaşılabilir.

```
saved_reports — tenant_id · store_id · ad · rapor_kodu · filtreler(jsonb)
                kirilim(jsonb) · sutunlar(jsonb) · olusturan · paylasim
```

---

## 2. Rapor kataloğu

### 2.1 Cari ve tahsilat

| Rapor | İçerik |
|---|---|
| **Borçlu cariler** | Bakiyesi olan tüm cariler; kurum/öğretmen ayrımıyla. **En çok istenen rapor** |
| **Yaşlandırma** | Borç yaşı kovaları: `0-30 · 31-60 · 61-90 · 90+ gün`. Hangi borç ne kadar bekledi |
| **Tahsilat özeti** | Dönem × yöntem (nakit/havale/kart/çek) × pazarlamacı |
| **Ödeme durumu dağılımı** | `odenmedi / kismi / odendi` teslimat sayısı ve tutarı (K48) |
| **Vadesi yaklaşan / geçen çekler** | Keşideci, banka, vade, tutar, durum (K11) |
| **Açık konsinye** | Cari bazlı kalan konsinye — türetilmiş (K45) |

### 2.2 Satış ve kârlılık

| Rapor | İçerik |
|---|---|
| **Ciro** | Dönem × dükkan × pazarlamacı × cari tipi |
| **Kurum bazlı iş hacmi** | Kurumdan çıkan toplam ciro (**alacak değil** — K7) |
| **Ürün satışı** | Hangi kitap kaç adet, hangi yayınevi, hangi sınıf |
| **Kârlılık** | `satir_tutari − (birim_maliyet × adet)` — K28'in maliyet damgası sayesinde geçmişe dönük doğru |
| **İskonto analizi** | Ortalama iskonto: pazarlamacı × cari tipi × yayınevi. Tavan aşımları ayrı |
| **Talep → sipariş dönüşümü** | Kaç talep açıldı, kaçı siparişe döndü, ne kadar sürede (K37 kalem bazlı) |

### 2.3 Saha

| Rapor | İçerik |
|---|---|
| **Pazarlamacı performansı** | Ciro · tahsilat · ziyaret sayısı · dönüşüm oranı *(prim hesabı yok — K35)* |
| **Ziyaret verimliliği** | Ziyaret başına üretilen çıktı: talep, teslimat, tahsilat (K10'un ölçütü) |
| **Portföy kapsama** | Bu dönem hiç ziyaret edilmemiş cariler — **boşluk raporu** |
| **Hazırlık süresi** | Sipariş düşmesi → "hazır" arası geçen süre, hazırlayan kişi kırılımlı (K46) |

### 2.4 Deneme

| Rapor | İçerik |
|---|---|
| **Takvim gerçekleşmesi** | Planlanan vs **uygulanan** deneme sayısı (K47). Programın yenilenip yenilenmeyeceği buna bakılarak kararlaştırılır |
| **Ertelenen denemeler** | Hangi kurum, kaç kez, gerekçeleriyle |
| **Kurum bazlı deneme adedi** | Dönem içinde kuruma giden toplam deneme |
| **Teslim edildi ama uygulanmadı** | K47'nin ayrımını işe yarar kılan rapor |

### 2.5 Katalog ve stok

| Rapor | İçerik |
|---|---|
| **Eski baskı stoğu** | Elde stoğu olan ve daha yeni baskısı bulunan ürünler (K23) — iskonto kararı için |
| **Depo sayacı** | Hafif stok görünümü; `stok_takibi = false` ürünler ayrı gösterilir (K13) |
| **Hiç satılmayan ürünler** | Dönem boyunca tek adet satılmamış kalemler |

---

## 3. Dışa aktarma

Her rapor, ekranda görüneni birebir dışarı verir.

### Excel (.xlsx)
- Ham satırlar + kırılım toplamları
- İlk sayfada **filtre özeti** (hangi dönem, hangi dükkan, hangi filtreler)
- Sütun seçimi ekrandakiyle aynı
- Sayısal alanlar sayı olarak yazılır (metin değil) — pivot çekilebilsin

### PDF
- İşletme adı, rapor adı, oluşturma tarihi, filtre özeti başlıkta
- Sayfa numarası ve tekrarlanan tablo başlığı
- Uzun tablolar bölünür, kırılım toplamları her sayfada taşınır
- **Yatay/dikey** seçimi (geniş tablolar için)

> İkisi de **aynı veri kümesinden** üretilir; Excel ile PDF asla farklı rakam göstermez.

---

## 4. İki kritik kural

### 4.1 Bakiye asla kurum düzeyinde toplanmaz (K7)

Motor bunu **zorlar**, dokümanda yazmakla bırakmaz:

```
Kırılım = kurum  +  Ölçü = bakiye/risk    →  ENGELLENIR
Kırılım = kurum  +  Ölçü = ciro/hacim     →  serbest
```

Kurum kırılımında bakiye toplamı istenirse motor uyarı verir ve carileri
**ayrı satırlar** olarak listeler. Sebep: kurum, öğretmenin borcunun kefili
değildir; toplanmış bir rakam yanlış kredi kararı doğurur.

### 4.2 Kapalı dönem özetleri kalıcı olarak saklanır

`kapali` dönemde veri değişmez (K8). Bu yüzden dönem kapandığında özetleri
**bir kez hesaplanır ve saklanır**; sonraki her çağrı hazır sonucu okur.

```
Açık dönem   → canlı hesaplanır (veri değişiyor)
Kapalı dönem → period_summaries'ten okunur (bir kez hesaplandı)
```

Yıllar geçtikçe rapor yavaşlamaz — ve bu, K8'in kapalı dönem kuralının
doğrudan kazancıdır.

---

## 5. Fazlandırma

| Ne | Faz |
|---|---|
| **Sabit çekirdek raporlar** — borçlu cariler · yaşlandırma · tahsilat özeti · basit ciro | **4** ✅ |
| **Rapor motoru** — filtre çerçevesi, kırılım, sütun seçimi, kaydedilmiş rapor | **10** ✅ |
| **Tam katalog** — §2'deki tüm raporlar | **10** ✅ (18 rapor) |
| **Excel + PDF dışa aktarma** | **10** ✅ |
| Zamanlanmış rapor (dönem sonu otomatik e-posta) | *kapsam dışı* |

---

## 6. Uygulanan hâli (Faz 10)

### 6.1 Katalog bir TABLODUR

"Rapor eklemek yeni ekran değil, katalog kaydı yazmaktır" cümlesi bir temenni
olarak kalmasın diye katalog jsonb sabiti değil gerçek bir tablo:

```
report_sources   kaynak · desteklenen süzgeçler · cari_bazli
report_dims      kaynak · anahtar · ad · SQL ifadesi
report_measures  kaynak · anahtar · ad · SQL ifadesi · tip · mali
report_defs      kod · ad · grup · kaynak · boyutlar[] · ölçüler[] · sabit süzgeç
```

Yeni rapor = `report_defs`'e bir `insert`. Ekran değişmez, Dart değişmez.
`RaporRepository`'de rapor başına metot YOKTUR ve olmamalı — olsaydı motor
motor olmazdı. Bunu widget testi kolluyor: katalogdan bir rapor çıkarılınca
ekrandan da kayboluyor.

**Dinamik SQL güvenli, çünkü kullanıcıdan gelen tek şey ANAHTAR.** İfadeler
katalog tablosundan okunur; anahtar tabloda yoksa istek reddedilir. Uçtan uca
test bunu `'; drop table accounts; --` ile deniyor.

### 6.2 Olgu görünümleri

| Görünüm | Ne sayar |
|---|---|
| `report_satis` | Teslimat SATIRLARI — ciro siparişten değil teslimattan doğar (K26). Fiyat ve maliyet satıra damgalı (K28), geçmiş rapor sonradan değişmez |
| `report_tahsilat` | Ödemeler |
| `report_cari` | Cari DURUMU — anlık fotoğraf, akış değil; bu yüzden tarih süzgeci yok |
| `report_ziyaret` | Ziyaret ve ÇIKTILARI (K10) |
| `report_deneme` | Deneme teslimleri; teslim ile uygulanan AYRI (K47) |
| `report_stok` | Stok sayacı, eski baskı karşılaştırması (K13 · K23) |

### 6.3 K7 kilidi: motor uyguluyor

Kural belgede yazmakla bırakılmadı. Mali ölçülü bir rapor (`bakiye`, `risk`,
`kredi_limiti`, `acik_konsinye`) kurum kırılımıyla istenirse motor kırılımı
**cariye çevirir ve sebebini söyler**:

> K7 · Kurum kırılımında bakiye/risk TOPLANMAZ: kurum, öğretmenin borcunun
> kefili değildir. Cariler ayrı satırlar olarak listelendi.

`kurum` bu raporların boyut listesinde **bilerek duruyor**: seçeneği gizlemek
kuralı öğretmez, yalnızca kuru bir "bu kırılım yok" hatası verir. Aynı kırılım
hacim raporunda (`kurum_hacmi`) serbesttir — orada toplanan şey alacak değil.

### 6.4 Kapalı dönem önbelleği: koşullar dar

`period_summaries`'e yazma yalnızca şu durumda yapılır: **tek bir kapalı dönem
seçili, başka hiçbir kullanıcı süzgeci yok, sayfalama varsayılan.** Aksi hâlde
saklanan özet sorulan soruya ait olmaz — *yanlış rakam, yavaş rapordan
kötüdür.* Önbellekten gelen sonuç ekranda bunu söyler.

### 6.5 Dışa aktarma: tek veri kümesi

"Excel ile PDF asla farklı rakam göstermez" iddiası yapısal olarak sağlanıyor:
ikisi de `RaporTablosu.kur()` çıktısını okur, o tablo tek yerde üretilir.

* **Excel** sayısal alanları `IntCellValue`/`DoubleCellValue` yazar — metin
  yazılsaydı pivot çekilemezdi, oysa kullanıcının dışa aktarmaktaki asıl amacı
  genelde odur. İlk sayfa künyedir: hangi rapor, hangi işletme/dükkan, ne
  zaman, hangi uyarılar.
* **PDF** gömülü **IBMPlexSans** kullanır. Paketin varsayılan Helvetica'sı
  ş/ğ/İ/ı taşımıyor ve bunları **sessizce boş kare** basıyor — Türkçe bir
  raporda kabul edilemez. Test bunu `/FontFile2` arayarak ölçüyor, umut
  ederek değil.

### 6.6 Toplam, sayfanın toplamı DEĞİLDİR

Toplam satırı ayrı bir sorguyla, sayfalama olmadan hesaplanır. "En çok borçlu
20 cari" sayfasının altındaki rakam tüm borcu gösterir; sayfa dışında kırılım
kaldıysa ekran ve künye bunu açıkça yazar (`12 / 57 kırılım`).

### 6.7 Faz 4'ün çekirdek raporları

`aging_report`, `collection_summary`, `revenue_report`, `stock_summary` SQL
tarafında **duruyor**: pilotta koşan sürüm onlara bağlı ve uçtan uca testler
onları doğruluyor. Uygulama artık motoru kullanıyor; bu RPC'lerin kaldırılması
pilot bittikten sonra yapılır.
