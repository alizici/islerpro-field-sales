import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session.dart';
import '../../../data/repositories/deneme_repository.dart';

/// Takvim süzgeçleri. Ekran durumu değil, SORGUNUN parçası: ay değişince
/// sunucudan yeni veri gelir, süzgeç aynı kalır.
class TakvimFiltre {
  const TakvimFiltre({required this.ay, this.eksen = 'stok', this.kademe,
                      this.turu, this.sadecePortfoy = false});
  final DateTime ay;
  final String eksen;
  final String? kademe, turu;
  final bool sadecePortfoy;

  TakvimFiltre kopya({DateTime? ay, String? eksen, String? kademe,
                      String? turu, bool? sadecePortfoy,
                      bool kademeTemizle = false, bool turTemizle = false}) =>
      TakvimFiltre(
        ay: ay ?? this.ay,
        eksen: eksen ?? this.eksen,
        kademe: kademeTemizle ? null : (kademe ?? this.kademe),
        turu: turTemizle ? null : (turu ?? this.turu),
        sadecePortfoy: sadecePortfoy ?? this.sadecePortfoy,
      );

  @override
  bool operator ==(Object other) =>
      other is TakvimFiltre && other.ay == ay && other.eksen == eksen &&
      other.kademe == kademe && other.turu == turu &&
      other.sadecePortfoy == sadecePortfoy;

  @override
  int get hashCode => Object.hash(ay, eksen, kademe, turu, sadecePortfoy);
}

class FiltreN extends Notifier<TakvimFiltre> {
  @override
  TakvimFiltre build() {
    final n = DateTime.now();
    return TakvimFiltre(ay: DateTime(n.year, n.month));
  }

  void ayDegistir(int adim) {
    final a = state.ay;
    state = state.kopya(ay: DateTime(a.year, a.month + adim));
  }

  void eksen(String e) => state = state.kopya(eksen: e);
  void kademe(String? k) =>
      state = state.kopya(kademe: k, kademeTemizle: k == null);
  void turu(String? t) => state = state.kopya(turu: t, turTemizle: t == null);
  void portfoy(bool v) => state = state.kopya(sadecePortfoy: v);
}

final takvimFiltreProvider =
    NotifierProvider<FiltreN, TakvimFiltre>(FiltreN.new);

final denemeTakvimiProvider = FutureProvider.autoDispose<DenemeTakvimi>((ref) {
  final o = ref.watch(sessionProvider);
  final f = ref.watch(takvimFiltreProvider);
  if (o?.storeId == null) return Future.value(const DenemeTakvimi());
  return ref.watch(denemeRepositoryProvider).takvim(
      o!.storeId!, ay: f.ay, eksen: f.eksen, kademe: f.kademe,
      turu: f.turu, sadecePortfoy: f.sadecePortfoy);
});

/// Ana sayfa şeridi: yaklaşan stok tarihleri + sabit tarihli Türkiye Geneli.
final yaklasanDenemelerProvider =
    FutureProvider.autoDispose<List<Deneme>>((ref) {
  final o = ref.watch(sessionProvider);
  if (o?.storeId == null) return Future.value(const []);
  return ref.watch(denemeRepositoryProvider).yaklasanlar(o!.storeId!);
});

final denemeHedefleriProvider =
    FutureProvider.autoDispose.family<List<DenemeHedefi>, String>(
        (ref, denemeId) {
  final o = ref.watch(sessionProvider);
  if (o?.storeId == null) return Future.value(const []);
  return ref.watch(denemeRepositoryProvider).hedefler(denemeId, o!.storeId!);
});

final mevcutlarProvider =
    FutureProvider.autoDispose.family<Mevcutlar, String>((ref, cariId) =>
        ref.watch(denemeRepositoryProvider).mevcutlar(cariId));
