import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Dokunma katmanı — camın altındaki asıl fark.
///
/// Ekran cam gibi görünebilir ama parmağın altında hâlâ Material duruyorsa
/// uygulama Material'dır. Mürekkep dalgası (`InkWell`) Material'ın imzası:
/// dokunulan noktadan dışa doğru yayılan bir dalga, bırakınca sönen bir iz.
/// iOS'ta böyle bir şey yok ve olmaması bir eksiklik değil — iki ayrı fikir:
///
///   Material  → dokunuş bir OLAY'dır, yüzeyde iz bırakır
///   iOS       → dokunuş bir HÂL'dir, nesne basılıyken basılı görünür
///
/// İkinci fikir iki farklı davranış gerektiriyor, çünkü iOS'ta her şey aynı
/// tepkiyi vermiyor:
///
///   [DokunusTuru.satir] → Liste satırı YERİNDEN OYNAMAZ, zemini kararır.
///       Satır kendi başına bir nesne değil, levhanın bir dilimi; küçülmesi
///       levhayı yırtar gibi görünür.
///   [DokunusTuru.nesne] → Kart, düğme, çip hafifçe KÜÇÜLÜR.
///       Bunlar bağımsız cisimler; parmağın altında geri çekilmeleri onlara
///       fiziksel bir kalınlık veriyor.
///
/// Zamanlama `CupertinoButton`dan alındı ve sebebi var: basınca HIZLI (60 ms),
/// bırakınca YAVAŞ (200 ms). Tersi yapılırsa hızlı dokunuşlar hiç geri bildirim
/// vermiyor — parmak kalkana kadar animasyon daha başlamamış oluyor.
enum DokunusTuru { satir, nesne }

class Dokunus extends StatefulWidget {
  const Dokunus({
    required this.child,
    this.onTap,
    this.onLongPress,
    this.tur = DokunusTuru.satir,
    this.yuvarlak,
    this.titresim = false,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final DokunusTuru tur;

  /// Vurgu zemininin köşeleri. Satır bir levhanın içindeyse verilmez —
  /// vurgu kenardan kenara uzanmalı.
  final BorderRadius? yuvarlak;

  /// Dokunsal geri bildirim. Varsayılanı KAPALI: iOS sıradan bir gezinme
  /// dokunuşunda titremez, yalnızca SEÇİM değiştiğinde titrer (süzgeç çipi,
  /// anahtar, seçici). Her dokunuşa titreşim koymak, titreşimi anlamsızlaştırır.
  final bool titresim;

  @override
  State<Dokunus> createState() => _DokunusState();
}

class _DokunusState extends State<Dokunus>
    with SingleTickerProviderStateMixin {
  /// `late final ... = AnimationController(...)` YAZILAMAZ. Tıklanamaz bir
  /// `Dokunus` çizimde denetleyiciye hiç dokunmuyor; alan bu yüzden ilk kez
  /// `dispose()` içinde okunuyor ve denetleyici, ağaçtan kopmuş bir öğenin
  /// üstünde YARATILIYOR. `TickerMode`u aramaya kalkınca da patlıyor.
  /// Denetleyici bir kare bile oynatmadığı sürece bedavaya yakın; peşin
  /// kurmak doğru olan.
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 60),
      reverseDuration: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  bool get _etkin => widget.onTap != null || widget.onLongPress != null;

  void _bas(_) => _c.forward();
  void _birak([_]) => _c.reverse();

  void _dokun() {
    if (widget.titresim) HapticFeedback.selectionClick();
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (!_etkin) return widget.child;
    final s = Theme.of(context).colorScheme;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _bas,
      onTapUp: _birak,
      onTapCancel: _birak,
      onTap: _dokun,
      onLongPress: widget.onLongPress,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          final t = _c.value;
          if (widget.tur == DokunusTuru.satir) {
            return DecoratedBox(
              decoration: BoxDecoration(
                color: s.onSurface.withValues(alpha: 0.055 * t),
                borderRadius: widget.yuvarlak,
              ),
              child: child,
            );
          }
          return Opacity(
            // Küçülme TEK BAŞINA yetmiyor: 0.97'lik bir ölçek küçük bir
            // çipte fark edilmiyor. Hafif sönme onu görünür kılıyor.
            opacity: 1 - 0.10 * t,
            child: Transform.scale(scale: 1 - 0.03 * t, child: child),
          );
        },
        child: widget.child,
      ),
    );
  }
}

/// iOS'un çarkı — Material'ın dönen yayı değil, sönen çubuklar.
///
/// Uygulamadaki en görünür Material izlerinden biriydi: her yükleme ekranında
/// ucu sivri bir yay dönüyordu. `.adaptive` DEĞİL, doğrudan Cupertino:
/// `.adaptive` Android'de yine Material yayı çiziyor ve uygulama platforma
/// göre iki ayrı dile bölünüyor. Tek dil istiyorsak çark da tek olmalı.
class Bekleme extends StatelessWidget {
  const Bekleme({this.boy = 20, this.renk, super.key});
  final double boy;
  final Color? renk;

  @override
  Widget build(BuildContext context) => Center(
        child: CupertinoActivityIndicator(
          radius: boy / 2,
          color: renk ?? Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
}
