import 'dart:ui';

import 'package:flutter/cupertino.dart' show CupertinoSliverRefreshControl;
import 'package:flutter/foundation.dart' show ValueListenable;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import 'dokunus.dart';

/// Cam katmanı — Liquid Glass'ın bu uygulamadaki karşılığı.
///
/// Camın tek kuralı var ve süslemeyle ilgisi yok: **cam, içeriğin ÜSTÜNDE
/// yüzen katmandır.** Gezinme çubuğu, başlık, alta sabitlenen eylem şeridi —
/// bunlar içeriğe ait değil, içeriğin üstünde duran denetimlerdir. İçerik
/// onların ALTINDAN akar; camı cam yapan da bu, dokusu değil.
///
/// Her şeyi bulanıklaştırırsak hiçbir şey yüzmez: cam "üstteyim" demek
/// olmaktan çıkıp bir dokuya dönüşür. Bu yüzden iki ayrı yüzey var:
///
///   [Cam]     → DENETİM katmanı. Bulanıklaştırır, çünkü arkasından gerçekten
///               içerik geçer.
///   [CamKart] → İÇERİK katmanı. Bulanıklaştırmaz — arkasında geçen bir şey
///               yok, [CamZemin]'in yumuşak geçişi var. Aynı ışığı, aynı
///               yuvarlaklığı, aynı derinliği taşır.
///
/// Bulanıklık bedava değil: her `BackdropFilter` ayrı bir katman açıp onu
/// süzüyor. Ekranda üç tanesi fark edilmez, kırk satırlık bir listede her
/// satıra bir tane koymak kare düşürür. Kartların buna ihtiyacı zaten yok:
/// arkalarında bulanıklaştırılacak yüksek frekanslı bir şey yok.
///
/// Bu katman, tasarımın "gölge yok, ayrım 1px kenarlıkla" kuralını BİLEREK
/// bozuyor. Düz yüzeyler düzlemde yan yana durur; cam yüzer, yüzen şeyin de
/// gölgesi olur. İkisi aynı ekranda tutarlı olamıyor — cam kazandı.


/// Zemin + üstten sönen parlama = TEK gradyan.
///
/// `BoxDecoration`da `color` ve `gradient` birlikte verilemez: gradyan bir
/// shader kuruyor ve shader, `color`ın yerine geçiyor — `color` hiç çizilmiyor.
/// Derleyici uyarmıyor, kod da doğru okunuyor. Camın zemini bu yüzden hiç
/// boyanmıyordu; ekranda görünen tek şey üstteki parlamaydı, kartın alt yarısı
/// tamamen saydam kalıyordu. Koyu bordo baskın kart da bu yüzden gri çıktı.
///
/// Parlamayı zemine burada karıştırıyoruz; dışarıya tek bir gradyan gidiyor.
LinearGradient parlat(Color zemin, Color parlama, double bitis) => LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color.alphaBlend(parlama, zemin), zemin],
      stops: [0, bitis],
    );

// ── Denetim katmanı ────────────────────────────────────────────────────────

/// Yüzen cam yüzey: bulanıklık + yarı saydam zemin + kenar ışığı + gölge.
///
/// Dördü de gerekli ve dördü ayrı iş yapıyor:
///   1. **Bulanıklık** arkadaki içeriği dağıtır — okunaklılığı bu kurtarır
///   2. **Yarı saydam zemin** dağılan içeriğin üstüne süt gibi bir kat çeker
///   3. **Kenar ışığı** camın KALINLIĞINI verir; cam ancak ışığı nasıl
///      tuttuğuyla anlaşılıyor
///   4. **Gölge** yüzdüğünü söyler; gölgesiz cam, cam değil delik
class Cam extends StatelessWidget {
  const Cam({
    required this.child,
    this.yuvarlak = T.rCam,
    this.bulaniklik = 24,
    this.golge = true,
    this.kenarlik = true,
    super.key,
  });

