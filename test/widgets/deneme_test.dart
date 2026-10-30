import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:islerpro/core/auth/session.dart';
import 'package:islerpro/core/test_keys.dart';
import 'package:islerpro/data/local/yerel_saglayici.dart';
import 'package:islerpro/data/repositories/deneme_repository.dart';
import 'package:islerpro/features/exams/presentation/deneme_takvimi_ekrani.dart';
import 'package:islerpro/features/exams/presentation/kurumlara_oner_ekrani.dart';
import 'package:islerpro/features/exams/presentation/mevcut_diyalogu.dart';

import 'sahte_depolar.dart';

/// Faz 9 · Deneme takvimi.
///
/// İki kural bu ekranın tamamını belirliyor ve testler onları koruyor:
///   **BULGU A** — omurga STOK tarihidir (267/267 dolu); uygulama tarihi
///   yalnızca %55 dolu, ona göre kurulan takvim kalemlerin yarısını kaybeder.
///   **BULGU B** — Türkiye Geneli çivilenmiş bir etkinliktir, Takvim türü ise
///   bir "stokta olacak" bildirimidir. İkisi aynı görünemez.
void main() {
  Future<SahteDenemeRepo> ac(WidgetTester t, Widget w,
      {SahteDenemeRepo? repo, AppRole rol = AppRole.pazarlamaci}) async {
    final r = repo ?? SahteDenemeRepo();
    t.view.physicalSize = const Size(1000, 2400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [
        denemeRepositoryProvider.overrideWithValue(r),
        sessionProvider.overrideWithValue(testOturumu(rol: rol)),
        yerelDbProvider.overrideWithValue(null),
      ],
      child: MaterialApp(home: w),
    ));
    await t.pumpAndSettle();
    return r;
  }

  group('Takvim', () {
    testWidgets('BULGU A · varsayılan eksen STOK tarihidir', (t) async {
      final r = await ac(t, const DenemeTakvimiEkrani());
      expect(r.sonEksen, 'stok',
          reason: '267/267 dolu olan tek eksen bu');
      expect(find.textContaining('kitapçıklar dükkana geliyor'), findsOneWidget);
    });

    testWidgets('eksen uygulamaya çevrilince sorgu da değişir', (t) async {
      final r = await ac(t, const DenemeTakvimiEkrani());
      await t.tap(find.byKey(K.denemeEksenUygulama));
      await t.pumpAndSettle();
      expect(r.sonEksen, 'uygulama');
      expect(find.textContaining('sınav kurumda yapılıyor'), findsOneWidget);
    });

    testWidgets('BULGU B · uygulama tarihi olmayanlar EKSİK sayılmaz',
        (t) async {
      await ac(t, const DenemeTakvimiEkrani(),
          repo: SahteDenemeRepo(takvimKaydi: DenemeTakvimi(
              eksen: 'uygulama', toplam: 3,
              tarihsiz: [deneme('5-6-7-8. SINIF-2', id: 'd9')])));

      expect(find.byKey(K.denemeTarihsiz), findsOneWidget);
      expect(find.textContaining('uygulama gününü kurum seçer'), findsOneWidget);
    });

    testWidgets('ay ileri geri gidince sorgu tekrarlanır', (t) async {
      final r = await ac(t, const DenemeTakvimiEkrani());
      final ilk = r.sonAy;
      await t.tap(find.byKey(K.denemeSonrakiAy));
      await t.pumpAndSettle();
      expect(r.sonAy, isNot(ilk));
      expect(r.cagrilar.where((c) => c.startsWith('takvim')).length,
          greaterThan(1));
    });

    testWidgets('portföy süzgeci sorguya geçer', (t) async {
      final r = await ac(t, const DenemeTakvimiEkrani());
      await t.tap(find.byKey(K.denemePortfoy));
      await t.pumpAndSettle();
      expect(r.sonPortfoy, isTrue);
    });

    testWidgets('kademe ve tür süzgeçleri sorguya geçer', (t) async {
      final r = await ac(t, const DenemeTakvimiEkrani());
      await t.tap(find.byKey(K.denemeKademe('lise')));
      await t.pumpAndSettle();
      expect(r.sonKademe, 'lise');

      await t.tap(find.byKey(K.denemeTur('turkiye_geneli')));
      await t.pumpAndSettle();
      expect(r.sonTur, 'turkiye_geneli');
    });

    testWidgets('boş ayda ızgara yine çizilir ve durum söylenir', (t) async {
      await ac(t, const DenemeTakvimiEkrani());
      expect(find.byKey(K.denemeIzgara), findsOneWidget);
      expect(find.textContaining('Bu ayda deneme yok'), findsOneWidget);
    });
  });

  group('Gün paneli', () {
    Future<void> panelAc(WidgetTester t, Deneme d) async {
      final ay = DateTime(DateTime.now().year, DateTime.now().month);
      await ac(t, const DenemeTakvimiEkrani(),
          repo: SahteDenemeRepo(takvimKaydi: DenemeTakvimi(
              ay: ay, toplam: 1,
              gunler: [DenemeGunu(
                  tarih: DateTime(ay.year, ay.month, 13), adet: 1,
                  turkiyeGeneli: d.sabit ? 1 : 0, denemeler: [d])])));
      await t.tap(find.byKey(K.denemeGun(13)));
      await t.pumpAndSettle();
    }

    testWidgets('K20 · Türkiye Geneli "kaçırılamaz" diye işaretlenir',
        (t) async {
      await panelAc(t, deneme('TÜRKİYE GENELİ-2', turu: 'turkiye_geneli',
          uygulama: DateTime(2025, 11, 13)));
      expect(find.byKey(K.denemeGunPaneli), findsOneWidget);
      expect(find.textContaining('Sabit tarih — kaçırılamaz'), findsOneWidget);
    });

    testWidgets('K12 · fiyatsız denemeden talep AÇILAMAZ ve sebebi yazılı',
        (t) async {
      await panelAc(t, deneme('FİYATSIZ DENEME', fiyatli: false));
      expect(find.textContaining('fiyatı yok — talep açılamaz'), findsOneWidget);
      final b = t.widget<TextButton>(find.byKey(K.denemeOner('d1')));
      expect(b.onPressed, isNull,
          reason: 'kullanıcı düğmeye basıp reddedilmeyi öğrenmesin');
    });

    testWidgets('Takvim türünde uygulamayı KURUM belirler', (t) async {
      await panelAc(t, deneme('5-6-7-8. SINIF-2'));
      expect(find.textContaining('kurum belirler'), findsOneWidget);
      expect(find.textContaining('kaçırılamaz'), findsNothing);
    });
  });

  group('Kurumlara öner', () {
    testWidgets('K22 · adet önerisi otomatik dolar ve KAYNAĞI yazılır',
        (t) async {
      await ac(t, KurumlaraOnerEkrani(deneme: deneme('PREMİUM-2')),
          repo: SahteDenemeRepo(hedefler_: [
            denemeHedefi('Y Lisesi Kurumsal', mevcut: 180, oneri: 180),
            denemeHedefi('Ahmet Öğr.', cariId: 'c2', mevcut: null, oneri: 60,
                etiket: 'geçen dönem siparişi'),
          ]));

      expect(find.byKey(K.onerListe), findsOneWidget);
      expect(find.textContaining('mevcut 180'), findsOneWidget);
      // Mevcut bildirilmemişse önerinin nereden geldiği yazılır
      expect(find.textContaining('geçen dönem siparişi'), findsOneWidget);
    });

    testWidgets('seçim yapılmadan talep açılamaz', (t) async {
      await ac(t, KurumlaraOnerEkrani(deneme: deneme('PREMİUM-2')),
          repo: SahteDenemeRepo(hedefler_: [denemeHedefi('Y Lisesi')]));
      final b = t.widget<FilledButton>(find.byKey(K.onerAc));
      expect(b.onPressed, isNull);
    });

    testWidgets('her cari için AYRI talep açıldığı yazılı', (t) async {
      await ac(t, KurumlaraOnerEkrani(deneme: deneme('PREMİUM-2')),
          repo: SahteDenemeRepo(hedefler_: [denemeHedefi('Y Lisesi')]));
      expect(find.textContaining('Her cari için AYRI talep'), findsOneWidget);
    });

    testWidgets('tümünü seç ve talep aç', (t) async {
      final r = await ac(t, KurumlaraOnerEkrani(deneme: deneme('PREMİUM-2')),
          repo: SahteDenemeRepo(hedefler_: [
            denemeHedefi('Y Lisesi', oneri: 180),
            denemeHedefi('X Dershanesi', cariId: 'c2', oneri: 90),
          ]));

      await t.tap(find.byKey(K.onerTumu));
      await t.pumpAndSettle();
      expect(find.text('2'), findsWidgets);      // seçilen cari

      await t.tap(find.byKey(K.onerAc));
      await t.pumpAndSettle();
      expect(r.cagrilar, contains('topluTalep:2'));
      expect(r.sonHedefler!.map((e) => e.adet).toList(), [180, 90]);
    });

    testWidgets('"Geçen sefer" önceki seçimi getirir', (t) async {
      final r = await ac(t, KurumlaraOnerEkrani(deneme: deneme('PREMİUM-2')),
          repo: SahteDenemeRepo(
              hedefler_: [
                denemeHedefi('Y Lisesi', oneri: 180),
                denemeHedefi('X Dershanesi', cariId: 'c2', oneri: 90),
              ],
              gecenSeferKaydi: {'c2': 75}));

      await t.tap(find.byKey(K.onerGecenSefer));
      await t.pumpAndSettle();

      expect(r.cagrilar, contains('gecenSefer'));
      await t.tap(find.byKey(K.onerAc));
      await t.pumpAndSettle();
      expect(r.sonHedefler!.single.cariId, 'c2');
      expect(r.sonHedefler!.single.adet, 75);
    });

    testWidgets('geçen sefer veri yoksa açıkça söylenir', (t) async {
      await ac(t, KurumlaraOnerEkrani(deneme: deneme('PREMİUM-2')),
          repo: SahteDenemeRepo(hedefler_: [denemeHedefi('Y Lisesi')]));
      await t.tap(find.byKey(K.onerGecenSefer));
      await t.pumpAndSettle();
      expect(find.textContaining('önceki denemesinde talep yok'), findsOneWidget);
    });

    testWidgets('sonuç KALEM KALEM gösterilir', (t) async {
      await ac(t, KurumlaraOnerEkrani(deneme: deneme('PREMİUM-2')),
          repo: SahteDenemeRepo(
              hedefler_: [denemeHedefi('Y Lisesi', oneri: 180)],
              topluSonuc: const TopluTalepSonucu(
                  acilan: 1, hatali: 1, toplamAdet: 180,
                  sonuclar: [
                    TopluTalepSatiri(cariId: 'c1', durum: 'ok',
                        talepId: 'r1'),
                    TopluTalepSatiri(cariId: 'c2', durum: 'hata',
                        hata: 'Kredi limiti aşıldı'),
                  ])));

      await t.tap(find.byKey(K.onerTumu));
      await t.pumpAndSettle();
      await t.tap(find.byKey(K.onerAc));
      await t.pumpAndSettle();

      expect(find.byKey(K.onerSonuc), findsOneWidget);
      expect(find.textContaining('Kısmen açıldı'), findsOneWidget);
      expect(find.textContaining('Kredi limiti aşıldı'), findsOneWidget);
    });

    testWidgets('portföyde uygun cari yoksa açıkça söylenir', (t) async {
      await ac(t, KurumlaraOnerEkrani(deneme: deneme('PREMİUM-2')));
      expect(find.textContaining('bu düzeye uygun cari yok'), findsOneWidget);
    });
  });

  group('K22 · sınıf mevcutları', () {
    Future<SahteDenemeRepo> diyalog(WidgetTester t,
        {SahteDenemeRepo? repo}) async {
      final r = await ac(t, Scaffold(
          body: Consumer(builder: (c, ref, _) => TextButton(
              onPressed: () => mevcutAkisi(c, ref, 'c1', 'Y Lisesi'),
              child: const Text('aç')))), repo: repo);
      await t.tap(find.text('aç'));
      await t.pumpAndSettle();
      return r;
    }

    testWidgets('girilmezse önerinin yine geleceği YAZILI', (t) async {
      await diyalog(t);
      expect(find.byKey(K.mevcutDiyalog), findsOneWidget);
      expect(find.textContaining('Girilmezse öneri yine gelir'), findsOneWidget);
    });

    testWidgets('mevcut değerler alanlara dolar', (t) async {
      await diyalog(t, repo: SahteDenemeRepo(mevcutlarKaydi: const Mevcutlar(
          toplam: 300,
          siniflar: [
            SinifMevcudu(sinif: 8, ogrenciSayisi: 180),
            SinifMevcudu(sinif: 7, ogrenciSayisi: 120),
          ])));

      final alan = t.widget<TextFormField>(find.byKey(K.mevcutSinif(8)));
      expect(alan.initialValue, '180');
    });

    testWidgets('V4 · öğrenci adı istenmez, yalnızca adet', (t) async {
      await diyalog(t);
      expect(find.textContaining('ad'), findsWidgets);   // "adet" geçer
      expect(find.textContaining('Öğrenci adı'), findsNothing);
      expect(find.textContaining('İsim'), findsNothing);
    });

    testWidgets('kaydedince sunucuya sınıf ve adet gider', (t) async {
      final r = await diyalog(t);
      await t.enterText(find.byKey(K.mevcutSinif(8)), '180');
      await t.pumpAndSettle();
      await t.tap(find.byKey(K.mevcutKaydet));
      await t.pumpAndSettle();

      expect(r.cagrilar.any((c) => c.startsWith('mevcutYaz')), isTrue);
      expect(r.sonMevcutlar!.firstWhere((e) => e.sinif == 8).ogrenciSayisi, 180);
    });
  });
}
