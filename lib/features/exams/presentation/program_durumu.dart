import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session.dart';
import '../../../data/repositories/deneme_repository.dart';

final programlarProvider =
    FutureProvider.autoDispose<List<ProgramOzeti>>((ref) {
  final o = ref.watch(sessionProvider);
  if (o?.storeId == null) return Future.value(const []);
  return ref.watch(denemeRepositoryProvider).programlar(o!.storeId!);
});

final programDetayProvider =
    FutureProvider.autoDispose.family<DenemeProgrami, String>((ref, id) =>
        ref.watch(denemeRepositoryProvider).programDetay(id));

final donemOzetiProvider = FutureProvider.autoDispose<DonemOzeti>((ref) {
  final o = ref.watch(sessionProvider);
  if (o?.storeId == null) return Future.value(const DonemOzeti());
  return ref.watch(denemeRepositoryProvider)
      .donemOzeti(o!.storeId!, periodId: o.periodId);
});

/// Program değişince hem liste hem detay hem dönem özeti etkilenir.
void programTazele(WidgetRef ref, [String? programId]) {
  ref.invalidate(programlarProvider);
  ref.invalidate(donemOzetiProvider);
  if (programId != null) ref.invalidate(programDetayProvider(programId));
}
