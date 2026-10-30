import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session.dart';
import '../../../core/test_keys.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/repositories/siparis_repository.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/widgets/cam.dart';
import '../../../shared/widgets/bolum.dart';
import '../../../shared/widgets/liste.dart';
import '../../../shared/widgets/parcalar.dart';
import '../../../shared/widgets/satir.dart';
import '../../notifications/presentation/bildirimler.dart';
import 'siparis_detay_ekrani.dart';

class SiparisFiltreNotifier extends Notifier<bool> {
  @override
  bool build() => false;   // hazırlık kutusu açık mı
  void ayarla(bool v) => state = v;
}

final siparisFiltreProvider =
    NotifierProvider<SiparisFiltreNotifier, bool>(SiparisFiltreNotifier.new,
        isAutoDispose: true);

/// Yalnızca ekranda süzer — depoya gitmez. "Onay bekleyenler" ve "eksik sevk"
/// zaten çekilmiş listenin içinde; ikinci bir ağ turu istemez.
enum SiparisSuzgec { hepsi, onayBekleyen, eksikSevk }

class SiparisDurumNotifier extends Notifier<SiparisSuzgec> {
  @override
  SiparisSuzgec build() => SiparisSuzgec.hepsi;
  void ayarla(SiparisSuzgec v) =>
      state = state == v ? SiparisSuzgec.hepsi : v;
}

final siparisDurumProvider =
    NotifierProvider<SiparisDurumNotifier, SiparisSuzgec>(
        SiparisDurumNotifier.new, isAutoDispose: true);

final siparislerProvider = FutureProvider.autoDispose((ref) {
  final hazirlik = ref.watch(siparisFiltreProvider);
  final o = ref.watch(sessionProvider);
  return ref.watch(siparisRepositoryProvider).liste(
        storeId: o?.storeId, hazirlikKutusu: hazirlik, limit: 100);
});

/// K46 · Saha siparişi senkron olduğu anda dükkanın "Hazırlanacak Siparişler"
/// kutusuna düşer. Hazırlık bir İŞ AKIŞIDIR, stok muhasebesi değil (K45).
class SiparislerEkrani extends ConsumerStatefulWidget {
  const SiparislerEkrani({this.hazirlikKutusu = false, super.key});

  /// K46 · /hazirlik yolundan gelindiğinde kutu açık başlar.
  final bool hazirlikKutusu;

  @override
  ConsumerState<SiparislerEkrani> createState() => _SiparislerEkraniState();
}

class _SiparislerEkraniState extends ConsumerState<SiparislerEkrani> {
  @override
  void initState() {
    super.initState();
    if (widget.hazirlikKutusu) {
      Future.microtask(() =>
          ref.read(siparisFiltreProvider.notifier).ayarla(true));
    }
  }

