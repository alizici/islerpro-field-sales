import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session.dart';
import '../../../core/test_keys.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/local/yerel_saglayici.dart';
import '../../../data/repositories/katalog_repository.dart';
import '../../../data/repositories/talep_repository.dart';
import '../../../data/services/saha_kuyrugu.dart';
import '../../../data/services/yerel_katalog.dart';
import '../../../data/services/yerel_referans.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/widgets/cam.dart';
import '../../../shared/widgets/liste.dart';
import '../../../shared/widgets/dokunus.dart';
import '../../../shared/widgets/bolum.dart';
import '../../../shared/widgets/parcalar.dart';
import '../../../shared/widgets/satir.dart';
import '../../../shared/widgets/form_kabuk.dart';
import '../../../shared/widgets/yerel_uyari.dart';

/// Muhatap listesi. Sunucuya ulaşılamazsa CİHAZDAKİ kopyadan (K43).
///
/// Bu yol olmadan çevrimdışı katalog aramasının bir kıymeti yoktu: ürün
/// bulunuyor ama muhatap seçilemediği için talep yine açılamıyordu.
typedef MuhatapSonucu = (List<Muhatap> liste, bool yerel);

final muhataplarProvider =
    FutureProvider.autoDispose<MuhatapSonucu>((ref) async {
  try {
    return (await ref.watch(talepRepositoryProvider).muhataplar(), false);
  } catch (e) {
    if (!sunucuyaUlasilamadi(e)) rethrow;
    final store = ref.watch(sessionProvider)?.storeId;
    if (store == null) rethrow;
    final yerel = await ref.watch(yerelReferansProvider).muhataplar(store);
    if (yerel.isEmpty) rethrow;
    return (yerel, true);
  }
});

/// Ürün arama. Sunucuya ulaşılamazsa CİHAZDAKİ kopyadan aranır (K43):
/// okulda sinyal yokken talep girilebilmesi bu modülün varlık sebebi.
/// İkinci alan "sonuçlar yerelden geldi mi" — kullanıcı fiyatın ne kadar
/// taze olduğunu bilmeli.
typedef UrunSonucu = (List<UrunOzet> liste, bool yerel);

final _urunAramaProvider = FutureProvider.autoDispose
    .family<UrunSonucu, (String q, String storeId)>((ref, a) async {
  if (a.$1.trim().length < 2) return (const <UrunOzet>[], false);
  try {
    final l = await ref.watch(katalogRepositoryProvider)
        .ara(storeId: a.$2, q: a.$1, fiyatDurumu: 'fiyatli', limit: 15);
    return (l, false);
  } catch (e) {
    if (!sunucuyaUlasilamadi(e)) rethrow;
    final yerel = await ref.watch(yerelKatalogProvider).ara(a.$1);
    if (yerel.isEmpty) rethrow;   // yerel kopya da yoksa hatayı gizleme
    return (yerel, true);
  }
});

class _Kalem {
  _Kalem({required this.urun, required this.adet});
  final UrunOzet urun;
  int adet;
  AdetOnerisi? oneri;
}

/// K36 · Kalemler YALNIZCA katalogdan seçilir; serbest metin yoktur.
/// Katalogda olmayan ürün: pazarlamacı önce katalogа ekler, sonra talebi açar.
class TalepOlusturEkrani extends ConsumerStatefulWidget {
  const TalepOlusturEkrani({super.key});
  @override
  ConsumerState<TalepOlusturEkrani> createState() => _TalepOlusturEkraniState();
}

class _TalepOlusturEkraniState extends ConsumerState<TalepOlusturEkrani> {
  final _ara = TextEditingController();
  final _not = TextEditingController();
  final _kalemler = <_Kalem>[];
  Muhatap? _muhatap;
  Timer? _gecikme;
  String _q = '';
  bool _kaydediyor = false;
  String? _hata;

  @override
  void dispose() {
    _gecikme?.cancel();
    _ara.dispose();
    _not.dispose();
    super.dispose();
  }

  void _araDegisti(String v) {
    _gecikme?.cancel();
    _gecikme = Timer(const Duration(milliseconds: 300),
        () { if (mounted) setState(() => _q = v); });
    setState(() {});
  }

  Future<void> _ekle(UrunOzet u) async {
    if (_kalemler.any((k) => k.urun.id == u.id)) return;
    final kalem = _Kalem(urun: u, adet: 1);
    setState(() {
      _kalemler.add(kalem);
      _ara.clear();
      _q = '';
    });
    // K22 · adet önerisi dört kademeli zincirden gelir; tıkanmaz.
    if (_muhatap != null) {
      final o = await ref.read(talepRepositoryProvider).adetOnerisi(
          cariId: _muhatap!.id, urunId: u.id,
          periodId: ref.read(sessionProvider)?.periodId);
      if (!mounted) return;
      setState(() {
        kalem.oneri = o;
        if (o.var_) kalem.adet = o.adet!;
      });
    }
  }

