import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:islerpro/data/local/ac_native.dart';
import 'package:islerpro/data/local/yerel_db.dart';

/// K42 · Yerel veri şifreli mi — SÖZE değil DOSYAYA bakarak.
///
/// "Şifreli" yazan ama şifrelemeyen bir uygulama, hiç şifrelemeyenden daha
/// tehlikelidir çünkü güven verir. Bu yüzden test bir pragma'nın cevabını
/// değil, diskteki baytları kontrol ediyor.
void main() {
  late Directory dizin;
  late File dosya;

  setUp(() {
    dizin = Directory.systemTemp.createTempSync('islerpro_sifre');
    dosya = File('${dizin.path}/saha.db');
  });
  tearDown(() => dizin.deleteSync(recursive: true));

  const anahtar =
      '4f3c1a9b7e2d8065f1a4c73b9e05d28c6a1f4b83d097e2c5a6b0d3f8172e94ac';

  YerelDb ac(String? key) => YerelDb.test(NativeDatabase(dosya,
      setup: key == null ? null : (db) => anahtariUygula(db, key)));

  test('anahtarsız açılan veritabanı DÜZ sqlite dosyasıdır', () async {
    final db = ac(null);
    await db.kuyrugaYaz('create_payment', const {}, 'Y Lisesi · 250 ₺');
    await db.close();

    expect(sifreliMi(dosya), isFalse,
        reason: 'kontrolün kendisi çalışıyor mu — düz dosyayı düz görmeli');
    expect(dosya.readAsBytesSync().length, greaterThan(0));
  });

  test('anahtarlı veritabanı diskte OKUNAMAZ', () async {
    final db = ac(anahtar);
    await db.kuyrugaYaz('create_payment', const {}, 'Y Lisesi · 250 ₺');
    await db.close();

    expect(sifreliMi(dosya), isTrue,
        reason: 'dosyanın ilk 16 baytı düz sqlite başlığı olmamalı');

    // Cari adı ve tutar kişisel/ticari veridir (K44): ham baytlarda
    // görünmemeli.
    final ham = String.fromCharCodes(dosya.readAsBytesSync());
    expect(ham.contains('Y Lisesi'), isFalse);
    expect(ham.contains('create_payment'), isFalse);
  });

  test('yanlış anahtarla açılmaz', () async {
    final db = ac(anahtar);
    await db.kuyrugaYaz('create_request', const {}, 'Talep');
    await db.close();

    final yanlis = ac('a' * 64);
    await expectLater(yanlis.bekleyenSayisi(), throwsA(anything),
        reason: 'anahtarı olmayan bir cihaz veriyi okuyamamalı');
    await yanlis.close().catchError((_) {});
  });

  test('doğru anahtarla yeniden açılır', () async {
    final db = ac(anahtar);
    await db.kuyrugaYaz('create_request', const {}, 'Talep');
    await db.close();

    final tekrar = ac(anahtar);
    expect(await tekrar.bekleyenSayisi(), 1,
        reason: 'kuyruk kalıcıdır (K43) — şifreleme onu kaybettirmemeli');
    await tekrar.close();
  });
}