  final Widget child;
  final double yuvarlak;
  final double bulaniklik;
  final bool golge;

  /// Kenar ışığı. Cam bir kenarına yapışıyorsa (başlık şeridi gibi) tam
  /// çerçeve yanlış olur; o zaman kapatılır.
  final bool kenarlik;

  /// Camın zemin rengi — çevresindeki bileşenlerin aynı sütü kullanabilmesi
  /// için açık (rozet, çip, iç yüzeyler).
  static Color doku(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark
          ? const Color(0xFF1F191B).withValues(alpha: 0.72)
          : Colors.white.withValues(alpha: 0.68);

  @override
  Widget build(BuildContext context) {
    final koyu = Theme.of(context).brightness == Brightness.dark;
    final sekil = BorderRadius.circular(yuvarlak);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: sekil,
        // İki gölge: geniş ve yumuşak olan yüksekliği, dar ve koyu olan
        // kenarı verir. Tek gölgeyle cam ya uçuyor ya yapışık duruyor.
        boxShadow: golge
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: koyu ? 0.44 : 0.13),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: koyu ? 0.30 : 0.06),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: sekil,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: bulaniklik, sigmaY: bulaniklik),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: sekil,
              border: kenarlik
                  ? Border.all(
                      color: Colors.white
                          .withValues(alpha: koyu ? 0.14 : 0.70),
                      width: 0.8,
                    )
                  : null,
              // Kenar parlaması: üstten aşağı sönen beyaz — ZEMİNE KARIŞMIŞ
              // hâlde. Bkz. [parlat]: `color` ile `gradient` birlikte
              // verilemiyor.
              gradient: parlat(doku(context),
                  Colors.white.withValues(alpha: koyu ? 0.34 : 0.34), 0.45),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

// ── Zemin ──────────────────────────────────────────────────────────────────

