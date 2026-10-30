import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import 'package:islerpro/core/auth/session.dart';
import 'package:islerpro/core/test_keys.dart';
import 'package:islerpro/data/local/yerel_db.dart';
import 'package:islerpro/data/local/yerel_saglayici.dart';
import 'package:islerpro/data/repositories/cari_repository.dart';
import 'package:islerpro/data/repositories/org_repository.dart';
import 'package:islerpro/data/repositories/siparis_repository.dart';
import 'package:islerpro/data/repositories/talep_repository.dart';
import 'package:islerpro/features/accounts/presentation/cariler_ekrani.dart';
import 'package:islerpro/features/collections/presentation/tahsilat_diyalogu.dart';
import 'package:islerpro/features/requests/presentation/talep_olustur_ekrani.dart';

import 'sahte_depolar.dart';

/// K43 · Çevrimdışı yolun EKRANA bağlandığını kanıtlar.
///
/// Servis katmanı `yerel_referans_test.dart`'ta ayrıca sınanıyor; buradaki
/// soru başka: **ekran gerçekten yerel kopyaya düşüyor mu, ve düştüğünü
/// kullanıcıya söylüyor mu?** Faz 7'de kopya iniyordu ama hiçbir ekran onu
/// okumuyordu — kimse fark etmemişti, çünkü kimse ekranı çevrimdışı
/// koşturmamıştı.
void main() {
  late YerelDb db;
  setUp(() => db = YerelDb.test(NativeDatabase.memory()));
  tearDown(() => db.close());

  /// Ağ yok: sunucu CEVAP VERMEDİ.
  final agYok = TimeoutException('ağ yok');

  /// Sunucu cevap verdi ve REDDETTİ.
  final redd = PostgrestException(message: 'yetkiniz yok', code: '42501');

  Future<void> tohum() async {
    await db.into(db.yerelKurum).insert(YerelKurumCompanion.insert(
        id: 'k1', ad: 'Y Lisesi', ilce: const Value('Haliliye'),
        tip: const Value('okul')));
    await db.into(db.yerelCari).insert(YerelCariCompanion.insert(
        id: 'c1', unvan: 'Y Lisesi Kurumsal', tip: 'kurum', durum: 'aktif',
        kurumId: const Value('k1'), bakiye: const Value(4500),
        krediLimiti: const Value(10000)));
    await db.ayarYaz('son_referans', '2026-08-20T09:30:00.000');
  }

  Future<void> ac(WidgetTester t, Widget w, {
    SahteCariRepo? cari, SahteTalepRepo? talep, SahteSiparisRepo? siparis,
  }) async {
    t.view.physicalSize = const Size(1000, 2400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [
        cariRepositoryProvider.overrideWithValue(cari ?? SahteCariRepo()),
        talepRepositoryProvider.overrideWithValue(talep ?? SahteTalepRepo()),
        siparisRepositoryProvider
            .overrideWithValue(siparis ?? SahteSiparisRepo()),
        orgRepositoryProvider.overrideWithValue(SahteOrgRepo()),
        sessionProvider.overrideWithValue(testOturumu()),
        yerelDbProvider.overrideWithValue(db),
      ],
      child: MaterialApp(home: w),
    ));
    await t.pumpAndSettle();
  }

  group('Cari listesi · okuma', () {
    testWidgets('sunucuya ULAŞILAMAZSA cihazdaki kopya gösterilir', (t) async {
      await tohum();
      await ac(t, const CarilerEkrani(),
          cari: SahteCariRepo(aramaHatasi: agYok));

      expect(find.byKey(K.cariListesi), findsOneWidget);
      expect(find.text('Y Lisesi Kurumsal'), findsOneWidget);
      expect(find.byKey(K.yerelKopyaUyarisi), findsOneWidget);
    });

    testWidgets('uyarı senkron TARİHİNİ söyler — "çevrimdışı" demek yetmez',
        (t) async {
      await tohum();
      await ac(t, const CarilerEkrani(),
          cari: SahteCariRepo(aramaHatasi: agYok));

      expect(find.textContaining('20 Ağu 2026 09:30'), findsOneWidget,
          reason: 'bakiyenin ne kadar bayat olduğu tarihten anlaşılır');
    });

    testWidgets('yerelden gelen bakiye satırda görünür', (t) async {
      await tohum();
      await ac(t, const CarilerEkrani(),
          cari: SahteCariRepo(aramaHatasi: agYok));
      expect(find.textContaining('4.500,00'), findsOneWidget);
    });

    testWidgets('sunucu CEVAP VERİP REDDETTİYSE kopya gösterilmez', (t) async {
      await tohum();
      await ac(t, const CarilerEkrani(), cari: SahteCariRepo(aramaHatasi: redd));

      expect(find.byKey(K.yerelKopyaUyarisi), findsNothing,
          reason: 'yetki hatasını bayat veriyle örtmek onu görünmez yapar');
      expect(find.text('Y Lisesi Kurumsal'), findsNothing);
      expect(find.textContaining('yetkiniz yok'), findsOneWidget);
    });

    testWidgets('kopya BOŞSA hata gizlenmez', (t) async {
      await ac(t, const CarilerEkrani(),
          cari: SahteCariRepo(aramaHatasi: agYok));

      expect(find.byKey(K.yerelKopyaUyarisi), findsNothing);
      expect(find.textContaining('ağ yok'), findsOneWidget);
    });

    testWidgets('sunucu çalışırken yerel uyarı ÇIKMAZ', (t) async {
      await tohum();
      await ac(t, const CarilerEkrani(),
          cari: SahteCariRepo(cariler: [cariOzeti()]));
      expect(find.byKey(K.yerelKopyaUyarisi), findsNothing);
    });
  });

  group('Yerelde cevaplanamayan süzgeç', () {
    testWidgets('atanmamış süzgeci açıkken yerel liste GÖSTERİLMEZ', (t) async {
      await tohum();
      late ProviderContainer kap;
      t.view.physicalSize = const Size(1000, 2400);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(ProviderScope(
        overrides: [
          cariRepositoryProvider
              .overrideWithValue(SahteCariRepo(aramaHatasi: agYok)),
          orgRepositoryProvider.overrideWithValue(SahteOrgRepo()),
          sessionProvider.overrideWithValue(testOturumu()),
          yerelDbProvider.overrideWithValue(db),
        ],
        child: Builder(builder: (c) {
          kap = ProviderScope.containerOf(c);
          return const MaterialApp(home: CarilerEkrani());
        }),
      ));
      await t.pumpAndSettle();

      kap.read(cariFiltreProvider.notifier)
          .ayarla(const CariFiltre(atanmamis: true));
      await t.pumpAndSettle();

      expect(find.byKey(K.yerelKopyaUyarisi), findsNothing,
          reason: 'portföy sahibi cihaza inmiyor; süzgeci sessizce yok sayıp '
              'liste göstermek "atanmamış cari kalmamış" yanılgısını üretir');
      expect(find.textContaining('ağ yok'), findsOneWidget);
    });
  });

  group('Yazma · kuyruğa alma', () {
    testWidgets('sunucuya ulaşılamazsa tahsilat KUYRUĞA yazılır', (t) async {
      await tohum();
      await ac(t, Scaffold(body: Builder(builder: (c) => TextButton(
          onPressed: () => showDialog<bool>(context: c,
              builder: (_) => TahsilatDiyalogu(cari: borclu('Y Lisesi'))),
          child: const Text('aç')))),
          siparis: SahteSiparisRepo(yazmaHatasi: agYok));

      await t.tap(find.text('aç'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(K.tahsilatKaydet));
      await t.pumpAndSettle();

      final kuyruk = await db.bekleyenler();
      expect(kuyruk, hasLength(1));
      expect(kuyruk.single.fn, 'create_payment');
      expect(kuyruk.single.ozet, contains('Y Lisesi'));
      expect(find.textContaining('kuyruğa alındı'), findsOneWidget);
    });

    testWidgets('kuyruktaki tahsilatta MAHSUP uydurulmaz', (t) async {
      await tohum();
      await ac(t, Scaffold(body: Builder(builder: (c) => TextButton(
          onPressed: () => showDialog<bool>(context: c,
              builder: (_) => TahsilatDiyalogu(cari: borclu('Y Lisesi'))),
          child: const Text('aç')))),
          siparis: SahteSiparisRepo(yazmaHatasi: agYok));

      await t.tap(find.text('aç'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(K.tahsilatKaydet));
      await t.pumpAndSettle();

      expect(find.text('Makbuz'), findsNothing,
          reason: 'makbuz no henüz yok — sunucu senkronda atayacak (K43·3)');
      expect(find.textContaining('mahsup edildi'), findsNothing,
          reason: 'FIFO dağılımını sunucu yapar; burada uydurmak yanlış olur');
    });

    testWidgets('K43 · idempotency anahtarı kuyruk satırına yazılır',
        (t) async {
      await tohum();
      await ac(t, Scaffold(body: Builder(builder: (c) => TextButton(
          onPressed: () => showDialog<bool>(context: c,
              builder: (_) => TahsilatDiyalogu(cari: borclu('Y Lisesi'))),
          child: const Text('aç')))),
          siparis: SahteSiparisRepo(yazmaHatasi: agYok));

      await t.tap(find.text('aç'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(K.tahsilatKaydet));
      await t.pumpAndSettle();

      final args = jsonDecode((await db.bekleyenler()).single.args) as Map;
      expect(args['client_key'], isNotEmpty,
          reason: 'anahtar olmadan aynı tahsilat iki kez yazılabilir');
      expect(args['tutar'], 400);
    });

    testWidgets('sunucu REDDEDERSE kuyruğa girmez, hata ekranda kalır',
        (t) async {
      await tohum();
      await ac(t, Scaffold(body: Builder(builder: (c) => TextButton(
          onPressed: () => showDialog<bool>(context: c,
              builder: (_) => TahsilatDiyalogu(cari: borclu('Y Lisesi'))),
          child: const Text('aç')))),
          siparis: SahteSiparisRepo(yazmaHatasi: redd));

      await t.tap(find.text('aç'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(K.tahsilatKaydet));
      await t.pumpAndSettle();

      expect(await db.bekleyenSayisi(), 0,
          reason: 'yarın da aynı cevabı alacak iş kuyrukta bekleyemez');
      expect(find.textContaining('yetkiniz yok'), findsOneWidget);
    });
  });

  group('Talep · muhatap seçimi', () {
    testWidgets('muhatap listesi de yerel kopyadan gelir', (t) async {
      await tohum();
      await ac(t, const TalepOlusturEkrani(),
          talep: SahteTalepRepo(muhatapHatasi: agYok));

      expect(find.byKey(K.talepMuhatap), findsOneWidget);
      expect(find.text('Y Lisesi Kurumsal'), findsOneWidget);
      expect(find.byKey(K.yerelKopyaUyarisi), findsOneWidget);
    });

    testWidgets('kopya yoksa muhatap hatası gizlenmez', (t) async {
      await ac(t, const TalepOlusturEkrani(),
          talep: SahteTalepRepo(muhatapHatasi: agYok));
      expect(find.textContaining('ağ yok'), findsOneWidget);
    });
  });
}

CariOzet cariOzeti() => const CariOzet(
      id: 'c1', tip: 'kurum', unvan: 'Sunucudan Gelen',
      durum: 'aktif', institutionId: 'k1', bakiye: 100);
