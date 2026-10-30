import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session.dart';
import '../../../core/test_keys.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/repositories/kurum_repository.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/widgets/cam.dart';
import '../../../shared/widgets/bolum.dart';
import '../../../shared/widgets/detay.dart';
import '../../../shared/widgets/diyalog.dart';
import '../../../shared/widgets/form_kabuk.dart';
import '../../../shared/widgets/liste.dart';
import '../../../shared/widgets/mono.dart';
import '../../../shared/widgets/parcalar.dart';
import '../../../shared/widgets/satir.dart';
import '../../accounts/presentation/cari_detay_ekrani.dart';

final kurumDetayProvider = FutureProvider.autoDispose
    .family<KurumDetay, String>((ref, id) =>
        ref.watch(kurumRepositoryProvider).detay(id));

/// Kurum detayı — cari sekmeleri (K5), kişiler (K30), şube zinciri (K18).
///
/// **K7 · Bakiyeler TOPLANMAZ.** Kurum yalnızca bir çatıdır; kurumun carisiyle
/// öğretmenin carisi ayrı hukuki kişilerdir. Başlıkta toplam risk satırı yoktur.
class KurumDetayEkrani extends ConsumerWidget {
  const KurumDetayEkrani({required this.kurumId, super.key});
  final String kurumId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detay = ref.watch(kurumDetayProvider(kurumId));
    final oturum = ref.watch(sessionProvider);

    return CamSayfa(
      baslik: detay.maybeWhen(
          data: (d) => d.kurum.ad, orElse: () => 'Kurum'),
      cocuklar: detay.when(
        loading: () => const [
          CamKart(dolgu: false, child: IskeletListe(satir: 5)),
        ],
        error: (e, _) => [Bildirim(e.toString(), tip: BildirimTip.hata)],
        data: (d) => [
          _Kunye(k: d.kurum, subeler: d.subeler),
          const SizedBox(height: T.s4),
          _Cariler(cariler: d.cariler),
          const SizedBox(height: T.s4),
          _Kisiler(
            kisiler: d.kisiler,
            kurumId: kurumId,
            storeId: oturum?.storeId,
          ),
          const SonBosluk(),
        ],
      ),
    );
  }
}

class _Kunye extends StatelessWidget {
  const _Kunye({required this.k, required this.subeler});
  final KurumOzet k;
  final List<({String id, String ad})> subeler;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return DetayBandi(
      baslik: k.ad,
      altBilgi: [
        k.kursMerkezi ? 'Özel kurs merkezi' : 'Okul',
        if (k.kademe != null) KurumOzet.kademeAd(k.kademe!),
        ?k.tur,
        if (k.ilce != null) '${k.il ?? ""} · ${k.ilce}',
        if (k.mebKodu != null) 'MEB ${k.mebKodu}',
      ].join(' · '),
      durum: k.dogrulandi ? null : 'Doğrulanmadı — bilgileri teyit edilmeli',
      durumRengi: k.dogrulandi ? s.primary : s.uyari,
      ikon: k.kursMerkezi
          ? Icons.cast_for_education_outlined
          : Icons.school_outlined,
      // K22 · öğrenci sayısı iskonto kademesini belirleyen girdi; kurumun
      // en çok bakılan sayısı bu.
      etiket: k.ogrenciSayisi == null ? null : 'Öğrenci',
      deger: k.ogrenciSayisi == null ? null : Fmt.adet(k.ogrenciSayisi),
      alt: subeler.isEmpty
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const BolumBasligi('Şubeler'),
                for (final sb in subeler)
                  Text('· ${sb.ad}',
                      style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
    );
  }
}

/// K5 · Aynı kurumda birden çok cari olabilir: kurumsal + her öğretmen ayrı.
/// K7 · Bakiyeler TOPLANMAZ — her cari kendi başına değerlendirilir.
class _Cariler extends StatelessWidget {
  const _Cariler({required this.cariler});
  final List<CariOzet> cariler;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return CamKart(
      key: K.kurumDetayCariler,
      dolgu: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SayacSeridi('Cariler · ${cariler.length}',
              sag: 'Bakiyeler toplanmaz'),
          Divider(height: 1, color: s.outlineVariant),
          if (cariler.isEmpty)
            const BosDurum('Bu kurumda henüz cari yok',
                ikon: Icons.account_balance_wallet_outlined,
                aciklama: 'Cari, alışverişin muhatabı. Bir okulda birden çok '
                    'olabilir: okulun kendi hesabı ve her öğretmen ayrı '
                    'birer cari.')
          else
            for (final c in cariler)
              KayitSatiri(
                key: ValueKey('cari.${c.id}'),
                baslik: c.unvan,
                altBilgi: [
                  c.kurumsal ? 'Kurumsal' : 'Öğretmen',
                  ?c.portfoySahibi,
                  if (c.limit > 0) 'limit ${Fmt.para(c.limit)}',
                ].join(' · '),
                ikon: c.kurumsal
                    ? Icons.business_outlined
                    : Icons.person_outline,
                durumRengi:
                    c.bakiye > 0 ? s.uyari : s.onSurfaceVariant,
                deger: Fmt.para(c.bakiye),
                degerRengi: c.bakiye > 0 ? s.error : null,
                onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => CariDetayEkrani(cariId: c.id))),
              ),
          // K7 · kurum yalnızca bir çatıdır; kurumun carisiyle öğretmenin
          // carisi ayrı hukuki kişilerdir.
          const Padding(
            padding: EdgeInsets.all(T.s4),
            child: KuralNotu('Kurumsal ve öğretmen carileri ayrıdır — '
                'bakiyeler toplanmaz, kurum kimsenin kefili değildir.'),
          ),
        ],
      ),
    );
  }
}

