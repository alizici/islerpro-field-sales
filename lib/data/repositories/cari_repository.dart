import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/network/supabase.dart';

/// Cari (account) — modelin merkezi soyutlaması (K5).
///
/// K7 · Bu sınıf kurum düzeyinde bakiye TOPLAMI döndüren bir metot içermez
/// ve içermemelidir. Kurumsal cari ile öğretmen carisi ayrı satırlardır.
class CariRepository {
  CariRepository(this._db);
  final SupabaseClient _db;

  Future<List<CariOzet>> ara({
    required String storeId,
    String? q,
    String? tip,
    String? durum,
    String? pazarlamaciId,
    bool atanmamis = false,
    bool borclu = false,
    String? periodId,
    int limit = 50,
    int offset = 0,
  }) async {
    final r = await _db.rpc<dynamic>('search_accounts', params: {
      'p_store_id': storeId,
      'p_q': (q ?? '').trim().isEmpty ? null : q!.trim(),
      'p_tip': tip, 'p_durum': durum,
      'p_pazarlamaci': pazarlamaciId,
      'p_atanmamis': atanmamis, 'p_borclu': borclu,
      'p_period_id': periodId, 'p_limit': limit, 'p_offset': offset,
    });
    return (r as List).map((e) => CariOzet.fromJson((e as Map).cast())).toList();
  }

  Future<int> say({
    required String storeId, String? q, String? tip, String? durum,
    String? pazarlamaciId, bool atanmamis = false, bool borclu = false,
    String? periodId,
  }) async {
    final r = await _db.rpc<dynamic>('count_accounts', params: {
      'p_store_id': storeId,
      'p_q': (q ?? '').trim().isEmpty ? null : q!.trim(),
      'p_tip': tip, 'p_durum': durum, 'p_pazarlamaci': pazarlamaciId,
      'p_atanmamis': atanmamis, 'p_borclu': borclu, 'p_period_id': periodId,
    });
    return (r as num).toInt();
  }

  Future<CariDetay> detay(String id) async {
    final r = await _db.rpc<dynamic>('account_detail', params: {'p_account_id': id});
    return CariDetay.fromJson((r as Map).cast());
  }

  Future<String> ekle({
    required String storeId,
    required String institutionId,
    required String tip,
    required String unvan,
    String? contactId,
    String? userId,
    String? discountTier,
    double creditLimit = 0,
  }) async {
    final r = await _db.rpc<dynamic>('create_account', params: {
      'p_store_id': storeId, 'p_institution_id': institutionId,
      'p_tip': tip, 'p_unvan': unvan, 'p_contact_id': contactId,
      'p_user_id': userId, 'p_discount_tier': discountTier,
      'p_credit_limit': creditLimit,
    });
    return (r as Map)['id'] as String;
  }

  Future<void> guncelle(String id, {
    String? unvan, String? discountTier, double? creditLimit,
    String? invoiceTitle, String? taxId, String? taxOffice,
  }) =>
      _db.rpc<dynamic>('update_account', params: {
        'p_account_id': id, 'p_unvan': unvan,
        'p_discount_tier': discountTier, 'p_credit_limit': creditLimit,
        'p_invoice_title': invoiceTitle, 'p_tax_id': taxId,
        'p_tax_office': taxOffice,
      });

  /// Bakiyesi olan cari 'pasif' istenirse sunucu 'tahsilatta'ya çevirir —
  /// borç ekrandan kaybolmasın diye. Dönen değer GERÇEKTE uygulanandır.
  Future<({String durum, String istenen, double bakiye})> durumDegistir(
      String id, String durum) async {
    final r = await _db.rpc<dynamic>('set_account_status',
        params: {'p_account_id': id, 'p_durum': durum});
    final m = (r as Map).cast<String, dynamic>();
    return (durum: m['durum'] as String,
            istenen: m['istenen'] as String? ?? durum,
            bakiye: (m['bakiye'] as num?)?.toDouble() ?? 0);
  }

  /// Saha gerçeği: 300 cari tek tek atanmaz. [userId] null ise atama kaldırılır.
  Future<({int atanan, int devralinan})> portfoyAta({
    required List<String> cariIdler,
    required String? userId,
    required String periodId,
  }) async {
    final r = await _db.rpc<dynamic>('assign_accounts', params: {
      'p_account_ids': cariIdler, 'p_user_id': userId, 'p_period_id': periodId,
    });
    final m = (r as Map).cast<String, dynamic>();
    return (atanan: (m['atanan'] as num?)?.toInt() ?? 0,
            devralinan: (m['devralinan'] as num?)?.toInt() ?? 0);
  }

