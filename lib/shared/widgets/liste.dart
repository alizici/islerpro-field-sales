import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import 'bolum.dart';
import 'cam.dart';
import 'gezinme.dart';
import 'form_kabuk.dart';
import 'mono.dart';

/// Liste ekranlarının ortak gövdesi.
///
/// Aynı yirmi satır otuz yedi ekranda kopyalanmıştı: 22 piksellik bir
/// çarkıfelek, `Bildirim`li bir hata dolgusu, `isEmpty` kontrolü ve
/// `ListView.separated`. Kopya olduğu için de hepsi biraz farklıydı —
/// kimi dolgu koymuş kimi koymamış, kimi `RefreshIndicator` sarmış kimi
/// sarmamış. Kullanıcı bunu "tasarım" olarak değil, **tutarsızlık** olarak
/// yaşıyor: aynı işi yapan iki ekran birbirine benzemiyor.
///
/// Yüklenme artık çarkıfelek değil İSKELET: kullanıcı bir sonraki karede
/// ne geleceğini görüyor, boş ekrana bakıp beklemiyor.
/// `whenData`nın yerine geçen eşleme.
///
/// `whenData` YETMİYOR ve sebebi ince: Riverpod tazeleme sırasında
/// `AsyncLoading`in İÇİNDE önceki değeri ya da hatayı taşıyor. `when`
/// varsayılan olarak (`skipLoadingOnRefresh: true`) bunu görüp eskisini
/// göstermeye devam ediyor — `whenData` ise yükleniyor hâlini DÜZ bir
/// `AsyncLoading`e çeviriyor ve taşınan hata yolda kayboluyor.
///
/// Sonucu ekranda şu: ağ yokken cari listesi hatayı hiç göstermiyor, sonsuza
/// kadar iskelet çiziyordu. Kullanıcı "ağ yok" satırını hiç görmüyor,
/// uygulamanın yüklenmeye devam ettiğini sanıyordu.
extension AsyncEsleme<T> on AsyncValue<T> {
  AsyncValue<R> esle<R>(R Function(T) f) => map(
        data: (d) => AsyncData(f(d.value)),
        error: (e) => AsyncError<R>(e.error, e.stackTrace),
        loading: (l) => l.hasError
            ? AsyncError<R>(l.error!, l.stackTrace!)
            : (l.hasValue ? AsyncData(f(l.requireValue)) : AsyncLoading<R>()),
      );
}

class ListeGovdesi<E> extends StatelessWidget {
  const ListeGovdesi({
    required this.veri,
    required this.satir,
    required this.bos,
    this.ust,
    this.son,
    this.listeKey,
    this.ayrac = true,
    this.iskeletSatir = 6,
    this.altBosluk = T.s6,
    super.key,
  });

  final AsyncValue<List<E>> veri;
  final Widget Function(BuildContext, E, int) satir;

  /// Boş durum — [BosDurum] bekler ama zorunlu değil.
  final Widget bos;

  /// Listeyle BİRLİKTE kayan başlık (özet şeridi, süzgeç, kural notu).
  final Widget? ust;

  /// Listenin SONUNA eklenen öğe — "daha fazlası yükleniyor" göstergesi
  /// gibi. Boş listede çizilmez: yüklenecek bir şey yok.
  final Widget? son;

  final Key? listeKey;
  final bool ayrac;
  final int iskeletSatir;
  final double altBosluk;

  @override
  Widget build(BuildContext context) {
    // Kimlik BÖLÜMÜN kendisine ait, yalnızca dolu hâline değil: "liste var mı"
    // sorusunu soran bir test, liste boşken de cevabını alabilmeli.
    // Yatay dolgu BURADA: `CamSayfa` yalnızca kutu çocuklarına dolgu
    // uygulayabiliyor, sliver kendi kenar payını kendi kurmak zorunda.
    // Unutulduğunda liste levhası ekranın kenarına yapışıyor ve tek başına
    // "bu ekran ötekilerden farklı" diye okunuyor.
    return KeyedSubtree(
      key: listeKey,
      child: SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: T.s4),
        sliver: SliverMainAxisGroup(slivers: [
          if (ust != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: T.s3),
                child: ust,
              ),
            ),
          _govde(context),
          SliverToBoxAdapter(child: SonBosluk(ek: altBosluk)),
        ]),
      ),
    );
  }

  Widget _govde(BuildContext context) => veri.when(
        loading: () => SliverToBoxAdapter(
            child: CamKart(dolgu: false, child: IskeletListe(satir: iskeletSatir))),
        error: (e, _) => SliverToBoxAdapter(
            child: Bildirim(e.toString(), tip: BildirimTip.hata)),
        data: (liste) => liste.isEmpty
            ? SliverToBoxAdapter(child: CamKart(dolgu: false, child: bos))
            : _KartliListe(
                sayi: liste.length,
                ayrac: ayrac,
                son: son,
                satir: (c, i) => satir(c, liste[i], i),
              ),
      );
}

