import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/network/supabase.dart';

/// Katalog (K15: kitap ve deneme tek tabloda) + dükkanın ticari katmanı (K12).
///
/// Ürün kimliği ortaktır, fiyat/iskonto/stok dükkana özeldir. Arama ikisini
/// tek satırda döndürür — pazarlamacı iki ekran arasında gidip gelmesin.
class KatalogRepository {
  KatalogRepository(this._db);
  final SupabaseClient _db;

  Future<List<UrunOzet>> ara({
    required String storeId,
    String? q,
    String? katalog,
    String? publisherId,
    int? sinif,
    String? fiyatDurumu,   // null · 'fiyatli' · 'fiyatsiz'
    bool arsiv = false,
    int limit = 50,
    int offset = 0,
  }) async {
    final r = await _db.rpc<dynamic>('search_products', params: {
      'p_store_id': storeId,
      'p_q': (q ?? '').trim().isEmpty ? null : q!.trim(),
      'p_katalog': katalog,
      'p_publisher_id': publisherId,
      'p_sinif': sinif,
      'p_fiyat_durumu': fiyatDurumu,
      'p_arsiv': arsiv,
      'p_limit': limit,
      'p_offset': offset,
    });
    return (r as List).map((e) => UrunOzet.fromJson((e as Map).cast())).toList();
  }

  /// Aynı süzgeçlerle toplam sayı — sonsuz kaydırmanın ve göç takibinin paydası.
  Future<int> say({
    required String storeId,
    String? q, String? katalog, String? publisherId, int? sinif,
    String? fiyatDurumu, bool arsiv = false,
  }) async {
    final r = await _db.rpc<dynamic>('count_products', params: {
      'p_store_id': storeId,
      'p_q': (q ?? '').trim().isEmpty ? null : q!.trim(),
      'p_katalog': katalog, 'p_publisher_id': publisherId, 'p_sinif': sinif,
      'p_fiyat_durumu': fiyatDurumu, 'p_arsiv': arsiv,
    });
    return (r as num).toInt();
  }

  /// K24 · Barkod benzersizdir; okuyucudan gelen tek atış.
  Future<UrunOzet?> barkodla(String storeId, String barkod) async {
    final r = await _db.rpc<dynamic>('product_by_barcode',
        params: {'p_store_id': storeId, 'p_barkod': barkod.trim()});
    if (r == null) return null;
    return UrunOzet.fromJson((r as Map).cast());
  }

  /// Barkod çakışırsa yeni kayıt AÇILMAZ; mevcut ürün döner (K24).
  Future<({String id, bool yeni, String? mesaj})> urunEkle({
    required String storeId,
    required String ad,
    String katalog = 'kitap',
    String? barkod,
    String? urunKod,
    String? yayinevi,
    String? kategori,
    String? ders,
    List<int>? sinif,
    String? sinavTipi,
    double? etiketFiyat,
    String? baskiEtiketi,
  }) async {
    final r = await _db.rpc<dynamic>('add_product', params: {
      'p_store_id': storeId, 'p_ad': ad, 'p_katalog': katalog,
      'p_barkod': barkod, 'p_urun_kod': urunKod, 'p_yayinevi': yayinevi,
      'p_kategori': kategori, 'p_ders': ders, 'p_sinif': sinif,
      'p_sinav_tipi': sinavTipi, 'p_etiket_fiyat': etiketFiyat,
      'p_baski_etiketi': baskiEtiketi,
    });
    final m = (r as Map).cast<String, dynamic>();
    return (id: m['id'] as String, yeni: m['yeni'] as bool? ?? false,
            mesaj: m['mesaj'] as String?);
  }

