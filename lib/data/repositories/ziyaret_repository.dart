import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/network/supabase.dart';

/// Saha: ziyaret ve rota (Faz 7).
///
/// K10 · Ziyarette konum yoktur. Ziyaretin kanıtı ÇIKTISIDIR — açıkken oluşan
/// talep, sipariş, teslimat, tahsilat ve eklenen kişi. Damgayı sunucudaki
/// trigger atar; bu katman `visit_id` diye bir alan taşımaz.
class ZiyaretRepository {
  ZiyaretRepository(this._db);
  final SupabaseClient _db;

  Future<AcikZiyaret?> acikZiyaret() async {
    final r = await _db.rpc<dynamic>('active_visit');
    if (r == null) return null;
    return AcikZiyaret.fromJson((r as Map).cast());
  }

  /// [clientKey] offline kuyruğun idempotency anahtarıdır (K43): aynı anahtar
  /// ikinci kez gelirse sunucu var olan ziyareti döndürür, yenisini açmaz.
  Future<({String id, bool yeni, String kurumAd})> baslat(
    String kurumId, {
    String? contactId,
    String? clientKey,
    DateTime? girisSaati,
  }) async {
    final r = await _db.rpc<dynamic>('start_visit', params: {
      'p_institution_id': kurumId,
      'p_contact_id': contactId,
      'p_client_key': clientKey,
      'p_checked_in_at': girisSaati?.toIso8601String(),
    });
    final m = (r as Map).cast<String, dynamic>();
    return (id: m['id'] as String,
            yeni: m['yeni'] as bool? ?? true,
            kurumAd: m['kurum_ad'] as String? ?? '');
  }

  Future<({String kurumAd, int dakika, ZiyaretCikti cikti})> bitir({
    String? ziyaretId, String? notMetni, String? sonuc, DateTime? cikisSaati,
  }) async {
    final r = await _db.rpc<dynamic>('end_visit', params: {
      'p_visit_id': ziyaretId,
      'p_not_metni': notMetni,
      'p_sonuc': sonuc,
      'p_checked_out_at': cikisSaati?.toIso8601String(),
    });
    final m = (r as Map).cast<String, dynamic>();
    return (kurumAd: m['kurum_ad'] as String? ?? '',
            dakika: (m['dakika'] as num?)?.toInt() ?? 0,
            cikti: ZiyaretCikti.fromJson(((m['cikti'] as Map?) ?? {}).cast()));
  }

  Future<ZiyaretDetay> detay(String ziyaretId) async {
    final r = await _db.rpc<dynamic>('visit_detail',
        params: {'p_visit_id': ziyaretId});
    if (r == null) throw StateError('Ziyaret bulunamadı veya yetkiniz yok');
    return ZiyaretDetay.fromJson((r as Map).cast());
  }

  Future<List<ZiyaretOzet>> liste({
    String? storeId, String? userId, String? kurumId,
    int gun = 30, int limit = 100,
  }) async {
    final r = await _db.rpc<dynamic>('list_visits', params: {
      'p_store_id': storeId, 'p_user_id': userId,
      'p_institution_id': kurumId, 'p_gun': gun, 'p_limit': limit,
    });
    return ((r as List?) ?? const [])
        .map((e) => ZiyaretOzet.fromJson((e as Map).cast())).toList();
  }

  // ── Rota ─────────────────────────────────────────────────────────────────
  Future<Rota> rota({DateTime? tarih}) async {
    final r = await _db.rpc<dynamic>('my_route',
        params: {'p_tarih': tarih == null ? null : _gun(tarih)});
    return Rota.fromJson(((r as Map?) ?? {}).cast());
  }

  Future<List<RotaOneri>> oneri({int limit = 15}) async {
    final r = await _db.rpc<dynamic>('suggest_route', params: {'p_limit': limit});
    return ((r as List?) ?? const [])
        .map((e) => RotaOneri.fromJson((e as Map).cast())).toList();
  }

  Future<String> planaEkle(String kurumId, {DateTime? tarih, String? amac}) async {
    final r = await _db.rpc<dynamic>('plan_visit', params: {
      'p_institution_id': kurumId,
      'p_tarih': tarih == null ? null : _gun(tarih),
      'p_amac': amac,
    });
    return r as String;
  }

  Future<void> plandanCikar(String planId) =>
      _db.rpc<dynamic>('remove_plan', params: {'p_plan_id': planId});

  Future<void> planDurumu(String planId, String durum) =>
      _db.rpc<dynamic>('set_plan_status',
          params: {'p_plan_id': planId, 'p_durum': durum});

