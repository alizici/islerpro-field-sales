import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/session.dart';
import '../../core/network/supabase.dart';

/// İşletme, dükkan, ekip ve dönem yönetimi (Faz 1).
class OrgRepository {
  OrgRepository(this._db);
  final SupabaseClient _db;

  // ── Dükkanlar ────────────────────────────────────────────────────────────
  Future<List<StoreRow>> dukkanlar() async {
    final r = await _db.from('stores').select().order('ad');
    return r.map(StoreRow.fromJson).toList();
  }

  Future<void> dukkanEkle(String tenantId, String ad, {String? il, String? ilce}) =>
      _db.from('stores').insert({
        'tenant_id': tenantId, 'ad': ad, 'il': il, 'ilce': ilce,
      });

  Future<void> dukkanGuncelle(String id,
          {required String ad, String? il, String? ilce, String? adres}) =>
      _db.rpc<dynamic>('update_store', params: {
        'p_store_id': id, 'p_ad': ad, 'p_il': il, 'p_ilce': ilce,
        'p_adres': adres,
      });

  /// Pasife almadan önce ne olacağını gösterir — kullanıcı kör onay vermesin.
  Future<DukkanEtki> pasifEtkisi(String storeId) async {
    final r = await _db.rpc<dynamic>('store_deactivation_check',
        params: {'p_store_id': storeId});
    return DukkanEtki.fromJson(((r ?? {}) as Map).cast());
  }

  /// Son aktif dükkan ve bakiyesi kapanmamış cari varsa DB reddeder (0018).
  Future<({int kapananCari, int kapananAtama})> dukkanDurumu(
      String storeId, bool aktif) async {
    final r = await _db.rpc<dynamic>('set_store_status',
        params: {'p_store_id': storeId, 'p_aktif': aktif});
    final m = ((r ?? {}) as Map).cast<String, dynamic>();
    return (kapananCari: (m['kapanan_cari'] as num?)?.toInt() ?? 0,
            kapananAtama: (m['kapanan_atama'] as num?)?.toInt() ?? 0);
  }

  // ── Ekip ─────────────────────────────────────────────────────────────────
  Future<List<StaffRow>> ekip({String? storeId}) async {
    final r = await _db.rpc<dynamic>('list_staff',
        params: {'p_store_id': storeId});
    return (r as List).map((e) => StaffRow.fromJson((e as Map).cast())).toList();
  }

  /// Ekip daveti — kod üretir. Sahibi/müdür çağırabilir.
  Future<String> ekipDavetiOlustur({
    required String storeId,
    required AppRole rol,
    String? adSoyad,
    String? telefon,
  }) async {
    final r = await _db.rpc<dynamic>('create_staff_invite', params: {
      'p_store_id': storeId,
      'p_role': _rolDb(rol),
      'p_ad_soyad': adSoyad,
      'p_telefon': telefon,
    });
    return (r as Map)['kod'] as String;
  }

  /// K34 (W-2) · Pasife alırken portföy devri zorunludur.
  /// Devredilmezse o carilerden gelen talepler hiçbir kutuya düşmez.
  Future<int> uyeyiPasifeAl(String userId, {String? devralanUserId}) async {
    final r = await _db.rpc<dynamic>('deactivate_member', params: {
      'p_user_id': userId,
      'p_devralan_user_id': devralanUserId,
    });
    return (r as Map)['devredilen_cari'] as int? ?? 0;
  }

  // ── Dönemler (K8) ────────────────────────────────────────────────────────
  Future<List<PeriodRow>> donemler() async {
    final r = await _db.from('periods').select()
        .order('academic_year', ascending: false).order('term', ascending: false);
    return r.map(PeriodRow.fromJson).toList();
  }

  /// Sonraki yarıyılı açar; portföy otomatik kopyalanır (K8 dönem geçişi).
  Future<String> sonrakiDonemiAc(String tenantId) async {
    final r = await _db.rpc<dynamic>('create_next_period',
        params: {'p_tenant_id': tenantId});
    return (r as Map)['ad'] as String? ?? '';
  }

  Future<void> donemDurumu(String periodId, String durum) =>
      _db.rpc<dynamic>('set_period_status',
          params: {'p_period_id': periodId, 'p_status': durum});

  // ── Öğretmen onayları (K3) ───────────────────────────────────────────────
  Future<List<PendingTeacher>> bekleyenOgretmenler() async {
    final r = await _db.rpc<dynamic>('list_pending_teachers');
    return (r as List)
        .map((e) => PendingTeacher.fromJson((e as Map).cast()))
        .toList();
  }

  Future<void> ogretmenOnayla({
    required String userId,
    required String institutionId,
    required String storeId,
    bool kurumAdinaSiparis = false,
  }) =>
      _db.rpc<dynamic>('approve_teacher', params: {
        'p_user_id': userId,
        'p_institution_id': institutionId,
        'p_store_id': storeId,
        'p_can_order_for_institution': kurumAdinaSiparis,
      });

