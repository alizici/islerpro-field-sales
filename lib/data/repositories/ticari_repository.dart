import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/network/supabase.dart';

/// Ticari işlemler (Faz 8): çek/senet yaşam döngüsü, iade, konsinye kapatma.
///
/// K11 · Çek ödeme değil ödeme VAADİDİR. Bakiye çek alındığında değil,
/// tahsil edildiğinde (ya da ciro edildiğinde) düşer.
/// K45 · Açık konsinye türetilir; kapatmak iki kayıt üretir — satış ve iade.
class TicariRepository {
  TicariRepository(this._db);
  final SupabaseClient _db;

  // ── Çek / senet ──────────────────────────────────────────────────────────
  Future<VadeTakvimi> vadeTakvimi(String storeId,
      {DateTime? baslangic, DateTime? bitis, String? durum}) async {
    final r = await _db.rpc<dynamic>('cheque_calendar', params: {
      'p_store_id': storeId,
      'p_baslangic': _gun(baslangic),
      'p_bitis': _gun(bitis),
      'p_durum': durum,
    });
    return VadeTakvimi.fromJson(((r ?? {}) as Map).cast());
  }

  Future<({String durum, bool degisti, double? bakiye})> cekDurumu(
    String cekId,
    String durum, {
    String? ciroEdilen,
    String? gerekce,
  }) async {
    final r = await _db.rpc<dynamic>('set_cheque_status', params: {
      'p_cheque_id': cekId,
      'p_durum': durum,
      'p_endorsed_to': ciroEdilen,
      'p_gerekce': gerekce,
    });
    final m = ((r ?? {}) as Map).cast<String, dynamic>();
    return (durum: m['durum'] as String? ?? durum,
            degisti: m['degisti'] as bool? ?? false,
            bakiye: (m['bakiye'] as num?)?.toDouble());
  }

  // ── İade ─────────────────────────────────────────────────────────────────
  Future<({String id, int kalem, double toplam, double? bakiye})> iadeAl({
    required String cariId,
    required List<({String urunId, int adet, String? teslimatKalemId})> kalemler,
    String? teslimatId,
    bool bakiyeyiAzaltir = true,
    String? gerekce,
    String? clientKey,
  }) async {
    final r = await _db.rpc<dynamic>('create_return', params: {
      'p_account_id': cariId,
      'p_items': [
        for (final k in kalemler)
          {
            if (k.teslimatKalemId != null) 'shipment_item_id': k.teslimatKalemId
            else 'product_id': k.urunId,
            'adet': k.adet,
          }
      ],
      'p_shipment_id': teslimatId,
      'p_bakiyeyi_azaltir': bakiyeyiAzaltir,
      'p_gerekce': gerekce,
      'p_client_key': clientKey,
    });
    final m = ((r ?? {}) as Map).cast<String, dynamic>();
    return (id: m['id'] as String,
            kalem: (m['kalem'] as num?)?.toInt() ?? 0,
            toplam: (m['toplam'] as num?)?.toDouble() ?? 0,
            bakiye: (m['bakiye'] as num?)?.toDouble());
  }

  /// Bu cariye çıkmış ve henüz iade edilmemiş kalemler. Ekran, iade
  /// edilemeyecek bir satırı hiç göstermemeli.
  Future<List<IadeKalemi>> iadeEdilebilirler(String cariId) async {
    final r = await _db.rpc<dynamic>('returnable_items',
        params: {'p_account_id': cariId});
    return ((r as List?) ?? const [])
        .map((e) => IadeKalemi.fromJson((e as Map).cast())).toList();
  }

  // ── Konsinye ─────────────────────────────────────────────────────────────
  Future<List<KonsinyeKalemi>> konsinyeDetay(String cariId) async {
    final r = await _db.rpc<dynamic>('open_consignment_detail',
        params: {'p_account_id': cariId});
    return ((r as List?) ?? const [])
        .map((e) => KonsinyeKalemi.fromJson((e as Map).cast())).toList();
  }

  Future<KonsinyeKapanisi> konsinyeKapat({
    required String cariId,
    List<({String urunId, int adet})> satilan = const [],
    List<({String urunId, int adet})> iade = const [],
    String? gerekce,
    String? clientKey,
  }) async {
    final r = await _db.rpc<dynamic>('settle_consignment', params: {
      'p_account_id': cariId,
      'p_satilan': [
        for (final k in satilan) {'product_id': k.urunId, 'adet': k.adet}
      ],
      'p_iade': [
        for (final k in iade) {'product_id': k.urunId, 'adet': k.adet}
      ],
      'p_gerekce': gerekce,
      'p_client_key': clientKey,
    });
    return KonsinyeKapanisi.fromJson(((r ?? {}) as Map).cast());
  }

  /// Açık konsinyesi olan cariler (0028 · consignment_report).
  Future<List<KonsinyeCari>> konsinyeCariler(String storeId) async {
    final r = await _db.rpc<dynamic>('consignment_report',
        params: {'p_store_id': storeId});
    return ((r as List?) ?? const [])
        .map((e) => KonsinyeCari.fromJson((e as Map).cast())).toList();
  }

