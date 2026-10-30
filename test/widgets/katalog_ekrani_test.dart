import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:islerpro/core/auth/session.dart';
import 'package:islerpro/core/test_keys.dart';
import 'package:islerpro/data/repositories/katalog_repository.dart';
import 'package:islerpro/features/catalog/presentation/katalog_ekrani.dart';

import 'sahte_depolar.dart';

/// K12 · Fiyat dükkana özeldir — fiyatı olmayan ürün siparişe açılamaz,
/// bu yüzden listede AYIRT EDİLEBİLİR olmalı.
/// K15 · Kitap ve deneme aynı katalogda; süzgeç ayırır.
void main() {
  Future<SahteKatalogRepo> ac(WidgetTester t,
      {List<UrunOzet> urunler = const [], int? toplam}) async {
    final repo = SahteKatalogRepo(urunler: urunler, toplam: toplam);
    await t.pumpWidget(ProviderScope(
      overrides: [
        katalogRepositoryProvider.overrideWithValue(repo),
        sessionProvider.overrideWithValue(testOturumu()),
      ],
      child: const MaterialApp(home: KatalogEkrani()),
    ));
    await t.pumpAndSettle();
    return repo;
  }

  testWidgets('fiyatı olmayan ürün açıkça işaretlenir', (t) async {
    await ac(t, urunler: [
      urun('Fiyatlı Kitap', id: 'a', satisFiyat: 120, varsayilanIskonto: 0.20),
      urun('Fiyatsız Kitap', id: 'b'),
    ]);

    // Rozet değil vurgu satırı: fiyatsız ürünün SONUCU da yazılı.
    expect(find.text('Fiyatı yok — siparişe açılamaz'), findsOneWidget,
        reason: 'siparişe açılamayan ürün gizlenmemeli, işaretlenmeli');
    expect(find.textContaining('120,00'), findsOneWidget);
    expect(find.textContaining('varsayılan %20'), findsOneWidget,
        reason: 'dükkan varsayılan iskontosu satırda görünmeli');
  });

  testWidgets('toplam sayı gösterilir', (t) async {
    await ac(t, urunler: [urun('Kitap', id: 'a')], toplam: 24632);
    expect(find.text('24.632 ÜRÜN'), findsOneWidget);
  });

  testWidgets('"Fiyatı yok" süzgeci depoya fiyatsiz olarak gider', (t) async {
    final repo = await ac(t, urunler: [urun('Kitap')]);
    repo.cagrilar.clear();

    await t.tap(find.byKey(K.katalogFiltreFiyatsiz));
    await t.pumpAndSettle();

    expect(repo.cagrilar.any((c) => c.contains('fiyat=fiyatsiz')), isTrue,
        reason: 'göçün asıl sorusu: hangi ürünün fiyatı eksik');
    // Süzgeç açıkken hem sayaç şeridi hem satırların kendisi söylüyor.
    expect(find.textContaining('siparişe açılamaz'), findsWidgets);
  });

  testWidgets('K15 · deneme süzgeci katalog tipini gönderir', (t) async {
    final repo = await ac(t, urunler: [urun('Kitap')]);
    repo.cagrilar.clear();

    await t.tap(find.byKey(K.katalogFiltreDeneme));
    await t.pumpAndSettle();

    expect(repo.cagrilar.any((c) => c.contains('katalog=deneme')), isTrue);
  });

  testWidgets('arama gecikmelidir — her tuşta sunucuya gidilmez', (t) async {
    final repo = await ac(t, urunler: [urun('Kitap')]);
    repo.cagrilar.clear();

    await t.enterText(find.byKey(K.katalogArama), 'mat');
    await t.pump(const Duration(milliseconds: 100));
    await t.enterText(find.byKey(K.katalogArama), 'matem');
    await t.pump(const Duration(milliseconds: 100));
    expect(repo.cagrilar, isEmpty,
        reason: '24 bin satır her tuş vuruşunda taranmamalı');

    await t.pump(const Duration(milliseconds: 400));
    await t.pumpAndSettle();
    expect(repo.cagrilar.where((c) => c.startsWith('ara:')).length, 1,
        reason: 'yalnızca son yazım aranmalı');
    expect(repo.cagrilar.first, contains('q=matem'));
  });

  testWidgets('boş sonuçta boş durum gösterilir', (t) async {
    await ac(t);
    expect(find.text('Eşleşen ürün yok'), findsOneWidget);
  });

  testWidgets('kaydırınca sonraki sayfa yüklenir', (t) async {
    // Sürüklenen şey LİSTE DEĞİL kaydırma görünümü: liste artık bir sliver
    // ve sliver'ın kutu gibi bir merkezi yok.
    // 50'lik sayfadan fazlası: ilk çekim doluysa devamı beklenir.
    final cok = [for (var i = 0; i < 60; i++) urun('Kitap $i', id: 'p$i')];
    final repo = await ac(t, urunler: cok);
    repo.cagrilar.clear();

    await t.drag(find.byType(CustomScrollView), const Offset(0, -4000));
    await t.pumpAndSettle();

    expect(repo.cagrilar.any((c) => c.contains('offset=50')), isTrue,
        reason: 'sonsuz kaydırma ikinci sayfayı istemeli');

    // İkinci sayfa 50'den az geldi → liste bitti, kuyruk toplamı yazar.
    await t.drag(find.byType(CustomScrollView), const Offset(0, -4000));
    await t.pumpAndSettle();
    expect(find.text('60 ÜRÜN LİSTELENDİ'), findsOneWidget,
        reason: 'iki sayfa birleşip 60 ürün olmalı');
  });
}
