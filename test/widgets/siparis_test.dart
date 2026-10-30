import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:islerpro/core/auth/session.dart';
import 'package:islerpro/core/test_keys.dart';
import 'package:islerpro/data/repositories/siparis_repository.dart';
import 'package:islerpro/data/repositories/talep_repository.dart';
import 'package:islerpro/features/collections/presentation/tahsilat_diyalogu.dart';
import 'package:islerpro/features/collections/presentation/tahsilat_ekrani.dart';
import 'package:islerpro/features/orders/presentation/siparis_detay_ekrani.dart';
import 'package:islerpro/features/orders/presentation/siparisler_ekrani.dart';
import 'package:islerpro/features/orders/presentation/teslimat_diyalogu.dart';

import 'sahte_depolar.dart';

/// Faz 4 · K26 borç teslimatla doğar · K28 damga · K46 hazırlık · K48 parçalı
void main() {
  Future<SahteSiparisRepo> ac(WidgetTester t, Widget w,
      {SahteSiparisRepo? repo, AppRole rol = AppRole.isletmeSahibi}) async {
    final r = repo ?? SahteSiparisRepo();
    t.view.physicalSize = const Size(1000, 2200);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [
        siparisRepositoryProvider.overrideWithValue(r),
        talepRepositoryProvider.overrideWithValue(SahteTalepRepo()),
        sessionProvider.overrideWithValue(testOturumu(rol: rol)),
      ],
      child: MaterialApp(home: w),
    ));
    await t.pumpAndSettle();
    return r;
  }

  group('K46 · hazırlık akışı', () {
    testWidgets('hazırlanacaklar süzgeci depoya iletilir', (t) async {
      final repo = await ac(t, const SiparislerEkrani(),
          repo: SahteSiparisRepo(siparisler: [siparis('Y Lisesi')]));
      repo.cagrilar.clear();

      await t.tap(find.byKey(K.siparisHazirlikKutusu));
      await t.pumpAndSettle();
      expect(repo.cagrilar.any((c) => c.contains('hazirlik=true')), isTrue);
    });

    testWidgets('durum geçişleri sırayla açılır', (t) async {
      final repo = await ac(t, const SiparisDetayEkrani(siparisId: 'o1'),
          repo: SahteSiparisRepo(detayKaydi: siparisDetay(
              durum: 'olusturuldu', kalemler: [siparisKalemi('Matematik SB')])));

      expect(find.byKey(K.siparisHazirla), findsOneWidget);
      expect(find.byKey(K.siparisHazir), findsNothing,
          reason: 'hazırlığa başlamadan "Hazır" çıkmamalı');

      await t.tap(find.byKey(K.siparisHazirla));
      await t.pumpAndSettle();
      expect(repo.cagrilar, contains('durum:o1:hazirlaniyor'));
    });

    testWidgets('kim hazırladı ve ne zaman gösterilir', (t) async {
      await ac(t, const SiparisDetayEkrani(siparisId: 'o1'),
          repo: SahteSiparisRepo(detayKaydi: siparisDetay(
              hazirlayan: 'Mehmet Usta',
              kalemler: [siparisKalemi('Matematik SB')])));

      // Rozet değil kural notu: hazırlığın kime emanet olduğunu bandın
      // altında düz yazıyla söylüyor.
      expect(find.textContaining('Hazırlayan: Mehmet Usta'), findsOneWidget);
    });
  });

  group('K28 · damga', () {
    testWidgets('kalem damgalı fiyat ve iskontoyla gösterilir', (t) async {
      await ac(t, const SiparisDetayEkrani(siparisId: 'o1'),
          repo: SahteSiparisRepo(detayKaydi: siparisDetay(
              kalemler: [siparisKalemi('Matematik SB')])));

      expect(find.byKey(K.siparisKalemler), findsOneWidget);
      expect(find.textContaining('5 × ₺100,00'), findsOneWidget);
      expect(find.textContaining('%20'), findsOneWidget);
      expect(find.textContaining('katalog fiyatı değişse bu sipariş oynamaz'),
          findsOneWidget);
    });
  });

  group('K26 · borç teslimatla doğar', () {
    testWidgets('sipariş ekranında "henüz borç değil" yazar', (t) async {
      await ac(t, const SiparisDetayEkrani(siparisId: 'o1'),
          repo: SahteSiparisRepo(detayKaydi: siparisDetay(
              kalemler: [siparisKalemi('Matematik SB')])));

      expect(find.textContaining('Sipariş henüz borç değildir'), findsOneWidget);
    });

    testWidgets('teslimat diyaloğu doğacak borcu önceden söyler', (t) async {
      await ac(t, TeslimatDiyalogu(siparis: siparisDetay(
          kalemler: [siparisKalemi('Matematik SB')])));

      expect(find.textContaining('₺400,00 borç doğar'), findsOneWidget);
    });

    testWidgets('konsinye seçilince borç doğmayacağı yazar', (t) async {
      final repo = await ac(t, TeslimatDiyalogu(siparis: siparisDetay(
          kalemler: [siparisKalemi('Matematik SB')])));

      await t.tap(find.byKey(K.teslimatKonsinye));
      await t.pumpAndSettle();
      expect(find.textContaining('BORÇ DOĞMAZ'), findsOneWidget);

      await t.tap(find.byKey(K.teslimatKaydet));
      await t.pumpAndSettle();
      expect(repo.sonBorclandirir, isFalse);
    });

    testWidgets('H-3 · kalandan fazla teslim edilemez', (t) async {
      await ac(t, TeslimatDiyalogu(siparis: siparisDetay(
          kalemler: [siparisKalemi('Matematik SB', backorder: 5)])));

      await t.enterText(find.byKey(K.teslimatAdet('ok1')), '9');
      await t.pumpAndSettle();
      expect(find.text('fazla'), findsOneWidget);
      expect(t.widget<FilledButton>(find.byKey(K.teslimatKaydet)).onPressed,
          isNull);
    });

    testWidgets('kısmi teslim gönderilebilir', (t) async {
      final repo = await ac(t, TeslimatDiyalogu(siparis: siparisDetay(
          kalemler: [siparisKalemi('Matematik SB', backorder: 5)])));

      await t.enterText(find.byKey(K.teslimatAdet('ok1')), '3');
      await t.pumpAndSettle();
      await t.tap(find.byKey(K.teslimatKaydet));
      await t.pumpAndSettle();

      expect(repo.sonTeslimat, {'ok1': 3});
      expect(repo.sonBorclandirir, isTrue);
    });

    testWidgets('backorder listede türetilmiş sayı olarak görünür', (t) async {
      await ac(t, const SiparisDetayEkrani(siparisId: 'o1'),
          repo: SahteSiparisRepo(detayKaydi: siparisDetay(
              durum: 'kismi_teslim',
              kalemler: [siparisKalemi('Matematik SB',
                  sevkEdilen: 3, backorder: 2)])));

      expect(find.textContaining('2 adet bekliyor'), findsOneWidget);
      expect(find.textContaining('Backorder ayrı bir kayıt değildir'),
          findsOneWidget);
    });
  });

  group('onay akışı', () {
    testWidgets('onay bekleyen sipariş gerekçesiyle gösterilir', (t) async {
      await ac(t, const SiparisDetayEkrani(siparisId: 'o1'),
          repo: SahteSiparisRepo(detayKaydi: siparisDetay(
              durum: 'onay_bekliyor',
              onayGerekce: 'İskonto tavanı aşıldı (%35)',
              kalemler: [siparisKalemi('Matematik SB')])));

      expect(find.byKey(K.siparisOnayUyari), findsOneWidget);
      expect(find.textContaining('İskonto tavanı aşıldı'), findsWidgets);
      expect(find.textContaining('Onaylanmadan hazırlığa geçemez'),
          findsOneWidget);
    });

    testWidgets('pazarlamacı onaylayamaz', (t) async {
      await ac(t, const SiparisDetayEkrani(siparisId: 'o1'),
          rol: AppRole.pazarlamaci,
          repo: SahteSiparisRepo(detayKaydi: siparisDetay(
              durum: 'onay_bekliyor', onayGerekce: 'Kredi limiti aşılıyor',
              kalemler: [siparisKalemi('Matematik SB')])));

      expect(t.widget<FilledButton>(find.byKey(K.siparisOnayla)).onPressed,
          isNull);
      expect(find.textContaining('Yalnızca sahip veya müdür'), findsOneWidget);
    });
  });

  group('K48 · tahsilat', () {
    testWidgets('K7 · borçlu listesinde toplam satırı yok', (t) async {
      await ac(t, const TahsilatEkrani(),
          repo: SahteSiparisRepo(borcluListesi: [
            borclu('Okul A', id: 'c1', bakiye: 45000),
            borclu('Okul B', id: 'c2', bakiye: 15000),
          ]));

      expect(find.textContaining('60.000'), findsNothing,
          reason: 'cari bakiyeleri toplanmaz (K7)');
      expect(find.textContaining('toplanmaz'), findsOneWidget);
    });

    testWidgets('gecikme gün sayısıyla işaretlenir', (t) async {
      await ac(t, const TahsilatEkrani(),
          repo: SahteSiparisRepo(borcluListesi: [
            borclu('Geciken Okul',
                enEski: DateTime.now().subtract(const Duration(days: 95))),
          ]));
      // Rozet değil vurgu satırı: durum artık büyük harfli bir etikette
      // değil, satırın kendi renkli üçüncü satırında yazıyor.
      expect(find.textContaining('95 gündür açık'), findsOneWidget);
    });

    testWidgets('tahsilat tutarı bakiyeyle açılır', (t) async {
      await ac(t, TahsilatDiyalogu(cari: borclu('Y Lisesi', bakiye: 400)));
      expect(t.widget<TextField>(find.byKey(K.tahsilatTutar)).controller?.text,
          '400,00');
    });

    testWidgets('K48 · borçtan fazla ödeme AVANS diye açıklanır', (t) async {
      await ac(t, TahsilatDiyalogu(cari: borclu('Y Lisesi', bakiye: 400)),
          repo: SahteSiparisRepo(
              acikTeslimatListesi: [acikTeslimat(tutar: 400)]));

      await t.enterText(find.byKey(K.tahsilatTutar), '500');
      await t.pumpAndSettle();
      expect(find.textContaining('AVANS olarak durur'), findsOneWidget);
      expect(find.textContaining('₺100,00'), findsWidgets);
    });

    testWidgets('K48 · para NEREYE gidecek, kaydetmeden önce yazar',
        (t) async {
      // Eskiden mahsup dağılımı ancak KAYDETTİKTEN sonra, makbuzda
      // öğreniliyordu — yani iş bittikten sonra.
      await ac(t, TahsilatDiyalogu(cari: borclu('Y Lisesi', bakiye: 3000)),
          repo: SahteSiparisRepo(acikTeslimatListesi: [
            acikTeslimat(id: 's1', tutar: 1000, gunOnce: 60),
            acikTeslimat(id: 's2', tutar: 2000, gunOnce: 30),
          ]));

      await t.enterText(find.byKey(K.tahsilatTutar), '1500');
      await t.pumpAndSettle();

      expect(find.byKey(K.tahsilatMahsup), findsOneWidget);
      // En eski teslimat KAPANIR (1.000), kalan 500 ikinciye kısmi gider.
      expect(find.textContaining('₺1.000,00'), findsWidgets);
      expect(find.textContaining('₺500,00'), findsWidgets);
      expect(find.textContaining('kalan ₺1.500,00'), findsOneWidget,
          reason: 'kısmi kapanan teslimatta ne kaldığı yazılmalı');
      expect(find.textContaining('En eski borçtan başlanır'), findsOneWidget);
    });

    testWidgets('K11 · çek seçilince mahsup önizlemesi GÖSTERİLMEZ',
        (t) async {
      // Çek ödeme değil ödeme vaadidir: bakiyeye dokunmaz, dolayısıyla
      // hiçbir teslimata mahsup edilmez. Önizleme göstermek yalan olurdu.
      await ac(t, TahsilatDiyalogu(cari: borclu('Y Lisesi', bakiye: 3000)),
          repo: SahteSiparisRepo(
              acikTeslimatListesi: [acikTeslimat(tutar: 3000)]));

      await t.enterText(find.byKey(K.tahsilatTutar), '1000');
      await t.pumpAndSettle();
      expect(find.byKey(K.tahsilatMahsup), findsOneWidget);

      await t.tap(find.byKey(K.tahsilatYontem));
      await t.pumpAndSettle();
      await t.tap(find.text('Çek').last);
      await t.pumpAndSettle();
      expect(find.byKey(K.tahsilatMahsup), findsNothing);
    });

    testWidgets('K11 · çek seçilince vade zorunlu ve uyarı çıkar', (t) async {
      await ac(t, TahsilatDiyalogu(cari: borclu('Y Lisesi')));

      await t.tap(find.byKey(K.tahsilatYontem));
      await t.pumpAndSettle();
      await t.tap(find.text('Çek').last);
      await t.pumpAndSettle();

      expect(find.byKey(K.tahsilatUyari), findsOneWidget);
      expect(find.textContaining('ödeme VAADİDİR'), findsOneWidget);
      expect(t.widget<FilledButton>(find.byKey(K.tahsilatKaydet)).onPressed,
          isNull, reason: 'vade seçilmeden kaydedilemez');
    });

    testWidgets('nakit tahsilat depoya gider', (t) async {
      final repo = await ac(t,
          TahsilatDiyalogu(cari: borclu('Y Lisesi', bakiye: 400)));

      await t.enterText(find.byKey(K.tahsilatTutar), '250');
      await t.pumpAndSettle();
      await t.tap(find.byKey(K.tahsilatKaydet));
      await t.pumpAndSettle();

      expect(repo.sonTutar, 250.0);
      expect(repo.sonYontem, 'nakit');
    });
  });
}
