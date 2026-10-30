import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/test_keys.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/repositories/ticari_repository.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/widgets/liste.dart';
import '../../../shared/widgets/bolum.dart';
import '../../../shared/widgets/cam.dart';
import '../../../shared/widgets/dokunus.dart';
import '../../../shared/widgets/satir.dart';
import '../../../shared/widgets/form_kabuk.dart';
import '../../../shared/widgets/mono.dart';
import 'ticari_durumu.dart';

/// K45 · Konsinye kapatma.
///
/// Kapatmak İKİ kayıt üretir ve ikisi TEK çağrıda gider:
///   satılan → konsinye_satis teslimatı, **borç doğar** (K26)
///   geri alınan → bakiyeyi azaltmayan iade, borç doğmaz
///
/// Ayrı ayrı gönderilseydi, satış yazılıp iade yazılamadığında cari hem
/// borçlanmış hem konsinyesi açık kalırdı.
class KonsinyeKapatmaEkrani extends ConsumerStatefulWidget {
  const KonsinyeKapatmaEkrani(
      {required this.cariId, required this.unvan, super.key});
  final String cariId, unvan;

  @override
  ConsumerState<KonsinyeKapatmaEkrani> createState() => _KapatmaState();
}

class _KapatmaState extends ConsumerState<KonsinyeKapatmaEkrani> {
  final _satilan = <String, int>{};
  final _iade = <String, int>{};
  final _gerekce = TextEditingController();
  bool _kaydediyor = false;
  String? _hata;

  @override
  void dispose() {
    _gerekce.dispose();
    super.dispose();
  }

  int _s(String id) => _satilan[id] ?? 0;
  int _i(String id) => _iade[id] ?? 0;

  bool _asiyor(KonsinyeKalemi k) => _s(k.urunId) + _i(k.urunId) > k.kalan;

  double _borc(List<KonsinyeKalemi> l) =>
      l.fold(0, (t, k) => t + k.tutar(_s(k.urunId)));

  int _iadeAdet(List<KonsinyeKalemi> l) =>
      l.fold(0, (t, k) => t + _i(k.urunId));

  bool _gecerli(List<KonsinyeKalemi> l) =>
      !_kaydediyor &&
      l.any((k) => _s(k.urunId) > 0 || _i(k.urunId) > 0) &&
      !l.any(_asiyor);

  Future<void> _kapat(List<KonsinyeKalemi> l) async {
    setState(() { _kaydediyor = true; _hata = null; });
    try {
      final r = await ref.read(ticariRepositoryProvider).konsinyeKapat(
        cariId: widget.cariId,
        satilan: [
          for (final k in l)
            if (_s(k.urunId) > 0) (urunId: k.urunId, adet: _s(k.urunId))
        ],
        iade: [
          for (final k in l)
            if (_i(k.urunId) > 0) (urunId: k.urunId, adet: _i(k.urunId))
        ],
        gerekce: _gerekce.text.trim().isEmpty ? null : _gerekce.text.trim(),
      );
      ticariTazele(ref);
      ref.invalidate(konsinyeDetayProvider(widget.cariId));
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(r.borc > 0
              ? 'Kapandı · ${Fmt.para(r.borc)} borç doğdu · '
                  'kalan ${Fmt.adet(r.kalanKonsinye)} adet'
              : 'Kapandı · kalan ${Fmt.adet(r.kalanKonsinye)} adet')));
    } catch (e) {
      if (!mounted) return;
      setState(() { _kaydediyor = false; _hata = _temiz(e.toString()); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = ref.watch(konsinyeDetayProvider(widget.cariId));
    return CamSayfa(
      baslik: widget.unvan,
      cocuklar: d.when(
        loading: () => const [Padding(
            padding: EdgeInsets.symmetric(vertical: T.s6),
            child: Bekleme())],
        error: (e, _) => [Bildirim(e.toString(), tip: BildirimTip.hata)],
        data: (l) => l.isEmpty
            ? const [CamKart(
                dolgu: false,
                child: BosDurum('Bu caride açık konsinye kalmadı',
                    ikon: Icons.assignment_turned_in_outlined))]
            : [
                  Bolum(
                    key: K.konsinyeKalemler,
                    baslik: 'Kalemler',
                    altBaslik: 'Her ürün için kaçı satıldı, kaçı geri alındı',
                    child: Column(children: [
                      for (final k in l) _Kalem(
                        k: k,
                        satilan: _s(k.urunId),
                        iade: _i(k.urunId),
                        asiyor: _asiyor(k),
                        onSatilan: (v) => setState(() => _satilan[k.urunId] = v),
                        onIade: (v) => setState(() => _iade[k.urunId] = v),
                      ),
                    ]),
                  ),
                  const SizedBox(height: T.s3),
                  _Ozet(borc: _borc(l), iadeAdet: _iadeAdet(l)),
                  const SizedBox(height: T.s3),
                  TextField(
                    controller: _gerekce,
                    decoration: const InputDecoration(
                      labelText: 'Gerekçe (isteğe bağlı)',
                      hintText: 'Dönem sonu sayımı, öğretmen iadesi…',
                    ),
                  ),
                  if (_hata != null) ...[
                    const SizedBox(height: T.s3),
                    Bildirim(_hata!, tip: BildirimTip.hata),
                  ],
                  const SizedBox(height: T.s4),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: K.konsinyeKapat,
                      onPressed: _gecerli(l) ? () => _kapat(l) : null,
                      child: Text(_kaydediyor ? 'Kaydediliyor…' : 'Kapat'),
                    ),
                  ),
                  const SonBosluk(),
            ],
      ),
    );
  }
}

