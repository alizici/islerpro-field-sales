import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/test_keys.dart';
import '../../../data/repositories/ticari_repository.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/widgets/diyalog.dart';
import '../../../shared/widgets/parcalar.dart';
import 'ticari_durumu.dart';

/// Her durumun ne ANLAMA geldiği yazılı. "Ciro edildi" seçeneği bir kod
/// değil bir karardır: bakiyeyi düşürür, ve çek geri dönerse borç geri gelir.
const _aciklama = <String, String>{
  'tahsilde': 'Bankaya tahsile verildi. Bakiye hâlâ durur.',
  'tahsil_edildi': 'Para geldi. Borç ŞİMDİ düşer.',
  'ciro_edildi': 'Yayınevine devredildi. Borç düşer; çek geri dönerse '
      'karşılıksız yazılır ve borç geri gelir.',
  'karsiliksiz': 'Borç geri yazılır ve cari "tahsilatta" durumuna alınır.',
  'iade_edildi': 'Müşteriye geri verildi. Borç yerinde kalır.',
  'portfoyde': 'Tahsilden geri alındı, yeniden portföyde.',
};

/// K11 · Çek durumu değiştirme.
///
/// Seçenekler `cekGecisleri` tablosundan gelir; sunucudaki
/// `cheque_transition_ok` ile aynı tablodur. Ekran, sunucunun reddedeceği
/// bir düğmeyi hiç göstermemeli — kullanıcı denemesin diye değil, "neden
/// olmuyor" diye sormak zorunda kalmasın diye.
Future<void> cekDurumAkisi(BuildContext context, WidgetRef ref, Cek c) async {
  if (c.gidilebilir.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${cekDurumAdi[c.durum]} bir çekin durumu '
            'değiştirilemez')));
    return;
  }
  final sonuc = await showDialog<(String, String?, String?)>(
    context: context,
    builder: (_) => _CekDiyalogu(c: c),
  );
  if (sonuc == null || !context.mounted) return;

  try {
    final r = await ref.read(ticariRepositoryProvider).cekDurumu(
        c.id, sonuc.$1, ciroEdilen: sonuc.$2, gerekce: sonuc.$3);
    ticariTazele(ref);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${cekDurumAdi[r.durum]}'
            '${r.bakiye == null ? "" : " · bakiye ${Fmt.para(r.bakiye)}"}')));
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(_temiz(e.toString()))));
  }
}

String _temiz(String m) {
  final i = m.indexOf('message: ');
  if (i >= 0) return m.substring(i + 9).split(', code:').first;
  return m.replaceFirst('Bad state: ', '').replaceFirst('Exception: ', '');
}

class _CekDiyalogu extends StatefulWidget {
  const _CekDiyalogu({required this.c});
  final Cek c;
  @override
  State<_CekDiyalogu> createState() => _CekDiyaloguState();
}

class _CekDiyaloguState extends State<_CekDiyalogu> {
  String? _secim;
  final _ciro = TextEditingController();
  final _gerekce = TextEditingController();

  @override
  void dispose() {
    _ciro.dispose();
    _gerekce.dispose();
    super.dispose();
  }

  bool get _gecerli {
    if (_secim == null) return false;
    if (_secim == 'ciro_edildi' && _ciro.text.trim().isEmpty) return false;
    if (_secim == 'karsiliksiz' && _gerekce.text.trim().isEmpty) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final s = Theme.of(context).colorScheme;
    return Diyalog(
      key: K.cekDiyalog,
      baslik: c.unvan,
      altBaslik: '${cekDurumAdi[c.durum] ?? c.durum} · '
          '${c.tip == 'senet' ? 'Senet' : 'Çek'}',
      onayKey: K.cekOnay,
      onOnay: _gecerli
          ? () => Navigator.pop(context,
              (_secim!, _ciro.text.trim(), _gerekce.text.trim()))
          : null,
      children: [
        DiyalogOlcu('Tutar', Fmt.para(c.tutar),
            kalin: true, altBilgi: 'vade ${Fmt.tarih(c.vade)}'),
        // Yalnızca GİDİLEBİLİR durumlar listelenir ve her birinin bakiyeye
        // etkisi yazılıdır: "tahsil edildi" ile "ciro edildi" farkı burada
        // görünmezse kimse ayırt etmez.
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const BolumBasligi('Yeni durum'),
            RadioGroup<String>(
              groupValue: _secim,
              onChanged: (v) => setState(() => _secim = v),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                for (final d in c.gidilebilir)
                  RadioListTile<String>(
                    key: K.cekDurum(d),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: d,
                    title: Text(cekDurumAdi[d] ?? d),
                    subtitle: Text(_aciklama[d] ?? '',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: d == 'karsiliksiz' ? s.error : null)),
                  ),
              ]),
            ),
          ],
        ),
        if (_secim == 'ciro_edildi')
          TextField(
            key: K.cekCiroAlan,
            controller: _ciro,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Kime ciro edildi',
              hintText: 'Yayınevi adı',
              helperText: 'Zorunlu — çekin nereye gittiği kayda geçer',
            ),
          ),
        if (_secim == 'karsiliksiz')
          TextField(
            key: K.cekGerekce,
            controller: _gerekce,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Gerekçe',
              hintText: 'Banka açıklaması, görüşme notu',
              helperText: 'Zorunlu',
            ),
          ),
      ],
    );
  }
}
