import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/test_keys.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/repositories/org_repository.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/widgets/diyalog.dart';
import '../../../shared/widgets/form_kabuk.dart';

/// Dükkan ekleme ve düzenleme — aynı form. [dukkan] null ise ekleme.
class DukkanDiyalogu extends ConsumerStatefulWidget {
  const DukkanDiyalogu({required this.tenantId, this.dukkan, super.key});
  final String tenantId;
  final StoreRow? dukkan;

  @override
  ConsumerState<DukkanDiyalogu> createState() => _DukkanDiyaloguState();
}

class _DukkanDiyaloguState extends ConsumerState<DukkanDiyalogu> {
  late final _ad = TextEditingController(text: widget.dukkan?.ad ?? '');
  late final _il = TextEditingController(text: widget.dukkan?.il ?? '');
  late final _ilce = TextEditingController(text: widget.dukkan?.ilce ?? '');
  bool _kaydediyor = false;
  String? _hata;

  bool get _duzenleme => widget.dukkan != null;

  @override
  void initState() {
    super.initState();
    _ad.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    for (final c in [_ad, _il, _ilce]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Diyalog(
        baslik: _duzenleme ? 'Dükkanı düzenle' : 'Dükkan ekle',
        // K12 · fiyat, iskonto ve stok dükkana özeldir.
        altBaslik: 'Fiyat, iskonto ve stok bu dükkana özel olur',
        hata: _hata,
        mesgul: _kaydediyor,
        onayEtiketi: _duzenleme ? 'Kaydet' : 'Ekle',
        onayKey: K.dukkanKaydet,
        onOnay: _ad.text.trim().isEmpty ? null : _kaydet,
        children: [
          TextField(
            key: K.dukkanAd,
            controller: _ad,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Dükkan adı'),
          ),
          Row(children: [
            Expanded(
              child: TextField(
                key: K.dukkanIl,
                controller: _il,
                decoration: const InputDecoration(labelText: 'İl'),
              ),
            ),
            const SizedBox(width: T.s2),
            Expanded(
              child: TextField(
                key: K.dukkanIlce,
                controller: _ilce,
                decoration: const InputDecoration(labelText: 'İlçe'),
              ),
            ),
          ]),
        ],
      );

  Future<void> _kaydet() async {
    setState(() { _kaydediyor = true; _hata = null; });
    final repo = ref.read(orgRepositoryProvider);
    final il = _il.text.trim().isEmpty ? null : _il.text.trim();
    final ilce = _ilce.text.trim().isEmpty ? null : _ilce.text.trim();
    try {
      if (_duzenleme) {
        await repo.dukkanGuncelle(widget.dukkan!.id,
            ad: _ad.text.trim(), il: il, ilce: ilce);
      } else {
        await repo.dukkanEkle(widget.tenantId, _ad.text.trim(),
            il: il, ilce: ilce);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() { _kaydediyor = false; _hata = e.toString(); });
    }
  }
}

/// Pasifleştirme onayı. Kör onay istemiyoruz: ne olacağı ÖNCE sayıyla gösterilir,
/// engel varsa buton hiç açılmaz (kapıların kendisi 0018'de, DB tarafında).
class DukkanPasifDiyalogu extends ConsumerWidget {
  const DukkanPasifDiyalogu({required this.dukkan, super.key});
  final StoreRow dukkan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final etki = ref.watch(_etkiProvider(dukkan.id));
    final d = etki.value;
    return Diyalog(
      baslik: '${dukkan.ad} pasife alınsın mı?',
      altBaslik: 'Hiçbir kayıt silinmez; istendiğinde geri açılır',
      onayEtiketi: 'Pasife al',
      onayKey: K.dukkanPasifOnay,
      onOnay: d?.engelli != false
          ? null
          : () async {
              await ref
                  .read(orgRepositoryProvider)
                  .dukkanDurumu(dukkan.id, false);
              if (context.mounted) Navigator.pop(context, true);
            },
      children: [
        ...switch (etki) {
          AsyncLoading() => const [DiyalogYukleniyor(boy: 72)],
          AsyncError(:final error) => [
              Bildirim(error.toString(), tip: BildirimTip.hata),
            ],
          // Kör onay istemiyoruz: ne olacağı ÖNCE sayıyla gösterilir,
          // engel varsa düğme hiç açılmaz.
          _ => [
              if (d!.engelli)
                Bildirim(d.gerekce,
                    tip: BildirimTip.hata, key: K.dukkanPasifUyari)
              else
                Bildirim(
                    'Dükkan pasife alınınca ${Fmt.adet(d.aktifCari)} cari ve '
                    '${Fmt.adet(d.aktifAtama)} portföy ataması da kapanır. '
                    'Hiçbir kayıt silinmez; istendiğinde geri açılabilir.',
                    tip: BildirimTip.uyari, key: K.dukkanPasifUyari),
              DiyalogOlcu('Açık bakiye', Fmt.para(d.borcTutari)),
            ],
        },
      ],
    );
  }
}

final _etkiProvider = FutureProvider.autoDispose.family<DukkanEtki, String>(
    (ref, id) => ref.watch(orgRepositoryProvider).pasifEtkisi(id));
