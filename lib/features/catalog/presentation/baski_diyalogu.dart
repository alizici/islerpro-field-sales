import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session.dart';
import '../../../core/test_keys.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/repositories/katalog_repository.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/widgets/bolum.dart';
import '../../../shared/widgets/diyalog.dart';
import '../../../shared/widgets/form_kabuk.dart';
import '../../../shared/widgets/parcalar.dart';
import '../../../shared/widgets/satir.dart';
import '../../../shared/widgets/mono.dart';

final baskilarProvider = FutureProvider.autoDispose
    .family<List<Baski>, (String urunId, String storeId)>(
        (ref, a) => ref.watch(katalogRepositoryProvider)
            .baskilar(a.$1, a.$2));

/// K23 · Baskı, TAHMİN EDİLMEZ — insan söyler.
///
/// Ad içindeki yıl bir yazım alışkanlığıdır; ondan üretilen gruplama doğruluğu
/// garanti edilemeyecek bir tahmindir. Grup tam da doğru anda doğar: burada.
class BaskiDiyalogu extends ConsumerStatefulWidget {
  const BaskiDiyalogu({required this.urun, super.key});
  final UrunOzet urun;

  @override
  ConsumerState<BaskiDiyalogu> createState() => _BaskiDiyaloguState();
}

class _BaskiDiyaloguState extends ConsumerState<BaskiDiyalogu> {
  final _etiket = TextEditingController();
  final _barkod = TextEditingController();
  final _fiyat = TextEditingController();
  bool _arsivle = false;
  bool _kaydediyor = false;
  String? _hata;

  @override
  void initState() {
    super.initState();
    _etiket.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    for (final c in [_etiket, _barkod, _fiyat]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(sessionProvider)?.storeId;
    final grup = store == null
        ? const AsyncValue<List<Baski>>.data([])
        : ref.watch(baskilarProvider((widget.urun.id, store)));

    return Diyalog(
      baslik: 'Baskılar',
      altBaslik: widget.urun.ad,
      hata: _hata,
      mesgul: _kaydediyor,
      genislik: 480,
      vazgecEtiketi: 'Kapat',
      onayEtiketi: 'Baskı ekle',
      onayKey: K.baskiKaydet,
      onOnay: (_etiket.text.trim().isEmpty || store == null)
          ? null
          : () => _ekle(store),
      children: [
        grup.when(
          loading: () => const DiyalogYukleniyor(boy: 60),
          error: (e, _) => Bildirim(e.toString(), tip: BildirimTip.hata),
          data: (liste) => liste.isEmpty
              // K23 · baskı ilişkisi ELLE kurulur; addaki yıldan türetilmez.
              ? const KuralNotu(
                  'Bu ürün henüz bir baskı grubunda değil. Yeni baskı '
                  'eklediğinizde grup kendiliğinden oluşur ve bu ürün de '
                  'gruba alınır.')
              : _GrupListesi(liste: liste),
        ),
        const Divider(),
        const BolumBasligi('Yeni baskı ekle'),
        // K23 · barkod ve fiyat kopyalanmaz: her baskının kendi kimliği ve
        // kendi fiyatı var. Stok ve geçmiş satışlar eski baskıda kalır.
        const Bildirim(
          'Ad, yayınevi, sınıf ve ders kopyalanır. Barkod ve fiyat '
          'KOPYALANMAZ — her baskının kendi kimliği ve kendi fiyatı vardır. '
          'Stok, açık sipariş ve geçmiş satışlar eski baskıda kalır.',
          tip: BildirimTip.bilgi),
        TextField(
          key: K.baskiEtiket,
          controller: _etiket,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Baskı etiketi',
            hintText: '2026-27 · 3. Baskı',
            helperText: 'Zorunlu — bu baskıyı tanımlayan ifade',
          ),
        ),
        TextField(
          key: K.baskiBarkod,
          controller: _barkod,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Barkod (ISBN)',
            helperText:
                'Yeni baskının kendi barkodu — sonradan da girilebilir',
          ),
        ),
        ParaAlani(
          alanKey: K.baskiEtiketFiyat,
          controller: _fiyat,
          etiket: 'Etiket fiyatı',
          yardim: 'Yeni baskı fiyatı genelde farklıdır',
        ),
        CheckboxListTile(
          key: K.baskiArsivle,
          value: _arsivle,
          onChanged: (v) => setState(() => _arsivle = v ?? false),
          title: const Text('Eski baskıyı arşivle'),
          subtitle: Text(
              widget.urun.stokAdedi != null && widget.urun.stokAdedi! > 0
                  ? 'Elde ${Fmt.adet(widget.urun.stokAdedi)} adet var — '
                      'arşivlenemez, önce eritilmeli'
                  : 'Katalogda görünmez olur; kayıtlar durur'),
          contentPadding: EdgeInsets.zero,
        ),
      ],
    );
  }

  Future<void> _ekle(String storeId) async {
    setState(() { _kaydediyor = true; _hata = null; });
    try {
      await ref.read(katalogRepositoryProvider).baskiEkle(
            storeId: storeId,
            kaynakUrunId: widget.urun.id,
            baskiEtiketi: _etiket.text.trim(),
            barkod: _barkod.text.trim().isEmpty ? null : _barkod.text.trim(),
            etiketFiyat: Fmt.sayiOku(_fiyat.text),
            eskiyiArsivle: _arsivle,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() { _kaydediyor = false; _hata = e.toString(); });
    }
  }
}

