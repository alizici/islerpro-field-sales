import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/test_keys.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/repositories/siparis_repository.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/widgets/bolum.dart';
import '../../../shared/widgets/detay.dart';
import '../../../shared/widgets/cam.dart';
import '../../../shared/widgets/liste.dart';
import '../../../shared/widgets/parcalar.dart';
import '../../../shared/widgets/satir.dart';

final ekstreProvider = FutureProvider.autoDispose.family<Ekstre, String>(
    (ref, id) => ref.watch(siparisRepositoryProvider).ekstre(id));

/// K29 · Bakiye TÜRETİLMİŞTİR. Ekstre bu türetimi görünür kılar:
/// her satır bir olay kaydıdır (teslimat · tahsilat · iade), bakiye onların
/// toplamıdır. "Bakiye neden bu?" sorusunun cevabı burasıdır.
class EkstreEkrani extends ConsumerWidget {
  const EkstreEkrani({required this.cariId, required this.unvan, super.key});
  final String cariId, unvan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = ref.watch(ekstreProvider(cariId));
    final s = Theme.of(context).colorScheme;
    final x = e.value;

    return CamSayfa(
      baslik: unvan,
      slivers: [
        ListeGovdesi<EkstreSatiri>(
        veri: e.esle((v) => v.hareketler),
        listeKey: K.ekstreSatirlar,
        ust: x == null
            ? null
            : Column(mainAxisSize: MainAxisSize.min, children: [
                DetayBandi(
                  baslik: unvan,
                  altBilgi: 'Cari hesap ekstresi',
                  ikon: Icons.receipt_outlined,
                  durumRengi: x.bakiye > 0 ? s.error : s.basarili,
                  etiket: 'Bakiye',
                  deger: Fmt.para(x.bakiye),
                  degerRengi: x.bakiye > 0 ? s.error : null,
                  // K29 · bakiye yazılmaz, aşağıdaki hareketlerden çıkar.
                  degerAlti: 'Aşağıdaki hareketlerin toplamı',
                  yanlar: [
                    // K11 · risk bakiyeden farklıysa aradaki fark çektir.
                    ('Risk', Fmt.para(x.risk), null),
                    if (x.acikKonsinye > 0)
                      ('Konsinye', '${Fmt.adet(x.acikKonsinye)} adet', s.bilgi),
                  ],
                  alt: x.acikKonsinye > 0
                      ? const KuralNotu(
                          'Açık konsinye borç değildir — mülkiyet hâlâ '
                          'dükkanda, bakiyeye girmez.')
                      : null,
                ),
                SayacSeridi('${x.hareketler.length} hareket',
                    sag: 'Bakiye yazılmaz, hareketlerden türetilir'),
              ]),
        bos: const BosDurum('Hareket yok',
            ikon: Icons.receipt_long_outlined,
            aciklama: 'Bu caride henüz teslimat, tahsilat ya da iade '
                'kaydı yok — bakiyesi de bu yüzden sıfır.'),
        satir: (_, h, _) => _Satir(h: h),
        ),
      ],
    );
  }
}

class _Satir extends StatelessWidget {
  const _Satir({required this.h});
  final EkstreSatiri h;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final borc = h.borc > 0;
    // İşaret RENKTEN değil, borç mu alacak mı olduğundan geliyor: ekstrenin
    // tek işi "bu satır bakiyeyi hangi yöne itti" sorusunu cevaplamak.
    return KayitSatiri(
      baslik: h.aciklama,
      altBilgi: [
        Fmt.tarihSaat(h.tarih),
        if (h.odemeAdi.isNotEmpty) h.odemeAdi,
      ].join(' · '),
      ikon: switch (h.tur) {
        'teslimat' => Icons.local_shipping_outlined,
        'tahsilat' => Icons.payments_outlined,
        _ => Icons.assignment_return_outlined,
      },
      durumRengi: borc ? s.error : s.basarili,
      deger: borc ? '+${Fmt.para(h.borc)}' : '−${Fmt.para(h.alacak)}',
      degerRengi: borc ? s.error : s.basarili,
    );
  }
}
