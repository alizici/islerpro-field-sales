import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/test_keys.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/repositories/kurum_repository.dart';
import '../../../shared/widgets/bolum.dart';
import '../../../shared/widgets/diyalog.dart';

/// Ö-8 · Kurum eklerken benzerlik kontrolü.
/// Dizin ORTAK olduğu için (K4) mükerrer kayıt yalnızca bu işletmeyi değil
/// herkesi etkiler — bu yüzden uyarı, kaydetmeden önce gösterilir.
class KurumEkleDiyalogu extends ConsumerStatefulWidget {
  const KurumEkleDiyalogu({required this.storeId, super.key});
  final String storeId;
  @override
  ConsumerState<KurumEkleDiyalogu> createState() => _KurumEkleDiyaloguState();
}

class _KurumEkleDiyaloguState extends ConsumerState<KurumEkleDiyalogu> {
  final _ad = TextEditingController();
  final _ilce = TextEditingController();
  final _mebKodu = TextEditingController();
  String _tip = 'okul';
  String? _kademe;
  Timer? _gecikme;
  List<BenzerKurum> _benzerler = const [];
  bool _mesgul = false;
  String? _hata;

  @override
  void dispose() {
    _gecikme?.cancel();
    for (final c in [_ad, _ilce, _mebKodu]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Yazarken benzerlik ara — her tuşta değil, 400 ms duraklamada.
  void _benzerlikAra() {
    _gecikme?.cancel();
    _gecikme = Timer(const Duration(milliseconds: 400), () async {
      final r = await ref.read(kurumRepositoryProvider).benzerler(
            _ad.text,
            ilce: _ilce.text.trim().isEmpty ? null : _ilce.text.trim(),
          );
      if (mounted) setState(() => _benzerler = r);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Diyalog(
      baslik: 'Kurum ekle',
      // K18 · okul ve özel kurs merkezi TEK dizinde.
      altBaslik: 'Okullar ve kurs merkezleri aynı dizinde durur',
      hata: _hata,
      mesgul: _mesgul,
      genislik: 460,
      onayEtiketi: 'Ekle',
      onayKey: K.kurumEkleKaydet,
      onOnay: _ad.text.trim().length < 3 ? null : _ekle,
      children: [
        SegmentedButton<String>(
          key: K.kurumEkleTip,
          segments: const [
            ButtonSegment(value: 'okul', label: Text('Okul'),
                icon: Icon(Icons.school_outlined, size: 16)),
            ButtonSegment(value: 'kurs_merkezi', label: Text('Kurs merkezi'),
                icon: Icon(Icons.cast_for_education_outlined, size: 16)),
          ],
          selected: {_tip},
          onSelectionChanged: (v) => setState(() {
            _tip = v.first;
            if (_tip != 'okul') _kademe = null;
          }),
        ),
        TextField(
          key: K.kurumEkleAd,
          controller: _ad,
          onChanged: (_) { setState(() {}); _benzerlikAra(); },
          decoration: const InputDecoration(
              labelText: 'Kurum adı',
              hintText: 'Şanlıurfa Anadolu Lisesi',
              helperText: 'En az 3 harf'),
        ),
        Row(children: [
          Expanded(
            child: TextField(
              key: K.kurumEkleIlce,
              controller: _ilce,
              onChanged: (_) => _benzerlikAra(),
              decoration: const InputDecoration(
                  labelText: 'İlçe', hintText: 'Haliliye'),
            ),
          ),
          const SizedBox(width: T.s2),
          Expanded(
            child: TextField(
              controller: _mebKodu,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'MEB kodu', hintText: '6 hane'),
            ),
          ),
        ]),
        if (_tip == 'okul')
          DropdownButtonFormField<String>(
            initialValue: _kademe,
            decoration: const InputDecoration(labelText: 'Kademe'),
            items: const [
              DropdownMenuItem(value: 'anaokulu', child: Text('Anaokulu')),
              DropdownMenuItem(value: 'ilkokul', child: Text('İlkokul')),
              DropdownMenuItem(value: 'ortaokul', child: Text('Ortaokul')),
              DropdownMenuItem(value: 'lise', child: Text('Lise')),
            ],
            onChanged: (v) => setState(() => _kademe = v),
          ),
        // Ö-8 · mükerrer kurum dizini bozar ve bir daha düzelmez: benzer
        // kayıt varsa KAYDETMEDEN önce gösterilir, üstelik tıklanabilir.
        if (_benzerler.isNotEmpty)
          Container(
            key: K.kurumBenzerUyari,
            width: double.infinity,
            padding: const EdgeInsets.all(T.s3),
            decoration: BoxDecoration(
              color: s.uyari.withValues(alpha: 0.08),
              border: Border.all(color: s.uyari.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(T.rDugme),
            ),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.info_outline, size: 16, color: s.uyari),
                const SizedBox(width: T.s2),
                Expanded(
                  child: Text(
                      'Benzer kurum${_benzerler.length > 1 ? "lar" : ""} '
                      'zaten var — mükerrer kayıt açmayın',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: s.onSurface)),
                ),
              ]),
              const SizedBox(height: T.s2),
              for (final b in _benzerler)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(children: [
                    Rozet('%${(b.benzerlik * 100).round()}', renk: s.uyari),
                    const SizedBox(width: T.s2),
                    Expanded(
                      child: Text(
                          '${b.ad}${b.ilce != null ? " · ${b.ilce}" : ""}',
                          style: Theme.of(context).textTheme.bodySmall),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, b.id),
                      child: const Text('Bunu kullan'),
                    ),
                  ]),
                ),
            ]),
          ),
      ],
    );
  }

  Future<void> _ekle() async {
    setState(() { _mesgul = true; _hata = null; });
    try {
      final id = await ref.read(kurumRepositoryProvider).ekle(
            ad: _ad.text.trim(),
            kurumTipi: _tip,
            il: 'Şanlıurfa',
            ilce: _ilce.text.trim().isEmpty ? null : _ilce.text.trim(),
            kademe: _kademe,
            mebKodu:
                _mebKodu.text.trim().isEmpty ? null : _mebKodu.text.trim(),
            storeId: widget.storeId,
          );
      if (mounted) Navigator.pop(context, id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _hata =
          e.toString().replaceFirst(RegExp(r'^\w+Exception:?\s*'), ''));
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }
}
