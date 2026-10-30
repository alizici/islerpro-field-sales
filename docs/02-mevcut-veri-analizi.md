# Mevcut Veri Analizi — schools_rows.sql & products_insert_v2.sql

> Kaynak: mevcut Supabase şeması (`branches`, `institutions`, `products`).
> Analiz tarihi: 2026-08-25 · 755 okul · 24.632 ürün

---

## 1. Okul verisi (755 kayıt)

| Alan | Durum |
|---|---|
| `id`, `ad`, `ilce` | Dolu |
| `il` | **Sütun yok** — tüm veri Şanlıurfa merkez |
| `latitude` / `longitude` | **0 / 755 dolu** — hiç koordinat yok |
| `host` | 754/755 benzersiz slug. Bir kısmı sayısal (`775534`, `773280`) → muhtemelen **MEB kurum kodu** |
| `branch_id` | Tümü NULL |
| MEB kodu | Ayrı sütun yok |

**İlçe dağılımı:** EYYÜBİYE 324 · HALİLİYE 298 · KARAKÖPRÜ 133

**Kademe dağılımı (addan çıkarıldı):**

```
İlkokul        357  ████████████████████████
Ortaokul       183  ████████████
Lise           124  ████████
Anaokulu        69  ████
Özel Eğitim     12  █
Bilim ve Sanat   3
```

> ### BULGU 1 — İş tanımı düzeltilmeli
> Doküman "lise ve üniversite hazırlık" varsayıyordu. Gerçek okul kütlesi
> **ilkokul + ortaokul (540/755 = %72)**. Ürün verisi de doğruluyor: en kalabalık
> sınıf **8. sınıf (3.017 ürün)** — yani **LGS** en az YKS kadar önemli.
> Okul türü listesi ve ürün sınıf aralığı buna göre genişletilmeli (1-12 + mezun).

---

## 2. Ürün verisi (24.632 kayıt)

Mevcut sütunlar: `branch_id · urun_tipi · barkod · urun_kod · ad · satis_fiyat · yayinevi · aktif`

### BULGU 2 — `urun_tipi` dört ayrı boyutu tek sütunda karıştırıyor
*(Tespit doğru, ama K16 gereği **düzeltilmiyor** — etiket olarak aynen taşınıyor.)*

| Değer | Adet | Aslında ne? |
|---|---|---|
| Genel | 14.162 | **Sınıflanmamış** — gerçek bir tip değil |
| İşler Yayınlar | 4.172 | **Marka** (kendi yayıneviniz) → `yayinevi` olmalı |
| Denemeler | 3.395 | Gerçek ürün tipi |
| Soru Bankası | 1.443 | Gerçek ürün tipi |
| Toptan Grubu | 1.432 | **Satış kanalı** → etiket olmalı |
| Gider Kalemleri | 28 | **Ürün değil** — yakıt, kira, elektrik, çay-şeker, kargo |

Ayrıştırma:
```
urun_tipi ──┬─► product_type   : kitap | deneme | soru_bankasi | set | dijital
            ├─► publisher_id   : "İşler Yayınlar" → yayınevi kaydı
            ├─► tags[]         : "toptan"
            └─► ✂ AYIKLA       : Gider Kalemleri (28) ürün tablosuna girmez
```

### BULGU 3 — ~~Denemelerin %44'ü yanlış tiplenmiş~~ *(geçersiz — aşağıya bak)*

| Ölçüm | Adet |
|---|---|
| `urun_tipi = 'Denemeler'` | 3.395 |
| Adında `DNM` / `DENEME` / `NxM` geçen | **6.106** |
| **Kayıp deneme** | **~2.700** (`Genel` içinde saklı) |

### BULGU 3 nasıl karara bağlandı → K15 + K16

Yukarıdaki "yanlış tiplenmiş deneme" bulgusu **geçersiz**. İşin gerçeği:

