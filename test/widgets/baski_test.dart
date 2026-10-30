import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:islerpro/core/auth/session.dart';
import 'package:islerpro/core/test_keys.dart';
import 'package:islerpro/data/repositories/katalog_repository.dart';
import 'package:islerpro/features/catalog/presentation/baski_diyalogu.dart';

import 'sahte_depolar.dart';

/// K23 · Baskı ilişkisi TAHMİN EDİLMEZ, insan söyler.
/// Ekranın işi: kopyalanan ile kopyalanmayanı açıkça söylemek ve grubun
/// tam da doğru anda — yeni baskı eklenirken — doğduğunu göstermek.
void main() {
  Future<SahteKatalogRepo> ac(WidgetTester t, UrunOzet u,
      {List<Baski> grup = const []}) async {
    final repo = SahteKatalogRepo()..baskiListesi = grup;
    await t.pumpWidget(ProviderScope(
      overrides: [
        katalogRepositoryProvider.overrideWithValue(repo),
        sessionProvider.overrideWithValue(testOturumu()),
      ],
      child: MaterialApp(home: Scaffold(body: BaskiDiyalogu(urun: u))),
    ));
    await t.pumpAndSettle();
    return repo;
  }

  VoidCallback? kaydet(WidgetTester t) =>
      t.widget<FilledButton>(find.byKey(K.baskiKaydet)).onPressed;

  testWidgets('grubu olmayan ürün için grubun sonra doğacağı yazar', (t) async {
    await ac(t, urun('Matematik SB'));

    expect(find.byKey(K.baskiListesi), findsNothing);
    expect(find.textContaining('grup kendiliğinden oluşur'), findsOneWidget);
  });

  testWidgets('ne kopyalanır ne kopyalanmaz açıkça yazılı', (t) async {
    await ac(t, urun('Matematik SB'));

    expect(find.textContaining('Barkod ve fiyat KOPYALANMAZ'), findsOneWidget,
        reason: 'barkod ürünün kimliğidir; kopyalanırsa K24 bozulur');
    expect(find.textContaining('geçmiş satışlar eski baskıda kalır'),
        findsOneWidget);
  });

  testWidgets('grup listelenir, güncel baskı sırayla belirlenir', (t) async {
    await ac(t, urun('Matematik SB', id: 'p1'), grup: [
      baski('2026-27', id: 'p2', sira: 2, guncel: true, satisFiyat: 329),
      baski('2024-25', id: 'p1', sira: 1, secili: true, satisFiyat: 219,
          stok: 40),
    ]);

    expect(find.byKey(K.baskiListesi), findsOneWidget);
    expect(find.text('2 baskı'), findsOneWidget);
    // Rozet değil vurgu satırı: hangi baskının güncel, hangisinin bu üründe
    // seçili olduğu satırın kendi üçüncü satırında yazıyor.
    expect(find.text('Güncel baskı'), findsOneWidget);
    expect(find.text('Bu üründe seçili'), findsOneWidget);
    expect(find.textContaining('tarihten değil'), findsOneWidget,
        reason: 'güncellik açık sırayla belirlenir, addaki yıldan değil');
    expect(find.textContaining('stok 40'), findsOneWidget);
  });

  testWidgets('baskı etiketi olmadan kaydedilemez', (t) async {
    await ac(t, urun('Matematik SB'));
    expect(kaydet(t), isNull);

    await t.enterText(find.byKey(K.baskiEtiket), '2026-27');
    await t.pump();
    expect(kaydet(t), isNotNull);
  });

  testWidgets('yeni baskı etiketi ve barkodla gönderilir', (t) async {
    final repo = await ac(t, urun('Matematik SB'));

    await t.enterText(find.byKey(K.baskiEtiket), '2026-27');
    await t.enterText(find.byKey(K.baskiBarkod), '9786051234567');
    await t.enterText(find.byKey(K.baskiEtiketFiyat), '329,50');
    await t.pump();
    await t.tap(find.byKey(K.baskiKaydet));
    await t.pumpAndSettle();

    expect(repo.sonBaskiEtiketi, '2026-27');
    expect(repo.sonBaskiBarkod, '9786051234567');
    expect(repo.sonArsivle, isFalse);
  });

  testWidgets('stoğu olan eski baskıda arşivlemenin engeli önden söylenir',
      (t) async {
    await ac(t, urun('Matematik SB', stokAdedi: 40, satisFiyat: 219));

    expect(find.textContaining('Elde 40 adet var'), findsOneWidget);
    expect(find.textContaining('önce eritilmeli'), findsOneWidget);
  });

  testWidgets('stoğu yoksa arşivleme seçilebilir', (t) async {
    final repo = await ac(t, urun('Matematik SB', stokAdedi: 0));

    await t.enterText(find.byKey(K.baskiEtiket), '2026-27');
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(K.baskiArsivle));
    await t.pumpAndSettle();
    await t.tap(find.byKey(K.baskiArsivle));
    await t.pumpAndSettle();
    await t.tap(find.byKey(K.baskiKaydet));
    await t.pumpAndSettle();

    expect(repo.sonArsivle, isTrue);
  });

  group('K23 · sipariş uyarısı iki yönlüdür', () {
    Future<void> uyariAc(WidgetTester t, BaskiUyarisi u) => t.pumpWidget(
          MaterialApp(home: Scaffold(body: BaskiUyariSatiri(uyari: u))),
        );

    testWidgets('eski baskı seçiliyse güncel ve fiyat farkı gösterilir',
        (t) async {
      await uyariAc(t, BaskiUyarisi(
        uyari: true,
        guncel: baski('2025-26', id: 'p2', satisFiyat: 329),
        secili: baski('2024-25', id: 'p1', satisFiyat: 219, stok: 40),
      ));
      await t.pumpAndSettle();

      expect(find.byKey(K.baskiUyari), findsOneWidget);
      expect(find.textContaining('2025-26 baskısı var'), findsOneWidget);
      expect(find.textContaining('329,00'), findsOneWidget);
      expect(find.textContaining('elde 40 adet'), findsOneWidget,
          reason: 'stok eritmek de meşru bir karardır');

      // Karar kullanıcınındır — iki yol da açık
      expect(find.text('Güncele geç'), findsOneWidget);
      expect(find.text('Eski baskıyla devam'), findsOneWidget);
    });

    testWidgets('güncel baskı seçiliyse uyarı hiç çıkmaz', (t) async {
      await uyariAc(t, const BaskiUyarisi());
      await t.pumpAndSettle();
      expect(find.byKey(K.baskiUyari), findsNothing);
    });

    testWidgets('"Güncele geç" seçilen ürünü bildirir', (t) async {
      String? secilen;
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: BaskiUyariSatiri(
            uyari: BaskiUyarisi(
                uyari: true, guncel: baski('2025-26', id: 'p2')),
            onGuncelSec: (id) => secilen = id,
          ),
        ),
      ));
      await t.pumpAndSettle();
      await t.tap(find.text('Güncele geç'));
      await t.pumpAndSettle();
      expect(secilen, 'p2');
    });
  });
}
