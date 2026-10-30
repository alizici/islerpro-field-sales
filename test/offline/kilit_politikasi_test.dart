import 'package:flutter_test/flutter_test.dart';

import 'package:islerpro/core/security/kilit_politikasi.dart';

/// K42 · Yanlış çalışan bir kilit, olmayan kilitten daha kötüdür: güven verir.
void main() {
  final t0 = DateTime(2026, 8, 26, 10);

  KilitKarari karar({Duration? bosta, Duration? arkaPlan}) =>
      KilitPolitikasi.karar(
        simdi: t0,
        sonEtkinlik: bosta == null ? null : t0.subtract(bosta),
        arkaPlanaGecis: arkaPlan == null ? null : t0.subtract(arkaPlan),
      );

  test('ilk açılışta kilit yok — giriş ekranı zaten kendi kapısı', () {
    expect(karar(), KilitKarari.serbest);
  });

  test('arka planda 5 dakikadan az kalmışsa serbest', () {
    expect(karar(arkaPlan: const Duration(minutes: 4, seconds: 59)),
        KilitKarari.serbest);
  });

  test('arka planda 5 dakika ve üzeri kilitlenir', () {
    expect(karar(arkaPlan: const Duration(minutes: 5)), KilitKarari.kilitle);
    expect(karar(arkaPlan: const Duration(hours: 3)), KilitKarari.kilitle);
  });

  test('30 gün hareketsizlik oturumu kapatır', () {
    expect(karar(bosta: const Duration(days: 29, hours: 23)),
        KilitKarari.serbest);
    expect(karar(bosta: const Duration(days: 30)), KilitKarari.oturumuKapat);
  });

  test('hareketsizlik kilidin ÖNÜNDE gelir', () {
    // 30 gündür açılmamış cihazda biyometri sormanın anlamı yok.
    expect(karar(bosta: const Duration(days: 40),
                 arkaPlan: const Duration(minutes: 10)),
        KilitKarari.oturumuKapat);
  });

  test('cihaz saati geriye alınmışsa fark güvenilmez sayılır', () {
    expect(KilitPolitikasi.saatGeriAlinmis(t0, t0.add(const Duration(days: 1))),
        isTrue);
    expect(KilitPolitikasi.saatGeriAlinmis(t0, t0.subtract(const Duration(days: 1))),
        isFalse);
    expect(KilitPolitikasi.saatGeriAlinmis(t0, null), isFalse);
  });
}