  static String? _gun(DateTime? t) => t == null
      ? null
      : '${t.year.toString().padLeft(4, '0')}-'
        '${t.month.toString().padLeft(2, '0')}-'
        '${t.day.toString().padLeft(2, '0')}';
}

final ticariRepositoryProvider =
    Provider<TicariRepository>((ref) => TicariRepository(ref.watch(supabaseProvider)));

// ── Modeller ───────────────────────────────────────────────────────────────

/// K11 · Çekin durumu. Geçişler sunucudaki tabloda kilitli; ekran yalnızca
/// oradan gelen listeyi gösterir.
const cekDurumAdi = <String, String>{
  'portfoyde': 'Portföyde',
  'tahsilde': 'Tahsilde',
  'tahsil_edildi': 'Tahsil edildi',
  'ciro_edildi': 'Ciro edildi',
  'karsiliksiz': 'Karşılıksız',
  'iade_edildi': 'İade edildi',
};

/// Sunucudaki `cheque_transition_ok` ile AYNI tablo. İkisi ayrı yerlerde
/// duruyor ama e2e ikisini yan yana koyup karşılaştırıyor — ekran sunucunun
/// reddedeceği bir düğmeyi göstermesin.
const cekGecisleri = <String, List<String>>{
  'portfoyde': ['tahsilde', 'ciro_edildi', 'iade_edildi'],
  'tahsilde': ['tahsil_edildi', 'karsiliksiz', 'portfoyde'],
  'ciro_edildi': ['karsiliksiz'],
  'karsiliksiz': ['tahsilde', 'tahsil_edildi'],
  'tahsil_edildi': [],
  'iade_edildi': [],
};

class Cek {
  const Cek({required this.id, required this.unvan, required this.tutar,
             required this.vade, required this.durum, this.tip = 'cek',
             this.banka, this.kesideci, this.cekNo, this.gun});
  final String id, unvan, durum, tip;
  final double tutar;

  /// Sunucu bir alanı göndermeyi unutursa EKRANIN TAMAMI kararmasın diye
  /// null olabilir. `cheque_calendar` gün gruplarında `due_date`'i uzun süre
  /// göndermedi ve zorunlu alan olduğu için tek bir çek Vadeler ekranını
  /// tamamen boşaltıyordu (0038 sunucu tarafını düzeltti). Tek satırın eksik
  /// kalması, bütün takvimin kaybolmasından iyidir.
  final DateTime? vade;
  final String? banka, kesideci, cekNo;
  /// Gecikmişlerde geçen gün, takvimde kalan gün.
  final int? gun;

  bool get acik => durum == 'portfoyde' || durum == 'tahsilde';
  List<String> get gidilebilir => cekGecisleri[durum] ?? const [];

  static Cek fromJson(Map<String, dynamic> j) => Cek(
        id: j['id'] as String,
        unvan: j['unvan'] as String? ?? '',
        tutar: (j['tutar'] as num?)?.toDouble() ?? 0,
        vade: DateTime.tryParse(j['due_date'] as String? ?? ''),
        durum: j['durum'] as String? ?? 'portfoyde',
        tip: j['tip'] as String? ?? 'cek',
        banka: j['banka'] as String?,
        kesideci: j['kesideci'] as String?,
        cekNo: j['cheque_no'] as String?,
        gun: (j['gun'] as num?)?.toInt(),
      );
}

class VadeGunu {
  const VadeGunu({required this.tarih, required this.tutar, required this.adet,
                  this.gun = 0, this.cekler = const []});
  final DateTime tarih;
  final double tutar;
  final int adet, gun;
  final List<Cek> cekler;

  static VadeGunu fromJson(Map<String, dynamic> j) => VadeGunu(
        tarih: DateTime.parse(j['tarih'] as String),
        tutar: (j['tutar'] as num?)?.toDouble() ?? 0,
        adet: (j['adet'] as num?)?.toInt() ?? 0,
        gun: (j['gun'] as num?)?.toInt() ?? 0,
        cekler: ((j['cekler'] as List?) ?? const [])
            .map((e) => Cek.fromJson((e as Map).cast())).toList(),
      );
}

class VadeTakvimi {
  const VadeTakvimi({this.gecikmis = const [], this.gecikmisTutar = 0,
                     this.gunler = const [], this.toplam = 0,
                     this.portfoyde = 0, this.tahsilde = 0,
                     this.karsiliksiz = 0});
  final List<Cek> gecikmis;
  final List<VadeGunu> gunler;
  final double gecikmisTutar, toplam, portfoyde, tahsilde, karsiliksiz;

  bool get bos => gecikmis.isEmpty && gunler.isEmpty;

