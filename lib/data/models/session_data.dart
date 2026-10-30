import '../../core/auth/session.dart';

/// `my_session()` RPC'sinin karşılığı.
/// Tek çağrıda gelir — 341 ms gecikmede oturum yüklemek beş tur atmamalı.
class SessionData {
  const SessionData({
    required this.userId,
    required this.adSoyad,
    this.telefon,
    this.eposta,
    this.memberships = const [],
    this.institutionMemberships = const [],
    this.stores = const [],
    this.activePeriods = const [],
    this.consentOk = false,
  });

  final String userId;
  final String adSoyad;
  final String? telefon;
  final String? eposta;
  final List<Membership> memberships;
  final List<InstitutionMembership> institutionMemberships;
  final List<StoreRef> stores;
  final List<PeriodRef> activePeriods;
  final bool consentOk;

  /// İşletme tarafı rolleri + (varsa) öğretmen rolü.
  Set<AppRole> get roller {
    final r = memberships.map((m) => m.role).nonNulls.toSet();
    if (institutionMemberships.any((i) => i.aktif)) r.add(AppRole.ogretmen);
    return r;
  }

  bool get kurulumGerekli => memberships.isEmpty && institutionMemberships.isEmpty;

  /// Onay bekleyen öğretmen: katalog ve fiyat göremez (K3).
  bool get onayBekliyor =>
      memberships.isEmpty &&
      institutionMemberships.isNotEmpty &&
      !institutionMemberships.any((i) => i.aktif);

  static SessionData fromJson(Map<String, dynamic> j) {
    final u = (j['user'] as Map?)?.cast<String, dynamic>() ?? const {};
    List<T> list<T>(String k, T Function(Map<String, dynamic>) f) =>
        ((j[k] as List?) ?? const [])
            .map((e) => f((e as Map).cast<String, dynamic>()))
            .toList();
    return SessionData(
      userId: u['id'] as String? ?? '',
      adSoyad: u['ad_soyad'] as String? ?? 'Kullanıcı',
      telefon: u['telefon'] as String?,
      eposta: u['eposta'] as String?,
      memberships: list('memberships', Membership.fromJson),
      institutionMemberships:
          list('institution_memberships', InstitutionMembership.fromJson),
      stores: list('stores', StoreRef.fromJson),
      activePeriods: list('active_periods', PeriodRef.fromJson),
      consentOk: j['consent_ok'] as bool? ?? false,
    );
  }
}

class Membership {
  const Membership({
    required this.tenantId,
    required this.tenantUnvan,
    required this.role,
    this.storeId,
    this.storeAd,
  });
  final String tenantId;
  final String tenantUnvan;
  final AppRole? role;
  final String? storeId;
  final String? storeAd;

  static Membership fromJson(Map<String, dynamic> j) => Membership(
        tenantId: j['tenant_id'] as String,
        tenantUnvan: j['tenant_unvan'] as String? ?? '',
        role: AppRole.fromDb(j['role'] as String?),
        storeId: j['store_id'] as String?,
        storeAd: j['store_ad'] as String?,
      );
}

class InstitutionMembership {
  const InstitutionMembership({
    required this.institutionId,
    required this.institutionAd,
    required this.status,
    this.gorev,
    this.brans,
    this.kurumAdinaSiparis = false,
  });
  final String institutionId;
  final String institutionAd;
  final String status;
  final String? gorev;
  final String? brans;
  final bool kurumAdinaSiparis;

  bool get aktif => status == 'aktif';

  static InstitutionMembership fromJson(Map<String, dynamic> j) =>
      InstitutionMembership(
        institutionId: j['institution_id'] as String,
        institutionAd: j['institution_ad'] as String? ?? '',
        status: j['status'] as String? ?? 'onay_bekliyor',
        gorev: j['gorev'] as String?,
        brans: j['brans'] as String?,
        kurumAdinaSiparis: j['can_order_for_institution'] as bool? ?? false,
      );
}

class StoreRef {
  const StoreRef({required this.id, required this.ad, required this.tenantId});
  final String id, ad, tenantId;
  static StoreRef fromJson(Map<String, dynamic> j) =>
      StoreRef(id: j['id'] as String, ad: j['ad'] as String? ?? '',
               tenantId: j['tenant_id'] as String);
}

class PeriodRef {
  const PeriodRef({required this.id, required this.ad, required this.tenantId,
                   this.startsOn, this.endsOn});
  final String id, ad, tenantId;
  final DateTime? startsOn, endsOn;
  static PeriodRef fromJson(Map<String, dynamic> j) => PeriodRef(
        id: j['id'] as String,
        ad: j['ad'] as String? ?? '',
        tenantId: j['tenant_id'] as String,
        startsOn: DateTime.tryParse(j['starts_on'] as String? ?? ''),
        endsOn: DateTime.tryParse(j['ends_on'] as String? ?? ''),
      );
}
