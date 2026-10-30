import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:islerpro/core/auth/session.dart';
import 'package:islerpro/core/test_keys.dart';
import 'package:islerpro/data/local/yerel_saglayici.dart';
import 'package:islerpro/data/repositories/ticari_repository.dart';
import 'package:islerpro/features/commercial/presentation/iade_diyalogu.dart';
import 'package:islerpro/features/commercial/presentation/konsinye_ekrani.dart';
import 'package:islerpro/features/commercial/presentation/konsinye_kapatma_ekrani.dart';
import 'package:islerpro/features/commercial/presentation/vade_takvimi_ekrani.dart';

import 'sahte_depolar.dart';

/// Faz 8 · Ticari.
///
/// Buradaki testlerin ortak derdi: **para hareketinin ne zaman doğduğunu
/// ekran doğru söylüyor mu.** Çek tahsil edilince borç düşer, ciro edilince
/// düşer, karşılıksız çıkınca geri gelir; konsinyeden satılan borç doğurur,
/// geri alınan doğurmaz. Kullanıcı bunu tıklamadan ÖNCE okuyabilmeli.
void main() {
  Future<SahteTicariRepo> ac(WidgetTester t, Widget w,
      {SahteTicariRepo? repo, AppRole rol = AppRole.isletmeSahibi}) async {
    final r = repo ?? SahteTicariRepo();
    t.view.physicalSize = const Size(1000, 2400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [
        ticariRepositoryProvider.overrideWithValue(r),
        sessionProvider.overrideWithValue(testOturumu(rol: rol)),
        yerelDbProvider.overrideWithValue(null),
      ],
      child: MaterialApp(home: w),
    ));
    await t.pumpAndSettle();
    return r;
  }

  group('Vade takvimi', () {
    testWidgets('K11 · portföydeki çekin ödeme OLMADIĞI yazılı', (t) async {
      await ac(t, const VadeTakvimiEkrani(),
          repo: SahteTicariRepo(takvim: const VadeTakvimi(portfoyde: 25000)));

      expect(find.byKey(K.vadeOzet), findsOneWidget);
      expect(find.textContaining('ödeme değil ödeme vaadidir'), findsOneWidget);
      expect(find.textContaining('25.000,00'), findsOneWidget);
    });

    testWidgets('gecikmişler takvimin ÜSTÜNDE ayrı durur', (t) async {
      await ac(t, const VadeTakvimiEkrani(),
          repo: SahteTicariRepo(takvim: VadeTakvimi(
              gecikmisTutar: 8000,
              gecikmis: [cek('Y Lisesi', tutar: 8000, gun: 12)],
              gunler: [VadeGunu(
                  tarih: DateTime(2026, 9, 1), tutar: 5000, adet: 1, gun: 6,
                  cekler: [cek('Z Ortaokulu', id: 'ch2', tutar: 5000)])])));

      expect(find.byKey(K.vadeGecikmis), findsOneWidget);
      expect(find.textContaining('12 gün gecikti'), findsOneWidget);
      expect(find.byKey(K.vadeTakvim), findsOneWidget);
    });

    testWidgets('bugün ve yarın gün sayısıyla değil ADIYLA yazılır', (t) async {
      await ac(t, const VadeTakvimiEkrani(),
          repo: SahteTicariRepo(takvim: VadeTakvimi(gunler: [
            VadeGunu(tarih: DateTime(2026, 8, 26), tutar: 1000, adet: 1,
                gun: 0, cekler: [cek('A', id: 'c1')]),
            VadeGunu(tarih: DateTime(2026, 8, 27), tutar: 2000, adet: 1,
                gun: 1, cekler: [cek('B', id: 'c2')]),
          ])));

      expect(find.textContaining('bugün'), findsOneWidget);
      expect(find.textContaining('yarın'), findsOneWidget);
      expect(find.textContaining('0 gün sonra'), findsNothing);
    });

    testWidgets('vade yoksa açıkça söylenir', (t) async {
      await ac(t, const VadeTakvimiEkrani());
      expect(find.textContaining('Yaklaşan vade yok'), findsOneWidget);
    });
  });

  group('Vade takvimi · eksik alan', () {
    testWidgets('vadesi gelmeyen alan EKRANI karartmaz', (t) async {
      // `cheque_calendar` gün gruplarında `due_date`'i göndermiyordu ve
      // zorunlu alan olduğu için tek bir çek Vadeler ekranının tamamını
      // "type 'Null' is not a subtype of type 'String'" ile boşaltıyordu.
      // Sunucu tarafı 0038'de düzeltildi; istemci de artık tek satırı
      // eksik gösterip devam ediyor.
      final ham = Cek.fromJson(const {
        'id': 'ch9',
        'unvan': 'Y Lisesi',
        'tutar': 5000,
        'durum': 'portfoyde',
        // due_date YOK
      });
      expect(ham.vade, isNull);

      await ac(t, const VadeTakvimiEkrani(),
          repo: SahteTicariRepo(takvim: VadeTakvimi(gunler: [
            VadeGunu(tarih: DateTime(2026, 9, 1), tutar: 5000, adet: 1, gun: 6,
                cekler: [ham]),
          ])));

      expect(find.text('Y Lisesi'), findsOneWidget);
      expect(find.textContaining('is not a subtype'), findsNothing);
    });
  });

  group('Çek durumu', () {
    Future<SahteTicariRepo> diyalogAc(WidgetTester t,
        {String durum = 'portfoyde', SahteTicariRepo? repo}) async {
      final r = await ac(t, const VadeTakvimiEkrani(),
          repo: repo ?? SahteTicariRepo(takvim: VadeTakvimi(
              gunler: [VadeGunu(
                  tarih: DateTime(2026, 9, 1), tutar: 5000, adet: 1, gun: 6,
                  cekler: [cek('Y Lisesi', durum: durum)])])));
      await t.tap(find.byKey(K.cekSatir('ch1')));
      await t.pumpAndSettle();
      return r;
    }

    testWidgets('yalnızca GİDİLEBİLİR durumlar gösterilir', (t) async {
      await diyalogAc(t);
      expect(find.byKey(K.cekDiyalog), findsOneWidget);
      // portfoyde → tahsilde | ciro_edildi | iade_edildi
      expect(find.byKey(K.cekDurum('tahsilde')), findsOneWidget);
      expect(find.byKey(K.cekDurum('ciro_edildi')), findsOneWidget);
      expect(find.byKey(K.cekDurum('iade_edildi')), findsOneWidget);
      // Doğrudan tahsil edilemez: önce tahsile verilir
      expect(find.byKey(K.cekDurum('tahsil_edildi')), findsNothing);
    });

    testWidgets('her seçeneğin bakiyeye ETKİSİ yazılı', (t) async {
      await diyalogAc(t, durum: 'tahsilde');
      expect(find.textContaining('Para geldi. Borç ŞİMDİ düşer'), findsOneWidget);
      expect(find.textContaining('Borç geri yazılır'), findsOneWidget);
    });

    testWidgets('terminal durumdaki çek değiştirilemez', (t) async {
      await diyalogAc(t, durum: 'tahsil_edildi');
      expect(find.byKey(K.cekDiyalog), findsNothing);
      expect(find.textContaining('değiştirilemez'), findsOneWidget);
    });

    testWidgets('ciro kime yapıldığı yazılmadan kaydedilemez', (t) async {
      await diyalogAc(t);
      await t.tap(find.byKey(K.cekDurum('ciro_edildi')));
      await t.pumpAndSettle();

      expect(find.byKey(K.cekCiroAlan), findsOneWidget);
      var b = t.widget<FilledButton>(find.byKey(K.cekOnay));
      expect(b.onPressed, isNull, reason: 'kime ciro edildiği zorunlu');

      await t.enterText(find.byKey(K.cekCiroAlan), 'Bes Yayınları');
      await t.pumpAndSettle();
      b = t.widget<FilledButton>(find.byKey(K.cekOnay));
      expect(b.onPressed, isNotNull);
    });

    testWidgets('karşılıksız gerekçe ister ve gerekçeyi iletir', (t) async {
      final r = await diyalogAc(t, durum: 'tahsilde');
      await t.tap(find.byKey(K.cekDurum('karsiliksiz')));
      await t.pumpAndSettle();

      var b = t.widget<FilledButton>(find.byKey(K.cekOnay));
      expect(b.onPressed, isNull);

      await t.enterText(find.byKey(K.cekGerekce), 'Banka: yetersiz bakiye');
      await t.pumpAndSettle();
      await t.tap(find.byKey(K.cekOnay));
      await t.pumpAndSettle();

      expect(r.cagrilar, contains('cekDurumu:ch1:karsiliksiz'));
      expect(r.sonGerekce, 'Banka: yetersiz bakiye');
    });

    testWidgets('sunucu reddederse gerekçe kullanıcıya gösterilir', (t) async {
      await diyalogAc(t,
          repo: SahteTicariRepo(
              hata: 'Çek durumu yalnızca sahip veya müdür tarafından '
                  'değiştirilebilir',
              takvim: VadeTakvimi(gunler: [VadeGunu(
                  tarih: DateTime(2026, 9, 1), tutar: 5000, adet: 1, gun: 6,
                  cekler: [cek('Y Lisesi')])])));
      await t.tap(find.byKey(K.cekDurum('tahsilde')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(K.cekOnay));
      await t.pumpAndSettle();
      expect(find.textContaining('sahip veya müdür'), findsOneWidget);
    });
  });

  group('Konsinye', () {
    testWidgets('K45 · defterinin olmadığı ekranda yazılı', (t) async {
      await ac(t, const KonsinyeEkrani(),
          repo: SahteTicariRepo(konsinyeler: [
            const KonsinyeCari(id: 'c1', unvan: 'Y Lisesi Kurumsal',
                kalanAdet: 40, kurumAd: 'Y Lisesi', pazarlamaci: 'Ali Veli'),
          ]));

      expect(find.byKey(K.konsinyeListesi), findsOneWidget);
      expect(find.textContaining('defteri yok, hareketlerden türetilir'),
          findsOneWidget);
      expect(find.text('Y Lisesi Kurumsal'), findsOneWidget);
      // Tek cari varken özet şeridi de satır da "40 adet" yazar — toplam
      // ile satırın çakışması beklenen bir şey, hata değil.
      expect(find.textContaining('40 adet'), findsWidgets);
    });

    testWidgets('açık konsinye yoksa açıkça söylenir', (t) async {
      await ac(t, const KonsinyeEkrani());
      expect(find.textContaining('Açık konsinye yok'), findsOneWidget);
    });

    testWidgets('K26 · kapanışta doğacak borç ÖNCEDEN gösterilir', (t) async {
      await ac(t,
          const KonsinyeKapatmaEkrani(cariId: 'c1', unvan: 'Y Lisesi'),
          repo: SahteTicariRepo(kalemler: [
            konsinyeKalemi('TYT Matematik', birakilan: 20),
          ]));

      expect(find.byKey(K.konsinyeOzet), findsOneWidget);
      await t.enterText(find.byKey(K.konsinyeSatildi('p1')), '5');
      await t.pumpAndSettle();

      // 100 ₺ × (1 − 0,20) × 5 = 400 ₺  (V6)
      expect(find.textContaining('400,00'), findsWidgets);
      // Kuralın kodu ('K26 ·') ekrandan kalktı — kullanıcıya bir şey
      // söylemiyordu. Kuralın KENDİSİ duruyor, düz Türkçe.
      expect(find.textContaining('Borç teslimatla doğar'), findsOneWidget);
      expect(find.textContaining('Borç doğurmaz'), findsOneWidget);
    });

    testWidgets('kalandan fazlası kapatılamaz', (t) async {
      await ac(t,
          const KonsinyeKapatmaEkrani(cariId: 'c1', unvan: 'Y Lisesi'),
          repo: SahteTicariRepo(kalemler: [
            konsinyeKalemi('TYT Matematik', birakilan: 20, satilan: 15),
          ]));

      await t.enterText(find.byKey(K.konsinyeSatildi('p1')), '9');
      await t.pumpAndSettle();
      expect(find.textContaining('Kalan 5 adetten fazlası'), findsOneWidget);
      final b = t.widget<FilledButton>(find.byKey(K.konsinyeKapat));
      expect(b.onPressed, isNull);
    });

    testWidgets('satış ve iade TEK çağrıda gider', (t) async {
      final r = await ac(t,
          const KonsinyeKapatmaEkrani(cariId: 'c1', unvan: 'Y Lisesi'),
          repo: SahteTicariRepo(kalemler: [
            konsinyeKalemi('TYT Matematik', birakilan: 20),
            konsinyeKalemi('AYT Fizik', urunId: 'p2', birakilan: 10),
          ]));

      await t.enterText(find.byKey(K.konsinyeSatildi('p1')), '5');
      await t.enterText(find.byKey(K.konsinyeIade('p2')), '3');
      await t.pumpAndSettle();
      await t.tap(find.byKey(K.konsinyeKapat));
      await t.pumpAndSettle();

      expect(r.cagrilar, contains('konsinyeKapat:1:1'),
          reason: 'ikisi ayrı gitseydi yarım kapanış mümkün olurdu');
      expect(r.sonSatilan!.single.adet, 5);
      expect(r.sonIade!.single.urunId, 'p2');
    });

    testWidgets('hiçbir şey girilmeden kapatılamaz', (t) async {
      await ac(t,
          const KonsinyeKapatmaEkrani(cariId: 'c1', unvan: 'Y Lisesi'),
          repo: SahteTicariRepo(kalemler: [konsinyeKalemi('TYT Matematik')]));
      final b = t.widget<FilledButton>(find.byKey(K.konsinyeKapat));
      expect(b.onPressed, isNull);
    });
  });

  group('İade', () {
    Future<SahteTicariRepo> iadeAc(WidgetTester t, SahteTicariRepo r) async {
      await ac(t, Builder(builder: (c) => Scaffold(
          body: Consumer(builder: (c, ref, _) => TextButton(
              onPressed: () => iadeAkisi(c, ref, 'c1', 'Y Lisesi'),
              child: const Text('aç'))))), repo: r);
      await t.tap(find.text('aç'));
      await t.pumpAndSettle();
      return r;
    }

    testWidgets('konsinyeden gelen kalem AYRI etiketlenir', (t) async {
      await iadeAc(t, SahteTicariRepo(iadeler: [
        iadeKalemi('TYT Matematik'),
        iadeKalemi('AYT Fizik', urunId: 'p2', borclandirdi: false),
      ]));

      expect(find.byKey(K.iadeDiyalog), findsOneWidget);
      expect(find.textContaining('borçtan düşer'), findsOneWidget);
      expect(find.textContaining('konsinye — borç doğmamıştı'), findsOneWidget);
    });

    testWidgets('çıkandan fazlası iade edilemez', (t) async {
      await iadeAc(t, SahteTicariRepo(
          iadeler: [iadeKalemi('TYT Matematik', cikan: 10, iade: 4)]));

      await t.enterText(find.byKey(K.iadeAdet('p1')), '9');
      await t.pumpAndSettle();
      expect(find.textContaining('en fazla 6'), findsOneWidget);
      final b = t.widget<FilledButton>(find.byKey(K.iadeOnay));
      expect(b.onPressed, isNull);
    });

    testWidgets('gerekçe zorunludur', (t) async {
      await iadeAc(t, SahteTicariRepo(iadeler: [iadeKalemi('TYT Matematik')]));
      await t.enterText(find.byKey(K.iadeAdet('p1')), '2');
      await t.pumpAndSettle();
      var b = t.widget<FilledButton>(find.byKey(K.iadeOnay));
      expect(b.onPressed, isNull, reason: 'iade sebebi olmadan kaydedilemez');

      await t.enterText(find.byKey(K.iadeGerekce), 'Hatalı baskı');
      await t.pumpAndSettle();
      b = t.widget<FilledButton>(find.byKey(K.iadeOnay));
      expect(b.onPressed, isNotNull);
    });

    testWidgets('borçlu ve konsinye kalemleri AYRI kayıtlara gider', (t) async {
      final r = await iadeAc(t, SahteTicariRepo(iadeler: [
        iadeKalemi('TYT Matematik'),
        iadeKalemi('AYT Fizik', urunId: 'p2', borclandirdi: false),
      ]));

      await t.enterText(find.byKey(K.iadeAdet('p1')), '2');
      await t.enterText(find.byKey(K.iadeAdet('p2')), '3');
      await t.enterText(find.byKey(K.iadeGerekce), 'Dönem sonu');
      await t.pumpAndSettle();
      await t.tap(find.byKey(K.iadeOnay));
      await t.pumpAndSettle();

      // Tek bir `returns` satırı ya bakiyeyi azaltır ya azaltmaz; ikisi birden
      // olamaz, bu yüzden iki ayrı kayıt.
      expect(r.cagrilar, contains('iadeAl:1:azaltir=true'));
      expect(r.cagrilar, contains('iadeAl:1:azaltir=false'));
    });

    testWidgets('iade edilebilecek ürün yoksa söylenir', (t) async {
      await iadeAc(t, SahteTicariRepo());
      // Boş durum artık sebebini de söylüyor.
      expect(find.text('İade edilebilecek ürün yok'), findsOneWidget);
      expect(find.textContaining('tamamı iade alınmış'), findsOneWidget);
    });
  });
}
