import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import 'cam.dart';
import 'dokunus.dart';
import 'gezinme.dart';
import 'mono.dart';

/// Ekranların ortak yapı taşları.
///
/// Bunlar süsleme değil: her biri, ekrandan ekrana kopyalanan bir kalıbın tek
/// yerde toplanmış hâli. Bir ekran kendi rengini, kendi boşluğunu, kendi
/// başlık boyutunu uydurmaya başladığında arayüz "sade" değil DAĞINIK
/// görünmeye başlıyor — kullanıcı da bunu kafa karışıklığı olarak yaşıyor.

/// Bölüm başlığı. Kart açmadan, yalnızca ayırmak için.
class BolumBasligi extends StatelessWidget {
  const BolumBasligi(this.baslik, {this.sag, this.sagRengi, super.key});
  final String baslik;
  final String? sag;
  final Color? sagRengi;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: T.s2),
        child: Row(children: [
          MikroEtiket(baslik),
          const Spacer(),
          if (sag != null)
            Text(sag!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: sagRengi,
                    fontWeight: sagRengi == null ? null : FontWeight.w600)),
        ]),
      );
}

/// Renkli zeminli ikon karesi — satırın kimliğini taşır.
class IkonKare extends StatelessWidget {
  const IkonKare(this.ikon, {this.renk, this.boy = 34, super.key});
  final IconData ikon;
  final Color? renk;
  final double boy;

  @override
  Widget build(BuildContext context) {
    final r = renk ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      width: boy,
      height: boy,
      decoration: BoxDecoration(
        color: r.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(T.rDugme),
      ),
      child: Icon(ikon, size: boy * 0.5, color: r),
    );
  }
}

/// Oranları TEK şeritte gösterir — yaşlandırma kovaları, teslim/sipariş,
/// hazırlık ilerlemesi. Dört sayıyı dört satıra yazmak yerine bir çizgi.
class OranSeridi extends StatelessWidget {
  const OranSeridi(this.dilimler, {this.kalinlik = 7, this.etiketler = true,
                   super.key});

  /// (etiket, değer, renk) — değeri sıfır olan dilim çizilmez.
  final List<(String, double, Color)> dilimler;
  final double kalinlik;
  final bool etiketler;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final toplam = dilimler.fold<double>(0, (a, b) => a + b.$2);
    if (toplam <= 0) return const SizedBox.shrink();
    final dolu = dilimler.where((d) => d.$2 > 0).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(kalinlik / 2),
          child: SizedBox(
            height: kalinlik,
            // `stretch` ŞART. Row'un varsayılan hizası `center`, bu da
            // çocuklara GEVŞEK dikey kısıt verir; çocuksuz bir `ColoredBox`
            // gevşek kısıtta izin verilen en küçük boyu alır — yani sıfır
            // yükseklik. Şerit bu yüzden hiç çizilmiyordu: kutu vardı,
            // rengi vardı, yüksekliği yoktu.
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final d in dolu)
                  Expanded(
                    flex: (d.$2 / toplam * 1000).round().clamp(1, 1000),
                    child: ColoredBox(color: d.$3),
                  ),
              ],
            ),
          ),
        ),
        if (etiketler) ...[
          const SizedBox(height: T.s1 + 1),
          Wrap(spacing: T.s3, runSpacing: 2, children: [
            for (final d in dolu)
              Text.rich(TextSpan(children: [
                TextSpan(text: '${d.$1} ',
                    style: Theme.of(context).textTheme.bodySmall),
                TextSpan(text: Fmt0.kisa(d.$2), style: TextStyle(
                    fontFamily: T.fontMono, fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _okunur(d.$3, s))),
              ])),
          ]),
        ],
        if (dolu.isEmpty) SizedBox(height: kalinlik, child: ColoredBox(
            color: s.surfaceContainerHigh)),
      ],
    );
  }

  /// Etiketteki sayının rengi.
  ///
  /// Sayı dilimin rengini taşır — ama "kalan" dilimi zemin tonunda çiziliyor
  /// (`surfaceContainerHigh`) ve o renkle yazılan sayı zeminde kayboluyordu:
  /// cari detayındaki "Kalan limit 32b" okunmuyordu. Renk zeminden yeterince
  /// ayrışmıyorsa sayı ikincil yazı rengine düşer.
  static Color _okunur(Color renk, ColorScheme s) {
    final a = renk.computeLuminance() + 0.05;
    final b = s.surface.computeLuminance() + 0.05;
    return (a > b ? a / b : b / a) < 1.5 ? s.onSurfaceVariant : renk;
  }
}

/// Şeritteki sayılar için kısa biçim — "8.428" tam yazılınca satır taşıyor.
abstract final class Fmt0 {
  static String kisa(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(v >= 10000 ? 0 : 1)}b';
    return v.toStringAsFixed(0);
  }
}

