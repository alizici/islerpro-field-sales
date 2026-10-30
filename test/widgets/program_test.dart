import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:islerpro/core/auth/session.dart';
import 'package:islerpro/core/test_keys.dart';
import 'package:islerpro/data/local/yerel_saglayici.dart';
import 'package:islerpro/data/repositories/deneme_repository.dart';
import 'package:islerpro/features/exams/presentation/program_detay_ekrani.dart';
import 'package:islerpro/features/exams/presentation/programlar_ekrani.dart';

import 'sahte_depolar.dart';

/// Faz 9 · Abonelik programı (C-3 · K47).
///
/// Bu ekranın koruduğu tek cümle: **plan borç doğurmaz.** `exam_deliveries`
/// yalnızca plandır; borç `shipments`'tan doğar (K26). Bu yüzden "teslim
/// edildi" işaretleyecek bir düğme YOKTUR — teslimat kaydı üretilir.
void main() {
  Future<SahteDenemeRepo> ac(WidgetTester t, Widget w,
      {SahteDenemeRepo? repo}) async {
    final r = repo ?? SahteDenemeRepo();
    t.view.physicalSize = const Size(1000, 2400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [
        denemeRepositoryProvider.overrideWithValue(r),
        sessionProvider.overrideWithValue(testOturumu()),
        yerelDbProvider.overrideWithValue(null),
      ],
      child: MaterialApp(home: w),
    ));
    await t.pumpAndSettle();
    return r;
  }

  DenemeProgrami program({
    String modu = 'takvim_bagli',
    List<TeslimKalemi> kalemler = const [],
    ProgramSayilari ozet = const ProgramSayilari(planlanan: 2),
  }) =>
      DenemeProgrami(id: 'pg1', cariId: 'c1', unvan: 'Y Lisesi Kurumsal',
          kurumAd: 'Y Lisesi', modu: modu, ogrenciSayisi: 200,
          denemeAdedi: 12, periyotGun: modu == 'takvim_bagli' ? null : 14,
          birimFiyat: 25, donem: '2025-2026 / 1. Dönem',
          kalemler: kalemler, ozet: ozet);

  TeslimKalemi kalem({String id = 'k1', String durum = 'planlandi',
      DateTime? tarih, DateTime? oncekiTarih, String? not,
      String? odemeDurumu, double? tutar}) =>
      TeslimKalemi(id: id, denemeId: 'd1', ad: 'TYT DENEME-3',
          yayinevi: 'Bes', tarih: tarih ?? DateTime(2026, 9, 15),
          adet: 200, durum: durum, oncekiTarih: oncekiTarih, notMetni: not,
          odemeDurumu: odemeDurumu, tutar: tutar,
          teslimatId: durum == 'planlandi' ? null : 's1');

  group('Program listesi', () {
    testWidgets('program yoksa açıkça söylenir', (t) async {
      await ac(t, const ProgramlarEkrani());
      expect(find.byKey(K.programListe), findsOneWidget);
      expect(find.textContaining('Henüz deneme programı yok'), findsOneWidget);
    });

    testWidgets('K8 · yıllık anlaşmanın iki program olduğu yazılı', (t) async {
      await ac(t, const ProgramlarEkrani());
      expect(find.textContaining('her yarıyıl bir tane'), findsOneWidget);
    });

    testWidgets('program satırı modunu ve ilerlemeyi taşır', (t) async {
      await ac(t, const ProgramlarEkrani(),
          repo: SahteDenemeRepo(programListesi: [
            ProgramOzeti(id: 'pg1', cariId: 'c1', unvan: 'Y Lisesi Kurumsal',
                kurumAd: 'Y Lisesi', modu: 'serbest_periyot',
                ogrenciSayisi: 200, denemeAdedi: 12, kalem: 12,
                teslimEdilen: 5, sonrakiTeslim: DateTime(2026, 9, 15)),
          ]));

      expect(find.text('Y Lisesi Kurumsal'), findsOneWidget);
      expect(find.text('5/12'), findsOneWidget);
      // Rozet değil alt bilgi: mod satırın kimliğinin parçası (Y-8).
      expect(find.textContaining('Serbest periyot'), findsOneWidget);   // Rozet büyütür
    });

    testWidgets('K47 · dönem özetinde uygulanan teslim edilenden AYRI sayılır',
        (t) async {
      await ac(t, const ProgramlarEkrani(),
          repo: SahteDenemeRepo(ozetKaydi: const DonemOzeti(
              donem: '2025-2026 / 1. Dönem', program: 3, aktifProgram: 2,
              ogrenci: 540, planlananKalem: 36, teslimEdilen: 20,
              uygulanan: 14, ertelenen: 4, ciro: 27000)));

      expect(find.byKey(K.programDonemOzeti), findsOneWidget);
      expect(find.textContaining('Teslim edilmiş ama uygulanmamış'),
          findsOneWidget);
      expect(find.text('20'), findsOneWidget);   // teslim edilen
      expect(find.text('14'), findsOneWidget);   // uygulanan
      expect(find.textContaining('27.000,00'), findsOneWidget);
    });

    testWidgets('hiç program yoksa dönem özeti gösterilmez', (t) async {
      await ac(t, const ProgramlarEkrani());
      expect(find.byKey(K.programDonemOzeti), findsNothing);
    });
  });

  group('Program detayı', () {
    testWidgets('C-3 · planın borç doğurmadığı yazılı', (t) async {
      await ac(t, const ProgramDetayEkrani(programId: 'pg1'),
          repo: SahteDenemeRepo(programKaydi: program(kalemler: [kalem()])));

      expect(find.byKey(K.programKalemler), findsOneWidget);
      expect(find.textContaining('Plan borç doğurmaz'), findsOneWidget);
    });

    testWidgets('Y-8 · modun tarihi nereden ürettiği yazılı', (t) async {
      await ac(t, const ProgramDetayEkrani(programId: 'pg1'),
          repo: SahteDenemeRepo(programKaydi: program()));
      expect(find.textContaining('Kalemler deneme takviminden'), findsOneWidget);

      await ac(t, const ProgramDetayEkrani(programId: 'pg1'),
          repo: SahteDenemeRepo(
              programKaydi: program(modu: 'serbest_periyot')));
      expect(find.textContaining('programın periyodundan üretilir'),
          findsOneWidget);
    });

    testWidgets('K47 · "teslim edildi" DURUM MENÜSÜNDE yok', (t) async {
      await ac(t, const ProgramDetayEkrani(programId: 'pg1'),
          repo: SahteDenemeRepo(programKaydi: program(kalemler: [kalem()])));

      await t.tap(find.byKey(K.programDurum('k1')));
      await t.pumpAndSettle();
      expect(find.text('Hazırlanıyor'), findsOneWidget);
      expect(find.text('Ertelendi'), findsOneWidget);
      expect(find.text('Teslim edildi'), findsNothing,
          reason: 'plan elle teslim edildi yapılamaz — borç doğmadan '
              'satış görünürdü');
    });

    testWidgets('teslimat ayrı bir düğme ve BORÇ DOĞURACAĞINI söylüyor',
        (t) async {
      final r = await ac(t, const ProgramDetayEkrani(programId: 'pg1'),
          repo: SahteDenemeRepo(programKaydi: program(kalemler: [kalem()])));

      await t.tap(find.byKey(K.programTeslim('k1')));
      await t.pumpAndSettle();
      expect(find.byKey(K.programTeslimOnay), findsOneWidget);
      expect(find.textContaining('BORÇ DOĞURUR'), findsOneWidget);

      await t.tap(find.byKey(K.programTeslimEt));
      await t.pumpAndSettle();
      expect(r.cagrilar, contains('teslimEt:k1'));
    });

    testWidgets('teslim edilmiş kalemde teslimat düğmesi YOK', (t) async {
      await ac(t, const ProgramDetayEkrani(programId: 'pg1'),
          repo: SahteDenemeRepo(programKaydi: program(
              kalemler: [kalem(durum: 'teslim_edildi')])));
      expect(find.byKey(K.programTeslim('k1')), findsNothing);
    });

    testWidgets('erteleme geçmişi ve gerekçesi görünür kalır', (t) async {
      await ac(t, const ProgramDetayEkrani(programId: 'pg1'),
          repo: SahteDenemeRepo(programKaydi: program(kalemler: [
            kalem(durum: 'ertelendi',
                oncekiTarih: DateTime(2026, 9, 1),
                not: 'Okul sınav haftası'),
          ])));

      expect(find.textContaining('önceki tarih'), findsOneWidget);
      expect(find.textContaining('Okul sınav haftası'), findsOneWidget);
    });

    testWidgets('kalem hem durumunu hem ÖDEME durumunu taşır', (t) async {
      await ac(t, const ProgramDetayEkrani(programId: 'pg1'),
          repo: SahteDenemeRepo(programKaydi: program(kalemler: [
            kalem(durum: 'teslim_edildi', odemeDurumu: 'odendi',
                tutar: 5000),
          ])));

      // Rozet yığını gitti: sıradan durum ve tutar alt bilgide, ödeme
      // durumu ayrı renkli vurgu satırında.
      expect(find.textContaining('Teslim edildi'), findsOneWidget);
      expect(find.text('Ödendi'), findsOneWidget);
      expect(find.textContaining('5.000,00'), findsOneWidget);
    });

    testWidgets('erteleme gerekçe olmadan kaydedilemez', (t) async {
      await ac(t, const ProgramDetayEkrani(programId: 'pg1'),
          repo: SahteDenemeRepo(programKaydi: program(kalemler: [kalem()])));

      await t.tap(find.byKey(K.programDurum('k1')));
      await t.pumpAndSettle();
      await t.tap(find.text('Ertelendi'));
      await t.pumpAndSettle();

      // Önce tarih seçici gelir; iptal edilirse akış durur ve çağrı gitmez.
      expect(find.byType(DatePickerDialog), findsOneWidget);
    });

    testWidgets('plana kalem eklenmemişse söylenir', (t) async {
      await ac(t, const ProgramDetayEkrani(programId: 'pg1'),
          repo: SahteDenemeRepo(programKaydi: program(
              ozet: const ProgramSayilari())));
      expect(find.textContaining('Plana kalem eklenmedi'), findsOneWidget);
    });
  });
}
