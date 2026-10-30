import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:islerpro/core/auth/session.dart';
import 'package:islerpro/core/test_keys.dart';
import 'package:islerpro/data/models/session_data.dart';
import 'package:islerpro/data/repositories/auth_repository.dart';
import 'package:islerpro/features/onboarding/presentation/kvkk_ekrani.dart';

/// K44 · Aydınlatma onayı.
///
/// Bu dosyanın varlık sebebi bir kilitlenme: **aktif öğretmen uygulamaya hiç
/// giremiyordu.** K3 gereği öğretmen işletmenin üyesi değildir, kuruma
/// bağlanır — yani `memberships` satırı yoktur ve `Session.tenantId` null
/// kalır. "Onaylıyorum" düğmesi tenant istiyordu, bu yüzden öğretmen için
/// hiçbir zaman aktifleşmiyordu; ekranda çalışan tek düğme "Çıkış yap"tı.
/// Yönlendirme onu oraya getiriyordu ama çıkışı yoktu.
void main() {
  Future<SahteAuth> ac(WidgetTester t, {required bool uyelikVar}) async {
    final repo = SahteAuth();
    t.view.physicalSize = const Size(900, 1800);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        sessionProvider.overrideWithValue(oturum(uyelikVar: uyelikVar)),
      ],
      child: const MaterialApp(home: KvkkEkrani()),
    ));
    await t.pumpAndSettle();
    return repo;
  }

  Future<void> okuduIsaretle(WidgetTester t) async {
    await t.tap(find.byType(CheckboxListTile));
    await t.pumpAndSettle();
  }

  testWidgets('okunmadan onaylanamaz', (t) async {
    await ac(t, uyelikVar: true);
    expect(t.widget<FilledButton>(find.byKey(K.kvkkOnayla)).onPressed, isNull);
  });

  testWidgets('işletme üyesi okuduktan sonra onaylayabilir', (t) async {
    final repo = await ac(t, uyelikVar: true);
    await okuduIsaretle(t);
    expect(t.widget<FilledButton>(find.byKey(K.kvkkOnayla)).onPressed,
        isNotNull);
    await t.tap(find.byKey(K.kvkkOnayla));
    await t.pumpAndSettle();
    expect(repo.onaylandi, isTrue);
  });

  testWidgets('K3 · ÖĞRETMEN de onaylayabilir — işletme üyeliği olmasa da',
      (t) async {
    final repo = await ac(t, uyelikVar: false);
    await okuduIsaretle(t);

    expect(t.widget<FilledButton>(find.byKey(K.kvkkOnayla)).onPressed, isNotNull,
        reason: 'tenant koşulu, öğretmen rolünün tamamını bu ekranda '
            'kilitliyordu');
    await t.tap(find.byKey(K.kvkkOnayla));
    await t.pumpAndSettle();
    expect(repo.onaylandi, isTrue);
    expect(repo.sonTenant, isNull,
        reason: 'onayı hangi işletmeye yazacağını SUNUCU çözer (0037)');
  });

  testWidgets('sunucu reddederse sebep ekranda kalır', (t) async {
    final repo = await ac(t, uyelikVar: false);
    repo.hata = Exception('Onay kaydedilemedi: hesabınız henüz bir '
        'işletmeye bağlı değil.');
    await okuduIsaretle(t);
    await t.tap(find.byKey(K.kvkkOnayla));
    await t.pumpAndSettle();
    expect(find.textContaining('işletmeye bağlı değil'), findsOneWidget);
  });
}

Session oturum({required bool uyelikVar}) => Session(
      data: SessionData.fromJson({
        'user': {'id': 'u1', 'ad_soyad': 'Fatma Öz', 'eposta': 'f@x.com'},
        // K3 · Öğretmenin işletme üyeliği YOKTUR; kuruma bağlanır.
        'memberships': uyelikVar
            ? [
                {'tenant_id': 't1', 'tenant_unvan': 'İşler Yayınları',
                 'role': 'pazarlamaci', 'status': 'aktif',
                 'store_id': 's1', 'store_ad': 'Merkez'}
              ]
            : [],
        'institution_memberships': uyelikVar
            ? []
            : [
                {'institution_id': 'k1', 'institution_ad': 'Y Lisesi',
                 'status': 'aktif', 'can_order_for_institution': true}
              ],
        'stores': [], 'active_periods': [], 'consent_ok': false,
      }),
      aktifRol: uyelikVar ? AppRole.pazarlamaci : AppRole.ogretmen,
    );

class SahteAuth implements AuthRepository {
  bool onaylandi = false;
  String? sonTenant;
  Object? hata;

  @override
  Future<void> onayKaydet(String? tenantId, String surum) async {
    if (hata != null) throw hata!;
    onaylandi = true;
    sonTenant = tenantId;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
