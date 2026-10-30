import 'package:flutter/material.dart';
import '../../../core/test_keys.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/org_repository.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/widgets/diyalog.dart';
import '../../../shared/widgets/form_kabuk.dart';

/// K34 (W-2) · Pasife alırken portföy devri ZORUNLUDUR.
/// Devredilmezse o carilerden gelen talepler hiçbir gelen kutusuna düşmez;
/// öğretmen talep açar, kimse görmez, 24 saat sonra anlamsız bir SLA uyarısı gider.
class DevirDiyalogu extends ConsumerStatefulWidget {
  const DevirDiyalogu({required this.uye, required this.adaylar, super.key});
  final StaffRow uye;
  final List<StaffRow> adaylar;
  @override
  ConsumerState<DevirDiyalogu> createState() => _DevirDiyaloguState();
}

class _DevirDiyaloguState extends ConsumerState<DevirDiyalogu> {
  String? _devralan;
  bool _mesgul = false;
  String? _hata;

  @override
  Widget build(BuildContext context) {
    final portfoyVar = widget.uye.portfoy > 0;
    return Diyalog(
      baslik: '${widget.uye.adSoyad} pasife alınsın mı?',
      hata: _hata,
      mesgul: _mesgul,
      onayEtiketi: 'Pasife al',
      onayKey: K.devirOnay,
      onOnay: portfoyVar && _devralan == null ? null : _pasifeAl,
      children: [
        if (portfoyVar) ...[
          // W-2 · atanmamış cariden gelen talep hiçbir kutuya düşmez.
          Bildirim(
            'Portföyünde ${Fmt.adet(widget.uye.portfoy)} cari var. '
            'Devredilmezse bu carilerden gelen talepler hiçbir gelen '
            'kutusuna düşmez — kimse görmez.',
            tip: BildirimTip.uyari),
          if (widget.adaylar.isEmpty)
            const Bildirim(
              key: K.devirUyari,
              'Devralacak aktif pazarlamacı yok. Önce yeni bir pazarlamacı '
              'davet edin.',
              tip: BildirimTip.hata)
          else
            DropdownButtonFormField<String>(
              key: K.devirAday,
              initialValue: _devralan,
              decoration: const InputDecoration(
                  labelText: 'Portföyü kim devralacak?'),
              items: [
                for (final a in widget.adaylar)
                  DropdownMenuItem(
                      value: a.userId,
                      child: Text(
                          '${a.adSoyad} · ${Fmt.adet(a.portfoy)} cari')),
              ],
              onChanged: (v) => setState(() => _devralan = v),
            ),
        ] else
          const Bildirim('Portföyünde cari yok, doğrudan pasife alınabilir.',
              tip: BildirimTip.bilgi),
      ],
    );
  }

  Future<void> _pasifeAl() async {
    setState(() { _mesgul = true; _hata = null; });
    try {
      final n = await ref
          .read(orgRepositoryProvider)
          .uyeyiPasifeAl(widget.uye.userId, devralanUserId: _devralan);
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              n > 0 ? '${Fmt.adet(n)} cari devredildi' : 'Pasife alındı')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _hata =
          e.toString().replaceFirst(RegExp(r'^\w+Exception:?\s*'), ''));
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }
}
