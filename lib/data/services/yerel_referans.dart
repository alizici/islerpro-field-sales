import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../local/yerel_db.dart';
import '../local/yerel_saglayici.dart';
import '../repositories/cari_repository.dart';
import '../repositories/kurum_repository.dart' show KurumOzet;
import '../repositories/talep_repository.dart';

/// Çevrimdışı referans okuması — cari, kurum, kişi.
///
/// Senkron bu üç listeyi zaten cihaza indiriyordu; okuyan yoktu. Sahadaki
/// sonuç şuydu: sinyalsiz okulda ürün araması çalışıyor ama **muhatap
/// seçilemediği için** talep yine girilemiyordu. Okuma yolu bağlanmadan
/// çevrimdışı yazma yolunun bir anlamı yok.
///
/// **Bu kopya sunucunun aynası değildir; kapsamı dardır.** `sync_reference`
/// yalnızca kullanıcının GÖREBİLDİĞİ, durumu `aktif`/`tahsilatta` olan
/// carileri indirir. Bu yüzden:
///
/// * pasif/kapalı cari yerelde **yoktur** — arama onu bulamaz;
/// * `atanmamis` süzgeci yerelde **cevaplanamaz** (portföy sahibi inmiyor);
/// * `risk` ve dönem bazlı bakiye yoktur — bunlar sunucuda türetilir (K45).
///
/// En önemlisi: **bakiye son senkron anına aittir.** Ekran bunu söylemeden
/// yerel bakiye göstermemelidir; bayat bir bakiyeye bakarak tahsilat yapan
/// pazarlamacı yanlış rakam okur.
class YerelReferans {
  const YerelReferans(this.db);
  final YerelDb? db;

  bool get kullanilabilir => db != null;

  /// Referans verinin indirildiği an. `null` ise hiç senkron yapılmamıştır.
  Future<DateTime?> tarih() async {
    final s = await db?.ayarOku('son_referans');
    return s == null ? null : DateTime.tryParse(s);
  }

  /// K42 · Cihazda GERÇEKTEN ne duruyor. Sahip bir cihazı iptal edip
  /// etmeyeceğine karar verirken "cari adı ve bakiye durur" cümlesine değil,
  /// ölçülmüş sayıya bakmalı.
  Future<YerelKopyaSayilari> sayilar() async {
    final d = db;
    if (d == null) return const YerelKopyaSayilari();
    Future<int> say(
        ResultSetImplementation<HasResultSet, dynamic> t,
        GeneratedColumn<String> id) {
      final c = id.count();
      return (d.selectOnly(t)..addColumns([c]))
          .getSingle()
          .then((r) => r.read(c) ?? 0);
    }
    return YerelKopyaSayilari(
      cari: await say(d.yerelCari, d.yerelCari.id),
      kurum: await say(d.yerelKurum, d.yerelKurum.id),
      kisi: await say(d.yerelKisi, d.yerelKisi.id),
      urun: await say(d.yerelUrun, d.yerelUrun.id),
      tarih: await tarih(),
    );
  }

  Future<bool> dolu() async {
    final d = db;
    if (d == null) return false;
    final s = d.yerelCari.id.count();
    final q = d.selectOnly(d.yerelCari)..addColumns([s]);
    return ((await q.getSingle()).read(s) ?? 0) > 0;
  }

  // ── Cari ─────────────────────────────────────────────────────────────────

  /// [borclu] yereldeki bakiyeye bakar — yani SON SENKRON anındaki borca.
  Future<List<CariOzet>> cariAra({
    String? q, String? tip, bool borclu = false, int limit = 200,
  }) async {
    final d = db;
    if (d == null) return const [];
    final sorgu = d.select(d.yerelCari)
      ..orderBy([(c) => OrderingTerm(expression: c.unvan)])
      ..limit(limit);
    final terim = (q ?? '').trim();
    if (terim.isNotEmpty) {
      // sqlite `lower()` yalnızca ASCII katlar: "İSTİKLAL" araması "İstiklal"i
      // bulur, "ISTIKLAL" bulmaz. Sunucudaki trigram aramasının yerini
      // tutmuyor — bilerek; yerel kopya bir yedek, ikinci bir arama motoru
      // değil.
      final k = '%${terim.toLowerCase()}%';
      sorgu.where((c) => c.unvan.lower().like(k));
    }
    if (tip != null) sorgu.where((c) => c.tip.equals(tip));
    if (borclu) sorgu.where((c) => c.bakiye.isBiggerThanValue(0));

    final satirlar = await sorgu.get();
    final kurumlar = await _kurumAdlari(satirlar.map((c) => c.kurumId));
    return [
      for (final c in satirlar)
        CariOzet(
          id: c.id, tip: c.tip, unvan: c.unvan, durum: c.durum,
          institutionId: c.kurumId ?? '',
          kurumAd: kurumlar[c.kurumId]?.ad,
          ilce: kurumlar[c.kurumId]?.ilce,
          discountTier: c.kademe,
          creditLimit: c.krediLimiti,
          bakiye: c.bakiye,
          // K11 · Risk = bakiye + vadesi gelmemiş çek. Çekler yerelde YOK,
          // bu yüzden risk hesaplanamaz; sıfır yazıp "risk yok" demek yerine
          // bakiyeyi olduğu gibi bırakıyoruz — ekran riski yerelde göstermez.
          risk: c.bakiye,
          limitAsildi: c.krediLimiti > 0 && c.bakiye > c.krediLimiti,
        ),
    ];
  }

