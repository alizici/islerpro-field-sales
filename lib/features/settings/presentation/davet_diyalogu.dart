import 'package:flutter/material.dart';
import '../../../core/test_keys.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/repositories/org_repository.dart';
import '../../../shared/widgets/diyalog.dart';
import '../../../shared/widgets/form_kabuk.dart';
import '../../../shared/widgets/mono.dart';

/// K3 · Ekip daveti. Kod üretilir, sahada sözlü de okunabilir
/// (karıştırılabilir karakterler kod alfabesinden çıkarılmıştır).
class DavetDiyalogu extends ConsumerStatefulWidget {
  const DavetDiyalogu({required this.storeId, super.key});
  final String storeId;
  @override
  ConsumerState<DavetDiyalogu> createState() => _DavetDiyaloguState();
}

class _DavetDiyaloguState extends ConsumerState<DavetDiyalogu> {
  final _ad = TextEditingController();
  AppRole _rol = AppRole.pazarlamaci;
  String? _kod;
  String? _hata;
  bool _mesgul = false;

  @override
  void dispose() { _ad.dispose(); super.dispose(); }

  Future<void> _uret() async {
    setState(() { _mesgul = true; _hata = null; });
    try {
      final k = await ref.read(orgRepositoryProvider).ekipDavetiOlustur(
            storeId: widget.storeId,
            rol: _rol,
            adSoyad: _ad.text.trim().isEmpty ? null : _ad.text.trim(),
          );
      setState(() => _kod = k);
    } catch (e) {
      setState(() =>
          _hata = e.toString().replaceFirst(RegExp(r'^\w+Exception:?\s*'), ''));
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Diyalog(
      baslik: _kod == null ? 'Ekibe davet et' : 'Davet kodu hazır',
      altBaslik: _kod == null
          ? 'Kod kurumu ve dükkanı taşır — davet edilen elle seçim yapmaz'
          : null,
      hata: _hata,
      mesgul: _mesgul,
      vazgecEtiketi: _kod == null ? 'Vazgeç' : 'Kapat',
      onVazgec: () => Navigator.pop(context),
      onayEtiketi: 'Kod üret',
      onayKey: K.davetUret,
      // Kod üretildikten sonra yapılacak bir şey kalmıyor: onay düğmesini
      // orada bırakmak "bir daha üret" gibi okunuyordu.
      onOnay: _kod == null ? _uret : null,
      children: [
        if (_kod == null) ...[
          DropdownButtonFormField<AppRole>(
            key: K.davetRol,
            initialValue: _rol,
            decoration: const InputDecoration(labelText: 'Rol'),
            items: const [
              DropdownMenuItem(
                  value: AppRole.pazarlamaci, child: Text('Pazarlamacı')),
              DropdownMenuItem(
                  value: AppRole.dukkanMuduru, child: Text('Dükkan müdürü')),
              DropdownMenuItem(
                  value: AppRole.hazirlik, child: Text('Hazırlık')),
            ],
            onChanged: (v) => setState(() => _rol = v ?? _rol),
          ),
          TextField(
            key: K.davetAd,
            controller: _ad,
            decoration: const InputDecoration(
                labelText: 'Ad soyad (isteğe bağlı)',
                hintText: 'Kimi davet ettiğinizi hatırlamak için'),
          ),
        ] else ...[
          const Bildirim(
            'Kodu kişiye iletin. Uygulamaya kaydolup bu kodu girdiğinde '
            'ekibe otomatik katılır. Kod 14 gün geçerlidir.',
            tip: BildirimTip.basari),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: T.s4),
            decoration: BoxDecoration(
              color: s.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(T.rDugme),
              border: Border.all(color: s.outlineVariant),
            ),
            child: Center(
              child: Mono(_kod!, key: K.davetKod, size: 26,
                  weight: FontWeight.w600, color: T.bordo),
            ),
          ),
          OutlinedButton.icon(
            key: K.davetKopyala,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _kod!));
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Kod kopyalandı')));
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Kopyala'),
          ),
        ],
      ],
    );
  }
}
