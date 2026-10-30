import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../../shared/formatters/turkce.dart';

/// K49 · Excel/CSV okuma ve sütun eşleme.
///
/// Saf mantık — ağ ve dosya sistemi yok, doğrudan test edilebilir.
class TabloVeri {
  const TabloVeri({required this.basliklar, required this.satirlar,
                   this.sayfaAdi = ''});
  final List<String> basliklar;
  final List<List<String>> satirlar;
  final String sayfaAdi;

  bool get bos => satirlar.isEmpty;
  int get satirSayisi => satirlar.length;

  /// Eşlemeye göre satırı alan adlarına çevirir. Boş hücreler atlanır ki
  /// içe aktarmada `coalesce(...)` mevcut değeri korusun.
  Map<String, dynamic> satirMap(int i, Map<String, String> eslesme) {
    final s = satirlar[i];
    final m = <String, dynamic>{'_satir': i + 2}; // 1 = başlık satırı
    for (var c = 0; c < basliklar.length && c < s.length; c++) {
      final alan = eslesme[basliklar[c]];
      if (alan == null || alan.isEmpty) continue;
      final deger = s[c].trim();
      if (deger.isEmpty) continue;
      m[alan] = deger;
    }
    return m;
  }
}

abstract final class TabloOkuyucu {
  /// .xlsx ve .csv — uzantıya göre.
  static TabloVeri oku(Uint8List bytes, String dosyaAdi) {
    final ad = dosyaAdi.kucuk;
    if (ad.endsWith('.csv') || ad.endsWith('.txt')) return _csv(bytes);
    return _xlsx(bytes);
  }

  static TabloVeri _xlsx(Uint8List bytes) {
    final kitap = Excel.decodeBytes(bytes);
    // En çok satırı olan sayfayı seç — ilk sayfa çoğu zaman kapak oluyor.
    MapEntry<String, Sheet>? secili;
    for (final e in kitap.tables.entries) {
      if (secili == null || e.value.rows.length > secili.value.rows.length) {
        secili = e;
      }
    }
    if (secili == null) return const TabloVeri(basliklar: [], satirlar: []);

    final ham = secili.value.rows;
    // Başlık satırı: dolu hücre sayısı en yüksek olan ilk 10 satırdan biri.
    var basIdx = 0, enCok = -1;
    for (var i = 0; i < ham.length && i < 10; i++) {
      final n = ham[i].where((d) => _metin(d?.value).isNotEmpty).length;
      if (n > enCok) { enCok = n; basIdx = i; }
    }

    final basliklar = <String>[];
    for (final d in ham[basIdx]) {
      basliklar.add(_metin(d?.value).trim());
    }
    while (basliklar.isNotEmpty && basliklar.last.isEmpty) {
      basliklar.removeLast();
    }

    final satirlar = <List<String>>[];
    for (var i = basIdx + 1; i < ham.length; i++) {
      final s = [for (final d in ham[i]) _metin(d?.value).trim()];
      if (s.every((x) => x.isEmpty)) continue;   // tamamen boş satır
      satirlar.add(s);
    }
    return TabloVeri(basliklar: basliklar, satirlar: satirlar,
                     sayfaAdi: secili.key);
  }

  static TabloVeri _csv(Uint8List bytes) {
    final metin = _cozumle(bytes);
    final satirlar = const LineSplitter().convert(metin)
        .where((l) => l.trim().isNotEmpty).toList();
    if (satirlar.isEmpty) return const TabloVeri(basliklar: [], satirlar: []);

    // Türkçe Excel ';' kullanır, İngilizce ','. Başlıkta hangisi çoksa o.
    final ayrac = ';'.allMatches(satirlar.first).length >=
                  ','.allMatches(satirlar.first).length ? ';' : ',';
    List<String> parcala(String l) =>
        l.split(ayrac).map((x) => x.trim().replaceAll('"', '')).toList();

    return TabloVeri(
      basliklar: parcala(satirlar.first),
      satirlar: [for (final l in satirlar.skip(1)) parcala(l)],
    );
  }

