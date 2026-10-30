import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session.dart';
import '../../../core/test_keys.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/repositories/siparis_repository.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/widgets/cam.dart';
import '../../../shared/widgets/bolum.dart';
import '../../../shared/widgets/liste.dart';
import '../../../shared/widgets/parcalar.dart';
import '../../../shared/widgets/satir.dart';
import '../../notifications/presentation/bildirimler.dart';
import 'tahsilat_diyalogu.dart';

final borclularProvider = FutureProvider.autoDispose((ref) {
  final o = ref.watch(sessionProvider);
  if (o?.storeId == null) return Future.value(const <BorcluCari>[]);
  return ref.watch(siparisRepositoryProvider).borclular(o!.storeId!);
});

enum BorcSuzgec { hepsi, gecikmis, limitAsan }

class BorcSuzgecNotifier extends Notifier<BorcSuzgec> {
  @override
  BorcSuzgec build() => BorcSuzgec.hepsi;
  void ayarla(BorcSuzgec v) => state = state == v ? BorcSuzgec.hepsi : v;
}

final borcSuzgecProvider = NotifierProvider<BorcSuzgecNotifier, BorcSuzgec>(
    BorcSuzgecNotifier.new, isAutoDispose: true);

/// K7 · Borçlu listesi CARİ bazlıdır. Okul altında gruplanabilir ama
/// TOPLAM SATIRI BASILMAZ — okul öğretmenin borcunun kefili değildir.
class TahsilatEkrani extends ConsumerWidget {
  const TahsilatEkrani({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liste = ref.watch(borclularProvider);
    final suzgec = ref.watch(borcSuzgecProvider);
    final s = Theme.of(context).colorScheme;

    final hepsi = liste.value ?? const <BorcluCari>[];
    bool gecikmis(BorcluCari c) => (c.gecikmeGunu ?? 0) > 60;
    final gorunen = switch (suzgec) {
      BorcSuzgec.hepsi => hepsi,
      BorcSuzgec.gecikmis => hepsi.where(gecikmis).toList(),
      BorcSuzgec.limitAsan => hepsi.where((c) => c.limitAsildi).toList(),
    };

    return CamSayfa(
      baslik: 'Tahsilat',
      eylemler: const [BildirimZili(), SizedBox(width: T.s2)],
      onYenile: () async => ref.invalidate(borclularProvider),
      slivers: [
        ListeGovdesi<BorcluCari>(
        veri: liste.esle((_) => gorunen),
        listeKey: K.tahsilatListesi,
        ust: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // K7 · Baskın sayı SAYIDIR, tutar değil: bakiyeleri toplamak
            // okulu öğretmenin borcuna kefil göstermek olur.
            OzetSerit(
              etiket: 'Borçlu cari',
              deger: Fmt.adet(gorunen.length),
              altBilgi: 'Her cari kendi başına tahsil edilir',
              yanlar: [
                if (hepsi.any(gecikmis))
                  ('60 günü geçen', '${hepsi.where(gecikmis).length}', s.error),
                if (hepsi.any((c) => c.limitAsildi))
                  ('Limit aşan',
                      '${hepsi.where((c) => c.limitAsildi).length}', s.uyari),
              ],
            ),
            SuzgecSeridi(cipler: [
              SuzgecCipi(
                etiket: '60 günü geçen',
                sayi: hepsi.where(gecikmis).length,
                renk: s.error,
                secili: suzgec == BorcSuzgec.gecikmis,
                onTap: () => ref
                    .read(borcSuzgecProvider.notifier)
                    .ayarla(BorcSuzgec.gecikmis),
              ),
              SuzgecCipi(
                etiket: 'Limit aşan',
                sayi: hepsi.where((c) => c.limitAsildi).length,
                renk: s.uyari,
                secili: suzgec == BorcSuzgec.limitAsan,
                onTap: () => ref
                    .read(borcSuzgecProvider.notifier)
                    .ayarla(BorcSuzgec.limitAsan),
              ),
            ]),
            const Padding(
              padding: EdgeInsets.fromLTRB(T.s4, T.s3, T.s4, T.s1),
              child: KuralNotu(
                  'Bakiyeler cari bazlıdır, toplanmaz — okul, '
                  'öğretmenin borcunun kefili değildir.'),
            ),
          ],
        ),
        bos: BosDurum(
          suzgec == BorcSuzgec.hepsi
              ? 'Açık borcu olan cari yok'
              : 'Bu süzgece uyan cari yok',
          ikon: Icons.payments_outlined,
          aciklama: suzgec == BorcSuzgec.hepsi
              ? 'Bu ekran kimden ne kadar alacağın olduğunu gösterir. '
                  'Borç teslimatla doğar — sipariş açmak tek başına borç '
                  'yaratmaz.'
              : 'Süzgeci genişletirsen borçlu carilerin tamamını görürsün.',
        ),
        satir: (_, c, _) => _Satir(c: c),
        ),
      ],
    );
  }
}

class _Satir extends ConsumerWidget {
  const _Satir({required this.c});
  final BorcluCari c;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = Theme.of(context).colorScheme;
    final gecikme = c.gecikmeGunu ?? 0;
    final renk = switch (c) {
      _ when c.limitAsildi => s.error,
      _ when gecikme > 60 => s.error,
      _ when gecikme > 30 => s.uyari,
      _ => s.onSurfaceVariant,
    };

    // Tek vurgu satırı: en acil olan hangisiyse o yazılır. Eskiden üç rozet
    // yan yana diziliyordu ve hepsi aynı sesle bağırıyordu.
    final (String? vurgu, Color? vurguRenk) = switch (c) {
      _ when c.limitAsildi => ('Limit aşıldı · $gecikme gündür açık', s.error),
      _ when gecikme > 60 => ('$gecikme gündür açık', s.error),
      _ when gecikme > 0 => ('$gecikme gündür açık', s.uyari),
      _ => (null, null),
    };

    return KayitSatiri(
      key: K.borcluSatiri(c.id),
      baslik: c.unvan,
      altBilgi: [?c.kurumAd, ?c.pazarlamaci].join(' · '),
      vurgu: vurgu,
      vurguRengi: vurguRenk,
      ikon: c.tip == 'ogretmen'
          ? Icons.person_outline
          : Icons.business_outlined,
      durumRengi: renk,
      deger: Fmt.para(c.bakiye),
      degerRengi: s.error,
      // K11 · risk bakiyeden farklıysa aradaki fark çektir. Alt bilgide
      // yazıyordu ve kurum + pazarlamacı adının ardından taşıp kayboluyordu;
      // yeri zaten SAYI SÜTUNU.
      degerAlti: c.risk != c.bakiye ? 'risk ${Fmt.para(c.risk)}' : null,
      onTap: () async {
        final ok = await showDialog<bool>(
          context: context,
          builder: (_) => TahsilatDiyalogu(cari: c),
        );
        if (ok == true) ref.invalidate(borclularProvider);
      },
    );
  }
}
