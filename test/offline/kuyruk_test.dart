import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import 'package:islerpro/data/local/yerel_db.dart';
import 'package:islerpro/data/repositories/senkron_repository.dart';
import 'package:islerpro/data/services/saha_kuyrugu.dart';
import 'package:islerpro/data/services/senkron.dart';
import 'package:islerpro/data/services/yerel_katalog.dart';

/// K43 · Çevrimdışı yazma yolu.
///
/// Buradaki testlerin tamamı tek bir ayrımı koruyor: **sunucu cevap verip
/// reddettiyse kuyruğa yazılmaz, cevap hiç gelmediyse yazılır.** Bu ayrım
/// bozulursa ya kullanıcının haklı hatası sessizce kuyrukta birikir, ya da
/// sahada girilen kayıt "hata" diye kaybolur.
void main() {
  late YerelDb db;
  setUp(() => db = YerelDb.test(NativeDatabase.memory()));
  tearDown(() => db.close());

  group('SahaKuyrugu · ne kuyruğa girer', () {
    test('çağrı başarılıysa kuyruğa hiçbir şey yazılmaz', () async {
      final k = SahaKuyrugu(db);
      final r = await k.dene(() async => 'tamam',
          fn: 'create_payment', args: {'tutar': 10}, ozet: 'Tahsilat');
      expect(r, 'tamam');
      expect(await db.bekleyenSayisi(), 0);
    });

    test('sunucuya ULAŞILAMAZSA iş kuyruğa yazılır ve null döner', () async {
      final k = SahaKuyrugu(db);
      final r = await k.dene<String>(
          () => Future.error(TimeoutException('ağ yok')),
          fn: 'create_payment', args: {'tutar': 10},
          ozet: 'Y Lisesi · 10 ₺ tahsilat');
      expect(r, isNull, reason: 'null "başarısız" değil, "sonra yüklenecek"');
      final kuyruk = await db.bekleyenler();
      expect(kuyruk, hasLength(1));
      expect(kuyruk.single.fn, 'create_payment');
      expect(kuyruk.single.ozet, 'Y Lisesi · 10 ₺ tahsilat');
      expect(jsonDecode(kuyruk.single.args), {'tutar': 10});
    });

    test('sunucu CEVAP VERİP reddettiyse kuyruğa girmez, hata yükselir',
        () async {
      final k = SahaKuyrugu(db);
      await expectLater(
        k.dene<String>(
            () => Future.error(PostgrestException(
                message: 'Cari bulunamadı veya yetkiniz yok', code: '42501')),
            fn: 'create_payment', args: const {}, ozet: 'Tahsilat'),
        throwsA(isA<PostgrestException>()),
      );
      expect(await db.bekleyenSayisi(), 0,
          reason: 'yarın da aynı cevabı alacak bir iş kuyrukta bekleyemez');
    });

    test('kodsuz PostgrestException ağ sorunu sayılır ve kuyruğa girer',
        () async {
      final k = SahaKuyrugu(db);
      final r = await k.dene<String>(
          () => Future.error(PostgrestException(message: 'connection failed')),
          fn: 'create_request', args: const {}, ozet: 'Talep');
      expect(r, isNull);
      expect(await db.bekleyenSayisi(), 1);
    });

    test('kod hatası (Error) kuyruğa gizlenmez', () async {
      final k = SahaKuyrugu(db);
      await expectLater(
        k.dene<String>(() => Future.error(StateError('null kontrolü')),
            fn: 'create_request', args: const {}, ozet: 'Talep'),
        throwsA(isA<StateError>()),
      );
      expect(await db.bekleyenSayisi(), 0);
    });

    test('web gibi yerel veritabanı olmayan yerde hata gizlenmez', () async {
      const k = SahaKuyrugu(null);
      expect(k.kullanilabilir, isFalse);
      await expectLater(
        k.dene<String>(() => Future.error(TimeoutException('ağ yok')),
            fn: 'create_request', args: const {}, ozet: 'Talep'),
        throwsA(isA<TimeoutException>()),
      );
    });
  });

  group('Kuyruk defteri', () {
    test('yüklenenler temizlenir, HATALILAR durur', () async {
      final a = await db.kuyrugaYaz('create_request', {'x': 1}, 'Talep A');
      final b = await db.kuyrugaYaz('create_payment', {'x': 2}, 'Tahsilat B');
      expect(await db.bekleyenSayisi(), 2);

      await db.yuklendiIsaretle(a, '{"id":"r1"}');
      await db.hataIsaretle(b, 'Cari bulunamadı');
      expect(await db.bekleyenSayisi(), 1);

      await db.yuklenenleriTemizle();
      final kalan = await db.bekleyenler();
      expect(kalan, hasLength(1));
      expect(kalan.single.ozet, 'Tahsilat B');
      expect(kalan.single.hata, 'Cari bulunamadı',
          reason: 'başarısız kayıt sessizce kaybolmaz (K43)');
      expect(kalan.single.deneme, 1);
    });

    test('kuyruk sıraya göre okunur — K43 çakışma değil SIRA sorunudur',
        () async {
      await db.kuyrugaYaz('start_visit', const {}, 'Ziyaret');
      await db.kuyrugaYaz('create_request', const {}, 'Talep');
      await db.kuyrugaYaz('end_visit', const {}, 'Ziyaret kapatma');
      final l = await db.bekleyenler();
      expect(l.map((e) => e.fn).toList(),
          ['start_visit', 'create_request', 'end_visit']);
    });

    test('K42 · her şeyi sil kuyruğu da götürür', () async {
      await db.kuyrugaYaz('create_request', const {}, 'Talep');
      await db.ayarYaz('client_id', 'abc');
      await db.herSeyiSil();
      expect(await db.bekleyenSayisi(), 0);
      expect(await db.ayarOku('client_id'), isNull);
    });
  });

  group('Çevrimdışı açık ziyaret', () {
    test('yerel ziyaret açılır, okunur, kapanır', () async {
      final k = SahaKuyrugu(db);
      expect(await k.yerelZiyaret(), isNull);
      await k.yerelZiyaretAc('k1', 'Fatih Anadolu Lisesi', DateTime(2026, 8, 25, 10));
      final z = await k.yerelZiyaret();
      expect(z!['kurum_ad'], 'Fatih Anadolu Lisesi');
      expect(z['institution_id'], 'k1');
      await k.yerelZiyaretKapat();
      expect(await k.yerelZiyaret(), isNull);
    });
  });

  group('Çevrimdışı katalog', () {
    Future<void> urun(String id, String ad,
        {double? fiyat = 100, String? barkod, bool aktif = true}) =>
        db.into(db.yerelUrun).insert(YerelUrunCompanion.insert(
              id: id, ad: ad,
              satisFiyat: Value(fiyat), barkod: Value(barkod),
              aktif: Value(aktif)));

    test('ada göre aranır, fiyatı olmayan listelenmez', () async {
      await urun('p1', 'TYT Matematik Soru Bankası');
      await urun('p2', 'AYT Fizik Föy');
      await urun('p3', 'Fiyatsız Kitap', fiyat: null);
      final k = YerelKatalog(db);

      expect((await k.ara('matematik')).map((e) => e.id), ['p1']);
      expect((await k.ara(null)).map((e) => e.id), ['p2', 'p1']);
      expect((await k.ara('fiyatsız')), isEmpty,
          reason: 'fiyatı olmayan ürün siparişe dönüşemez');
    });

    test('arşivlenen ürün yerelde de listelenmez (K14)', () async {
      await urun('p1', 'Eski Baskı', aktif: false);
      expect(await YerelKatalog(db).ara('eski'), isEmpty);
    });

    test('barkod tam eşleşmeyle bulunur', () async {
      await urun('p1', 'TYT Türkçe', barkod: '9786051234567');
      final k = YerelKatalog(db);
      expect((await k.ara('9786051234567')).single.id, 'p1');
      expect((await k.barkodla('9786051234567'))?.ad, 'TYT Türkçe');
      expect(await k.barkodla('yok'), isNull);
    });

    test('yerel veritabanı yoksa boş döner, patlamaz', () async {
      const k = YerelKatalog(null);
      expect(k.kullanilabilir, isFalse);
      expect(await k.ara('matematik'), isEmpty);
      expect(await k.sayi(), 0);
    });
  });

  group('SenkronServisi', () {
    test('ÖNCE iter SONRA çeker — kendi yazdığımız bakiye geri gelsin',
        () async {
      final repo = SahteSenkronRepo();
      await db.kuyrugaYaz('create_payment', {'tutar': 100}, 'Tahsilat');
      await SenkronServisi(db: db, repo: repo, storeId: 's1').calistir();
      expect(repo.sira.indexOf('push'), lessThan(repo.sira.indexOf('referans')),
          reason: 'referans önce çekilirse pazarlamacı kendi ödemesini '
              'bakiyede göremez');
    });

    test('yüklenen kayıt kuyruktan düşer, hatalı kalır', () async {
      final repo = SahteSenkronRepo(basariliSeq: {1});
      await db.kuyrugaYaz('create_payment', {'tutar': 100}, 'İyi');
      await db.kuyrugaYaz('create_request', const {}, 'Kötü');
      final r = await SenkronServisi(db: db, repo: repo, storeId: 's1')
          .calistir();

      expect(r.yuklenen, 1);
      expect(r.hatali, 1);
      final kalan = await db.bekleyenler();
      expect(kalan, hasLength(1));
      expect(kalan.single.ozet, 'Kötü');
      expect(kalan.single.hata, isNotNull);
    });

    test('referans veri sunucunun AYNASI — düşen cari yerelde kalmaz',
        () async {
      final repo = SahteSenkronRepo(cariler: [
        {'id': 'c1', 'unvan': 'A Lisesi', 'tip': 'kurum', 'durum': 'aktif',
         'bakiye': 400},
        {'id': 'c2', 'unvan': 'B Ortaokulu', 'tip': 'kurum', 'durum': 'aktif'},
      ]);
      final s = SenkronServisi(db: db, repo: repo, storeId: 's1');
      await s.calistir(katalog: false);
      expect(await db.select(db.yerelCari).get(), hasLength(2));

      repo.cariler = [
        {'id': 'c1', 'unvan': 'A Lisesi', 'tip': 'kurum', 'durum': 'aktif'}
      ];
      await s.calistir(katalog: false);
      final kalan = await db.select(db.yerelCari).get();
      expect(kalan.map((e) => e.id).toList(), ['c1'],
          reason: 'portföyden çıkan cari yerelde sonsuza dek kalamaz');
    });

    test('katalog imleçle sayfalanır ve delta damgası saklanır', () async {
      final repo = SahteSenkronRepo(sayfalar: [
        [{'id': 'p1', 'ad': 'Kitap 1', 'satis_fiyat': 100.0},
         {'id': 'p2', 'ad': 'Kitap 2', 'satis_fiyat': 200.0}],
        [{'id': 'p3', 'ad': 'Kitap 3'}],
      ]);
      final r = await SenkronServisi(db: db, repo: repo, storeId: 's1')
          .calistir();
      expect(r.urun, 3);
      expect(await db.select(db.yerelUrun).get(), hasLength(3));
      expect(repo.imlecler, ['', 'p2'], reason: 'ikinci sayfa imleçten devam');
      expect(await db.ayarOku('katalog_tarih'), isNotNull);
    });

    test('hata alan satır aynı koşuda TEKRAR TEKRAR gönderilmez', () async {
      final repo = SahteSenkronRepo(basariliSeq: const {});
      for (var i = 0; i < 3; i++) {
        await db.kuyrugaYaz('create_request', const {}, 'Talep $i');
      }
      await SenkronServisi(db: db, repo: repo, storeId: 's1')
          .calistir(katalog: false);
      expect(repo.sira.where((e) => e == 'push').length, 1,
          reason: 'kuyruk bir kez okunup yerelde dilimlenir');
      final kalan = await db.bekleyenler();
      expect(kalan.every((k) => k.deneme == 1), isTrue);
    });

    test('tamamlanan turdan sonra imleç uuid olarak geri gönderilmez',
        () async {
      final repo = SahteSenkronRepo(sayfalar: [
        [{'id': 'p1', 'ad': 'Kitap 1'}],
      ]);
      final s = SenkronServisi(db: db, repo: repo, storeId: 's1');
      await s.calistir();
      expect(await db.ayarOku('katalog_imlec'), '');
      await s.calistir();
      expect(repo.imlecler.last, '',
          reason: 'boş imleç null olarak gitmeli, yoksa uuid dönüşümü patlar');
    });

    test('ikinci senkron yalnızca DEĞİŞENİ ister', () async {
      final repo = SahteSenkronRepo(sayfalar: [
        [{'id': 'p1', 'ad': 'Kitap 1'}],
      ]);
      final s = SenkronServisi(db: db, repo: repo, storeId: 's1');
      await s.calistir();
      expect(repo.sinceler.first, isNull);
      await s.calistir();
      expect(repo.sinceler.last, isNotNull,
          reason: '24.623 ürün her senkronda baştan inmemeli');
    });

    test('K42 · iptal edilen cihazda yerel veri silinir ve senkron durur',
        () async {
      final repo = SahteSenkronRepo(iptal: true, silinsin: true);
      await db.kuyrugaYaz('create_payment', const {}, 'Tahsilat');
      final r = await SenkronServisi(db: db, repo: repo, storeId: 's1')
          .calistir();

      expect(r.cihazIptal, isTrue);
      expect(r.ozet, contains('yerel veri silindi'));
      expect(await db.bekleyenSayisi(), 0);
      expect(repo.silmeOnaylandi, isTrue,
          reason: 'bayrak ancak istemci sildiğini bildirince kapanır');
      expect(repo.sira, isNot(contains('push')),
          reason: 'iptal edilen cihazdan yazma denenmez');
    });
  });
}

