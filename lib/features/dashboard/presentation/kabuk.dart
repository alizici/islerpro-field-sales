import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session.dart';
import '../../../data/repositories/siparis_repository.dart';
import '../../../core/router/app_router.dart';
import '../../../core/test_keys.dart';
import '../../../core/theme/breakpoints.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../shared/widgets/dokunus.dart';
import '../../../shared/widgets/mono.dart';
import '../../../shared/widgets/baglam.dart';
import '../../../shared/widgets/cam.dart';
import '../../../shared/widgets/gezinme.dart';
import '../../visits/presentation/ziyaret_cubugu.dart';

/// Tek kod tabanı, üç yerleşim (§6 Responsive strateji):
/// mobil → BottomNav · tablet → NavigationRail · masaüstü → kalıcı sidebar
/// Sekmelerde gösterilecek bekleyen iş sayıları: yol → sayı.
///
/// Panel'de duran bilgiyi çubuğa taşır. Kullanıcı Cariler ekranındayken üç
/// gecikmiş talebi olduğunu bilmiyordu; o bilgi tek bir ekrana hapsolmuştu.
///
/// Rozet YALNIZCA gelen kutusu benzeri hedeflerde: talep, onay, hazırlık.
/// "Portföysüz cari" de bir eksiklik ama süregelen bir durum, biriken bir
/// iş değil — sekmede sayı olarak göstermek onu "iki yeni şey var" diye
/// okuturdu.
///
/// Tek toplu sorgu (`panel` / `bugun`), sekme değişiminde tazelenir: bayat
/// bir rozet ("3 onay bekliyor" ama hepsi onaylanmış) rozetsizlikten kötüdür.
final gezinmeSayaclariProvider =
    FutureProvider.autoDispose<Map<String, int>>((ref) async {
  final o = ref.watch(sessionProvider);
  if (o?.storeId == null) return const {};
  final repo = ref.watch(siparisRepositoryProvider);
  try {
    switch (o!.aktifRol) {
      case AppRole.isletmeSahibi:
      case AppRole.dukkanMuduru:
        final p = await repo.panel(o.storeId!, periodId: o.periodId);
        return {
          '/talepler': p.bekleyenTalep,
          '/siparisler': p.onayBekleyenSiparis,
          '/hazirlik': p.hazirlanacakSiparis,
        };
      case AppRole.pazarlamaci:
        final b = await repo.bugun(o.storeId!, periodId: o.periodId);
        return {
          '/talepler': b.bekleyenTalep,
          // Hazır sipariş pazarlamacı için iş demek: teslim edilmeyi bekliyor.
          '/siparisler': b.hazirSiparis,
        };
      // Hazırlık ve öğretmen rolleri bu özetleri çağıramaz (RLS); rozet de
      // görmezler. Sayaç uğruna yetki genişletilmez.
      case AppRole.hazirlik:
      case AppRole.ogretmen:
      case AppRole.platformAdmin:
        return const {};
    }
  } catch (_) {
    // Sayaç ikincil bilgi: alınamazsa çubuk rozetsiz çizilir, gezinme
    // çalışmaya devam eder. Burada hata göstermek gezinmeyi kilitlerdi.
    return const {};
  }
});