  Future<CariOzet?> cari(String id) async {
    final l = await cariAra(limit: 1000);
    for (final c in l) {
      if (c.id == id) return c;
    }
    return null;
  }

  // ── Muhatap (talep açarken) ──────────────────────────────────────────────

  /// K5 · Muhatap caridir. Yereldeki liste portföyün kendisidir; öğretmenin
  /// "kendi carisi" işareti (`kendi`) inmediği için burada her zaman `false`
  /// döner — çevrimdışı talep açan pazarlamacıdır, öğretmen değil.
  Future<List<Muhatap>> muhataplar(String storeId) async {
    final l = await cariAra(limit: 500);
    return [
      for (final c in l)
        Muhatap(id: c.id, tip: c.tip, unvan: c.unvan, storeId: storeId,
                kurumAd: c.kurumAd, ilce: c.ilce),
    ];
  }

  // ── Kurum ────────────────────────────────────────────────────────────────

  /// Yerelde yalnızca **portföyümdeki carilerin kurumları** vardır; kurum
  /// dizininin tamamı inmez. `bagli` bu yüzden daima doğrudur.
  Future<List<KurumOzet>> kurumAra({String? q, int limit = 200}) async {
    final d = db;
    if (d == null) return const [];
    final sorgu = d.select(d.yerelKurum)
      ..orderBy([(k) => OrderingTerm(expression: k.ad)])
      ..limit(limit);
    final terim = (q ?? '').trim();
    if (terim.isNotEmpty) {
      sorgu.where((k) => k.ad.lower().like('%${terim.toLowerCase()}%'));
    }
    final satirlar = await sorgu.get();
    final sayilar = await _cariSayilari();
    return [
      for (final k in satirlar)
        KurumOzet(
          id: k.id, ad: k.ad, kurumTipi: k.tip ?? 'okul',
          il: k.il, ilce: k.ilce,
          bagli: true,
          cariSayisi: sayilar[k.id] ?? 0,
        ),
    ];
  }

  /// K30 · Kişiler işletmeye özeldir; yerelde de yalnızca kendi kayıtları.
  Future<List<YerelKisiData>> kisiler(String kurumId) async {
    final d = db;
    if (d == null) return const [];
    return (d.select(d.yerelKisi)
          ..where((k) => k.kurumId.equals(kurumId))
          ..orderBy([(k) => OrderingTerm(expression: k.adSoyad)]))
        .get();
  }

  // ── Yardımcılar ──────────────────────────────────────────────────────────

  Future<Map<String?, YerelKurumData>> _kurumAdlari(
      Iterable<String?> idler) async {
    final d = db;
    final istenen = idler.whereType<String>().toSet();
    if (d == null || istenen.isEmpty) return const {};
    final satirlar = await (d.select(d.yerelKurum)
          ..where((k) => k.id.isIn(istenen)))
        .get();
    return {for (final k in satirlar) k.id: k};
  }

  Future<Map<String, int>> _cariSayilari() async {
    final d = db;
    if (d == null) return const {};
    final sayac = d.yerelCari.id.count();
    final q = d.selectOnly(d.yerelCari)
      ..addColumns([d.yerelCari.kurumId, sayac])
      ..where(d.yerelCari.kurumId.isNotNull())
      ..groupBy([d.yerelCari.kurumId]);
    final cikti = <String, int>{};
    for (final r in await q.get()) {
      final k = r.read(d.yerelCari.kurumId);
      if (k != null) cikti[k] = r.read(sayac) ?? 0;
    }
    return cikti;
  }
}

class YerelKopyaSayilari {
  const YerelKopyaSayilari({this.cari = 0, this.kurum = 0, this.kisi = 0,
                            this.urun = 0, this.tarih});
  final int cari, kurum, kisi, urun;
  final DateTime? tarih;

  bool get bos => cari == 0 && kurum == 0 && kisi == 0 && urun == 0;
}

final yerelReferansProvider =
    Provider<YerelReferans>((ref) => YerelReferans(ref.watch(yerelDbProvider)));

/// K42 · Cihazdaki kopyanın ölçülmüş dökümü.
final yerelKopyaSayilariProvider =
    FutureProvider.autoDispose<YerelKopyaSayilari>((ref) =>
        ref.watch(yerelReferansProvider).sayilar());

/// Referans kopyasının indirildiği an. Ekranlarda "ne kadar bayat" sorusunun
/// cevabıdır; `null` iken uyarı gösterilmez çünkü söylenecek bir tarih yoktur.
final yerelReferansTarihiProvider =
    FutureProvider.autoDispose<DateTime?>((ref) =>
        ref.watch(yerelReferansProvider).tarih());
