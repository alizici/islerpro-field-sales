import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session.dart';
import '../../../core/test_keys.dart';
import '../../notifications/presentation/bildirimler.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/repositories/katalog_repository.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/dokunus.dart';
import '../../../shared/widgets/bolum.dart';
import '../../../shared/widgets/cam.dart';
import '../../../shared/widgets/liste.dart';
import '../../../shared/widgets/mono.dart';
import '../../../shared/widgets/parcalar.dart';
import '../../../shared/widgets/satir.dart';
import 'urun_ekle_diyalogu.dart';
import 'urun_fiyat_diyalogu.dart';

const _sayfa = 50;

class KatalogFiltre {
  const KatalogFiltre({this.q, this.katalog, this.publisherId, this.fiyatDurumu});
  final String? q, katalog, publisherId, fiyatDurumu;

  KatalogFiltre kopya({
    Object? q = _yok, Object? katalog = _yok,
    Object? publisherId = _yok, Object? fiyatDurumu = _yok,
  }) =>
      KatalogFiltre(
        q: q == _yok ? this.q : q as String?,
        katalog: katalog == _yok ? this.katalog : katalog as String?,
        publisherId: publisherId == _yok ? this.publisherId : publisherId as String?,
        fiyatDurumu: fiyatDurumu == _yok ? this.fiyatDurumu : fiyatDurumu as String?,
      );

  static const _yok = Object();
}

class KatalogFiltreNotifier extends Notifier<KatalogFiltre> {
  @override
  KatalogFiltre build() => const KatalogFiltre();
  void ayarla(KatalogFiltre f) => state = f;
}

final katalogFiltreProvider =
    NotifierProvider<KatalogFiltreNotifier, KatalogFiltre>(
        KatalogFiltreNotifier.new, isAutoDispose: true);

/// Sonsuz kaydırma: 24.632 ürün tek seferde çekilemez, sayfa sayfa gelir.
/// Süzgeç değişince build() yeniden koşar ve liste sıfırlanır.
class KatalogListesi extends AsyncNotifier<List<UrunOzet>> {
  bool _bitti = false;
  bool _yukleniyor = false;

  bool get bitti => _bitti;

  @override
  Future<List<UrunOzet>> build() async {
    final f = ref.watch(katalogFiltreProvider);
    final store = ref.watch(sessionProvider)?.storeId;
    if (store == null) return const [];
    _bitti = false;
    final ilk = await ref.read(katalogRepositoryProvider).ara(
          storeId: store, q: f.q, katalog: f.katalog,
          publisherId: f.publisherId, fiyatDurumu: f.fiyatDurumu,
          limit: _sayfa,
        );
    _bitti = ilk.length < _sayfa;
    return ilk;
  }

  Future<void> dahaYukle() async {
    if (_bitti || _yukleniyor) return;
    final mevcut = state.value;
    if (mevcut == null) return;
    final f = ref.read(katalogFiltreProvider);
    final store = ref.read(sessionProvider)?.storeId;
    if (store == null) return;

    _yukleniyor = true;
    try {
      final sonraki = await ref.read(katalogRepositoryProvider).ara(
            storeId: store, q: f.q, katalog: f.katalog,
            publisherId: f.publisherId, fiyatDurumu: f.fiyatDurumu,
            limit: _sayfa, offset: mevcut.length,
          );
      _bitti = sonraki.length < _sayfa;
      state = AsyncData([...mevcut, ...sonraki]);
    } finally {
      _yukleniyor = false;
    }
  }
}

final katalogListesiProvider =
    AsyncNotifierProvider<KatalogListesi, List<UrunOzet>>(
        KatalogListesi.new, isAutoDispose: true);

final katalogSayimProvider = FutureProvider.autoDispose((ref) {
  final f = ref.watch(katalogFiltreProvider);
  final store = ref.watch(sessionProvider)?.storeId;
  if (store == null) return Future.value(0);
  return ref.watch(katalogRepositoryProvider).say(
        storeId: store, q: f.q, katalog: f.katalog,
        publisherId: f.publisherId, fiyatDurumu: f.fiyatDurumu,
      );
});

final yayinevleriProvider = FutureProvider.autoDispose((ref) {
  final store = ref.watch(sessionProvider)?.storeId;
  return ref.watch(katalogRepositoryProvider).yayinevleri(storeId: store);
});

