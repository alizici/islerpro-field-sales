import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/test_keys.dart';
import '../../../data/repositories/katalog_repository.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/widgets/diyalog.dart';
import '../../../shared/widgets/form_kabuk.dart';
import 'urun_fiyat_diyalogu.dart';

/// K24 · Barkod benzersizdir. Çakışırsa yeni kayıt AÇILMAZ — mevcut ürün
/// gösterilir ve doğrudan fiyat katmanına geçilir. Mükerrer ürün, mükerrer
/// kurum kadar pahalıdır: iki kayıt arasında stok ve borç bölünür.
class UrunEkleDiyalogu extends ConsumerStatefulWidget {
  const UrunEkleDiyalogu({required this.storeId, super.key});
  final String storeId;

  @override
  ConsumerState<UrunEkleDiyalogu> createState() => _UrunEkleDiyaloguState();
}

class _UrunEkleDiyaloguState extends ConsumerState<UrunEkleDiyalogu> {
  final _ad = TextEditingController();
  final _barkod = TextEditingController();
  final _yayinevi = TextEditingController();
  final _etiket = TextEditingController();
  String _katalog = 'kitap';
  bool _kaydediyor = false;
  String? _hata;
  UrunOzet? _cakisan;

  @override
  void initState() {
    super.initState();
    _ad.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    for (final c in [_ad, _barkod, _yayinevi, _etiket]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Diyalog(
      baslik: 'Ürün ekle',
      // K15 · kitap ve deneme aynı katalogda; ayrım `katalog` alanıdır.
      altBaslik: 'Kitap ve deneme aynı katalogda durur',
      hata: _hata,
      mesgul: _kaydediyor,
      onayEtiketi: 'Ekle',
      onayKey: K.urunEkleKaydet,
      onOnay: _ad.text.trim().isEmpty ? null : _kaydet,
      children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'kitap', label: Text('Kitap')),
            ButtonSegment(value: 'deneme', label: Text('Deneme')),
          ],
          selected: {_katalog},
          onSelectionChanged: (v) => setState(() => _katalog = v.first),
        ),
        TextField(
          key: K.urunEkleAd,
          controller: _ad,
          onChanged: (_) => setState(() {}),
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Ürün adı'),
        ),
        TextField(
          key: K.urunEkleBarkod,
          controller: _barkod,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
              labelText: 'Barkod (ISBN)',
              helperText: 'Benzersizdir — aynı barkod ikinci kez eklenemez'),
        ),
        TextField(
          key: K.urunEkleYayinevi,
          controller: _yayinevi,
          decoration: const InputDecoration(
              labelText: 'Yayınevi',
              helperText: 'Yoksa açılır; yazım farkları aynı sayılır'),
        ),
        ParaAlani(
          alanKey: K.urunEkleEtiketFiyat,
          controller: _etiket,
          etiket: 'Etiket fiyatı',
          yardim: 'Yayınevi listesi — hesaba girmez, satış fiyatı ayrı',
        ),
        // K24 · barkod çakıştı: yeni kayıt açmak yerine kullanıcıya YOL
        // gösterilir. "Zaten var" demek yeterli değil.
        if (_cakisan != null) ...[
          Bildirim(
              'Bu barkod katalogda zaten var: ${_cakisan!.ad}. '
              'Yeni kayıt açmak yerine bu ürünün dükkan fiyatını '
              'düzenleyebilirsin.',
              tip: BildirimTip.uyari),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              onPressed: () async {
                final u = _cakisan!;
                Navigator.pop(context, false);
                await showDialog<bool>(
                  context: context,
                  builder: (_) => UrunFiyatDiyalogu(urun: u),
                );
              },
              icon: const Icon(Icons.price_change_outlined, size: 16),
              label: const Text('Mevcut ürünü fiyatlandır'),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _kaydet() async {
    setState(() { _kaydediyor = true; _hata = null; _cakisan = null; });
    final repo = ref.read(katalogRepositoryProvider);
    try {
      final sonuc = await repo.urunEkle(
        storeId: widget.storeId,
        ad: _ad.text.trim(),
        katalog: _katalog,
        barkod: _barkod.text.trim().isEmpty ? null : _barkod.text.trim(),
        yayinevi: _yayinevi.text.trim().isEmpty ? null : _yayinevi.text.trim(),
        etiketFiyat: Fmt.sayiOku(_etiket.text),
      );
      if (!mounted) return;
      if (sonuc.yeni) {
        Navigator.pop(context, true);
        return;
      }
      // K24 · barkod çakıştı: mevcut ürünü getir, kullanıcıya yolu göster.
      final mevcut = await repo.barkodla(widget.storeId, _barkod.text.trim());
      if (!mounted) return;
      setState(() { _kaydediyor = false; _cakisan = mevcut; });
    } catch (e) {
      if (mounted) setState(() { _kaydediyor = false; _hata = e.toString(); });
    }
  }

}