  Future<void> planSirala(List<String> planIdler) =>
      _db.rpc<dynamic>('reorder_plan', params: {'p_ids': planIdler});

  /// K35 · Prim hesaplanmaz; bu yalnızca rapordur.
  Future<List<ZiyaretPerformans>> performans(String storeId,
      {String? periodId, String? userId}) async {
    final r = await _db.rpc<dynamic>('visit_performance', params: {
      'p_store_id': storeId, 'p_period_id': periodId, 'p_user_id': userId,
    });
    return ((r as List?) ?? const [])
        .map((e) => ZiyaretPerformans.fromJson((e as Map).cast())).toList();
  }

  static String _gun(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}-'
      '${t.month.toString().padLeft(2, '0')}-'
      '${t.day.toString().padLeft(2, '0')}';
}

final ziyaretRepositoryProvider = Provider<ZiyaretRepository>(
    (ref) => ZiyaretRepository(ref.watch(supabaseProvider)));

// ── Modeller ───────────────────────────────────────────────────────────────

/// K10 · Ziyaretin ölçüsü. `toplam` sıfırsa ziyaret hiçbir şey üretmemiştir —
/// bu gizlenmez, ölçüt tam olarak budur.
class ZiyaretCikti {
  const ZiyaretCikti({this.talep = 0, this.siparis = 0, this.teslimat = 0,
                      this.tahsilat = 0, this.kisi = 0, this.tutar = 0,
                      this.toplam = 0});
  final int talep, siparis, teslimat, tahsilat, kisi, toplam;
  final double tutar;
  bool get bos => toplam == 0;

  static ZiyaretCikti fromJson(Map<String, dynamic> j) => ZiyaretCikti(
        talep: (j['talep'] as num?)?.toInt() ?? 0,
        siparis: (j['siparis'] as num?)?.toInt() ?? 0,
        teslimat: (j['teslimat'] as num?)?.toInt() ?? 0,
        tahsilat: (j['tahsilat'] as num?)?.toInt() ?? 0,
        kisi: (j['kisi'] as num?)?.toInt() ?? 0,
        tutar: (j['tutar'] as num?)?.toDouble() ?? 0,
        toplam: (j['toplam'] as num?)?.toInt() ?? 0,
      );
}

class AcikZiyaret {
  const AcikZiyaret({required this.id, required this.kurumId,
                     required this.kurumAd, required this.girisSaati,
                     this.ilce, this.dakika = 0,
                     this.cikti = const ZiyaretCikti(), this.yerel = false});
  final String id, kurumId, kurumAd;
  final String? ilce;
  final DateTime girisSaati;
  final int dakika;
  final ZiyaretCikti cikti;

  /// K43 · Ziyaret kuyrukta bekliyor; sunucu henüz bilmiyor. Çıktı sayısı da
  /// bu yüzden sıfırdır — damgayı sunucu, kuyruk yüklenince atacak (Y-18).
  final bool yerel;

  /// Çevrimdışı açılan ziyaret. Kimliği yoktur: kapatma isteği kuyruğa
  /// `visit_id: null` ile girer ve sunucu onu SIRAYLA açık ziyaretten çözer.
  static AcikZiyaret yerelKayit(Map<String, dynamic> j) => AcikZiyaret(
        id: '', kurumId: j['institution_id'] as String,
        kurumAd: j['kurum_ad'] as String? ?? '',
        girisSaati: DateTime.parse(j['checked_in_at'] as String),
        yerel: true,
      );

  static AcikZiyaret fromJson(Map<String, dynamic> j) => AcikZiyaret(
        id: j['id'] as String,
        kurumId: j['institution_id'] as String,
        kurumAd: j['kurum_ad'] as String? ?? '',
        ilce: j['ilce'] as String?,
        girisSaati: DateTime.parse(j['checked_in_at'] as String).toLocal(),
        dakika: (j['dakika'] as num?)?.toInt() ?? 0,
        cikti: ZiyaretCikti.fromJson(((j['cikti'] as Map?) ?? {}).cast()),
      );
}

class ZiyaretSatir {
  const ZiyaretSatir({required this.tur, required this.id, required this.tarih,
                      required this.baslik, this.aciklama, this.tutar});
  final String tur, id, baslik;
  final DateTime tarih;
  final String? aciklama;
  final double? tutar;

  static ZiyaretSatir fromJson(Map<String, dynamic> j) => ZiyaretSatir(
        tur: j['tur'] as String? ?? '',
        id: j['id'] as String,
        tarih: DateTime.parse(j['tarih'] as String).toLocal(),
        baslik: j['baslik'] as String? ?? '',
        aciklama: j['aciklama'] as String?,
        tutar: (j['tutar'] as num?)?.toDouble(),
      );
}

