import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session.dart';
import '../../../core/test_keys.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/repositories/siparis_repository.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/widgets/cam.dart';
import '../../../shared/widgets/detay.dart';
import '../../../shared/widgets/form_kabuk.dart';
import '../../../shared/widgets/liste.dart';
import '../../../shared/widgets/parcalar.dart';
import 'siparisler_ekrani.dart' show siparisRengi;
import 'teslimat_diyalogu.dart';

final siparisDetayProvider = FutureProvider.autoDispose
    .family<SiparisDetay, String>(
        (ref, id) => ref.watch(siparisRepositoryProvider).detay(id));

/// Siparişin yaşam çizgisi. Rozet "hazırlanıyor" der ve susar; çizgi bundan
/// SONRA ne olacağını da söyler — kullanıcı sırayı ekrandan öğrenir.
const _asamalar = ['Oluştu', 'Hazırlanıyor', 'Hazır', 'Sevk', 'Teslim'];

int _asama(String durum) => switch (durum) {
      'onay_bekliyor' || 'olusturuldu' || 'reddedildi' || 'iptal' => 0,
      'hazirlaniyor' => 1,
      'hazir' => 2,
      'sevk_edildi' || 'kismi_teslim' => 3,
      'teslim_edildi' || 'kapandi' => 4,
      _ => 0,
    };

String _durumAdi(String durum) => switch (durum) {
      'olusturuldu' => 'Oluşturuldu',
      'onay_bekliyor' => 'Onay bekliyor',
      'reddedildi' => 'Reddedildi',
      'hazirlaniyor' => 'Hazırlanıyor',
      'hazir' => 'Hazır',
      'sevk_edildi' => 'Sevk edildi',
      'kismi_teslim' => 'Kısmi teslim',
      'teslim_edildi' => 'Teslim edildi',
      'kapandi' => 'Kapandı',
      'iptal' => 'İptal',
      _ => durum,
    };

/// K46 · Hazırlık akışı: kim hazırladı, ne zaman.
/// K26 · Borç burada değil TESLİMATTA doğar.
class SiparisDetayEkrani extends ConsumerStatefulWidget {
  const SiparisDetayEkrani({required this.siparisId, super.key});
  final String siparisId;

  @override
  ConsumerState<SiparisDetayEkrani> createState() =>
      _SiparisDetayEkraniState();
}

class _SiparisDetayEkraniState extends ConsumerState<SiparisDetayEkrani> {
  bool _degisti = false;
  String? _hata;

  Future<void> _durum(String durum) async {
    try {
      await ref.read(siparisRepositoryProvider)
          .durumDegistir(widget.siparisId, durum);
      _degisti = true;
      ref.invalidate(siparisDetayProvider(widget.siparisId));
      if (mounted) setState(() => _hata = null);
    } catch (e) {
      if (mounted) setState(() => _hata = e.toString());
    }
  }

  Future<void> _teslim(SiparisDetay d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => TeslimatDiyalogu(siparis: d),
    );
    if (ok == true) {
      _degisti = true;
      ref.invalidate(siparisDetayProvider(widget.siparisId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final detay = ref.watch(siparisDetayProvider(widget.siparisId));
    final oturum = ref.watch(sessionProvider);
    final yetkili = oturum?.aktifRol == AppRole.isletmeSahibi ||
        oturum?.aktifRol == AppRole.dukkanMuduru;
    final d = detay.value;

    return CamSayfa(
      baslik: 'Sipariş',
      // Geri dönerken listeye "değişti mi" bilgisini taşıyan tek yol bu:
      // sistemin kendi geri hareketi bir sonuç döndüremiyor.
      oncul: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.pop(context, _degisti),
      ),
      // Asıl eylem listenin dibinde kaybolmaz: telefonda kullanıcı
      // kaydırmayı bırakıp "şimdi ne yapacağım" diye düşünmek zorunda
      // kalıyordu.
      altSerit: d == null
          ? null
          : _Eylemler(d: d, hata: _hata, onDurum: _durum,
              onTeslim: () => _teslim(d)),
      cocuklar: detay.when(
        loading: () => const [
          _BantIskeleti(),
          SizedBox(height: T.s4),
          CamKart(dolgu: false, child: IskeletListe(satir: 4, ikon: false)),
        ],
        error: (e, _) => [Bildirim(e.toString(), tip: BildirimTip.hata)],
        data: (d) => [
            _Bant(d: d),
            if (d.onayGerekce != null && d.durum == 'onay_bekliyor')
              _OnayKutusu(d: d, yetkili: yetkili,
                  onOnay: () => _durum('olusturuldu'),
                  onRed: () => _durum('reddedildi')),
            _Kalemler(d: d),
          const SonBosluk(),
        ],
      ),
    );
  }
}

class _BantIskeleti extends StatelessWidget {
  const _BantIskeleti();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: T.s3),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Iskelet(190, 16),
          SizedBox(height: T.s2),
          Iskelet(120, 11),
          SizedBox(height: T.s5),
          Iskelet(150, 28),
        ]),
      );
}

