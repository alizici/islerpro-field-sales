import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:islerpro/data/repositories/rapor_repository.dart';
import 'package:islerpro/data/services/rapor_disa_aktar.dart';
import 'package:islerpro/shared/formatters/formatters.dart';

/// K50 §3 · Dışa aktarma.
///
/// İki iddia sınanıyor, ikisi de belgede yazılı:
///   1. "Sayısal alanlar SAYI olarak yazılır (metin değil) — pivot çekilebilsin"
///   2. "Excel ile PDF asla farklı rakam göstermez"
///
/// İkincisi yapısal olarak sağlanıyor (ikisi de `RaporTablosu`'nu okur); test
/// o yapının bozulmadığını kolluyor.
void main() {
  final sonuc = RaporSonucu(
    kod: 'ciro', ad: 'Ciro',
    kirilim: const ['pazarlamaci'],
    sutunlar: const [
      RaporSutunu(anahtar: 'pazarlamaci', ad: 'Pazarlamacı',
          tip: 'metin', kirilim: true),
      RaporSutunu(anahtar: 'ciro', ad: 'Ciro', tip: 'para', kirilim: false),
      RaporSutunu(anahtar: 'adet', ad: 'Adet', tip: 'sayi', kirilim: false),
      RaporSutunu(anahtar: 'iskonto', ad: 'İskonto', tip: 'oran',
          kirilim: false),
    ],
    satirlar: const [
      {'pazarlamaci': 'Şükrü Çağdaş', 'ciro': 1250.5, 'adet': 40,
       'iskonto': 0.2},
      {'pazarlamaci': 'Ayşe Iğdır', 'ciro': 800.0, 'adet': 25,
       'iskonto': 0.15},
    ],
    toplam: const {'ciro': 2050.5, 'adet': 65, 'iskonto': 0.18},
    kirilimSayisi: 2,
    uretildiAt: DateTime(2026, 8, 27, 10, 30),
  );

  // Künye raporun ÜRETİLDİĞİ anı taşır, dosyanın yazıldığı anı değil:
  // geçen hafta alınmış bir rapor bugün dışa aktarılınca taze görünmemeli.
  final kunye = RaporKunyesi(
    raporAd: 'Ciro', isletme: 'İşler Yayınları', dukkan: 'Merkez Şube',
    uretildi: sonuc.uretildiAt,
    satirlar: const [('Kırılım', 'pazarlamaci')],
    uyarilar: const ['K7 · Kurum kırılımında bakiye TOPLANMAZ.'],
  );

  group('Ortak tablo', () {
    test('sayısal sütun ham SAYI kalır, biçimlenmiş metin değil', () {
      final t = RaporTablosu.kur(sonuc);
      expect(t.satirlar.first[1], 1250.5);
      expect(t.satirlar.first[2], 40);
      expect(t.satirlar.first[0], 'Şükrü Çağdaş');
    });

    test('toplam satırı kırılım sütununda BOŞ kalır', () {
      final t = RaporTablosu.kur(sonuc);
      expect(t.toplam[0], isNull, reason: 'ad toplanamaz');
      expect(t.toplam[1], 2050.5);
    });

    test('eksik değer sayısal sütunda sıfırdır, boş metin değil', () {
      final r = RaporSonucu(
        kod: sonuc.kod, ad: sonuc.ad, sutunlar: sonuc.sutunlar,
        satirlar: const [{'pazarlamaci': 'X'}], toplam: const {},
      );
      final t = RaporTablosu.kur(r);
      expect(t.satirlar.first[1], 0);
    });

    test('biçimlendirme tipine göre yapılır', () {
      expect(RaporTablosu.yaz(1250.5, 'para'), contains('1.250,50'));
      expect(RaporTablosu.yaz(0.2, 'oran'), '%20.0');
      expect(RaporTablosu.yaz(40, 'sayi'), '40');
    });
  });

  group('Excel', () {
    late Excel kitap;
    setUpAll(() => kitap = Excel.decodeBytes(
        RaporDisaAktar.excel(sonuc, kunye)));

    test('K50 · sayısal hücreler SAYI tipinde yazılır', () {
      final veri = kitap['Veri'];
      // 0. satır başlık; 1. satır ilk veri.
      expect(veri.row(1)[1]?.value, isA<DoubleCellValue>(),
          reason: 'metin yazılırsa Excel pivot çekilemez — kullanıcının '
              'dışa aktarmaktaki asıl amacı odur');
      expect(veri.row(1)[2]?.value, isA<IntCellValue>());
      expect(veri.row(1)[0]?.value, isA<TextCellValue>());
    });

    test('rakamlar rapordaki değerin AYNISI', () {
      final h = kitap['Veri'].row(1)[1]?.value as DoubleCellValue;
      expect(h.value, 1250.5);
    });

    test('ilk sayfa künyedir — hangi rapor, hangi süzgeç, ne zaman', () {
      final k = kitap['Künye'];
      final metin = [
        for (var i = 0; i < k.maxRows; i++)
          k.row(i).map((c) => c?.value?.toString() ?? '').join('|'),
      ].join('\n');
      expect(metin, contains('İşler Yayınları'));
      expect(metin, contains('Merkez Şube'));
      expect(metin, contains('Ciro'));
      expect(metin, contains('K7'), reason: 'uyarı çıktıya da taşınmalı');

      // Bu satır bir zamanlar `contains('27 Ağu 2026')` diye SABİT yazılmıştı
      // ve yalnızca yazıldığı gün geçiyordu; ertesi gün kırıldı. Doğrusu
      // raporun kendi damgasını beklemek — hem tarihten bağımsız hem de
      // asıl kuralı sınıyor.
      expect(metin, contains(Fmt.tarihSaat(sonuc.uretildiAt)));
    });

    test('künye dosyanın yazıldığı anı DEĞİL, raporun damgasını taşır', () {
      // Geçen ayın raporu bugün dışa aktarılınca bugünün tarihiyle
      // çıkarsa okuyan onu taze veri sanır.
      final eski = DateTime(2026, 3, 4, 9, 15);
      final k = RaporDisaAktar.excel(
        sonuc,
        RaporKunyesi(
          raporAd: 'Ciro', isletme: 'İşler Yayınları', dukkan: 'Merkez Şube',
          uretildi: eski,
        ),
      );
      final sayfa = Excel.decodeBytes(k)['Künye'];
      final metin = [
        for (var i = 0; i < sayfa.maxRows; i++)
          sayfa.row(i).map((c) => c?.value?.toString() ?? '').join('|'),
      ].join('\n');

      expect(metin, contains(Fmt.tarihSaat(eski)));
      expect(metin, isNot(contains(Fmt.tarihSaat(DateTime.now()))));
    });

    test('TOPLAM satırı sonda ve sayısal', () {
      final veri = kitap['Veri'];
      final son = veri.row(veri.maxRows - 1);
      expect(son[0]?.value.toString(), contains('TOPLAM'));
      expect((son[1]?.value as DoubleCellValue).value, 2050.5);
    });

    test('Türkçe karakter bozulmadan yazılır', () {
      expect(kitap['Veri'].row(1)[0]?.value.toString(), 'Şükrü Çağdaş');
      expect(kitap['Veri'].row(2)[0]?.value.toString(), 'Ayşe Iğdır');
    });
  });

  group('PDF', () {
    late final font =
        File('assets/fonts/IBMPlexSans.ttf').readAsBytesSync();

    test('geçerli bir PDF üretilir', () async {
      final b = await RaporDisaAktar.pdf(sonuc, kunye, yaziTipi: font);
      expect(String.fromCharCodes(b.take(5)), '%PDF-');
      expect(b.length, greaterThan(1000));
    });

    test('yazı tipi GÖMÜLÜR — Türkçe harfler boş kare basılmasın', () async {
      final b = await RaporDisaAktar.pdf(sonuc, kunye, yaziTipi: font);
      // PDF sözlük anahtarları sıkıştırılmış belgede bile ASCII kalır.
      final govde = String.fromCharCodes(b);
      expect(govde, contains('/FontFile2'),
          reason: 'gömülü TrueType yoksa paket Helvetica\'ya düşer ve '
              'ş/ğ/İ/ı yerine SESSİZCE boş kare basar');
    });

    test('yatay ve dikey farklı sayfa boyu üretir', () async {
      final yatay = await RaporDisaAktar.pdf(sonuc, kunye,
          yaziTipi: font, yatay: true);
      final dikey = await RaporDisaAktar.pdf(sonuc, kunye,
          yaziTipi: font, yatay: false);
      expect(yatay.length, isNot(dikey.length));
    });
  });

  group('Excel ile PDF aynı veriden', () {
    test('ikisi de RaporTablosu.kur çıktısını kullanır', () async {
      // Yapısal iddia: tablo TEK yerde üretiliyor. Bozulursa bu test değil,
      // derleme kırılır — burada tablonun beklenen içeriği sabitleniyor.
      final t = RaporTablosu.kur(sonuc);
      expect(t.basliklar, ['Pazarlamacı', 'Ciro', 'Adet', 'İskonto']);
      expect(t.sayisal, [false, true, true, true]);
      expect(t.satirlar, hasLength(2));

      final excel = Excel.decodeBytes(RaporDisaAktar.excel(sonuc, kunye));
      final satir = excel['Veri'].row(1);
      expect((satir[1]?.value as DoubleCellValue).value, t.satirlar[0][1]);
      expect((satir[2]?.value as IntCellValue).value, t.satirlar[0][2]);
    });
  });
}