  static String _rolDb(AppRole r) => switch (r) {
        AppRole.pazarlamaci => 'pazarlamaci',
        AppRole.dukkanMuduru => 'dukkan_muduru',
        AppRole.hazirlik => 'hazirlik',
        _ => throw ArgumentError('Bu rol davetle verilemez: $r'),
      };
}

final orgRepositoryProvider =
    Provider<OrgRepository>((ref) => OrgRepository(ref.watch(supabaseProvider)));

// ── Satır modelleri ────────────────────────────────────────────────────────
class StoreRow {
  const StoreRow({required this.id, required this.ad, required this.tenantId,
                  this.il, this.ilce, this.aktif = true});
  final String id, ad, tenantId;
  final String? il, ilce;
  final bool aktif;
  String get konum => [il, ilce].nonNulls.where((e) => e.isNotEmpty).join(' · ');
  static StoreRow fromJson(Map<String, dynamic> j) => StoreRow(
        id: j['id'] as String, ad: j['ad'] as String? ?? '',
        tenantId: j['tenant_id'] as String,
        il: j['il'] as String?, ilce: j['ilce'] as String?,
        aktif: j['aktif'] as bool? ?? true,
      );
}

class DukkanEtki {
  const DukkanEtki({this.sonDukkan = false, this.borcluCari = 0,
                    this.borcTutari = 0, this.aktifCari = 0, this.aktifAtama = 0});
  final bool sonDukkan;
  final int borcluCari, aktifCari, aktifAtama;
  final double borcTutari;

  /// İki kapıdan biri kapalıysa pasife alınamaz (0018).
  bool get engelli => sonDukkan || borcluCari > 0;

  String get gerekce => sonDukkan
      ? 'Bu tek aktif dükkan. Pasife alınırsa oturumun dükkanı kalmaz.'
      : 'Bakiyesi kapanmamış $borcluCari cari var. Borç ekrandan kaybolur '
        'ama tahsil edilmemiş olarak durur.';

  static DukkanEtki fromJson(Map<String, dynamic> j) => DukkanEtki(
        sonDukkan: j['son_dukkan'] as bool? ?? false,
        borcluCari: (j['borclu_cari'] as num?)?.toInt() ?? 0,
        borcTutari: (j['borc_tutari'] as num?)?.toDouble() ?? 0,
        aktifCari: (j['aktif_cari'] as num?)?.toInt() ?? 0,
        aktifAtama: (j['aktif_atama'] as num?)?.toInt() ?? 0,
      );
}

class StaffRow {
  const StaffRow({required this.userId, required this.adSoyad, required this.role,
                  required this.status, this.telefon, this.eposta,
                  this.storeAd, this.portfoy = 0});
  final String userId, adSoyad, status;
  final AppRole? role;
  final String? telefon, eposta, storeAd;
  final int portfoy;
  bool get aktif => status == 'aktif';
  static StaffRow fromJson(Map<String, dynamic> j) => StaffRow(
        userId: j['user_id'] as String,
        adSoyad: j['ad_soyad'] as String? ?? '',
        role: AppRole.fromDb(j['role'] as String?),
        status: j['status'] as String? ?? 'aktif',
        telefon: j['telefon'] as String?, eposta: j['eposta'] as String?,
        storeAd: j['store_ad'] as String?,
        portfoy: (j['portfoy'] as num?)?.toInt() ?? 0,
      );
}

class PeriodRow {
  const PeriodRow({required this.id, required this.ad, required this.status,
                   required this.startsOn, required this.endsOn});
  final String id, ad, status;
  final DateTime startsOn, endsOn;
  bool get aktif => status == 'aktif';
  static PeriodRow fromJson(Map<String, dynamic> j) => PeriodRow(
        id: j['id'] as String, ad: j['ad'] as String? ?? '',
        status: j['status'] as String? ?? 'planlandi',
        startsOn: DateTime.parse(j['starts_on'] as String),
        endsOn: DateTime.parse(j['ends_on'] as String),
      );
}

class PendingTeacher {
  const PendingTeacher({required this.userId, required this.adSoyad,
                        required this.institutionId, required this.institutionAd,
                        this.telefon, this.ilce});
  final String userId, adSoyad, institutionId, institutionAd;
  final String? telefon, ilce;
  static PendingTeacher fromJson(Map<String, dynamic> j) => PendingTeacher(
        userId: j['user_id'] as String,
        adSoyad: j['ad_soyad'] as String? ?? '',
        institutionId: j['institution_id'] as String,
        institutionAd: j['institution_ad'] as String? ?? '',
        telefon: j['telefon'] as String?, ilce: j['institution_ilce'] as String?,
      );
}