class _Bant extends StatelessWidget {
  const _Bant({required this.d});
  final SiparisDetay d;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final kirik = d.durum == 'reddedildi' || d.durum == 'iptal';
    return DetayBandi(
      baslik: d.cariUnvan,
      altBilgi: [
        if (d.kurumAd.isNotEmpty) d.kurumAd,
        Fmt.tarihSaat(d.createdAt),
        ?d.olusturan,
      ].join(' · '),
      durum: _durumAdi(d.durum),
      durumRengi: siparisRengi(s, d.durum),
      ikon: Icons.receipt_long_outlined,
      etiket: 'Sipariş tutarı',
      deger: Fmt.para(d.toplam),
      // K26 · borç burada değil teslimatta doğar.
      degerAlti: 'Sipariş henüz borç değildir — borç teslimatla doğar',
      yanlar: [
        ('Kalem', '${d.kalemler.length}', null),
        if (d.toplamBackorder > 0)
          ('Sevk edilmeyen', '${Fmt.adet(d.toplamBackorder)} adet', s.uyari),
      ],
      alt: Column(mainAxisSize: MainAxisSize.min, children: [
        AsamaCizgisi(
          asamalar: _asamalar,
          aktif: _asama(d.durum),
          kirik: kirik,
          renk: siparisRengi(s, d.durum),
        ),
        // K46 · kim hazırladı, ne zaman — akışın kime emanet olduğunu
        // gösteren tek bilgi bu.
        if (d.hazirlayan != null) ...[
          const SizedBox(height: T.s3),
          KuralNotu(
            [
              'Hazırlayan: ${d.hazirlayan}',
              if (d.hazirlikBitti != null)
                'bitti ${Fmt.tarihSaat(d.hazirlikBitti)}',
            ].join(' · '),
            ikon: Icons.inventory_2_outlined,
          ),
        ],
      ]),
    );
  }
}

class _OnayKutusu extends StatelessWidget {
  const _OnayKutusu({required this.d, required this.yetkili,
                     required this.onOnay, required this.onRed});
  final SiparisDetay d;
  final bool yetkili;
  final VoidCallback onOnay, onRed;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Container(
      key: K.siparisOnayUyari,
      margin: const EdgeInsets.all(T.s4),
      decoration: BoxDecoration(
        color: s.uyari.withValues(alpha: 0.07),
        border: Border.all(color: s.uyari.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(T.rKart),
      ),
      padding: const EdgeInsets.all(T.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.gpp_maybe_outlined, size: 17, color: s.uyari),
            const SizedBox(width: T.s2),
            Expanded(
              child: Text('Onay bekliyor',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(color: s.uyari)),
            ),
          ]),
          const SizedBox(height: T.s2),
          Text(
            'Bu sipariş ${d.onayGerekce} sebebiyle onaya düştü. '
            'Onaylanmadan hazırlığa geçemez.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: T.s4),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                  onPressed: yetkili ? onRed : null,
                  child: const Text('Reddet')),
            ),
            const SizedBox(width: T.s3),
            Expanded(
              child: FilledButton(
                key: K.siparisOnayla,
                onPressed: yetkili ? onOnay : null,
                child: const Text('Onayla'),
              ),
            ),
          ]),
          if (!yetkili)
            Padding(
              padding: const EdgeInsets.only(top: T.s2),
              child: Text('Yalnızca sahip veya müdür onaylayabilir',
                  style: Theme.of(context).textTheme.bodySmall),
            ),
        ],
      ),
    );
  }
}