  Future<PortfoyOzeti> portfoyOzeti(String storeId, String periodId) async {
    final r = await _db.rpc<dynamic>('portfolio_summary',
        params: {'p_store_id': storeId, 'p_period_id': periodId});
    return PortfoyOzeti.fromJson(((r ?? {}) as Map).cast());
  }

  /// K6 · Taşımadan önce kapıları göster; kör onay yok.
  Future<TasimaKontrol> tasimaKontrol(String cariId) async {
    final r = await _db.rpc<dynamic>('transfer_account_check',
        params: {'p_account_id': cariId});
    return TasimaKontrol.fromJson(((r ?? {}) as Map).cast());
  }

  Future<void> tasi(String cariId, String hedefKurumId, String gerekce) =>
      _db.rpc<dynamic>('transfer_account', params: {
        'p_account_id': cariId, 'p_to_institution_id': hedefKurumId,
        'p_gerekce': gerekce,
      });
}

final cariRepositoryProvider =
    Provider<CariRepository>((ref) => CariRepository(ref.watch(supabaseProvider)));

// ── Modeller ───────────────────────────────────────────────────────────────

class CariOzet {
  const CariOzet({
    required this.id, required this.tip, required this.unvan,
    required this.durum, required this.institutionId,
    this.kurumAd, this.ilce, this.discountTier,
    this.creditLimit = 0, this.bakiye = 0, this.risk = 0,
    this.limitAsildi = false, this.pazarlamaciId, this.pazarlamaci,
  });

  final String id, tip, unvan, durum, institutionId;
  final String? kurumAd, ilce, discountTier, pazarlamaciId, pazarlamaci;
  final double creditLimit, bakiye, risk;
  final bool limitAsildi;

  bool get ogretmen => tip == 'ogretmen';
  bool get aktif => durum == 'aktif';
  bool get tahsilatta => durum == 'tahsilatta';
  bool get atanmamis => pazarlamaciId == null;

  String get altBilgi =>
      [?kurumAd, ?ilce, ?pazarlamaci].join(' · ');

  String get durumAdi => switch (durum) {
        'aktif' => 'Aktif',
        'pasif' => 'Pasif',
        'tahsilatta' => 'Tahsilatta',
        'kapali' => 'Kapalı',
        _ => durum,
      };

  static CariOzet fromJson(Map<String, dynamic> j) => CariOzet(
        id: j['id'] as String,
        tip: j['tip'] as String? ?? 'kurum',
        unvan: j['unvan'] as String? ?? '',
        durum: j['durum'] as String? ?? 'aktif',
        institutionId: j['institution_id'] as String,
        kurumAd: j['kurum_ad'] as String?,
        ilce: j['ilce'] as String?,
        discountTier: j['discount_tier'] as String?,
        creditLimit: (j['credit_limit'] as num?)?.toDouble() ?? 0,
        bakiye: (j['bakiye'] as num?)?.toDouble() ?? 0,
        risk: (j['risk'] as num?)?.toDouble() ?? 0,
        limitAsildi: j['limit_asildi'] as bool? ?? false,
        pazarlamaciId: j['pazarlamaci_id'] as String?,
        pazarlamaci: j['pazarlamaci'] as String?,
      );
}

class CariDetay {
  const CariDetay({
    required this.id, required this.tip, required this.unvan,
    required this.durum, required this.kurumId, required this.kurumAd,
    this.ilce, this.discountTier, this.creditLimit = 0,
    this.bakiye = 0, this.risk = 0, this.acikKonsinye = 0,
    this.kisiAd, this.kisiTelefon,
    this.portfoy = const [], this.tasimalar = const [],
    this.kardesCariler = const [],
  });

  final String id, tip, unvan, durum, kurumId, kurumAd;
  final String? ilce, discountTier, kisiAd, kisiTelefon;
  final double creditLimit, bakiye, risk, acikKonsinye;
  final List<PortfoySatiri> portfoy;
  final List<TasimaKaydi> tasimalar;
  /// K7 · Ayrı satırlar. Bu listenin TOPLAMI HİÇBİR YERDE ALINMAZ.
  final List<CariOzet> kardesCariler;

  bool get limitAsildi => creditLimit > 0 && risk > creditLimit;

