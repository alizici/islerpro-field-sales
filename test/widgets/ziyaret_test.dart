import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:islerpro/core/auth/session.dart';
import 'package:islerpro/core/test_keys.dart';
import 'package:islerpro/data/local/yerel_saglayici.dart';
import 'package:islerpro/data/repositories/siparis_repository.dart';
import 'package:islerpro/data/repositories/talep_repository.dart';
import 'package:islerpro/data/repositories/ziyaret_repository.dart';
import 'package:islerpro/features/dashboard/presentation/bugun_ekrani.dart';
import 'package:islerpro/features/visits/presentation/rota_ekrani.dart';
import 'package:islerpro/features/visits/presentation/ziyaret_cubugu.dart';
import 'package:islerpro/features/visits/presentation/ziyaret_detay_ekrani.dart';

import 'sahte_depolar.dart';

/// Saha modülü (Faz 7).
///
/// Buradaki testlerin ortak derdi tek bir kural: **K10 · ziyaretin ölçüsü
/// çıktısıdır.** Çıktısı sıfır olan ziyaret gizlenmemeli, öneri listesindeki
/// her satır neden orada olduğunu söylemeli, açık ziyaret gözden kaçmamalı.
void main() {
  Future<SahteZiyaretRepo> ac(WidgetTester t, Widget w,
      {SahteZiyaretRepo? repo, AppRole rol = AppRole.pazarlamaci}) async {
    final r = repo ?? SahteZiyaretRepo();
    t.view.physicalSize = const Size(1000, 2400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [
        ziyaretRepositoryProvider.overrideWithValue(r),
        siparisRepositoryProvider.overrideWithValue(SahteSiparisRepo()),
        talepRepositoryProvider.overrideWithValue(SahteTalepRepo()),
        sessionProvider.overrideWithValue(testOturumu(rol: rol)),
        // Widget testinde dosya sistemi yok; yerel veritabanı
        // web'deki gibi kapalı çalışır (bkz. ac_stub.dart).
        yerelDbProvider.overrideWithValue(null),
      ],
      child: MaterialApp(home: w),
    ));
    await t.pumpAndSettle();
    return r;
  }

  group('Rota · duraklar', () {
    testWidgets('durak yoksa nereden ekleneceği söylenir', (t) async {
      await ac(t, const RotaEkrani());
      expect(find.byKey(K.rotaDuraklar), findsOneWidget);
      expect(find.textContaining('önerilerden durak ekle'), findsOneWidget);
    });

    testWidgets('durak satırı kurumdaki işi yanında taşır', (t) async {
      await ac(t, const RotaEkrani(),
          repo: SahteZiyaretRepo(rotaKaydi: Rota(planlanan: 2, tamamlanan: 1,
              duraklar: [
                durak('Fatih Anadolu Lisesi',
                    borc: 8400, talep: 2, hazir: 1, amac: 'tahsilat'),
                durak('Barış Ortaokulu', kurumId: 'k2', planId: 'pl2',
                    durum: 'ziyaret_edildi', ziyaretId: 'v9'),
              ])));

      expect(find.text('Fatih Anadolu Lisesi'), findsOneWidget);
      expect(find.textContaining('8.400,00'), findsOneWidget);
      // Durakta bekleyen iş TEK vurgu satırında toplanıyor: borç ile
      // "2 talep" ayrı rozetlerde aynı sesle bağırmasın.
      expect(find.textContaining('2 talep bekliyor'), findsOneWidget);
      expect(find.textContaining('1 hazır sipariş'), findsOneWidget);
      expect(find.textContaining('1/2 tamamlandı'), findsOneWidget);
    });

    testWidgets('hiç ziyaret edilmemiş kurum "ilk ziyaret" diye işaretlenir',
        (t) async {
      await ac(t, const RotaEkrani(),
          repo: SahteZiyaretRepo(rotaKaydi: Rota(planlanan: 1,
              duraklar: [durak('Yeni Kurs Merkezi')])));
      expect(find.textContaining('ilk ziyaret'), findsOneWidget);
    });

    testWidgets('plansız ziyaret sayısı rotada görünür', (t) async {
      await ac(t, const RotaEkrani(),
          repo: SahteZiyaretRepo(rotaKaydi: Rota(planlanan: 1, tamamlanan: 1,
              plansizZiyaret: 2, duraklar: [durak('A Lisesi')])));
      expect(find.textContaining('2 plansız ziyaret'), findsOneWidget);
    });

    testWidgets('Giriş ziyaret açar', (t) async {
      final r = await ac(t, const RotaEkrani(),
          repo: SahteZiyaretRepo(rotaKaydi: Rota(planlanan: 1,
              duraklar: [durak('Fatih Anadolu Lisesi')])));

      await t.tap(find.byKey(K.rotaGiris('k1')));
      await t.pumpAndSettle();
      expect(r.cagrilar, contains('baslat:k1'));
    });

    testWidgets('açık ziyaret varken ikinci giriş sunucunun gerekçesini gösterir',
        (t) async {
      await ac(t, const RotaEkrani(),
          repo: SahteZiyaretRepo(
              baslatHatasi: 'Barış Ortaokulu ziyaretiniz hâlâ açık. '
                  'Önce onu kapatın.',
              rotaKaydi: Rota(planlanan: 1,
                  duraklar: [durak('Fatih Anadolu Lisesi')])));

      await t.tap(find.byKey(K.rotaGiris('k1')));
      await t.pumpAndSettle();
      expect(find.textContaining('hâlâ açık'), findsOneWidget);
    });

    testWidgets('durak rotadan çıkarılabilir', (t) async {
      final r = await ac(t, const RotaEkrani(),
          repo: SahteZiyaretRepo(rotaKaydi: Rota(planlanan: 1,
              duraklar: [durak('Fatih Anadolu Lisesi')])));

      await t.tap(find.byIcon(Icons.more_vert));
      await t.pumpAndSettle();
      await t.tap(find.text('Rotadan çıkar'));
      await t.pumpAndSettle();
      expect(r.cagrilar, contains('plandanCikar:pl1'));
    });

    // `onReorder`dan `onReorderItem`a geçişte hedef sıra artık çıkarılan öğe
    // hesaba katılmış geliyor; eski `yeni -= 1` düzeltmesi kalsaydı durak
    // yerinden oynamazdı ve sunucuya aynı sıra giderdi.
    testWidgets('durak sürüklenince yeni sıra sunucuya gider', (t) async {
      final r = await ac(t, const RotaEkrani(),
          repo: SahteZiyaretRepo(rotaKaydi: Rota(planlanan: 3, duraklar: [
            durak('Fatih Anadolu Lisesi', kurumId: 'k1', planId: 'pl1'),
            durak('Harran Fen Lisesi', kurumId: 'k2', planId: 'pl2'),
            durak('Atatürk Ortaokulu', kurumId: 'k3', planId: 'pl3'),
          ])));

      // İlk durağı sıra numarasından tutup ikincinin altına bırak.
      final tutamac = find.descendant(
          of: find.byKey(K.rotaSiralama), matching: find.text('1'));
      final boy = t.getSize(find.byKey(const ValueKey('pl1'))).height;
      final g = await t.startGesture(t.getCenter(tutamac));
      await t.pump();
      for (var i = 0; i < 20; i++) {
        await g.moveBy(Offset(0, boy * 1.5 / 20));
        await t.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await t.pumpAndSettle();

      expect(r.cagrilar, contains('planSirala'));
      expect(r.sonSira, ['pl2', 'pl1', 'pl3']);
    });
  });

  group('Rota · öneriler', () {
    testWidgets('her öneri gerekçesini yazar', (t) async {
      await ac(t, const RotaEkrani(),
          repo: SahteZiyaretRepo(oneriler: [
            oneri('Borçlu Lisesi', kurumId: 'k5', gecikmisBorc: 1,
                neden: 'Gecikmiş borç — 30 günü aşan ödenmemiş teslimat'),
            oneri('Sessiz Ortaokul', kurumId: 'k6',
                neden: '45 gündür uğranmadı'),
          ]));

      expect(find.byKey(K.rotaOneriler), findsOneWidget);
      expect(find.textContaining('Gecikmiş borç'), findsOneWidget);
      expect(find.text('45 gündür uğranmadı'), findsOneWidget);
    });

    testWidgets('zaten rotada olan kurum önerilmez', (t) async {
      await ac(t, const RotaEkrani(),
          repo: SahteZiyaretRepo(oneriler: [
            oneri('Zaten Planda', kurumId: 'k7', planda: true),
            oneri('Planda Değil', kurumId: 'k8'),
          ]));

      expect(find.text('Zaten Planda'), findsNothing);
      expect(find.text('Planda Değil'), findsOneWidget);
    });

    testWidgets('öneri rotaya eklenir', (t) async {
      final r = await ac(t, const RotaEkrani(),
          repo: SahteZiyaretRepo(oneriler: [oneri('Borçlu Lisesi', kurumId: 'k5')]));

      await t.tap(find.byKey(K.rotaEkle('k5')));
      await t.pumpAndSettle();
      expect(r.cagrilar, contains('planaEkle:k5'));
    });

    testWidgets('portföyünde kurum yoksa açıkça söylenir', (t) async {
      await ac(t, const RotaEkrani());
      expect(find.textContaining('kurum bağlı cari yok'), findsOneWidget);
    });
  });

  group('Açık ziyaret çubuğu', () {
    testWidgets('ziyaret yoksa çubuk hiç çizilmez', (t) async {
      await ac(t, const Scaffold(body: ZiyaretCubugu()));
      expect(find.byKey(K.ziyaretCubugu), findsNothing);
    });

    testWidgets('açık ziyaret kurum, süre ve çıktı sayısıyla görünür', (t) async {
      await ac(t, const Scaffold(body: ZiyaretCubugu()),
          repo: SahteZiyaretRepo(acik: acikZiyaret(dakika: 24,
              cikti: const ZiyaretCikti(talep: 2, tahsilat: 1, toplam: 3))));

      expect(find.byKey(K.ziyaretCubugu), findsOneWidget);
      expect(find.text('Fatih Anadolu Lisesi'), findsOneWidget);
      expect(find.textContaining('3 kayıt'), findsOneWidget);
    });

    testWidgets('henüz çıktı yoksa bunu saklamaz', (t) async {
      await ac(t, const Scaffold(body: ZiyaretCubugu()),
          repo: SahteZiyaretRepo(acik: acikZiyaret()));
      expect(find.textContaining('henüz kayıt yok'), findsOneWidget);
    });

    testWidgets('bir saati geçen ziyaret saat cinsinden yazılır', (t) async {
      await ac(t, const Scaffold(body: ZiyaretCubugu()),
          repo: SahteZiyaretRepo(acik: acikZiyaret(dakika: 95)));
      expect(find.textContaining('1 sa 35 dk'), findsOneWidget);
    });

    testWidgets('bitirirken not ve sonuç iletilir', (t) async {
      final r = await ac(t, const Scaffold(body: ZiyaretCubugu()),
          repo: SahteZiyaretRepo(acik: acikZiyaret()));

      await t.tap(find.byKey(K.ziyaretBitir));
      await t.pumpAndSettle();
      await t.tap(find.byKey(K.ziyaretSonuc('takip')));
      await t.enterText(find.byKey(K.ziyaretNot), 'Müdür yardımcısı arayacak');
      await t.tap(find.byKey(K.ziyaretBitirOnay));
      await t.pumpAndSettle();

      expect(r.cagrilar, contains('bitir:v1'));
      expect(r.sonSonuc, 'takip');
      expect(r.sonNot, 'Müdür yardımcısı arayacak');
    });

    testWidgets('kapanış özeti ziyaretten çıkanları sayar', (t) async {
      await ac(t, const Scaffold(body: ZiyaretCubugu()),
          repo: SahteZiyaretRepo(acik: acikZiyaret()));

      await t.tap(find.byKey(K.ziyaretBitir));
      await t.pumpAndSettle();
      await t.tap(find.byKey(K.ziyaretBitirOnay));
      await t.pumpAndSettle();

      expect(find.byKey(K.ziyaretOzet), findsOneWidget);
      expect(find.textContaining('27 dakika'), findsOneWidget);
      // Özet ölçüleri mikro-etiketle yazılıyor — diyaloglarda "AÇIK BAKİYE"
      // ve "TOPLAM" ile aynı dil.
      expect(find.text('TALEP'), findsOneWidget);
    });

    testWidgets('K10 · çıktısız ziyaret olgusal biçimde söylenir', (t) async {
      await ac(t, const Scaffold(body: ZiyaretCubugu()),
          repo: SahteZiyaretRepo(acik: acikZiyaret(),
              bitisCikti: const ZiyaretCikti()));

      await t.tap(find.byKey(K.ziyaretBitir));
      await t.pumpAndSettle();
      await t.tap(find.byKey(K.ziyaretBitirOnay));
      await t.pumpAndSettle();

      expect(find.textContaining('Bu ziyaretten kayıt çıkmadı'), findsOneWidget);
    });
  });

  group('Ziyaret detayı', () {
    testWidgets('çıktılar tür adlarıyla kalem kalem listelenir', (t) async {
      await ac(t, const ZiyaretDetayEkrani(ziyaretId: 'v1'),
          repo: SahteZiyaretRepo(detayKaydi: ziyaretDetay(
              cikti: const ZiyaretCikti(talep: 1, tahsilat: 1, toplam: 2),
              satirlar: [
                ziyaretSatiri('talep', 'Y Lisesi Kurumsal', aciklama: '3 kalem'),
                ziyaretSatiri('tahsilat', 'Y Lisesi Kurumsal',
                    aciklama: 'nakit', tutar: 1500),
              ])));

      expect(find.byKey(K.ziyaretCikti), findsOneWidget);
      expect(find.textContaining('Talep · 3 kalem'), findsOneWidget);
      expect(find.textContaining('1.500,00'), findsOneWidget);
      expect(find.textContaining('otomatik damgalanır'), findsOneWidget);
    });

    testWidgets('K10 · çıktısı olmayan ziyaret gizlenmez', (t) async {
      await ac(t, const ZiyaretDetayEkrani(ziyaretId: 'v1'),
          repo: SahteZiyaretRepo(detayKaydi: ziyaretDetay()));
      expect(find.textContaining('Henüz kayıt çıkmadı'), findsOneWidget);
    });

    testWidgets('sonuç kodu okunur metne çevrilir', (t) async {
      await ac(t, const ZiyaretDetayEkrani(ziyaretId: 'v1'),
          repo: SahteZiyaretRepo(detayKaydi: ziyaretDetay(sonuc: 'bulunamadi')));
      expect(find.text('Yetkili bulunamadı'), findsOneWidget);
    });

    testWidgets('açık ziyaret detaydan da bitirilebilir', (t) async {
      final r = await ac(t, const ZiyaretDetayEkrani(ziyaretId: 'v1'),
          repo: SahteZiyaretRepo(detayKaydi: ziyaretDetay(acik: true,
              sonuc: null)));

      expect(find.text('Ziyareti bitir'), findsOneWidget);
      await t.tap(find.text('Ziyareti bitir'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(K.ziyaretBitirOnay));
      await t.pumpAndSettle();
      expect(r.cagrilar, contains('bitir:v1'));
    });
  });

  group('Ziyaret geçmişi', () {
    testWidgets('çıktısı sıfır olan ziyaret listede kalır', (t) async {
      await ac(t, const ZiyaretGecmisiEkrani(),
          repo: SahteZiyaretRepo(ziyaretler: [
            ZiyaretOzet(id: 'v1', kurumId: 'k1', kurumAd: 'Verimli Lisesi',
                girisSaati: DateTime(2026, 8, 24, 9),
                cikisSaati: DateTime(2026, 8, 24, 9, 40), dakika: 40, cikti: 4),
            ZiyaretOzet(id: 'v2', kurumId: 'k2', kurumAd: 'Boş Geçen Okul',
                girisSaati: DateTime(2026, 8, 24, 11),
                cikisSaati: DateTime(2026, 8, 24, 11, 12), dakika: 12, cikti: 0),
          ]));

      expect(find.text('Boş Geçen Okul'), findsOneWidget);
      // Rozet değil sağdaki sayı sütunu — sıfır da yazılır, gizlenmez.
      expect(find.text('0 kayıt'), findsOneWidget);
      expect(find.text('4 kayıt'), findsOneWidget);
    });
  });

  group('Bugün · rota', () {
    testWidgets('rota özeti Bugün ekranının üstünde yer alır', (t) async {
      await ac(t, const BugunEkrani(),
          repo: SahteZiyaretRepo(rotaKaydi: Rota(planlanan: 2, tamamlanan: 1,
              duraklar: [
                durak('Fatih Anadolu Lisesi', borc: 8400),
                durak('Barış Ortaokulu', kurumId: 'k2', planId: 'pl2'),
              ])));

      expect(find.byKey(K.bugunRota), findsOneWidget);
      expect(find.text('Fatih Anadolu Lisesi'), findsOneWidget);
      expect(find.textContaining('1/2 tamamlandı'), findsOneWidget);
    });

    testWidgets('rota boşsa kurulması önerilir', (t) async {
      await ac(t, const BugunEkrani());
      expect(find.text('Rota kur'), findsOneWidget);
    });
  });
}