  /// K12 · Dükkanın fiyat katmanı. null geçilen alan DEĞİŞTİRİLMEZ.
  Future<void> fiyatKaydet({
    required String storeId,
    required String productId,
    double? satisFiyat,
    double? alisFiyat,
    double? varsayilanIskonto,
    bool? stokTakibi,
    bool? aktif,
  }) =>
      _db.rpc<dynamic>('upsert_store_product', params: {
        'p_store_id': storeId, 'p_product_id': productId,
        'p_satis_fiyat': satisFiyat, 'p_alis_fiyat': alisFiyat,
        'p_varsayilan_iskonto': varsayilanIskonto,
        'p_stok_takibi': stokTakibi, 'p_aktif': aktif,
      });

  /// K25 · Bir carinin bu üründeki iskontosu — ve NEDEN o oran olduğu.
  Future<IskontoSonuc> iskonto({
    required String storeId,
    required String accountId,
    required String productId,
    int adet = 1,
  }) async {
    final r = await _db.rpc<dynamic>('resolve_discount_detail', params: {
      'p_store': storeId, 'p_account': accountId,
      'p_product': productId, 'p_adet': adet,
    });
    return IskontoSonuc.fromJson((r as Map).cast());
  }

  /// K25 · Tavan aşılırsa sipariş engellenmez, onaya düşer.
  Future<({double? tavan, bool asildi})> tavanKontrol(
      String storeId, double iskonto) async {
    final r = await _db.rpc<dynamic>('check_discount_cap',
        params: {'p_store': storeId, 'p_iskonto': iskonto});
    final m = (r as Map).cast<String, dynamic>();
    return (tavan: (m['tavan'] as num?)?.toDouble(),
            asildi: m['asildi'] as bool? ?? false);
  }

  // ── K23 · Baskı grupları ────────────────────────────────────────────────
  // Baskı ilişkisi tahmin edilmez, insan söyler. Grup yeni baskı eklenirken
  // doğar; ad içindeki yıl bilgisinden ASLA üretilmez.

  Future<({String id, String grupId, int sira})> baskiEkle({
    required String storeId,
    required String kaynakUrunId,
    required String baskiEtiketi,
    String? barkod,
    double? etiketFiyat,
    bool eskiyiArsivle = false,
  }) async {
    final r = await _db.rpc<dynamic>('add_edition', params: {
      'p_store_id': storeId, 'p_kaynak_product_id': kaynakUrunId,
      'p_baski_etiketi': baskiEtiketi, 'p_barkod': barkod,
      'p_etiket_fiyat': etiketFiyat, 'p_eski_arsivle': eskiyiArsivle,
    });
    final m = (r as Map).cast<String, dynamic>();
    return (id: m['id'] as String, grupId: m['grup_id'] as String,
            sira: (m['sira'] as num?)?.toInt() ?? 1);
  }

  Future<List<Baski>> baskilar(String urunId, String storeId) async {
    final r = await _db.rpc<dynamic>('edition_group',
        params: {'p_product_id': urunId, 'p_store_id': storeId});
    return ((r ?? []) as List)
        .map((e) => Baski.fromJson((e as Map).cast())).toList();
  }

  /// İki yönlü uyarı: eski baskı seçiliyse güncelini gösterir. Karar
  /// kullanıcınındır — sistemin işi sessiz kalmamaktır.
  Future<BaskiUyarisi> baskiUyarisi(String urunId, String storeId) async {
    final r = await _db.rpc<dynamic>('edition_warning',
        params: {'p_product_id': urunId, 'p_store_id': storeId});
    return BaskiUyarisi.fromJson(((r ?? {}) as Map).cast());
  }

  Future<void> baskiyaBagla(String urunId, String hedefUrunId) =>
      _db.rpc<dynamic>('link_edition', params: {
        'p_product_id': urunId, 'p_hedef_product_id': hedefUrunId,
      });

  Future<void> baskidanCikar(String urunId) =>
      _db.rpc<dynamic>('unlink_edition', params: {'p_product_id': urunId});


  /// K27 · K45 · Stok bir SAYAÇTIR, defter değildir. Bilgi amaçlıdır,
  /// siparişi engellemez.

