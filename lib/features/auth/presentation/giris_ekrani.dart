import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/supabase.dart';
import '../../../core/test_keys.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../shared/widgets/dokunus.dart';
import '../../../shared/widgets/form_kabuk.dart';

/// K3 · Birincil yol telefon OTP. SMS sağlayıcısı bağlanana kadar e-posta
/// ile de girilebilir; kullanıcı sekmeyle seçer.
class GirisEkrani extends ConsumerStatefulWidget {
  const GirisEkrani({super.key});
  @override
  ConsumerState<GirisEkrani> createState() => _GirisEkraniState();
}

enum _Yol { telefon, eposta, parola }

class _GirisEkraniState extends ConsumerState<GirisEkrani> {
  final _kimlik = TextEditingController();
  final _kod = TextEditingController();
  _Yol _yol = _Yol.telefon;
  bool _kodGonderildi = false;
  bool _mesgul = false;
  String? _hata;
  String? _bilgi;

  @override
  void dispose() {
    _kimlik.dispose();
    _kod.dispose();
    super.dispose();
  }

  String get _telefon {
    var t = _kimlik.text.trim().replaceAll(RegExp(r'[\s()-]'), '');
    if (t.startsWith('0')) t = t.substring(1);
    if (!t.startsWith('+')) t = '+90$t';
    return t;
  }

  Future<void> _calistir(Future<void> Function() f, {String? basari}) async {
    setState(() { _mesgul = true; _hata = null; _bilgi = null; });
    try {
      await f();
      if (mounted) setState(() => _bilgi = basari);
    } catch (e) {
      if (mounted) setState(() => _hata = _oku(e));
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  static String _oku(Object e) {
    final m = e.toString();
    if (m.contains('Invalid login')) return 'E-posta veya parola hatalı.';
    if (m.contains('Token has expired') || m.contains('expired')) {
      return 'Kodun süresi doldu, yeniden isteyin.';
    }
    if (m.contains('Invalid token')) return 'Kod hatalı.';
    if (m.contains('provider is not enabled') || m.contains('Unsupported phone')) {
      return 'Telefon girişi henüz açık değil. E-posta sekmesini kullanın.';
    }
    return m.replaceFirst(RegExp(r'^\w+Exception:?\s*'), '');
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(authRepositoryProvider);
    final telefonMu = _yol == _Yol.telefon;
    final parolaMu = _yol == _Yol.parola;

    return FormKabuk(
      baslik: 'İşlerPro',
      altBaslik: 'Okul kanalı kitap ve deneme yönetimi',
      children: [
        if (!SupabaseConfig.yapilandirildi) ...[
          const Bildirim(
            'Supabase yapılandırılmadı. --dart-define SUPABASE_URL ve '
            'SUPABASE_ANON_KEY verilmeden giriş yapılamaz.',
            tip: BildirimTip.uyari),
        ] else ...[
          SegmentedButton<_Yol>(
            segments: const [
              ButtonSegment(value: _Yol.telefon, label: Text('Telefon'),
                  icon: Icon(Icons.smartphone, size: 16, key: K.girisYolTelefon)),
              ButtonSegment(value: _Yol.eposta, label: Text('E-posta'),
                  icon: Icon(Icons.alternate_email, size: 16, key: K.girisYolEposta)),
              if (SupabaseConfig.devLogin)
                ButtonSegment(value: _Yol.parola, label: Text('Parola'),
                    icon: Icon(Icons.key, size: 16, key: K.girisYolParola)),
            ],
            selected: {_yol},
            onSelectionChanged: (s) => setState(() {
              _yol = s.first; _kodGonderildi = false; _hata = null; _bilgi = null;
            }),
          ),
          const SizedBox(height: T.s4),
          if (_hata != null) Bildirim(_hata!, tip: BildirimTip.hata),
          if (_bilgi != null) Bildirim(_bilgi!, tip: BildirimTip.basari),
          TextField(
            key: K.girisKimlik,
            controller: _kimlik,
            enabled: !_kodGonderildi,
            onChanged: (_) => setState(() {}),
            keyboardType: telefonMu ? TextInputType.phone : TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: telefonMu ? 'Telefon' : 'E-posta',
              hintText: telefonMu ? '0532 000 00 00' : 'ad@ornek.com',
              prefixIcon: Icon(telefonMu ? Icons.smartphone : Icons.alternate_email,
                  size: 18),
            ),
          ),
          const SizedBox(height: T.s3),
          if (parolaMu) ...[
            TextField(
              key: K.girisKod,
              controller: _kod,
              obscureText: true,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                  labelText: 'Parola', prefixIcon: Icon(Icons.key, size: 18)),
            ),
            const SizedBox(height: T.s3),
            FilledButton(
              key: K.girisGonder,
              onPressed: _mesgul || _kod.text.isEmpty
                  ? null
                  : () => _calistir(() => repo.parolaIleGiris(
                      _kimlik.text.trim(), _kod.text)),
              child: _mesgul ? const _Bekle() : const Text('Giriş yap'),
            ),
          ] else if (_kodGonderildi) ...[
            TextField(
              key: K.girisKod,
              controller: _kod,
              keyboardType: TextInputType.number,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Doğrulama kodu',
                hintText: '6 haneli kod',
                prefixIcon: Icon(Icons.password, size: 18),
              ),
            ),
            const SizedBox(height: T.s3),
            FilledButton(
              key: K.girisGonder,
              onPressed: _mesgul || _kod.text.trim().length < 4
                  ? null
                  : () => _calistir(() => repo.otpDogrula(
                    telefon: telefonMu ? _telefon : null,
                    eposta: telefonMu ? null : _kimlik.text.trim(),
                    kod: _kod.text.trim(),
                  )),
              child: _mesgul
                  ? const _Bekle()
                  : const Text('Giriş yap'),
            ),
            TextButton(
              onPressed: _mesgul ? null : () => setState(() => _kodGonderildi = false),
              child: const Text('Numarayı değiştir'),
            ),
          ] else
            FilledButton(
              key: K.girisGonder,
              onPressed: _mesgul || _kimlik.text.trim().isEmpty
                  ? null
                  : () => _calistir(
                        () async {
                          await repo.otpGonder(
                            telefon: telefonMu ? _telefon : null,
                            eposta: telefonMu ? null : _kimlik.text.trim(),
                          );
                          if (mounted) setState(() => _kodGonderildi = true);
                        },
                        basari: telefonMu
                            ? 'Kod SMS ile gönderildi.'
                            : 'Kod e-postanıza gönderildi.',
                      ),
              child: _mesgul ? const _Bekle() : const Text('Kod gönder'),
            ),
        ],
      ],
    );
  }
}

class _Bekle extends StatelessWidget {
  const _Bekle();
  @override
  Widget build(BuildContext context) => SizedBox(
      width: 18,
      height: 18,
      // Rengi elle beyaz vermek koyu temada görünmez bir çark bırakıyordu.
      child: Bekleme(boy: 16, renk: Theme.of(context).colorScheme.onPrimary));
}
