import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:islerpro/data/repositories/org_repository.dart';
import 'package:islerpro/features/settings/presentation/devir_diyalogu.dart';

import 'sahte_depolar.dart';

/// K34 (W-2) · Portföy devri zorunludur.
/// Devredilmezse o carilerden gelen talepler hiçbir gelen kutusuna düşmez.
void main() {
  Future<SahteOrgRepo> ac(WidgetTester t, StaffRow hedef,
      {List<StaffRow> adaylar = const []}) async {
    final repo = SahteOrgRepo();
    await t.pumpWidget(ProviderScope(
      overrides: [orgRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        home: Scaffold(
          body: DevirDiyalogu(uye: hedef, adaylar: adaylar),
        ),
      ),
    ));
    await t.pump();
    return repo;
  }

  VoidCallback? pasifeAlButonu(WidgetTester t) => t
      .widget<FilledButton>(find.widgetWithText(FilledButton, 'Pasife al'))
      .onPressed;

  testWidgets('portföyü olan üye devralan seçilmeden pasife alınamaz',
      (t) async {
    await ac(t, uye('Ahmet Yılmaz', portfoy: 37),
        adaylar: [uye('Ayşe Demir', id: 'u3')]);

    expect(find.textContaining('37 cari'), findsOneWidget,
        reason: 'kaç cari etkileneceği gösterilmeli');
    expect(find.textContaining('hiçbir gelen kutusuna'), findsOneWidget,
        reason: 'sonucu açıkça yazmalı');
    expect(pasifeAlButonu(t), isNull, reason: 'devralan seçilmeden kapalı olmalı');
  });

  testWidgets('devralan seçilince buton açılır ve devir yapılır', (t) async {
    final repo = await ac(t, uye('Ahmet Yılmaz', portfoy: 37),
        adaylar: [uye('Ayşe Demir', id: 'u3')]);

    await t.tap(find.byType(DropdownButtonFormField<String>));
    await t.pumpAndSettle();
    await t.tap(find.text('Ayşe Demir · 0 cari').last);
    await t.pumpAndSettle();

    expect(pasifeAlButonu(t), isNotNull);
    await t.tap(find.widgetWithText(FilledButton, 'Pasife al'));
    await t.pumpAndSettle();

    expect(repo.cagrilar, contains('pasifeAl:u2'));
    expect(repo.sonDevralan, 'u3', reason: 'seçilen kişiye devredilmeli');
  });

  testWidgets('portföyü boş üye doğrudan pasife alınabilir', (t) async {
    final repo = await ac(t, uye('Boş Portföy', portfoy: 0));

    expect(find.textContaining('doğrudan pasife alınabilir'), findsOneWidget);
    expect(pasifeAlButonu(t), isNotNull);

    await t.tap(find.widgetWithText(FilledButton, 'Pasife al'));
    await t.pumpAndSettle();
    expect(repo.sonDevralan, isNull);
  });

  testWidgets('devralacak aday yoksa uyarı çıkar ve buton kapalı kalır',
      (t) async {
    await ac(t, uye('Tek Pazarlamacı', portfoy: 12), adaylar: const []);

    expect(find.textContaining('Devralacak aktif pazarlamacı yok'),
        findsOneWidget);
    expect(pasifeAlButonu(t), isNull);
  });
}
