import 'package:flutter/material.dart';
import '../../core/theme/tokens.dart';
import 'cam.dart';
import 'mono.dart';

/// Başlıklı kart bölümü.
///
/// Artık kendi yüzeyini çizmiyor, [CamBolum]'e devrediyor. İki ayrı bölüm
/// bileşeni tutmanın anlamı yok: aynı işi yapan iki yüzey, kaçınılmaz olarak
/// birbirinden kayıyor. Adı kalıyor çünkü otuz ekran onu çağırıyor ve
/// "bölüm" doğru kelime — değişen yalnızca neyle çizildiği.
class Bolum extends StatelessWidget {
  const Bolum({
    required this.baslik,
    required this.child,
    this.eylem,
    this.altBaslik,
    super.key,
  });

  final String baslik;
  final String? altBaslik;
  final Widget child;
  final Widget? eylem;

  @override
  Widget build(BuildContext context) => CamBolum(
        baslik: baslik,
        altBaslik: altBaslik,
        eylem: eylem,
        child: child,
      );
}

/// Durum rozeti — sipariş, dönem, üyelik durumlarında tutarlı kullanılır.
class Rozet extends StatelessWidget {
  const Rozet(this.metin, {this.renk, this.zemin, super.key});
  final String metin;
  final Color? renk, zemin;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final fg = renk ?? s.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: T.s2, vertical: 3),
      decoration: BoxDecoration(
        color: zemin ?? fg.withValues(alpha: 0.10),
        border: Border.all(color: fg.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(T.rCip),
      ),
      child: MikroEtiket(metin, color: fg),
    );
  }
}

/// Boş durum — "henüz kayıt yok" görünümü.
///
/// Boş ekran, ekranın en sık görülen hâlidir: yeni bir dükkan kurulduğunda
/// HER ekran boştur. Eskiden tek satır soluk yazıydı ve kullanıcı "bozuldu mu,
/// yükleniyor mu, benim mi yapmam gerekiyor" diye düşünüyordu. Artık üç şey
/// söylüyor: ne yok, neden yok, ne yapılabilir.
class BosDurum extends StatelessWidget {
  const BosDurum(
    this.metin, {
    this.ikon = Icons.inbox_outlined,
    this.aciklama,
    this.eylem,
    super.key,
  });

  final String metin;
  final IconData ikon;

  /// Neden boş — kural varsa kural ("Konsinyenin defteri yoktur").
  final String? aciklama;

  /// Buradan çıkış: "Yeni talep aç" gibi tek bir düğme.
  final Widget? eylem;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: T.s6, horizontal: T.s5),
      child: Column(children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: s.onSurface.withValues(alpha: 0.05),
            shape: BoxShape.circle,
          ),
          child: Icon(ikon, size: 26, color: s.onSurfaceVariant),
        ),
        const SizedBox(height: T.s3),
        Text(metin, textAlign: TextAlign.center, style: t.titleMedium),
        if (aciklama != null) ...[
          const SizedBox(height: T.s1),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(aciklama!,
                textAlign: TextAlign.center, style: t.bodySmall),
          ),
        ],
        if (eylem != null) ...[
          const SizedBox(height: T.s4),
          eylem!,
        ],
      ]),
    );
  }
}
