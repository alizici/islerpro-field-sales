import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session.dart';
import '../../../data/local/yerel_saglayici.dart';
import '../../sync/presentation/senkron_durumu.dart';
import '../../../data/repositories/ziyaret_repository.dart';

/// Açık ziyaret. Kabuk her ekranda bunu izler — ziyaret açıkken kullanıcı
/// hangi ekranda olursa olsun çubuğu görür ve kapatmayı unutmaz.
final acikZiyaretProvider = FutureProvider<AcikZiyaret?>((ref) async {
  final o = ref.watch(sessionProvider);
  if (o == null) return null;
  // K43 · Çevrimdışı açılan ziyaret sunucuda YOKTUR; çubuk yine de görünmeli.
  // Yerel kayıt sunucununkini ezer: kuyruk yüklenene kadar doğru olan odur.
  final yerel = await ref.watch(sahaKuyruguProvider).yerelZiyaret();
  if (yerel != null) return AcikZiyaret.yerelKayit(yerel);
  return ref.watch(ziyaretRepositoryProvider).acikZiyaret();
});

/// Gün rotası. `null` bugün demektir.
final rotaProvider =
    FutureProvider.autoDispose.family<Rota, DateTime?>((ref, tarih) {
  final o = ref.watch(sessionProvider);
  if (o == null) return Future.value(const Rota());
  return ref.watch(ziyaretRepositoryProvider).rota(tarih: tarih);
});

/// K10 · "Bugün nereye gitmeliyim" — her satır gerekçesini taşır.
final rotaOnerisiProvider = FutureProvider.autoDispose<List<RotaOneri>>((ref) {
  final o = ref.watch(sessionProvider);
  if (o == null) return Future.value(const []);
  return ref.watch(ziyaretRepositoryProvider).oneri();
});

final ziyaretDetayProvider =
    FutureProvider.autoDispose.family<ZiyaretDetay, String>(
        (ref, id) => ref.watch(ziyaretRepositoryProvider).detay(id));

/// Ziyaret geçmişi. [userId] null ise dükkanın tamamı (sahip görünümü).
typedef ZiyaretFiltre = ({String? userId, String? kurumId, int gun});

final ziyaretlerProvider =
    FutureProvider.autoDispose.family<List<ZiyaretOzet>, ZiyaretFiltre>(
        (ref, f) {
  final o = ref.watch(sessionProvider);
  if (o?.storeId == null) return Future.value(const []);
  return ref.watch(ziyaretRepositoryProvider).liste(
      storeId: o!.storeId, userId: f.userId, kurumId: f.kurumId, gun: f.gun);
});

final ziyaretPerformansProvider =
    FutureProvider.autoDispose<List<ZiyaretPerformans>>((ref) {
  final o = ref.watch(sessionProvider);
  if (o?.storeId == null) return Future.value(const []);
  return ref.watch(ziyaretRepositoryProvider)
      .performans(o!.storeId!, periodId: o.periodId);
});

/// Ziyaretle ilgili her şey tazelenir. Ziyaret açmak/kapatmak rotayı,
/// öneriyi ve listeyi aynı anda etkiler — üçünü ayrı ayrı hatırlamak yerine
/// tek yerden yapılır.
void ziyaretTazele(Ref ref) {
  ref.invalidate(acikZiyaretProvider);
  ref.invalidate(rotaProvider);
  ref.invalidate(rotaOnerisiProvider);
  ref.invalidate(ziyaretlerProvider);
  // Çevrimdışı yazma kuyruğa düşmüş olabilir; uyarı hemen görünsün.
  ref.invalidate(bekleyenSayisiProvider);
}

void ziyaretTazeleW(WidgetRef ref) {
  ref.invalidate(acikZiyaretProvider);
  ref.invalidate(rotaProvider);
  ref.invalidate(rotaOnerisiProvider);
  ref.invalidate(ziyaretlerProvider);
  ref.invalidate(bekleyenSayisiProvider);
}
