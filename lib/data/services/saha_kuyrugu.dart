import 'dart:convert';
import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../local/yerel_db.dart';

/// **Sunucu CEVAP VERDİ Mİ?** — K43'ün tek ayrımı, hem yazma hem okuma için.
///
/// Cevap verip reddettiyse (kodlu `PostgrestException`) iş kuyruğa yazılmaz
/// ve yerel kopya da gösterilmez: aynı iş yarın da aynı cevabı alır, yetki
/// hatasını bayat veriyle örtmek onu görünmez yapar. Cevap hiç gelmediyse
/// (ağ yok, zaman aşımı) çevrimdışı yola geçilir.
///
/// `Error` türleri hiçbir koşulda çevrimdışı sayılmaz: onlar bizim kod
/// hatamızdır, sahada sessizce yutulmamalı.
bool sunucuyaUlasilamadi(Object e) =>
    e is! Error && !(e is PostgrestException && (e.code ?? '').isNotEmpty);

/// K43 · Sahada yazma yolu.
///
/// **Ayrım tek soruda kapanıyor: sunucu CEVAP VERDİ Mİ?**
/// Cevap verip reddettiyse (PostgrestException, kod dolu) iş kuyruğa
/// yazılmaz — aynı iş yarın da aynı cevabı alır, kullanıcıya hemen söylemek
/// gerekir. Cevap hiç gelmediyse (ağ yok, zaman aşımı) iş kuyruğa yazılır.
///
/// `Error` türleri her zaman yükselir: onlar bizim kod hatamızdır, sahada
/// sessizce kuyruğa girmemeli.
class SahaKuyrugu {
  const SahaKuyrugu(this.db);
  final YerelDb? db;

  static const acikZiyaretAnahtari = 'acik_ziyaret';
  static final _rastgele = Random.secure();

  bool get kullanilabilir => db != null;

  /// K43 · İdempotency anahtarı üretir.
  ///
  /// Anahtar **çevrimiçi denemede de** gönderilir: asıl tehlike ağın koptuğu
  /// an değil, sunucunun kaydı yazıp cevabın yolda kaybolduğu andır. O durumda
  /// iş kuyruğa girer ve senkronda ikinci kez gönderilir; aynı anahtarı gören
  /// sunucu yeni kayıt açmaz, ilkinin kimliğini döndürür. Anahtar yoksa aynı
  /// tahsilat iki kez yazılırdı.
  ///
  /// Rastgele son ek şart: anahtar `tenant` genelinde tekildir ve iki cihaz
  /// aynı mikrosaniyede yazabilir.
  static String anahtar(String onek) =>
      '$onek-${DateTime.now().microsecondsSinceEpoch}'
      '-${_rastgele.nextInt(1 << 32).toRadixString(36)}';

  /// [online] denenir. Sunucuya ULAŞILAMAZSA iş kuyruğa yazılır ve `null`
  /// döner. `null` "başarısız" demek değildir — "sonra yüklenecek" demektir.
  Future<T?> dene<T>(
    Future<T> Function() online, {
    required String fn,
    required Map<String, dynamic> args,
    required String ozet,
  }) async {
    try {
      return await online();
    } catch (e) {
      if (!sunucuyaUlasilamadi(e)) rethrow;
      final d = db;
      if (d == null) rethrow;   // web: kuyruk yok, hatayı gizleme
      await d.kuyrugaYaz(fn, args, ozet);
      return null;
    }
  }

  // ── Çevrimdışı açık ziyaret ──────────────────────────────────────────────
  //
  // Kuyruktaki `start_visit` henüz yüklenmediği için sunucunun bir açık
  // ziyareti yoktur; çubuk yine de görünmeli. Yerel kayıt bu boşluğu doldurur.
  //
  // Kapatma `visit_id: null` ile kuyruğa girer. Sunucuda `end_visit` boş
  // gelen id'yi AÇIK ZİYARETTEN çözer ve kuyruk sırayla işlendiği için o an
  // açık olan ziyaret, bir önceki işlemin açtığı ziyarettir. K43'ün
  // "çakışma yok, sıralama var" kuralı tam olarak buna dayanıyor.

  Future<void> yerelZiyaretAc(String kurumId, String kurumAd,
      DateTime girisSaati) async {
    await db?.ayarYaz(acikZiyaretAnahtari, jsonEncode({
      'institution_id': kurumId,
      'kurum_ad': kurumAd,
      'checked_in_at': girisSaati.toIso8601String(),
    }));
  }

  Future<Map<String, dynamic>?> yerelZiyaret() async {
    final s = await db?.ayarOku(acikZiyaretAnahtari);
    if (s == null || s.isEmpty) return null;
    return (jsonDecode(s) as Map).cast<String, dynamic>();
  }

  Future<void> yerelZiyaretKapat() async =>
      db?.ayarYaz(acikZiyaretAnahtari, '');
}