/// Sayan süzgeç çipi — "kaç tane" sorusu tıklamadan cevaplanır.
class SuzgecCipi extends StatelessWidget {
  const SuzgecCipi({
    required this.etiket,
    required this.secili,
    required this.onTap,
    this.sayi,
    this.renk,
    super.key,
  });

  final String etiket;
  final bool secili;

  /// null ise çip KAPALI çizilir. Tıklanabilir görünüp hiçbir şey yapmayan
  /// bir çip, kullanıcıya "bozuk" diye okunuyor — seçilemiyorsa görünürde de
  /// seçilemez olmalı.
  final VoidCallback? onTap;
  final int? sayi;
  final Color? renk;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final kapali = onTap == null;
    final r = renk ?? s.primary;
    final fg = kapali
        ? s.onSurfaceVariant.withValues(alpha: 0.55)
        : (secili ? s.onPrimary : (renk ?? s.onSurface));
    if (kapali) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: T.s3 + 2, vertical: 7),
        decoration: BoxDecoration(
          color: s.surfaceContainerHigh,
          border: Border.all(color: s.outlineVariant),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(etiket,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(color: fg)),
      );
    }
    return Dokunus(
      tur: DokunusTuru.nesne,
      // Süzgeç SEÇİM değiştiriyor — iOS'un titreştiği tek yer bu tür bir
      // değişim. Gezinme dokunuşları sessiz kalıyor.
      titresim: true,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: T.s3 + 2, vertical: 7),
        decoration: BoxDecoration(
          color: secili ? r : (renk?.withValues(alpha: 0.08) ??
              s.surfaceContainerLowest),
          border: Border.all(
              color: secili ? r : (renk?.withValues(alpha: 0.35) ??
                  s.outlineVariant)),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
          Text(etiket, style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: fg,
                  fontWeight: secili || renk != null
                      ? FontWeight.w600 : FontWeight.w500)),
          if (sayi != null) ...[
            const SizedBox(width: 5),
            Mono('$sayi', size: 12, weight: FontWeight.w600,
                color: secili ? s.onPrimary.withValues(alpha: 0.85) : fg),
          ],
        ]),
      ),
    );
  }
}

/// Detay ekranının eylemleri.
///
/// Dört eylemi `AppBar`a `TextButton.icon` olarak dizmek masaüstünde
/// çalışıyordu, telefonda değil: başlık eziliyor, son iki düğme ekrandan
/// taşıyordu. Eylemler artık içeriğin içinde, dokunulabilir boyda ve dar
/// ekranda alt satıra sarıyor.
class Eylem {
  const Eylem(this.ikon, this.etiket, this.onTap, {this.dugmeKey, this.renk});
  final IconData ikon;
  final String etiket;
  final VoidCallback? onTap;
  final Key? dugmeKey;
  final Color? renk;
}

class EylemCipleri extends StatelessWidget {
  const EylemCipleri(this.eylemler, {super.key});
  final List<Eylem> eylemler;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    if (eylemler.isEmpty) return const SizedBox.shrink();
    // Yatay kaydırma DEĞİL sarma: kaydırılan bir şeritte dördüncü eylem
    // ekran dışında kalıyor ve keşfedilmiyor. Sarınca iki satır oluyor,
    // hepsi görünüyor.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: T.s2),
      child: Wrap(
        spacing: T.s2,
        runSpacing: T.s2,
        children: [
          for (final e in eylemler)
            Dokunus(
              key: e.dugmeKey,
              tur: DokunusTuru.nesne,
              onTap: e.onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: T.s3 + 2, vertical: 9),
                decoration: BoxDecoration(
                  border: Border.all(color: s.outlineVariant),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(e.ikon, size: 16, color: e.renk ?? s.onSurface),
                  const SizedBox(width: 6),
                  Text(e.etiket,
                      style: Theme.of(context).textTheme.labelLarge
                          ?.copyWith(color: e.renk ?? s.onSurface)),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}

/// "Kaç sonuç var" şeridi.
///
/// Arama ve dizin ekranlarında baskın bir para sayısı yoktur; oraya
/// [OzetSerit] koymak 26 puntoyla "42" yazmak demek — ekranın en büyük
/// öğesi en önemsiz bilgi olur. Bu şerit sessiz kalır ama sorunun cevabını
/// verir: süzgeç işe yaradı mı, kaç kayıt kaldı.
class SayacSeridi extends StatelessWidget {
  const SayacSeridi(this.sol, {this.sag, this.sagRengi, super.key});
  final String sol;
  final String? sag;
  final Color? sagRengi;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(T.s1, T.s2, T.s1, T.s2),
      child: Row(children: [
        MikroEtiket(sol),
        const Spacer(),
        if (sag != null)
          Flexible(
            child: Text(sag!,
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: sagRengi,
                      fontWeight: sagRengi == null ? null : FontWeight.w600,
                    )),
          ),
      ]),
    );
  }
}

