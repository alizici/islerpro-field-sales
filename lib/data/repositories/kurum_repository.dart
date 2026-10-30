import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/network/supabase.dart';

/// Kurum dizini (K18) — okul ve özel kurs merkezi birlikte.
/// Dizin ortaktır (K4); kişi kayıtları işletmeye özeldir (K30).
class KurumRepository {
  KurumRepository(this._db);
  final SupabaseClient _db;

  Future<List<KurumOzet>> ara({
    String? q, String? il, String? ilce, String? kurumTipi, int limit = 50,
  }) async {
    final r = await _db.rpc<dynamic>('search_institutions', params: {
      'p_q': (q ?? '').trim().isEmpty ? null : q!.trim(),
      'p_il': il, 'p_ilce': ilce, 'p_kurum_tipi': kurumTipi, 'p_limit': limit,
    });
    return (r as List).map((e) => KurumOzet.fromJson((e as Map).cast())).toList();
  }

  /// Ö-8 · Kurum eklerken benzerlik kontrolü. Dizin ortak olduğu için mükerrer
  /// kayıt yalnızca bu işletmeyi değil herkesi etkiler.
  Future<List<BenzerKurum>> benzerler(String ad, {String? ilce}) async {
    if (ad.trim().length < 3) return const [];
    final r = await _db.rpc<dynamic>('similar_institutions',
        params: {'p_ad': ad.trim(), 'p_ilce': ilce});
    return (r as List).map((e) => BenzerKurum.fromJson((e as Map).cast())).toList();
  }

  Future<String> ekle({
    required String ad,
    required String kurumTipi,
    String? il, String? ilce, String? kademe, String? tur,
    String? mebKodu, int? ogrenciSayisi, String? storeId,
  }) async {
    final r = await _db.rpc<dynamic>('add_institution', params: {
      'p_ad': ad, 'p_kurum_tipi': kurumTipi, 'p_il': il, 'p_ilce': ilce,
      'p_kademe': kademe, 'p_tur': tur, 'p_meb_kodu': mebKodu,
      'p_ogrenci_sayisi': ogrenciSayisi, 'p_store_id': storeId,
    });
    return (r as Map)['id'] as String;
  }

  Future<void> bagla(String institutionId, String storeId, {bool bagla = true}) =>
      _db.rpc<dynamic>('link_institution', params: {
        'p_institution_id': institutionId, 'p_store_id': storeId, 'p_bagla': bagla,
      });

  Future<KurumDetay> detay(String id) async {
    final r = await _db.rpc<dynamic>('institution_detail', params: {'p_id': id});
    return KurumDetay.fromJson((r as Map).cast());
  }

  Future<List<(String il, String ilce)>> bolgeler() async {
    final r = await _db.rpc<dynamic>('institution_regions');
    return (r as List)
        .map((e) => ((e as Map)['il'] as String, e['ilce'] as String? ?? ''))
        .toList();
  }

  /// K3 · Öğretmen daveti — kod kurumu ve dükkanı taşır.
  Future<String> ogretmenDaveti(String institutionId, String storeId,
      {String? telefon}) async {
    final r = await _db.rpc<dynamic>('create_invite', params: {
      'p_institution_id': institutionId, 'p_store_id': storeId,
      'p_telefon': telefon,
    });
    return (r as Map)['kod'] as String;
  }
}

final kurumRepositoryProvider =
    Provider<KurumRepository>((ref) => KurumRepository(ref.watch(supabaseProvider)));

// ── Modeller ───────────────────────────────────────────────────────────────
class KurumOzet {
  const KurumOzet({
    required this.id, required this.ad, required this.kurumTipi,
    this.kademe, this.tur, this.il, this.ilce, this.mebKodu,
    this.ogrenciSayisi, this.dogrulandi = false,
    this.bagli = false, this.cariSayisi = 0, this.benzerlik = 0,
  });
  final String id, ad, kurumTipi;
  final String? kademe, tur, il, ilce, mebKodu;
  final int? ogrenciSayisi;
  final bool dogrulandi, bagli;
  final int cariSayisi;
  final double benzerlik;

  bool get kursMerkezi => kurumTipi == 'kurs_merkezi';
  String get altBilgi => [
        if (kademe != null) kademeAd(kademe!),
        ?tur,
        ?ilce,
      ].join(' · ');

