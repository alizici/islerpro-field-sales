import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import 'mono.dart';
import 'cam.dart';
import 'dokunus.dart';
import 'parcalar.dart';

/// Detay ekranlarının başlığı.
///
/// Detay ekranları en çok bozulan yerdi: `AppBar`da unvan, gövdenin ilk
/// kartında yine unvan, sonra alt alta on `ListTile`. Kullanıcı "bu kayıt
/// ne durumda, ne kadar tutuyor" sorusuna cevap bulmak için okumak zorunda
/// kalıyordu.
///
/// Bant üç şeyi bir bakışta verir: KİM (unvan + bağlam), NE DURUMDA
/// (renkli üst şerit + durum yazısı), NE KADAR (tek baskın sayı).
class DetayBandi extends StatelessWidget {
  const DetayBandi({
    required this.baslik,
    this.altBilgi,
    this.durum,
    this.durumRengi,
    this.ikon,
    this.etiket,
    this.deger,
    this.degerRengi,
    this.degerAlti,
    this.yanlar = const [],
    this.alt,
    super.key,
  });

  final String baslik;
  final String? altBilgi;

  /// Durum yazısı. Renk tek başına durum anlatamaz — yazı hep vardır.
  final String? durum;
  final Color? durumRengi;
  final IconData? ikon;

  /// Baskın sayı ve başlığı. İkisi de null ise sayı bloğu çizilmez.
  final String? etiket, deger;
  final Color? degerRengi;
  final String? degerAlti;

  /// İkincil ölçüler — (etiket, değer, renk).
  final List<(String, String, Color?)> yanlar;

  /// Bandın altına eklenen serbest içerik (aşama çizgisi, kural notu).
  final Widget? alt;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final renk = durumRengi ?? s.primary;