class Kabuk extends ConsumerWidget {
  const Kabuk({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final oturum = ref.watch(sessionProvider);
    if (oturum == null) return const SizedBox.shrink();

    final hedefler = hedeflerFor(oturum.aktifRol);
    final yol = GoRouterState.of(context).matchedLocation;
    var index = hedefler.indexWhere((h) => yol.startsWith(h.yol));
    if (index < 0) index = 0;

    final sayaclar = ref.watch(gezinmeSayaclariProvider).value ?? const {};

    void git(int i) {
      context.go(hedefler[i].yol);
      // Sekme değişince sayaçlar tazelenir. Kullanıcı üç siparişi onaylayıp
      // başka sekmeye geçtiğinde rozet hâlâ "3" diyorsa rozet yalan söylüyor
      // demektir — bayat rozet, rozetsizlikten kötüdür. Bedeli sekme başına
      // tek toplu sorgu.
      ref.invalidate(gezinmeSayaclariProvider);
    }

    // Açık ziyaret çubuğu üç yerleşimde de gövdenin üstünde durur: ziyaretin
    // açık kaldığı fark edilmezse sonraki günün kayıtları da damgalanır (Y-18).
    // Bağlam şeridi EN ÜSTTE: hangi dükkan, hangi dönem. Yoksa sahip ilk
    // dükkanında kilitli kalıp Panel'i sıfır görüyor ve sebebini bulamıyor.
    final govde = Column(children: [
      const ZiyaretCubugu(),
      Expanded(child: child),
    ]);

    return switch (context.formFactor) {
      FormFactor.mobil => _MobilKabuk(
          hedefler: hedefler, secili: index, onSec: git, sayaclar: sayaclar,
          child: Column(key: K.baglamSeridi, children: [
            const BaglamSeridi(),
            Expanded(
              // Alt pay artık KALIYOR. `extendBody` ile Scaffold gövdeye
              // "altında şu kadar çubuk var" diye haber veriyor; ekranın
              // kendi eylem şeridi (`SafeArea`) o payı okuyup camın üstüne
              // çıkıyor, kaydırma görünümleri de `SonBosluk` ile.
              //
              // Bir zamanlar burada `removeBottom: true` vardı: o dönemde
              // çubuk opak ve yapışıktı, pay iki kez uygulanıp düğmelerin
              // altında 34 piksellik boşluk bırakıyordu. Cam çubukla birlikte
              // aynı pay artık taşınması gereken bilgi.
              child: MediaQuery.removePadding(
                  context: context, removeTop: true, child: govde),
            ),
          ])),
      FormFactor.tablet => Scaffold(
          body: Column(key: K.baglamSeridi, children: [
            const BaglamSeridi(),
            Expanded(child: MediaQuery.removePadding(
              context: context, removeTop: true,
              child: Row(children: [
            // `NavigationRail` KENDİ KENDİNE KAYMAZ. Sahip rolünde 19 hedef
            // var; kısa bir pencerede (macOS varsayılanı, yatay iPad, bölünmüş
            // ekran) taşıyor ve Flutter yerleşimi kırıyor — gezinme tamamen
            // kullanılamaz hâle geliyordu. Kaydırılabilir sarmalayıcı şart.
            //
            // `IntrinsicHeight` + `minHeight` ikilisi gerekiyor: rail dikeyde
            // sonsuz alan görürse ayırıcı ve göstergeler doğru çizilmez, kısa
            // listede de rail pencerenin altına kadar uzamaz.
            LayoutBuilder(
              builder: (context, kisit) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: kisit.maxHeight),
                  child: IntrinsicHeight(
                    child: NavigationRail(
                      selectedIndex: index,
                      onDestinationSelected: git,
                      labelType: NavigationRailLabelType.all,
                      destinations: [
                        for (final h in hedefler)
                          NavigationRailDestination(
                              icon: Icon(h.ikon), label: Text(h.etiket)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: govde),
            ]))),
          ]),
        ),
      // Masaüstünde bağlam sidebar'ın içinde: şerit ayrıca çizilirse
      // marka bloğuyla iki kez aynı şeyi söyler.
      FormFactor.masaustu => Scaffold(
          body: Row(children: [
            _Sidebar(hedefler: hedefler, secili: index, onSec: git, oturum: oturum),
            const VerticalDivider(width: 1),
            Expanded(child: govde),
          ]),
        ),
    };
  }
}

/// Koyu bordo sidebar — tasarımdaki panel kimliği (design/web-panel.dc.html).
class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.hedefler,
    required this.secili,
    required this.onSec,
    required this.oturum,
  });
  final List<NavHedef> hedefler;
  final int secili;
  final ValueChanged<int> onSec;
  final Session oturum;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const acik = Color(0xFFF1EAE7);
    final soluk = acik.withValues(alpha: 0.55);

    return Container(
      width: 244,
      color: scheme.sidebar,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Marka
        Padding(
          padding: const EdgeInsets.fromLTRB(T.s4, T.s5, T.s4, T.s5),
          child: Row(children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: T.bordo,
                borderRadius: BorderRadius.circular(T.rDugme),
              ),
              child: const Text('İP',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
            ),
            const SizedBox(width: T.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('İşlerPro',
                      style: TextStyle(
                          color: acik, fontWeight: FontWeight.w600, fontSize: 15)),
                  Text(_rolAdi(oturum.aktifRol),
                      style: TextStyle(color: soluk, fontSize: 11.5)),
                ],
              ),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(T.s4, 0, T.s4, T.s2),
          child: MikroEtiket('Navigasyon', color: soluk),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: T.s2),
            itemCount: hedefler.length,
            itemBuilder: (_, i) {
              final h = hedefler[i];
              final aktif = i == secili;
              return Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Material(
                  color: aktif ? T.bordo : Colors.transparent,
                  borderRadius: BorderRadius.circular(T.rDugme),
                  child: Dokunus(
                    yuvarlak: BorderRadius.circular(T.rDugme),
                    onTap: () => onSec(i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: T.s3, vertical: T.s3 - 1),
                      child: Row(children: [
                        Icon(h.ikon, size: 18, color: aktif ? Colors.white : soluk),
                        const SizedBox(width: T.s3),
                        Expanded(
                          child: Text(h.etiket,
                              style: TextStyle(
                                  color: aktif ? Colors.white : acik,
                                  fontSize: 13,
                                  fontWeight:
                                      aktif ? FontWeight.w600 : FontWeight.w500)),
                        ),
                      ]),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Divider(height: 1, color: acik.withValues(alpha: 0.12)),
        Padding(
          padding: const EdgeInsets.all(T.s4),
          child: Row(children: [
            CircleAvatar(
              radius: 15,
              backgroundColor: T.bordoOrta,
              child: const Text('MK',
                  style: TextStyle(
                      color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: T.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Kullanıcı',
                      style: TextStyle(
                          color: acik, fontSize: 12.5, fontWeight: FontWeight.w600)),
                  Text(_rolAdi(oturum.aktifRol),
                      style: TextStyle(color: soluk, fontSize: 11)),
                ],
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  static String _rolAdi(AppRole r) => switch (r) {
        AppRole.platformAdmin => 'Platform Yöneticisi',
        AppRole.isletmeSahibi => 'İşletme sahibi',
        AppRole.dukkanMuduru => 'Dükkan müdürü',
        AppRole.pazarlamaci => 'Pazarlamacı',
        AppRole.hazirlik => 'Hazırlık',
        AppRole.ogretmen => 'Öğretmen',
      };
}

/// Mobilde en fazla 4 sekme + "Daha fazla".
/// Taşan ekranlar alt panelde listelenir — hiçbir ekran erişilemez kalmaz.
class _MobilKabuk extends StatelessWidget {
  const _MobilKabuk({
    required this.hedefler,
    required this.secili,
    required this.onSec,
    required this.child,
    this.sayaclar = const {},
  });
  final List<NavHedef> hedefler;
  final int secili;
  final ValueChanged<int> onSec;
  final Widget child;

  /// yol → bekleyen iş sayısı.
  final Map<String, int> sayaclar;

  static const _sekme = 4;

  @override
  Widget build(BuildContext context) {
    final gorunur = hedefler.take(_sekme).toList();
    final tasan = hedefler.skip(_sekme).toList();
    final tasanSecili = secili >= _sekme;

    void dahaFazla() {
      // 15 hedefi düz listeye dökmek, kullanıcıyı her açışta baştan okumaya
      // zorluyordu ve her satır 130 piksel yer kaplıyordu. Öbekli ızgara
      // hem arama yerine yön bulmayı sağlıyor hem üç katı hedefi sığdırıyor.
      final obekler = <NavObek, List<(int, NavHedef)>>{};
      for (var i = 0; i < tasan.length; i++) {
        (obekler[tasan[i].obek] ??= []).add((_sekme + i, tasan[i]));
      }

      showModalBottomSheet<void>(
        context: context,
        // Tutamağı Material çizmiyor: onu panelin KENDİ zeminine koyuyor ve
        // zemin saydam olunca camın dışında, içeriğin üstünde kalıyordu.
        showDragHandle: false,
        // Panel de CAM: arkasındaki ekran bulanıklaşarak duruyor, opak beyaz
        // bir levha inmiyor. Perde de koyu — cam ancak arkası uzaklaşırsa
        // öne çıkıyor.
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.62 : 0.34),
        elevation: 0,
        builder: (c) {
          final s = Theme.of(c).colorScheme;
          return Cam(
            yuvarlak: 28,
            golge: false,
            child: SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.75,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(T.s4, 0, T.s4, T.s4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 5,
                        margin: const EdgeInsets.only(top: T.s2),
                        decoration: BoxDecoration(
                          color: s.onSurface.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                    for (final o in NavObek.values)
                      if (obekler[o] != null) ...[
                        Padding(
                          padding: const EdgeInsets.only(
                              top: T.s3, bottom: T.s2),
                          child: MikroEtiket(o.ad),
                        ),
                        GridView.count(
                          crossAxisCount: 3,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          mainAxisSpacing: T.s2,
                          crossAxisSpacing: T.s2,
                          childAspectRatio: 1.15,
                          children: [
                            for (final (i, h) in obekler[o]!)
                              Dokunus(
                                tur: DokunusTuru.nesne,
                                key: K.menuHedef(h.yol),
                                onTap: () {
                                  Navigator.pop(context);
                                  onSec(i);
                                },
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: secili == i
                                        ? s.primary.withValues(alpha: 0.14)
                                        : Colors.white.withValues(
                                            alpha: s.brightness ==
                                                    Brightness.dark
                                                ? 0.06 : 0.55),
                                    border: Border.all(
                                        color: secili == i
                                            ? s.primary.withValues(alpha: 0.5)
                                            : s.outlineVariant
                                                .withValues(alpha: 0.6)),
                                    // Camın içindeki öğeler de yuvarlak:
                                    // keskin köşeli bir kutu, yuvarlak bir
                                    // levhanın içinde yamalı duruyor.
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Icon(h.ikon, size: 21, color: s.primary),
                                      const SizedBox(height: T.s2),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 4),
                                        child: Text(h.etiket,
                                            textAlign: TextAlign.center,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(c)
                                                .textTheme.labelMedium),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                  ],
                ),
              ),
            ),
            ),
          );
        },
      );
    }

    return Scaffold(
      // Cam çubuğun arkasından içerik AKAR — camın çalışma biçimi bu.
      // Karşılığında gövde çubuğun altına uzuyor; kaydırma görünümlerinin
      // sonundaki `SonBosluk` son satırı camın altından kurtarıyor.
      extendBody: true,
      body: CubukPayi(pay: AltGezinme.toplamYukseklik(context), child: child),
      bottomNavigationBar: AltGezinme(
        secili: tasanSecili ? gorunur.length : secili,
        onSec: (i) => i < gorunur.length ? onSec(i) : dahaFazla(),
        ogeler: [
          for (final h in gorunur)
            GezinmeOgesi(
                ikon: h.ikon,
                doluIkon: h.doluIkon,
                etiket: h.etiket,
                sayi: sayaclar[h.yol] ?? 0),
          if (tasan.isNotEmpty)
            GezinmeOgesi(
              // Menüde bir ekran seçiliyken sekme "Daha fazla" demeye devam
              // ediyordu: kullanıcı Vadeler'deyken çubuk nerede olduğunu
              // söylemiyordu. Seçiliyken hedefin kendi kimliğini taşır.
              ikon: tasanSecili ? hedefler[secili].ikon : Icons.more_horiz,
              doluIkon:
                  tasanSecili ? hedefler[secili].doluIkon : Icons.more_horiz,
              etiket: tasanSecili ? hedefler[secili].etiket : 'Daha fazla',
              // Menü kara kutu değil: gizli hedeflerdeki işin TOPLAMI.
              sayi: tasanSecili
                  ? 0
                  : tasan.fold<int>(0, (a, h) => a + (sayaclar[h.yol] ?? 0)),
            ),
        ],
      ),
    );
  }
}
