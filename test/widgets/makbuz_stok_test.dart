import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:islerpro/core/auth/session.dart';
import 'package:islerpro/core/test_keys.dart';
import 'package:islerpro/data/repositories/katalog_repository.dart';
import 'package:islerpro/data/repositories/rapor_repository.dart';
import 'package:islerpro/data/repositories/siparis_repository.dart';
import 'package:islerpro/features/accounts/presentation/ekstre_ekrani.dart';
import 'package:islerpro/features/collections/presentation/makbuz_ekrani.dart';
import 'package:islerpro/features/reports/presentation/rapor_ekrani.dart';
import 'package:islerpro/features/reports/presentation/raporlar_ekrani.dart';

import 'sahte_depolar.dart';

/// B1 · makbuz fatura DEĞİLDİR (K26)
/// K29 · ekstre bakiye türetimini görünür kılar
/// K27 · K45 · stok bir sayaçtır, defter değildir
void main() {
  Future<void> ac(WidgetTester t, Widget w,
      {SahteSiparisRepo? siparis, SahteKatalogRepo? katalog}) async {
    t.view.physicalSize = const Size(1000, 2200);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [
        siparisRepositoryProvider.overrideWithValue(
            siparis ?? SahteSiparisRepo()),
        katalogRepositoryProvider.overrideWithValue(
            katalog ?? SahteKatalogRepo()),
        sessionProvider.overrideWithValue(testOturumu()),
      ],
      child: MaterialApp(home: w),
    ));
    await t.pumpAndSettle();
  }

  group('B1 · makbuz', () {
    testWidgets('fatura olmadığı açıkça yazılı', (t) async {
      await ac(t, const MakbuzEkrani(tahsilatId: 'p1'),
          siparis: SahteSiparisRepo()..makbuzVerisi = {
            'id': 'p1', 'makbuz_no': 'MK-001', 'tarih': '2026-08-25',
            'tutar': 250.0, 'yontem': 'nakit', 'alan': 'Ali Veli',
            'isletme': 'İşler Yayınları', 'dukkan': {'ad': 'Merkez Şube'},
            'cari': {'unvan': 'Y Lisesi Kurumsal'}, 'kurum': 'Y Lisesi',
            'mahsuplar': [], 'dagitilmayan': 0, 'kalan_bakiye': 150.0,
          });

      expect(find.byKey(K.makbuzGovde), findsOneWidget);
      expect(find.textContaining('₺250,00'), findsOneWidget);
      expect(find.textContaining('fatura değildir'), findsOneWidget,
          reason: 'K26 · fatura kesilmiyor, bu belge onun yerine geçmez');
    });

    testWidgets('K48 · mahsup edilmeyen tutar AVANS diye açıklanır', (t) async {
      await ac(t, const MakbuzEkrani(tahsilatId: 'p1'),
          siparis: SahteSiparisRepo()..makbuzVerisi = {
            'id': 'p1', 'tarih': '2026-08-25', 'tutar': 500.0,
            'yontem': 'havale', 'alan': 'Ali', 'isletme': 'X',
            'dukkan': {'ad': 'Merkez'}, 'cari': {'unvan': 'Y Lisesi'},
            'mahsuplar': [
              {'tarih': '2026-08-20T10:00:00Z', 'tutar': 400.0,
               'durum': 'odendi'},
            ],
            'dagitilmayan': 100.0, 'kalan_bakiye': -100.0,
          });

      expect(find.textContaining('avans olarak duruyor'), findsOneWidget);
      expect(find.textContaining('FIFO'), findsOneWidget);
    });

    testWidgets('yazdırılabilir HTML üretiliyor', (t) async {
      final html = MakbuzEkrani.htmlUret({
        'makbuz_no': 'MK-7', 'tarih': '2026-08-25', 'tutar': 250.0,
        'yontem': 'nakit', 'alan': 'Ali Veli', 'isletme': 'İşler Yayınları',
        'dukkan': {'ad': 'Merkez Şube', 'ilce': 'HALİLİYE'},
        'cari': {'unvan': 'Y Lisesi'}, 'kurum': 'Y Lisesi',
        'mahsuplar': [], 'dagitilmayan': 0, 'kalan_bakiye': 150.0,
      });
      expect(html, contains('MK-7'));
      expect(html, contains('₺250,00'));
      expect(html, contains('fatura değildir'));
      expect(html, contains('@media print'),
          reason: 'tarayıcıdan yazdırılabilmeli');
    });
  });

  group('K29 · ekstre', () {
    testWidgets('bakiyenin türetildiği yazılı, hareketler listeleniyor',
        (t) async {
      await ac(t, const EkstreEkrani(cariId: 'c1', unvan: 'Y Lisesi'),
          siparis: SahteSiparisRepo()..ekstreKaydi = Ekstre(
            bakiye: 150, risk: 250, acikKonsinye: 5,
            hareketler: [
              EkstreSatiri(tur: 'teslimat', tarih: DateTime(2026, 8, 20),
                  aciklama: 'Teslimat', borc: 400, odemeDurumu: 'kismi'),
              EkstreSatiri(tur: 'tahsilat', tarih: DateTime(2026, 8, 22),
                  aciklama: 'Tahsilat · nakit', alacak: 250),
            ],
          ));

      expect(find.textContaining('hareketlerden türetilir'), findsOneWidget);
      expect(find.byKey(K.ekstreSatirlar), findsOneWidget);
      expect(find.textContaining('+₺400,00'), findsOneWidget);
      expect(find.textContaining('−₺250,00'), findsOneWidget);
      expect(find.text('Kısmi'), findsNothing,
          reason: 'ödeme durumu alt satırda birleşik gösterilir');
      expect(find.textContaining('Kısmi'), findsOneWidget);
      // Konsinye borç DEĞİLDİR
      expect(find.textContaining('borç değildir'), findsOneWidget);
    });
  });

  // K27 · K45 · K13 · K23 · stok bilgisi Faz 10'da rapor MOTORUNA taşındı;
  // ekrandaki sabit metinler katalogdaki rapor açıklamasına ve `guncel_baski`
  // sütununa dönüştü. Kural aynı yerde durmuyor ama AYNI ŞEYİ söylüyor —
  // testler onu takip etti.
  group('K27 · K45 · stok raporu', () {
    testWidgets('stokun sayaç olduğu ve siparişi engellemediği yazılı',
        (t) async {
      await raporda(t, const RaporlarEkrani(), [depoSayaciTanimi()]);
      expect(find.textContaining('SAYAÇTIR'), findsOneWidget);
      expect(find.textContaining('engellemez'), findsOneWidget);
      // K13 · takibi kapalı üründe sıfır "stok bitti" demek değil
      expect(find.textContaining('adet gösterilmez'), findsOneWidget);
    });

    testWidgets('K23 · eski baskı GÜNCEL baskıyla yan yana', (t) async {
      await raporda(t, RaporEkrani(tanim: eskiBaskiTanimi()),
          [eskiBaskiTanimi()], sonuc: eskiBaskiSonucu());

      expect(find.byKey(K.raporTablo), findsOneWidget);
      expect(find.text('Güncel baskı'), findsWidgets);
      expect(find.text('2024-25'), findsOneWidget);
      expect(find.text('2025-26'), findsOneWidget,
          reason: 'raporun değeri karşılaştırmada: elde eski var, yeni çıkmış');
      expect(find.textContaining('40'), findsWidgets);
    });
  });
}