/// Sunucu yerine geçen sahte. Hangi çağrının hangi SIRAYLA yapıldığını da
/// kaydeder — senkron sırası bu modülün en kolay bozulan yanı.
class SahteSenkronRepo implements SenkronRepository {
  SahteSenkronRepo({this.iptal = false, this.silinsin = false,
                    this.basariliSeq, this.cariler = const [],
                    this.sayfalar = const []});

  final bool iptal, silinsin;
  final Set<int>? basariliSeq;
  List<Map<String, dynamic>> cariler;
  final List<List<Map<String, dynamic>>> sayfalar;

  final sira = <String>[];
  final imlecler = <String>[];
  final sinceler = <DateTime?>[];
  bool silmeOnaylandi = false;
  int _sayfa = 0;

  @override
  Future<CihazDurumu> cihazKaydet({required String clientId, String? ad,
      String? platform, String? surum}) async {
    sira.add('cihaz');
    return CihazDurumu(deviceId: 'd1', iptal: iptal, silinsin: silinsin);
  }

  @override
  Future<void> silmeOnayla(String clientId) async => silmeOnaylandi = true;

  @override
  Future<ItmeSonucu> kuyrugaYolla(
      String clientId, List<Map<String, dynamic>> ops) async {
    sira.add('push');
    var ok = 0, hata = 0;
    final satirlar = <ItmeSatiri>[];
    for (final op in ops) {
      final seq = op['local_seq'] as int;
      final basarili = basariliSeq == null || basariliSeq!.contains(seq);
      satirlar.add(ItmeSatiri(
          localSeq: seq, durum: basarili ? 'ok' : 'hata',
          sonuc: basarili ? {'id': 'x$seq'} : null,
          hata: basarili ? null : 'Cari bulunamadı'));
      basarili ? ok++ : hata++;
    }
    return ItmeSonucu(basarili: ok, hatali: hata, sonuclar: satirlar);
  }

  @override
  Future<Map<String, dynamic>> referans(String storeId) async {
    sira.add('referans');
    return {
      'sunucu_saati': DateTime(2026, 8, 25, 12).toIso8601String(),
      'cariler': cariler, 'kurumlar': const [], 'kisiler': const [],
    };
  }

  @override
  Future<KatalogSayfasi> katalog(String storeId, {DateTime? since,
      String? after, int limit = 500}) async {
    sira.add('katalog');
    imlecler.add(after ?? '');
    sinceler.add(since);
    if (_sayfa >= sayfalar.length) {
      _sayfa = 0;
      return const KatalogSayfasi();
    }
    final s = sayfalar[_sayfa++];
    final son = _sayfa >= sayfalar.length;
    if (son) _sayfa = 0;
    return KatalogSayfasi(
        satirlar: s, sonId: s.isEmpty ? null : s.last['id'] as String,
        sayi: s.length, bitti: son);
  }

  @override
  Future<List<CihazSatiri>> cihazlar() async => const [];
  @override
  Future<void> cihazIptal(String deviceId) async {}
}