class ZiyaretDetay {
  const ZiyaretDetay({required this.id, required this.kurumId,
                      required this.kurumAd, required this.girisSaati,
                      this.ilce, this.pazarlamaci, this.cikisSaati,
                      this.dakika, this.gorusulen, this.notMetni, this.sonuc,
                      this.cikti = const ZiyaretCikti(),
                      this.satirlar = const []});
  final String id, kurumId, kurumAd;
  final String? ilce, pazarlamaci, gorusulen, notMetni, sonuc;
  final DateTime girisSaati;
  final DateTime? cikisSaati;
  final int? dakika;
  final ZiyaretCikti cikti;
  final List<ZiyaretSatir> satirlar;
  bool get acik => cikisSaati == null;

  static ZiyaretDetay fromJson(Map<String, dynamic> j) => ZiyaretDetay(
        id: j['id'] as String,
        kurumId: j['institution_id'] as String,
        kurumAd: j['kurum_ad'] as String? ?? '',
        ilce: j['ilce'] as String?,
        pazarlamaci: j['pazarlamaci'] as String?,
        girisSaati: DateTime.parse(j['checked_in_at'] as String).toLocal(),
        cikisSaati: j['checked_out_at'] == null
            ? null : DateTime.parse(j['checked_out_at'] as String).toLocal(),
        dakika: (j['dakika'] as num?)?.toInt(),
        gorusulen: j['gorusulen'] as String?,
        notMetni: j['not_metni'] as String?,
        sonuc: j['sonuc'] as String?,
        cikti: ZiyaretCikti.fromJson(((j['cikti'] as Map?) ?? {}).cast()),
        satirlar: ((j['satirlar'] as List?) ?? const [])
            .map((e) => ZiyaretSatir.fromJson((e as Map).cast())).toList(),
      );
}

class ZiyaretOzet {
  const ZiyaretOzet({required this.id, required this.kurumId,
                     required this.kurumAd, required this.girisSaati,
                     this.ilce, this.pazarlamaci, this.userId,
                     this.cikisSaati, this.dakika, this.sonuc, this.cikti = 0});
  final String id, kurumId, kurumAd;
  final String? ilce, pazarlamaci, userId, sonuc;
  final DateTime girisSaati;
  final DateTime? cikisSaati;
  final int? dakika;
  final int cikti;
  bool get acik => cikisSaati == null;

  static ZiyaretOzet fromJson(Map<String, dynamic> j) => ZiyaretOzet(
        id: j['id'] as String,
        kurumId: j['institution_id'] as String,
        kurumAd: j['kurum_ad'] as String? ?? '',
        ilce: j['ilce'] as String?,
        pazarlamaci: j['pazarlamaci'] as String?,
        userId: j['user_id'] as String?,
        girisSaati: DateTime.parse(j['checked_in_at'] as String).toLocal(),
        cikisSaati: j['checked_out_at'] == null
            ? null : DateTime.parse(j['checked_out_at'] as String).toLocal(),
        dakika: (j['dakika'] as num?)?.toInt(),
        sonuc: j['sonuc'] as String?,
        cikti: (j['cikti'] as num?)?.toInt() ?? 0,
      );
}

class RotaDurak {
  const RotaDurak({required this.planId, required this.kurumId,
                   required this.kurumAd, this.ilce, this.tip,
                   this.sira = 0, this.amac, this.durum = 'planlandi',
                   this.ziyaretId, this.cari = 0, this.borc = 0,
                   this.bekleyenTalep = 0, this.hazirSiparis = 0,
                   this.sonZiyaret});
  final String planId, kurumId, kurumAd, durum;
  final String? ilce, tip, amac, ziyaretId;
  final int sira, cari, bekleyenTalep, hazirSiparis;
  final double borc;
  final DateTime? sonZiyaret;
  bool get tamam => durum == 'ziyaret_edildi';

  static RotaDurak fromJson(Map<String, dynamic> j) => RotaDurak(
        planId: j['plan_id'] as String,
        kurumId: j['institution_id'] as String,
        kurumAd: j['kurum_ad'] as String? ?? '',
        ilce: j['ilce'] as String?,
        tip: j['tip'] as String?,
        sira: (j['sira'] as num?)?.toInt() ?? 0,
        amac: j['amac'] as String?,
        durum: j['durum'] as String? ?? 'planlandi',
        ziyaretId: j['visit_id'] as String?,
        cari: (j['cari'] as num?)?.toInt() ?? 0,
        borc: (j['borc'] as num?)?.toDouble() ?? 0,
        bekleyenTalep: (j['bekleyen_talep'] as num?)?.toInt() ?? 0,
        hazirSiparis: (j['hazir_siparis'] as num?)?.toInt() ?? 0,
        sonZiyaret: j['son_ziyaret'] == null
            ? null : DateTime.parse(j['son_ziyaret'] as String).toLocal(),
      );
}

