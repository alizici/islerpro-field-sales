import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:islerpro/shared/widgets/liste.dart';

/// Liste gövdesinin veri eşlemesi.
///
/// Buradaki tek soru: **tazeleme sırasında hata kayboluyor mu?** Riverpod,
/// yeniden yüklerken önceki değeri ya da hatayı `AsyncLoading`in içinde
/// taşıyor; `when` bunu varsayılan olarak görüyor ama `whenData` görmüyor.
/// Aradaki fark ekranda şuydu: ağ yokken cari listesi hatayı hiç
/// göstermiyor, sonsuza kadar iskelet çiziyordu.
class _Anahtar extends Notifier<int> {
  @override
  int build() => 0;
  void arttir() => state = state + 1;
}

final _anahtar = NotifierProvider<_Anahtar, int>(_Anahtar.new);

/// Her koşusunda düşen, bir anahtara bağlı sağlayıcı.
final _veri = FutureProvider<int>((ref) async {
  ref.watch(_anahtar);
  await Future<void>.delayed(const Duration(milliseconds: 10));
  throw Exception('ağ yok');
});

void main() {
  final hata = Exception('ağ yok');
  final iz = StackTrace.empty;

  group('esle', () {
    // Hâl ELLE KURULMUYOR: `copyWithPrevious` Riverpod'un iç API'si ve
    // "yeniden yükleme" biçimini elle üretmek, gerçekte ne olduğunu değil
    // ne olduğunu SANDIĞIMIZI test etmek olurdu. Bu yüzden gerçek bir
    // sağlayıcı, gerçekten hata verip gerçekten yeniden yükleniyor.
    test('yeniden yüklenirken taşınan HATA korunur', () async {
      final k = ProviderContainer();
      addTearDown(k.dispose);
      k.listen(_veri, (_, _) {});

      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(k.read(_veri).hasError, isTrue, reason: 'ilk deneme düşmeli');

      // Süzgeç değişti → sağlayıcı baştan koşuyor; Riverpod bu sırada
      // önceki hatayı yükleniyor hâlinin İÇİNDE taşıyor.
      k.read(_anahtar.notifier).arttir();
      final ara = k.read(_veri);
      expect(ara.isLoading, isTrue, reason: 'yeniden yükleme başlamış olmalı');

      expect(ara.esle((x) => '$x').hasError, isTrue,
          reason: 'hata yolda kaybolursa kullanıcı sonsuza kadar iskelet '
              'görür ve uygulamanın yüklendiğini sanır');

      // Kıyas: `whenData` aynı değerde hatayı DÜŞÜRÜYOR — `esle` bu yüzden
      // var. Bu satır kırılırsa Riverpod davranışı değişmiş demektir.
      expect(ara.whenData((x) => '$x').hasError, isFalse);
    });

    test('gerçekten boş yükleme yükleme kalır', () {
      expect(const AsyncLoading<int>().esle((x) => '$x').isLoading, isTrue);
    });

    test('veri ve hata olduğu gibi geçer', () {
      expect(const AsyncData(3).esle((x) => x + 1).value, 4);
      expect(AsyncError<int>(hata, iz).esle((x) => '$x').hasError, isTrue);
    });
  });
}