  static VadeTakvimi fromJson(Map<String, dynamic> j) => VadeTakvimi(
        gecikmis: ((j['gecikmis'] as List?) ?? const [])
            .map((e) => Cek.fromJson((e as Map).cast())).toList(),
        gecikmisTutar: (j['gecikmis_tutar'] as num?)?.toDouble() ?? 0,
        gunler: ((j['gunler'] as List?) ?? const [])
            .map((e) => VadeGunu.fromJson((e as Map).cast())).toList(),
        toplam: (j['toplam'] as num?)?.toDouble() ?? 0,
        portfoyde: (j['portfoyde'] as num?)?.toDouble() ?? 0,
        tahsilde: (j['tahsilde'] as num?)?.toDouble() ?? 0,
        karsiliksiz: (j['karsiliksiz'] as num?)?.toDouble() ?? 0,
      );
}

class KonsinyeKalemi {
  const KonsinyeKalemi({required this.urunId, required this.ad,
                        required this.birakilan, required this.kalan,
                        this.barkod, this.yayinevi, this.satilan = 0,
                        this.iade = 0, this.birimFiyat, this.iskontoOrani = 0});
  final String urunId, ad;
  final String? barkod, yayinevi;
  final int birakilan, satilan, iade, kalan;
  final double? birimFiyat;
  final double iskontoOrani;

  /// V6 · satır aritmetiği: fiyat × (1 − iskonto) × adet
  double tutar(int adet) =>
      (birimFiyat ?? 0) * (1 - iskontoOrani) * adet;

  static KonsinyeKalemi fromJson(Map<String, dynamic> j) => KonsinyeKalemi(
        urunId: j['product_id'] as String,
        ad: j['ad'] as String? ?? '',
        barkod: j['barkod'] as String?,
        yayinevi: j['yayinevi'] as String?,
        birakilan: (j['birakilan'] as num?)?.toInt() ?? 0,
        satilan: (j['satilan'] as num?)?.toInt() ?? 0,
        iade: (j['iade'] as num?)?.toInt() ?? 0,
        kalan: (j['kalan'] as num?)?.toInt() ?? 0,
        birimFiyat: (j['birim_fiyat'] as num?)?.toDouble(),
        iskontoOrani: (j['iskonto_orani'] as num?)?.toDouble() ?? 0,
      );
}

class KonsinyeKapanisi {
  const KonsinyeKapanisi({this.teslimatId, this.iadeId, this.borc = 0,
                          this.kalanKonsinye = 0, this.bakiye = 0});
  final String? teslimatId, iadeId;
  final double borc, kalanKonsinye, bakiye;

  static KonsinyeKapanisi fromJson(Map<String, dynamic> j) => KonsinyeKapanisi(
        teslimatId: j['shipment_id'] as String?,
        iadeId: j['return_id'] as String?,
        borc: (j['borc'] as num?)?.toDouble() ?? 0,
        kalanKonsinye: (j['kalan_konsinye'] as num?)?.toDouble() ?? 0,
        bakiye: (j['bakiye'] as num?)?.toDouble() ?? 0,
      );
}

class KonsinyeCari {
  const KonsinyeCari({required this.id, required this.unvan,
                      required this.kalanAdet, this.kurumAd, this.pazarlamaci});
  final String id, unvan;
  final String? kurumAd, pazarlamaci;
  final double kalanAdet;

  static KonsinyeCari fromJson(Map<String, dynamic> j) => KonsinyeCari(
        id: j['id'] as String,
        unvan: j['unvan'] as String? ?? '',
        kurumAd: j['kurum_ad'] as String?,
        kalanAdet: (j['kalan_adet'] as num?)?.toDouble() ?? 0,
        pazarlamaci: j['pazarlamaci'] as String?,
      );
}

class IadeKalemi {
  const IadeKalemi({required this.urunId, required this.ad,
                    required this.cikan, required this.kalan,
                    this.barkod, this.yayinevi, this.iade = 0,
                    this.borclandirdi = true, this.birimFiyat,
                    this.iskontoOrani = 0});
  final String urunId, ad;
  final String? barkod, yayinevi;
  final int cikan, iade, kalan;
  /// Borçlandıran teslimattan geldiyse iade borcu DÜŞÜRÜR; konsinyeden
  /// geldiyse yalnızca açık konsinyeyi azaltır (K45).
  final bool borclandirdi;
  final double? birimFiyat;
  final double iskontoOrani;

  double tutar(int adet) => (birimFiyat ?? 0) * (1 - iskontoOrani) * adet;

  static IadeKalemi fromJson(Map<String, dynamic> j) => IadeKalemi(
        urunId: j['product_id'] as String,
        ad: j['ad'] as String? ?? '',
        barkod: j['barkod'] as String?,
        yayinevi: j['yayinevi'] as String?,
        cikan: (j['cikan'] as num?)?.toInt() ?? 0,
        iade: (j['iade'] as num?)?.toInt() ?? 0,
        kalan: (j['kalan'] as num?)?.toInt() ?? 0,
        borclandirdi: j['borclandirdi'] as bool? ?? true,
        birimFiyat: (j['birim_fiyat'] as num?)?.toDouble(),
        iskontoOrani: (j['iskonto_orani'] as num?)?.toDouble() ?? 0,
      );
}