/// Camın arkasındaki ışık.
///
/// Bu, kozmetik bir arka plan değil — camın ÖN KOŞULU. Düz tek renk bir
/// zeminin üstünde `BackdropFilter` hiçbir şey yapmaz: bulanıklaştırılan düz
/// renk yine aynı düz renktir. Yarı saydam bir kart da öyle; #FCFAF9 üstünde
/// %70 beyaz, yine #FCFAF9'a yakın bir şey verir.
///
/// Cam ancak arkasında DEĞİŞEN bir şey varsa cam görünür. Bu yumuşak bordo
/// geçişleri o değişimi sağlıyor: kart ekranın neresinde durursa dursun farklı
/// bir tonun üstünde duruyor, kenarı da bu yüzden seçiliyor.
///
/// Ölçülü tutuldu — bu bir muhasebe ekranı, duvar kâğıdı değil. Açık temada
/// geçişler zar zor görülüyor; işi kartın kenarını ayırt ettirmek, dikkat
/// çekmek değil.
class CamZemin extends StatelessWidget {
  const CamZemin({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final koyu = Theme.of(context).brightness == Brightness.dark;

    return DecoratedBox(
      decoration: BoxDecoration(color: s.surface),
      child: DecoratedBox(
        // Sağ üstte marka bordosu — başlığın ve baskın sayının olduğu yer.
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0.85, -0.75),
            radius: 1.15,
            colors: [
              (koyu ? T.dBordo : T.bordo).withValues(alpha: koyu ? 0.16 : 0.09),
              (koyu ? T.dBordo : T.bordo).withValues(alpha: 0),
            ],
          ),
        ),
        child: DecoratedBox(
          // Sol altta daha soğuk, çok daha soluk bir ikinci kaynak: tek
          // kaynakta zemin düz bir eğim gibi okunuyor, iki kaynakta hacim
          // kazanıyor.
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-1, 0.85),
              radius: 1.0,
              colors: [
                (koyu ? T.bilgi : T.bordoOrta)
                    .withValues(alpha: koyu ? 0.10 : 0.06),
                Colors.transparent,
              ],
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

// ── İçerik katmanı ─────────────────────────────────────────────────────────

/// Kartın tonu.
enum CamTon {
  /// Sıradan içerik: süt beyazı cam.
  duz,

  /// Ekranın TEK baskın kartı: koyu bordo cam, üstünde açık yazı.
  /// Ekranda birden fazla olursa hiçbiri baskın olmaz.
  marka,
}

/// İçerik kartı — camın ışığını taşır, bulanıklaştırmaz.
///
/// Bulanıklık burada olmayışı bir eksik değil, bir karar: arkasında geçen bir
/// şey yok ([CamZemin] duruyor), maliyeti ise listelerde gerçek. Kartı cam
/// yapan şey zaten bulanıklık değil — yarı saydamlık, kenar ışığı ve gölge.
class CamKart extends StatelessWidget {
  const CamKart({
    required this.child,
    this.dolgu = true,
    this.ton = CamTon.duz,
    this.onTap,
    super.key,
  });

  final Widget child;

  /// İçeriden dolgu. Liste barındıran kartlarda kapatılır: satırlar kenara
  /// kadar uzanmalı ki dokunma alanı kartın tamamı olsun.
  final bool dolgu;
  final CamTon ton;
  final VoidCallback? onTap;

  /// Kartın boyası — [CamKart]'ın dışında da gerekiyor: tembel bir sliver
  /// listesinin arkasına `DecoratedSliver` ile aynı yüzeyi çizmek için.
  /// İki yerde ayrı ayrı yazılsaydı biri diğerinden kayardı.
  static BoxDecoration susu(BuildContext context,
      {CamTon ton = CamTon.duz, BorderRadius? sekil}) {
    final koyu = Theme.of(context).brightness == Brightness.dark;
    final marka = ton == CamTon.marka;
    final zemin = marka
        ? (koyu ? const Color(0xFF2A121B) : T.bordoKoyu)
        : (koyu
            ? T.dKart.withValues(alpha: 0.62)
            : Colors.white.withValues(alpha: 0.72));

    return BoxDecoration(
      borderRadius: sekil ?? BorderRadius.circular(T.rCam),
      border: Border.all(
        color: marka
            ? Colors.white.withValues(alpha: 0.16)
            : Colors.white.withValues(alpha: koyu ? 0.08 : 0.85),
        width: marka ? 0.8 : 1,
      ),
      // Işık yukarıdan gelir. Marka kartında köşegen boyunca: bordo altta
      // derinleşince kart düz bir renk lekesi değil, kalın bir cisim gibi
      // duruyor. Zemin gradyana KARIŞTIRILIYOR — bkz. [parlat].
      gradient: marka
          ? LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.alphaBlend(Colors.white.withValues(alpha: 0.13), zemin),
                Color.alphaBlend(Colors.white.withValues(alpha: 0.03), zemin),
                Color.alphaBlend(Colors.black.withValues(alpha: 0.22), zemin),
              ],
              stops: const [0, 0.45, 1],
            )
          : parlat(
              zemin, Colors.white.withValues(alpha: koyu ? 0.05 : 0.55), 0.4),
      boxShadow: [
        BoxShadow(
          color: Colors.black
              .withValues(alpha: koyu ? 0.34 : (marka ? 0.16 : 0.055)),
          blurRadius: marka ? 22 : 16,
          offset: Offset(0, marka ? 8 : 5),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: koyu ? 0.22 : 0.03),
          blurRadius: 2,
          offset: const Offset(0, 1),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final marka = ton == CamTon.marka;
    final sekil = BorderRadius.circular(T.rCam);

    final govde = DecoratedBox(
      decoration: susu(context, ton: ton),
      child: ClipRRect(
        borderRadius: sekil,
        // `Material` mürekkep için değil, İÇİNDEKİLER için: `TextField`,
        // `Tooltip` gibi bileşenler bir `Material` atası arıyor ve
        // bulamayınca patlıyorlar.
        child: Material(
          type: MaterialType.transparency,
          child: dolgu
              ? Padding(padding: const EdgeInsets.all(T.s4), child: child)
              : child,
        ),
      ),
    );

    // Küçülme kartın GÖLGESİYLE birlikte olmalı; yalnızca içerik küçülürse
    // kart yerinde durup içi kayıyormuş gibi görünüyor. `Dokunus` bu yüzden
    // en dışta — hem koyu şema sarmalayıcısının hem gövdenin dışında.
    Widget bit(Widget w) => onTap == null
        ? w
        : Dokunus(tur: DokunusTuru.nesne, onTap: onTap, child: w);

    // Marka kartının içi KOYU. Çocukları hâlâ açık tema renkleriyle çizerse
    // koyu bordonun üstüne koyu mürekkep yazılır ve hiçbiri okunmaz. Şemayı
    // burada çeviriyoruz — tek tek renk vermek yerine, çünkü içeride
    // `s.basarili` / `s.error` gibi anlam renkleri de var ve onların da koyu
    // zemin karşılığına geçmesi gerekiyor.
    if (!marka) return bit(govde);
    final t = Theme.of(context);
    final koyuSema = t.colorScheme.copyWith(brightness: Brightness.dark);
    return bit(Theme(
      data: t.copyWith(
        brightness: Brightness.dark,
        colorScheme: koyuSema.copyWith(
          onSurface: Colors.white,
          onSurfaceVariant: Colors.white.withValues(alpha: 0.68),
          outlineVariant: Colors.white.withValues(alpha: 0.15),
          surfaceContainerHigh: Colors.white.withValues(alpha: 0.12),
          // `error` şemada İKİ temada da aynı koyu kırmızı (#B0332B) — koyu
          // bordonun üstünde neredeyse görünmüyordu. Anlam renklerinin koyu
          // zemin karşılıkları `AppStatusColors`ta; şema koyuya çevrildiği
          // için uzantı doğru olanı veriyor.
          error: koyuSema.tehlike,
        ),
        // `apply` her gövde stiline aynı rengi basıyor; bodySmall'ın temada
        // AÇIKÇA verilmiş `onSurfaceVariant` rengi de bu arada eziliyor.
        // Sonra geri kısıyoruz: koyu kartta her satır aynı beyazlıkta olursa
        // ikincil bilgi ikincil görünmez.
        textTheme: t.textTheme
            .apply(bodyColor: Colors.white, displayColor: Colors.white)
            .copyWith(
              bodySmall: t.textTheme.bodySmall
                  ?.copyWith(color: Colors.white.withValues(alpha: 0.66)),
            ),
      ),
      child: govde,
    ));
  }
}

/// Başlıklı cam bölüm — [CamKart]'ın `Bolum` karşılığı.
class CamBolum extends StatelessWidget {
  const CamBolum({
    required this.baslik,
    required this.child,
    this.altBaslik,
    this.eylem,
    super.key,
  });

  final String baslik;
  final String? altBaslik;
  final Widget child;
  final Widget? eylem;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return CamKart(
      dolgu: false,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(T.s4, T.s4, T.s3, T.s3),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(baslik, style: t.titleMedium),
                  if (altBaslik != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(altBaslik!, style: t.bodySmall),
                    ),
                ],
              ),
            ),
            ?eylem,
          ]),
        ),
        Divider(height: 1, color: s.outlineVariant.withValues(alpha: 0.6)),
        child,
      ]),
    );
  }
}