String _temiz(String m) {
  final i = m.indexOf('message: ');
  if (i >= 0) return m.substring(i + 9).split(', code:').first;
  return m.replaceFirst('Bad state: ', '').replaceFirst('Exception: ', '');
}

class _Kalem extends StatelessWidget {
  const _Kalem({required this.k, required this.satilan, required this.iade,
                required this.asiyor, required this.onSatilan,
                required this.onIade});
  final KonsinyeKalemi k;
  final int satilan, iade;
  final bool asiyor;
  final ValueChanged<int> onSatilan, onIade;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(T.s4, T.s3, T.s4, T.s3),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(k.ad, maxLines: 2, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 2),
        Text([
          if (k.yayinevi != null) k.yayinevi!,
          'bırakılan ${k.birakilan}',
          if (k.satilan > 0) 'satılan ${k.satilan}',
          if (k.iade > 0) 'iade ${k.iade}',
        ].join(' · '), style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: T.s2),
        Row(children: [
          Expanded(
            child: _Sayi(
              key: K.konsinyeSatildi(k.urunId),
              etiket: 'Satıldı',
              deger: satilan,
              onChanged: onSatilan,
            ),
          ),
          const SizedBox(width: T.s3),
          Expanded(
            child: _Sayi(
              key: K.konsinyeIade(k.urunId),
              etiket: 'İade',
              deger: iade,
              onChanged: onIade,
            ),
          ),
          const SizedBox(width: T.s3),
          SizedBox(
            width: 64,
            child: Column(crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min, children: [
              MikroEtiket('Kalan'),
              const SizedBox(height: 4),
              Mono('${k.kalan}', size: 15, weight: FontWeight.w600),
            ]),
          ),
        ]),
        if (asiyor)
          Padding(
            padding: const EdgeInsets.only(top: T.s2),
            child: Text('Kalan ${k.kalan} adetten fazlası kapatılamaz',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: s.error)),
          ),
        if (satilan > 0)
          Padding(
            padding: const EdgeInsets.only(top: T.s2),
            child: Text('Satılan için borç: ${Fmt.para(k.tutar(satilan))}',
                style: Theme.of(context).textTheme.bodySmall),
          ),
        const Divider(height: T.s4),
      ]),
    );
  }
}

class _Sayi extends StatelessWidget {
  const _Sayi({required this.etiket, required this.deger,
               required this.onChanged, super.key});
  final String etiket;
  final int deger;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => TextFormField(
        initialValue: deger == 0 ? '' : '$deger',
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(labelText: etiket, isDense: true),
        onChanged: (v) => onChanged(int.tryParse(v) ?? 0),
      );
}

/// Kapanışın parasal SONUCU. "Kapat" düğmesine basmadan önce ne olacağı
/// yazılı olmalı: satılan kısım borç doğurur, iade edilen kısım doğurmaz.
class _Ozet extends StatelessWidget {
  const _Ozet({required this.borc, required this.iadeAdet});
  final double borc;
  final int iadeAdet;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Bolum(
      key: K.konsinyeOzet,
      baslik: 'Kapanışta ne olacak',
      altBaslik: 'Borç teslimatla doğar: yalnızca satılan kısım borçlandırır',
      child: Column(children: [
        KayitSatiri(
          baslik: 'Satıştan doğacak borç',
          ikon: Icons.trending_up,
          durumRengi: borc > 0 ? s.error : s.onSurfaceVariant,
          deger: Fmt.para(borc),
          degerRengi: borc > 0 ? s.error : null,
        ),
        KayitSatiri(
          baslik: 'Geri alınan',
          altBilgi: 'Borç doğurmaz — mal dükkana döner',
          ikon: Icons.undo,
          durumRengi: s.onSurfaceVariant,
          deger: '$iadeAdet adet',
        ),
      ]),
    );
  }
}
