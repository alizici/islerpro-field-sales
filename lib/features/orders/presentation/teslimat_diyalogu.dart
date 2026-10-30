import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/test_keys.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/local/yerel_saglayici.dart';
import '../../../data/repositories/siparis_repository.dart';
import '../../../data/services/saha_kuyrugu.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/widgets/diyalog.dart';
import '../../../shared/widgets/form_kabuk.dart';

/// K26 · BORÇ BURADA DOĞAR.
/// C-1 · `tip` ve `borclandirir` bağımsızdır: konsinye bırakma fiziksel bir
/// hareket ama borç doğurmaz. Kısmi teslim mümkündür — kalanı H-3 gereği
/// backorder olarak kendiliğinden türetilir.
class TeslimatDiyalogu extends ConsumerStatefulWidget {
  const TeslimatDiyalogu({required this.siparis, super.key});
  final SiparisDetay siparis;

  @override
  ConsumerState<TeslimatDiyalogu> createState() => _TeslimatDiyaloguState();
}

class _TeslimatDiyaloguState extends ConsumerState<TeslimatDiyalogu> {
  final _adetler = <String, int>{};
  final _alan = TextEditingController();
  bool _konsinye = false;
  bool _kaydediyor = false;
  String? _hata;

  @override
  void initState() {
    super.initState();
    // Varsayılan: kalan her şey teslim edilir.
    for (final k in widget.siparis.kalemler) {
      if (k.backorder > 0) _adetler[k.id] = k.backorder;
    }
  }

  @override
  void dispose() { _alan.dispose(); super.dispose(); }

  double get _tutar => widget.siparis.kalemler.fold(0.0, (t, k) {
        final adet = _adetler[k.id] ?? 0;
        if (adet == 0) return t;
        return t + k.birimFiyat * (1 - k.iskontoOrani) * adet;
      });

  bool get _gecerli =>
      _adetler.values.any((a) => a > 0) && !_kaydediyor &&
      widget.siparis.kalemler.every(
          (k) => (_adetler[k.id] ?? 0) <= k.backorder);

  @override
  Widget build(BuildContext context) {
    final kalanlar =
        widget.siparis.kalemler.where((k) => k.backorder > 0).toList();

    return Diyalog(
      baslik: 'Teslimat kaydet',
      altBaslik: widget.siparis.cariUnvan,
      hata: _hata,
      mesgul: _kaydediyor,
      genislik: 480,
      onayEtiketi: _konsinye ? 'Konsinye bırak' : 'Teslimatı kaydet',
      onayKey: K.teslimatKaydet,
      onOnay: _gecerli ? _kaydet : null,
      children: [
        // K26 · borç TESLİMATTA doğar. Doğacak tutar kaydetmeden önce
        // yazılı: kullanıcı ne imzaladığını bilerek imzalasın.
        Bildirim(
            _konsinye
                ? 'Konsinye bırakma: kitaplar kuruma gider ama BORÇ DOĞMAZ. '
                  'Satıldıkça ayrıca kayıt girilir.'
                : 'Teslimat kaydedilince ${Fmt.para(_tutar)} borç doğar.',
            tip: _konsinye ? BildirimTip.bilgi : BildirimTip.uyari),
        for (final k in kalanlar)
          _Kalem(
            k: k,
            adet: _adetler[k.id] ?? 0,
            onAdet: (v) => setState(() => _adetler[k.id] = v),
          ),
        TextField(
          key: K.teslimatAlan,
          controller: _alan,
          decoration: const InputDecoration(
            labelText: 'Teslim alan',
            helperText: 'İsim yeterli — imza ve fotoğraf saklanmaz',
          ),
        ),
        CheckboxListTile(
          key: K.teslimatKonsinye,
          value: _konsinye,
          onChanged: (v) => setState(() => _konsinye = v ?? false),
          title: const Text('Konsinye bırakma'),
          subtitle: const Text('Mülkiyet dükkanda kalır, borç doğmaz'),
          contentPadding: EdgeInsets.zero,
        ),
      ],
    );
  }

  Future<void> _kaydet() async {
    setState(() { _kaydediyor = true; _hata = null; });
    final kuyruk = ref.read(sahaKuyruguProvider);
    final alan = _alan.text.trim().isEmpty ? null : _alan.text.trim();
    final ck = SahaKuyrugu.anahtar('sv');
    final kalemler = [
      for (final e in _adetler.entries)
        if (e.value > 0) (siparisKalemId: e.key, urunId: null, adet: e.value),
    ];
    try {
      // K34 · Mal fiziken verildi. Çevrimdışıyken doğrulanacak bir zimmet
      // bakiyesi olmadığı için kayıt beklemeye alınmaz: kuyruğa yazılır ve
      // borç senkronda, teslimat anına damgalı olarak doğar (K26).
      //
      // `kaynak` bilinçli olarak değiştirilmiyor: kuyruğa girmek kaydın
      // ANLAMINI değiştirmemeli, yalnızca ne zaman yüklendiğini.
      final r = await kuyruk.dene(
        () => ref.read(siparisRepositoryProvider).teslimEt(
              cariId: widget.siparis.cariId,
              siparisId: widget.siparis.id,
              borclandirir: !_konsinye,
              teslimAlanAd: alan,
              kalemler: kalemler,
              clientKey: ck,
            ),
        fn: 'create_shipment',
        args: {
          'account_id': widget.siparis.cariId,
          'order_id': widget.siparis.id,
          'borclandirir': !_konsinye,
          'tip': 'teslimat',
          'teslim_alan_ad': alan,
          'client_key': ck,
          'items': [
            for (final k in kalemler)
              {'order_item_id': k.siparisKalemId, 'adet': k.adet},
          ],
        },
        ozet: '${widget.siparis.cariUnvan} · '
            '${Fmt.adet(kalemler.length)} kalem teslimat',
      );
      if (!mounted) return;
      Navigator.pop(context, true);
      if (r == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Teslimat kuyruğa alındı — çevrimdışı; '
                'belge no senkronda kesinleşecek')));
      }
    } catch (e) {
      if (mounted) setState(() { _kaydediyor = false; _hata = e.toString(); });
    }
  }
}

/// Teslim edilecek adet satırı. H-3 · kalandan fazlası girilemez —
/// backorder ayrı bir kayıt değil, türetilmiş sayıdır.
class _Kalem extends StatelessWidget {
  const _Kalem({required this.k, required this.adet, required this.onAdet});
  final SiparisKalemi k;
  final int adet;
  final void Function(int) onAdet;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final fazla = adet > k.backorder;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(k.ad, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: t.bodyLarge),
              Text(
                  '${Fmt.adet(k.backorder)} adet bekliyor · '
                  '${Fmt.para(k.birimFiyat)}',
                  style: t.bodySmall),
            ],
          ),
        ),
        const SizedBox(width: T.s3),
        SizedBox(
          width: 92,
          child: TextFormField(
            key: K.teslimatAdet(k.id),
            initialValue: '$adet',
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textAlign: TextAlign.end,
            decoration: InputDecoration(
              isDense: true,
              suffixText: 'ad',
              errorText: fazla ? 'fazla' : null,
            ),
            onChanged: (v) => onAdet(int.tryParse(v) ?? 0),
          ),
        ),
      ]),
    );
  }
}