// ── Sayfa ──────────────────────────────────────────────────────────────────

/// Camın altından akan sayfa.
///
/// Cam katmanının bedeli hep aynı: içerik onun ALTINDAN geçmeli, yoksa cam
/// değil boyalı şerit olur. Bunu her ekranın kendi eliyle kurması, ilk satırın
/// başlığın altında kalması demek — alt çubukta bir kez yaşadığımız hata.
/// Burada üst ve alt pay ekrandan alınmıyor, sayfa kendisi veriyor.
///
/// BÜYÜK BAŞLIK. Ekranın adı önce içeriğin bir parçası olarak, 30 punto
/// yazıyor; kaydırdıkça camın altına giriyor ve tam o anda çubuktaki küçük
/// karşılığı beliriyor. Material'ın sabit yükseklikte, hep aynı puntoda duran
/// `AppBar`ıyla arasındaki fark yalnızca boy değil: burada başlık, ekranın
/// KENDİSİNİN parçası — üstüne oturtulmuş bir şerit değil.
///
/// Başlık tepedeyken cam DEĞİL. Altından geçen bir şey yokken bulanıklık da
/// kenar da yalan olur. Cam, içerik altına girdiği anda beliriyor — camı
/// gösteren şey hareketin kendisi.
class CamSayfa extends StatefulWidget {
  const CamSayfa({
    required this.baslik,
    this.cocuklar = const [],
    this.slivers = const [],
    this.eylemler = const [],
    this.oncul,
    this.onYenile,
    this.altSerit,
    this.denetleyici,
    this.yatayDolgu = T.s4,
    super.key,
  });

