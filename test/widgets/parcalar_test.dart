import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:islerpro/shared/widgets/detay.dart';
import 'package:islerpro/shared/widgets/parcalar.dart';

/// Bileşen kitaplığının kendi testleri.
///
/// Buradaki her sınama, ekranda GÖZLE görülen bir hatadan doğdu: bileşen
/// derleniyor, testler geçiyor ama ekranda hiçbir şey yok. Widget testi
/// "var mı" diye sorarsa yakalayamıyor; "kaç piksel" diye sorması gerekiyor.
void main() {
  Future<void> ac(WidgetTester t, Widget w) => t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(padding: const EdgeInsets.all(16), child: w),
          ),
        ),
      );

  group('OranSeridi', () {
    testWidgets('şerit GERÇEKTEN çizilir — yüksekliği sıfır değildir',
        (t) async {
      await ac(
        t,
        const OranSeridi([
          ('Bitti', 3, Colors.green),
          ('Kalan', 7, Colors.grey),
        ], kalinlik: 7),
      );

      // Row'un varsayılan `center` hizası çocuksuz ColoredBox'a gevşek dikey
      // kısıt veriyordu ve kutu sıfır yükseklik alıyordu. Şerit aylarca
      // görünmez kaldı; "bileşen var" demek "çiziliyor" demek değil.
      final dilim = find.descendant(
          of: find.byType(OranSeridi), matching: find.byType(ColoredBox));
      expect(dilim, findsNWidgets(2), reason: 'iki dolu dilim çizilmeli');
      for (var i = 0; i < 2; i++) {
        expect(t.getSize(dilim.at(i)).height, 7,
            reason: 'dilim şeridin kalınlığını almalı');
      }
    });

    testWidgets('dilimler değerleriyle ORANTILI genişler', (t) async {
      await ac(
        t,
        const OranSeridi([
          ('Az', 1, Colors.green),
          ('Çok', 9, Colors.red),
        ], kalinlik: 6, etiketler: false),
      );

      final kutular = find.descendant(
          of: find.byType(OranSeridi), matching: find.byType(ColoredBox));
      final az = t.getSize(kutular.at(0)).width;
      final cok = t.getSize(kutular.at(1)).width;
      expect(cok / az, closeTo(9, 0.3),
          reason: 'oran şeridi oranı göstermezse yalnızca renkli bir çizgidir');
    });

    testWidgets('değeri sıfır olan dilim hiç çizilmez', (t) async {
      await ac(
        t,
        const OranSeridi([
          ('Var', 5, Colors.green),
          ('Yok', 0, Colors.red),
        ], etiketler: false),
      );
      expect(
          find.descendant(
              of: find.byType(OranSeridi), matching: find.byType(ColoredBox)),
          findsOneWidget);
    });

    testWidgets('toplam sıfırsa şerit hiç yer kaplamaz', (t) async {
      await ac(t, const OranSeridi([('Yok', 0, Colors.red)]));
      expect(t.getSize(find.byType(OranSeridi)).height, 0);
    });

    testWidgets('zemin tonundaki dilimin sayısı yine OKUNUR', (t) async {
      // "Kalan" dilimi zemin tonunda çiziliyor; sayısı da o renkle yazılınca
      // cari detayındaki "Kalan limit 32b" zeminde kayboluyordu.
      await ac(t, Builder(builder: (c) {
        final s = Theme.of(c).colorScheme;
        return OranSeridi([
          ('Limit içinde', 118000, s.primary),
          ('Kalan limit', 32000, s.surfaceContainerHigh),
        ]);
      }));
      final s = Theme.of(t.element(find.byType(OranSeridi))).colorScheme;

      Color sayiRengi(String etiket) {
        final metin = t.widget<Text>(find.byWidgetPredicate((w) =>
            w is Text &&
            (w.textSpan?.toPlainText().startsWith(etiket) ?? false)));
        final parcalar = (metin.textSpan! as TextSpan).children!;
        return (parcalar.last as TextSpan).style!.color!;
      }

      expect(sayiRengi('Kalan limit'), s.onSurfaceVariant,
          reason: 'zemin tonunda yazılan sayı okunmaz');
      expect(sayiRengi('Limit içinde'), s.primary,
          reason: 'okunan dilim rengi sayıda da kalır');
    });
  });

  /// Telefon genişliğinde (390 nokta) DÜZEN — bu hatalar ancak ekran
  /// görüntüsünde göründü; geniş test penceresinde hepsi tek satıra sığıyordu.
  group('Detay bandı · dar ekran', () {
    Future<void> telefonda(WidgetTester t, Widget w) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await ac(t, SingleChildScrollView(child: w));
    }

    testWidgets('baskın tutar iki satıra BÖLÜNMEZ', (t) async {
      await telefonda(
        t,
        const DetayBandi(
          baslik: 'Yeşiltepe Lisesi Kurumsal',
          etiket: 'Sipariş tutarı',
          deger: '₺86.984,00',
          yanlar: [
            ('Kalem', '5', null),
            ('Sevk edilmeyen', '125 adet', null),
          ],
        ),
      );
      // Yan ölçüler yer kaplayınca tutar "₺86.984,0" / "0" diye kırılıyordu.
      expect(t.getSize(find.text('₺86.984,00')).height, lessThan(28 * 2),
          reason: 'tutar tek satırda kalmalı; sığmıyorsa küçülür');
    });

    testWidgets('aşama etiketi harf harf BÖLÜNMEZ', (t) async {
      await telefonda(
        t,
        const AsamaCizgisi(
          asamalar: ['Oluştu', 'Hazırlanıyor', 'Hazır', 'Sevk', 'Teslim'],
          aktif: 3,
        ),
      );
      // Beş sütunda "Hazırlanıyor" sığmıyor ve "Hazırlanıyo" / "r" oluyordu.
      // Eşik bir buçuk satır: tek satır ~12,6, iki satır ~26 nokta.
      expect(t.getSize(find.text('Hazırlanıyor')).height,
          lessThan(10.5 * 1.2 * 1.5),
          reason: 'tek kelimelik etiket tek satırda kalmalı');
    });
  });

  group('SuzgecCipi', () {
    testWidgets('onTap null ise çip görünürde de kapalıdır', (t) async {
      await ac(
        t,
        const Row(children: [
          SuzgecCipi(etiket: 'Kapalı', secili: false, onTap: null),
        ]),
      );
      // Kapalı çip InkWell kurmaz: tıklanabilir görünüp hiçbir şey
      // yapmayan bir düğme kullanıcıya "bozuk" diye okunuyor.
      expect(
          find.descendant(
              of: find.byType(SuzgecCipi), matching: find.byType(InkWell)),
          findsNothing);
    });
  });
}
