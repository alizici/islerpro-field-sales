import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:islerpro/core/test_keys.dart';
import 'package:islerpro/data/repositories/org_repository.dart';
import 'package:islerpro/features/settings/presentation/dukkan_diyalogu.dart';

import 'sahte_depolar.dart';

/// 0018 · Dükkan kapatmak W-2 ile aynı sınıf risktir: kabı kapatırken
/// içindekiler yetim kalmamalı. Kapılar veritabanında; bu testler kullanıcının
/// kör onay VERMEDİĞİNİ doğrular.
void main() {
  Future<SahteOrgRepo> ac(WidgetTester t, Widget w, {DukkanEtki? etki}) async {
    final repo = SahteOrgRepo(
        etki: etki ?? const DukkanEtki(aktifCari: 3, aktifAtama: 2));
    await t.pumpWidget(ProviderScope(
      overrides: [orgRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(home: Scaffold(body: w)),
    ));
    await t.pumpAndSettle();
    return repo;
  }

  VoidCallback? buton(WidgetTester t, Key k) =>
      t.widget<FilledButton>(find.byKey(k)).onPressed;

  group('düzenleme', () {
    testWidgets('mevcut bilgiler forma dolu gelir', (t) async {
      await ac(t, DukkanDiyalogu(
          tenantId: 't1',
          dukkan: dukkan('Merkez Şube', il: 'Şanlıurfa', ilce: 'HALİLİYE')));

      expect(t.widget<TextField>(find.byKey(K.dukkanAd)).controller?.text,
          'Merkez Şube');
      expect(t.widget<TextField>(find.byKey(K.dukkanIlce)).controller?.text,
          'HALİLİYE');
    });

    testWidgets('boş ad kaydedilemez', (t) async {
      await ac(t, DukkanDiyalogu(tenantId: 't1', dukkan: dukkan('Merkez')));

      await t.enterText(find.byKey(K.dukkanAd), '   ');
      await t.pump();
      expect(buton(t, K.dukkanKaydet), isNull);
    });

    testWidgets('düzenleme ekleme değil güncelleme çağırır', (t) async {
      final repo = await ac(t,
          DukkanDiyalogu(tenantId: 't1', dukkan: dukkan('Merkez', id: 's9')));

      await t.enterText(find.byKey(K.dukkanAd), 'Merkez Kitabevi');
      await t.pump();
      await t.tap(find.byKey(K.dukkanKaydet));
      await t.pumpAndSettle();

      expect(repo.cagrilar, contains('dukkanGuncelle:s9:Merkez Kitabevi'));
      expect(repo.cagrilar.where((c) => c.startsWith('dukkanEkle')), isEmpty);
    });

    testWidgets('dükkan verilmezse ekleme yapar', (t) async {
      final repo = await ac(t, const DukkanDiyalogu(tenantId: 't1'));

      await t.enterText(find.byKey(K.dukkanAd), 'İkinci Şube');
      await t.pump();
      await t.tap(find.byKey(K.dukkanKaydet));
      await t.pumpAndSettle();

      expect(repo.cagrilar, contains('dukkanEkle:İkinci Şube'));
    });
  });

  group('pasifleştirme', () {
    testWidgets('etkisi sayıyla gösterilir, sonra onay açılır', (t) async {
      await ac(t, DukkanPasifDiyalogu(dukkan: dukkan('İkinci Şube', id: 's2')),
          etki: const DukkanEtki(aktifCari: 12, aktifAtama: 4));

      expect(find.byKey(K.dukkanPasifUyari), findsOneWidget);
      expect(find.textContaining('12 cari'), findsOneWidget,
          reason: 'kaç cari kapanacağı önceden söylenmeli');
      expect(find.textContaining('4 portföy'), findsOneWidget);
      expect(buton(t, K.dukkanPasifOnay), isNotNull);
    });

    testWidgets('son aktif dükkan pasife alınamaz', (t) async {
      await ac(t, DukkanPasifDiyalogu(dukkan: dukkan('Tek Şube')),
          etki: const DukkanEtki(sonDukkan: true, aktifCari: 5));

      expect(find.textContaining('tek aktif dükkan'), findsOneWidget);
      expect(buton(t, K.dukkanPasifOnay), isNull,
          reason: 'DB reddedecek — kullanıcı denemeden önce görmeli');
    });

    testWidgets('açık bakiyeli cari varsa engellenir ve tutar gösterilir',
        (t) async {
      await ac(t, DukkanPasifDiyalogu(dukkan: dukkan('Borçlu Şube')),
          etki: const DukkanEtki(borcluCari: 7, borcTutari: 48250.75,
                                 aktifCari: 20));

      expect(find.textContaining('Bakiyesi kapanmamış 7 cari'), findsOneWidget);
      expect(find.textContaining('48.250,75'), findsOneWidget,
          reason: 'ne kadar borç askıda kalacağı görünmeli');
      expect(buton(t, K.dukkanPasifOnay), isNull);
    });

    testWidgets('onaylanınca pasife alma çağrılır', (t) async {
      final repo = await ac(t,
          DukkanPasifDiyalogu(dukkan: dukkan('İkinci Şube', id: 's2')));

      await t.tap(find.byKey(K.dukkanPasifOnay));
      await t.pumpAndSettle();

      expect(repo.cagrilar, contains('dukkanDurumu:s2:false'));
    });
  });
}
