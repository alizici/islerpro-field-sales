import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Mobil ve masaüstü: belgeler klasörüne yazar, yolu döndürür.
Future<String> dosyaIndir(Uint8List veri, String ad,
    {String? mime}) async {
  final dizin = await getApplicationDocumentsDirectory();
  final yol = p.join(dizin.path, ad);
  await File(yol).writeAsBytes(veri, flush: true);
  return yol;
}