> **Katalogdaki hiçbir ürün, işletmenin "deneme"si değildir.**
> Okullara uygulanan denemeler ayrı bir iştir ve bu veride yoktur.
> Adında "DENEME" geçen kayıtlar (deneme kitapçıkları) **kitaptır**.

Buradan iki karar çıktı:

- **K15 — İki katalog.** Mevcut 24.632 kayıt tamamı `katalog = kitap`.
  Deneme kataloğu ayrıdır ve sıfırdan girilecektir.
- **K16 — Yeniden tipleme yapılmaz.** `urun_tipi` değerleri `kategori` etiketi
  olarak **olduğu gibi** taşınır. Ürün adı zaten ne olduğunu söylüyor ve
  pazarlamacı ne aradığını biliyor. Otomatik sınıflandırmanın riski
  (31 kayıtlık "DNM HEDİYE" tuzağı gibi) kazancından büyük.

Bu ikisi import'un en riskli iki adımını tamamen iptal etti.

### BULGU 4 — Yayınevi alanının %46'sı boş

- **11.280 / 24.632 ürün** yayınevisiz
- 270 ham değer → normalize edilince **239** (30 grup birleşiyor)
- Örnek çiftler: `BES KURUMSAL` \| `BES KURUMSAL YAYINLARI` · `ÇAP` \| `Çap Yayınları` ·
  `HIZ VE RENK` \| `Hız ve Renk Yayınları`
- Barkod neredeyse tam (**78 boş / 24.632**) → ISBN üzerinden yayınevi zenginleştirme mümkün

### BULGU 5 — Ürün adından otomatik çıkarım oranları

| Alan | Çıkarılabilen | Oran |
|---|---|---|
| Sınıf düzeyi | 11.049 | %45 |
| Ders / branş | 9.788 | %40 |
| Sınav tipi | 9.309 | %38 |

**Sınıf dağılımı:** 8.sınıf 3.017 · 6.sınıf 1.456 · 5.sınıf 1.335 · 7.sınıf 1.239 ·
10.sınıf 1.053 · 9.sınıf 995 · 11.sınıf 926 · 12.sınıf 43

**Sınav dağılımı:** TYT 3.779 · AYT 2.867 · KPSS 2.161 · YKS 1.803 · LGS 698 ·
DGS 271 · ALES 266 · YDT 38

> ### BULGU 6 — İkinci bir satış kanalı var
> **KPSS 2.161 + DGS 271 + ALES 266 = 2.698 ürün** okul kanalına ait değildir.
> Bunlar üniversite mezunlarına **dükkandan perakende** satılır — pazarlamacı,
> okul, öğretmen, konsinye yoktur. Doküman şu an yalnızca okul kanalını modelliyor.
> **Karara bağlanmalı** (aşağıda A11).

### BULGU 7 — Fiyat anomalileri

| Durum | Adet | Örnek |
|---|---|---|
| 0 ₺ | 136 | — |
| > 1.000 ₺ | 130 | `YKS DİL SETİ 2026` 5.000 ₺ |
| Ürün olmayan kayıt | — | `FARK FATURASI` **399.399,61 ₺** → muhasebe kalemi, ayıklanmalı |
| Dijital ürün | — | `DİJİDEMİ PLUS DOMAİN - MOBİL UYGULAMA` 25.000 ₺ → `type: dijital`, KDV %20 (V1) |

### BULGU 9 — Baskı yılı ürün adının içinde saklı

| Ölçüm | Sonuç |
|---|---|
| Adında baskı yılı olan | **11.375 / 24.632 (%46)** |
| Kalıplar | `2024` (6.640) · `2024-25` (2.497) · `-23-24` (2.205) · `2025-2026` (33) |
| Aynı eserin birden çok baskısı | **766 eser · 2.537 ürün** |
| Yeni/eski baskı fiyat oranı | **medyan 1.40x** · en uç 11.9x |

