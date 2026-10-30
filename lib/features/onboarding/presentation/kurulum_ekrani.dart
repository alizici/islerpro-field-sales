import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../shared/widgets/dokunus.dart';
import '../../../shared/widgets/form_kabuk.dart';

/// İlk kullanıcı kendini var eder: işletme + dükkan + iki dönem (K8) + sahiplik.
/// Öğretmen bu ekranı görmez — o davet koduyla girer (K3).
class KurulumEkrani extends ConsumerStatefulWidget {
  const KurulumEkrani({super.key});
  @override
  ConsumerState<KurulumEkrani> createState() => _KurulumEkraniState();
}

class _KurulumEkraniState extends ConsumerState<KurulumEkrani> {
  final _unvan = TextEditingController();
  final _dukkan = TextEditingController(text: 'Merkez Şube');
  final _il = TextEditingController();
  final _ilce = TextEditingController();
  final _davet = TextEditingController();
  bool _mesgul = false;
  String? _hata;
  bool _davetYolu = false;

  @override
  void dispose() {
    for (final c in [_unvan, _dukkan, _il, _ilce, _davet]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _calistir(Future<void> Function() f) async {
    setState(() { _mesgul = true; _hata = null; });
    try {
      await f();
      await ref.read(sessionStateProvider.notifier).yenile();
    } catch (e) {
      if (mounted) {
        setState(() => _hata =
            e.toString().replaceFirst(RegExp(r'^\w+Exception:?\s*'), ''));
      }
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(authRepositoryProvider);
    return FormKabuk(
      baslik: _davetYolu ? 'Davet kodu' : 'İşletmenizi kurun',
      altBaslik: _davetYolu
          ? 'Pazarlamacınızdan aldığınız kodu girin'
          : 'Bir kez yapılır. Dönemler otomatik oluşturulur.',
      genislik: 440,
      children: [
        if (_hata != null) Bildirim(_hata!, tip: BildirimTip.hata),
        if (_davetYolu) ...[
          TextField(
            controller: _davet,
            textCapitalization: TextCapitalization.characters,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
                labelText: 'Davet kodu', hintText: '8 karakter'),
          ),
          const SizedBox(height: T.s3),
          FilledButton(
            onPressed: _mesgul || _davet.text.trim().length < 4
                ? null
                : () => _calistir(() => repo.davetKullan(_davet.text.trim())),
            child: const Text('Kodu kullan'),
          ),
          TextButton(
            onPressed: () => setState(() => _davetYolu = false),
            child: const Text('İşletme kurmak istiyorum'),
          ),
        ] else ...[
          TextField(
            controller: _unvan,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
                labelText: 'İşletme unvanı', hintText: 'İşler Yayınları Kitap'),
          ),
          const SizedBox(height: T.s3),
          TextField(
            controller: _dukkan,
            decoration: const InputDecoration(labelText: 'İlk dükkan adı'),
          ),
          const SizedBox(height: T.s3),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _il,
                decoration: const InputDecoration(
                    labelText: 'İl', hintText: 'Şanlıurfa'),
              ),
            ),
            const SizedBox(width: T.s3),
            Expanded(
              child: TextField(
                controller: _ilce,
                decoration: const InputDecoration(
                    labelText: 'İlçe', hintText: 'Haliliye'),
              ),
            ),
          ]),
          const SizedBox(height: T.s4),
          const Bildirim(
            '2 yarıyıl dönemi otomatik açılır: 1 Eylül–31 Ocak ve '
            '1 Şubat–31 Ağustos. Bugünün içinde olduğu dönem aktif olur.',
            tip: BildirimTip.bilgi),
          FilledButton(
            onPressed: _mesgul || _unvan.text.trim().isEmpty
                ? null
                : () => _calistir(() => repo.kurulumYap(
                      unvan: _unvan.text.trim(),
                      dukkanAd: _dukkan.text.trim().isEmpty
                          ? 'Merkez Şube'
                          : _dukkan.text.trim(),
                      il: _il.text.trim().isEmpty ? null : _il.text.trim(),
                      ilce: _ilce.text.trim().isEmpty ? null : _ilce.text.trim(),
                    )),
            child: _mesgul
                ? const SizedBox(
                    width: 18, height: 18,
                    child: Bekleme(boy: 16, renk: Colors.white))
                : const Text('İşletmeyi kur'),
          ),
          TextButton(
            onPressed: () => setState(() => _davetYolu = true),
            child: const Text('Davet kodum var (öğretmen)'),
          ),
        ],
        TextButton(
          onPressed: () => ref.read(sessionStateProvider.notifier).cikis(),
          child: const Text('Çıkış yap'),
        ),
      ],
    );
  }
}