  static String kademeAd(String k) => switch (k) {
        'anaokulu' => 'Anaokulu',
        'ilkokul' => 'İlkokul',
        'ortaokul' => 'Ortaokul',
        'lise' => 'Lise',
        _ => k,
      };

  static KurumOzet fromJson(Map<String, dynamic> j) => KurumOzet(
        id: j['id'] as String, ad: j['ad'] as String? ?? '',
        kurumTipi: j['kurum_tipi'] as String? ?? 'okul',
        kademe: j['kademe'] as String?, tur: j['tur'] as String?,
        il: j['il'] as String?, ilce: j['ilce'] as String?,
        mebKodu: j['meb_kodu'] as String?,
        ogrenciSayisi: (j['ogrenci_sayisi'] as num?)?.toInt(),
        dogrulandi: j['dogrulandi'] as bool? ?? false,
        bagli: j['bagli'] as bool? ?? false,
        cariSayisi: (j['cari_sayisi'] as num?)?.toInt() ?? 0,
        benzerlik: (j['benzerlik'] as num?)?.toDouble() ?? 0,
      );
}

class BenzerKurum {
  const BenzerKurum({required this.id, required this.ad, required this.benzerlik,
                     this.ilce, this.dogrulandi = false});
  final String id, ad;
  final double benzerlik;
  final String? ilce;
  final bool dogrulandi;
  static BenzerKurum fromJson(Map<String, dynamic> j) => BenzerKurum(
        id: j['id'] as String, ad: j['ad'] as String? ?? '',
        benzerlik: (j['benzerlik'] as num?)?.toDouble() ?? 0,
        ilce: j['ilce'] as String?, dogrulandi: j['dogrulandi'] as bool? ?? false,
      );
}

class KurumDetay {
  const KurumDetay({required this.kurum, this.subeler = const [],
                    this.cariler = const [], this.kisiler = const []});
  final KurumOzet kurum;
  final List<({String id, String ad})> subeler;
  final List<CariOzet> cariler;
  final List<KisiOzet> kisiler;

  static KurumDetay fromJson(Map<String, dynamic> j) => KurumDetay(
        kurum: KurumOzet.fromJson((j['kurum'] as Map).cast()),
        subeler: ((j['subeler'] as List?) ?? [])
            .map((e) => (id: (e as Map)['id'] as String, ad: e['ad'] as String? ?? ''))
            .toList(),
        cariler: ((j['cariler'] as List?) ?? [])
            .map((e) => CariOzet.fromJson((e as Map).cast())).toList(),
        kisiler: ((j['kisiler'] as List?) ?? [])
            .map((e) => KisiOzet.fromJson((e as Map).cast())).toList(),
      );
}

class CariOzet {
  const CariOzet({required this.id, required this.tip, required this.unvan,
                  required this.bakiye, required this.limit, required this.durum,
                  this.portfoySahibi});
  final String id, tip, unvan, durum;
  final double bakiye, limit;
  final String? portfoySahibi;
  bool get kurumsal => tip == 'kurum';
  static CariOzet fromJson(Map<String, dynamic> j) => CariOzet(
        id: j['id'] as String, tip: j['tip'] as String? ?? 'kurum',
        unvan: j['unvan'] as String? ?? '',
        bakiye: (j['bakiye'] as num?)?.toDouble() ?? 0,
        limit: (j['limit'] as num?)?.toDouble() ?? 0,
        durum: j['durum'] as String? ?? 'aktif',
        portfoySahibi: j['portfoy_sahibi'] as String?,
      );
}

class KisiOzet {
  const KisiOzet({required this.id, required this.adSoyad, this.telefon,
                  this.brans, this.gorev, this.hesabiVar = false});
  final String id, adSoyad;
  final String? telefon, brans, gorev;
  final bool hesabiVar;
  static KisiOzet fromJson(Map<String, dynamic> j) => KisiOzet(
        id: j['id'] as String, adSoyad: j['ad_soyad'] as String? ?? '',
        telefon: j['telefon'] as String?, brans: j['brans'] as String?,
        gorev: j['gorev'] as String?, hesabiVar: j['hesabi_var'] as bool? ?? false,
      );
}
