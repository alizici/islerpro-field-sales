import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import 'kilit_politikasi.dart';

/// Kilit sayaçlarının durduğu yer.
///
/// Kasa arkasına küçük bir arayüz koyduk: güvenlik mantığı bir eklentiye
/// bağlı kalırsa test edilemez, test edilemeyen güvenlik de güvenlik değildir.
abstract interface class KilitDeposu {
  Future<String?> oku(String ad);
  Future<void> yaz(String ad, String deger);
  Future<void> sil(String ad);
}

/// Zaman damgaları yerel VERİTABANINDA değil cihaz kasasında tutulur:
/// veritabanı 30 günlük hareketsizlikte silinen şeyin ta kendisi; silinen
/// yerden "ne zaman silmeliyim" bilgisi okunamaz.
class KasaDeposu implements KilitDeposu {
  const KasaDeposu([this._kasa = const FlutterSecureStorage(
      iOptions:
          IOSOptions(accessibility: KeychainAccessibility.first_unlock))]);
  final FlutterSecureStorage _kasa;

  @override
  Future<String?> oku(String ad) => _kasa.read(key: ad);
  @override
  Future<void> yaz(String ad, String deger) =>
      _kasa.write(key: ad, value: deger);
  @override
  Future<void> sil(String ad) => _kasa.delete(key: ad);
}

/// Biyometri/PIN. Cihaz destekliyor mu ve doğrulama geçti mi.
abstract interface class Dogrulayici {
  Future<bool> destekli();
  Future<bool> dogrula();
}

class CihazDogrulayici implements Dogrulayici {
  CihazDogrulayici([LocalAuthentication? auth])
      : _auth = auth ?? LocalAuthentication();
  final LocalAuthentication _auth;