  /// Türkçe Excel CSV'yi çoğunlukla Windows-1254 ile kaydeder. UTF-8 olarak
  /// okunursa okul adlarındaki ı/ş/ğ sessizce bozulur — "KARAKÖPRÜ" yerine
  /// anlamsız karakterler geçer ve mükerrer kurum açılır.
  static String _cozumle(Uint8List bytes) {
    var b = bytes;
    if (b.length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) {
      b = Uint8List.sublistView(b, 3);           // UTF-8 BOM
    }
    final utf = utf8.decode(b, allowMalformed: true);
    if (!utf.contains('\uFFFD')) return utf;    // geçerli UTF-8
    return _cp1254(b);
  }

  /// Windows-1254 = Latin-1 + Türkçe yuvalar. Tam tablo gerekmiyor;
  /// yalnızca farklı olan konumlar.
  static const _ust = '€\u0081‚ƒ„…†‡ˆ‰Š‹Œ\u008d\u008e\u008f'
      '\u0090‘’“”•–—˜™š›œ\u009d\u009eŸ';
  static String _cp1254(Uint8List b) {
    final sb = StringBuffer();
    for (final x in b) {
      sb.writeCharCode(switch (x) {
        < 0x80 => x,
        < 0xA0 => _ust.codeUnitAt(x - 0x80),
        0xD0 => 0x011E,   // Ğ
        0xDD => 0x0130,   // İ
        0xDE => 0x015E,   // Ş
        0xF0 => 0x011F,   // ğ
        0xFD => 0x0131,   // ı
        0xFE => 0x015F,   // ş
        _ => x,           // gerisi Latin-1 ile aynı
      });
    }
    return sb.toString();
  }

  static String _metin(CellValue? v) => switch (v) {
        null => '',
        TextCellValue() => v.value.toString(),
        IntCellValue() => v.value.toString(),
        DoubleCellValue() => v.value.toString(),
        BoolCellValue() => v.value ? 'true' : 'false',
        DateCellValue() => v.asDateTimeLocal().toIso8601String().split('T').first,
        DateTimeCellValue() => v.asDateTimeLocal().toIso8601String(),
        _ => v.toString(),
      };

  /// Excel çıktısı üretir — dışa aktarma ve hata raporu için.
  static Uint8List yaz(List<String> basliklar, List<List<String>> satirlar,
      {String sayfa = 'Sayfa1'}) {
    final kitap = Excel.createExcel();
    final ad = kitap.getDefaultSheet() ?? 'Sheet1';
    kitap.rename(ad, sayfa);
    final s = kitap[sayfa];
    s.appendRow([for (final b in basliklar) TextCellValue(b)]);
    for (final r in satirlar) {
      s.appendRow([for (final h in r) TextCellValue(h)]);
    }
    return Uint8List.fromList(kitap.encode() ?? const []);
  }
}

/// Sütun adı → alan adı otomatik tahmini.
///
/// Kitapçının elindeki dosyalar tek biçimli değil ("Aktif Ürünler.xls",
/// yayınevi listeleri, kendi Excel'leri). Kullanıcıyı 12 sütunu elle
/// eşlemeye zorlamamak için tahmin ediyoruz — sonuç HER ZAMAN düzenlenebilir.
abstract final class SutunTahmini {
  static const alanlar = <String, List<String>>{
    'barkod': ['barkod', 'isbn', 'barcode', 'barkodno'],
    'ad': ['ad', 'urunadi', 'isim', 'kitapadi', 'aciklama', 'urun', 'baslik',
           'kurumadi', 'okuladi', 'denemeadi'],
    'yayinevi': ['yayinevi', 'yayin', 'yayinci', 'publisher', 'marka'],
    'urun_kod': ['urunkodu', 'urunkod', 'stokkodu', 'stokkod', 'kod'],
    'satis_fiyat': ['satisfiyati', 'satisfiyat', 'fiyat', 'birimfiyat'],
    'alis_fiyat': ['alisfiyati', 'alisfiyat', 'maliyet'],
    'varsayilan_iskonto': ['iskonto', 'indirim', 'iskontoorani'],
    'etiket_fiyat': ['etiketfiyati', 'listefiyati', 'tavsiyeedilenfiyat',
                     'etiketfiyat', 'listefiyat'],
    'stok_adedi': ['stok', 'stokadedi', 'adet', 'miktar'],
    'kategori': ['kategori', 'uruntipi', 'grup'],
    'ders': ['ders', 'brans'],
    'sinif': ['sinif', 'seviye', 'sinifduzeyi'],
    'sinav_tipi': ['sinavtipi', 'sinav'],
    'baski_etiketi': ['baski', 'baskietiketi', 'yil'],
    'katalog': ['katalog', 'tip'],
    'meb_kodu': ['mebkodu', 'kurumkodu', 'mebkod'],
    'il': ['il', 'sehir'],
    'ilce': ['ilce'],
    'kurum_tipi': ['kurumtipi'],
    'kademe': ['kademe', 'okulturu'],
    'tur': ['tur'],
    'ogrenci_sayisi': ['ogrencisayisi', 'mevcut', 'ogrenci'],
    // Deneme takvimi (K20) — kaynak Excel'in başlıkları
    'stok_tarihi': ['stoktarihi', 'stok', 'stoktarih', 'gelistarihi'],
    'uygulama_tarihi': ['uygulamatarihi', 'uygulama', 'sinavtarihi',
                        'uygulamatarih'],
    'deneme_turu': ['denemeturu', 'tur2', 'denemetipi'],
    'duzey': ['duzey', 'seviye', 'sinifduzeyi'],
    'kapsam': ['kapsam', 'icerik'],
  };

