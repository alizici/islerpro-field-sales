import 'package:flutter_test/flutter_test.dart';
import 'package:islerpro/shared/formatters/formatters.dart';

/// Fiyat alanlarının tek okuyucusu. Buradaki bir hata doğrudan paraya yazar:
/// "100.00" yanlış okununca ürün 10.000 ₺ olur.
void main() {
  group('Fmt.sayiOku', () {
    test('Türkçe ondalık: virgül', () {
      expect(Fmt.sayiOku('37,45'), 37.45);
      expect(Fmt.sayiOku('0,5'), 0.5);
    });

    test('İngilizce ondalık: nokta (Excel yapıştırması)', () {
      expect(Fmt.sayiOku('37.45'), 37.45);
      expect(Fmt.sayiOku('100.00'), 100.0,
          reason: 'toStringAsFixed çıktısı 10.000 olarak okunmamalı');
    });

    test('Türkçe binlik ayracı: nokta + tam 3 hane', () {
      expect(Fmt.sayiOku('1.250'), 1250);
      expect(Fmt.sayiOku('1.250.000'), 1250000);
    });

    test('ikisi birden: sonuncusu ondalık ayracıdır', () {
      expect(Fmt.sayiOku('1.250,50'), 1250.50);
      expect(Fmt.sayiOku('1,250.50'), 1250.50);
    });

    test('boş ve geçersiz girdi null döner', () {
      expect(Fmt.sayiOku(''), isNull);
      expect(Fmt.sayiOku('   '), isNull);
      expect(Fmt.sayiOku(null), isNull);
      expect(Fmt.sayiOku('abc'), isNull);
    });

    test('para simgesi ve boşluk temizlenir', () {
      expect(Fmt.sayiOku(' 37,45 ₺ '), 37.45);
    });
  });

  group('Fmt.sayiYaz ↔ sayiOku gidiş-dönüş', () {
    test('yazılan değer aynı okunur', () {
      for (final v in [0.0, 5.0, 37.45, 100.0, 1250.5, 24632.99]) {
        expect(Fmt.sayiOku(Fmt.sayiYaz(v)), v,
            reason: '$v gidiş-dönüşte bozulmamalı');
      }
    });

    test('yazım Türkçe ayraç kullanır', () {
      expect(Fmt.sayiYaz(100), '100,00');
      expect(Fmt.sayiYaz(20, basamak: 0), '20');
    });
  });
}
