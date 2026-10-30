import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:islerpro/core/auth/session.dart';
import 'package:islerpro/data/repositories/org_repository.dart';
import 'package:islerpro/features/settings/presentation/ayarlar_ekrani.dart';

import 'sahte_depolar.dart';

void main() {
  Future<SahteOrgRepo> ac(WidgetTester t, {
    AppRole rol = AppRole.isletmeSahibi,
    List<StaffRow> ekip = const [],
    List<PendingTeacher> bekleyen = const [],
  }) async {
    final repo = SahteOrgRepo(
      dukkanListesi: [
        const StoreRow(id: 's1', ad: 'Merkez Şube', tenantId: 't1',
            il: 'Şanlıurfa', ilce: 'HALİLİYE'),
      ],
      ekipListesi: ekip,
      bekleyenListesi: bekleyen,
      donemListesi: [
        PeriodRow(id: 'p1', ad: '2025-2026 / 2. Dönem', status: 'aktif',
            startsOn: DateTime(2026, 2), endsOn: DateTime(2026, 8, 31)),
        PeriodRow(id: 'p0', ad: '2025-2026 / 1. Dönem', status: 'kapali',
            startsOn: DateTime(2025, 9), endsOn: DateTime(2026, 1, 31)),
      ],
    );
    // Ayarlar ekranı BÖLÜMLERDEN oluşuyor ve hepsi 800x600'e sığmıyor.
    // Tembel liste görünmeyeni hiç kurmadığı için sorulan şey ("bu bölümler
    // var mı") kısa pencerede cevaplanamıyor. Yükseklik veriliyor.
    t.view.physicalSize = const Size(1000, 2400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [
        orgRepositoryProvider.overrideWithValue(repo),
        sessionProvider.overrideWithValue(testOturumu(rol: rol)),
      ],
      child: const MaterialApp(home: AyarlarEkrani()),
    ));
    await t.pumpAndSettle();
    return repo;
  }

  testWidgets('sahip dükkan, ekip ve dönem bölümlerini görür', (t) async {
    await ac(t, ekip: [uye('Ahmet Yılmaz', portfoy: 12)]);

    expect(find.text('İşler Yayınları'), findsOneWidget);
    expect(find.text('Merkez Şube'), findsWidgets);
    expect(find.text('Ahmet Yılmaz'), findsOneWidget);
    expect(find.text('2025-2026 / 2. Dönem'), findsWidgets);
    // Rozet değil vurgu satırı: kapalı dönemin SONUCU da yazılı (K8).
    expect(find.textContaining('Aktif dönem'), findsWidgets);
    expect(find.textContaining('Kapalı — yeni kayıt açılamaz'), findsOneWidget);
  });

  testWidgets('pazarlamacı dükkan ekleyemez, davet gönderemez', (t) async {
    await ac(t, rol: AppRole.pazarlamaci, ekip: [uye('Ahmet Yılmaz')]);

    expect(find.widgetWithText(TextButton, 'Ekle'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Davet et'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Sonraki dönem'), findsNothing);
  });

  testWidgets('sahip için yönetim eylemleri görünür', (t) async {
    await ac(t, ekip: [uye('Ahmet Yılmaz')]);

    expect(find.widgetWithText(TextButton, 'Ekle'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Davet et'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Sonraki dönem'), findsOneWidget);
  });

  testWidgets('işletme sahibi pasife alınamaz (buton yok)', (t) async {
    await ac(t, ekip: [
      uye('Mahmut Kaya', rol: AppRole.isletmeSahibi, id: 'u1'),
      uye('Ahmet Yılmaz', id: 'u2'),
    ]);
    // Yalnızca pazarlamacı satırında pasife alma düğmesi olmalı.
    expect(find.byIcon(Icons.person_off_outlined), findsOneWidget);
  });

  group('K3 · öğretmen onayı', () {
    testWidgets('bekleyen yoksa bölüm hiç görünmez', (t) async {
      await ac(t);
      expect(find.text('Onay bekleyen öğretmenler'), findsNothing);
    });

    testWidgets('bekleyen varsa sayısıyla listelenir', (t) async {
      await ac(t, bekleyen: [
        const PendingTeacher(userId: 'o1', adSoyad: 'Ayşe Öğretmen',
            institutionId: 'i1', institutionAd: 'Şanlıurfa Anadolu Lisesi',
            ilce: 'HALİLİYE'),
      ]);
      expect(find.text('Onay bekleyen öğretmenler'), findsOneWidget);
      expect(find.text('Ayşe Öğretmen'), findsOneWidget);
      expect(find.textContaining('katalog ve fiyat göremez'), findsOneWidget,
          reason: 'K3: onaysız hesabın kısıtı ekranda yazmalı');
    });

    testWidgets('onayda kurum adına sipariş yetkisi ayrıca sorulur (Y-15)',
        (t) async {
      final repo = await ac(t, bekleyen: [
        const PendingTeacher(userId: 'o1', adSoyad: 'Ayşe Öğretmen',
            institutionId: 'i1', institutionAd: 'X Lisesi'),
      ]);

      await t.tap(find.widgetWithText(FilledButton, 'Onayla'));
      await t.pumpAndSettle();

      expect(find.text('Kurum adına sipariş verebilir'), findsOneWidget);
      await t.tap(find.byType(CheckboxListTile));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Onayla').last);
      await t.pumpAndSettle();

      expect(repo.cagrilar, contains('onayla:o1:kurumAdina=true'));
    });
  });
}
