import 'package:intl/intl.dart';

/// V5 · Yalnızca TRY.  V8 · numeric(12,2), ROUND_HALF_UP, asla float.
abstract final class Fmt {
  static final _para = NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 2);
  static final _sayi = NumberFormat.decimalPattern('tr_TR');
  static final _tarih = DateFormat('d MMM yyyy', 'tr_TR');
  static final _tarihSaat = DateFormat('d MMM yyyy HH:mm', 'tr_TR');

  static String para(num? v) => _para.format(v ?? 0);
  static String adet(num? v) => _sayi.format(v ?? 0);
  static String yuzde(num? oran) =>
      '%${((oran ?? 0) * 100).toStringAsFixed((oran ?? 0) * 100 % 1 == 0 ? 0 : 2)}';
  static String tarih(DateTime? d) => d == null ? '—' : _tarih.format(d.toLocal());
  static String tarihSaat(DateTime? d) => d == null ? '—' : _tarihSaat.format(d.toLocal());

  /// Girdi alanına yazılacak sayı — Türkçe ondalık ayracıyla (37,45).
  ///
  /// `toStringAsFixed` nokta koyar; [sayiOku] ise Türkçede noktayı binlik
  /// ayracı sayar. İkisi karıştığında "100.00" değeri 10.000'e dönüşür —
  /// bu yüzden alanlar HER ZAMAN bu fonksiyonla doldurulur.
  static String sayiYaz(num? v, {int basamak = 2}) =>
      v == null ? '' : v.toStringAsFixed(basamak).replaceAll('.', ',');

  /// Kullanıcının yazdığı sayıyı okur. Türkçe (1.250,50) ve İngilizce (1250.50)
  /// yazımın ikisini de kabul eder — veri Excel'den de yapıştırılabiliyor (K49).
  static double? sayiOku(String? v) {
    var t = (v ?? '').trim().replaceAll(' ', '').replaceAll('₺', '');
    if (t.isEmpty) return null;
    final nokta = t.lastIndexOf('.');
    final virgul = t.lastIndexOf(',');
    if (nokta >= 0 && virgul >= 0) {
      // İkisi de varsa sonuncusu ondalık ayracıdır.
      t = virgul > nokta
          ? t.replaceAll('.', '').replaceAll(',', '.')
          : t.replaceAll(',', '');
    } else if (virgul >= 0) {
      t = t.replaceAll(',', '.');
    } else if (nokta >= 0) {
      // Yalnızca nokta belirsizdir: 1.250 binlik, 100.00 ondalık.
      // Kural: noktadan sonraki her grup tam 3 haneliyse binlik ayracıdır.
      final parca = t.split('.');
      if (parca.length > 1 && parca.skip(1).every((x) => x.length == 3)) {
        t = t.replaceAll('.', '');
      }
    }
    return double.tryParse(t);
  }
}
