import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import 'cam.dart';
import 'dokunus.dart';
import 'mono.dart';

/// İlk açılışta "şimdi ne yapacağım" sorusunun cevabı.
///
/// Yeni kurulan bir dükkanda HER ekran boştur: cari yok, talep yok, sipariş
/// yok. Uygulama bu hâlde on iki ayrı boş ekran gösteriyordu ve hiçbiri
/// nereden başlanacağını söylemiyordu — kullanıcı sekmeleri tek tek gezip
/// hepsinin boş olduğunu görüyor, sonra duruyordu.
///
/// Kart KENDİLİĞİNDEN kayboluyor: kalıcı bir "gördüm" işareti tutmuyoruz.
/// Gösterilme şartı verinin kendisi — iş çıktığı anda rehber gitmiş oluyor.
/// Kapatma düğmesi de yok; kapatılabilen bir rehber, yanlışlıkla kapatılıp
/// bir daha bulunamayan bir rehberdir.
class Baslangic extends StatelessWidget {
  const Baslangic({
    required this.baslik,
    required this.aciklama,
    this.adimlar = const [],
    super.key,
  });

  final String baslik;

  /// Bir cümlede: bu ekran ne işe yarıyor, sıradaki adım neden gerekli.
  final String aciklama;

  /// Sıralı adımlar. Boş bırakılabilir — bazen yapılacak bir şey yoktur ve
  /// doğru cevap "bekle" olur (portföyünü sahip atar).
  final List<BaslangicAdimi> adimlar;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    return CamKart(
      dolgu: false,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(T.s4, T.s4, T.s4, T.s3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Icon(Icons.flag_outlined, size: 18, color: s.primary),
                const SizedBox(width: T.s2),
                Expanded(
                  child: Text(baslik,
                      style: t.titleMedium?.copyWith(color: s.primary)),
                ),
              ]),
              const SizedBox(height: T.s2),
              Text(aciklama, style: t.bodyMedium),
            ],
          ),
        ),
        if (adimlar.isNotEmpty) ...[
          Divider(height: 1, color: s.outlineVariant.withValues(alpha: 0.55)),
          for (final (i, a) in adimlar.indexed) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.only(left: 52),
                child: Divider(
                    height: 1,
                    color: s.outlineVariant.withValues(alpha: 0.55)),
              ),
            _Adim(sira: i + 1, adim: a),
          ],
        ],
      ]),
    );
  }
}

class BaslangicAdimi {
  const BaslangicAdimi(this.metin, {this.onTap, this.tamam = false});

  final String metin;
  final VoidCallback? onTap;

  /// Adım yapılmış. Numarası yerine onay işareti çizilir — ilerlemenin
  /// görünmesi, listeyi bir görev listesine çeviren şey.
  final bool tamam;
}

class _Adim extends StatelessWidget {
  const _Adim({required this.sira, required this.adim});
  final int sira;
  final BaslangicAdimi adim;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final renk = adim.tamam ? s.basarili : s.primary;

    return Dokunus(
      onTap: adim.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: T.s4, vertical: T.s3),
        child: Row(children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: renk.withValues(alpha: adim.tamam ? 0.14 : 0.10),
              shape: BoxShape.circle,
            ),
            child: adim.tamam
                ? Icon(Icons.check, size: 14, color: renk)
                : Mono('$sira', size: 12, weight: FontWeight.w700, color: renk),
          ),
          const SizedBox(width: T.s3),
          Expanded(
            child: Text(
              adim.metin,
              style: t.bodyLarge?.copyWith(
                color: adim.tamam ? s.onSurfaceVariant : s.onSurface,
                decoration: adim.tamam ? TextDecoration.lineThrough : null,
                decorationColor: s.onSurfaceVariant,
              ),
            ),
          ),
          if (adim.onTap != null && !adim.tamam)
            Icon(Icons.chevron_right, size: 18, color: s.onSurfaceVariant),
        ]),
      ),
    );
  }
}