  final String baslik;

  /// Kutu çocuklar — yatay dolgu uygulanır, tembel DEĞİL. Panel gibi sayısı
  /// belli ekranlar için.
  final List<Widget> cocuklar;

  /// Sliver çocuklar — dolguyu kendileri kurar, tembel olabilirler. Uzunluğu
  /// veriye bağlı listeler için ([ListeGovdesi] bunu üretir).
  final List<Widget> slivers;
  final List<Widget> eylemler;

  /// Geri düğmesinin yerine konan öğe. Sipariş detayı bunu kullanıyor:
  /// geri dönerken listeye "bir şey değişti" bilgisini sonuç olarak
  /// taşımanın başka yolu yok.
  final Widget? oncul;

  final Future<void> Function()? onYenile;

  /// Ekranın altına sabitlenen şerit (`EylemSeridi` gibi).
  final Widget? altSerit;

  /// Dışarıdan verilen kaydırma denetleyicisi — sona yaklaşınca sonraki
  /// sayfayı çeken ekranlar (katalog) buna ihtiyaç duyuyor.
  final ScrollController? denetleyici;
  final double yatayDolgu;

  @override
  State<CamSayfa> createState() => _CamSayfaState();
}

class _CamSayfaState extends State<CamSayfa> {
  /// Kaydırma miktarı. `ValueNotifier` — `setState` DEĞİL: başlık her pikselde
  /// yeniden çiziliyor ve `setState` bunu yaparken listeyi de yeniden kurardı.
  /// Değişen yalnızca çubuk; dinleyen de yalnızca çubuk olmalı.
  final _kaydirma = ValueNotifier<double>(0);

  @override
  void dispose() {
    _kaydirma.dispose();
    super.dispose();
  }