/// Süzgeç çiplerinin şeridi.
///
/// Her ekran bunu kendi eliyle kuruyordu: kimi 44 piksel yüksekliğinde,
/// kimi 46; kimi ayraç koymuş kimi koymamış. Süzgeç, ekranın ne gösterdiğini
/// söyleyen şey — ekrandan ekrana kayarsa kullanıcı her seferinde yeniden
/// arıyor.
class SuzgecSeridi extends StatelessWidget {
  const SuzgecSeridi({required this.cipler, this.sag, this.ayrac = true,
                      super.key});
  final List<Widget> cipler;

  /// Şeridin sağ ucunda sabit duran öğe (sıralama düğmesi gibi).
  final Widget? sag;
  final bool ayrac;

  @override
  Widget build(BuildContext context) {
    // Kendi zemini YOK. Süzgeç bir yüzey değil, yüzeyin üstünde duran
    // denetimler; kart gibi çizilince listeyle aynı ağırlığı alıp ikisini de
    // zayıflatıyordu.
    return SizedBox(
      child: Row(children: [
        Expanded(
          child: SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(vertical: T.s1),
              itemCount: cipler.length,
              separatorBuilder: (_, _) => const SizedBox(width: T.s2),
              itemBuilder: (_, i) => Center(child: cipler[i]),
            ),
          ),
        ),
        if (sag != null)
          Padding(
            padding: const EdgeInsets.only(right: T.s2),
            child: sag,
          ),
      ]),
    );
  }
}

/// Etiket + sayı çifti. İkincil ölçüler için; baskın sayı `SayiBloku`.
class SayiCifti extends StatelessWidget {
  const SayiCifti({required this.etiket, required this.deger,
                   this.altBilgi, this.renk, super.key});
  final String etiket, deger;
  final String? altBilgi;
  final Color? renk;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(etiket, style: t.bodyMedium),
        Mono(deger, size: 17, weight: FontWeight.w600, color: renk),
        if (altBilgi != null) Text(altBilgi!, style: t.bodySmall),
      ],
    );
  }
}

/// Ekranın altına sabitlenen eylem şeridi.
///
/// Asıl eylem listenin dibinde kaybolmamalı: telefonda kullanıcı kaydırmayı
/// bırakıp "şimdi ne yapacağım" diye düşünmek zorunda kalıyor.
class EylemSeridi extends StatelessWidget {
  const EylemSeridi({required this.child, this.altMetin, super.key});
  final Widget child;
  final String? altMetin;

  @override
  Widget build(BuildContext context) {
    final alt = MediaQuery.paddingOf(context).bottom;
    // Gezinme çubuğuyla AYNI malzeme ve aynı kenar payı: ekranın altında iki
    // farklı dilde iki çubuk olamaz. İçerik ikisinin de altından akıyor.
    return Padding(
      padding: EdgeInsets.fromLTRB(
          12, 0, 12, (alt > 0 ? alt - 6 : 12) + CubukPayi.of(context)),
      child: Cam(
        yuvarlak: 22,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(T.s3, T.s3, T.s3, T.s3),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            child,
            if (altMetin != null)
              Padding(
                padding: const EdgeInsets.only(top: T.s2),
                child: Text(altMetin!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Bir kuralı ekranda söyleyen ince şerit.
///
/// Ürünün kuralları (K7, K11, K26, K48) kullanıcıya ancak ekranda yazılıysa
/// öğretilebilir. Bunlar `Bildirim`den daha sessiz: hata değil, bilgi.
class KuralNotu extends StatelessWidget {
  const KuralNotu(this.metin, {this.ikon = Icons.info_outline, this.renk,
                  super.key});
  final String metin;
  final IconData ikon;
  final Color? renk;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final r = renk ?? s.bilgi;
    return Container(
      padding: const EdgeInsets.all(T.s3),
      decoration: BoxDecoration(
        color: r.withValues(alpha: 0.07),
        border: Border.all(color: r.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(T.rDugme),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(ikon, size: 15, color: r),
        const SizedBox(width: T.s2),
        Expanded(
          child: Text(metin, style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: r)),
        ),
      ]),
    );
  }
}

/// Kart gövdesi — `Bolum`un başlıksız, doğrudan içerik alan hâli.
/// Yüzeyi [CamKart]'ın; ikinci bir kart tanımı tutmuyoruz.
class Kart extends StatelessWidget {
  const Kart({required this.child, this.dolgu = true, super.key});
  final Widget child;
  final bool dolgu;

  @override
  Widget build(BuildContext context) => CamKart(dolgu: dolgu, child: child);
}
