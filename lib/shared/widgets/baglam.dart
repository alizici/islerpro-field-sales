import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/session.dart';
import '../../core/test_keys.dart';
import '../../core/theme/tokens.dart';
import 'dokunus.dart';

/// Hangi dükkan, hangi dönem — HER ekranın tepesinde.
///
/// Bu şerit bir süsleme değil, bir hata düzeltmesi. Aktif dükkan yalnızca
/// Ayarlar'ın içinde görünüyordu ve **hiçbir yerden değiştirilemiyordu**:
/// `dukkanDegistir` kodda vardı, hiçbir ekran çağırmıyordu. Sahip ilk
/// dükkanında kilitli kalıp Panel'i baştan sona ₺0,00 görüyor, sebebini
/// söyleyen tek bir işaret bulamıyordu.
///
/// Aynısı rol için de geçerliydi (`rolDegistir`). Çok rollü kullanıcı tek
/// rolde kilitliydi.
class BaglamSeridi extends ConsumerWidget {
  const BaglamSeridi({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = ref.watch(sessionProvider);
    if (o == null) return const SizedBox.shrink();
    final d = ref.watch(sessionStateProvider).data;
    final tekDukkan = (d?.stores.length ?? 0) <= 1;
    final tekDonem = (d?.activePeriods.length ?? 0) <= 1;
    final tekRol = o.roller.length <= 1;

    return Material(
      color: T.bordoKoyu,
      child: Dokunus(
        // Tek dükkan, tek dönem ve tek rol varsa seçecek bir şey yok:
        // dokunulabilir göstermek boş bir vaat olurdu.
        onTap: tekDukkan && tekDonem && tekRol
            ? null
            : () => baglamSec(context, ref),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(T.s4, T.s2, T.s4, T.s2),
            child: Row(children: [
              Container(
                width: 22, height: 22, alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: T.bordo,
                  borderRadius: BorderRadius.circular(T.rKucuk),
                ),
                child: const Text('İP', style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700,
                    fontSize: 10, letterSpacing: -0.3)),
              ),
              const SizedBox(width: T.s2),
              Flexible(
                child: Text(o.store?.ad ?? '—',
                    key: K.baglamDukkan,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFFF7EDEF),
                        fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              if (!(tekDukkan && tekDonem && tekRol))
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(Icons.expand_more, size: 15, color: T.dBordo),
                ),
              const Spacer(),
              Text(_kisaDonem(o.period?.ad),
                  key: K.baglamDonem,
                  style: const TextStyle(color: T.dBordo, fontSize: 11,
                      fontWeight: FontWeight.w500)),
            ]),
          ),
        ),
      ),
    );
  }

  /// "2025-2026 / 2. Dönem" şeride sığmıyor; ayırt eden kısım son parçası.
  static String _kisaDonem(String? ad) {
    if (ad == null || ad.isEmpty) return '—';
    final p = ad.split('/');
    return p.length > 1 ? p.last.trim() : ad;
  }
}

/// Dükkan · dönem · rol seçimi.
Future<void> baglamSec(BuildContext context, WidgetRef ref) async {
  final o = ref.read(sessionProvider);
  final d = ref.read(sessionStateProvider).data;
  if (o == null || d == null) return;

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (c) {
      final s = Theme.of(c).colorScheme;
      final t = Theme.of(c).textTheme;
      Widget baslik(String m) => Padding(
            padding: const EdgeInsets.fromLTRB(T.s4, T.s3, T.s4, T.s2),
            child: Text(m, style: t.labelSmall
                ?.copyWith(color: s.onSurfaceVariant)),
          );
      Widget secim(String ad, String? altBilgi, bool secili, VoidCallback ac) =>
          ListTile(
            dense: true,
            title: Text(ad),
            subtitle: altBilgi == null ? null : Text(altBilgi),
            trailing: secili
                ? Icon(Icons.check, size: 18, color: s.primary)
                : null,
            selected: secili,
            onTap: () { ac(); Navigator.pop(c); },
          );

      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (d.stores.length > 1) ...[
                baslik('DÜKKAN'),
                for (final x in d.stores)
                  secim(x.ad, null, x.id == o.storeId,
                      () => ref.read(sessionStateProvider.notifier)
                          .dukkanDegistir(x.id)),
              ],
              if (d.activePeriods.length > 1) ...[
                baslik('DÖNEM'),
                for (final x in d.activePeriods)
                  secim(x.ad, null, x.id == o.periodId,
                      () => ref.read(sessionStateProvider.notifier)
                          .donemDegistir(x.id)),
              ],
              if (o.roller.length > 1) ...[
                baslik('ROL'),
                for (final r in o.roller)
                  secim(r.ad, null, r == o.aktifRol,
                      () => ref.read(sessionStateProvider.notifier)
                          .rolDegistir(r)),
              ],
              const SizedBox(height: T.s3),
            ],
          ),
        ),
      );
    },
  );
}