/// Rapor motoruna bağlı ekranları açar.
Future<void> raporda(WidgetTester t, Widget w, List<RaporTanimi> katalog,
    {RaporSonucu? sonuc}) async {
  t.view.physicalSize = const Size(1200, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: [
      raporRepositoryProvider.overrideWithValue(
          SahteRaporRepo(katalogListesi: katalog, sonuc: sonuc)),
      sessionProvider.overrideWithValue(testOturumu()),
    ],
    child: MaterialApp(home: w),
  ));
  await t.pumpAndSettle();
}

RaporTanimi depoSayaciTanimi() => const RaporTanimi(
      kod: 'depo_sayaci', ad: 'Depo sayacı', grup: 'katalog',
      kaynak: 'report_stok',
      aciklama: 'K27 · K45 · Stok bir SAYAÇTIR, defter değildir: siparişi '
          'engellemez. K13 · Takibi kapalı üründe adet gösterilmez, sıfır '
          'görünmesi "stok bitti" demek değildir.',
      boyutlar: [RaporBoyutu(anahtar: 'yayinevi', ad: 'Yayınevi')],
      varsayilanKirilim: ['yayinevi'],
      olculer: [RaporOlcusu(anahtar: 'stok', ad: 'Stok')],
    );

RaporTanimi eskiBaskiTanimi() => const RaporTanimi(
      kod: 'eski_baski_stogu', ad: 'Eski baskı stoğu', grup: 'katalog',
      kaynak: 'report_stok',
      aciklama: 'K23 · Elde stoğu olan ve daha yeni baskısı bulunan ürünler.',
      boyutlar: [
        RaporBoyutu(anahtar: 'urun', ad: 'Ürün'),
        RaporBoyutu(anahtar: 'baski', ad: 'Baskı'),
        RaporBoyutu(anahtar: 'guncel_baski', ad: 'Güncel baskı'),
      ],
      varsayilanKirilim: ['urun', 'baski', 'guncel_baski'],
      olculer: [RaporOlcusu(anahtar: 'stok', ad: 'Stok')],
    );

RaporSonucu eskiBaskiSonucu() => RaporSonucu(
      kod: 'eski_baski_stogu', ad: 'Eski baskı stoğu',
      kirilim: const ['urun', 'baski', 'guncel_baski'],
      sutunlar: const [
        RaporSutunu(anahtar: 'urun', ad: 'Ürün', tip: 'metin', kirilim: true),
        RaporSutunu(anahtar: 'baski', ad: 'Baskı', tip: 'metin', kirilim: true),
        RaporSutunu(anahtar: 'guncel_baski', ad: 'Güncel baskı',
            tip: 'metin', kirilim: true),
        RaporSutunu(anahtar: 'stok', ad: 'Stok', tip: 'sayi', kirilim: false),
      ],
      satirlar: const [
        {'urun': 'TYT Matematik', 'baski': '2024-25',
         'guncel_baski': '2025-26', 'stok': 40},
      ],
      toplam: const {'stok': 40},
      kirilimSayisi: 1,
    );
