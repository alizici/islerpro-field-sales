import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:islerpro/core/auth/session.dart';
import 'package:islerpro/core/test_keys.dart';
import 'package:islerpro/data/repositories/katalog_repository.dart';
import 'package:islerpro/features/catalog/presentation/urun_fiyat_diyalogu.dart';

import 'sahte_depolar.dart';

/// K12 · Dükkanın fiyat katmanı.
/// K25 · Satış fiyatı iskontonun tabanıdır; etiket fiyat hesaba GİRMEZ.
///
/// Buradaki asıl risk yüzde/oran karışıklığı: kullanıcı 20 yazar, veritabanı
/// 0.20 bekler. 20 yazılıp 20 kaydedilirse iskonto %2000 olur.
void main() {
  Future<SahteKatalogRepo> ac(WidgetTester t, UrunOzet u) async {
    final repo = SahteKatalogRepo();
    await t.pumpWidget(ProviderScope(
      overrides: [
        katalogRepositoryProvider.overrideWithValue(repo),
        sessionProvider.overrideWithValue(testOturumu()),
      ],
      child: MaterialApp(home: Scaffold(body: UrunFiyatDiyalogu(urun: u))),
    ));
    await t.pump();
    return repo;
  }

  VoidCallback? kaydetButonu(WidgetTester t) =>
      t.widget<FilledButton>(find.byKey(K.fiyatKaydet)).onPressed;

  testWidgets('yüzde girilir, oran kaydedilir (20 → 0.20)', (t) async {
    final repo = await ac(t, urun('Test Kitabı', satisFiyat: 100));

    await t.enterText(find.byKey(K.fiyatIskonto), '20');
    await t.pump();
    await t.tap(find.byKey(K.fiyatKaydet));
    await t.pumpAndSettle();

    expect(repo.sonIskonto, 0.20,
        reason: 'ekranda yüzde, veritabanında oran tutulmalı');
    expect(repo.sonSatis, 100.0);
  });

  testWidgets('mevcut oran ekranda yüzde olarak açılır (0.15 → 15)', (t) async {
    await ac(t, urun('Test Kitabı', satisFiyat: 100, varsayilanIskonto: 0.15));

    final alan = t.widget<TextField>(find.byKey(K.fiyatIskonto));
    expect(alan.controller?.text, '15',
        reason: 'gidiş ve dönüş aynı birimde olmalı');
  });

  testWidgets('önizleme V6 aritmetiğini gösterir: 100 × %20 → 80', (t) async {
    await ac(t, urun('Test Kitabı', satisFiyat: 100));
    await t.enterText(find.byKey(K.fiyatIskonto), '20');
    await t.pump();

    expect(find.byKey(K.fiyatOnizleme), findsOneWidget);
    expect(find.textContaining('80,00'), findsWidgets,
        reason: 'birim fiyat hesaplanıp gösterilmeli');
    expect(find.textContaining('800,00'), findsOneWidget,
        reason: '10 adet için satır toplamı da gösterilmeli');
  });

  testWidgets('%100 ve üzeri iskonto kaydedilemez', (t) async {
    await ac(t, urun('Test Kitabı', satisFiyat: 100));

    await t.enterText(find.byKey(K.fiyatIskonto), '120');
    await t.pump();
    expect(kaydetButonu(t), isNull, reason: 'geçersiz oranda buton kapanmalı');
    expect(find.textContaining('%0 ile %100 arasında'), findsOneWidget);

    await t.enterText(find.byKey(K.fiyatIskonto), '20');
    await t.pump();
    expect(kaydetButonu(t), isNotNull, reason: 'düzeltilince açılmalı');
  });

  testWidgets('K25 · etiket fiyat referans olduğunu açıkça yazar', (t) async {
    await ac(t, urun('Test Kitabı', satisFiyat: 100, etiketFiyat: 150));

    expect(find.textContaining('150,00'), findsWidgets);
    expect(find.textContaining('yalnızca referanstır'), findsOneWidget,
        reason: 'etiket fiyatın hesaba girmediği kullanıcıya söylenmeli');
  });

  testWidgets('virgüllü fiyat okunur (37,45)', (t) async {
    final repo = await ac(t, urun('Test Kitabı'));

    await t.enterText(find.byKey(K.fiyatSatis), '37,45');
    await t.pump();
    await t.tap(find.byKey(K.fiyatKaydet));
    await t.pumpAndSettle();

    expect(repo.sonSatis, 37.45, reason: 'Türkçe ondalık ayracı desteklenmeli');
  });

  testWidgets('stok takibi kapatılabilir (K13)', (t) async {
    final repo = await ac(t, urun('Test Kitabı', satisFiyat: 50));

    await t.tap(find.byKey(K.fiyatStokTakibi));
    await t.pump();
    await t.tap(find.byKey(K.fiyatKaydet));
    await t.pumpAndSettle();

    expect(repo.sonStokTakibi, false);
  });
}
