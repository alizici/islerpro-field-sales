import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/test_keys.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/repositories/talep_repository.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/widgets/bolum.dart';
import '../../../shared/widgets/liste.dart';
import '../../../shared/widgets/satir.dart';
import '../../../shared/widgets/form_kabuk.dart';
import '../../requests/presentation/talep_detay_ekrani.dart';

final bildirimlerProvider = FutureProvider.autoDispose(
    (ref) => ref.watch(talepRepositoryProvider).bildirimler());

/// K41 · Bildirim matrisi sabittir; kullanıcı bazlı açma/kapama Sürüm 1'de yok.
/// Her bildirim ilgili kaydın ekranına DERİN BAĞLANTI taşır.
class BildirimZili extends ConsumerWidget {
  const BildirimZili({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liste = ref.watch(bildirimlerProvider).value ?? const <Bildirim0>[];
    final okunmamis = liste.where((b) => !b.okundu).length;
    final s = Theme.of(context).colorScheme;

    return Stack(clipBehavior: Clip.none, children: [
      IconButton(
        key: K.bildirimZili,
        tooltip: 'Bildirimler',
        icon: const Icon(Icons.notifications_none, size: 20),
        onPressed: () async {
          await showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (_) => const BildirimPaneli(),
          );
          ref.invalidate(bildirimlerProvider);
        },
      ),
      if (okunmamis > 0)
        Positioned(
          right: 4, top: 4,
          child: IgnorePointer(
            child: Container(
              key: K.bildirimSayaci,
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: s.error,
                borderRadius: BorderRadius.circular(T.rCip),
              ),
              child: Text('$okunmamis',
                  style: TextStyle(fontSize: 10, height: 1.2,
                      fontWeight: FontWeight.w700, color: s.onError)),
            ),
          ),
        ),
    ]);
  }
}

class BildirimPaneli extends ConsumerWidget {
  const BildirimPaneli({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liste = ref.watch(bildirimlerProvider);
    final s = Theme.of(context).colorScheme;

    return ConstrainedBox(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(T.s4, T.s4, T.s3, T.s2),
          child: Row(children: [
            Text('Bildirimler',
                style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            TextButton(
              key: K.bildirimHepsiniOku,
              onPressed: () async {
                await ref.read(talepRepositoryProvider).bildirimleriOkundu();
                ref.invalidate(bildirimlerProvider);
              },
              child: const Text('Hepsini okundu işaretle'),
            ),
          ]),
        ),
        const Divider(height: 1),
        Flexible(
          child: liste.when(
            loading: () => const IskeletListe(satir: 4),
            error: (e, _) => Padding(
                padding: const EdgeInsets.all(T.s4),
                child: Bildirim(e.toString(), tip: BildirimTip.hata)),
            data: (b) => b.isEmpty
                ? const BosDurum('Bildirim yok',
                    ikon: Icons.notifications_none,
                    aciklama: 'Talep açıldığında, karara bağlandığında ya da '
                        '24 saati geçtiğinde burada haber verilir.')
                : ListView.separated(
                    key: K.bildirimListesi,
                    shrinkWrap: true,
                    itemCount: b.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: s.outlineVariant),
                    itemBuilder: (_, i) => _Satir(b: b[i]),
                  ),
          ),
        ),
      ]),
    );
  }
}

class _Satir extends ConsumerWidget {
  const _Satir({required this.b});
  final Bildirim0 b;

  /// K41 matrisindeki olay kodları → ikon.
  static IconData _ikon(String olay) => switch (olay) {
        'talep_acildi' => Icons.inbox_outlined,
        'talep_karara_baglandi' => Icons.rule_outlined,
        'talep_sla' => Icons.schedule_outlined,
        'siparis_onay' => Icons.gavel_outlined,
        'teslimat' => Icons.local_shipping_outlined,
        _ => Icons.notifications_none,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = Theme.of(context).colorScheme;
    // Okunmamış olan ŞERİTLE işaretli: liste tarandığında hangilerine
    // bakılmadığı, punto farkını okumadan görünüyor.
    return KayitSatiri(
      key: K.bildirimSatiri(b.id),
      baslik: b.baslik,
      altBilgi: [?b.govde, Fmt.tarihSaat(b.createdAt)].join(' · '),
      ikon: _ikon(b.olay),
      durumRengi: b.okundu ? null : s.primary,
      sondaki: b.okundu
          ? null
          : Padding(
              padding: const EdgeInsets.only(left: T.s2, top: 6),
              child: Icon(Icons.circle, size: 8, color: s.primary),
            ),
      // K41 · her bildirim ilgili kaydın ekranına derin bağlantı taşır
      onTap: b.hedefId == null ? null : () async {
        await ref.read(talepRepositoryProvider)
            .bildirimleriOkundu(idler: [b.id]);
        if (!context.mounted) return;
        Navigator.pop(context);
        if (b.hedefTur == 'request') {
          await Navigator.of(context).push<bool>(MaterialPageRoute(
              builder: (_) => TalepDetayEkrani(talepId: b.hedefId!)));
        }
      },
    );
  }
}
