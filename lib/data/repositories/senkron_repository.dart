import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/network/supabase.dart';

/// K43 senkron sözleşmesi ve K42 cihaz kayıtlarının sunucu yüzü (Faz 7).
class SenkronRepository {
  SenkronRepository(this._db);
  final SupabaseClient _db;

  Future<CihazDurumu> cihazKaydet({
    required String clientId, String? ad, String? platform, String? surum,
  }) async {
    final r = await _db.rpc<dynamic>('register_device', params: {
      'p_client_id': clientId, 'p_ad': ad,
      'p_platform': platform, 'p_surum': surum,
    });
    return CihazDurumu.fromJson(((r ?? {}) as Map).cast());
  }

  Future<void> silmeOnayla(String clientId) =>
      _db.rpc<dynamic>('confirm_wipe', params: {'p_client_id': clientId});

  Future<List<CihazSatiri>> cihazlar() async {
    final r = await _db.rpc<dynamic>('list_devices');
    return ((r as List?) ?? const [])
        .map((e) => CihazSatiri.fromJson((e as Map).cast())).toList();
  }

  Future<void> cihazIptal(String deviceId) =>
      _db.rpc<dynamic>('revoke_device', params: {'p_device_id': deviceId});

  /// Kuyruğun tamamı TEK istekte gider (bkz. 0032 başlığı).
  Future<ItmeSonucu> kuyrugaYolla(String clientId,
      List<Map<String, dynamic>> ops) async {
    final r = await _db.rpc<dynamic>('sync_push',
        params: {'p_client_id': clientId, 'p_ops': ops});
    return ItmeSonucu.fromJson(((r ?? {}) as Map).cast());
  }

  Future<Map<String, dynamic>> referans(String storeId) async {
    final r = await _db.rpc<dynamic>('sync_reference',
        params: {'p_store_id': storeId});
    if (r == null) throw StateError('Referans veri alınamadı');
    return (r as Map).cast<String, dynamic>();
  }

  Future<KatalogSayfasi> katalog(String storeId,
      {DateTime? since, String? after, int limit = 500}) async {
    final r = await _db.rpc<dynamic>('sync_catalog', params: {
      'p_store_id': storeId,
      'p_since': since?.toUtc().toIso8601String(),
      'p_after': after, 'p_limit': limit,
    });
    return KatalogSayfasi.fromJson(((r ?? {}) as Map).cast());
  }
}

final senkronRepositoryProvider = Provider<SenkronRepository>(
    (ref) => SenkronRepository(ref.watch(supabaseProvider)));

// ── Modeller ───────────────────────────────────────────────────────────────

class CihazDurumu {
  const CihazDurumu({this.deviceId, this.iptal = false, this.silinsin = false});
  final String? deviceId;
  final bool iptal, silinsin;
  static CihazDurumu fromJson(Map<String, dynamic> j) => CihazDurumu(
        deviceId: j['device_id'] as String?,
        iptal: j['iptal'] as bool? ?? false,
        silinsin: j['silinsin'] as bool? ?? false,
      );
}

class CihazSatiri {
  const CihazSatiri({required this.id, required this.userId,
                     required this.adSoyad, required this.cihaz,
                     this.platform, this.surum, this.sonGorulme,
                     this.gun = 0, this.iptal = false});
  final String id, userId, adSoyad, cihaz;
  final String? platform, surum;
  final DateTime? sonGorulme;
  final int gun;
  final bool iptal;
  static CihazSatiri fromJson(Map<String, dynamic> j) => CihazSatiri(
        id: j['id'] as String,
        userId: j['user_id'] as String? ?? '',
        adSoyad: j['ad_soyad'] as String? ?? '—',
        cihaz: j['cihaz'] as String? ?? 'bilinmeyen cihaz',
        platform: j['platform'] as String?,
        surum: j['surum'] as String?,
        sonGorulme: j['son_gorulme'] == null
            ? null : DateTime.parse(j['son_gorulme'] as String).toLocal(),
        gun: (j['gun'] as num?)?.toInt() ?? 0,
        iptal: j['iptal'] as bool? ?? false,
      );
}

class ItmeSonucu {
  const ItmeSonucu({this.basarili = 0, this.hatali = 0, this.tekrar = 0,
                    this.sonuclar = const []});
  final int basarili, hatali, tekrar;
  final List<ItmeSatiri> sonuclar;
  static ItmeSonucu fromJson(Map<String, dynamic> j) => ItmeSonucu(
        basarili: (j['basarili'] as num?)?.toInt() ?? 0,
        hatali: (j['hatali'] as num?)?.toInt() ?? 0,
        tekrar: (j['tekrar'] as num?)?.toInt() ?? 0,
        sonuclar: ((j['sonuclar'] as List?) ?? const [])
            .map((e) => ItmeSatiri.fromJson((e as Map).cast())).toList(),
      );
}

class ItmeSatiri {
  const ItmeSatiri({required this.localSeq, required this.durum,
                    this.sonuc, this.hata, this.tekrar = false});
  final int localSeq;
  final String durum;
  final Map<String, dynamic>? sonuc;
  final String? hata;
  final bool tekrar;
  bool get basarili => durum == 'ok';
  static ItmeSatiri fromJson(Map<String, dynamic> j) => ItmeSatiri(
        localSeq: (j['local_seq'] as num).toInt(),
        durum: j['durum'] as String? ?? 'hata',
        sonuc: (j['sonuc'] as Map?)?.cast<String, dynamic>(),
        hata: j['hata'] as String?,
        tekrar: j['tekrar'] as bool? ?? false,
      );
}

class KatalogSayfasi {
  const KatalogSayfasi({this.satirlar = const [], this.sonId, this.sayi = 0,
                        this.bitti = true});
  final List<Map<String, dynamic>> satirlar;
  final String? sonId;
  final int sayi;
  final bool bitti;
  static KatalogSayfasi fromJson(Map<String, dynamic> j) => KatalogSayfasi(
        satirlar: ((j['satirlar'] as List?) ?? const [])
            .map((e) => (e as Map).cast<String, dynamic>()).toList(),
        sonId: j['son_id'] as String?,
        sayi: (j['sayi'] as num?)?.toInt() ?? 0,
        bitti: j['bitti'] as bool? ?? true,
      );
}
