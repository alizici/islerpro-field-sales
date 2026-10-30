/// K42 · Yerel verinin şifreleme durumu.
///
/// Bu dosya BİLEREK platformdan bağımsız: `dart:io` içeren bir dosyayı koşullu
/// içe aktarmayla tip kaynağı yapmak analiz ile derleme arasında ayrışıyordu
/// (analiz geçiyor, derleyici "tip değil" diyordu). Tip burada duruyor, ölçümü
/// yapan işlev ise açılışta yerine konuyor.
enum SifrelemeDurumu {
  /// Henüz hiçbir şey yazılmamış — "şifresiz" demek yanlış olurdu.
  veriYok,

  /// Dosya düz sqlite: veri korumasız.
  sifresiz,

  /// Dosya başlığı bile okunamıyor.
  sifreli,
}

/// Varsayılan web/test davranışı: yerel dosya yok, ölçecek bir şey de yok.
/// Native açılışta (`ac_native.dart`) gerçek ölçümle değiştirilir.
Future<SifrelemeDurumu> Function() sifrelemeOlc =
    () async => SifrelemeDurumu.veriYok;