/// K30 · Kişi kayıtları yalnızca kendi işletmesine görünür.
class _Kisiler extends ConsumerWidget {
  const _Kisiler({required this.kisiler, required this.kurumId, this.storeId});
  final List<KisiOzet> kisiler;
  final String kurumId;
  final String? storeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = Theme.of(context).colorScheme;
    return Column(
      key: K.kurumDetayKisiler,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SayacSeridi('Kurumdaki kişiler · ${kisiler.length}',
            sag: 'Yalnızca sizin işletmenize görünür'),
        if (storeId != null)
          EylemCipleri([
            Eylem(Icons.person_add_alt, 'Öğretmen davet et',
                dugmeKey: K.kurumOgretmenDavet,
                () => showDialog<void>(
                      context: context,
                      builder: (_) => _OgretmenDavetDiyalogu(
                          kurumId: kurumId, storeId: storeId!),
                    )),
          ])
        else
          Divider(height: 1, color: s.outlineVariant),
        if (kisiler.isEmpty)
          const BosDurum('Henüz kişi kaydı yok',
              ikon: Icons.people_outline,
              aciklama: 'Kişi kayıtları yalnızca kendi işletmenize '
                  'görünür; başka bir dükkan bu listeyi göremez.')
        else
          for (final p in kisiler)
            KayitSatiri(
              baslik: p.adSoyad,
              altBilgi: [p.gorev, p.brans, p.telefon]
                  .nonNulls
                  .where((e) => e.isNotEmpty)
                  .join(' · '),
              vurgu: p.hesabiVar ? 'Uygulamada' : null,
              vurguRengi: s.basarili,
              ikon: Icons.person_outline,
              durumRengi: p.hesabiVar ? s.basarili : s.onSurfaceVariant,
            ),
      ],
    );
  }
}

/// K3 · Davet kodu kurumu ve dükkanı taşır — öğretmen elle kurum seçmez,
/// yanlış eşleşme ve sahte kayıt bu noktada kesilir.
class _OgretmenDavetDiyalogu extends ConsumerStatefulWidget {
  const _OgretmenDavetDiyalogu({required this.kurumId, required this.storeId});
  final String kurumId, storeId;
  @override
  ConsumerState<_OgretmenDavetDiyalogu> createState() => _ODState();
}

class _ODState extends ConsumerState<_OgretmenDavetDiyalogu> {
  final _tel = TextEditingController();
  String? _kod, _hata;
  bool _mesgul = false;

  @override
  void dispose() { _tel.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Diyalog(
      baslik: _kod == null ? 'Öğretmen davet et' : 'Davet kodu hazır',
      // K3 · davet kodu kurumu ve dükkanı TAŞIR; öğretmen elle kurum
      // seçmez — yanlış eşleşme ve sahte kayıt bu noktada kesilir.
      altBaslik: _kod == null ? 'Kod kurumu ve dükkanı taşır' : null,
      hata: _hata,
      mesgul: _mesgul,
      genislik: 400,
      vazgecEtiketi: _kod == null ? 'Vazgeç' : 'Kapat',
      onVazgec: () => Navigator.pop(context),
      onayEtiketi: 'Kod üret',
      onOnay: _kod == null ? _uret : null,
      children: [
        if (_kod == null) ...[
          const Bildirim(
            'Öğretmen kurum seçmez. Kaydolduktan sonra sizin onayınızı '
            'bekler; onaya kadar katalog ve fiyat göremez.',
            tip: BildirimTip.bilgi),
          TextField(
            controller: _tel,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
                labelText: 'Telefon (isteğe bağlı)',
                hintText: 'Kimi davet ettiğinizi hatırlamak için'),
          ),
        ] else ...[
          const Bildirim('Kodu öğretmene iletin. 14 gün geçerlidir.',
              tip: BildirimTip.basari),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: T.s4),
            decoration: BoxDecoration(
              color: s.surfaceContainerHigh,
              border: Border.all(color: s.outlineVariant),
              borderRadius: BorderRadius.circular(T.rDugme),
            ),
            child: Center(
              child: Mono(_kod!, size: 26, weight: FontWeight.w600,
                  color: T.bordo),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _uret() async {
    setState(() { _mesgul = true; _hata = null; });
    try {
      final k = await ref.read(kurumRepositoryProvider).ogretmenDaveti(
            widget.kurumId, widget.storeId,
            telefon: _tel.text.trim().isEmpty ? null : _tel.text.trim(),
          );
      if (mounted) setState(() => _kod = k);
    } catch (e) {
      if (!mounted) return;
      setState(() => _hata =
          e.toString().replaceFirst(RegExp(r'^\w+Exception:?\s*'), ''));
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }
}