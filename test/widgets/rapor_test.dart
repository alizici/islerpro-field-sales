import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:islerpro/core/auth/session.dart';
import 'package:islerpro/core/test_keys.dart';
import 'package:islerpro/data/repositories/rapor_repository.dart';
import 'package:islerpro/features/reports/presentation/rapor_ekrani.dart';
import 'package:islerpro/features/reports/presentation/raporlar_ekrani.dart';

import 'sahte_depolar.dart';

/// K50 · Rapor motoru.
///
/// Bu dosyanın koruduğu tek cümle: **ekranın rapora özel dalı yoktur.**
/// Sütunlar, kırılım seçenekleri ve uyarılar sunucudan gelen tanımdan çizilir.
/// Ekranda bir rapor adı sabit yazılı olsaydı, katalog satırı eklemek yetmez,
/// kod değişikliği gerekirdi — motor da motor olmazdı.
void main() {
  Future<SahteRaporRepo> ac(WidgetTester t, Widget w,
      {SahteRaporRepo? repo}) async {
    final r = repo ?? SahteRaporRepo();
    t.view.physicalSize = const Size(1200, 2400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [
        raporRepositoryProvider.overrideWithValue(r),
        sessionProvider.overrideWithValue(testOturumu()),
      ],
      child: MaterialApp(home: w),
    ));
    await t.pumpAndSettle();
    return r;
  }

  group('Katalog', () {
    testWidgets('raporlar sunucudan gelen gruplarla listelenir', (t) async {
      await ac(t, const RaporlarEkrani());
      expect(find.byKey(K.raporKatalog), findsOneWidget);
      expect(find.text('Ciro'), findsOneWidget);
      expect(find.text('Borçlu cariler'), findsOneWidget);
      // Grup başlıkları artık mikro-etiket: bölüm ayıracı, kart başlığı değil.
      expect(find.textContaining('SATIŞ VE KÂRLILIK'), findsOneWidget);
      expect(find.textContaining('CARİ VE TAHSİLAT'), findsOneWidget);
    });

    testWidgets('katalogda OLMAYAN rapor ekranda da yok', (t) async {
      await ac(t, const RaporlarEkrani(),
          repo: SahteRaporRepo(katalogListesi: [tanimCiro()]));
      expect(find.text('Ciro'), findsOneWidget);
      expect(find.text('Borçlu cariler'), findsNothing,
          reason: 'ekran rapor adı taşımaz; listeyi katalog belirler');
    });

    testWidgets('rapor açıklaması ürün kuralını taşır', (t) async {
      await ac(t, const RaporlarEkrani());
      expect(find.textContaining('teslimattan doğar'), findsOneWidget);
    });

    testWidgets('kayıtlı rapor yoksa bölüm hiç çizilmez', (t) async {
      await ac(t, const RaporlarEkrani());
      expect(find.byKey(K.raporKayitlilar), findsNothing);
    });

    testWidgets('K50 · kayıtlı rapor kırılımıyla listelenir', (t) async {
      await ac(t, const RaporlarEkrani(),
          repo: SahteRaporRepo(kayitliListesi: [
            const KayitliRapor(id: 'r1', ad: 'Aylık ciro', kod: 'ciro',
                raporAd: 'Ciro', kirilim: ['ay'], paylasim: 'dukkan',
                benim: true),
          ]));
      expect(find.byKey(K.raporKayitlilar), findsOneWidget);
      expect(find.text('Aylık ciro'), findsOneWidget);
      expect(find.textContaining('ay'), findsWidgets);
      expect(find.text('Dükkanla paylaşıldı'), findsOneWidget);
    });

    testWidgets('başkasının kaydında SİLME düğmesi yok', (t) async {
      await ac(t, const RaporlarEkrani(),
          repo: SahteRaporRepo(kayitliListesi: [
            const KayitliRapor(id: 'r1', ad: 'Ali\'nin raporu', kod: 'ciro',
                paylasim: 'dukkan', benim: false, olusturan: 'Ali Veli'),
          ]));
      expect(find.byIcon(Icons.delete_outline), findsNothing,
          reason: 'paylaşılan rapor OKUNUR, sahibinin elinde kalır');
      expect(find.textContaining('paylaşan: Ali Veli'), findsOneWidget);
    });
  });

  group('Rapor ekranı', () {
    testWidgets('sütunlar tanımdan çizilir, sabit yazılı değil', (t) async {
      await ac(t, RaporEkrani(tanim: tanimCiro()));
      expect(find.byKey(K.raporTablo), findsOneWidget);
      expect(find.text('Pazarlamacı'), findsWidgets);
      expect(find.text('Ciro'), findsWidgets);
      expect(find.text('Adet'), findsWidgets);
    });

    testWidgets('toplam satırı AYRI ve raporun tamamını kapsar', (t) async {
      await ac(t, RaporEkrani(tanim: tanimCiro()));
      expect(find.text('TOPLAM'), findsOneWidget);
      expect(find.textContaining('3.000,00'), findsWidgets);
    });

    testWidgets('sayfa dışında kırılım kaldıysa bu SÖYLENİR', (t) async {
      await ac(t, RaporEkrani(tanim: tanimCiro()),
          repo: SahteRaporRepo(sonuc: sonucCiro(kirilimSayisi: 57)));
      expect(find.textContaining('2 / 57'), findsOneWidget);
      expect(find.textContaining('TOPLAM satırı tümünü kapsar'), findsOneWidget);
    });

    testWidgets('K7 · motorun uyarısı ekranda GÖRÜNÜR', (t) async {
      await ac(t, RaporEkrani(tanim: tanimCiro()),
          repo: SahteRaporRepo(sonuc: sonucCiro(uyarilar: [
            'K7 · Kurum kırılımında bakiye/risk TOPLANMAZ: kurum, '
            'öğretmenin borcunun kefili değildir.',
          ])));
      expect(find.byKey(K.raporUyari), findsOneWidget);
      expect(find.textContaining('kefili değildir'), findsOneWidget);
    });

    testWidgets('K8 · kapalı dönem özeti olduğu yazılı', (t) async {
      await ac(t, RaporEkrani(tanim: tanimCiro()),
          repo: SahteRaporRepo(sonuc: sonucCiro(onbellekten: true)));
      expect(find.byKey(K.raporOnbellek), findsOneWidget);
      expect(find.textContaining('bir kez hesaplandı'), findsOneWidget);
    });

    testWidgets('canlı raporda önbellek uyarısı ÇIKMAZ', (t) async {
      await ac(t, RaporEkrani(tanim: tanimCiro()));
      expect(find.byKey(K.raporOnbellek), findsNothing);
    });

    testWidgets('kırılım değişince depoya iletilir', (t) async {
      final r = await ac(t, RaporEkrani(tanim: tanimCiro()));
      r.cagrilar.clear();
      await t.tap(find.byKey(K.raporBoyut('ay')));
      await t.pumpAndSettle();
      expect(r.cagrilar.any((c) => c.contains('ay')), isTrue);
    });

    testWidgets('son kırılım da kaldırılamaz — rapor tek satıra düşmesin',
        (t) async {
      final r = await ac(t, RaporEkrani(tanim: tanimCiro()));
      r.cagrilar.clear();
      await t.tap(find.byKey(K.raporBoyut('pazarlamaci')));
      await t.pumpAndSettle();
      expect(r.cagrilar, isEmpty);
    });

    testWidgets('çok seviyeli kırılımda satırlar ÇAKIŞMADAN çizilir',
        (t) async {
      // İlk sütun tekrar ediyor: satır kimliği yalnızca ondan kurulursa
      // Flutter "iki TableRow aynı anahtarı taşıyor" diye tabloyu çizmeyi
      // bırakıyor — hata ancak gerçek çok seviyeli raporda ortaya çıkıyor.
      await ac(t, RaporEkrani(tanim: tanimCiro()),
          repo: SahteRaporRepo(sonuc: sonucCokSeviyeli()));

      expect(t.takeException(), isNull);
      expect(find.byKey(K.raporTablo), findsOneWidget);
      expect(find.text('TYT Matematik'), findsOneWidget);
      expect(find.text('TYT Türkçe'), findsOneWidget);
      expect(find.text('Bes'), findsWidgets);
    });

    testWidgets('sonuç boşsa uydurulmaz', (t) async {
      await ac(t, RaporEkrani(tanim: tanimCiro()),
          repo: SahteRaporRepo(sonuc: sonucCiro(satirlar: const [])));
      expect(find.textContaining('eşleşen kayıt yok'), findsOneWidget);
      expect(find.text('TOPLAM'), findsNothing);
    });
  });

  group('Kaydetme', () {
    testWidgets('K50 · ad ve paylaşım sorulur, kırılımla birlikte kaydedilir',
        (t) async {
      final r = await ac(t, RaporEkrani(tanim: tanimCiro()));
      await t.tap(find.byKey(K.raporKaydet));
      await t.pumpAndSettle();

      await t.enterText(find.byKey(K.raporKaydetAd), 'Aylık ciro');
      await t.pumpAndSettle();
      await t.tap(find.text('Dükkan'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(K.raporKaydetOnay));
      await t.pumpAndSettle();

      expect(r.cagrilar, contains('kaydet:Aylık ciro:ciro:dukkan'));
    });

    testWidgets('adsız kaydedilemez', (t) async {
      await ac(t, RaporEkrani(tanim: tanimCiro()));
      await t.tap(find.byKey(K.raporKaydet));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(K.raporKaydetAd), '   ');
      await t.pumpAndSettle();
      final b = t.widget<FilledButton>(find.byKey(K.raporKaydetOnay));
      expect(b.onPressed, isNull);
    });
  });
}
