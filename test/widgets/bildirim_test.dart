import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:islerpro/core/test_keys.dart';
import 'package:islerpro/shared/widgets/satir.dart';
import 'package:islerpro/data/repositories/talep_repository.dart';
import 'package:islerpro/features/notifications/presentation/bildirimler.dart';

import 'sahte_depolar.dart';

/// K41 · Bildirim matrisi sabittir; her bildirim derin bağlantı taşır.
void main() {
  Future<SahteTalepRepo> ac(WidgetTester t, Widget w,
      {List<Bildirim0> liste = const []}) async {
    final repo = SahteTalepRepo()..bildirimListesi = liste;
    await t.pumpWidget(ProviderScope(
      overrides: [talepRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
          home: Scaffold(appBar: AppBar(actions: [w]), body: const SizedBox())),
    ));
    await t.pumpAndSettle();
    return repo;
  }

  testWidgets('okunmamış bildirim sayısı zilde görünür', (t) async {
    await ac(t, const BildirimZili(), liste: [
      bildirim('Yeni talep: Y Lisesi'),
      bildirim('Talebiniz karara bağlandı', id: 'b2',
          olay: 'talep_karara_baglandi'),
      bildirim('Eski bildirim', id: 'b3', okundu: true),
    ]);

    expect(find.byKey(K.bildirimSayaci), findsOneWidget);
    expect(find.text('2'), findsOneWidget,
        reason: 'yalnızca okunmamışlar sayılmalı');
  });

  testWidgets('okunmamış yoksa sayaç hiç çıkmaz', (t) async {
    await ac(t, const BildirimZili(),
        liste: [bildirim('Okundu', okundu: true)]);
    expect(find.byKey(K.bildirimSayaci), findsNothing);
  });

  testWidgets('panel bildirimleri listeler', (t) async {
    await ac(t, const BildirimZili(), liste: [
      bildirim('Yeni talep: Y Lisesi', govde: '2 kalem'),
    ]);

    await t.tap(find.byKey(K.bildirimZili));
    await t.pumpAndSettle();

    expect(find.byKey(K.bildirimListesi), findsOneWidget);
    expect(find.text('Yeni talep: Y Lisesi'), findsOneWidget);
    expect(find.textContaining('2 kalem'), findsOneWidget);
  });

  testWidgets('hepsini okundu işaretle depoya gider', (t) async {
    final repo = await ac(t, const BildirimZili(),
        liste: [bildirim('Yeni talep')]);

    await t.tap(find.byKey(K.bildirimZili));
    await t.pumpAndSettle();
    await t.tap(find.byKey(K.bildirimHepsiniOku));
    await t.pumpAndSettle();

    expect(repo.cagrilar, contains('okundu:hepsi'));
  });

  testWidgets('K41 · bildirime dokununca derin bağlantı açılır', (t) async {
    final repo = await ac(t, const BildirimZili(), liste: [
      bildirim('Yeni talep', hedefTur: 'request', hedefId: 't1'),
    ]);

    await t.tap(find.byKey(K.bildirimZili));
    await t.pumpAndSettle();
    await t.tap(find.byKey(K.bildirimSatiri('b1')));
    await t.pumpAndSettle();

    expect(repo.cagrilar, contains('okundu:b1'),
        reason: 'açılan bildirim okundu sayılmalı');
  });

  testWidgets('hedefi olmayan bildirim tıklanamaz', (t) async {
    await ac(t, const BildirimZili(),
        liste: [bildirim('Bilgi', hedefId: null)]);

    await t.tap(find.byKey(K.bildirimZili));
    await t.pumpAndSettle();
    expect(t.widget<KayitSatiri>(find.byKey(K.bildirimSatiri('b1'))).onTap,
        isNull);
  });
}
