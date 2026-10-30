import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/test_keys.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/repositories/ticari_repository.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/widgets/cam.dart';
import '../../../shared/widgets/bolum.dart';
import '../../../shared/widgets/liste.dart';
import '../../../shared/widgets/parcalar.dart';
import '../../../shared/widgets/satir.dart';
import 'konsinye_kapatma_ekrani.dart';
import 'ticari_durumu.dart';

/// K45 · Konsinye.
///
/// Konsinye DEFTERİ yoktur — açık konsinye bırakılan, satılan ve iade edilen
/// adetlerden türetilir. Bu ekran o türetmeyi gösterir ve kapatma akışına
/// götürür; kendi başına hiçbir sayaç tutmaz.
///
/// Y-13 · Konsinye limite girmez: mülkiyet hâlâ dükkandadır, alacak değildir.
/// Ama görünmez de olmaz — 0 ₺ bakiyeli bir cari 40.000 ₺ konsinye
/// taşıyorsa bu ekranda görülür.
class KonsinyeEkrani extends ConsumerWidget {
  const KonsinyeEkrani({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = ref.watch(konsinyeCarilerProvider);
    final cariler = l.value ?? const <KonsinyeCari>[];
    final toplamAdet = cariler.fold<double>(0, (a, c) => a + c.kalanAdet);

    return CamSayfa(
      baslik: 'Konsinye',
      onYenile: () async => ticariTazele(ref),
      eylemler: [
        IconButton(
          tooltip: 'Yenile',
          onPressed: () => ticariTazele(ref),
          icon: const Icon(Icons.refresh, size: 20),
        ),
        const SizedBox(width: T.s2),
      ],
      slivers: [
        ListeGovdesi<KonsinyeCari>(
        veri: l,
        listeKey: K.konsinyeListesi,
        ust: Column(mainAxisSize: MainAxisSize.min, children: [
          // Baskın sayı ADETTİR, tutar değil: konsinye alacak değil,
          // mülkiyeti hâlâ dükkanda olan maldır (Y-13).
          OzetSerit(
            etiket: 'Sahadaki açık konsinye',
            deger: '${Fmt.adet(toplamAdet)} adet',
            altBilgi: '${Fmt.adet(cariler.length)} caride duruyor',
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(T.s4, T.s3, T.s4, T.s1),
            child: KuralNotu(
                'Bırakılan − satılan − iade · defteri yok, hareketlerden '
                'türetilir. Limite girmez: mülkiyet hâlâ dükkanda.'),
          ),
        ]),
        bos: const BosDurum(
          'Açık konsinye yok',
          ikon: Icons.assignment_turned_in_outlined,
          aciklama: 'Konsinye, satılmak üzere bırakılan maldır: mülkiyeti '
              'hâlâ dükkanda, borç doğurmaz. Satılan kısım bildirilince '
              'borca, kalanı iadeye döner. Şu an bırakılan her şey '
              'kapatılmış.',
        ),
        satir: (_, c, _) => _Satir(c: c),
        ),
      ],
    );
  }
}

class _Satir extends ConsumerWidget {
  const _Satir({required this.c});
  final KonsinyeCari c;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = Theme.of(context).colorScheme;
    return KayitSatiri(
      key: K.konsinyeCari(c.id),
      baslik: c.unvan,
      altBilgi: [?c.kurumAd, ?c.pazarlamaci].join(' · '),
      ikon: Icons.assignment_return_outlined,
      durumRengi: s.bilgi,
      deger: '${Fmt.adet(c.kalanAdet)} adet',
      sondaki: Padding(
        padding: const EdgeInsets.only(left: T.s2),
        child: Icon(Icons.chevron_right, size: 16, color: s.onSurfaceVariant),
      ),
      onTap: () async {
        await Navigator.of(context).push<bool>(MaterialPageRoute(
            builder: (_) =>
                KonsinyeKapatmaEkrani(cariId: c.id, unvan: c.unvan)));
        ticariTazele(ref);
      },
    );
  }
}
