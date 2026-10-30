import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session.dart';
import '../../../data/repositories/rapor_repository.dart';

/// Bir raporun o anki kurulumu: kırılım + süzgeç + sıralama.
///
/// Kaydedilmiş rapor (K50 §1.3) tam olarak bu nesnedir; ekranda kurulan şeyle
/// saklanan şeyin aynı olması, "kaydettiğim rapor açılınca farklı çıkıyor"
/// sınıfı hataları baştan imkânsız kılıyor.
class RaporKurulumu {
  const RaporKurulumu({
    this.kirilim = const [],
    this.filtreler = const {},
    this.sirala,
    this.artan = false,
  });

  final List<String> kirilim;
  final Map<String, dynamic> filtreler;
  final String? sirala;
  final bool artan;

  RaporKurulumu kopya({
    List<String>? kirilim, Map<String, dynamic>? filtreler,
    Object? sirala = _yok, bool? artan,
  }) =>
      RaporKurulumu(
        kirilim: kirilim ?? this.kirilim,
        filtreler: filtreler ?? this.filtreler,
        sirala: sirala == _yok ? this.sirala : sirala as String?,
        artan: artan ?? this.artan,
      );

  RaporKurulumu suzgec(String anahtar, Object? deger) {
    final y = Map<String, dynamic>.from(filtreler);
    if (deger == null) {
      y.remove(anahtar);
    } else {
      y[anahtar] = deger;
    }
    return kopya(filtreler: y);
  }

  static const _yok = Object();
}

class RaporKurulumN extends Notifier<RaporKurulumu> {
  @override
  RaporKurulumu build() => const RaporKurulumu();
  void ayarla(RaporKurulumu k) => state = k;
  void sirala(String olcu) => state = state.sirala == olcu
      ? state.kopya(artan: !state.artan)
      : state.kopya(sirala: olcu, artan: false);
}

final raporKurulumProvider =
    NotifierProvider<RaporKurulumN, RaporKurulumu>(RaporKurulumN.new,
        isAutoDispose: true);

final raporKatalogProvider = FutureProvider.autoDispose<List<RaporTanimi>>(
    (ref) => ref.watch(raporRepositoryProvider).katalog());

final raporSonucProvider =
    FutureProvider.autoDispose.family<RaporSonucu, String>((ref, kod) {
  final o = ref.watch(sessionProvider);
  final k = ref.watch(raporKurulumProvider);
  if (o?.storeId == null) {
    return Future.value(const RaporSonucu(kod: '', ad: ''));
  }
  return ref.watch(raporRepositoryProvider).calistir(
        kod: kod, storeId: o!.storeId!,
        kirilim: k.kirilim, filtreler: k.filtreler,
        sirala: k.sirala, artan: k.artan,
      );
});

final kayitliRaporlarProvider =
    FutureProvider.autoDispose<List<KayitliRapor>>((ref) {
  final o = ref.watch(sessionProvider);
  if (o?.storeId == null) return Future.value(const <KayitliRapor>[]);
  return ref.watch(raporRepositoryProvider).kayitlilar(o!.storeId!);
});
