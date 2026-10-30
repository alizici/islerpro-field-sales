import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/test_keys.dart';
import '../../core/theme/tokens.dart';
import '../../data/services/yerel_referans.dart';
import '../formatters/formatters.dart';
import 'form_kabuk.dart';

/// Ekrandaki liste cihazdaki kopyadan geldiğinde gösterilir.
///
/// Tek işi **tarihi söylemek**. "Çevrimdışı" demek yetmez: pazarlamacı
/// bakiyeye bakarak tahsilat yapıyor, o bakiyenin ne kadar eski olduğunu
/// bilmeden karar veremez. Tarih yoksa (hiç senkron yapılmamış) uyarı da
/// gösterilmez — uyduracak bir tarih yok.
class YerelKopyaUyarisi extends ConsumerWidget {
  const YerelKopyaUyarisi({this.ek, super.key});

  /// Ekrana özel ikinci cümle: "Pasif cariler bu listede yok" gibi.
  final String? ek;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(yerelReferansTarihiProvider).value;
    return Padding(
      padding: const EdgeInsets.only(bottom: T.s3),
      child: Bildirim(
        key: K.yerelKopyaUyarisi,
        [
          t == null
              ? 'Sunucuya ulaşılamıyor — cihazdaki kopya gösteriliyor.'
              : 'Sunucuya ulaşılamıyor — ${Fmt.tarihSaat(t)} '
                  'senkronundaki kopya gösteriliyor.',
          ?ek,
        ].join(' '),
        tip: BildirimTip.uyari,
      ),
    );
  }
}
