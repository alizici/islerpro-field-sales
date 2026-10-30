import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:islerpro/core/auth/session.dart';
import 'package:islerpro/core/test_keys.dart';
import 'package:islerpro/data/local/yerel_db.dart';
import 'package:islerpro/data/local/yerel_saglayici.dart';
import 'package:islerpro/data/repositories/senkron_repository.dart';
import 'package:islerpro/features/sync/presentation/senkron_ekrani.dart';

import 'sahte_depolar.dart';

/// K43 · Kuyruğun GÖRÜNÜRLÜĞÜ.
///
/// Sözleşme "başarısız kayıt sessizce kaybolmaz" diyor. Sessizce kaybolmamak
/// bir ekran meselesidir: kayıt veritabanında duruyor olabilir ama kullanıcı
/// onu göremiyorsa, kaybolmuş sayılır.
void main() {
  late YerelDb db;
  setUp(() => db = YerelDb.test(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> ac(WidgetTester t, {SahteSenkronRepo? repo,
      AppRole rol = AppRole.pazarlamaci}) async {
    t.view.physicalSize = const Size(1000, 2400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [
        yerelDbProvider.overrideWithValue(db),
        senkronRepositoryProvider.overrideWithValue(repo ?? SahteSenkronRepo()),
        sessionProvider.overrideWithValue(testOturumu(rol: rol)),
      ],
      child: const MaterialApp(home: SenkronEkrani()),
    ));
    await t.pumpAndSettle();
  }

  group('K42 · cihazdaki kopya ÖLÇÜLÜR', () {
    testWidgets('kopya boşken "boş" denir — dolu gibi gösterilmez', (t) async {
      await ac(t);
      await t.scrollUntilVisible(find.byKey(K.senkronYerelKopya), 300);
      await t.pumpAndSettle();
      expect(find.textContaining('Boş — henüz eşitlenmedi'), findsOneWidget);
    });

    testWidgets('eşitlemeden SONRA sayım tazelenir', (t) async {
      await ac(t, repo: SahteSenkronRepo(referansVerisi: const {
        'cariler': [
          {'id': 'c1', 'unvan': 'Y Lisesi Kurumsal', 'tip': 'kurum',
           'durum': 'aktif'},
        ],
        'kurumlar': [{'id': 'k1', 'ad': 'Y Lisesi'}],
        'kisiler': <Map<String, dynamic>>[],
      }));

      await t.scrollUntilVisible(find.byKey(K.senkronYerelKopya), 300);
      await t.pumpAndSettle();
      expect(find.textContaining('Boş — henüz eşitlenmedi'), findsOneWidget);

      await t.scrollUntilVisible(find.byKey(K.senkronCalistir), -300);
      await t.pumpAndSettle();
      await t.tap(find.byKey(K.senkronCalistir));
      await t.pumpAndSettle();

      await t.scrollUntilVisible(find.byKey(K.senkronYerelKopya), 300);
      await t.pumpAndSettle();
      expect(find.textContaining('Boş — henüz eşitlenmedi'), findsNothing,
          reason: 'eşitleme bittiyse ekran eşitlemeden ÖNCEKİ hâli '
              'göstermeye devam edemez');
      expect(find.textContaining('1 cari · 1 kurum'), findsOneWidget);
    });

    testWidgets('sayılar gerçekten sayılır, iddia edilmez', (t) async {
      await db.into(db.yerelCari).insert(YerelCariCompanion.insert(
          id: 'c1', unvan: 'Y Lisesi Kurumsal', tip: 'kurum', durum: 'aktif'));
      await db.into(db.yerelKurum).insert(
          YerelKurumCompanion.insert(id: 'k1', ad: 'Y Lisesi'));
      await db.into(db.yerelUrun).insert(
          YerelUrunCompanion.insert(id: 'u1', ad: 'TYT Matematik'));
      await db.ayarYaz('son_referans', '2026-08-20T09:30:00.000');
      await ac(t);

      await t.scrollUntilVisible(find.byKey(K.senkronYerelKopya), 300);
      await t.pumpAndSettle();
      expect(find.textContaining('1 cari · 1 kurum · 0 kişi · 1 ürün'),
          findsOneWidget,
          reason: 'sahip cihazı iptal ederken ölçülmüş sayıya bakmalı');
      expect(find.textContaining('20 Ağu 2026 09:30'), findsOneWidget);
    });
  });

  group('Kuyruk görünürlüğü', () {
    testWidgets('bekleyen kayıt yoksa açıkça söylenir', (t) async {
      await ac(t);
      expect(find.byKey(K.senkronDurum), findsOneWidget);
      expect(find.textContaining('Yüklenmeyi bekleyen kayıt yok'),
          findsOneWidget);
    });

    testWidgets('bekleyen kayıt insan diliyle listelenir', (t) async {
      await db.kuyrugaYaz('create_payment', {'tutar': 250},
          'Y Lisesi Kurumsal · 250 ₺ tahsilat');
      await ac(t);

      expect(find.text('Y Lisesi Kurumsal · 250 ₺ tahsilat'), findsOneWidget);
      // Ham fonksiyon adı değil, ne olduğu yazar
      expect(find.textContaining('Tahsilat ·'), findsOneWidget);
      expect(find.text('1'), findsWidgets, reason: 'bekleyen sayısı');
    });

    testWidgets('K43 · yüklenemeyen kayıt SEBEBİYLE birlikte durur', (t) async {
      final id = await db.kuyrugaYaz('create_request', const {},
          'Barış Ortaokulu · 3 kalem talep');
      await db.hataIsaretle(id, 'Cari bulunamadı veya yetkiniz yok');
      await ac(t);

      expect(find.textContaining('Cari bulunamadı'), findsOneWidget);
      expect(find.byKey(K.senkronSil(id)), findsOneWidget,
          reason: 'düzelmeyecek kayıt kullanıcı eliyle atılabilmeli');
    });

    testWidgets('hatalı kayıt kuyruktan silinebilir', (t) async {
      final id = await db.kuyrugaYaz('create_request', const {}, 'Talep');
      await db.hataIsaretle(id, 'hata');
      await ac(t);

      await t.tap(find.byKey(K.senkronSil(id)));
      await t.pumpAndSettle();
      expect(await db.bekleyenSayisi(), 0);
    });

    testWidgets('bekleyen kayıt yüklenmemişse silme düğmesi YOKTUR', (t) async {
      final id = await db.kuyrugaYaz('create_payment', const {}, 'Tahsilat');
      await ac(t);
      expect(find.byKey(K.senkronSatir(id)), findsOneWidget);
      expect(find.byKey(K.senkronSil(id)), findsNothing,
          reason: 'henüz denenmemiş kayıt yanlışlıkla atılmamalı');
    });
  });

  group('K42 · güvenlik durumu', () {
    testWidgets('yerel veri şifresizse bunu SAKLAMAZ', (t) async {
      await ac(t);
      await t.pumpAndSettle();
      expect(find.byKey(K.senkronGuvenlik), findsOneWidget);
      // Bellekteki test veritabanının dosyası yok → "veri yok" der; hiçbir
      // durumda "şifreli" diye yalan söylemez.
      expect(find.text('ŞİFRELİ'), findsNothing);
    });

    testWidgets('cihazda ekran kilidi yoksa kilidin kapalı olduğu YAZAR',
        (t) async {
      await ac(t);
      await t.pumpAndSettle();
      // Rozet değil vurgu satırı: "KAPALI" ile sonucu tek cümlede.
      expect(find.text('Kapalı — otomatik kilit ÇALIŞMIYOR'), findsOneWidget);
      expect(find.textContaining('Cihazda ekran kilidi yok'), findsOneWidget);
    });
  });

  group('K42 · cihazlar', () {
    testWidgets('cihaz listesi yalnızca yöneticiye görünür', (t) async {
      await ac(t, rol: AppRole.pazarlamaci);
      expect(find.byKey(K.senkronCihazlar), findsNothing);

      await ac(t, rol: AppRole.isletmeSahibi,
          repo: SahteSenkronRepo(cihazlar_: [cihaz('Ali Veli')]));
      expect(find.byKey(K.senkronCihazlar), findsOneWidget);
      expect(find.text('Ali Veli'), findsOneWidget);
    });

    testWidgets('iptal onayı NE KAYBEDİLECEĞİNİ söyler', (t) async {
      final repo = SahteSenkronRepo(cihazlar_: [cihaz('Ali Veli')]);
      await ac(t, rol: AppRole.isletmeSahibi, repo: repo);

      await t.tap(find.byKey(K.senkronCihazIptal('d1')));
      await t.pumpAndSettle();
      expect(find.textContaining('yerel veri silinir'), findsOneWidget);
      expect(find.textContaining('yüklenmemiş kayıtları'), findsOneWidget);

      await t.tap(find.byKey(K.senkronCihazIptalOnay));
      await t.pumpAndSettle();
      expect(repo.iptalEdilen, 'd1');
    });

    testWidgets('iptal edilmiş cihaz rozetle işaretlenir', (t) async {
      await ac(t, rol: AppRole.isletmeSahibi,
          repo: SahteSenkronRepo(cihazlar_: [cihaz('Ali Veli', iptal: true)]));
      // Rozet değil vurgu satırı: iptalin SONUCU da yazılı — cihaz ilk
      // bağlanışında yerel verisini siler (K42).
      expect(find.textContaining('İptal edildi'), findsOneWidget);   // Rozet büyütür
      expect(find.byKey(K.senkronCihazIptal('d1')), findsNothing);
    });
  });
}

CihazSatiri cihaz(String ad, {String id = 'd1', bool iptal = false,
    int gun = 0}) =>
    CihazSatiri(id: id, userId: 'u1', adSoyad: ad, cihaz: 'iPhone / iPad',
        platform: 'iOS', surum: '1.0.0', gun: gun, iptal: iptal,
        sonGorulme: DateTime(2026, 8, 25, 9));

class SahteSenkronRepo implements SenkronRepository {
  SahteSenkronRepo({this.cihazlar_ = const [], this.referansVerisi = const {}});
  final List<CihazSatiri> cihazlar_;
  final Map<String, dynamic> referansVerisi;
  String? iptalEdilen;

  @override
  Future<List<CihazSatiri>> cihazlar() async => cihazlar_;
  @override
  Future<void> cihazIptal(String deviceId) async => iptalEdilen = deviceId;
  @override
  Future<CihazDurumu> cihazKaydet({required String clientId, String? ad,
      String? platform, String? surum}) async => const CihazDurumu();
  @override
  Future<void> silmeOnayla(String clientId) async {}
  @override
  Future<ItmeSonucu> kuyrugaYolla(String clientId,
      List<Map<String, dynamic>> ops) async => const ItmeSonucu();
  @override
  Future<Map<String, dynamic>> referans(String storeId) async =>
      referansVerisi;
  @override
  Future<KatalogSayfasi> katalog(String storeId, {DateTime? since,
      String? after, int limit = 500}) async => const KatalogSayfasi();
}
