import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/test_keys.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/repositories/ticari_repository.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/widgets/bolum.dart';
import '../../../shared/widgets/diyalog.dart';
import '../../../shared/widgets/form_kabuk.dart';
import '../../../shared/widgets/mono.dart';
import 'ticari_durumu.dart';

/// İade — K26'nın tersi.
///
/// İki farklı olay aynı ekrandan girilir ve ayrımı ÜRÜNÜN GEÇMİŞİ yapar:
///   borçlandıran teslimattan gelen ürün → iade borcu DÜŞÜRÜR
///   konsinyeden gelen ürün → borç zaten doğmamıştı, yalnızca açık konsinye azalır
///
/// Bu ayrım kullanıcıya sorulmuyor çünkü kullanıcı bilmek zorunda değil:
/// sunucu ürünün nasıl çıktığını zaten biliyor.
Future<bool> iadeAkisi(BuildContext context, WidgetRef ref, String cariId,
    String unvan) async {
  final sonuc = await showDialog<bool>(
    context: context,
    builder: (_) => _IadeDiyalogu(cariId: cariId, unvan: unvan),
  );
  return sonuc ?? false;
}

class _IadeDiyalogu extends ConsumerStatefulWidget {
  const _IadeDiyalogu({required this.cariId, required this.unvan});
  final String cariId, unvan;
  @override
  ConsumerState<_IadeDiyalogu> createState() => _IadeState();
}

class _IadeState extends ConsumerState<_IadeDiyalogu> {
  final _adet = <String, int>{};
  final _gerekce = TextEditingController();
  bool _kaydediyor = false;
  String? _hata;

  @override
  void dispose() {
    _gerekce.dispose();
    super.dispose();
  }

  int _a(String id) => _adet[id] ?? 0;

  double _tutar(List<IadeKalemi> l) => l
      .where((k) => k.borclandirdi)
      .fold(0, (t, k) => t + k.tutar(_a(k.urunId)));

  bool _gecerli(List<IadeKalemi> l) =>
      !_kaydediyor &&
      l.any((k) => _a(k.urunId) > 0) &&
      !l.any((k) => _a(k.urunId) > k.kalan) &&
      _gerekce.text.trim().isNotEmpty;

  Future<void> _kaydet(List<IadeKalemi> l) async {
    setState(() { _kaydediyor = true; _hata = null; });
    // Borçlandıran ve konsinye kalemleri AYRI kayıtlara gider: tek bir
    // `returns` satırı ya bakiyeyi azaltır ya azaltmaz, ikisi birden olamaz.
    final borclu = [
      for (final k in l)
        if (k.borclandirdi && _a(k.urunId) > 0)
          (urunId: k.urunId, adet: _a(k.urunId), teslimatKalemId: null)
    ];
    final konsinye = [
      for (final k in l)
        if (!k.borclandirdi && _a(k.urunId) > 0)
          (urunId: k.urunId, adet: _a(k.urunId), teslimatKalemId: null)
    ];
    try {
      final rep = ref.read(ticariRepositoryProvider);
      if (borclu.isNotEmpty) {
        await rep.iadeAl(cariId: widget.cariId, kalemler: borclu,
            gerekce: _gerekce.text.trim());
      }
      if (konsinye.isNotEmpty) {
        await rep.iadeAl(cariId: widget.cariId, kalemler: konsinye,
            bakiyeyiAzaltir: false, gerekce: _gerekce.text.trim());
      }
      ticariTazele(ref);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() { _kaydediyor = false; _hata = _temiz(e.toString()); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final d = ref.watch(iadeEdilebilirProvider(widget.cariId));

    return Diyalog(
      key: K.iadeDiyalog,
      baslik: 'İade',
      altBaslik: widget.unvan,
      hata: _hata,
      mesgul: _kaydediyor,
      genislik: 460,
      onayEtiketi: 'İadeyi kaydet',
      onayKey: K.iadeOnay,
      onOnay: _gecerli(d.value ?? const []) ? () => _kaydet(d.value!) : null,
      children: [
        ...switch (d) {
          AsyncLoading() => const [DiyalogYukleniyor()],
          AsyncError(:final error) => [
              Bildirim(error.toString(), tip: BildirimTip.hata),
            ],
          _ when (d.value ?? const []).isEmpty => const [
              BosDurum('İade edilebilecek ürün yok',
                  ikon: Icons.assignment_return_outlined,
                  aciklama: 'Bu cariye henüz mal çıkmamış ya da çıkanların '
                      'tamamı iade alınmış.'),
            ],
          _ => [
              for (final k in d.value!)
                _Satir(
                  k: k,
                  adet: _a(k.urunId),
                  onChanged: (v) => setState(() => _adet[k.urunId] = v),
                ),
              // K26 · iade borcu GERİ ALIR; konsinye kalemi zaten borç
              // doğurmamıştı, ona dokunmaz.
              DiyalogOlcu('Borçtan düşecek', Fmt.para(_tutar(d.value!)),
                  kalin: true, renk: s.basarili),
              TextField(
                key: K.iadeGerekce,
                controller: _gerekce,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Gerekçe',
                  hintText: 'Hatalı baskı, fazla gönderim, satılmadı…',
                  helperText: 'Zorunlu — kalıcı olarak kayda geçer',
                ),
              ),
            ],
        },
      ],
    );
  }
}

String _temiz(String m) {
  final i = m.indexOf('message: ');
  if (i >= 0) return m.substring(i + 9).split(', code:').first;
  return m.replaceFirst('Bad state: ', '').replaceFirst('Exception: ', '');
}

class _Satir extends StatelessWidget {
  const _Satir({required this.k, required this.adet, required this.onChanged});
  final IadeKalemi k;
  final int adet;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final asiyor = adet > k.kalan;
    return Padding(
      padding: const EdgeInsets.only(bottom: T.s3),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(k.ad, maxLines: 2, overflow: TextOverflow.ellipsis),
        Text([
          if (k.yayinevi != null) k.yayinevi!,
          'çıkan ${k.cikan}',
          if (k.iade > 0) 'iade ${k.iade}',
          // Kullanıcı hangi kalemin borcu düşüreceğini görsün.
          k.borclandirdi ? 'borçtan düşer' : 'konsinye — borç doğmamıştı',
        ].join(' · '), style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: T.s2),
        Row(children: [
          SizedBox(
            width: 110,
            child: TextFormField(
              key: K.iadeAdet(k.urunId),
              initialValue: adet == 0 ? '' : '$adet',
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'İade adedi',
                isDense: true,
                errorText: asiyor ? 'en fazla ${k.kalan}' : null,
              ),
              onChanged: (v) => onChanged(int.tryParse(v) ?? 0),
            ),
          ),
          const SizedBox(width: T.s3),
          Text('kalan ${k.kalan}',
              style: Theme.of(context).textTheme.bodySmall),
          const Spacer(),
          if (adet > 0 && k.borclandirdi)
            Mono(Fmt.para(k.tutar(adet)), size: 13, color: s.basarili),
        ]),
      ]),
    );
  }
}