```
«09.SINIF HIZ ve RENK HİT S.B. BİYOLOJİ»
   2024      169,00 ₺
   2024-25   219,00 ₺
   2025-26   329,00 ₺   ← güncel
```

**Elenen sinyal:** `*` ön eki (1.629 kayıt) eski baskıyı işaret ediyor gibiydi.
Çok baskılı eserlerde test edildi: **%56 tutarlı, %40 karışık** → kullanılmıyor.

→ **K23**: her baskı ayrı üründür, ama bağlantı **import'ta kurulmaz**.
Addaki yıl bir yazım alışkanlığıdır, veri değildir (%46'sında var, kalıpları
tutarsız). Baskı ilişkisi **"Yeni baskı ekle" eylemiyle** insan tarafından kurulur.
Yukarıdaki sayılar baskı takibinin **değerini** gösterir, otomatik gruplamanın
gerekçesi değildir.

### BULGU 8 — İskonto ve alış fiyatı verisi yok

Mevcut veride yalnızca `satis_fiyat` var. **Alış/bayi fiyatı ve iskonto sütunu yok.**
Bu alanlar sıfırdan girilecek — import sonrası toplu düzenleme ekranı gerekir
(yayınevi bazlı toplu iskonto atama).

---

## 3. Ürün kartı tasarımı

İstenen alanlar (ad · yayınevi · fiyat · iskonto) iki katmana ayrılır. Sebep:
**ürün kimliği paylaşılabilir, ticari koşullar paylaşılamaz** — her dükkanın
yayıneviyle anlaşması farklıdır.

```
┌─ products ───────────────── GLOBAL (ortak katalog) ─────────────┐
│  ad · publisher_id · barkod/ISBN · urun_kod                     │
│  type: kitap|deneme|soru_bankasi|set|dijital                    │
│  sinif[] · ders · sinav_tipi · etiket_fiyat (yayınevi listesi)  │
└─────────────────────────────────────────────────────────────────┘
           │
┌─ store_products ─────────── DÜKKANA ÖZEL ───────────────────────┐
│  store_id · product_id                                          │
│  alis_fiyat · satis_fiyat · varsayilan_iskonto · aktif          │
└─────────────────────────────────────────────────────────────────┘
           │
┌─ discount_rules ─────────── CARİ TİPİNE GÖRE (K5) ──────────────┐
│  account_type: okul | ogretmen  ×  min_adet  →  iskonto_orani   │
└─────────────────────────────────────────────────────────────────┘
           │
┌─ stock_items ────────────── KONUM BAZLI (K2) ───────────────────┐
│  depo | pazarlamacı zimmeti | cari konsinyesi   ×  adet         │
└─────────────────────────────────────────────────────────────────┘
```

> **Fiyat ve iskonto asla global değildir** (K12). Aksi hâlde iki dükkanın farklı
> yayınevi anlaşması aynı satıra yazılır ve kâr marjı bozulur. Ayrıca K5 gereği
> aynı üründe kurumsal ve öğretmen iskontosu farklıdır.

---

## 4. İçe aktarma planı

K15 ve K16 sonrası plan **11 adımdan 7'ye** indi ve **onay gerektiren adım kalmadı**.

