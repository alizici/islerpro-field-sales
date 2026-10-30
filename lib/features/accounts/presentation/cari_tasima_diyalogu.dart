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

final _kontrolProvider = FutureProvider.autoDispose
    .family<TasimaKontrol, String>(
        (ref, id) => ref.watch(cariRepositoryProvider).tasimaKontrol(id));

final _kurumAramaProvider = FutureProvider.autoDispose
    .family<List<KurumOzet>, String>((ref, q) async {
  if (q.trim().length < 3) return const [];
  return ref.watch(kurumRepositoryProvider).ara(q: q, limit: 12);
});

/// K6 · Cari taşıma. Bakiye taşınır, GEÇMİŞ HAREKETLER eski kurumda kalır —
/// çünkü sipariş ve sevkiyat satırları kendi institution_id snapshot'ını
/// taşır. Kapılar önce gösterilir; kör onay yok.
class CariTasimaDiyalogu extends ConsumerStatefulWidget {
  const CariTasimaDiyalogu({required this.cari, super.key});
  final CariDetay cari;

  @override
  ConsumerState<CariTasimaDiyalogu> createState() => _CariTasimaDiyaloguState();
}

class _CariTasimaDiyaloguState extends ConsumerState<CariTasimaDiyalogu> {
  final _ara = TextEditingController();
  final _gerekce = TextEditingController();
  KurumOzet? _hedef;
  bool _kaydediyor = false;
  String? _hata;

  @override
  void initState() {
    super.initState();
    _gerekce.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ara.dispose();
    _gerekce.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kontrol = ref.watch(_kontrolProvider(widget.cari.id));
    final sonuclar = ref.watch(_kurumAramaProvider(_ara.text));
    final engelli = kontrol.value?.engelli ?? true;

    return Diyalog(
      baslik: 'Cariyi başka kuruma taşı',
      // K6 · hiçbir hareket silinmez; taşıma günlüğü kalıcıdır.
      altBaslik: 'Geçmiş hareketler eski kurumun altında kalır',
      hata: _hata,
      mesgul: _kaydediyor,
      genislik: 460,
      onayEtiketi: 'Taşı',
      onayKey: K.cariTasiOnay,
      onOnay: (engelli || _hedef == null || _gerekce.text.trim().isEmpty)
          ? null
          : _tasi,
      children: [
        kontrol.when(
          loading: () => const DiyalogYukleniyor(boy: 60),
          error: (e, _) => Bildirim(e.toString(), tip: BildirimTip.hata),
          data: (k) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (k.engelli)
                Column(
                  key: K.cariTasiEngel,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final e in k.engeller)
                      Bildirim(e, tip: BildirimTip.hata),
                  ],
                )
              else
                Bildirim(
                  'Bakiye (${Fmt.para(k.bakiye)}) yeni kuruma taşınır. '
                  'Geçmiş satışlar ${k.kurumAd} altında kalır — okul bazlı '
                  'iş hacmi raporu bozulmaz.',
                  tip: BildirimTip.bilgi),
            ],
          ),
        ),
        TextField(
          key: K.cariTasiHedef,
          controller: _ara,
          enabled: !engelli,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
              labelText: 'Hedef kurum',
              hintText: 'En az 3 harf yazın…',
              prefixIcon: Icon(Icons.search, size: 18)),
        ),
        if (_hedef != null)
          KayitSatiri(
            baslik: _hedef!.ad,
            altBilgi: _hedef!.altBilgi,
            ikon: Icons.check_circle_outline,
            durumRengi: Theme.of(context).colorScheme.basarili,
            sondaki: IconButton(
              icon: const Icon(Icons.clear, size: 16),
              onPressed: () => setState(() => _hedef = null),
            ),
          )
        else
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
                    onTap: () => setState(() => _hedef = k),
                  ),
              ],
            ),
            orElse: () => const SizedBox.shrink(),
          ),
        TextField(
          key: K.cariTasiGerekce,
          controller: _gerekce,
          enabled: !engelli,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Gerekçe',
            helperText: 'Zorunlu — kalıcı olarak kayda geçer',
          ),
        ),
      ],
    );
  }

  Future<void> _tasi() async {
    setState(() { _kaydediyor = true; _hata = null; });
    try {
      await ref.read(cariRepositoryProvider)
          .tasi(widget.cari.id, _hedef!.id, _gerekce.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() { _kaydediyor = false; _hata = e.toString(); });
    }
  }
}