    return CamKart(
      dolgu: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Üst şerit: durumun rengi. Ekranı açar açmaz görünen ilk şey.
          // Kartın yuvarlak üst köşesine oturması için ayrıca kırpılıyor.
          ClipRRect(
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(T.rCam)),
            child: Container(height: 3, color: renk),
          ),
          Padding(
            padding: const EdgeInsets.all(T.s4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (ikon != null) ...[
                      IkonKare(ikon!, renk: renk, boy: 38),
                      const SizedBox(width: T.s3),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(baslik, style: t.titleLarge),
                          if (altBilgi != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(altBilgi!, style: t.bodySmall),
                            ),
                          if (durum != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 5),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                      color: renk,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    durum!,
                                    style: t.labelMedium?.copyWith(
                                      color: renk,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (deger != null) ...[
                  const SizedBox(height: T.s4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (etiket != null) MikroEtiket(etiket!),
                            const SizedBox(height: 2),
                            Mono(deger!,
                                size: 28,
                                weight: FontWeight.w600,
                                color: degerRengi),
                            if (degerAlti != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child:
                                    Text(degerAlti!, style: t.bodySmall),
                              ),
                          ],
                        ),
                      ),
                      if (yanlar.isNotEmpty)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final y in yanlar)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(y.$1, style: t.bodySmall),
                                    const SizedBox(width: T.s2),
                                    Mono(y.$2,
                                        size: 13,
                                        weight: FontWeight.w600,
                                        color: y.$3),
                                  ],
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ],
                if (alt != null) ...[
                  const SizedBox(height: T.s4),
                  alt!,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Kaydın hangi aşamada olduğunu gösteren yatay çizgi.
///
/// Sipariş "hazırlanıyor" yazısı tek başına eksik bilgi: kullanıcı bundan
/// sonra ne olacağını da bilmek istiyor. Rozet bunu söyleyemez, çizgi söyler.
class AsamaCizgisi extends StatelessWidget {
  const AsamaCizgisi({
    required this.asamalar,
    required this.aktif,
    this.renk,
    this.kirik = false,
    super.key,
  });

  final List<String> asamalar;

  /// Kaçıncı aşamada — 0 tabanlı. Aşılan aşamalar dolu çizilir.
  final int aktif;
  final Color? renk;

  /// Akış koptu (reddedildi, iptal): kalan aşamalar çizilmez, aktif olan
  /// kırmızı olur.
  final bool kirik;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final r = kirik ? s.error : (renk ?? s.primary);
    return Row(
      children: [
        for (var i = 0; i < asamalar.length; i++)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i <= aktif ? r : s.surfaceContainerHigh,
                        border: i <= aktif
                            ? null
                            : Border.all(color: s.outlineVariant),
                      ),
                    ),
                    if (i < asamalar.length - 1)
                      Expanded(
                        child: Container(
                          height: 2,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          color: i < aktif ? r : s.outlineVariant,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 5),
                Padding(
                  padding: const EdgeInsets.only(right: T.s2),
                  child: Text(
                    asamalar[i],
                    maxLines: 2,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 10.5,
                          height: 1.2,
                          color: i <= aktif ? r : s.onSurfaceVariant,
                          fontWeight:
                              i == aktif ? FontWeight.w600 : FontWeight.w400,
                        ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Detaydaki "etiket … değer" satırı.
///
/// `ListTile` bunun için fazla şişkin (72px) ve etiketle değeri aynı
/// ağırlıkta gösteriyor. Burada etiket sessiz, değer okunur.
class AlanSatiri extends StatelessWidget {
  const AlanSatiri(
    this.etiket,
    this.deger, {
    this.renk,
    this.mono = false,
    this.kalin = false,
    this.ikincil,
    super.key,
  });

  final String etiket, deger;
  final Color? renk;
  final bool mono, kalin;
  final String? ikincil;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(etiket, style: t.bodySmall),
          ),
          const SizedBox(width: T.s2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (mono)
                  Mono(deger,
                      size: 13,
                      weight: kalin ? FontWeight.w600 : FontWeight.w500,
                      color: renk)
                else
                  Text(
                    deger,
                    style: t.bodyMedium?.copyWith(
                      color: renk,
                      fontWeight: kalin ? FontWeight.w600 : null,
                    ),
                  ),
                if (ikincil != null)
                  Text(ikincil!, style: t.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Bir kaydın kalemleri — sipariş satırı, talep kalemi, ekstre hareketi.
///
/// [KayitSatiri]dan farkı: burada kimlik değil MİKTAR taranır. Ürün adı
/// solda, adet ve tutar sağda hizalı; ikisi arasında birim fiyat sessizce.
class KalemSatiri extends StatelessWidget {
  const KalemSatiri({
    required this.ad,
    this.altBilgi,
    this.adet,
    this.tutar,
    this.durumRengi,
    this.durumMetni,
    this.sondaki,
    this.onTap,
    super.key,
  });

  final String ad;
  final String? altBilgi, adet, tutar, durumMetni;
  final Color? durumRengi;
  final Widget? sondaki;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Dokunus(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: T.s3, horizontal: T.s4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(ad,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodyLarge),
                  if (altBilgi != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(altBilgi!, style: t.bodySmall),
                    ),
                  if (durumMetni != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        durumMetni!,
                        style: t.labelMedium?.copyWith(
                          color: durumRengi ?? s.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: T.s3),
            if (adet != null || tutar != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (adet != null)
                    Mono(adet!, size: 13, weight: FontWeight.w600),
                  if (tutar != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Mono(tutar!,
                          size: 12, color: s.onSurfaceVariant),
                    ),
                ],
              ),
            ?sondaki,
          ],
        ),
      ),
    );
  }
}

/// Toplam satırı — kalemlerin altına çekilen çizgi ve tutar.
class ToplamSatiri extends StatelessWidget {
  const ToplamSatiri({
    required this.etiket,
    required this.deger,
    this.renk,
    this.altSatirlar = const [],
    super.key,
  });

  final String etiket, deger;
  final Color? renk;

  /// Toplamın üstündeki ara satırlar — (etiket, değer, renk).
  final List<(String, String, Color?)> altSatirlar;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(T.s4, T.s3, T.s4, T.s4),
      decoration: BoxDecoration(
        color: s.surfaceContainerHigh.withValues(alpha: 0.5),
        border: Border(top: BorderSide(color: s.outlineVariant)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final a in altSatirlar)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Expanded(child: Text(a.$1, style: t.bodySmall)),
                  Mono(a.$2, size: 12, color: a.$3),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: Text(etiket,
                    style: t.titleMedium
                        ?.copyWith(color: s.onSurfaceVariant)),
              ),
              Mono(deger,
                  size: 19,
                  weight: FontWeight.w600,
                  color: renk ?? s.onSurface),
            ],
          ),
        ],
      ),
    );
  }
}