class _Kalemler extends StatelessWidget {
  const _Kalemler({required this.d});
  final SiparisDetay d;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Column(
      key: K.siparisKalemler,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SayacSeridi('${d.kalemler.length} kalem'),
        Divider(height: 1, color: s.outlineVariant),
        for (var i = 0; i < d.kalemler.length; i++) ...[
          if (i > 0) Divider(height: 1, color: s.outlineVariant),
          _Kalem(k: d.kalemler[i]),
        ],
        ToplamSatiri(
          etiket: 'Sipariş tutarı',
          deger: Fmt.para(d.toplam),
          altSatirlar: [
            if (d.toplamBackorder > 0)
              ('Sevk edilmeyen', '${Fmt.adet(d.toplamBackorder)} adet',
                  s.uyari),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(T.s4, T.s4, T.s4, 0),
          child: Column(children: [
            // K28 · fiyat ve iskonto sipariş anında damgalandı.
            const KuralNotu('Fiyat ve iskonto sipariş anında damgalandı — '
                'katalog fiyatı değişse bu sipariş oynamaz.'),
            if (d.toplamBackorder > 0) ...[
              const SizedBox(height: T.s2),
              KuralNotu(
                  'Sevk edilmemiş ${Fmt.adet(d.toplamBackorder)} adet var. '
                  'Backorder ayrı bir kayıt değildir — sevk edilince '
                  'kendiliğinden kapanır.',
                  renk: s.uyari),
            ],
          ]),
        ),
      ],
    );
  }
}

class _Kalem extends StatelessWidget {
  const _Kalem({required this.k});
  final SiparisKalemi k;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return KalemSatiri(
      ad: k.ad,
      altBilgi: [
        ?k.yayinevi,
        '${Fmt.adet(k.adet)} × ${Fmt.para(k.birimFiyat)}',
        if (k.iskontoOrani > 0) Fmt.yuzde(k.iskontoOrani),
      ].join(' · '),
      // H-3 · backorder türetilmiş sayıdır, ayrı kayıt değil.
      durumMetni: k.backorder > 0
          ? '${Fmt.adet(k.backorder)} adet bekliyor'
          : (k.sevkEdilen > 0 ? 'Sevk edildi' : null),
      durumRengi: k.backorder > 0 ? s.uyari : s.basarili,
      adet: '${Fmt.adet(k.adet)} adet',
      tutar: Fmt.para(k.satirTutari),
    );
  }
}

class _Eylemler extends StatelessWidget {
  const _Eylemler({required this.d, required this.hata,
                   required this.onDurum, required this.onTeslim});
  final SiparisDetay d;
  final String? hata;
  final Future<void> Function(String) onDurum;
  final VoidCallback onTeslim;

  @override
  Widget build(BuildContext context) {
    // TEK birincil eylem: akışta bir sonraki adım ne ise o. Dört düğmeyi
    // yan yana dizmek kullanıcıya karar verdirmek demek; sıra zaten belli.
    final (Widget? asil, String? not) = switch (d.durum) {
      'olusturuldu' => (
          FilledButton.icon(
            key: K.siparisHazirla,
            onPressed: () => onDurum('hazirlaniyor'),
            icon: const Icon(Icons.inventory_2_outlined, size: 16),
            label: const Text('Hazırlamaya başla'),
          ),
          null,
        ),
      'hazirlaniyor' => (
          FilledButton.icon(
            key: K.siparisHazir,
            onPressed: () => onDurum('hazir'),
            icon: const Icon(Icons.check, size: 16),
            label: const Text('Hazırlığı bitir'),
          ),
          null,
        ),
      'hazir' => (
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                key: K.siparisSevk,
                onPressed: () => onDurum('sevk_edildi'),
                icon: const Icon(Icons.local_shipping_outlined, size: 16),
                label: const Text('Sevk edildi'),
              ),
            ),
            if (d.sevkEdilebilir && d.toplamBackorder > 0) ...[
              const SizedBox(width: T.s3),
              Expanded(
                child: FilledButton.icon(
                  key: K.siparisTeslimEt,
                  onPressed: onTeslim,
                  icon: const Icon(Icons.assignment_turned_in_outlined,
                      size: 16),
                  label: const Text('Teslim et'),
                ),
              ),
            ],
          ]),
          'Teslimat kaydedilince borç doğar',
        ),
      _ when d.sevkEdilebilir && d.toplamBackorder > 0 => (
          FilledButton.icon(
            key: K.siparisTeslimEt,
            onPressed: onTeslim,
            icon: const Icon(Icons.assignment_turned_in_outlined, size: 16),
            label: const Text('Teslim et'),
          ),
          'Teslimat kaydedilince borç doğar',
        ),
      _ => (null, null),
    };

    if (asil == null && hata == null) return const SizedBox.shrink();

    return EylemSeridi(
      altMetin: not,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (hata != null) Bildirim(hata!, tip: BildirimTip.hata),
        if (asil != null) SizedBox(width: double.infinity, child: asil),
      ]),
    );
  }
}
