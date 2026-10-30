import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Web: blob üretip görünmez bir bağlantıyı tıklar — tarayıcı indirir.
Future<String> dosyaIndir(Uint8List veri, String ad, {String? mime}) async {
  final blob = web.Blob(
    [veri.toJS].toJS,
    web.BlobPropertyBag(
        type: mime ??
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'),
  );
  final url = web.URL.createObjectURL(blob);
  final a = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = ad;
  web.document.body!.appendChild(a);
  a.click();
  a.remove();
  web.URL.revokeObjectURL(url);
  return ad;
}
