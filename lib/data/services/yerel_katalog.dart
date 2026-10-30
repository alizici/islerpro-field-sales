import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../local/yerel_db.dart';
import '../local/yerel_saglayici.dart';
import '../repositories/katalog_repository.dart';

/// Çevrimdışı katalog okuması.
///
/// Senkron 24.623 ürünü cihaza indiriyor; okumayan bir kopya boşuna yer
/// kaplardı. Sahada asıl ihtiyaç budur: okulda sinyal yokken "hangi ürün,
/// kaç lira" sorusunun cevabı verilebilmeli.
///
/// Arama sunucudaki `search_products` kadar zengin değildir (trigram benzerlik
/// yok, sınıf/yayınevi süzgeci yok) — bilerek: yerel kopya bir yedek, ikinci
/// bir katalog motoru değil.
class YerelKatalog {
  const YerelKatalog(this.db);
  final YerelDb? db;

  bool get kullanilabilir => db != null;

  Future<List<UrunOzet>> ara(String? q, {int limit = 15}) async {
    final d = db;
    if (d == null) return const [];
    final terim = (q ?? '').trim();
    final sorgu = d.select(d.yerelUrun)
      ..where((u) => u.aktif.equals(true) & u.satisFiyat.isNotNull())
      ..orderBy([(u) => OrderingTerm(expression: u.ad)])
      ..limit(limit);
    if (terim.isNotEmpty) {
      // Barkod tam eşleşir, ad içinde geçer.
      //
      // sqlite'ın `lower()` ve `LIKE`'ı yalnızca ASCII harfleri katlar:
      // "İSTİKLAL" araması "İstiklal"i bulur ama "ISTIKLAL" bulmaz. Sunucudaki
      // trigram aramasının yerini tutmuyor — bilerek. Yerel kopya bir yedek,
      // ikinci bir katalog motoru değil.
      final k = '%${terim.toLowerCase()}%';
      sorgu.where((u) => u.ad.lower().like(k) | u.barkod.equals(terim));
    }
    final satirlar = await sorgu.get();
    return satirlar.map(_cevir).toList();
  }

  Future<UrunOzet?> barkodla(String barkod) async {
    final d = db;
    if (d == null) return null;
    final r = await (d.select(d.yerelUrun)
          ..where((u) => u.barkod.equals(barkod))
          ..limit(1))
        .getSingleOrNull();
    return r == null ? null : _cevir(r);
  }

  Future<int> sayi() async {
    final d = db;
    if (d == null) return 0;
    final s = d.yerelUrun.id.count();
    final q = d.selectOnly(d.yerelUrun)..addColumns([s]);
    return (await q.getSingle()).read(s) ?? 0;
  }

  static UrunOzet _cevir(YerelUrunData u) => UrunOzet(
        id: u.id, ad: u.ad, katalog: 'kitap',
        barkod: u.barkod, yayinevi: u.yayinevi, kategori: u.kategori,
        ders: u.ders, satisFiyat: u.satisFiyat,
        varsayilanIskonto: u.varsayilanIskonto,
        stokAdedi: u.stokAdedi, fiyatli: u.satisFiyat != null,
      );
}

final yerelKatalogProvider =
    Provider<YerelKatalog>((ref) => YerelKatalog(ref.watch(yerelDbProvider)));
