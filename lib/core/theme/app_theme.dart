// Flutter 3.44'ten beri Cupertino geçişi material'da değil, cupertino'da.
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'tokens.dart';

/// İşlerPro tasarım sistemi — `design/web-panel.dc.html` uyarlaması.
///
/// Karakteri üç şey belirler:
///   1. **Bordo** marka rengi, sıcak nötr zeminler üzerinde
///   2. **Düz yüzeyler** — gölge yok, ayrım 1px kenarlıkla yapılır
///   3. **Yoğun tipografi** — veri tabloları için küçük punto, 600 ağırlıklı etiketler
abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness b) {
    final koyu = b == Brightness.dark;

    final scheme = ColorScheme(
      brightness: b,
      primary:            koyu ? T.dBordo : T.bordo,
      onPrimary:          koyu ? T.bordoKoyu : Colors.white,
      primaryContainer:   koyu ? const Color(0xFF3A2429) : T.bordoSoft,
      onPrimaryContainer: koyu ? T.dInk : T.bordoKoyu,
      secondary:          koyu ? T.dBordo : T.bordoOrta,
      onSecondary:        koyu ? T.bordoKoyu : Colors.white,
      secondaryContainer: koyu ? const Color(0xFF33262A) : T.bordoSofter,
      onSecondaryContainer: koyu ? T.dInk : T.bordo,
      error:              T.tehlike,
      onError:            Colors.white,
      errorContainer:     koyu ? const Color(0xFF3A2422) : T.tehlikeSoft,
      onErrorContainer:   koyu ? T.dInk : T.tehlike,
      surface:            koyu ? T.dZemin : T.zemin,
      onSurface:          koyu ? T.dInk : T.ink,
      onSurfaceVariant:   koyu ? T.dMuted : T.muted,
      surfaceContainerLowest:  koyu ? T.dZemin : Colors.white,
      surfaceContainerLow:     koyu ? T.dKart : T.kart,
      surfaceContainer:        koyu ? T.dKart : T.zemin,
      surfaceContainerHigh:    koyu ? T.dKart2 : T.zemin2,
      surfaceContainerHighest: koyu ? T.dKart2 : T.zemin2,
      outline:            koyu ? T.dKenar : T.kenarKoyu,
      outlineVariant:     koyu ? T.dKenar : T.kenar,
      inverseSurface:     koyu ? T.dInk : T.ink,
      onInverseSurface:   koyu ? T.dZemin : T.zemin,
      shadow: Colors.black,
      scrim: Colors.black,
    );

    final base = ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      fontFamily: T.fontSans,
    );

    // Yoğun veri arayüzü: küçük punto, 600 ağırlıklı etiketler.
    final tt = base.textTheme.copyWith(
      headlineSmall: base.textTheme.headlineSmall
          ?.copyWith(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.6),
      titleLarge: base.textTheme.titleLarge
          ?.copyWith(fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.3),
      titleMedium: base.textTheme.titleMedium
          ?.copyWith(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: -0.1),
      titleSmall: base.textTheme.titleSmall
          ?.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
      bodyLarge:  base.textTheme.bodyLarge?.copyWith(fontSize: 14, height: 1.45),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: 13, height: 1.45),
      bodySmall:  base.textTheme.bodySmall
          ?.copyWith(fontSize: 12, height: 1.4, color: scheme.onSurfaceVariant),
      labelLarge:  base.textTheme.labelLarge?.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
      labelMedium: base.textTheme.labelMedium?.copyWith(fontSize: 12, fontWeight: FontWeight.w500),
      labelSmall:  base.textTheme.labelSmall?.copyWith(
          fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8),
    ).apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);

    return base.copyWith(
      textTheme: tt,
      scaffoldBackgroundColor: scheme.surface,
      // MÜREKKEP YOK. Dokunulan noktadan yayılan dalga Material'ın imzası;
      // basılı hâli anlatan iOS diliyle aynı ekranda duramaz. Basma geri
      // bildirimi artık `Dokunus`ta: satır kararır, nesne küçülür.
      splashFactory: NoSplash.splashFactory,
      // Sayfa geçişi: iOS/macOS'ta kenardan kaydırmayla geri gelinen yatay
      // kayma. Flutter'ın varsayılanı da bu; AÇIKÇA yazılıyor çünkü bu bir
      // tercih, miras alınan bir varsayılan değil. Android bilerek kendi
      // geçişinde bırakıldı: Cupertino geçişi oraya kenar-kaydırma da
      // ekliyor ve sistemin geri hareketiyle çakışıyor.
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      }),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: tt.titleLarge,
        shape: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      // Gölge yok — ayrım kenarlıkla (tasarımda box-shadow hiç kullanılmıyor).
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: koyu ? T.dKart : T.kart,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(T.rKart),
        ),
      ),
      // Diyalog zemini AÇIKÇA veriliyor. Material varsayılanı
      // `surfaceContainerHigh` kullanıyor; bizim şemamızda o renk sıcak
      // nötr bir gri (#F1EAE7) ve büyük bir yüzeye yayılınca pembeye
      // çalıyor — bordo markanın yanında diyaloglar "renkli" görünüyordu.
      // Kart neyse diyalog da o: beyaz yüzey, 1px kenarlık, gölge yok.
      dialogTheme: DialogThemeData(
        backgroundColor: koyu ? T.dKart : Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        // Köşeler kartlarla aynı: diyalog da yüzen bir levha.
        shape: RoundedRectangleBorder(
          side: BorderSide(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(T.rCam),
        ),
        // Arka perde daha koyu: cam diyalog ancak arkası gerçekten
        // uzaklaşırsa öne çıkıyor.
        barrierColor: Colors.black.withValues(alpha: koyu ? 0.62 : 0.34),
        titleTextStyle: tt.titleLarge,
        contentTextStyle: tt.bodyMedium,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: koyu ? T.dKart : Colors.white,
        isDense: true,
        hintStyle: tt.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        contentPadding: const EdgeInsets.symmetric(horizontal: T.s3, vertical: T.s3),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(T.rGiris),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(T.rGiris),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(T.rGiris),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      // KAPSÜL. iOS 26'nın en görünür kararı bu: düğme yuvarlak bir hap,
      // köşeli bir kutu değil. 8 piksellik köşe "yazılım düğmesi" diye
      // okunuyor; tam yuvarlak olan, basılacak bir CİSİM gibi duruyor.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, T.minTouch),
          textStyle: tt.labelLarge,
          shape: const StadiumBorder(),
          // Mürekkep gittiğine göre basılı hâli bu anlatıyor.
          overlayColor: Colors.black.withValues(alpha: 0.12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, T.minTouch),
          textStyle: tt.labelLarge,
          side: BorderSide(color: scheme.outline),
          shape: const StadiumBorder(),
          overlayColor: scheme.onSurface.withValues(alpha: 0.07),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: tt.labelLarge,
          shape: const StadiumBorder(),
          overlayColor: scheme.primary.withValues(alpha: 0.09),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        labelStyle: tt.labelSmall,
        side: BorderSide(color: scheme.outlineVariant),
        backgroundColor: koyu ? T.dKart2 : T.zemin2,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: T.s3, vertical: 2),
      ),
      listTileTheme: ListTileThemeData(
        minVerticalPadding: T.s3,
        titleTextStyle: tt.bodyLarge,
        subtitleTextStyle: tt.bodySmall,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(T.rDugme)),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1, thickness: 1),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: koyu ? T.dKart : Colors.white,
        indicatorColor: koyu ? const Color(0xFF3A2429) : T.bordoSoft,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        height: 64,
        labelTextStyle: WidgetStatePropertyAll(tt.labelSmall?.copyWith(letterSpacing: 0)),
      ),
      // Ray da alt gezinme gibi KOYU BORDO — maketteki kenar çubuğunun
      // kendisi bu. Telefonda çubuk, tablette ray; ikisi de aynı bandı
      // kullanınca uygulamanın bir omurgası oluyor.
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.sidebar,
        indicatorColor: Colors.white.withValues(alpha: 0.12),
        selectedIconTheme: const IconThemeData(color: Colors.white, size: 22),
        unselectedIconTheme:
            IconThemeData(color: Colors.white.withValues(alpha: 0.72), size: 22),
        selectedLabelTextStyle: tt.labelSmall!.copyWith(
            color: Colors.white, letterSpacing: 0, fontWeight: FontWeight.w600),
        unselectedLabelTextStyle: tt.labelSmall!.copyWith(
            color: Colors.white.withValues(alpha: 0.72), letterSpacing: 0),
      ),
      // Bildirim şeridi YÜZER ve kapsüldür. Material'ın kenardan kenara
      // uzanan dikdörtgen şeridi ekranın altına yapışıyor ve yüzen cam
      // çubukla aynı dilde konuşmuyor.
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: koyu ? T.dKart2 : T.ink,
        contentTextStyle: tt.bodyMedium?.copyWith(
            color: koyu ? T.dInk : Colors.white),
        actionTextColor: koyu ? T.dBordo : T.bordoSoft,
        elevation: 6,
        insetPadding: const EdgeInsets.symmetric(horizontal: T.s3),
        shape: const StadiumBorder(),
      ),
      dataTableTheme: DataTableThemeData(
        headingTextStyle: tt.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
        dataTextStyle: tt.bodyMedium,
        dividerThickness: 1,
      ),
    );
  }
}

/// Semantik durum renkleri — sipariş, deneme ve ödeme durumlarında tutarlı.
extension AppStatusColors on ColorScheme {
  bool get _koyu => brightness == Brightness.dark;
  Color get basarili     => _koyu ? const Color(0xFF6FBF98) : T.basarili;
  Color get basariliSoft => _koyu ? const Color(0xFF1E3229) : T.basariliSoft;
  Color get uyari        => _koyu ? const Color(0xFFD9A441) : T.uyari;
  Color get uyariSoft    => _koyu ? const Color(0xFF33280F) : T.uyariSoft;
  Color get tehlike      => _koyu ? const Color(0xFFE38B82) : T.tehlike;
  Color get tehlikeSoft  => _koyu ? const Color(0xFF3A2422) : T.tehlikeSoft;
  Color get bilgi        => _koyu ? const Color(0xFF89B4CE) : T.bilgi;
  Color get bilgiSoft    => _koyu ? const Color(0xFF1C2A32) : T.bilgiSoft;
  /// Sidebar zemini — açık temada da koyu bordo kalır (tasarımdaki gibi).
  Color get sidebar      => _koyu ? const Color(0xFF150F11) : T.bordoKoyu;
}
