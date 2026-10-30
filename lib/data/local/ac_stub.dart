import 'package:drift/drift.dart';

/// Web'de yerel veritabanı YOKTUR. Tarayıcı sekmesi sahadaki offline senaryosu
/// değildir; sqlite WASM'ı taşımak yerine kuyruk özelliği o platformda
/// kapatılır ve ekran bunu açıkça söyler.
///
/// Şifreleme ölçümü de burada yok: `sifreleme.dart`'taki varsayılan
/// "veri yok" cevabı web için zaten doğru.
QueryExecutor yerelDosya() =>
    throw UnsupportedError('Yerel veritabanı bu platformda yok');

bool get yerelDbVar => false;
