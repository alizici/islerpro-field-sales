import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session.dart';
import '../../../core/test_keys.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../shared/widgets/form_kabuk.dart';

/// K44 · Aydınlatma metni ilk girişte gösterilir ve onay kaydedilir.
///
/// Sistem imza ve fotoğraf toplamıyor (K32), konum toplamıyor (K10),
/// öğrenci verisi tutmuyor (V4) — ama **ad, telefon, branş, irtibat kişileri
/// ve ziyaret notları** hâlâ kişisel veridir. Yükümlülük azaldı, bitmedi.
class KvkkEkrani extends ConsumerStatefulWidget {
  const KvkkEkrani({super.key});
  @override
  ConsumerState<KvkkEkrani> createState() => _KvkkEkraniState();
}

class _KvkkEkraniState extends ConsumerState<KvkkEkrani> {
  static const surum = '2026-08-v1';
  bool _okudum = false;
  bool _mesgul = false;
  String? _hata;

  @override
  Widget build(BuildContext context) {
    final oturum = ref.watch(sessionProvider);
    final s = Theme.of(context).colorScheme;

    return FormKabuk(
      baslik: 'Kişisel verilerin korunması',
      altBaslik: 'Devam etmeden önce bir kez okunur',
      genislik: 520,
      children: [
        if (_hata != null) Bildirim(_hata!, tip: BildirimTip.hata),
        Container(
          key: K.kvkkMetin,
          constraints: const BoxConstraints(maxHeight: 320),
          padding: const EdgeInsets.all(T.s4),
          decoration: BoxDecoration(
            color: s.surfaceContainerLow,
            border: Border.all(color: s.outlineVariant),
            borderRadius: BorderRadius.circular(T.rKart),
          ),
          child: const SingleChildScrollView(child: _Metin()),
        ),
        const SizedBox(height: T.s3),
        CheckboxListTile(
          value: _okudum,
          onChanged: (v) => setState(() => _okudum = v ?? false),
          contentPadding: EdgeInsets.zero,
          title: const Text('Okudum, anladım'),
        ),
        const SizedBox(height: T.s2),
        FilledButton(
          key: K.kvkkOnayla,
          // Tenant KOŞUL DEĞİL: öğretmenin işletme üyeliği yoktur (K3) ve
          // burada tenant istenince rolün tamamı bu ekranda kilitleniyordu —
          // çalışan tek düğme "Çıkış yap"tı. Onayı hangi işletmeye yazacağını
          // sunucu çözüyor (0037).
          onPressed: !_okudum || _mesgul
              ? null
              : () async {
                  setState(() { _mesgul = true; _hata = null; });
                  try {
                    await ref.read(authRepositoryProvider)
                        .onayKaydet(oturum?.tenantId, surum);
                    await ref.read(sessionStateProvider.notifier).yenile();
                  } catch (e) {
                    setState(() => _hata = e.toString()
                        .replaceFirst(RegExp(r'^\w+Exception:?\s*'), ''));
                  } finally {
                    if (mounted) setState(() => _mesgul = false);
                  }
                },
          child: const Text('Onaylıyorum'),
        ),
        TextButton(
          onPressed: () => ref.read(sessionStateProvider.notifier).cikis(),
          child: const Text('Çıkış yap'),
        ),
      ],
    );
  }
}

class _Metin extends StatelessWidget {
  const _Metin();

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).textTheme.bodySmall;
    final k = Theme.of(context).textTheme.titleSmall;
    Widget baslik(String t) => Padding(
        padding: const EdgeInsets.only(top: T.s3, bottom: T.s1),
        child: Text(t, style: k));
    Widget p(String t) => Padding(
        padding: const EdgeInsets.only(bottom: T.s1), child: Text(t, style: b));

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Aydınlatma Metni', style: Theme.of(context).textTheme.titleMedium),
      p('Sürüm 2026-08-v1'),
      baslik('Veri sorumlusu'),
      p('Bu uygulamayı kullanan işletmedir. Uygulamayı sağlayan taraf veri '
        'sorumlusu değil, veri işleyendir.'),
      baslik('İşlenen veriler'),
      p('· Kullanıcı: ad soyad, telefon, e-posta\n'
        '· Kurum irtibat kişileri: ad soyad, telefon, branş, görev\n'
        '· Ticari kayıtlar: talep, sipariş, teslimat, tahsilat\n'
        '· Ziyaret notları'),
      baslik('Toplanmayan veriler'),
      p('· Konum bilgisi — ziyaret kaydı yalnızca saat damgası tutar\n'
        '· İmza ve fotoğraf — teslimat kaydında toplanmaz\n'
        '· Öğrenci adı veya kimliği — deneme programı yalnızca adet tutar'),
      baslik('Amaç'),
      p('Okul kanalı kitap ve deneme satışının yürütülmesi; talep, sipariş, '
        'teslimat ve tahsilat süreçlerinin takibi.'),
      baslik('Saklama süresi'),
      p('Ticari kayıtlar ilgili mevzuatın öngördüğü saklama süresince tutulur. '
        'Süre sonunda kişisel alanlar anonimleştirilir; mali hareketler '
        'kimliksiz olarak korunur.'),
      baslik('Haklarınız'),
      p('Verilerinize erişme, düzeltme ve silinmesini isteme hakkınız vardır. '
        'Silme talebinde kişisel alanlar anonimleştirilir, mali hareketler '
        'yasal saklama süresi boyunca kalır. Talepleriniz için işletmeye '
        'başvurabilirsiniz.'),
    ]);
  }
}
