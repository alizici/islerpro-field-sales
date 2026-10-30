import 'dart:typed_data';

export 'dosya_indir_io.dart'
    if (dart.library.js_interop) 'dosya_indir_web.dart';

/// Üretilen Excel'i kullanıcıya verir.
/// Web'de tarayıcı indirmesi, mobil/masaüstünde belgeler klasörü.
typedef DosyaIndirici = Future<String> Function(
    Uint8List veri, String ad, {String? mime});