  bool _kaydir(ScrollNotification n) {
    // Yalnızca sayfanın kendi kaydırması: içerideki yatay şeritler (süzgeç
    // çipleri) başlığı camlaştırmamalı.
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    _kaydirma.value = n.metrics.pixels;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: CamBaslik(
        baslik: widget.baslik,
        eylemler: widget.eylemler,
        oncul: widget.oncul,
        kaydirma: _kaydirma,
      ),
      bottomNavigationBar: widget.altSerit,
      body: CamZemin(
        child: Builder(builder: (c) {
          // `extendBodyBehindAppBar` gövdenin üst payına başlık boyunu
          // ekliyor; ilk kart bu yüzden camın altından başlayıp payla
          // aşağı itiliyor — kaydırınca gerçekten altına giriyor.
          final ust = MediaQuery.paddingOf(c).top;
          return NotificationListener<ScrollNotification>(
            onNotification: _kaydir,
            child: CustomScrollView(
              controller: widget.denetleyici,
              // Zıplayan fizik her platformda: çekip bırakma hissi bu dilin
              // parçası ve `CupertinoSliverRefreshControl` da buna dayanıyor.
              physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics()),
              slivers: [
                SliverPadding(padding: EdgeInsets.only(top: ust)),
                if (widget.onYenile != null)
                  // Material'ın aşağı inen tekerine karşılık iOS'un çekme
                  // hareketi: yay parmağın çektiği kadar beliriyor, ayrı bir
                  // nesne düşmüyor.
                  CupertinoSliverRefreshControl(onRefresh: widget.onYenile),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                      widget.yatayDolgu, T.s2, widget.yatayDolgu, 0),
                  sliver: SliverToBoxAdapter(
                    child: _BuyukBaslik(widget.baslik),
                  ),
                ),
                if (widget.cocuklar.isNotEmpty)
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                        widget.yatayDolgu, T.s3, widget.yatayDolgu, 0),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate(widget.cocuklar),
                    ),
                  ),
                ...widget.slivers,
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _BuyukBaslik extends StatelessWidget {
  const _BuyukBaslik(this.metin);
  final String metin;

  /// Büyük başlığın kapladığı yükseklik. Çubuktaki küçük başlığın ne zaman
  /// belireceği buradan hesaplanıyor — iki sayı ayrı yerlerde durursa başlık
  /// ya erken ya geç beliriyor ve ikisi bir an yan yana görünüyor.
  static const boy = 44.0;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: boy,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            metin,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: T.fontSans,
              fontSize: 30,
              height: 1.1,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.8,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      );
}

/// Cam başlık şeridi.
class CamBaslik extends StatelessWidget implements PreferredSizeWidget {
  const CamBaslik({
    required this.baslik,
    this.eylemler = const [],
    this.oncul,
    this.kaydirma,
    super.key,
  });

  final String baslik;
  final List<Widget> eylemler;
  final Widget? oncul;

  /// Sayfanın kaydırma miktarı. Yoksa çubuk hep cam çizilir.
  final ValueListenable<double>? kaydirma;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final koyu = Theme.of(context).brightness == Brightness.dark;
    final t = Theme.of(context).textTheme;

    // Cam, İLK pikselde belirir: altına bir şey girdiği an. Küçük başlık ise
    // ancak büyük başlık gerçekten geçtikten sonra — ikisi aynı anda
    // görünürse ekranda başlık iki kere yazılı oluyor.
    Widget kur(double px) {
      final cam = (px / 10).clamp(0.0, 1.0);
      final yazi = ((px - _BuyukBaslik.boy * 0.55) / 22).clamp(0.0, 1.0);
      return Stack(fit: StackFit.expand, children: [
        IgnorePointer(
          child: Opacity(
            opacity: cam,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Cam.doku(context),
                    border: Border(
                      bottom: BorderSide(
                        color:
                            Colors.white.withValues(alpha: koyu ? 0.10 : 0.55),
                        width: 0.8,
                      ),
                    ),
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
        // Küçük başlık ORTADA: iOS'ta çubuğa çöken başlık ortalanır, sola
        // dayalı kalan büyük olanıdır.
        Center(
          child: Opacity(
            opacity: yazi,
            child: Text(baslik,
                style: t.titleMedium?.copyWith(fontSize: 15.5)),
          ),
        ),
      ]);
    }

    return AppBar(
      title: const SizedBox.shrink(),
      leading: oncul,
      actions: eylemler,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      // Temadaki alt kenarlık burada YANLIŞ: cam kendi kenarını taşıyor ve
      // tepedeyken hiç kenarı olmamalı.
      shape: const Border(),
      flexibleSpace: kaydirma == null
          ? kur(1000)
          : ValueListenableBuilder<double>(
              valueListenable: kaydirma!,
              builder: (_, px, _) => kur(px),
            ),
    );
  }
}
