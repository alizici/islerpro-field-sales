import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session.dart';
import '../../../core/test_keys.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/repositories/katalog_repository.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/widgets/diyalog.dart';
import '../../../shared/widgets/form_kabuk.dart';
import '../../../shared/widgets/mono.dart';
import 'baski_diyalogu.dart';

/// K12 · Dükkanın ticari katmanı. Ürün kimliği ortak, bu ekran dükkana özel.
/// K25 · Buradaki satış fiyatı iskontonun TABANIDIR; etiket fiyat sadece bilgi.
class UrunFiyatDiyalogu extends ConsumerStatefulWidget {
  const UrunFiyatDiyalogu({required this.urun, super.key});
  final UrunOzet urun;

  @override
  ConsumerState<UrunFiyatDiyalogu> createState() => _UrunFiyatDiyaloguState();
}

class _UrunFiyatDiyaloguState extends ConsumerState<UrunFiyatDiyalogu> {
  late final _satis = TextEditingController(
      text: Fmt.sayiYaz(widget.urun.satisFiyat));
  late final _alis = TextEditingController(
      text: Fmt.sayiYaz(widget.urun.alisFiyat));
  // Kullanıcı yüzde yazar (20), veritabanı oran tutar (0.20).
  late final _iskonto = TextEditingController(
      text: widget.urun.varsayilanIskonto == 0
          ? ''
          : Fmt.sayiYaz(widget.urun.varsayilanIskonto * 100,
              basamak: widget.urun.varsayilanIskonto * 100 % 1 == 0 ? 0 : 2));
  late bool _stokTakibi = widget.urun.stokTakibi;
  bool _kaydediyor = false;
  String? _hata;

  @override
  void initState() {
    super.initState();
    for (final c in [_satis, _alis, _iskonto]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_satis, _alis, _iskonto]) {
      c.dispose();
    }
    super.dispose();
  }

  double? get _satisDeger => Fmt.sayiOku(_satis.text);
  double? get _oranDeger {
    final y = Fmt.sayiOku(_iskonto.text);
    return y == null ? null : y / 100;
  }

  bool get _gecerli {
    final o = _oranDeger;
    if (o != null && (o < 0 || o >= 1)) return false;
    final f = _satisDeger;
    if (f != null && f < 0) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.urun;
    final oturum = ref.watch(sessionProvider);

    return Diyalog(
      baslik: u.ad,
      // K12 · fiyat ürünün değil DÜKKANIN katmanıdır.
      altBaslik: [
        u.deneme ? 'Deneme' : 'Kitap',
        ?u.yayinevi,
        ?u.barkod,
        if (u.ozel) 'İşletmeye özel',
      ].join(' · '),
      hata: _hata,
      mesgul: _kaydediyor,
      onayKey: K.fiyatKaydet,
      onOnay: (!_gecerli || oturum?.storeId == null)
          ? null
          : () => _kaydet(oturum!.storeId!),
      // K23 · Baskı ilişkisi buradan kurulur; addaki yıldan türetilmez.
      ikincilEylem: TextButton.icon(
        key: K.baskiAc,
        onPressed: _kaydediyor
            ? null
            : () async {
                final nav = Navigator.of(context);
                final eklendi = await showDialog<bool>(
                  context: context,
                  builder: (_) => BaskiDiyalogu(urun: u),
                );
                // Baskı eklendiyse katalog tazelensin diye üstteki diyalog
                // da kapanır.
                if (eklendi == true) nav.pop(true);
              },
        icon: const Icon(Icons.layers_outlined, size: 16),
        label: const Text('Baskılar'),
      ),
      children: [
        if (u.etiketFiyat != null)
          Bildirim(
            'Yayınevi etiket fiyatı ${Fmt.para(u.etiketFiyat)}. '
            'Bu sayı yalnızca referanstır — iskonto ve satır tutarı '
            'aşağıdaki satış fiyatından hesaplanır.',
            tip: BildirimTip.bilgi),
        Row(children: [
          Expanded(
            child: ParaAlani(
              alanKey: K.fiyatSatis,
              controller: _satis,
              etiket: 'Satış fiyatı',
              yardim: 'İskontonun tabanı',
            ),
          ),
          const SizedBox(width: T.s3),
          Expanded(
            child: ParaAlani(
              alanKey: K.fiyatAlis,
              controller: _alis,
              etiket: 'Alış fiyatı',
              yardim: 'Yalnızca kâr raporunda',
            ),
          ),
        ]),
        ParaAlani(
          alanKey: K.fiyatIskonto,
          controller: _iskonto,
          etiket: 'Varsayılan iskonto',
          birim: '%',
          yardim: 'Yalnızca hiçbir iskonto kuralı eşleşmezse kullanılır',
        ),
        SwitchListTile(
          key: K.fiyatStokTakibi,
          value: _stokTakibi,
          onChanged: (v) => setState(() => _stokTakibi = v),
          title: const Text('Stok takibi'),
          subtitle: const Text('Kapalıysa adet gösterilmez — stoğu başka '
              'yerde yönetilen ürün'),
          contentPadding: EdgeInsets.zero,
        ),
        if (_satisDeger != null)
          _Onizleme(fiyat: _satisDeger!, oran: _oranDeger ?? 0),
        if (!_gecerli)
          const Bildirim('İskonto %0 ile %100 arasında olmalı.',
              tip: BildirimTip.uyari),
      ],
    );
  }

  Future<void> _kaydet(String storeId) async {
    setState(() { _kaydediyor = true; _hata = null; });
    try {
      await ref.read(katalogRepositoryProvider).fiyatKaydet(
            storeId: storeId,
            productId: widget.urun.id,
            satisFiyat: _satisDeger,
            alisFiyat: Fmt.sayiOku(_alis.text),
            varsayilanIskonto: _oranDeger ?? 0,
            stokTakibi: _stokTakibi,
            aktif: true,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() { _kaydediyor = false; _hata = e.toString(); });
    }
  }
}

/// V6 · satis_fiyat × (1 − iskonto) × adet. Ekranda da aynı aritmetik görünsün
/// ki kullanıcı yüzdeyi oranla karıştırdığında anında fark etsin.
class _Onizleme extends StatelessWidget {
  const _Onizleme({required this.fiyat, required this.oran});
  final double fiyat, oran;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final birim = fiyat * (1 - oran);
    return Container(
      key: K.fiyatOnizleme,
      margin: const EdgeInsets.only(top: T.s3),
      padding: const EdgeInsets.all(T.s3),
      decoration: BoxDecoration(
        color: s.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(T.rKucuk),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const MikroEtiket('Satır önizlemesi'),
        const SizedBox(height: 4),
        // Dar ekranda taşmasın: sığmazsa alt satıra insin.
        Wrap(
          spacing: T.s2,
          runSpacing: T.s1,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Mono('${Fmt.para(fiyat)} × ${Fmt.yuzde(oran)}', size: 12),
            const Icon(Icons.arrow_forward, size: 13),
            Mono('${Fmt.para(birim)} / adet', size: 13, weight: FontWeight.w600),
          ],
        ),
        const SizedBox(height: 2),
        Text('10 adet → ${Fmt.para(double.parse((birim * 10).toStringAsFixed(2)))}',
            style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }
}