  bool get _gecerli =>
      _muhatap != null && _kalemler.isNotEmpty &&
      _kalemler.every((k) => k.adet > 0) && !_kaydediyor;

  /// YAKLAŞIK tutar: gerçek iskonto sunucuda çözülür (K25) ve kademe,
  /// kural, sözleşme sırasıyla değişebilir. Yine de sıfırdan iyidir —
  /// "üç kalem gönderiyorum" demek kaç lira olduğunu söylemiyor.
  double get _yaklasikTutar => _kalemler.fold<double>(
      0,
      (a, k) =>
          a + (k.urun.satisFiyat ?? 0) * (1 - k.urun.varsayilanIskonto) *
              k.adet);

  @override
  Widget build(BuildContext context) {
    final muhataplar = ref.watch(muhataplarProvider);
    final store = ref.watch(sessionProvider)?.storeId;
    final sonuclar = store == null
        ? const AsyncValue<UrunSonucu>.data((<UrunOzet>[], false))
        : ref.watch(_urunAramaProvider((_q, store)));

    return CamSayfa(
      baslik: 'Yeni talep',
      // Gönder düğmesi uzun bir listenin dibinde kalıyordu: kullanıcı kalem
      // ekledikçe düğme aşağı kaçıyor, "şimdi ne yapacağım" diye kaydırmaya
      // devam ediyordu.
      altSerit: EylemSeridi(
        altMetin: _kalemler.isEmpty
            ? 'Katalogdan en az bir kalem seç'
            : 'Yaklaşık ${Fmt.para(_yaklasikTutar)} · '
                'kesin iskonto onaydan sonra belli olur',
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_hata != null) Bildirim(_hata!, tip: BildirimTip.hata),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: K.talepGonder,
              onPressed: _gecerli ? _gonder : null,
              icon: const Icon(Icons.send, size: 18),
              label: Text(_kaydediyor
                  ? 'Gönderiliyor…'
                  : 'Talebi gönder (${Fmt.adet(_kalemler.length)} kalem)'),
            ),
          ),
        ]),
      ),
      cocuklar: [
          // ── Muhatap (K5 · K19) ──────────────────────────────────────
          Bolum(
            key: K.talepMuhatap,
            baslik: 'Muhatap',
            altBaslik: 'Talep hangi cariye açılıyor — okul mu, öğretmen mi',
            child: muhataplar.when(
              loading: () => const Padding(
                  padding: EdgeInsets.all(T.s5),
                  child: Center(child: Bekleme(boy: 20))),
              error: (e, _) => Padding(
                  padding: const EdgeInsets.all(T.s4),
                  child: Bildirim(e.toString(), tip: BildirimTip.hata)),
              data: (sonuc) {
                final liste = sonuc.$1;
                if (liste.isEmpty) {
                  return const BosDurum('Talep açabileceğin bir cari yok',
                      ikon: Icons.account_balance_wallet_outlined,
                      aciklama: 'Talep bir CARİ adına açılır; portföyünde '
                          'cari yoksa açılacak talep de yok.');
                }
                return Column(children: [
                  if (sonuc.$2)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(T.s4, T.s3, T.s4, 0),
                      child: YerelKopyaUyarisi(
                          ek: 'Yalnızca aktif portföyün listeleniyor.'),
                    ),
                  RadioGroup<String>(
                    groupValue: _muhatap?.id,
                    onChanged: (v) => setState(() =>
                        _muhatap = liste.firstWhere((x) => x.id == v)),
                    child: Column(children: [
                      for (final m in liste)
                        RadioListTile<String>(
                          value: m.id,
                          dense: true,
                          title: Text(m.unvan),
                          subtitle: Text([
                            m.kurumsal ? 'Kurumsal cari' : 'Öğretmen carisi',
                            if (m.altBilgi.isNotEmpty) m.altBilgi,
                          ].join(' · ')),
                        ),
                    ]),
                  ),
                ]);
              },
            ),
          ),
          const SizedBox(height: T.s3),

          // ── Ürün seçimi (K36) ───────────────────────────────────────
          Bolum(
            baslik: 'Kalemler',
            altBaslik: 'Yalnızca katalogdan seçilir — serbest metin yoktur',
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.all(T.s4),
                child: TextField(
                  key: K.talepUrunAra,
                  controller: _ara,
                  onChanged: _araDegisti,
                  decoration: const InputDecoration(
                    hintText: 'Ürün adı veya barkod…',
                    prefixIcon: Icon(Icons.search, size: 18),
                    helperText: 'Fiyatı olmayan ürün siparişe dönüşemez, '
                        'bu yüzden listelenmez',
                  ),
                ),
              ),
              ...sonuclar.maybeWhen(
                data: (r) => [
                  if (r.$2)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(T.s4, 0, T.s4, T.s2),
                      child: Bildirim(
                          'Çevrimdışı katalogdan arandı — fiyatlar son '
                          'senkrondaki hâliyle gösteriliyor.',
                          tip: BildirimTip.uyari),
                    ),
                  for (final u in r.$1.take(8))
                    KayitSatiri(
                      baslik: u.ad,
                      altBilgi: u.altBilgi,
                      ikon: u.deneme
                          ? Icons.assignment_outlined
                          : Icons.menu_book_outlined,
                      deger: Fmt.para(u.satisFiyat),
                      onTap: () => _ekle(u),
                    ),
                ],
                orElse: () => const <Widget>[],
              ),
              if (_kalemler.isEmpty)
                const BosDurum('Henüz kalem eklenmedi',
                    ikon: Icons.playlist_add,
                    aciklama: 'Yukarıdan ürün ara ve dokun — mevcut bilgisi '
                        'varsa adet kendiliğinden önerilir (K22).')
              else
                for (final k in _kalemler) _KalemSatiri(
                  kalem: k,
                  onAdet: (v) => setState(() => k.adet = v),
                  onSil: () => setState(() => _kalemler.remove(k)),
                ),
            ]),
          ),
          const SizedBox(height: T.s3),

          TextField(
            key: K.talepNot,
            controller: _not,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Not (isteğe bağlı)'),
          ),
          const SonBosluk(),
      ],
    );
  }

  Future<void> _gonder() async {
    setState(() { _kaydediyor = true; _hata = null; });
    final kuyruk = ref.read(sahaKuyruguProvider);
    final not = _not.text.trim().isEmpty ? null : _not.text.trim();
    final ck = SahaKuyrugu.anahtar('tl');
    final kalemler = [
      for (final k in _kalemler) (urunId: k.urun.id, adet: k.adet),
    ];
    try {
      final r = await kuyruk.dene(
        () => ref.read(talepRepositoryProvider).olustur(
              cariId: _muhatap!.id,
              kalemler: kalemler,
              notMetni: not,
              clientKey: ck,
            ),
        fn: 'create_request',
        args: {
          'account_id': _muhatap!.id,
          'not_metni': not,
          'gonder': true,
          'client_key': ck,
          'items': [
            for (final k in kalemler) {'product_id': k.urunId, 'adet': k.adet},
          ],
        },
        ozet: '${_muhatap!.unvan} · '
            '${Fmt.adet(kalemler.length)} kalem talep',
      );
      if (!mounted) return;
      Navigator.pop(context, true);
      if (r == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Talep kuyruğa alındı — çevrimdışı; '
                'senkronda gönderilecek')));
      }
    } catch (e) {
      if (mounted) setState(() { _kaydediyor = false; _hata = e.toString(); });
    }
  }
}

