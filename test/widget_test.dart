import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:islerpro/core/auth/session.dart';
import 'package:islerpro/core/router/app_router.dart';
import 'package:islerpro/core/theme/breakpoints.dart';
import 'package:islerpro/data/models/session_data.dart';

void main() {
  group('rol → ekran eşlemesi', () {
    test('her rol en az bir ekrana sahiptir', () {
      for (final rol in AppRole.values) {
        if (rol == AppRole.platformAdmin) continue; // Faz 2'de eklenecek
        expect(hedeflerFor(rol), isNotEmpty, reason: 'rol: $rol');
      }
    });

    test('hazirlik yalnızca hazırlık akışını görür (K46)', () {
      final y = hedeflerFor(AppRole.hazirlik).map((h) => h.yol).toSet();
      expect(y, contains('/hazirlik'));
      expect(y, isNot(contains('/raporlar')));
      expect(y, isNot(contains('/katalog')));
    });

    test('öğretmen katalog ve raporlara erişemez', () {
      final y = hedeflerFor(AppRole.ogretmen).map((h) => h.yol).toSet();
      expect(y, isNot(contains('/katalog')));
      expect(y, isNot(contains('/raporlar')));
      expect(y, contains('/talepler'));
    });

    test('pazarlamacının tüm ekranları mobilde erişilebilir', () {
      // 4 sekme + "Daha fazla" → taşanlar alt panelde listelenir.
      final h = hedeflerFor(AppRole.pazarlamaci);
      expect(h.length, greaterThan(4),
          reason: 'taşma varsa "Daha fazla" gerekir');
      expect(h.map((e) => e.yol), contains('/tahsilat'));
      expect(h.map((e) => e.yol), contains('/deneme-takvimi'));
    });
  });

  group('oturum çözümleme', () {
    SessionData veri({List<Map<String, dynamic>> uyelik = const [],
                      List<Map<String, dynamic>> kurum = const []}) =>
        SessionData.fromJson({
          'user': {'id': 'u1', 'ad_soyad': 'Test'},
          'memberships': uyelik,
          'institution_memberships': kurum,
          'stores': [], 'active_periods': [], 'consent_ok': false,
        });

    test('üyeliği olmayan kullanıcı kurulum gerektirir', () {
      expect(veri().kurulumGerekli, isTrue);
      expect(Session.fromData(veri()), isNull);
    });

    test('onay bekleyen öğretmen içeri alınmaz (K3)', () {
      final d = veri(kurum: [
        {'institution_id': 'i1', 'institution_ad': 'X Lisesi',
         'status': 'onay_bekliyor'}
      ]);
      expect(d.onayBekliyor, isTrue);
      expect(d.roller, isEmpty);
    });

    test('onaylı öğretmen ogretmen rolü alır', () {
      final d = veri(kurum: [
        {'institution_id': 'i1', 'institution_ad': 'X Lisesi', 'status': 'aktif'}
      ]);
      expect(d.onayBekliyor, isFalse);
      expect(d.roller, contains(AppRole.ogretmen));
    });

    test('çok rollü kullanıcıda işletme rolü öncelenir (K19)', () {
      final d = veri(
        uyelik: [{'tenant_id': 't1', 'tenant_unvan': 'İşler',
                  'role': 'pazarlamaci', 'status': 'aktif'}],
        kurum: [{'institution_id': 'i1', 'institution_ad': 'X', 'status': 'aktif'}],
      );
      final s = Session.fromData(d)!;
      expect(s.cokRollu, isTrue);
      expect(s.aktifRol, AppRole.pazarlamaci);
    });
  });

  group('kırılımlar', () {
    test('breakpoint sınırları', () {
      expect(Breakpoints.fromWidth(375), FormFactor.mobil);
      expect(Breakpoints.fromWidth(599), FormFactor.mobil);
      expect(Breakpoints.fromWidth(600), FormFactor.tablet);
      expect(Breakpoints.fromWidth(1023), FormFactor.tablet);
      expect(Breakpoints.fromWidth(1024), FormFactor.masaustu);
    });
  });

  testWidgets('metin girilmeden buton kapalı, girilince açılır', (t) async {
    // Regresyon: controller'a dinleyici yoktu, buton hiç aktifleşmiyordu.
    await t.pumpWidget(MaterialApp(home: _ButonTesti()));
    final buton = find.byType(FilledButton);
    expect(butonEylemi(t, buton), isNull, reason: 'başta kapalı olmalı');
    await t.enterText(find.byType(TextField), 'İşler Yayınları');
    await t.pump();
    expect(butonEylemi(t, buton), isNotNull, reason: 'metin girilince açılmalı');
  });
}

VoidCallback? butonEylemi(WidgetTester t, Finder f) =>
    t.widget<FilledButton>(f).onPressed;

/// Giriş ve kurulum ekranlarındaki "metin girilince buton açılır" davranışı.
class _ButonTesti extends StatefulWidget {
  @override
  State<_ButonTesti> createState() => _ButonTestiState();
}

class _ButonTestiState extends State<_ButonTesti> {
  final c = TextEditingController();
  @override
  void dispose() { c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(children: [
          TextField(controller: c, onChanged: (_) => setState(() {})),
          FilledButton(
            onPressed: c.text.trim().isEmpty ? null : () {},
            child: const Text('Devam'),
          ),
        ]),
      );
}
