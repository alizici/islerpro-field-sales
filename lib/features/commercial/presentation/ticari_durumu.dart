import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session.dart';
import '../../../data/repositories/ticari_repository.dart';

/// Faz 8 sağlayıcıları tek yerde: çek durumu değişince hem takvim hem
/// konsinye hem cari bakiyesi etkilenir. Üçünü ayrı ayrı hatırlamak yerine
/// `ticariTazele` bir kez çağrılıyor.
final vadeTakvimiProvider = FutureProvider.autoDispose<VadeTakvimi>((ref) {
  final o = ref.watch(sessionProvider);
  if (o?.storeId == null) return Future.value(const VadeTakvimi());
  return ref.watch(ticariRepositoryProvider).vadeTakvimi(o!.storeId!);
});

final konsinyeCarilerProvider =
    FutureProvider.autoDispose<List<KonsinyeCari>>((ref) {
  final o = ref.watch(sessionProvider);
  if (o?.storeId == null) return Future.value(const []);
  return ref.watch(ticariRepositoryProvider).konsinyeCariler(o!.storeId!);
});

final konsinyeDetayProvider =
    FutureProvider.autoDispose.family<List<KonsinyeKalemi>, String>(
        (ref, cariId) =>
            ref.watch(ticariRepositoryProvider).konsinyeDetay(cariId));

final iadeEdilebilirProvider =
    FutureProvider.autoDispose.family<List<IadeKalemi>, String>(
        (ref, cariId) =>
            ref.watch(ticariRepositoryProvider).iadeEdilebilirler(cariId));

void ticariTazele(WidgetRef ref) {
  ref.invalidate(vadeTakvimiProvider);
  ref.invalidate(konsinyeCarilerProvider);
  ref.invalidate(konsinyeDetayProvider);
  ref.invalidate(iadeEdilebilirProvider);
}