/// Satırları TEK cam levhanın içinde tutan tembel liste.
///
/// Tembel kalması şart — katalogda binlerce satır olabiliyor ve hepsini bir
/// `Column`a dizmek ilk kareyi saniyelere çıkarıyor. Bu yüzden gövde
/// `SliverList`, zemin ise `DecoratedSliver`: kart, satırların arkasına
/// çizilen bir boya; satırları İÇİNDE tutan bir kutu değil.
///
/// Bedeli: `DecoratedSliver` kırpmıyor. Basılı satırın vurgusu, levhanın
/// yuvarlak köşesinden taşardı — ilk ve son satır bu yüzden ayrıca
/// kırpılıyor. Aradakiler kırpılmıyor: köşeleri yok, `ClipRRect` bedava değil.
class _KartliListe extends StatelessWidget {
  const _KartliListe(
      {required this.sayi, required this.satir, required this.ayrac,
       this.son});
  final int sayi;
  final bool ayrac;
  final Widget Function(BuildContext, int) satir;

  /// Listenin son öğesi — "daha fazlası yükleniyor". AYNI `SliverList`in
  /// içinde durmak zorunda: ayrı bir sliver olarak verildiğinde, ekranın
  /// dışında kalsa bile kuruluyordu (`SliverMainAxisGroup` çocuklarının
  /// hepsini yerleştiriyor, `SliverList` de en az bir çocuk kuruyor).
  /// İçindeki çark böylece hiç durmayan bir animasyon başlatıp
  /// `pumpAndSettle`'ı sonsuza kilitliyordu — ve `find.byType` görünmeyeni
  /// atladığı için testte "çark yok" diye görünüyordu.
  final Widget? son;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    const yuvarlak = Radius.circular(T.rCam);
    final toplam = sayi + (son == null ? 0 : 1);

    return DecoratedSliver(
      decoration: CamKart.susu(context),
      sliver: SliverList.builder(
        itemCount: toplam,
        itemBuilder: (c, i) {
          Widget w = Column(mainAxisSize: MainAxisSize.min, children: [
            if (ayrac && i > 0)
              // Ayraç SOLDAN İÇERİDE başlar: kenardan kenara uzanan bir çizgi
              // levhayı ikiye böler gibi görünüyor, içeriden başlayan çizgi
              // satırları ayırıyor.
              Padding(
                padding: const EdgeInsets.only(left: T.s4),
                child: Divider(
                    height: 1,
                    thickness: 1,
                    color: s.outlineVariant.withValues(alpha: 0.55)),
              ),
            if (i == sayi) son! else satir(c, i),
          ]);
          if (i == 0 || i == toplam - 1) {
            w = ClipRRect(
              borderRadius: BorderRadius.vertical(
                top: i == 0 ? yuvarlak : Radius.zero,
                bottom: i == toplam - 1 ? yuvarlak : Radius.zero,
              ),
              child: w,
            );
          }
          return w;
        },
      ),
    );
  }
}

/// Kaydırma görünümlerinin SONUNA konan boşluk.
///
/// Yüzen cam çubuk içeriğin üstünde durur ve içerik onun ALTINDAN akar —
/// camın çalışma biçimi bu. Bedeli: son satır çubuğun altında kalıp
/// okunamaz. Bu boşluk onu yukarı iter.
///
/// Payı kabuk [CubukPayi] ile bildirir. `MediaQuery.paddingOf` bu iş için
/// yetmiyor: her ekranın kendi `Scaffold`u var ve iç içe `Scaffold`lar alt
/// payı tüketiyor — ilk denemede son satır camın altında kalıyordu.
///
/// Ekranlar payı elle hesaplamaz; hesaplasalardı çubuk boyu değiştiğinde on
/// sekiz ayrı yerde unutulurdu.
class SonBosluk extends StatelessWidget {
  const SonBosluk({this.ek = T.s6, super.key});
  final double ek;

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: ek + CubukPayi.of(context));
}