  static CariDetay fromJson(Map<String, dynamic> j) {
    final k = ((j['kurum'] as Map?) ?? {}).cast<String, dynamic>();
    final kisi = (j['kisi'] as Map?)?.cast<String, dynamic>();
    return CariDetay(
      id: j['id'] as String,
      tip: j['tip'] as String? ?? 'kurum',
      unvan: j['unvan'] as String? ?? '',
      durum: j['durum'] as String? ?? 'aktif',
      kurumId: k['id'] as String? ?? '',
      kurumAd: k['ad'] as String? ?? '',
      ilce: k['ilce'] as String?,
      discountTier: j['discount_tier'] as String?,
      creditLimit: (j['credit_limit'] as num?)?.toDouble() ?? 0,
      bakiye: (j['bakiye'] as num?)?.toDouble() ?? 0,
      risk: (j['risk'] as num?)?.toDouble() ?? 0,
      acikKonsinye: (j['acik_konsinye'] as num?)?.toDouble() ?? 0,
      kisiAd: kisi?['ad_soyad'] as String?,
      kisiTelefon: kisi?['telefon'] as String?,
      portfoy: ((j['portfoy'] as List?) ?? const [])
          .map((e) => PortfoySatiri.fromJson((e as Map).cast())).toList(),
      tasimalar: ((j['tasimalar'] as List?) ?? const [])
          .map((e) => TasimaKaydi.fromJson((e as Map).cast())).toList(),
      kardesCariler: ((j['kardes_cariler'] as List?) ?? const [])
          .map((e) => CariOzet.fromJson({
                ...(e as Map).cast<String, dynamic>(),
                'institution_id': k['id'],
              })).toList(),
    );
  }
}

class PortfoySatiri {
  const PortfoySatiri({required this.userId, required this.adSoyad,
                       required this.periodAd, this.aktif = true});
  final String userId, adSoyad, periodAd;
  final bool aktif;
  static PortfoySatiri fromJson(Map<String, dynamic> j) => PortfoySatiri(
        userId: j['user_id'] as String,
        adSoyad: j['ad_soyad'] as String? ?? '',
        periodAd: j['period_ad'] as String? ?? '',
        aktif: j['aktif'] as bool? ?? true,
      );
}

class TasimaKaydi {
  const TasimaKaydi({required this.tarih, required this.nereden,
                     required this.nereye, this.gerekce});
  final DateTime tarih;
  final String nereden, nereye;
  final String? gerekce;
  static TasimaKaydi fromJson(Map<String, dynamic> j) => TasimaKaydi(
        tarih: DateTime.parse(j['tarih'] as String),
        nereden: j['nereden'] as String? ?? '',
        nereye: j['nereye'] as String? ?? '',
        gerekce: j['gerekce'] as String?,
      );
}

class PortfoyOzeti {
  const PortfoyOzeti({this.pazarlamacilar = const [], this.atanmamis = 0});
  final List<PortfoySahibi> pazarlamacilar;
  final int atanmamis;
  static PortfoyOzeti fromJson(Map<String, dynamic> j) => PortfoyOzeti(
        pazarlamacilar: ((j['pazarlamacilar'] as List?) ?? const [])
            .map((e) => PortfoySahibi.fromJson((e as Map).cast())).toList(),
        atanmamis: (j['atanmamis'] as num?)?.toInt() ?? 0,
      );
}

class PortfoySahibi {
  const PortfoySahibi({required this.userId, required this.adSoyad,
                       this.cariSayisi = 0, this.bakiye = 0});
  final String userId, adSoyad;
  final int cariSayisi;
  final double bakiye;
  static PortfoySahibi fromJson(Map<String, dynamic> j) => PortfoySahibi(
        userId: j['user_id'] as String,
        adSoyad: j['ad_soyad'] as String? ?? '',
        cariSayisi: (j['cari_sayisi'] as num?)?.toInt() ?? 0,
        bakiye: (j['bakiye'] as num?)?.toDouble() ?? 0,
      );
}

class TasimaKontrol {
  const TasimaKontrol({this.acikKonsinye = 0, this.sevkEdilmemisSiparis = 0,
                       this.bakiye = 0, this.kurumAd = ''});
  final double acikKonsinye, bakiye;
  final int sevkEdilmemisSiparis;
  final String kurumAd;

  bool get engelli => acikKonsinye > 0 || sevkEdilmemisSiparis > 0;

  /// Kapılar sırayla anlatılır; ikisi birden varsa ikisi de yazılır.
  List<String> get engeller => [
        if (acikKonsinye > 0)
          'Açık konsinye var (${acikKonsinye.toStringAsFixed(0)} adet). '
          'Kitaplar fiziken eski kurumda — satıldı/iade kaydı girilmeli.',
        if (sevkEdilmemisSiparis > 0)
          'Sevk edilmemiş $sevkEdilmemisSiparis sipariş var. '
          'Önce sevk edin veya iptal edin.',
      ];

  static TasimaKontrol fromJson(Map<String, dynamic> j) => TasimaKontrol(
        acikKonsinye: (j['acik_konsinye'] as num?)?.toDouble() ?? 0,
        sevkEdilmemisSiparis:
            (j['sevk_edilmemis_siparis'] as num?)?.toInt() ?? 0,
        bakiye: (j['bakiye'] as num?)?.toDouble() ?? 0,
        kurumAd: j['kurum_ad'] as String? ?? '',
      );
}
