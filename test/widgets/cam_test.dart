import 'package:flutter/cupertino.dart' show CupertinoSliverRefreshControl;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:islerpro/core/theme/app_theme.dart';
import 'package:islerpro/shared/widgets/cam.dart';

/// Cam katmanı — GÖRÜNÜŞ testleri.
///
/// Bunlar "bileşen ağaçta mı" diye sormuyor; **ne boyandığını** soruyor. Bu
/// dosyanın var olma sebebi somut: `BoxDecoration`a `color` ve `gradient`
/// birlikte verilince `color` HİÇ çizilmiyor (gradyanın shader'ı onun yerine
/// geçiyor). Kod doğru okunuyordu, analiz temizdi, bileşenler ağaçtaydı — ama
/// koyu bordo baskın kart ekranda GRİ çıkıyordu ve düz kartların alt yarısı
/// tamamen saydamdı. Aynı tuzağa daha önce `OranSeridi` düşmüştü: orada da
/// kutu vardı, rengi vardı, yüksekliği yoktu.
void main() {
  Future<void> ac(WidgetTester t, Widget w) => t.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: Center(child: w)),
      ));

  /// Verilen bileşenin İÇİNDE gerçekten boyanan gradyan.
  LinearGradient boya(WidgetTester t, Finder icinde) => t
      .widgetList<DecoratedBox>(
          find.descendant(of: icinde, matching: find.byType(DecoratedBox)))
      .map((w) => w.decoration)
      .whereType<BoxDecoration>()
      .map((b) => b.gradient)
      .whereType<LinearGradient>()
      .first;

  group('Cam boyası', () {
    testWidgets('baskın kart OPAK ve koyu boyanır', (t) async {
      await ac(t, const CamKart(ton: CamTon.marka, child: Text('x')));
      final g = boya(t, find.byType(CamKart));

      for (final c in g.colors) {
        expect(c.a, 1.0,
            reason: 'baskın kartın zemini opak olmalı; saydam çıkarsa '
                'gradyan zemini yutmuş demektir');
        expect(c.computeLuminance(), lessThan(0.10),
            reason: 'koyu bordo; gri çıkıyorsa zemin boyanmıyor');
      }
    });

    testWidgets('düz kartın zemini ALTA KADAR sürer', (t) async {
      await ac(t, const CamKart(child: Text('x')));
      final g = boya(t, find.byType(CamKart));

      // Gradyanın son durağı zeminin kendisidir. Sıfır saydamlığa inerse
      // kartın alt yarısı boyanmıyor demektir — kart yarısından aşağısı yok.
      expect(g.colors.last.a, greaterThan(0.5),
          reason: 'kartın altı saydama düşmemeli');
      expect(g.colors.first.a, greaterThan(g.colors.last.a),
          reason: 'üst kenar parlaması zemini AŞMALI, yerine geçmemeli');
    });

    testWidgets('yüzen camın sütü altta da durur', (t) async {
      await ac(t, const Cam(child: SizedBox(width: 100, height: 40)));
      final g = boya(t, find.byType(Cam));

      expect(g.colors.last.a, closeTo(Cam.doku(_ctx(t)).a, 0.001),
          reason: 'çubuğun/başlığın zemini gradyanın altında kaybolmamalı');
    });

    testWidgets('koyu kartta anlam renkleri koyu karşılığına geçer',
        (t) async {
      late ColorScheme icerisi;
      await ac(
          t,
          CamKart(
            ton: CamTon.marka,
            child: Builder(builder: (c) {
              icerisi = Theme.of(c).colorScheme;
              return const Text('x');
            }),
          ));

      // `error` şemada iki temada da AYNI koyu kırmızı. Koyu bordo kartta
      // "₺9.998,14 gecikmiş" satırı bu yüzden zemine karışıyordu — bir uyarı
      // okunamıyorsa uyarı değildir.
      expect(icerisi.error.computeLuminance(),
          greaterThan(AppTheme.light().colorScheme.error.computeLuminance()),
          reason: 'koyu zeminde hata rengi AÇILMALI');
      expect(icerisi.onSurface, Colors.white);
    });
  });

  group('CamSayfa', () {
    List<Widget> uzunIcerik() =>
        [for (var i = 0; i < 30; i++) SizedBox(height: 60, child: Text('sat$i'))];

    Future<void> ac(WidgetTester t) => t.pumpWidget(MaterialApp(
          theme: AppTheme.light(),
          home: CamSayfa(baslik: 'Panel', cocuklar: uzunIcerik()),
        ));

    /// Bir bileşenin EN YAKIN saydamlık sarmalayıcısı.
    double opaklik(WidgetTester t, Finder ne) => t
        .widget<Opacity>(
            find.ancestor(of: ne, matching: find.byType(Opacity)).first)
        .opacity;

    /// Çubuktaki küçük başlık — büyük olan gövdede, `AppBar`ın dışında.
    Finder kucukBaslik() => find.descendant(
        of: find.byType(AppBar), matching: find.text('Panel'));

    testWidgets('ilk içerik başlığın ALTINDA kalmaz', (t) async {
      await ac(t);

      // İçerik camın altından AKAR ama altında BAŞLAMAZ. Ölçü piksel:
      // "dolgu verilmiş mi" değil, büyük başlık gerçekten çubuğun altına mı
      // düşmüş. Bu unutulunca ilk satır camın altında kalıyor — alt çubukta
      // bir kez yaşadığımız hatanın üstteki eşi.
      expect(t.getTopLeft(find.text('Panel').first).dy,
          greaterThanOrEqualTo(kToolbarHeight),
          reason: 'büyük başlık çubuğun altından başlamalı');
    });

    testWidgets('cam tepedeyken YOK, içerik altına girince belirir',
        (t) async {
      await ac(t);
      expect(opaklik(t, find.byType(BackdropFilter)), 0,
          reason: 'altından geçen bir şey yokken bulanıklık yalan olur');

      await t.drag(find.byType(CustomScrollView), const Offset(0, -220));
      await t.pumpAndSettle();
      expect(opaklik(t, find.byType(BackdropFilter)), 1);
    });

    testWidgets('büyük başlık çubuğa DEVREDER, ikisi birden görünmez',
        (t) async {
      await ac(t);
      // Tepede ekranın adı bir kez yazılı: büyük olan. Çubuktaki karşılığı
      // aynı anda görünürse başlık ekranda iki kere duruyor.
      expect(opaklik(t, kucukBaslik()), 0);

      await t.drag(find.byType(CustomScrollView), const Offset(0, -200));
      await t.pumpAndSettle();
      expect(opaklik(t, kucukBaslik()), 1,
          reason: 'büyük başlık geçtikten sonra küçüğü devralmalı');
    });

    testWidgets('aşağı çekme iOS yayı, Material tekeri değil', (t) async {
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: CamSayfa(
            baslik: 'Panel', cocuklar: uzunIcerik(), onYenile: () async {}),
      ));

      // `skipOffstage: false` ŞART: çekilmemiş yay sıfır yükseklikte duruyor
      // ve `Viewport` görünmeyen sliver'ları arama dışında bırakıyor.
      expect(find.byType(CupertinoSliverRefreshControl, skipOffstage: false),
          findsOneWidget);
      expect(find.byType(RefreshIndicator), findsNothing,
          reason: 'aşağı inen Material tekeri bu dilin parçası değil');
    });
  });
}

BuildContext _ctx(WidgetTester t) => t.element(find.byType(Scaffold).first);