  Future<List<Yayinevi>> yayinevleri({String? storeId}) async {
    final r = await _db.rpc<dynamic>('list_publishers',
        params: {'p_store_id': storeId});
    return (r as List).map((e) => Yayinevi.fromJson((e as Map).cast())).toList();
  }
}

final katalogRepositoryProvider = Provider<KatalogRepository>(
    (ref) => KatalogRepository(ref.watch(supabaseProvider)));

// ── Modeller ───────────────────────────────────────────────────────────────

class UrunOzet {
  const UrunOzet({
    required this.id, required this.ad, required this.katalog,
    this.barkod, this.urunKod, this.yayinevi, this.publisherId,
    this.kategori, this.ders, this.sinavTipi, this.sinif = const [],
    this.etiketFiyat, this.baskiEtiketi,
    this.satisFiyat, this.alisFiyat, this.varsayilanIskonto = 0,
    this.stokAdedi, this.stokTakibi = true,
    this.fiyatli = false, this.arsivlendi = false, this.ozel = false,
  });

  final String id, ad, katalog;
  final String? barkod, urunKod, yayinevi, publisherId, kategori, ders,
      sinavTipi, baskiEtiketi;
  final List<int> sinif;
  /// Yayınevi listesi — yalnızca gösterim. Hiçbir hesaba girmez (K25).
  final double? etiketFiyat;
  /// İskontonun tabanı (K25).
  final double? satisFiyat, alisFiyat;
  final double varsayilanIskonto;
  final int? stokAdedi;
  final bool stokTakibi, fiyatli, arsivlendi, ozel;

  bool get deneme => katalog == 'deneme';

  /// Fiyatı olmayan ürün sipariş edilemez — listede bunu ayırt etmek gerekir.
  bool get fiyatsiz => satisFiyat == null;

  String get altBilgi => [
        ?yayinevi,
        if (sinif.isNotEmpty) '${sinif.map((e) => e == 13 ? 'Mezun' : '$e').join('·')}. sınıf',
        ?ders,
        ?sinavTipi,
        ?baskiEtiketi,
      ].join(' · ');

  static UrunOzet fromJson(Map<String, dynamic> j) => UrunOzet(
        id: j['id'] as String,
        ad: j['ad'] as String? ?? '',
        katalog: j['katalog'] as String? ?? 'kitap',
        barkod: j['barkod'] as String?,
        urunKod: j['urun_kod'] as String?,
        yayinevi: j['yayinevi'] as String?,
        publisherId: j['publisher_id'] as String?,
        kategori: j['kategori'] as String?,
        ders: j['ders'] as String?,
        sinavTipi: j['sinav_tipi'] as String?,
        sinif: ((j['sinif'] as List?) ?? const [])
            .map((e) => (e as num).toInt()).toList(),
        etiketFiyat: (j['etiket_fiyat'] as num?)?.toDouble(),
        baskiEtiketi: j['baski_etiketi'] as String?,
        satisFiyat: (j['satis_fiyat'] as num?)?.toDouble(),
        alisFiyat: (j['alis_fiyat'] as num?)?.toDouble(),
        varsayilanIskonto: (j['varsayilan_iskonto'] as num?)?.toDouble() ?? 0,
        stokAdedi: (j['stok_adedi'] as num?)?.toInt(),
        stokTakibi: j['stok_takibi'] as bool? ?? true,
        fiyatli: j['fiyatli'] as bool? ?? false,
        arsivlendi: j['arsivlendi'] as bool? ?? false,
        ozel: j['ozel'] as bool? ?? false,
      );
}

/// K25 · Oran tek başına yetmez; pazarlamacı "neden %25?" diye sorabilmeli.
class IskontoSonuc {
  const IskontoSonuc({required this.oran, required this.kaynak,
                      required this.kaynakAd, this.kuralId});
  final double oran;
  /// kademe · kural · dukkan_varsayilani · yok
  final String kaynak, kaynakAd;
  final String? kuralId;

  bool get kuraldanGeliyor => kaynak == 'kademe' || kaynak == 'kural';

