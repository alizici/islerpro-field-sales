import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:islerpro/data/services/tablo_okuyucu.dart';

/// K49 · Dosya okuma ve sütun tahmini.
/// Kitapçının elindeki dosyalar tek biçimli değil; tahmin tutmazsa kullanıcı
/// 12 sütunu elle eşlemek zorunda kalır.
void main() {
  Uint8List csv(String s) => Uint8List.fromList(utf8.encode(s));
  /// Türkçe Excel'in ürettiği kodlama.
  Uint8List csv1254(String s) => Uint8List.fromList([
        for (final r in s.runes)
          switch (r) {
            0x011E => 0xD0, 0x0130 => 0xDD, 0x015E => 0xDE,
            0x011F => 0xF0, 0x0131 => 0xFD, 0x015F => 0xFE,
            _ => r,
          }
      ]);

  group('CSV', () {
    test('Türkçe Excel noktalı virgül kullanır', () {
      final v = TabloOkuyucu.oku(
          csv('Barkod;Ürün Adı;Fiyat\n123;Kitap A;26,50\n456;Kitap B;30'),
          'liste.csv');
      expect(v.basliklar, ['Barkod', 'Ürün Adı', 'Fiyat']);
      expect(v.satirSayisi, 2);
      expect(v.satirlar[0], ['123', 'Kitap A', '26,50']);
    });

    test('virgüllü CSV de okunur', () {
      final v = TabloOkuyucu.oku(csv('a,b\n1,2'), 'x.csv');
      expect(v.basliklar, ['a', 'b']);
      expect(v.satirlar[0], ['1', '2']);
    });

    test('Windows-1254 CSV bozulmadan okunuyor', () {
      final v = TabloOkuyucu.oku(
          csv1254('Ad;İlçe\nAkziyaret Ortaokulu;KARAKÖPRÜ\nIşık İlkokulu;SİVEREK'),
          'okullar.csv');
      expect(v.basliklar, ['Ad', 'İlçe']);
      expect(v.satirlar[0][1], 'KARAKÖPRÜ');
      expect(v.satirlar[1][0], 'Işık İlkokulu',
          reason: 'ı ve ş bozulursa mükerrer kurum açılır');
    });

    test('UTF-8 BOM atlanır', () {
      final b = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode('Ad;İl\nX;Y')]);
      final v = TabloOkuyucu.oku(b, 'x.csv');
      expect(v.basliklar, ['Ad', 'İl'], reason: 'BOM ilk başlığa yapışmamalı');
    });

    test('boş satırlar atlanır', () {
      final v = TabloOkuyucu.oku(csv('a;b\n1;2\n\n3;4\n'), 'x.csv');
      expect(v.satirSayisi, 2);
    });
  });

  group('sütun tahmini', () {
    test('ürün dosyasının sütunlarını bulur', () {
      final e = SutunTahmini.tahminEt(
          ['Barkod', 'Ürün Adı', 'Yayınevi', 'Etiket Fiyatı', 'Sınıf'], 'urun');
      expect(e['Barkod'], 'barkod');
      expect(e['Ürün Adı'], 'ad');
      expect(e['Yayınevi'], 'yayinevi');
      expect(e['Etiket Fiyatı'], 'etiket_fiyat');
      expect(e['Sınıf'], 'sinif');
    });

    test('Türkçe karakter ve boşluk farkları önemsiz', () {
      final e = SutunTahmini.tahminEt(
          ['BARKOD NO', 'urun adi', 'YAYIN EVİ'], 'urun');
      expect(e['BARKOD NO'], 'barkod');
      expect(e['urun adi'], 'ad');
      expect(e['YAYIN EVİ'], 'yayinevi');
    });

    test('"Satış Fiyatı" genel "Fiyat"a düşmez', () {
      final e = SutunTahmini.tahminEt(
          ['Barkod', 'Alış Fiyatı', 'Satış Fiyatı'], 'fiyat_iskonto');
      expect(e['Satış Fiyatı'], 'satis_fiyat');
      expect(e['Alış Fiyatı'], 'alis_fiyat');
    });

    test('tür kendi alanlarıyla sınırlı — fiyat dosyasında "ad" eşleşmez', () {
      final e = SutunTahmini.tahminEt(
          ['Barkod', 'Ürün Adı', 'Satış Fiyatı'], 'fiyat_iskonto');
      expect(e['Ürün Adı'], isNull,
          reason: 'fiyat aktarımı adı kullanmaz — yanlış eşleme kafa karıştırır');
      expect(e['Satış Fiyatı'], 'satis_fiyat');
    });

    test('aynı alana iki başlık düşerse ilki kazanır', () {
      final e = SutunTahmini.tahminEt(['Barkod', 'ISBN'], 'urun');
      expect(e.values.where((v) => v == 'barkod').length, 1);
    });

    test('tanınmayan sütun eşlenmez (elle seçilir)', () {
      final e = SutunTahmini.tahminEt(['Barkod', 'Zülbiye'], 'urun');
      expect(e['Zülbiye'], isNull);
    });
  });

  group('satır → alan eşlemesi', () {
    test('boş hücre gönderilmez (mevcut değer korunsun)', () {
      final v = TabloOkuyucu.oku(csv('Barkod;Ad;Fiyat\n123;Kitap;\n'), 'x.csv');
      final m = v.satirMap(0,
          {'Barkod': 'barkod', 'Ad': 'ad', 'Fiyat': 'etiket_fiyat'});
      expect(m['barkod'], '123');
      expect(m['ad'], 'Kitap');
      expect(m.containsKey('etiket_fiyat'), isFalse,
          reason: 'boş hücre yazılırsa mevcut fiyat silinir');
    });

    test('satır numarası Excel ile aynı (başlık 1. satır)', () {
      final v = TabloOkuyucu.oku(csv('a\n1\n2'), 'x.csv');
      expect(v.satirMap(0, {'a': 'ad'})['_satir'], 2);
      expect(v.satirMap(1, {'a': 'ad'})['_satir'], 3);
    });

    test('eşlenmemiş sütun atlanır', () {
      final v = TabloOkuyucu.oku(csv('Barkod;Zülbiye\n123;xyz'), 'x.csv');
      final m = v.satirMap(0, {'Barkod': 'barkod'});
      expect(m.keys.toSet(), {'_satir', 'barkod'});
    });
  });

  group('Excel · gerçek dosyalar', () {
    test('deneme takvimi .xlsx okunuyor', () {
      final f = File('2025-2026 İŞLER LİSE DENEME TAKVİMİ AYLIK.xlsx');
      if (!f.existsSync()) {
        markTestSkipped('kaynak dosya yok');
        return;
      }
      final v = TabloOkuyucu.oku(f.readAsBytesSync(), f.path);
      expect(v.basliklar, isNotEmpty, reason: 'başlık satırı bulunmalı');
      expect(v.satirSayisi, greaterThan(10),
          reason: 'gerçek takvimde onlarca deneme var');
    });

    test('gerçek ürün dökümü (24.632 satır) okunuyor ve eşleniyor', () {
      final f = File('veri/urunler.csv');
      if (!f.existsSync()) {
        markTestSkipped('veri/urunler.csv yok — veri/urunleri_cevir.py çalıştır');
        return;
      }
      final v = TabloOkuyucu.oku(f.readAsBytesSync(), f.path);
      expect(v.satirSayisi, greaterThan(24000));

      final urun = SutunTahmini.tahminEt(v.basliklar, 'urun');
      expect(urun['Barkod'], 'barkod');
      expect(urun['Ürün Adı'], 'ad');
      expect(urun['Yayınevi'], 'yayinevi');
      expect(urun['Kategori'], 'kategori');
      expect(urun.containsValue('satis_fiyat'), isFalse,
          reason: 'ürün geçişi fiyat yazmaz — fiyat ayrı geçiştir (K12)');

      // Aynı dosya ikinci geçişte fiyat aktarımı olarak kullanılır.
      final fiyat = SutunTahmini.tahminEt(v.basliklar, 'fiyat_iskonto');
      expect(fiyat['Barkod'], 'barkod');
      expect(fiyat['Satış Fiyatı'], 'satis_fiyat');

      final ilk = v.satirMap(0, urun);
      expect(ilk['barkod'], isNotEmpty);
      expect(ilk['ad'], isNotEmpty);
      expect(ilk['_satir'], 2);
    });

    test('yazılan Excel geri okunabiliyor (gidiş-dönüş)', () {
      final b = TabloOkuyucu.yaz(
          ['Barkod', 'Ad'], [['123', 'Kitap A'], ['456', 'Kitap B']]);
      final v = TabloOkuyucu.oku(b, 'cikti.xlsx');
      expect(v.basliklar, ['Barkod', 'Ad']);
      expect(v.satirSayisi, 2);
      expect(v.satirlar[1], ['456', 'Kitap B']);
    });
  });
}
