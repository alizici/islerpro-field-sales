import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:islerpro/core/auth/session.dart';
import 'package:islerpro/core/test_keys.dart';
import 'package:islerpro/shared/widgets/parcalar.dart';
import 'package:islerpro/data/repositories/katalog_repository.dart';
import 'package:islerpro/data/repositories/talep_repository.dart';
import 'package:islerpro/features/requests/presentation/talep_detay_ekrani.dart';
import 'package:islerpro/features/requests/presentation/talep_olustur_ekrani.dart';
import 'package:islerpro/features/requests/presentation/talepler_ekrani.dart';

import 'sahte_depolar.dart';

/// Faz 3 · Talep akışı — ürünün kalbi.
/// En kritik davranış: K37 kısmi onay. 5 kalemin 3'ü onaylanıp 2'si
/// reddedilebilir; bekleyen kalem kalırsa talep KAPANMAZ.
void main() {
  Future<SahteTalepRepo> ac(WidgetTester t, Widget w,
      {SahteTalepRepo? repo, SahteKatalogRepo? katalog,
       AppRole rol = AppRole.pazarlamaci}) async {
    final r = repo ?? SahteTalepRepo();
    // Talep detayı uzun bir ListView; varsayılan 800×600'de alt bölümler hiç
    // KURULMAZ ve findsNothing yanıltıcı biçimde geçer. Masaüstü boyu veriyoruz.
    t.view.physicalSize = const Size(1000, 2200);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [
        talepRepositoryProvider.overrideWithValue(r),
        katalogRepositoryProvider.overrideWithValue(
            katalog ?? SahteKatalogRepo()),
        sessionProvider.overrideWithValue(testOturumu(rol: rol)),
      ],
      child: MaterialApp(home: w),
    ));
    await t.pumpAndSettle();
    return r;
  }

  VoidCallback? kararButonu(WidgetTester t) =>
      t.widget<FilledButton>(find.byKey(K.talepKararVer)).onPressed;

  group('gelen kutusu', () {
    testWidgets('talep özeti kalem ve adetle listelenir', (t) async {
      await ac(t, const TaleplerEkrani(),
          repo: SahteTalepRepo(talepler: [talep('Y Lisesi Kurumsal')]));

      expect(find.byKey(K.talepListesi), findsOneWidget);
      expect(find.text('Y Lisesi Kurumsal'), findsOneWidget);
      expect(find.textContaining('2 kalem'), findsOneWidget);
      expect(find.textContaining('42 adet'), findsOneWidget);
      expect(find.textContaining('Gönderildi'), findsOneWidget,
          reason: 'durum yalnızca renkle anlatılamaz — yazılı olmalı');
    });

    testWidgets('V7 · 24 saati geçen talep işaretlenir', (t) async {
      await ac(t, const TaleplerEkrani(), repo: SahteTalepRepo(talepler: [
        talep('Geciken Okul', id: 't1', gecikmis: true),
        talep('Yeni Okul', id: 't2'),
      ]));

      expect(find.text('24 saati geçti'), findsOneWidget,
          reason: 'SLA aşımı gelen kutusunda görünmeli');

      await t.tap(find.byKey(K.talepFiltreGecikmis));
      await t.pumpAndSettle();
      expect(find.text('Geciken Okul'), findsOneWidget);
      expect(find.text('Yeni Okul'), findsNothing);
    });

    testWidgets('incelemedeki talepte bekleyen kalem sayısı görünür', (t) async {
      await ac(t, const TaleplerEkrani(), repo: SahteTalepRepo(talepler: [
        talep('X Okulu', durum: 'incelemede', bekleyen: 3),
      ]));
      expect(find.text('3 kalem bekliyor'), findsOneWidget);
    });
  });

  group('Talep oluşturma', () {
    testWidgets('kaç kalem gönderildiği yetmez, YAKLAŞIK TUTAR da yazar',
        (t) async {
      // "Üç kalem gönderiyorum" demek kaç lira olduğunu söylemiyor. Kesin
      // iskonto sunucuda çözülüyor (K25) ama yaklaşık tutar sıfırdan iyidir.
      await ac(t, const TalepOlusturEkrani(),
          repo: SahteTalepRepo(muhatapListesi: const [
            Muhatap(id: 'c1', tip: 'kurum', unvan: 'Y Lisesi Kurumsal',
                storeId: 's1', kurumAd: 'Y Lisesi'),
          ]),
          katalog: SahteKatalogRepo(urunler: [
            urun('TYT Matematik', satisFiyat: 200, varsayilanIskonto: 0.25),
          ]));

      await t.enterText(find.byKey(K.talepUrunAra), 'TYT');
      await t.pump(const Duration(milliseconds: 400));
      await t.pumpAndSettle();
      await t.tap(find.text('TYT Matematik').last);
      await t.pumpAndSettle();

      // 200 × (1 − 0,25) × 1 = 150 ₺
      expect(find.textContaining('Yaklaşık ₺150,00'), findsOneWidget);
      expect(find.textContaining('kesin iskonto onaydan sonra'),
          findsOneWidget);
    });
  });

  group('K37 · kalem bazında karar', () {
    testWidgets('karar verilmeden buton kapalı', (t) async {
      await ac(t, const TalepDetayEkrani(talepId: 't1'),
          repo: SahteTalepRepo(detayKaydi: talepDetay(
              kalemler: [kalem('Matematik SB'), kalem('Türkçe SB', id: 'k2')])));

      expect(find.byKey(K.talepKalemler), findsOneWidget);
      expect(kararButonu(t), isNull);
      expect(find.textContaining('kısmi onay mümkündür'), findsOneWidget);
    });

    testWidgets('red gerekçesi olmadan kaydedilemez', (t) async {
      await ac(t, const TalepDetayEkrani(talepId: 't1'),
          repo: SahteTalepRepo(detayKaydi: talepDetay(
              kalemler: [kalem('Matematik SB')])));

      await t.tap(find.byKey(K.kalemRed('k1')));
      await t.pumpAndSettle();

      expect(find.byKey(K.redNedeni), findsOneWidget);
      expect(kararButonu(t), isNull);
      expect(find.textContaining('gerekçe zorunlu'), findsOneWidget);

      await t.enterText(find.byKey(K.redNedeni), 'Stokta yok');
      await t.pumpAndSettle();
      expect(kararButonu(t), isNotNull);
    });

    testWidgets('kısmi kararda talebin kapanmayacağı söylenir', (t) async {
      await ac(t, const TalepDetayEkrani(talepId: 't1'),
          repo: SahteTalepRepo(detayKaydi: talepDetay(kalemler: [
            kalem('Matematik SB', id: 'k1'),
            kalem('Türkçe SB', id: 'k2'),
            kalem('Fen SB', id: 'k3'),
          ])));

      await t.tap(find.byKey(K.kalemOnay('k1')));
      await t.pumpAndSettle();

      expect(find.textContaining('2 kalem sonraya kalıyor'), findsOneWidget);
      expect(find.textContaining('talep kapanmaz'), findsOneWidget,
          reason: 'K37 · bekleyen kalem varsa talep sonuçlanmaz');
    });

    testWidgets('kararlar depoya doğru gönderilir', (t) async {
      final repo = await ac(t, const TalepDetayEkrani(talepId: 't1'),
          repo: SahteTalepRepo(detayKaydi: talepDetay(kalemler: [
            kalem('Matematik SB', id: 'k1'),
            kalem('Türkçe SB', id: 'k2'),
          ])));

      await t.tap(find.byKey(K.kalemOnay('k1')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(K.kalemRed('k2')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(K.redNedeni), 'Bu dönem basılmıyor');
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(K.talepKararVer));
      await t.pumpAndSettle();
      await t.tap(find.byKey(K.talepKararVer));
      await t.pumpAndSettle();

      final k = repo.sonKararlar!;
      expect(k.length, 2);
      expect(k.firstWhere((x) => x.kalemId == 'k1').onay, isTrue);
      final red = k.firstWhere((x) => x.kalemId == 'k2');
      expect(red.onay, isFalse);
      expect(red.redNedeni, 'Bu dönem basılmıyor');
    });

    testWidgets('fiyatı olmayan kalem ONAYLANAMAZ', (t) async {
      await ac(t, const TalepDetayEkrani(talepId: 't1'),
          repo: SahteTalepRepo(detayKaydi: talepDetay(kalemler: [
            kalem('Fiyatsız Kitap', satisFiyat: null, satirTutari: null),
          ])));

      expect(find.textContaining('Fiyatı olmayan ürün onaylanamaz'),
          findsOneWidget);
      // Çip görünürde de kapalı: tıklanabilir görünüp hiçbir şey yapmayan
      // bir düğme kullanıcıya "bozuk" diye okunuyor.
      final onay = t.widget<SuzgecCipi>(find.byKey(K.kalemOnay('k1')));
      expect(onay.onTap, isNull);
    });

    testWidgets('sonuçlanmış talepte karar bölümü hiç çıkmaz', (t) async {
      await ac(t, const TalepDetayEkrani(talepId: 't1'),
          repo: SahteTalepRepo(detayKaydi: talepDetay(
              durum: 'karara_baglandi',
              kalemler: [kalem('Matematik SB', durum: 'onaylandi')])));

      expect(find.byKey(K.talepOzet), findsNothing);
      expect(find.textContaining('siparişe dönüşebilir'), findsOneWidget);
    });

    testWidgets('red gerekçesi sonradan da görünür', (t) async {
      await ac(t, const TalepDetayEkrani(talepId: 't1'),
          repo: SahteTalepRepo(detayKaydi: talepDetay(
              durum: 'karara_baglandi',
              kalemler: [kalem('Fen SB', durum: 'reddedildi',
                  redNedeni: 'Stokta yok')])));

      expect(find.text('Reddedildi'), findsOneWidget);
      expect(find.text('· Stokta yok'), findsOneWidget,
          reason: 'talebi açan kişi neden reddedildiğini görmeli');
    });
  });

  group('karar ekranındaki bağlam', () {
    testWidgets('K25 · iskontonun gerekçesi kalemde yazılı', (t) async {
      await ac(t, const TalepDetayEkrani(talepId: 't1'),
          repo: SahteTalepRepo(detayKaydi: talepDetay(
              kalemler: [kalem('Matematik SB')])));

      expect(find.textContaining('%20'), findsOneWidget);
      expect(find.textContaining('BES KURUMSAL ANLAŞMASI'), findsOneWidget,
          reason: '"neden %20?" sorusunun cevabı ekranda olmalı');
    });

    testWidgets('K11 · limit aşımı sipariş öncesi uyarır', (t) async {
      await ac(t, const TalepDetayEkrani(talepId: 't1'),
          repo: SahteTalepRepo(detayKaydi: talepDetay(
              bakiye: 40000, risk: 70000, limit: 60000,
              kalemler: [kalem('Matematik SB')])));

      expect(find.byKey(K.talepCariRisk), findsOneWidget);
      expect(find.textContaining('kardeş cariler etkilemez'), findsOneWidget);
      expect(find.textContaining('onaya düşer'), findsOneWidget);
    });

    testWidgets('K23 · eski baskı seçilmişse sessiz kalınmaz', (t) async {
      await ac(t, const TalepDetayEkrani(talepId: 't1'),
          repo: SahteTalepRepo(detayKaydi: talepDetay(kalemler: [
            kalem('Matematik SB', uyari: BaskiUyarisi(
                uyari: true,
                guncel: baski('2025-26', id: 'p2', satisFiyat: 329))),
          ])));

      expect(find.textContaining('2025-26 baskısı var'), findsOneWidget);
      expect(find.textContaining('329,00'), findsOneWidget);
    });
  });

  group('talep oluşturma', () {
    testWidgets('K5 · muhatap seçilmeden gönderilemez', (t) async {
      await ac(t, const TalepOlusturEkrani(),
          repo: SahteTalepRepo(muhatapListesi: [
            Muhatap(id: 'c1', tip: 'kurum', unvan: 'Y Lisesi Kurumsal',
                storeId: 's1', kurumAd: 'Y Lisesi'),
          ]));

      expect(find.byKey(K.talepMuhatap), findsOneWidget);
      expect(find.text('Kurumsal cari · Y Lisesi'), findsOneWidget);
      expect(t.widget<FilledButton>(find.byKey(K.talepGonder)).onPressed,
          isNull);
    });

    testWidgets('K36 · yalnızca katalogdan seçildiği yazılı', (t) async {
      await ac(t, const TalepOlusturEkrani());
      expect(find.textContaining('serbest metin yoktur'), findsOneWidget);
      expect(find.textContaining('Fiyatı olmayan ürün siparişe dönüşemez'),
          findsOneWidget);
    });

    testWidgets('K22 · adet önerisi kaynağıyla birlikte gelir', (t) async {
      final katalog = SahteKatalogRepo(urunler: [
        urun('Matematik SB', id: 'p1', satisFiyat: 100, varsayilanIskonto: 0.2),
      ]);
      final repo = SahteTalepRepo(
        muhatapListesi: [
          Muhatap(id: 'c1', tip: 'kurum', unvan: 'Y Lisesi', storeId: 's1'),
        ],
        oneri: const AdetOnerisi(adet: 120, kaynak: 'kurum_bildirdi',
            etiket: 'kurum bildirdi'),
      );
      await ac(t, const TalepOlusturEkrani(), repo: repo, katalog: katalog);

      await t.tap(find.text('Y Lisesi'));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(K.talepUrunAra), 'Mat');
      await t.pump(const Duration(milliseconds: 400));
      await t.pumpAndSettle();
      await t.tap(find.text('Matematik SB').last);
      await t.pumpAndSettle();

      // Rozet değil alt bilgi: "elle girildi" ile "kurum bildirdi" aynı
      // sayı olsa bile aynı güvenilirlikte değil (K22).
      expect(find.textContaining('kurum bildirdi'), findsOneWidget,
          reason: 'adetin nereden geldiği yazılı olmalı');

      await t.ensureVisible(find.byKey(K.talepGonder));
      await t.pumpAndSettle();
      await t.tap(find.byKey(K.talepGonder));
      await t.pumpAndSettle();

      expect(repo.sonCariId, 'c1');
      expect(repo.sonKalemler!.first.adet, 120,
          reason: 'öneri adet alanına yerleşmeli');
    });
  });
}
