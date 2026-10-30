import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session.dart';
import '../../../core/test_keys.dart';
import '../../../data/repositories/cari_repository.dart';
import '../../../data/repositories/org_repository.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/widgets/diyalog.dart';
import '../../../shared/widgets/form_kabuk.dart';
import '../../../shared/widgets/parcalar.dart';

final _pazarlamacilarProvider = FutureProvider.autoDispose((ref) async {
  final ekip = await ref.watch(orgRepositoryProvider).ekip();
  return ekip
      .where((u) => u.aktif && u.role == AppRole.pazarlamaci)
      .toList();
});

/// W-2 · Atanmamış cari, kimsenin gelen kutusuna düşmeyen talep demektir.
/// Toplu atama saha gerçeğidir: 300 cari tek tek atanmaz.
class PortfoyAtamaDiyalogu extends ConsumerStatefulWidget {
  const PortfoyAtamaDiyalogu({required this.cariIdler, required this.periodId,
                              super.key});
  final List<String> cariIdler;
  final String periodId;

  @override
  ConsumerState<PortfoyAtamaDiyalogu> createState() =>
      _PortfoyAtamaDiyaloguState();
}

class _PortfoyAtamaDiyaloguState extends ConsumerState<PortfoyAtamaDiyalogu> {
  String? _userId;
  bool _kaldir = false;
  bool _kaydediyor = false;
  String? _hata;

  @override
  Widget build(BuildContext context) {
    final adaylar = ref.watch(_pazarlamacilarProvider);

    return Diyalog(
      baslik: '${Fmt.adet(widget.cariIdler.length)} cariyi portföye ata',
      altBaslik: 'Bir cari bir dönemde tek kişiye aittir',
      hata: _hata,
      mesgul: _kaydediyor,
      onayEtiketi: 'Ata',
      onayKey: K.atamaOnay,
      onOnay: (_userId == null && !_kaldir) ? null : _ata,
      children: [
        adaylar.when(
          loading: () => const DiyalogYukleniyor(boy: 60),
          error: (e, _) => Bildirim(e.toString(), tip: BildirimTip.hata),
          data: (liste) => liste.isEmpty
              ? const Bildirim(
                  'Aktif pazarlamacı yok. Önce ekibe davet gönderin.',
                  tip: BildirimTip.uyari)
              : DropdownButtonFormField<String>(
                  key: K.atamaAday,
                  initialValue: _userId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Pazarlamacı'),
                  items: [
                    for (final u in liste)
                      DropdownMenuItem(
                          value: u.userId,
                          child: Text(
                              '${u.adSoyad} · ${Fmt.adet(u.portfoy)} cari')),
                  ],
                  onChanged:
                      _kaldir ? null : (v) => setState(() => _userId = v),
                ),
        ),
        CheckboxListTile(
          value: _kaldir,
          onChanged: (v) => setState(() {
            _kaldir = v ?? false;
            if (_kaldir) _userId = null;
          }),
          title: const Text('Portföyden çıkar'),
          subtitle: const Text('Seçili cariler kimseye atanmamış olur'),
          contentPadding: EdgeInsets.zero,
        ),
        // W-2 · portföysüz cariden gelen talep hiçbir kutuya düşmez.
        if (_kaldir)
          const Bildirim(
            'Portföysüz cariden gelen talep hiçbir gelen kutusuna düşmez. '
            'Bunu yalnızca cariyi geçici olarak dondururken kullanın.',
            tip: BildirimTip.uyari)
        else
          const KuralNotu(
              'Zaten başka bir pazarlamacıda olan cariler devralınır.'),
      ],
    );
  }

  Future<void> _ata() async {
    setState(() { _kaydediyor = true; _hata = null; });
    try {
      final r = await ref.read(cariRepositoryProvider).portfoyAta(
            cariIdler: widget.cariIdler,
            userId: _kaldir ? null : _userId,
            periodId: widget.periodId,
          );
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_kaldir
              ? '${r.devralinan} cari portföyden çıkarıldı'
              : '${r.atanan} cari atandı'
                '${r.devralinan > 0 ? ' (${r.devralinan} devralındı)' : ''}')));
    } catch (e) {
      if (mounted) setState(() { _kaydediyor = false; _hata = e.toString(); });
    }
  }
}
