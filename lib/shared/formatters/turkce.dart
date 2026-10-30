/// Türkçe'ye duyarlı harf dönüşümleri.
///
/// Dart'ın `toUpperCase()`'i değişmez kültür kullanır: `i → I`.
/// Türkçe'de doğrusu `i → İ` ve `ı → I`'dır. Uygulamadaki bütün büyük harf
/// etiketleri (sidebar başlığı, tablo sütunları, durum rozetleri) bundan
/// etkilenir — "Aktif" → "AKTIF" yerine "AKTİF" olmalı.
extension TurkceMetin on String {
  /// Türkçe büyük harf: `i → İ`, `ı → I`.
  String get buyuk => replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();

  /// Türkçe küçük harf: `I → ı`, `İ → i`.
  String get kucuk => replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();

  /// Her kelimenin ilk harfi büyük (Türkçe kurallarıyla).
  String get baslikBicimi => split(' ')
      .map((k) => k.isEmpty ? k : k.substring(0, 1).buyuk + k.substring(1).kucuk)
      .join(' ');
}
