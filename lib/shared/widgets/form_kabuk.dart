import 'package:flutter/material.dart';
import '../../core/theme/tokens.dart';
import 'cam.dart';

/// Giriş ve kurulum gibi tek sütunlu formların ortak kabuğu.
class FormKabuk extends StatelessWidget {
  const FormKabuk({
    required this.baslik,
    required this.altBaslik,
    required this.children,
    this.genislik = 400,
    super.key,
  });

  final String baslik;
  final String altBaslik;
  final List<Widget> children;
  final double genislik;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CamZemin(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(T.s5),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: genislik),
              // `stretch` ŞART: varsayılan `center` hizasında metin alanları
              // tam genişlik alıyor ama düğmeler içeriklerine göre
              // daralıyordu. Aynı formda bir alan kenardan kenara, altındaki
              // düğme ortada dar bir kutu — form yarım kalmış gibi duruyor.
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      // Marka işareti KAPSÜL değil yuvarlak kare: uygulama
                      // simgesinin kendi biçimi bu ve simge kapsüle dönüşünce
                      // "İP" bir düğme gibi okunuyor.
                      child: Container(
                        width: 52, height: 52, alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: T.bordo,
                          borderRadius: BorderRadius.circular(15),
                          boxShadow: [
                            BoxShadow(
                              color: T.bordo.withValues(alpha: 0.28),
                              blurRadius: 18,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: const Text('İP',
                            style: TextStyle(color: Colors.white,
                                fontWeight: FontWeight.w700, fontSize: 18)),
                      ),
                    ),
                    const SizedBox(height: T.s4),
                    Text(baslik,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: T.s1),
                    Text(altBaslik,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                    const SizedBox(height: T.s6),
                    ...children,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Hata ve bilgi kutusu — tasarımdaki soft zeminli kart.
class Bildirim extends StatelessWidget {
  const Bildirim(this.metin, {this.tip = BildirimTip.bilgi, super.key});
  final String metin;
  final BildirimTip tip;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final (fg, bg, ikon) = switch (tip) {
      BildirimTip.hata => (T.tehlike, T.tehlikeSoft, Icons.error_outline),
      BildirimTip.uyari => (T.uyari, T.uyariSoft, Icons.info_outline),
      BildirimTip.basari => (T.basarili, T.basariliSoft, Icons.check_circle_outline),
      BildirimTip.bilgi => (T.bilgi, T.bilgiSoft, Icons.info_outline),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(T.s3),
      margin: const EdgeInsets.only(bottom: T.s3),
      decoration: BoxDecoration(
        color: s.brightness == Brightness.dark
            ? fg.withValues(alpha: 0.12) : bg,
        border: Border.all(color: fg.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(T.rGiris),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(ikon, size: 18, color: fg),
        const SizedBox(width: T.s2),
        Expanded(
          child: Text(metin,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: s.onSurface)),
        ),
      ]),
    );
  }
}

enum BildirimTip { bilgi, uyari, hata, basari }
