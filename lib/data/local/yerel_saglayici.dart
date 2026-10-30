import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/saha_kuyrugu.dart';
import 'yerel_db.dart';

/// Yerel veritabanı. Web'de YOKTUR (bkz. `ac_stub.dart`): tarayıcı sekmesi
/// sahadaki çevrimdışı senaryosu değildir, sqlite WASM'ı taşımak yerine
/// kuyruk orada kapatılır ve ekran bunu açıkça söyler.
final yerelDbProvider = Provider<YerelDb?>((ref) {
  if (kIsWeb) return null;
  final db = YerelDb();
  ref.onDispose(db.close);
  return db;
});

final sahaKuyruguProvider =
    Provider<SahaKuyrugu>((ref) => SahaKuyrugu(ref.watch(yerelDbProvider)));
