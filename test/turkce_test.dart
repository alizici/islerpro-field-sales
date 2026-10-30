import 'package:flutter_test/flutter_test.dart';
import 'package:islerpro/shared/formatters/turkce.dart';

/// Regresyon: Dart'ın toUpperCase()'i Türkçe'de yanlış sonuç veriyordu.
/// Bu hata uygulamadaki bütün büyük harf etiketlerini etkiliyordu.
void main() {
  group('Türkçe büyük harf', () {
    test('i → İ (dotless I hatası)', () {
      expect('Aktif'.buyuk, 'AKTİF');
      expect('Navigasyon'.buyuk, 'NAVİGASYON');
      expect('Ciro'.buyuk, 'CİRO');
      expect('İlçe'.buyuk, 'İLÇE');
      expect('Teslimat'.buyuk, 'TESLİMAT');
    });

    test('ı → I korunur', () {
      expect('Kapalı'.buyuk, 'KAPALI');
      expect('Planlandı'.buyuk, 'PLANLANDI');
      expect('Hazırlık'.buyuk, 'HAZIRLIK');
    });

    test('diğer Türkçe harfler bozulmuyor', () {
      expect('Dükkan'.buyuk, 'DÜKKAN');
      expect('Öğretmen'.buyuk, 'ÖĞRETMEN');
      expect('Şube'.buyuk, 'ŞUBE');
      expect('Çek'.buyuk, 'ÇEK');
    });

    test('Dart varsayılanı gerçekten yanlış (hatanın kanıtı)', () {
      expect('Aktif'.toUpperCase(), 'AKTIF');
      expect('Aktif'.buyuk, isNot('Aktif'.toUpperCase()));
    });
  });

  group('Türkçe küçük harf', () {
    test('I → ı, İ → i', () {
      expect('KAPALI'.kucuk, 'kapalı');
      expect('AKTİF'.kucuk, 'aktif');
      expect('İŞLER'.kucuk, 'işler');
    });
  });

  test('başlık biçimi', () {
    expect('İŞLER YAYINLARI'.baslikBicimi, 'İşler Yayınları');
    expect('mahmut kaya'.baslikBicimi, 'Mahmut Kaya');
  });
}
