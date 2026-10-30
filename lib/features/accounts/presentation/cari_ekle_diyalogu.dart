import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/test_keys.dart';
import '../../../data/repositories/cari_repository.dart';
import '../../../data/repositories/kurum_repository.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/diyalog.dart';
import '../../../shared/widgets/form_kabuk.dart';
import '../../../shared/widgets/satir.dart';

final _kurumAramaProvider = FutureProvider.autoDispose
    .family<List<KurumOzet>, String>((ref, q) async {
  if (q.trim().length < 3) return const [];
  return ref.watch(kurumRepositoryProvider).ara(q: q, limit: 12);
});

/// K5 · Cari açma. Öğretmen carisi uygulama hesabı OLMADAN da açılabilir —
/// muhatabın telefonu yoksa bile ticaret yürür.
class CariEkleDiyalogu extends ConsumerStatefulWidget {
  const CariEkleDiyalogu({required this.storeId, this.kurum, super.key});
  final String storeId;
  final KurumOzet? kurum;

  @override
  ConsumerState<CariEkleDiyalogu> createState() => _CariEkleDiyaloguState();
}

class _CariEkleDiyaloguState extends ConsumerState<CariEkleDiyalogu> {
  final _unvan = TextEditingController();
  final _limit = TextEditingController();
  final _kurumAra = TextEditingController();
  String _tip = 'kurum';
  KurumOzet? _kurum;
  bool _kaydediyor = false;
  String? _hata;

  @override
  void initState() {
    super.initState();
    _kurum = widget.kurum;
    if (_kurum != null) _unvan.text = _kurum!.ad;
    _unvan.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    for (final c in [_unvan, _limit, _kurumAra]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _gecerli =>
      _unvan.text.trim().isNotEmpty && _kurum != null && !_kaydediyor;

  @override
  Widget build(BuildContext context) {
    final sonuclar = ref.watch(_kurumAramaProvider(_kurumAra.text));

    return Diyalog(
      baslik: 'Cari aç',
      // K5 · cari = muhatap. Öğretmen carisi uygulama hesabı OLMADAN da
      // açılabilir; muhatabın telefonu yoksa bile ticaret yürür.
      altBaslik: 'Cari, borcun muhatabıdır',
      hata: _hata,
      mesgul: _kaydediyor,
      onayEtiketi: 'Cari aç',
      onayKey: K.cariEkleKaydet,
      onOnay: _gecerli ? _kaydet : null,
      children: [
        SegmentedButton<String>(
          key: K.cariEkleTip,
          segments: const [
            ButtonSegment(value: 'kurum', label: Text('Kurumsal')),
            ButtonSegment(value: 'ogretmen', label: Text('Öğretmen')),
          ],
          selected: {_tip},
          onSelectionChanged: (v) => setState(() => _tip = v.first),
        ),
        if (_kurum == null) ...[
          TextField(
            controller: _kurumAra,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
                labelText: 'Kurum',
                hintText: 'En az 3 harf yazın…',
                prefixIcon: Icon(Icons.search, size: 18)),
          ),
          sonuclar.maybeWhen(
            data: (liste) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final k in liste.take(6))
                  KayitSatiri(
                    baslik: k.ad,
                    altBilgi: k.altBilgi,
                    ikon: Icons.school_outlined,
                    onTap: () => setState(() {
                      _kurum = k;
                      if (_tip == 'kurum' && _unvan.text.trim().isEmpty) {
                        _unvan.text = k.ad;
                      }
                    }),
                  ),
              ],
            ),
            orElse: () => const SizedBox.shrink(),
          ),
        ] else
          KayitSatiri(
            baslik: _kurum!.ad,
            altBilgi: _kurum!.altBilgi,
            ikon: Icons.check_circle_outline,
            durumRengi: Theme.of(context).colorScheme.basarili,
            sondaki: widget.kurum != null
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear, size: 16),
                    onPressed: () => setState(() => _kurum = null),
                  ),
          ),
        TextField(
          key: K.cariEkleUnvan,
          controller: _unvan,
          decoration: InputDecoration(
            labelText: 'Cari unvanı',
            helperText: _tip == 'ogretmen'
                ? 'Öğretmenin adı — kurumdan bağımsız kendi carisi'
                : 'Kurumun ticari unvanı',
          ),
        ),
        ParaAlani(
          alanKey: K.cariEkleLimit,
          controller: _limit,
          etiket: 'Kredi limiti',
          yardim: 'Yalnızca bu cariye aittir; kurum düzeyinde limit yoktur',
        ),
        // K7 · öğretmen carisi okula yansımaz.
        if (_tip == 'ogretmen')
          const Bildirim(
            'Öğretmen carisi okula yansımaz: bakiye, limit ve risk '
            'tamamen ayrıdır. Okul öğretmenin borcunun kefili değildir.',
            tip: BildirimTip.bilgi),
      ],
    );
  }

  Future<void> _kaydet() async {
    setState(() { _kaydediyor = true; _hata = null; });
    try {
      final id = await ref.read(cariRepositoryProvider).ekle(
            storeId: widget.storeId,
            institutionId: _kurum!.id,
            tip: _tip,
            unvan: _unvan.text.trim(),
            creditLimit: Fmt.sayiOku(_limit.text) ?? 0,
          );
      if (mounted) Navigator.pop(context, id);
    } catch (e) {
      if (mounted) setState(() { _kaydediyor = false; _hata = e.toString(); });
    }
  }
}