/// K15 · Kitap ve deneme aynı katalogda; ayrım `katalog` alanıdır.
/// K12 · Fiyat/iskonto/stok satırın sağında — dükkana özel katman.
class KatalogEkrani extends ConsumerStatefulWidget {
  const KatalogEkrani({super.key});
  @override
  ConsumerState<KatalogEkrani> createState() => _KatalogEkraniState();
}

class _KatalogEkraniState extends ConsumerState<KatalogEkrani> {
  final _arama = TextEditingController();
  final _kaydirma = ScrollController();
  Timer? _gecikme;

  @override
  void initState() {
    super.initState();
    _kaydirma.addListener(() {
      if (_kaydirma.position.pixels >=
          _kaydirma.position.maxScrollExtent - 400) {
        ref.read(katalogListesiProvider.notifier).dahaYukle();
      }
    });
  }

  @override
  void dispose() {
    _gecikme?.cancel();
    _arama.dispose();
    _kaydirma.dispose();
    super.dispose();
  }

  /// Her tuşta 24 bin satırı taramak sunucuyu boğar — 350 ms bekle.
  void _ara(String v) {
    _gecikme?.cancel();
    _gecikme = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      final f = ref.read(katalogFiltreProvider);
      ref.read(katalogFiltreProvider.notifier)
          .ayarla(f.kopya(q: v.trim().isEmpty ? null : v.trim()));
    });
    setState(() {});
  }

  /// Ürün ekleme — başlık çubuğundan da, boş ekrandan da.
  Future<void> _urunEkle(String storeId) async {
    final eklendi = await showDialog<bool>(
      context: context,
      builder: (_) => UrunEkleDiyalogu(storeId: storeId),
    );
    if (eklendi == true) ref.invalidate(katalogListesiProvider);
  }

  @override
  Widget build(BuildContext context) {
    final liste = ref.watch(katalogListesiProvider);
    final filtre = ref.watch(katalogFiltreProvider);
    final sayim = ref.watch(katalogSayimProvider);
    final oturum = ref.watch(sessionProvider);

    return CamSayfa(
      baslik: 'Katalog',
      denetleyici: _kaydirma,
      eylemler: [
          TextButton.icon(
            key: K.katalogUrunEkle,
            onPressed: oturum?.storeId == null
                ? null
                : () => _urunEkle(oturum!.storeId!),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Ürün ekle'),
          ),
        const BildirimZili(),
        const SizedBox(width: T.s2),
      ],
      slivers: [
        ListeGovdesi<UrunOzet>(
          veri: liste,
          listeKey: K.katalogListesi,
          iskeletSatir: 8,
          ust: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: T.s2),
          child: TextField(
            key: K.katalogArama,
            controller: _arama,
            onChanged: _ara,
            decoration: InputDecoration(
              hintText: 'Ürün adı, barkod veya ürün kodu…',
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _arama.text.isEmpty ? null : IconButton(
                icon: const Icon(Icons.clear, size: 16),
                onPressed: () { _arama.clear(); _ara(''); },
              ),
            ),
          ),
        ),
        _Filtreler(filtre: filtre),
        _Ozet(sayim: sayim, filtre: filtre),
          ]),
          bos: BosDurum(
            filtre.fiyatDurumu == 'fiyatsiz'
                ? 'Fiyatsız ürün yok'
                : 'Eşleşen ürün yok',
            ikon: Icons.menu_book_outlined,
            aciklama: filtre.fiyatDurumu == 'fiyatsiz'
                ? 'Bütün ürünlerin fiyatı girilmiş — hepsi siparişe açık.'
                : 'Katalog, satılabilecek her şeyi tutar: kitaplar ve '
                    'denemeler aynı yerde. Fiyatı girilmemiş bir ürün '
                    'siparişe açılamaz.',
            eylem: oturum?.storeId == null
                ? null
                : FilledButton.icon(
                    onPressed: () => _urunEkle(oturum!.storeId!),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Ürün ekle'),
                  ),
          ),
          son: _Kuyruk(sayi: liste.value?.length ?? 0),
          satir: (_, u, _) => _UrunSatiri(u: u),
        ),
      ],
    );
  }
}

class _Filtreler extends ConsumerWidget {
  const _Filtreler({required this.filtre});
  final KatalogFiltre filtre;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final yayinevleri = ref.watch(yayinevleriProvider);
    void ayarla(KatalogFiltre f) =>
        ref.read(katalogFiltreProvider.notifier).ayarla(f);

