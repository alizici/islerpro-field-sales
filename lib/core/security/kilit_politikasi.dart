/// K42 · Cihaz kilidi kuralları.
///
/// Saf mantık: zaman dışarıdan verilir, platform çağrısı yoktur. Güvenlik
/// kuralının "5 dakika mı 50 dakika mı" sorusu bir kenara, kuralın kendisi
/// test edilebilir olmalı — yanlış çalışan bir kilit, olmayan kilitten daha
/// kötüdür çünkü güven verir.
enum KilitKarari {
  /// Kullanıcı içeri girebilir.
  serbest,

  /// Arka planda eşikten uzun kaldı: biyometri/PIN istenir, oturum durur.
  kilitle,

  /// Uzun süredir hiç kullanılmadı: oturum kapatılır ve yerel veri silinir.
  oturumuKapat,
}

abstract final class KilitPolitikasi {
  /// Arka planda bu süreden uzun kalınırsa kilit ekranı gelir.
  static const arkaPlan = Duration(minutes: 5);

  /// Bu süre hiç kullanılmazsa oturum kapatılır ve yerel veri silinir.
  static const hareketsizlik = Duration(days: 30);

  /// [sonEtkinlik] kullanıcının son gerçek etkileşimi, [arkaPlanaGecis]
  /// uygulamanın en son arka plana düştüğü an. İkisi de null ise (ilk açılış)
  /// karar `serbest`tir — giriş ekranı zaten kendi kapısıdır.
  static KilitKarari karar({
    required DateTime simdi,
    DateTime? sonEtkinlik,
    DateTime? arkaPlanaGecis,
  }) {
    // Hareketsizlik önce bakılır: 30 gündür açılmamış cihazda kilit ekranı
    // göstermenin anlamı yok, oturumun kendisi düşmeli.
    if (sonEtkinlik != null && simdi.difference(sonEtkinlik) >= hareketsizlik) {
      return KilitKarari.oturumuKapat;
    }
    if (arkaPlanaGecis != null &&
        simdi.difference(arkaPlanaGecis) >= arkaPlan) {
      return KilitKarari.kilitle;
    }
    return KilitKarari.serbest;
  }

  /// Cihaz saati geriye alınmışsa fark negatif çıkar. Bunu "hiç zaman
  /// geçmemiş" saymak, saati geri alarak kilidi atlatmayı mümkün kılardı;
  /// bu yüzden negatif fark KİLİT sayılır.
  static bool saatGeriAlinmis(DateTime simdi, DateTime? isaret) =>
      isaret != null && simdi.isBefore(isaret);
}
