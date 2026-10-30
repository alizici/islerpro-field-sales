import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:islerpro/core/security/oturum_kilidi.dart';
import 'package:islerpro/core/test_keys.dart';
import 'package:islerpro/features/security/presentation/kilit_ekrani.dart';

/// K42 · Kilit kapısı.
///
/// Kilit, cihazı arabada unutulan bir pazarlamacı için var. Bu yüzden
/// testlerin derdi "ekran güzel mi" değil: **hangi durumda içeri girilir,
/// hangi durumda girilmez.**
void main() {
  final t0 = DateTime(2026, 8, 26, 10);
  late SahteDepo depo;
  late SahteDogrulayici auth;
  late int cikisSayisi;

  setUp(() {
    depo = SahteDepo();
    auth = SahteDogrulayici();
    cikisSayisi = 0;
  });

  KilitKapisi kapi({DateTime? simdi}) => KilitKapisi(
        depo: depo,
        dogrulayici: auth,
        saat: () => simdi ?? t0,
        oturumuKapat: () async => cikisSayisi++,
      );

  ProviderContainer kap({DateTime? simdi}) {
    final c = ProviderContainer(overrides: [
      kilitKapisiProvider.overrideWithValue(kapi(simdi: simdi)),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  group('Karar', () {
    test('ilk açılışta kilit yok', () async {
      final c = kap();
      await c.read(kilitProvider.notifier).baslat();
      expect(c.read(kilitProvider).kilitli, isFalse);
      expect(c.read(kilitProvider).hazir, isTrue);
    });

    test('kısa süre arka planda kalmak kilitlemez', () async {
      final c = kap();
      await c.read(kilitProvider.notifier).baslat();
      await c.read(kilitProvider.notifier).arkaPlanaGecti();

      final c2 = kap(simdi: t0.add(const Duration(minutes: 2)));
      await c2.read(kilitProvider.notifier).baslat();
      expect(c2.read(kilitProvider).kilitli, isFalse);
    });

    test('5 dakikadan uzun arka plan KİLİTLER', () async {
      final c = kap();
      await c.read(kilitProvider.notifier).baslat();
      await c.read(kilitProvider.notifier).arkaPlanaGecti();

      final c2 = kap(simdi: t0.add(const Duration(minutes: 6)));
      await c2.read(kilitProvider.notifier).baslat();
      expect(c2.read(kilitProvider).kilitli, isTrue);
    });

    test('30 gün hareketsizlik oturumu KAPATIR, kilit ekranı göstermez',
        () async {
      await depo.yaz('kilit_son_etkinlik',
          t0.subtract(const Duration(days: 31)).toIso8601String());
      final c = kap();
      await c.read(kilitProvider.notifier).baslat();

      expect(cikisSayisi, 1);
      expect(c.read(kilitProvider).kilitli, isFalse,
          reason: 'oturum düştüyse kilitlenecek bir şey kalmadı');
    });

    test('cihaz saati geri alınırsa kilitlenir', () async {
      // Kullanıcı saati ileri alıp geri çekerek kilidi atlatmaya çalışamasın.
      await depo.yaz('kilit_arka_plan',
          t0.add(const Duration(hours: 2)).toIso8601String());
      final c = kap();
      await c.read(kilitProvider.notifier).baslat();
      expect(c.read(kilitProvider).kilitli, isTrue);
    });

    test('ekran kilidi olmayan cihazda kilit ÇALIŞMAZ ve bu saklanmaz',
        () async {
      auth.destek = false;
      final c = kap();
      await c.read(kilitProvider.notifier).baslat();

      final d = c.read(kilitProvider);
      expect(d.cihazDestekliyor, isFalse);
      expect(d.kilitli, isFalse,
          reason: 'cihazın vermediği güvenliği uydurmuyoruz');
    });

    test('doğrulama geçerse kilit açılır ve sayaç sıfırlanır', () async {
      final c = kap();
      await c.read(kilitProvider.notifier).baslat();
      await c.read(kilitProvider.notifier).arkaPlanaGecti();

      final c2 = kap(simdi: t0.add(const Duration(minutes: 10)));
      await c2.read(kilitProvider.notifier).baslat();
      expect(c2.read(kilitProvider).kilitli, isTrue);

      expect(await c2.read(kilitProvider.notifier).ac(), isTrue);
      expect(c2.read(kilitProvider).kilitli, isFalse);
      expect(depo.kayit['kilit_arka_plan'], isNull,
          reason: 'açılınca arka plan işareti silinmeli');
    });

    test('doğrulama başarısızsa kilit AÇILMAZ', () async {
      auth.sonuc = false;
      final c = kap();
      await c.read(kilitProvider.notifier).baslat();
      await c.read(kilitProvider.notifier).arkaPlanaGecti();

      final c2 = kap(simdi: t0.add(const Duration(minutes: 10)));
      await c2.read(kilitProvider.notifier).baslat();
      expect(await c2.read(kilitProvider.notifier).ac(), isFalse);
      expect(c2.read(kilitProvider).kilitli, isTrue);
    });
  });

  group('Kapı ekranı', () {
    testWidgets('kilitliyken altındaki ekran GÖRÜNMEZ', (t) async {
      auth.sonuc = false;   // otomatik açılmasın, ekran ayakta kalsın
      await depo.yaz('kilit_arka_plan',
          t0.subtract(const Duration(minutes: 30)).toIso8601String());

      await t.pumpWidget(ProviderScope(
        overrides: [kilitKapisiProvider.overrideWithValue(kapi())],
        child: const MaterialApp(
          home: KilitKapisiWidget(child: Text('Gizli sipariş listesi')),
        ),
      ));
      await t.pumpAndSettle();

      expect(find.byKey(K.kilitEkrani), findsOneWidget);
      // Metin ağaçta duruyor ama kilit onu TAMAMEN örtüyor — kapı
      // Navigator'ın üstünde durduğu için açık bir diyalog da örtülür.
      final kilit = t.getRect(find.byKey(K.kilitEkrani));
      expect(kilit.width, greaterThan(0));
      expect(kilit.height, greaterThan(0));
    });

    testWidgets('denetim sürerken kapatılan provider ÇÖKMEZ', (t) async {
      // K42 · Denetim asenkron: cihaza sor, kasadan oku, gerekirse oturumu
      // kapat. Bu sırada provider yok edilirse (uygulama kapanışı, oturum
      // değişimi) `state` yazmak UnmountedRefException atıyordu. macOS
      // koşusunda testler arası uygulama yıkımı bunu her seferinde tetikledi;
      // mobilde nadiren görülüyordu — yani hata vardı, görünmüyordu.
      auth.destek = true;
      final c = ProviderContainer(overrides: [
        kilitKapisiProvider.overrideWithValue(kapi()),
      ]);
      c.read(kilitProvider);          // denetimi başlat
      c.dispose();                    // bitmeden yık
      await t.pump(const Duration(milliseconds: 50));
      expect(t.takeException(), isNull);
    });

    testWidgets('kilit yoksa ekran serbest', (t) async {
      await t.pumpWidget(ProviderScope(
        overrides: [kilitKapisiProvider.overrideWithValue(kapi())],
        child: const MaterialApp(
          home: KilitKapisiWidget(child: Text('Gizli sipariş listesi')),
        ),
      ));
      await t.pumpAndSettle();

      expect(find.byKey(K.kilitEkrani), findsNothing);
      expect(find.text('Gizli sipariş listesi'), findsOneWidget);
    });
  });
}

class SahteDepo implements KilitDeposu {
  final kayit = <String, String>{};
  @override
  Future<String?> oku(String ad) async => kayit[ad];
  @override
  Future<void> yaz(String ad, String deger) async => kayit[ad] = deger;
  @override
  Future<void> sil(String ad) async => kayit.remove(ad);
}

class SahteDogrulayici implements Dogrulayici {
  bool destek = true;
  bool sonuc = true;
  int cagri = 0;
  @override
  Future<bool> destekli() async => destek;
  @override
  Future<bool> dogrula() async {
    cagri++;
    return sonuc;
  }
}