class _KalemSatiri extends StatelessWidget {
  const _KalemSatiri({required this.kalem, required this.onAdet,
                      required this.onSil});
  final _Kalem kalem;
  final void Function(int) onAdet;
  final VoidCallback onSil;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final tutar = (kalem.urun.satisFiyat ?? 0) *
        (1 - kalem.urun.varsayilanIskonto) * kalem.adet;

    return KayitSatiri(
      baslik: kalem.urun.ad,
      // K22 · önerinin NEREDEN geldiği yazılı: "elle" ile "geçen dönem"
      // aynı sayı olsa bile aynı güvenilirlikte değil.
      altBilgi: [
        kalem.oneri?.etiket ?? 'elle girildi',
        '≈ ${Fmt.para(tutar)}',
      ].join(' · '),
      ikon: kalem.urun.deneme
          ? Icons.assignment_outlined
          : Icons.menu_book_outlined,
      durumRengi: kalem.oneri?.etiket != null ? s.bilgi : s.onSurfaceVariant,
      sondaki: Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 74,
          child: TextFormField(
            initialValue: '${kalem.adet}',
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textAlign: TextAlign.end,
            decoration:
                const InputDecoration(isDense: true, suffixText: 'ad'),
            onChanged: (v) => onAdet(int.tryParse(v) ?? 0),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close, size: 16),
          onPressed: onSil,
        ),
      ]),
    );
  }
}