  @override
  Future<bool> destekli() async {
    if (kIsWeb) return false;
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// Biyometri yoksa cihaz parolasına düşer (`biometricOnly: false`).
  @override
  Future<bool> dogrula() async {
    try {
      return await _auth.authenticate(
        localizedReason:
            'İşlerPro kilitli — devam etmek için kimliğinizi doğrulayın',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}

class KilitDurumu {
  const KilitDurumu({
    this.kilitli = false,
    this.cihazDestekliyor = true,
    this.hazir = false,
  });

  final bool kilitli;

  /// Cihazda hiç ekran kilidi yoksa biyometri/PIN sorulamaz. Olmayan bir
  /// güvenliği varmış gibi göstermek yerine bunu açıkça taşıyoruz — Senkron
  /// ekranı durumu yazıyor.
  final bool cihazDestekliyor;

  /// İlk denetim yapıldı mı.
  final bool hazir;

  KilitDurumu kopya({bool? kilitli, bool? cihazDestekliyor, bool? hazir}) =>
      KilitDurumu(
        kilitli: kilitli ?? this.kilitli,
        cihazDestekliyor: cihazDestekliyor ?? this.cihazDestekliyor,
        hazir: hazir ?? this.hazir,
      );
}

/// K42 · Kilit kapısı. Politikayı uygular, sayaçları tutar.
class KilitKapisi {
  const KilitKapisi({
    required this.oturumuKapat,
    required this.depo,
    required this.dogrulayici,
    this.saat = DateTime.now,
  });

  final Future<void> Function() oturumuKapat;
  final KilitDeposu depo;
  final Dogrulayici dogrulayici;
  final DateTime Function() saat;

  static const _sonEtkinlik = 'kilit_son_etkinlik';
  static const _arkaPlan = 'kilit_arka_plan';

  Future<DateTime?> _oku(String ad) async {
    final s = await depo.oku(ad);
    return s == null ? null : DateTime.tryParse(s);
  }

  Future<void> arkaPlanaGecti() async {
    final t = saat();
    await depo.yaz(_arkaPlan, t.toIso8601String());
    await depo.yaz(_sonEtkinlik, t.toIso8601String());
  }

  Future<KilitKarari> denetle() async {
    final simdi = saat();
    final sonEtkinlik = await _oku(_sonEtkinlik);
    final arkaPlan = await _oku(_arkaPlan);

    // Cihaz saati geriye alınmışsa ölçüm güvenilmez. "Zaman geçmemiş" saymak,
    // saati geri alarak kilidi atlatmayı mümkün kılardı.
    if (KilitPolitikasi.saatGeriAlinmis(simdi, arkaPlan) ||
        KilitPolitikasi.saatGeriAlinmis(simdi, sonEtkinlik)) {
      return KilitKarari.kilitle;
    }

    final karar = KilitPolitikasi.karar(
        simdi: simdi, sonEtkinlik: sonEtkinlik, arkaPlanaGecis: arkaPlan);
    if (karar == KilitKarari.serbest) {
      await depo.yaz(_sonEtkinlik, simdi.toIso8601String());
    }
    return karar;
  }

  Future<void> acildi() async {
    await depo.yaz(_sonEtkinlik, saat().toIso8601String());
    await depo.sil(_arkaPlan);
  }
}

class KilitN extends Notifier<KilitDurumu> {
  late final KilitKapisi _kapi;

  /// İlk denetim yalnızca BİR KEZ çalışır. `build()` de, kilit kapısı widget'ı
  /// da başlatmak isteyebilir; ikisi de aynı Future'ı bekler, yoksa oturum iki
  /// kez kapatılabilirdi.
  Future<void>? _denetim;

  @override
  KilitDurumu build() {
    _kapi = ref.watch(kilitKapisiProvider);
    // Ölçüm KİM SORARSA SORSUN yapılır. Önceden yalnızca kilit kapısı widget'ı
    // `baslat()` çağırıyordu; o ağaçta yokken güvenlik bölümü cihaza hiç
    // sormadan "Açık" diyordu — yani en kötü yalanı söylüyordu.
    Future.microtask(baslat);
    return const KilitDurumu();
  }

  Future<void> baslat() => _denetim ??= _ilkDenetim();

  /// Denetim ASENKRON: cihaza sormak, kasadan okumak ve gerekirse oturumu
  /// kapatmak zaman alır. Bu sırada provider yok edilmiş olabilir (uygulama
  /// kapanışı, oturum değişimi) — o hâlde `state` yazmak
  /// `UnmountedRefException` atar. macOS koşusunda testler arası uygulama
  /// yıkımı bu yarışı her seferinde tetikledi; mobilde nadiren görülüyordu.
  ///
  /// Yazmadan önce kontrol etmek yetmez, her `await`'ten SONRA kontrol
  /// gerekir: yarış aradaki her boşlukta açılabilir.
  void _yaz(KilitDurumu d) {
    if (ref.mounted) state = d;
  }

  Future<void> _ilkDenetim() async {
    if (!await _kapi.dogrulayici.destekli()) {
      _yaz(const KilitDurumu(cihazDestekliyor: false, hazir: true));
      return;
    }
    if (!ref.mounted) return;
    final karar = await _kapi.denetle();
    if (karar == KilitKarari.oturumuKapat) {
      await _kapi.oturumuKapat();
      await _kapi.acildi();
      _yaz(const KilitDurumu(hazir: true));
      return;
    }
    _yaz(KilitDurumu(kilitli: karar == KilitKarari.kilitle, hazir: true));
  }

  Future<void> arkaPlanaGecti() => _kapi.arkaPlanaGecti();

  Future<void> oneGeldi() async {
    if (!state.cihazDestekliyor) return;
    final karar = await _kapi.denetle();
    if (!ref.mounted) return;
    if (karar == KilitKarari.oturumuKapat) {
      await _kapi.oturumuKapat();
      await _kapi.acildi();
      _yaz(state.kopya(kilitli: false));
      return;
    }
    if (karar == KilitKarari.kilitle) _yaz(state.kopya(kilitli: true));
  }

  Future<bool> ac() async {
    final oldu = await _kapi.dogrulayici.dogrula();
    if (oldu) {
      await _kapi.acildi();
      _yaz(state.kopya(kilitli: false));
    }
    return oldu;
  }
}

/// Bellekte tutan depo — test ve web için. Kalıcı olmadığı için kilit de
/// kalıcı değildir; zaten `KapaliDogrulayici` ile birlikte kullanılıyor.
class BellekDeposu implements KilitDeposu {
  final _kayit = <String, String>{};
  @override
  Future<String?> oku(String ad) async => _kayit[ad];
  @override
  Future<void> yaz(String ad, String deger) async => _kayit[ad] = deger;
  @override
  Future<void> sil(String ad) async => _kayit.remove(ad);
}

/// Doğrulama yapamayan cihaz. `destekli() == false` olduğu için kilit hiç
/// devreye girmez ve Senkron ekranı bunu "Kapalı" diye YAZAR.
class KapaliDogrulayici implements Dogrulayici {
  const KapaliDogrulayici();
  @override
  Future<bool> destekli() async => false;
  @override
  Future<bool> dogrula() async => false;
}

/// Varsayılan GÜVENLİ ama KAPALI bir kapıdır; `main.dart` gerçeğiyle değiştirir.
///
/// Önceden burada `throw` vardı ve kilidi kullanmayan her ekranı düşürüyordu.
/// Varsayılanın patlaması yanlış: yanlış bağlanmış bir kilit, ekranda "Kapalı"
/// diye GÖRÜNMELİ — sessizce çalışıyormuş gibi de yapmamalı, uygulamayı da
/// çökertmemeli.
final kilitKapisiProvider = Provider<KilitKapisi>((ref) => KilitKapisi(
      depo: BellekDeposu(),
      dogrulayici: const KapaliDogrulayici(),
      oturumuKapat: () async {},
    ));

final kilitProvider = NotifierProvider<KilitN, KilitDurumu>(KilitN.new);