class _GrupListesi extends StatelessWidget {
  const _GrupListesi({required this.liste});
  final List<Baski> liste;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Bolum(
      key: K.baskiListesi,
      baslik: '${liste.length} baskı',
      altBaslik: 'Güncel baskı = en yüksek sıradaki, tarihten değil',
      child: Column(children: [
        for (final b in liste)
          KayitSatiri(
            key: K.baskiSatiri(b.id),
            baslik: b.etiket,
            altBilgi: [
              ?b.barkod,
              if (b.satisFiyat != null) Fmt.para(b.satisFiyat),
              if (b.stokAdedi != null && b.stokAdedi! > 0)
                'stok ${Fmt.adet(b.stokAdedi)}',
            ].join(' · '),
            // K23 · güncel baskı EN YÜKSEK SIRADAKİDİR, tarihten değil.
            vurgu: switch (b) {
              _ when b.guncel => 'Güncel baskı',
              _ when b.arsivlendi => 'Arşivlendi',
              _ when b.secili => 'Bu üründe seçili',
              _ => null,
            },
            vurguRengi: b.guncel
                ? s.basarili
                : (b.arsivlendi ? s.onSurfaceVariant : s.bilgi),
            oncul: SizedBox(
              width: 26,
              child: Center(
                child: Mono('${b.baskiSirasi}',
                    size: 14,
                    weight: FontWeight.w600,
                    color: b.guncel ? s.primary : s.onSurfaceVariant),
              ),
            ),
            durumRengi: b.guncel ? s.basarili : s.onSurfaceVariant,
          ),
      ]),
    );
  }
}

/// K23 · Sipariş anında iki yönlü uyarı. Bazen doğru olan eski baskıyla
/// devam etmektir (stok eritmek), bazen yeni müfredat gerekir.
/// Karar kullanıcınındır; sistemin işi sessiz kalmamaktır.
class BaskiUyariSatiri extends StatelessWidget {
  const BaskiUyariSatiri({required this.uyari, this.onGuncelSec, super.key});
  final BaskiUyarisi uyari;
  final void Function(String urunId)? onGuncelSec;

  @override
  Widget build(BuildContext context) {
    if (!uyari.uyari || uyari.guncel == null) return const SizedBox.shrink();
    final g = uyari.guncel!;
    final s = uyari.secili;
    final renk = Theme.of(context).colorScheme;

    return Container(
      key: K.baskiUyari,
      padding: const EdgeInsets.all(T.s3),
      decoration: BoxDecoration(
        color: renk.uyariSoft,
        border: Border.all(color: renk.uyari.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(T.rKucuk),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Bu ürünün ${g.etiket} baskısı var'
            '${g.satisFiyat == null ? '' : ' (${Fmt.para(g.satisFiyat)})'}.',
            style: Theme.of(context).textTheme.bodyMedium),
        if (s != null)
          Text('Seçili: ${s.etiket} baskısı'
              '${s.satisFiyat == null ? '' : ' (${Fmt.para(s.satisFiyat)})'}'
              '${s.stokAdedi == null || s.stokAdedi == 0
                  ? '' : ' · elde ${Fmt.adet(s.stokAdedi)} adet'}',
              style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: T.s2),
        Wrap(spacing: T.s2, children: [
          FilledButton(
            onPressed: onGuncelSec == null ? null : () => onGuncelSec!(g.id),
            child: const Text('Güncele geç'),
          ),
          TextButton(
            onPressed: () {},
            child: const Text('Eski baskıyla devam'),
          ),
        ]),
      ]),
    );
  }
}