/// Yüklenirken görünen iskelet satırları.
///
/// KASITLI OLARAK ANİMASYONSUZ. Parıldayan bir iskelet daha "canlı" durur ama
/// sonsuz bir animasyon `pumpAndSettle`'ı asla bitirmez ve testlerin tamamı
/// zaman aşımına uğrar. Düz bloklar zaten tasarımın diline (gölgesiz, düz
/// yüzey) daha yakın.
class IskeletListe extends StatelessWidget {
  const IskeletListe(
      {this.satir = 6, this.ikon = true, this.sayfa = false, super.key});
  final int satir;
  final bool ikon;

  /// Ekranın TAMAMINI kaplayan yükleme mi? O zaman kırpılmalı: iskelet
  /// sabit yükseklikte, ekran ise değil — kısa bir pencerede `Column`
  /// taşıyor ve testler "RenderFlex overflowed" diye patlıyor.
  final bool sayfa;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final govde = Column(
      children: [
        for (var i = 0; i < satir; i++) ...[
          if (i > 0) Divider(height: 1, color: s.outlineVariant),
          Padding(
            padding: const EdgeInsets.fromLTRB(T.s4, T.s3, T.s4, T.s3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (ikon) ...[
                  const Iskelet(34, 34, yuvarlak: T.rDugme),
                  const SizedBox(width: T.s3),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Genişlik satırdan satıra değişiyor: eşit uzunlukta
                      // bloklar tablo gibi duruyor, liste gibi değil.
                      Iskelet(120 + (i % 3) * 42, 12),
                      const SizedBox(height: T.s2),
                      Iskelet(80 + (i % 2) * 56, 10),
                    ],
                  ),
                ),
                const SizedBox(width: T.s3),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Iskelet(62, 12),
                    SizedBox(height: T.s2),
                    Iskelet(44, 10),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
    return sayfa
        ? SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(), child: govde)
        : govde;
  }
}

/// Tek iskelet bloğu.
class Iskelet extends StatelessWidget {
  const Iskelet(this.en, this.boy, {this.yuvarlak = 3, super.key});
  final double en, boy, yuvarlak;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Container(
      width: en,
      height: boy,
      decoration: BoxDecoration(
        color: s.onSurface.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(yuvarlak),
      ),
    );
  }
}

/// Ekranın üstündeki özet şeridi.
///
/// Bir liste ekranı "kaç tane var, ne kadar tutuyor" sorusunu kaydırmadan
/// cevaplamalı. Cam dilinde bu da bir kart — ama listenin kartından ÖNCE ve
/// ayrı duruyor: iki levha arasındaki boşluk, "bu özet, aşağısı liste" demenin
/// tek yolu.
class OzetSerit extends StatelessWidget {
  const OzetSerit({
    required this.etiket,
    required this.deger,
    this.renk,
    this.altBilgi,
    this.yanlar = const [],
    this.eylem,
    super.key,
  });

  final String etiket, deger;
  final Color? renk;
  final String? altBilgi;

  /// Sağdaki ikincil ölçüler — (etiket, değer, renk).
  final List<(String, String, Color?)> yanlar;
  final Widget? eylem;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return CamKart(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                MikroEtiket(etiket),
                const SizedBox(height: 2),
                Mono(deger, size: 26, weight: FontWeight.w600, color: renk),
                if (altBilgi != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(altBilgi!, style: t.bodySmall),
                  ),
              ],
            ),
          ),
          if (yanlar.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final y in yanlar)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(y.$1, style: t.bodySmall),
                        const SizedBox(width: T.s2),
                        Mono(y.$2,
                            size: 13, weight: FontWeight.w600, color: y.$3),
                      ],
                    ),
                  ),
              ],
            ),
          ?eylem,
        ],
      ),
    );
  }
}
