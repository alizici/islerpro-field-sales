import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import 'cam.dart';

/// Alt gezinme çubuğunun tek öğesi.
class GezinmeOgesi {
  const GezinmeOgesi({
    required this.ikon,
    required this.etiket,
    this.doluIkon,
    this.sayi = 0,
    this.dugmeKey,
  });

  final IconData ikon;

  /// Seçiliyken kullanılan DOLU ikon. Seçimin asıl işareti budur: aynı
  /// sembolün içi dolar. Renk tek başına yetmez — renk körlüğünde iki sekme
  /// aynı görünür, dolu/boş ayrımı ise biçimdir.
  final IconData? doluIkon;

  final String etiket;

  /// Bu sekmenin arkasında bekleyen iş sayısı. 0 ise rozet çizilmez.
  final int sayi;
  final Key? dugmeKey;
}

/// Yüzen cam gezinme çubuğu (iOS 26 · Liquid Glass).
///
/// Material'ın `NavigationBar`ı da, klasik opak iOS tab bar'ı da ekranın
/// dibine YAPIŞIK, mat bir şeritti. Bu çubuk yüzüyor: kenarlardan boşluklu,
/// kapsül köşeli, ARKASINDAN içerik akıyor.
///
/// Camın çalışması için tek şart var ve pahalı: içerik çubuğun altından
/// geçmeli. `Scaffold(extendBody: true)` bunu sağlıyor; karşılığında her
/// kaydırma görünümünün sonuna çubuk boyu kadar boşluk eklemek gerekiyor
/// ([SonBosluk]). Bu yapılmazsa son satır camın altında kalıp okunmaz —
/// güzel ama kullanılamaz bir çubuk olurdu.
///
/// Camın kendisi [Cam]'da: çubuk, başlık ve kartlar aynı malzemeden. Cam tek
/// yerde tanımlı olmazsa iki cam birbirini tutmaz ve arayüz iki farklı
/// uygulamadan derlenmiş gibi görünür.
class AltGezinme extends StatelessWidget {
  const AltGezinme({
    required this.ogeler,
    required this.secili,
    required this.onSec,
    super.key,
  });

  final List<GezinmeOgesi> ogeler;
  final int secili;
  final ValueChanged<int> onSec;

  static const yukseklik = 58.0;
  static const _kenar = 12.0;
  static const _yuvarlak = 26.0;

  /// Çubuğun kapladığı TOPLAM yükseklik: gövde + alt boşluk.
  static double toplamYukseklik(BuildContext c) {
    final alt = MediaQuery.paddingOf(c).bottom;
    return yukseklik + (alt > 0 ? alt - 6 : _kenar);
  }

  @override
  Widget build(BuildContext context) {
    if (ogeler.isEmpty) return const SizedBox.shrink();
    final alt = MediaQuery.paddingOf(context).bottom;

    return Padding(
      padding:
          EdgeInsets.fromLTRB(_kenar, 0, _kenar, alt > 0 ? alt - 6 : _kenar),
      child: Cam(
        yuvarlak: _yuvarlak,
        child: SizedBox(
          height: yukseklik,
          child: Row(
            children: [
              for (final (i, o) in ogeler.indexed)
                Expanded(
                  child: _Sekme(
                    oge: o,
                    secili: i == secili,
                    onTap: () => onSec(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Sekme extends StatelessWidget {
  const _Sekme({required this.oge, required this.secili, required this.onTap});
  final GezinmeOgesi oge;
  final bool secili;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final renk = secili ? s.primary : s.onSurfaceVariant;
    final ikon = secili ? (oge.doluIkon ?? oge.ikon) : oge.ikon;

    return Semantics(
      selected: secili,
      button: true,
      // Tek cümle: yoksa ekran okuyucu "Talepler" ve "3" diye iki parça
      // okuyor, sayının neye ait olduğu anlaşılmıyor.
      excludeSemantics: true,
      label: oge.sayi > 0 ? '${oge.etiket}, ${oge.sayi} bekleyen' : oge.etiket,
      child: GestureDetector(
        key: oge.dugmeKey,
        // iOS'ta sekmeye basınca mürekkep yayılmaz; durum anında değişir.
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: DecoratedBox(
            decoration: BoxDecoration(
              // Seçili sekme camın içinde ikinci bir cam parçası: markanın
              // rengiyle hafifçe boyanmış.
              color: secili
                  ? s.primary.withValues(alpha: 0.13)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _Ikon(ikon: ikon, sayi: oge.sayi, renk: renk),
                const SizedBox(height: 1),
                Text(
                  oge.etiket,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: T.fontSans,
                    fontSize: 10,
                    height: 1.1,
                    letterSpacing: -0.1,
                    fontWeight: secili ? FontWeight.w600 : FontWeight.w500,
                    color: renk,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Ikon extends StatelessWidget {
  const _Ikon({required this.ikon, required this.sayi, required this.renk});
  final IconData ikon;
  final int sayi;
  final Color renk;

  @override
  Widget build(BuildContext context) {
    final glif = Icon(ikon, size: 23, color: renk);
    if (sayi <= 0) return glif;

    final s = Theme.of(context).colorScheme;
    // Rozet KIRMIZI ve opak: camın saydamlığı ona bulaşmaz. Bekleyen iş
    // sayısı okunamıyorsa rozet süs olur.
    return Stack(clipBehavior: Clip.none, children: [
      glif,
      Positioned(
        left: 13,
        top: -4,
        child: Container(
          constraints: const BoxConstraints(minWidth: 17),
          height: 17,
          padding: const EdgeInsets.symmetric(horizontal: 4.5),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: s.error,
            borderRadius: BorderRadius.circular(9),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Text(
            sayi > 99 ? '99+' : '$sayi',
            style: const TextStyle(
              fontFamily: T.fontSans,
              fontSize: 10.5,
              height: 1,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
              color: Colors.white,
            ),
          ),
        ),
      ),
    ]);
  }
}


/// Yüzen çubuğun kapladığı payı ekranlara taşır.
///
/// `MediaQuery.paddingOf` bu iş için yetmiyor: her ekranın kendi `Scaffold`u
/// var ve iç içe `Scaffold`lar alt payı tüketiyor. Son satır kaydırdıkça
/// camın altında kalıp bir daha çıkmıyordu — güzel ama kullanılamaz bir
/// çubuk. Pay artık kabuktan doğrudan geliyor.
class CubukPayi extends InheritedWidget {
  const CubukPayi({required this.pay, required super.child, super.key});
  final double pay;

  static double of(BuildContext c) =>
      c.dependOnInheritedWidgetOfExactType<CubukPayi>()?.pay ?? 0;

  @override
  bool updateShouldNotify(CubukPayi eski) => eski.pay != pay;
}
