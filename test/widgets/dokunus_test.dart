import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:islerpro/core/theme/app_theme.dart';
import 'package:islerpro/shared/widgets/dokunus.dart';
import 'package:islerpro/shared/widgets/satir.dart';

/// Dokunma davranışı.
///
/// Ekranın cam görünmesi yetmiyor: parmağın altında Material duruyorsa
/// uygulama Material'dır. Bu dosya "hangi bileşen kullanıldı" diye sormuyor,
/// **basınca ne oluyor** diye soruyor.
void main() {
  Future<void> ac(WidgetTester t, Widget w) => t.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: Center(child: w)),
      ));

  /// Basılı tut, animasyonu ilerlet, ölçmeye hazır bırak.
  ///
  /// İKİ kare gerekiyor ve sebebi `Dokunus`ta değil: `TapGestureRecognizer`,
  /// hareketin sürüklemeye dönüşüp dönüşmeyeceğini görmek için `onTapDown`u
  /// `kPressTimeout` (100 ms) kadar bekletiyor. İlk kare o zamanlayıcıyı
  /// ateşliyor, animasyon ancak ikinci karede ilerliyor.
  Future<TestGesture> bas(WidgetTester t, Finder ne) async {
    final g = await t.startGesture(t.getCenter(ne));
    await t.pump(const Duration(milliseconds: 120));
    await t.pump(const Duration(milliseconds: 80));
    return g;
  }

  group('Dokunuş', () {
    testWidgets('satır YERİNDEN OYNAMAZ, zemini kararır', (t) async {
      var basildi = false;
      await ac(
          t,
          Dokunus(
            onTap: () => basildi = true,
            child: const SizedBox(width: 200, height: 60, child: Text('satır')),
          ));

      final once = t.getRect(find.text('satır'));
      final g = await bas(t, find.byType(Dokunus));

      expect(t.getRect(find.text('satır')), once,
          reason: 'satır levhanın bir dilimi; küçülürse levha yırtılmış gibi '
              'görünüyor');

      final zemin = t
          .widgetList<DecoratedBox>(find.descendant(
              of: find.byType(Dokunus), matching: find.byType(DecoratedBox)))
          .map((w) => w.decoration)
          .whereType<BoxDecoration>()
          .first;
      expect(zemin.color!.a, greaterThan(0),
          reason: 'basılı hâl görünür olmalı — mürekkep gittiğine göre '
              'onun yerini bu alıyor');

      await g.up();
      await t.pumpAndSettle();
      expect(basildi, isTrue);
    });

    testWidgets('nesne KÜÇÜLÜR', (t) async {
      await ac(
          t,
          Dokunus(
            tur: DokunusTuru.nesne,
            onTap: () {},
            child: const SizedBox(width: 200, height: 60, child: Text('kart')),
          ));

      final once = t.getRect(find.text('kart')).width;
      final g = await bas(t, find.byType(Dokunus));
      expect(t.getRect(find.text('kart')).width, lessThan(once),
          reason: 'bağımsız cisim parmağın altında geri çekilmeli');

      await g.up();
      await t.pumpAndSettle();
      expect(t.getRect(find.text('kart')).width, closeTo(once, 0.01),
          reason: 'bırakınca eski boyuna dönmeli');
    });

    testWidgets('tıklanamaz olan hiç tepki vermez', (t) async {
      await ac(t, const Dokunus(child: Text('ölü')));
      final once = t.getRect(find.text('ölü'));
      final g = await bas(t, find.text('ölü'));

      // Basılı görünüp hiçbir şey yapmayan bir yüzey "bozuk" diye okunuyor.
      expect(t.getRect(find.text('ölü')), once);
      await g.up();
      await t.pumpAndSettle();
    });

    testWidgets('gezinme dokunuşu TİTREMEZ', (t) async {
      final cagrilar = <String>[];
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform, (c) async {
        if (c.method == 'HapticFeedback.vibrate') cagrilar.add('${c.arguments}');
        return null;
      });
      addTearDown(() => t.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      await ac(t, Dokunus(onTap: () {}, child: const Text('git')));
      await t.tap(find.text('git'));
      await t.pumpAndSettle();

      // iOS sıradan bir gezinme dokunuşunda titremez; yalnızca SEÇİM
      // değiştiğinde titrer. Her dokunuşa titreşim koymak onu
      // anlamsızlaştırıyor — sinyal olmaktan çıkıp zemin gürültüsü oluyor.
      expect(cagrilar, isEmpty);

      await ac(t, Dokunus(titresim: true, onTap: () {}, child: const Text('süz')));
      await t.tap(find.text('süz'));
      await t.pumpAndSettle();
      expect(cagrilar, isNotEmpty, reason: 'seçim değişimi titremeli');
    });
  });

  group('Mürekkep', () {
    testWidgets('liste satırında dalga yok', (t) async {
      await ac(
          t,
          SizedBox(
            width: 320,
            child: KayitSatiri(baslik: 'Bir Okul', onTap: () {}),
          ));

      // `InkWell`in kendisi de, temadaki `NoSplash` da tek başına yetmiyor:
      // biri bileşeni, öteki boyayı anlatıyor. Aranan şey ikisinin toplamı —
      // ağaçta hiç mürekkep tepkisi olmaması.
      expect(find.byType(InkWell), findsNothing);
      expect(find.byType(InkResponse), findsNothing);
      expect(find.byType(Dokunus), findsWidgets);
    });
  });
}