  /// Her tür yalnızca kendi alanlarını görsün — 'ad' kurumda da ürün de var.
  static const turAlanlari = <String, List<String>>{
    'urun': ['ad', 'barkod', 'urun_kod', 'yayinevi', 'kategori', 'ders',
             'sinif', 'sinav_tipi', 'etiket_fiyat', 'baski_etiketi', 'katalog'],
    'fiyat_iskonto': ['barkod', 'urun_kod', 'satis_fiyat', 'alis_fiyat',
                      'varsayilan_iskonto'],
    'stok': ['barkod', 'urun_kod', 'stok_adedi'],
    'kurum': ['ad', 'meb_kodu', 'il', 'ilce', 'kurum_tipi', 'kademe', 'tur',
              'ogrenci_sayisi'],
    // 'ad' burada DENEME ADIDIR; 'tur' sütunu kurumdaki 'tur' ile
    // karışmasın diye deneme türü ayrı adla (`deneme_turu`) eşleniyor.
    'deneme_takvimi': ['ad', 'stok_tarihi', 'uygulama_tarihi', 'yayinevi',
                       'deneme_turu', 'duzey', 'kapsam', 'kademe',
                       'sinav_tipi'],
  };

  static String _norm(String s) =>
      s.buyuk.replaceAll(RegExp(r'[^A-Z0-9ÇĞİÖŞÜ]'), '')
          .replaceAll('İ', 'I').replaceAll('Ç', 'C').replaceAll('Ğ', 'G')
          .replaceAll('Ö', 'O').replaceAll('Ş', 'S').replaceAll('Ü', 'U')
          .toLowerCase();

  /// Başlıkları alanlara eşler. Aynı alana iki başlık düşerse ilki kazanır.
  static Map<String, String> tahminEt(List<String> basliklar, String tur) {
    final izin = turAlanlari[tur] ?? const <String>[];
    final sonuc = <String, String>{};
    final kullanilan = <String>{};

    // Önce birebir eşleşme, sonra "içeriyor" — 'Satış Fiyatı' önce 'Fiyat'a
    // düşmesin diye iki tur.
    for (final tam in [true, false]) {
      for (final b in basliklar) {
        if (b.isEmpty || sonuc.containsKey(b)) continue;
        final n = _norm(b);
        if (n.isEmpty) continue;
        for (final alan in izin) {
          if (kullanilan.contains(alan)) continue;
          final adaylar = alanlar[alan] ?? const [];
          final vurdu = tam
              ? adaylar.contains(n)
              : adaylar.any((a) => n.contains(a) || a.contains(n));
          if (vurdu) {
            sonuc[b] = alan;
            kullanilan.add(alan);
            break;
          }
        }
      }
    }
    return sonuc;
  }
}