class Rota {
  const Rota({this.tarih, this.duraklar = const [], this.tamamlanan = 0,
              this.planlanan = 0, this.plansizZiyaret = 0});
  final DateTime? tarih;
  final List<RotaDurak> duraklar;
  final int tamamlanan, planlanan, plansizZiyaret;
  bool get bos => duraklar.isEmpty;

  static Rota fromJson(Map<String, dynamic> j) => Rota(
        tarih: j['tarih'] == null ? null : DateTime.parse(j['tarih'] as String),
        duraklar: ((j['duraklar'] as List?) ?? const [])
            .map((e) => RotaDurak.fromJson((e as Map).cast())).toList(),
        tamamlanan: (j['tamamlanan'] as num?)?.toInt() ?? 0,
        planlanan: (j['planlanan'] as num?)?.toInt() ?? 0,
        plansizZiyaret: (j['plansiz_ziyaret'] as num?)?.toInt() ?? 0,
      );
}

/// Her öneri NEDEN listede olduğunu kendisi söyler — gizli skor yoktur.
class RotaOneri {
  const RotaOneri({required this.kurumId, required this.kurumAd,
                   required this.neden, this.ilce, this.tip, this.cari = 0,
                   this.borc = 0, this.gecikmisBorc = 0, this.gecikmisTalep = 0,
                   this.hazirSiparis = 0, this.konsinye = 0,
                   this.sonZiyaret, this.gun, this.planda = false});
  final String kurumId, kurumAd, neden;
  final String? ilce, tip;
  final int cari, gecikmisBorc, gecikmisTalep, hazirSiparis, konsinye;
  final double borc;
  final DateTime? sonZiyaret;
  final int? gun;
  final bool planda;

  /// Acil bir sebep var mı — yoksa satır yalnızca "uğranmadı" diyordur.
  bool get acil => gecikmisBorc > 0 || gecikmisTalep > 0 ||
      hazirSiparis > 0 || konsinye > 0;

  static RotaOneri fromJson(Map<String, dynamic> j) => RotaOneri(
        kurumId: j['institution_id'] as String,
        kurumAd: j['kurum_ad'] as String? ?? '',
        neden: j['neden'] as String? ?? '',
        ilce: j['ilce'] as String?,
        tip: j['tip'] as String?,
        cari: (j['cari'] as num?)?.toInt() ?? 0,
        borc: (j['borc'] as num?)?.toDouble() ?? 0,
        gecikmisBorc: (j['gecikmis_borc'] as num?)?.toInt() ?? 0,
        gecikmisTalep: (j['gecikmis_talep'] as num?)?.toInt() ?? 0,
        hazirSiparis: (j['hazir_siparis'] as num?)?.toInt() ?? 0,
        konsinye: (j['konsinye'] as num?)?.toInt() ?? 0,
        sonZiyaret: j['son_ziyaret'] == null
            ? null : DateTime.parse(j['son_ziyaret'] as String).toLocal(),
        gun: (j['gun'] as num?)?.toInt(),
        planda: j['planda'] as bool? ?? false,
      );
}

class ZiyaretPerformans {
  const ZiyaretPerformans({required this.userId, required this.adSoyad,
                           this.ziyaret = 0, this.cikti = 0, this.bosZiyaret = 0,
                           this.ortCikti = 0, this.ortDakika, this.ciro = 0});
  final String userId, adSoyad;
  final int ziyaret, cikti, bosZiyaret;
  final double ortCikti, ciro;
  final int? ortDakika;

  static ZiyaretPerformans fromJson(Map<String, dynamic> j) => ZiyaretPerformans(
        userId: j['user_id'] as String? ?? '',
        adSoyad: j['ad_soyad'] as String? ?? '—',
        ziyaret: (j['ziyaret'] as num?)?.toInt() ?? 0,
        cikti: (j['cikti'] as num?)?.toInt() ?? 0,
        bosZiyaret: (j['bos_ziyaret'] as num?)?.toInt() ?? 0,
        ortCikti: (j['ort_cikti'] as num?)?.toDouble() ?? 0,
        ortDakika: (j['ort_dakika'] as num?)?.toInt(),
        ciro: (j['ciro'] as num?)?.toDouble() ?? 0,
      );
}
