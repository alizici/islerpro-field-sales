import 'dart:async';
import 'package:intl/date_symbol_data_local.dart';

/// Tüm testlerden önce bir kez çalışır (Flutter test altyapısı bunu tanır).
/// Fmt.tarih 'tr_TR' yerel verisi olmadan çalışamaz — main.dart bunu yapıyor,
/// testlerin de aynı ön koşulu sağlaması gerekiyor.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await initializeDateFormatting('tr_TR');
  await testMain();
}