    return SuzgecSeridi(cipler: [
      // K15 · kitap ve deneme aynı katalogda; ayrım `katalog` alanı.
      SuzgecCipi(
        key: K.katalogFiltreKitap,
        etiket: 'Kitap',
        secili: filtre.katalog == 'kitap',
        onTap: () => ayarla(filtre.kopya(
            katalog: filtre.katalog == 'kitap' ? null : 'kitap')),
      ),
      SuzgecCipi(
        key: K.katalogFiltreDeneme,
        etiket: 'Deneme',
        secili: filtre.katalog == 'deneme',
        onTap: () => ayarla(filtre.kopya(
            katalog: filtre.katalog == 'deneme' ? null : 'deneme')),
      ),
      // Göçün asıl sorusu: hangi ürünün fiyatı hâlâ girilmedi?
      SuzgecCipi(
        key: K.katalogFiltreFiyatsiz,
        etiket: 'Fiyatı yok',
        renk: Theme.of(context).colorScheme.error,
        secili: filtre.fiyatDurumu == 'fiyatsiz',
        onTap: () => ayarla(filtre.kopya(
            fiyatDurumu: filtre.fiyatDurumu == 'fiyatsiz' ? null : 'fiyatsiz')),
      ),
      SuzgecCipi(
        etiket: 'Fiyatlı',
        secili: filtre.fiyatDurumu == 'fiyatli',
        onTap: () => ayarla(filtre.kopya(
            fiyatDurumu: filtre.fiyatDurumu == 'fiyatli' ? null : 'fiyatli')),
      ),
      ...yayinevleri.maybeWhen(
        data: (liste) => [
          for (final y in liste.take(30))
            SuzgecCipi(
              etiket: y.ad,
              sayi: y.urunSayisi,
              secili: filtre.publisherId == y.id,
              onTap: () => ayarla(filtre.kopya(
                  publisherId: filtre.publisherId == y.id ? null : y.id)),
            ),
        ],
        orElse: () => const <Widget>[],
      ),
    ]);
  }
}

class _Ozet extends StatelessWidget {
  const _Ozet({required this.sayim, required this.filtre});
  final AsyncValue<int> sayim;
  final KatalogFiltre filtre;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final n = sayim.value;
    return SayacSeridi(
      n == null ? 'Sayılıyor…' : '${Fmt.adet(n)} ürün',
      sag: filtre.fiyatDurumu == 'fiyatsiz' && n != null && n > 0
          ? 'Bu ürünler siparişe açılamaz'
          : null,
      sagRengi: s.error,
    );
  }
}

class _Kuyruk extends ConsumerWidget {
  const _Kuyruk({required this.sayi});
  final int sayi;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bitti = ref.read(katalogListesiProvider.notifier).bitti;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: T.s4),
      child: Center(
        child: bitti
            ? MikroEtiket('$sayi ürün listelendi')
            : const Bekleme(boy: 18),
      ),
    );
  }
}

class _UrunSatiri extends ConsumerWidget {
  const _UrunSatiri({required this.u});
  final UrunOzet u;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = Theme.of(context).colorScheme;
    // K12 · fiyat/iskonto/stok dükkana özel katmandır; ürünün kendisi değil.
    // Fiyatsız ürün siparişe açılamaz — bu satırın en önemli olgusu.
    return KayitSatiri(
      key: K.urunSatiri(u.id),
      baslik: u.ad,
      altBilgi: [
        if (u.altBilgi.isNotEmpty) u.altBilgi else ?u.barkod,
        if (!u.fiyatsiz && u.varsayilanIskonto > 0)
          'varsayılan ${Fmt.yuzde(u.varsayilanIskonto)}',
        if (u.stokTakibi && u.stokAdedi != null)
          'stok ${Fmt.adet(u.stokAdedi)}',
      ].join(' · '),
      vurgu: u.fiyatsiz ? 'Fiyatı yok — siparişe açılamaz' : null,
      vurguRengi: s.error,
      ikon: u.deneme ? Icons.assignment_outlined : Icons.menu_book_outlined,
      durumRengi: u.fiyatsiz
          ? s.error
          : (u.deneme ? s.bilgi : null),
      deger: u.fiyatsiz ? null : Fmt.para(u.satisFiyat),
      onTap: () async {
        final ok = await showDialog<bool>(
          context: context,
          builder: (_) => UrunFiyatDiyalogu(urun: u),
        );
        if (ok == true) {
          ref.invalidate(katalogListesiProvider);
          ref.invalidate(katalogSayimProvider);
        }
      },
    );
  }
}
