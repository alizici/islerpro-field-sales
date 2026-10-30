import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import 'package:islerpro/data/local/yerel_db.dart';
import 'package:islerpro/data/services/saha_kuyrugu.dart';
import 'package:islerpro/data/services/yerel_referans.dart';

/// K43 · Çevrimdışı OKUMA yolu.
///
/// Senkron cari/kurum/kişiyi zaten indiriyordu; okuyan yoktu. Sahadaki sonuç
/// şuydu: sinyalsiz okulda ürün araması çalışıyor ama muhatap seçilemediği
/// için talep yine açılamıyordu.
///
/// Buradaki testler iki şeyi koruyor: (1) yerel kopyadan doğru satır çıkıyor,
/// (2) kopyanın **cevaplayamadığı** soru sessizce cevaplanmış gibi
/// gösterilmiyor.
void main() {
  late YerelDb db;
  setUp(() => db = YerelDb.test(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> tohum() async {
    await db.into(db.yerelKurum).insert(YerelKurumCompanion.insert(
        id: 'k1', ad: 'Y Lisesi',
        il: const Value('Şanlıurfa'), ilce: const Value('Haliliye'),
        tip: const Value('okul')));
    await db.into(db.yerelKurum).insert(YerelKurumCompanion.insert(
        id: 'k2', ad: 'Z Kurs Merkezi',
        il: const Value('Şanlıurfa'), ilce: const Value('Eyyübiye'),
        tip: const Value('kurs_merkezi')));
    await db.into(db.yerelCari).insert(YerelCariCompanion.insert(
        id: 'c1', unvan: 'Y Lisesi Kurumsal', tip: 'kurum', durum: 'aktif',
        kurumId: const Value('k1'), bakiye: const Value(4500),
        krediLimiti: const Value(10000)));
    await db.into(db.yerelCari).insert(YerelCariCompanion.insert(
        id: 'c2', unvan: 'Ahmet Yılmaz', tip: 'ogretmen', durum: 'aktif',
        kurumId: const Value('k1'), bakiye: const Value(0)));
    await db.into(db.yerelCari).insert(YerelCariCompanion.insert(
        id: 'c3', unvan: 'Z Kurs Kurumsal', tip: 'kurum', durum: 'tahsilatta',
        kurumId: const Value('k2'), bakiye: const Value(12000),
        krediLimiti: const Value(8000)));
    await db.into(db.yerelKisi).insert(YerelKisiCompanion.insert(
        id: 'p1', kurumId: 'k1', adSoyad: 'Ayşe Müdür',
        gorev: const Value('Müdür'), telefon: const Value('05001112233')));
    await db.into(db.yerelKisi).insert(YerelKisiCompanion.insert(
        id: 'p2', kurumId: 'k2', adSoyad: 'Veli Öğretmen'));
  }

  group('Cari', () {
    test('unvan parçasıyla bulunur, kurum adı ve ilçe eklenir', () async {
      await tohum();
      final l = await YerelReferans(db).cariAra(q: 'lisesi');
      expect(l, hasLength(1));
      expect(l.single.unvan, 'Y Lisesi Kurumsal');
      expect(l.single.kurumAd, 'Y Lisesi');
      expect(l.single.ilce, 'Haliliye');
    });

    test('tip süzgeci öğretmen carisini ayırır', () async {
      await tohum();
      final l = await YerelReferans(db).cariAra(tip: 'ogretmen');
      expect(l.map((c) => c.id), ['c2']);
    });

    test('borclu süzgeci SON SENKRONDAKİ bakiyeye bakar', () async {
      await tohum();
      final l = await YerelReferans(db).cariAra(borclu: true);
      expect(l.map((c) => c.id), ['c1', 'c3'],
          reason: 'bakiyesi sıfır olan cari borçlu listesine girmemeli');
    });

    test('kredi limiti aşımı yerelde de hesaplanır', () async {
      await tohum();
      final l = await YerelReferans(db).cariAra(q: 'Z Kurs');
      expect(l.single.limitAsildi, isTrue);
    });

    test('limit sıfırken aşım İDDİA EDİLMEZ', () async {
      await tohum();
      final l = await YerelReferans(db).cariAra(tip: 'ogretmen');
      expect(l.single.limitAsildi, isFalse,
          reason: 'limiti olmayan cari her bakiyede aşmış görünemez');
    });

    test('web: yerel veritabanı yokken liste boş döner, patlamaz', () async {
      expect(await const YerelReferans(null).cariAra(), isEmpty);
      expect(await const YerelReferans(null).kurumAra(), isEmpty);
      expect(await const YerelReferans(null).kisiler('k1'), isEmpty);
      expect(const YerelReferans(null).kullanilabilir, isFalse);
    });
  });

  group('Muhatap', () {
    test('portföy muhatap listesine çevrilir, store damgası taşır', () async {
      await tohum();
      final l = await YerelReferans(db).muhataplar('s1');
      expect(l, hasLength(3));
      expect(l.every((m) => m.storeId == 's1'), isTrue);
      expect(l.firstWhere((m) => m.id == 'c2').kurumsal, isFalse);
    });

    test('kopya boşken muhatap listesi de boştur — uydurulmaz', () async {
      expect(await YerelReferans(db).muhataplar('s1'), isEmpty);
    });
  });

  group('Kurum ve kişi', () {
    test('kurum satırı kendi cari sayısını taşır', () async {
      await tohum();
      final l = await YerelReferans(db).kurumAra();
      expect(l.map((k) => k.ad), ['Y Lisesi', 'Z Kurs Merkezi']);
      expect(l.firstWhere((k) => k.id == 'k1').cariSayisi, 2);
      expect(l.firstWhere((k) => k.id == 'k2').cariSayisi, 1);
    });

    test('kurum tipi korunur — kurs merkezi okula dönüşmez', () async {
      await tohum();
      final l = await YerelReferans(db).kurumAra(q: 'kurs');
      expect(l.single.kursMerkezi, isTrue);
    });

    test('K30 · kişiler yalnızca kendi kurumundan gelir', () async {
      await tohum();
      final l = await YerelReferans(db).kisiler('k1');
      expect(l.map((k) => k.adSoyad), ['Ayşe Müdür']);
      expect(l.single.telefon, '05001112233');
    });
  });

  group('Tazelik', () {
    test('senkron yapılmamışsa tarih YOKTUR — uydurulmaz', () async {
      expect(await YerelReferans(db).tarih(), isNull);
      expect(await YerelReferans(db).dolu(), isFalse);
    });

    test('senkron tarihi olduğu gibi okunur', () async {
      await tohum();
      await db.ayarYaz('son_referans', '2026-08-20T09:30:00.000');
      expect(await YerelReferans(db).tarih(), DateTime(2026, 8, 20, 9, 30));
      expect(await YerelReferans(db).dolu(), isTrue);
    });
  });

  group('K42 · cihazdaki kopyanın dökümü', () {
    test('her tablo ayrı ayrı sayılır', () async {
      await tohum();
      final s = await YerelReferans(db).sayilar();
      expect((s.cari, s.kurum, s.kisi, s.urun), (3, 2, 2, 0));
      expect(s.bos, isFalse);
    });

    test('boş cihazda sayı UYDURULMAZ', () async {
      final s = await YerelReferans(db).sayilar();
      expect(s.bos, isTrue);
      expect(s.tarih, isNull);
    });

    test('web: yerel veritabanı yokken döküm boştur', () async {
      expect((await const YerelReferans(null).sayilar()).bos, isTrue);
    });
  });

  group('Çevrimdışı ayrımı okumada da aynı', () {
    test('ağ yoksa yerel kopyaya düşülür', () {
      expect(sunucuyaUlasilamadi(TimeoutException('ağ yok')), isTrue);
    });

    test('sunucu CEVAP VERİP reddettiyse yerel kopya gösterilmez', () {
      expect(
          sunucuyaUlasilamadi(
              PostgrestException(message: 'yetkiniz yok', code: '42501')),
          isFalse,
          reason: 'yetki hatasını bayat veriyle örtmek onu görünmez yapar');
    });

    test('kod hatası hiçbir koşulda çevrimdışı sayılmaz', () {
      expect(sunucuyaUlasilamadi(StateError('bozuk durum')), isFalse);
    });
  });
}
