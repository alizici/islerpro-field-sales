import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// K42 · Yerel veritabanı anahtarı.
///
/// Anahtar cihazın KENDİ kasasında durur (iOS Keychain, Android Keystore).
/// Uygulama onu yalnızca veritabanını açarken okur; loglamaz, sunucuya
/// göndermez, yedeklemez.
///
/// **Anahtar kaybolursa veri de kaybolur.** Bu bilinçlidir: kurtarılabilir bir
/// yedek anahtar, şifrelemenin kendisini anlamsız kılardı. Kaybolan şey zaten
/// sunucudaki verinin bir kopyasıdır — tek istisna henüz yüklenmemiş kuyruktur
/// ve o yüzden kuyruk her fırsatta yüklenmeye çalışılır (bkz. `senkron.dart`).
class YerelAnahtar {
  const YerelAnahtar([this._kasa = const FlutterSecureStorage(
      // Cihaz açıldıktan sonra erişilebilir; kilitliyken erişilemez. Arka plan
      // senkronu ilk kilit açılışından sonra çalışır, önce değil.
      iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock))]);

  final FlutterSecureStorage _kasa;

  static const _ad = 'yerel_db_anahtari';

  Future<String> al() async {
    final mevcut = await _kasa.read(key: _ad);
    if (mevcut != null && mevcut.length == 64) return mevcut;
    final r = Random.secure();
    final yeni = List.generate(32, (_) => r.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    await _kasa.write(key: _ad, value: yeni);
    return yeni;
  }

  /// Cihaz iptal edilince anahtar da silinir: dosya diskte kalsa bile
  /// açılamaz hâle gelir.
  Future<void> sil() => _kasa.delete(key: _ad);
}
