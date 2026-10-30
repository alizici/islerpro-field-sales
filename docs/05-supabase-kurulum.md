# Supabase Bağlantısı

> **Durum: bağlı, şema yüklü, Frankfurt'a taşındı.**
> Proje `islerpro` · ref `xiohljzbcdzkbmqccvwc` · **eu-central-1 (Frankfurt)** · Postgres 17.
> 45 tablo · 22 enum · 17 fonksiyon · RLS aktif ve doğrulandı.
>
> Mumbai'deki ilk proje (veri yoktu, yalnızca şema) silindi; Frankfurt'ta sıfırdan kuruldu.
> Veritabanı parolası `.env.local` içinde (mod 600, gitignore'da) — sohbete hiç girmedi.

### Gecikme ölçümü — bulgu

| | Mumbai (ap-south-1) | Frankfurt (eu-central-1) |
|---|---|---|
| Sorgu (medyan, ısınmış) | **491 ms** | **341 ms** |

Taşıma **1.5 kat** kazandırdı — başlangıçta 3 kat tahmin etmiştim, **yanlıştı**.
Sebebi kırılımda görünüyor:

```
Bağlantı (TLS + ağ)  :  90 ms   ← bölge bunu etkiler, iyi durumda
Sunucu tarafı        : 251 ms   ← PostgREST + ücretsiz plan micro örneği
```

Gecikmenin çoğu **coğrafya değil, ücretsiz plandaki küçük örnek**. Yani asıl
kazanç bölgeden değil, pilota geçerken **Pro plana (daha büyük örnek)**
yükseltmekten gelecek. Bölge yine de doğru yerde artık — bunu sonradan
değiştirmek veri göçü olurdu, şimdi bedavaydı.

## Neyi kim yapıyor

| Adım | Kim |
|---|---|
| 1. Supabase projesi oluştur | **Sen** — hesap ve faturalandırma senin |
| 2. `supabase login` | **Sen** — tarayıcıda kimlik doğrulaması |
| 3. `supabase link` | **Sen** — veritabanı parolası istiyor |
| 4. Şemayı yükle (`db push`) | **Ben** |
| 5. `.env` doldur | **Sen** (2 satır) |
| 6. Uygulamayı bağla ve doğrula | **Ben** |

> **Parolayı ve `service_role` anahtarını sohbete yazma.** İhtiyacım olan tek şey
> `.env` dosyasının **dolu olduğu bilgisi** — dosyayı ben okumuyorum, uygulama okuyor.
> `anon` anahtarı zaten herkese açıktır, güvenliği RLS sağlar (0009_rls.sql).

---

## 1 · Proje oluştur  *(tamamlandı)*

[supabase.com/dashboard](https://supabase.com/dashboard) → **New project**

| Alan | Öneri |
|---|---|
| Name | `islerpro` |
| Database Password | Güçlü bir parola üret ve **parola yöneticine kaydet** |
| Region | **Frankfurt (eu-central-1)** — Türkiye'ye en düşük gecikmeli bölge |
| Plan | Free ile başlanabilir; pilot sonrası Pro |

Proje ~2 dakikada hazır olur.

---

## 2 · Şemayı yükle  *(tamamlandı)*

### Yol A — CLI *(önerilen; sonraki migration'lar da bu yolla gider)*

```bash
supabase login                          # tarayıcı açılır
supabase link --project-ref <PROJE_REF> # parola sorar
supabase db push                        # 9 migration sırayla uygulanır
```

`<PROJE_REF>` panelde **Project Settings → General → Reference ID** altında.

`login` ve `link` bittikten sonra **bana haber ver** — `db push` ve sonrasını ben yürütürüm.

### Yol B — SQL Editor *(CLI istemiyorsan)*

Panelde **SQL Editor → New query** → `supabase/tam-sema.sql` dosyasının tamamını
yapıştır → **Run**. Dosya 9 migration'ı doğru sırayla birleştirir (1.313 satır).

---

## 3 · Uygulamayı bağla  *(tamamlandı)*

Panelde **Project Settings → API**:

```bash
cp .env.example .env
```

`.env` içine iki değeri yaz:

```
SUPABASE_URL=https://xxxxxxxxxxxx.supabase.co
SUPABASE_ANON_KEY=eyJhbGci...
```

> `Project URL` → `SUPABASE_URL` · `anon public` → `SUPABASE_ANON_KEY`
> `service_role` anahtarına **dokunma** — mobil uygulamada asla kullanılmaz.

Çalıştır:

```bash
flutter run --dart-define-from-file=.env --dart-define=DEV_LOGIN=true
```

VS Code'da aynısı: cihazı seç, **F5**. Yapılandırmalar `.vscode/launch.json`
içinde; anahtarları oraya yazmıyoruz, `--dart-define-from-file` `.env`i
doğrudan okuyor.

`.env` yoksa uygulama çökmez — hangi değerin eksik olduğunu ve komutu söyleyen
bir ekran açılır. Giriş ekranındaki "Supabase yapılandırılmadı" kartı
kaybolursa bağlantı kurulmuş demektir.

---

## 4 · Kimlik doğrulama ayarı (Faz 1 için)

Panelde **Authentication → Providers**:

- **Phone** → aç. Türkiye için SMS sağlayıcısı gerekir (Netgsm / İleti Merkezi
  → Twilio uyumlu uç nokta veya özel bir Edge Function).
- Faz 0'ı denemek için **Email** yeterlidir; K3'ün telefon OTP akışı Faz 1'de kurulur.

---

## Karşılaşılan hata ve düzeltmesi

İlk `db push`'ta `0009_rls.sql` şu hatayı verdi:

```
ERROR: column "tenant_id" does not exist (SQLSTATE 42703)
At statement: 49
```

Sebep: `sample_limits` tablosu `tenant_id` değil `store_id` taşıyor ama
tenant bazlı politika döngüsüne konmuştu. Düzeltme:

- `sample_limits` tenant listesinden çıkarıldı, `store_id` bazlı ayrı döngüye alındı
- Tüm politikalara `drop policy if exists` eklendi → migration **yeniden çalıştırılabilir**

## Doğrulama

Şema yüklendikten sonra kontrol:

```sql
select count(*) as tablo from information_schema.tables where table_schema='public';
-- beklenen: 45

select count(*) as politika from pg_policies where schemaname='public';
-- RLS politikaları (0009) — sıfırdan büyük olmalı

select count(*) as fonksiyon from information_schema.routines
where routine_schema='public' and routine_type='FUNCTION';
-- beklenen: 17
```

### Yapılan doğrulamalar

| Kontrol | Sonuç |
|---|---|
| 45 tablo REST üzerinden erişilebilir | ✓ 45/45 |
| Anonim yazma engelleniyor (RLS) | ✓ `tenants`, `accounts`, `products`, `institution_contacts` |
| `line_total(100, 0.20, 5)` | ✓ `400.00` — §4.2'deki işlenmiş örnekle birebir |
| `line_total(37.45, 0.17, 7)` | ✓ `217.58` — ara sonuç yuvarlanmıyor (V8). Yuvarlasaydı 217.56 çıkardı |
| `calc_account_balance` boş cari | ✓ `0` |
| `open_consignment` boş cari | ✓ `0` |
| Uygulama bağlantısı | ✓ "Supabase yapılandırılmadı" kartı kayboldu |