| # | Adım | Kayıt | Otomasyon |
|---|---|---|---|
| 1 | **Ayıklama** — 28 gider kalemi (yakıt, kira, çay-şeker) + `FARK FATURASI` ürün tablosuna girmez | 29 | Tam otomatik |
| 2 | **Yayınevi aktarımı** — 270 ham değer `publishers` tablosuna. 30 birleşme adayı (`ÇAP` \| `Çap Yayınları`) **öneri olarak** sunulur, zorunlu değil | 270 | Otomatik |
| 3 | **`urun_tipi` → `kategori`** — dönüşüm yok, olduğu gibi taşınır (K16) | 24.603 | Tam otomatik |
| 4 | **Ad'dan zenginleştirme** — sınıf %45 · ders %40 · sınav %38 doldurulur; çıkarılamayan **boş kalır**, zorlanmaz | ~11.000 | Otomatik, opsiyonel |
| 5 | **`store_products` üretimi** — her ürüne dükkan kartı; `satis_fiyat` taşınır, `alis_fiyat` ve `iskonto` **boş** başlar | 24.603 | Tam otomatik |
| 6 | **`stok_takibi = false`** — KPSS/DGS/ALES ürünleri (K13, hayalet stok önlemi) | 2.698 | Tam otomatik |
| 7 | **`arsivlendi = true`** — adında 2023 ve öncesi yıl geçenler (K14) | 4.689 | Tam otomatik |
| 8 | **Kurum içe aktarma** — 755 kayıt `institutions` tablosuna, hepsi **`kurum_tipi = okul`** (K18) + `il = Şanlıurfa` + kademe tespiti + `host` MEB kodu doğrulaması | 755 | Otomatik, 7 belirsiz kayıt manuel |

**Import sonrası tek manuel iş:** `alis_fiyat` ve `iskonto` alanları boş gelir
(mevcut veride yok). Bunun için **yayınevi bazlı toplu düzenleme ekranı** gerekir —
"Bilgi Sarmal'ın tüm ürünlerine %35 iskonto" gibi tek hamlede atama. Faz 2 kapsamında.

**Deneme kataloğu** (K17) ve **özel kurs merkezleri** (K18) bu import'un dışındadır — ikisi de elle girilir, sayıları azdır.

## 5. Bu analizden doğan açık sorular

| # | Soru | Durum |
|---|---|---|
| A11 | Perakende satış kapsamda mı? | **Kapatıldı → K13: kapsam dışı.** 2.698 KPSS/DGS/ALES ürünü `stok_takibi = false` ile aktarılır |
| A12 | `host` alanı MEB kurum kodu mu? | **Açık** — import sırasında doğrulanacak |
| A13 | Eski ürünler ne olsun? | **Kapatıldı → K14: arşivlenir.** 4.689 kayıt `arsivlendi = true` |

---

## Göç sonucu (25 Ağustos 2026)

24.632 satırlık `products_insert_v2.sql`, **uygulamanın kendi toplu aktarma
motoruyla** (K49) İşler Yayınları Kitap / Merkez Şube'ye aktarıldı. Ayrı bir
göç scripti yazılmadı: `veri/goc.py` yalnızca ekranın çağırdığı RPC'leri
(`create_import_batch → import_chunk → finish_import_batch`) aynı 400'lük
parçalarla çağırır.

| | |
|---|---|
| Kaynak satır | 24.632 |
| Açılan ürün | **24.623** |
| Fiyat katmanı | **24.623** (fiyatı boş kalan: 0) |
| Açılan yayınevi | **270** |
| Hatalı satır | **1** |

**Neden 24.623, 24.632 değil:** 9 satır barkodsuzdu ve ad + yayınevi eşleşmesiyle
mevcut bir ürüne bağlandı (mükerrer kayıt açılmadı — K24'ün amacı bu).

**Tek hatalı satır:** `FARK FATURASI` (satır 14937) — barkodu, ürün kodu ve
anlamlı bir adı yok, fiyatı 399.399,61 ₺. Bu bir ürün değil, eski sistemden
gelen bir muhasebe kalemi. Katalog dışında bırakılması doğrudur.

**Geri alınabilir:** göç iki `import_batches` kaydı üretti; aktarma ekranındaki
"Geri al" düğmesi ikisini de tersine çevirir.

> **Ders:** göç sırasında ilk koşu ölmüş sanılıp ikincisi başlatıldı. Aktarma
> idempotent olduğu için veri bozulmadı (ikinci koşu 0 yeni + 24.632 güncelleme
> üretti), ama eşzamanlı iki koşu fiyat geçişinde 5 geçici "katalogda yok"
> hatası doğurdu. `veri/goc.py` başlığına uyarı eklendi.
