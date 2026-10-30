import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../local/yerel_db.dart';

/// K42 · Cihaz kimliği.
///
/// `client_id` bir SIR DEĞİLDİR — idempotency anahtarının yarısıdır (K43).
/// Bu yüzden yerel veritabanında durur: uygulama silinip yeniden kurulursa
/// yeni kimlik alınır, ki bu doğrudur — o kurulumda bekleyen kuyruk da yoktur.
class CihazKimligi {
  CihazKimligi(this._db);
  final YerelDb _db;

  static const _anahtar = 'client_id';

  Future<String> id() async {
    final mevcut = await _db.ayarOku(_anahtar);
    if (mevcut != null && mevcut.isNotEmpty) return mevcut;
    final r = Random.secure();
    final yeni = List.generate(16, (_) => r.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    await _db.ayarYaz(_anahtar, yeni);
    return yeni;
  }

  /// Sahibin cihaz listesinde okunacak ad. Model bilgisi toplamıyoruz —
  /// platform ve sürüm "hangi cihazı iptal ediyorum" sorusuna yetiyor.
  static String ad() => switch (defaultTargetPlatform) {
        TargetPlatform.iOS => 'iPhone / iPad',
        TargetPlatform.android => 'Android',
        TargetPlatform.macOS => 'Mac',
        TargetPlatform.windows => 'Windows',
        TargetPlatform.linux => 'Linux',
        _ => 'Tarayıcı',
      };

  static String platform() =>
      kIsWeb ? 'web' : defaultTargetPlatform.name;
}

/// Kuyruk satırının sunucuya giden hâli.
Map<String, dynamic> kuyrukOp(int localSeq, String fn, String argsJson) => {
      'local_seq': localSeq,
      'fn': fn,
      'args': jsonDecode(argsJson),
    };
