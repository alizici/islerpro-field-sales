import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:islerpro/core/auth/session.dart';
import 'package:islerpro/core/theme/app_theme.dart';
import 'package:islerpro/core/router/app_router.dart';
import 'package:islerpro/data/local/yerel_saglayici.dart';
import 'package:islerpro/data/repositories/ziyaret_repository.dart';
import 'package:islerpro/shared/widgets/gezinme.dart';
import 'package:islerpro/data/repositories/siparis_repository.dart';
import 'package:islerpro/features/dashboard/presentation/kabuk.dart';

import 'sahte_depolar.dart';

/// Rolün AÇILIŞ EKRANI, gezinme listesindeki ilk öğedir.
///
/// Bu dolaylı bağ bir kez ısırdı: `/senkron` listeye Panel'den önce eklenince
/// işletme sahibi uygulamayı açtığında Panel yerine Senkron ekranına
/// düşüyordu. Liste sırası artık burada kilitli.
void main() {
  group('Açılış ekranları', () {
    test('her rol kendi işine bakan ekranda açılır', () {
      expect(hedeflerFor(AppRole.isletmeSahibi).first.yol, '/panel');
      expect(hedeflerFor(AppRole.dukkanMuduru).first.yol, '/panel');
      expect(hedeflerFor(AppRole.pazarlamaci).first.yol, '/bugun');
      expect(hedeflerFor(AppRole.hazirlik).first.yol, '/hazirlik');
      expect(hedeflerFor(AppRole.ogretmen).first.yol, '/talepler');
    });

    test('araç ekranları listenin SONUNDA durur', () {
      for (final rol in [AppRole.isletmeSahibi, AppRole.pazarlamaci,
                         AppRole.dukkanMuduru]) {
        final yollar = hedeflerFor(rol).map((h) => h.yol).toList();
        expect(yollar.indexOf('/senkron'), greaterThan(0),
            reason: '$rol için senkron açılış ekranı olamaz');
        expect(yollar.last, '/ayarlar');
      }
    });

    test('her rolün en az bir ekranı vardır', () {
      for (final rol in AppRole.values) {
        if (rol == AppRole.platformAdmin) continue;
        expect(hedeflerFor(rol), isNotEmpty, reason: '$rol boş kalamaz');
      }
    });
  });

  group('Menü öbekleri', () {
    test('taşan her hedefin bir öbeği var', () {
      for (final rol in [AppRole.isletmeSahibi, AppRole.pazarlamaci,
                         AppRole.dukkanMuduru, AppRole.hazirlik]) {
        final tasan = hedeflerFor(rol).skip(4);
        for (final h in tasan) {
          expect(h.obek, isNotNull, reason: '\${h.yol} öbeksiz kalamaz');
        }
      }
    });

    test('araçlar öbeği menünün SONUNDA', () {
      // Öbek sırası `NavObek.values`; senkron ve ayarlar en sonda olmalı,
      // kimsenin günü onlarla başlamaz.
      expect(NavObek.values.last, NavObek.arac);
      final s = navHedefleri.where((h) => h.yol == '/senkron').single;
      final a = navHedefleri.where((h) => h.yol == '/ayarlar').single;
      expect((s.obek, a.obek), (NavObek.arac, NavObek.arac));
    });

    test('açılış ekranı MENÜDE DEĞİL, sekmede', () {
      // Öbek yalnızca taşan hedefleri düzenler. Açılış ekranı ilk dörtte
      // olduğu için menüye hiç düşmez — hangi öbekte olduğu da önemsizdir.
      // (Hazırlık rolünün açılışı `/hazirlik` ve o SATIŞ öbeğinde; bunu
      // "günlük olmalı" diye kurala bağlamak yanlış olurdu.)
      for (final rol in AppRole.values) {
        if (rol == AppRole.platformAdmin) continue;
        final h = hedeflerFor(rol);
        if (h.isEmpty) continue;
        expect(h.take(4).contains(h.first), isTrue,
            reason: '\$rol açılışı menünün içine gömülemez');
      }
    });
  });

  /// Masaüstü/tablet yerleşiminde gezinme, PENCERE KISALINCA kırılmamalı.
  ///
  group('Alt gezinme çubuğu', () {
    Future<void> cubuk(WidgetTester t,
        {required List<GezinmeOgesi> ogeler, int secili = 0}) async {
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          bottomNavigationBar: AltGezinme(
            ogeler: ogeler, secili: secili, onSec: (_) {}),
        ),
      ));
      await t.pumpAndSettle();
    }

    testWidgets('bekleyen iş sekmede sayıyla görünür', (t) async {
      // Bu bilgi eskiden yalnızca Panel'deydi: kullanıcı Cariler
      // ekranındayken üç gecikmiş talebi olduğunu bilmiyordu.
      await cubuk(t, ogeler: const [
        GezinmeOgesi(ikon: Icons.today_outlined, etiket: 'Bugün'),
        GezinmeOgesi(ikon: Icons.inbox_outlined, etiket: 'Talepler', sayi: 3),
      ]);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('seçili sekmenin ikonu DOLAR', (t) async {
      // iOS'ta seçimi anlatan asıl sinyal bu. Renk tek başına yetmez:
      // renk körlüğünde iki sekme aynı görünür, dolu/boş ayrımı biçimdir.
      await cubuk(t, secili: 1, ogeler: const [
        GezinmeOgesi(
            ikon: Icons.today_outlined,
            doluIkon: Icons.today,
            etiket: 'Bugün'),
        GezinmeOgesi(
            ikon: Icons.inbox_outlined,
            doluIkon: Icons.inbox,
            etiket: 'Talepler'),
      ]);
      expect(find.byIcon(Icons.inbox), findsOneWidget,
          reason: 'seçili sekme dolu ikon');
      expect(find.byIcon(Icons.today_outlined), findsOneWidget,
          reason: 'seçilmeyen sekme boş ikon');
      expect(find.byIcon(Icons.today), findsNothing);
    });

    testWidgets('Material dalga efekti YOK', (t) async {
      // iOS'ta sekmeye basınca mürekkep yayılmaz; durum anında değişir.
      await cubuk(t, ogeler: const [
        GezinmeOgesi(ikon: Icons.today_outlined, etiket: 'Bugün'),
      ]);
      expect(
          find.descendant(
              of: find.byType(AltGezinme), matching: find.byType(InkWell)),
          findsNothing);
    });

    testWidgets('sıfır sayaç rozet ÇİZMEZ', (t) async {
      // Her sekmede "0" yazsaydı rozet bilgi değil gürültü olurdu.
      await cubuk(t, ogeler: const [
        GezinmeOgesi(ikon: Icons.inbox_outlined, etiket: 'Talepler'),
      ]);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('üç haneli sayı taşmaz', (t) async {
      await cubuk(t, ogeler: const [
        GezinmeOgesi(ikon: Icons.inbox_outlined, etiket: 'Talepler', sayi: 240),
      ]);
      expect(t.takeException(), isNull);
      expect(find.text('99+'), findsOneWidget);
    });

    testWidgets('ekran okuyucu sayacı da okur', (t) async {
      await cubuk(t, ogeler: const [
        GezinmeOgesi(ikon: Icons.inbox_outlined, etiket: 'Talepler', sayi: 3),
      ]);
      expect(
          find.bySemanticsLabel('Talepler, 3 bekleyen'), findsOneWidget,
          reason: 'rozet yalnızca göze anlatılamaz');
    });
  });

  group('Menü sekmesi kara kutu değil', () {
    Future<void> ac(WidgetTester t, {required String yol}) async {
      t.view.physicalSize = const Size(400, 900);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(ProviderScope(
        overrides: [
          sessionProvider.overrideWithValue(
              testOturumu(rol: AppRole.isletmeSahibi)),
          ziyaretRepositoryProvider.overrideWithValue(SahteZiyaretRepo()),
          yerelDbProvider.overrideWithValue(null),
          siparisRepositoryProvider.overrideWithValue(SahteSiparisRepo()),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: GoRouter(
            initialLocation: yol,
            routes: [
              ShellRoute(
                builder: (_, _, child) => Kabuk(child: child),
                routes: [
                  for (final h in hedeflerFor(AppRole.isletmeSahibi))
                    GoRoute(path: h.yol,
                        builder: (_, _) => Text('ekran ${h.etiket}')),
                ],
              ),
            ],
          ),
        ),
      ));
      await t.pumpAndSettle();
    }

    testWidgets('menüdeki bir ekran açıkken sekme onun ADINI taşır',
        (t) async {
      // Sekme "Daha fazla" demeye devam edince kullanıcı Vadeler'deyken
      // çubuk nerede olduğunu söylemiyordu.
      await ac(t, yol: '/vadeler');
      expect(find.text('Daha fazla'), findsNothing);
      expect(find.text('Vadeler'), findsWidgets);
    });

    testWidgets('ilk dörtteki ekranda sekme "Daha fazla" kalır', (t) async {
      await ac(t, yol: '/panel');
      expect(find.text('Daha fazla'), findsOneWidget);
    });
  });

  /// `NavigationRail` kendi kendine kaymıyor: sahip rolünde 19 hedef var ve
  /// kısa bir pencerede (macOS varsayılan boyutu, yatay iPad, bölünmüş ekran)
  /// 400 piksel taşıyordu. Taşan `RenderFlex` yerleşimi kırdığı için gezinme
  /// tamamen kullanılamaz hâle geliyordu — hata ancak uygulamayı masaüstünde
  /// KOŞTURUNCA görüldü.
  group('Dar pencerede gezinme', () {
    Future<void> ac(WidgetTester t, Size boyut,
        {AppRole rol = AppRole.isletmeSahibi}) async {
      t.view.physicalSize = boyut;
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(ProviderScope(
        overrides: [
          sessionProvider.overrideWithValue(testOturumu(rol: rol)),
          ziyaretRepositoryProvider.overrideWithValue(SahteZiyaretRepo()),
          yerelDbProvider.overrideWithValue(null),
        ],
        child: MaterialApp.router(
          // Uygulamanın KENDİ teması: Material varsayılanıyla çizilen bir
          // kabuk, kullanıcının gördüğü kabuk değil. Taşma sınamaları da
          // gerçek punto ve ray etiketleriyle koşsun.
          theme: AppTheme.light(),
          routerConfig: GoRouter(
            initialLocation: '/panel',
            routes: [
              ShellRoute(
                builder: (_, _, child) => Kabuk(child: child),
                routes: [
                  for (final h in hedeflerFor(rol))
                    GoRoute(path: h.yol,
                        builder: (_, _) => Text('ekran ${h.etiket}')),
                ],
              ),
            ],
          ),
        ),
      ));
      await t.pumpAndSettle();
    }

    testWidgets('kısa pencerede taşma YOK — 19 hedef sığmasa da', (t) async {
      // 800x600: macOS penceresinin açıldığı boy. Tablet kırılımı burada.
      await ac(t, const Size(800, 600));
      expect(t.takeException(), isNull,
          reason: 'taşan RenderFlex gezinmeyi tamamen kırıyordu');
      expect(find.byType(NavigationRail), findsOneWidget);
    });

    testWidgets('sığmayan hedeflere KAYDIRARAK ulaşılır', (t) async {
      await ac(t, const Size(800, 600));
      final son = find.text(hedeflerFor(AppRole.isletmeSahibi).last.etiket);

      // Ağaçta var ama EKRANIN ALTINDA: "bulundu" görünürlük demek değil.
      expect(t.getRect(son).top, greaterThan(600),
          reason: 'son hedef pencereye sığmıyor — kaydırma şart');

      await t.scrollUntilVisible(son, 200,
          scrollable: find.byType(Scrollable).first);
      await t.pumpAndSettle();
      expect(t.getRect(son).top, lessThan(600));
    });

    testWidgets('uzun pencerede de sorunsuz', (t) async {
      await ac(t, const Size(800, 1600));
      expect(t.takeException(), isNull);
      expect(find.byType(NavigationRail), findsOneWidget);
    });

    testWidgets('ray marka bandını kullanır, beyaz yüzeyi değil', (t) async {
      // Tablet/masaüstü rayı maketteki koyu bordo kenar çubuğunun kendisi.
      // Telefon sekmesi ise platformun dilini konuşur (iOS tab bar açık
      // zeminde, marka `tintColor` olarak) — bu bir tutarsızlık değil,
      // kırılıma göre ayrı iki bileşen olmalarının sonucu.
      await ac(t, const Size(800, 600));
      final ray = t.widget<NavigationRail>(find.byType(NavigationRail));
      final beklenen =
          Theme.of(t.element(find.byType(NavigationRail))).colorScheme.sidebar;
      final gercek = ray.backgroundColor ??
          Theme.of(t.element(find.byType(NavigationRail)))
              .navigationRailTheme
              .backgroundColor;
      expect(gercek, beklenen);
    });

    testWidgets('masaüstü genişlikte sidebar zaten kayıyor', (t) async {
      await ac(t, const Size(1400, 600));
      expect(t.takeException(), isNull);
      expect(find.byType(NavigationRail), findsNothing);
    });
  });

  group('Sekme sırası role göre', () {
    test('pazarlamacının çubuğunda gelen kutusu var, dizin yok', () {
      final ilkDort =
          hedeflerFor(AppRole.pazarlamaci).take(4).map((h) => h.yol).toList();

      // Rozet taşıyan gelen kutusu taşma menüsünde duruyordu: bir işin
      // bekliyorsa onu görmek için menü açman gerekmemeli.
      expect(ilkDort, contains('/talepler'));
      // Kurumlar okunan bir dizin — üstünde iş yapılmıyor, sekme hakkı yok.
      expect(ilkDort, isNot(contains('/kurumlar')));
      expect(ilkDort.first, '/bugun', reason: 'gün buradan başlar');
    });

    test('sahibin çubuğunda onay bekleyen iki kutu var', () {
      final ilkDort =
          hedeflerFor(AppRole.isletmeSahibi).take(4).map((h) => h.yol).toList();
      expect(ilkDort.first, '/panel');
      expect(ilkDort, containsAll(<String>['/talepler', '/siparisler']));
    });

    test('sıralama yetkiyi GENİŞLETMEZ', () {
      // Öncelik listesi bir görünürlük kaynağı değil; rolün göremediği bir
      // yolu oraya yazmak onu çubuğa taşımamalı.
      for (final rol in AppRole.values) {
        for (final h in hedeflerFor(rol)) {
          expect(h.roller, contains(rol));
        }
      }
    });
  });
}
