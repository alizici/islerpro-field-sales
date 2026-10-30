import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session.dart';
import '../../../data/local/sifreleme.dart';
import '../../../data/local/yerel_db.dart';
import '../../../data/local/yerel_saglayici.dart';
import '../../../data/repositories/senkron_repository.dart';
import '../../../data/services/senkron.dart';
import '../../../data/services/yerel_referans.dart';

export '../../../data/local/yerel_saglayici.dart' show yerelDbProvider;

final senkronServisiProvider = Provider<SenkronServisi?>((ref) {
  final db = ref.watch(yerelDbProvider);
  final store = ref.watch(sessionProvider)?.storeId;
  if (db == null || store == null) return null;
  return SenkronServisi(
      db: db, repo: ref.watch(senkronRepositoryProvider), storeId: store);
});

final bekleyenSayisiProvider = FutureProvider<int>((ref) async {
  final db = ref.watch(yerelDbProvider);
  if (db == null) return 0;
  return db.bekleyenSayisi();
});

final kuyrukProvider = FutureProvider.autoDispose<List<KuyrukData>>((ref) async {
  final db = ref.watch(yerelDbProvider);
  if (db == null) return const [];
  return db.bekleyenler();
});

final cihazlarProvider = FutureProvider.autoDispose<List<CihazSatiri>>(
    (ref) => ref.watch(senkronRepositoryProvider).cihazlar());

class SenkronDurum {
  const SenkronDurum({this.calisiyor = false, this.rapor, this.hata,
                      this.sonZaman});
  final bool calisiyor;
  final SenkronRaporu? rapor;
  final String? hata;
  final DateTime? sonZaman;

  SenkronDurum kopya({bool? calisiyor, SenkronRaporu? rapor, String? hata,
                      DateTime? sonZaman, bool hatayiTemizle = false}) =>
      SenkronDurum(
        calisiyor: calisiyor ?? this.calisiyor,
        rapor: rapor ?? this.rapor,
        hata: hatayiTemizle ? null : (hata ?? this.hata),
        sonZaman: sonZaman ?? this.sonZaman,
      );
}

class SenkronN extends Notifier<SenkronDurum> {
  @override
  SenkronDurum build() => const SenkronDurum();

  Future<void> calistir({bool katalog = true}) async {
    final s = ref.read(senkronServisiProvider);
    if (s == null || state.calisiyor) return;
    state = state.kopya(calisiyor: true, hatayiTemizle: true);
    try {
      final r = await s.calistir(katalog: katalog);
      state = SenkronDurum(rapor: r, sonZaman: DateTime.now());
    } catch (e) {
      state = state.kopya(calisiyor: false, hata: _temiz(e.toString()));
    }
    ref.invalidate(bekleyenSayisiProvider);
    ref.invalidate(kuyrukProvider);
    // Cihazdaki kopya senkronla DEĞİŞTİ: sayım tazelenmezse ekran eşitlemeden
    // önceki hâli göstermeye devam eder — "boş" yazan bir kopya dolu olur.
    ref.invalidate(yerelKopyaSayilariProvider);
    ref.invalidate(yerelReferansTarihiProvider);
  }

  static String _temiz(String m) {
    final i = m.indexOf('message: ');
    if (i >= 0) return m.substring(i + 9).split(', code:').first;
    return m.replaceFirst('Bad state: ', '').replaceFirst('Exception: ', '');
  }
}

final senkronProvider =
    NotifierProvider<SenkronN, SenkronDurum>(SenkronN.new);

/// K42 · Cihaz güvenliğinin GERÇEK durumu.
///
/// "Şifreli" yazan ama şifrelemeyen bir uygulama hiç şifrelemeyenden daha
/// tehlikelidir. Bu yüzden değer bir bayraktan değil DİSKTEKİ DOSYADAN
/// okunuyor.
final guvenlikDurumuProvider =
    FutureProvider.autoDispose<SifrelemeDurumu>((ref) async {
  final db = ref.watch(yerelDbProvider);
  if (db == null) return SifrelemeDurumu.veriYok;
  // Ölçüm anlamlı olsun diye önce bir yazma yapılıp dosya oluşturulur.
  await db.ayarYaz('guvenlik_olcumu', DateTime.now().toIso8601String());
  return sifrelemeOlc();
});