  @override
  Widget build(BuildContext context) {
    final liste = ref.watch(siparislerProvider);
    final hazirlik = ref.watch(siparisFiltreProvider);
    final suzgec = ref.watch(siparisDurumProvider);
    final s = Theme.of(context).colorScheme;

    final hepsi = liste.value ?? const <SiparisOzet>[];
    final gorunen = switch (suzgec) {
      SiparisSuzgec.hepsi => hepsi,
      SiparisSuzgec.onayBekleyen =>
        hepsi.where((o) => o.onayBekliyor).toList(),
      SiparisSuzgec.eksikSevk => hepsi.where((o) => o.backorderVar).toList(),
    };
    final bekleyenAdet =
        hepsi.fold<int>(0, (a, o) => a + o.bekleyenAdet);

    return CamSayfa(
      baslik: widget.hazirlikKutusu ? 'Hazırlık' : 'Siparişler',
      eylemler: const [BildirimZili(), SizedBox(width: T.s2)],
      onYenile: () async => ref.invalidate(siparislerProvider),
      slivers: [
        ListeGovdesi<SiparisOzet>(
        veri: liste.esle((_) => gorunen),
        listeKey: K.siparisListesi,
        // Özet ve süzgeç listeyle BİRLİKTE kayar: telefonda dokuz satırlık
        // ekranın üçünü sabit başlığa vermek listeyi okunmaz yapıyor.
        ust: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            OzetSerit(
              etiket: hazirlik ? 'Hazırlanacak tutar' : 'Açık sipariş tutarı',
              deger: Fmt.para(gorunen.fold<double>(0, (a, o) => a + o.toplam)),
              altBilgi: '${Fmt.adet(gorunen.length)} sipariş',
              yanlar: [
                if (hepsi.any((o) => o.onayBekliyor))
                  ('Onay bekleyen',
                      '${hepsi.where((o) => o.onayBekliyor).length}', s.uyari),
                // H-3 · sevk edilmemiş adet ayrı kayıt değil, türetilmiş sayı.
                // Süzgeç çipiyle aynı adı taşımıyor: çip SİPARİŞ sayar,
                // burası ADET. Aynı etiket iki farklı sayıya konunca
                // "3 mü 560 mı" diye okunuyordu.
                if (bekleyenAdet > 0)
                  ('Sevk edilmeyen', '${Fmt.adet(bekleyenAdet)} adet', s.uyari),
              ],
            ),
            SuzgecSeridi(cipler: [
              SuzgecCipi(
                key: K.siparisHazirlikKutusu,
                etiket: 'Hazırlanacaklar',
                secili: hazirlik,
                onTap: () => ref
                    .read(siparisFiltreProvider.notifier)
                    .ayarla(!hazirlik),
              ),
              SuzgecCipi(
                etiket: 'Onay bekleyen',
                sayi: hepsi.where((o) => o.onayBekliyor).length,
                renk: s.uyari,
                secili: suzgec == SiparisSuzgec.onayBekleyen,
                onTap: () => ref
                    .read(siparisDurumProvider.notifier)
                    .ayarla(SiparisSuzgec.onayBekleyen),
              ),
              SuzgecCipi(
                etiket: 'Eksik sevk',
                sayi: hepsi.where((o) => o.backorderVar).length,
                renk: s.bilgi,
                secili: suzgec == SiparisSuzgec.eksikSevk,
                onTap: () => ref
                    .read(siparisDurumProvider.notifier)
                    .ayarla(SiparisSuzgec.eksikSevk),
              ),
            ]),
          ],
        ),
        bos: BosDurum(
          hazirlik ? 'Hazırlanacak sipariş yok' : 'Sipariş yok',
          ikon: Icons.receipt_long_outlined,
          aciklama: hazirlik
              ? 'Hazırlık kutusu, depoda toplanmayı bekleyen siparişleri '
                  'tutar. Sahadan gelen siparişler senkron olur olmaz buraya '
                  'düşer.'
              : 'Sipariş kendiliğinden açılmaz: onaylanan bir talepten doğar. '
                  'Talepler ekranından başla.',
        ),
        satir: (_, o, _) => _Satir(o: o),
        ),
      ],
    );
  }
}

/// Sipariş durumunun rengi — ekranın her yerinde aynı eşleme.
Color siparisRengi(ColorScheme s, String durum) => switch (durum) {
      'onay_bekliyor' => s.uyari,
      'hazirlaniyor' => s.bilgi,
      'hazir' => s.basarili,
      'sevk_edildi' => s.bilgi,
      'kismi_teslim' => s.uyari,
      'teslim_edildi' || 'kapandi' => s.basarili,
      'reddedildi' || 'iptal' => s.error,
      // `outline` fazla soluk: ikon karesi %10 saydamlıkta çizildiği için
      // "Oluşturuldu" satırlarının ikonu bomboş görünüyordu.
      _ => s.onSurfaceVariant,
    };

class _Satir extends ConsumerWidget {
  const _Satir({required this.o});
  final SiparisOzet o;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = Theme.of(context).colorScheme;
    final renk = siparisRengi(s, o.durum);

    // Durum HER SATIRDA yazılı ama iki ayrı yerde: sıradan durum alt bilgi
    // içinde sessizce, iş çıkaran durum ayrı renkli satırda. Aksi hâlde
    // "Hazırlanacaklar" süzgecinde on satır birden "Hazırlanıyor" diyor —
    // bilgi değil gürültü.
    final (String? vurgu, Color? vurguRenk) = switch (o) {
      _ when o.onayBekliyor => ('Onay bekliyor', s.uyari),
      _ when o.backorderVar =>
        ('${Fmt.adet(o.bekleyenAdet)} adet sevk edilmedi', s.uyari),
      _ when o.durum == 'reddedildi' || o.durum == 'iptal' =>
        (o.durumAdi, s.error),
      _ when o.durum == 'hazir' => ('Hazır — teslime bekliyor', s.basarili),
      _ => (null, null),
    };

    return KayitSatiri(
      key: K.siparisSatiri(o.id),
      baslik: o.unvan,
      altBilgi: [
        if (vurgu == null) o.durumAdi,
        '${Fmt.adet(o.kalemSayisi)} kalem',
        if (o.tip == 'konsinye') 'Konsinye',
        if (o.hazirlayan != null) o.hazirlayan!,
      ].join(' · '),
      vurgu: vurgu,
      vurguRengi: vurguRenk,
      ikon: o.tip == 'konsinye'
          ? Icons.assignment_return_outlined
          : Icons.receipt_long_outlined,
      durumRengi: renk,
      deger: Fmt.para(o.toplam),
      degerAlti: Fmt.tarih(o.createdAt),
      onTap: () async {
        final degisti = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
                builder: (_) => SiparisDetayEkrani(siparisId: o.id)));
        if (degisti == true) ref.invalidate(siparislerProvider);
      },
    );
  }
}
