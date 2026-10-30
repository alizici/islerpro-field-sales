import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/test_keys.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/repositories/deneme_repository.dart';
import '../../../shared/widgets/diyalog.dart';
import '../../../shared/widgets/form_kabuk.dart';
import '../../../shared/widgets/parcalar.dart';
import 'deneme_durumu.dart';

/// K22 · Sınıf mevcutlarını KURUM bildirir.
///
/// Bu ekran adet önerisinin birinci basamağıdır, tek basamağı değil:
/// girilmezse öneri dört kademeli yedek zincire düşer ve **tıkanmaz** (0024).
/// Yani burası bir zorunluluk değil, bir hızlandırıcıdır.
///
/// V4 · Yalnızca ADET tutulur. Öğrenci adı/kimliği hiçbir zaman istenmez —
/// bu yüzden KVKK yükü hiç doğmaz (K40).
Future<bool> mevcutAkisi(BuildContext context, WidgetRef ref, String cariId,
    String unvan) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (_) => _MevcutDiyalogu(cariId: cariId, unvan: unvan),
  );
  return r ?? false;
}

class _MevcutDiyalogu extends ConsumerStatefulWidget {
  const _MevcutDiyalogu({required this.cariId, required this.unvan});
  final String cariId, unvan;
  @override
  ConsumerState<_MevcutDiyalogu> createState() => _MevcutState();
}

class _MevcutState extends ConsumerState<_MevcutDiyalogu> {
  final _deger = <int, int>{};
  bool _dolduruldu = false;
  bool _kaydediyor = false;
  String? _hata;

  /// 1-12 sınıf + 13 = mezun. Hepsi gösterilir: hangi sınıfların olduğunu
  /// kurum bilir, uygulama tahmin etmez.
  static const _siniflar = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13];

  void _doldur(Mevcutlar m) {
    if (_dolduruldu) return;
    _dolduruldu = true;
    for (final s in m.siniflar) {
      _deger[s.sinif] = s.ogrenciSayisi;
    }
  }

  int get _toplam => _deger.values.fold(0, (a, b) => a + b);

  Future<void> _kaydet() async {
    setState(() { _kaydediyor = true; _hata = null; });
    try {
      await ref.read(denemeRepositoryProvider).mevcutYaz(
        widget.cariId,
        [
          for (final e in _deger.entries)
            (sinif: e.key, ogrenciSayisi: e.value)
        ],
      );
      ref.invalidate(mevcutlarProvider(widget.cariId));
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() { _kaydediyor = false; _hata = _temiz(e.toString()); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = ref.watch(mevcutlarProvider(widget.cariId));
    if (m.hasValue) _doldur(m.value!);

    return Diyalog(
      key: K.mevcutDiyalog,
      baslik: 'Sınıf mevcutları',
      altBaslik: widget.unvan,
      hata: _hata,
      mesgul: _kaydediyor,
      genislik: 420,
      onayKey: K.mevcutKaydet,
      onOnay: m.hasValue ? _kaydet : null,
      children: [
        // K22 · mevcut, deneme adedi önerisinin en güçlü girdisi ama
        // ZORUNLU değil: girilmezse öneri sipariş geçmişinden türetilir.
        const KuralNotu(
            'Deneme adedi bu sayılardan önerilir. Girilmezse öneri yine '
            'gelir — sipariş geçmişinden ve kurum mevcudundan türetilir.'),
        ...switch (m) {
          AsyncLoading() => const [DiyalogYukleniyor()],
          AsyncError(:final error) => [
              Bildirim(error.toString(), tip: BildirimTip.hata),
            ],
          _ => [
              Wrap(spacing: T.s3, runSpacing: T.s3, children: [
                for (final sinif in _siniflar)
                  SizedBox(
                    width: 92,
                    child: TextFormField(
                      key: K.mevcutSinif(sinif),
                      initialValue:
                          (_deger[sinif] ?? 0) == 0 ? '' : '${_deger[sinif]}',
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly
                      ],
                      decoration: InputDecoration(
                        labelText: sinif == 13 ? 'Mezun' : '$sinif. sınıf',
                        isDense: true,
                      ),
                      onChanged: (x) => setState(
                          () => _deger[sinif] = int.tryParse(x) ?? 0),
                    ),
                  ),
              ]),
              DiyalogOlcu('Toplam', '$_toplam', kalin: true),
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