  static IskontoSonuc fromJson(Map<String, dynamic> j) => IskontoSonuc(
        oran: (j['oran'] as num?)?.toDouble() ?? 0,
        kaynak: j['kaynak'] as String? ?? 'yok',
        kaynakAd: j['kaynak_ad'] as String? ?? '',
        kuralId: j['kural_id'] as String?,
      );
}

class Yayinevi {
  const Yayinevi({required this.id, required this.ad,
                  this.urunSayisi = 0, this.fiyatliSayisi = 0});
  final String id, ad;
  final int urunSayisi, fiyatliSayisi;
  static Yayinevi fromJson(Map<String, dynamic> j) => Yayinevi(
        id: j['id'] as String, ad: j['ad'] as String? ?? '',
        urunSayisi: (j['urun_sayisi'] as num?)?.toInt() ?? 0,
        fiyatliSayisi: (j['fiyatli_sayisi'] as num?)?.toInt() ?? 0,
      );
}

/// K23 · Bir baskı grubundaki tek satır.
class Baski {
  const Baski({required this.id, required this.ad, this.baskiEtiketi,
               this.baskiSirasi = 1, this.barkod, this.etiketFiyat,
               this.satisFiyat, this.stokAdedi, this.arsivlendi = false,
               this.guncel = false, this.secili = false, this.guncelEtiket});
  final String id, ad;
  final String? baskiEtiketi, barkod, guncelEtiket;
  final int baskiSirasi;
  final double? etiketFiyat, satisFiyat;
  final int? stokAdedi;
  final bool arsivlendi, guncel, secili;

  String get etiket => baskiEtiketi ?? '\$baskiSirasi. baskı';

  static Baski fromJson(Map<String, dynamic> j) => Baski(
        id: j['id'] as String,
        ad: j['ad'] as String? ?? '',
        baskiEtiketi: j['baski_etiketi'] as String?,
        baskiSirasi: (j['baski_sirasi'] as num?)?.toInt() ?? 1,
        barkod: j['barkod'] as String?,
        etiketFiyat: (j['etiket_fiyat'] as num?)?.toDouble(),
        satisFiyat: (j['satis_fiyat'] as num?)?.toDouble(),
        stokAdedi: (j['stok_adedi'] as num?)?.toInt(),
        arsivlendi: j['arsivlendi'] as bool? ?? false,
        guncel: j['guncel'] as bool? ?? false,
        secili: j['secili'] as bool? ?? false,
        guncelEtiket: j['guncel_etiket'] as String?,
      );
}

class BaskiUyarisi {
  const BaskiUyarisi({this.uyari = false, this.guncel, this.secili});
  final bool uyari;
  final Baski? guncel, secili;

  static BaskiUyarisi fromJson(Map<String, dynamic> j) => BaskiUyarisi(
        uyari: j['uyari'] as bool? ?? false,
        guncel: j['guncel'] == null
            ? null : Baski.fromJson((j['guncel'] as Map).cast()),
        secili: j['secili'] == null
            ? null : Baski.fromJson((j['secili'] as Map).cast()),
      );
}


class StokSatiri {
  const StokSatiri({required this.id, required this.ad, this.barkod,
                    this.yayinevi, this.baskiEtiketi, this.stokAdedi = 0,
                    this.satisFiyat, this.deger = 0});
  final String id, ad;
  final String? barkod, yayinevi, baskiEtiketi;
  final int stokAdedi;
  final double? satisFiyat;
  final double deger;
  static StokSatiri fromJson(Map<String, dynamic> j) => StokSatiri(
        id: j['id'] as String, ad: j['ad'] as String? ?? '',
        barkod: j['barkod'] as String?, yayinevi: j['yayinevi'] as String?,
        baskiEtiketi: j['baski_etiketi'] as String?,
        stokAdedi: (j['stok_adedi'] as num?)?.toInt() ?? 0,
        satisFiyat: (j['satis_fiyat'] as num?)?.toDouble(),
        deger: (j['deger'] as num?)?.toDouble() ?? 0,
      );
}
