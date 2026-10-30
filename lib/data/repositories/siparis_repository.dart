import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/network/supabase.dart';

/// Sipariş, teslimat ve tahsilat (Faz 4).
///
/// K26 · Borç faturayla değil TESLİMATLA doğar — sipariş henüz borç değildir.
/// K28 · Sipariş satırı fiyatı, iskontoyu ve maliyeti damgalar.
/// K48 · Ödeme parçalıdır; durum türetilir, hiçbir yerde yazılmaz.
class SiparisRepository {
  SiparisRepository(this._db);
  final SupabaseClient _db;

  Future<({String id, int kalem, double toplam, String? onayGerekce})>
      talebiSiparisEt(String talepId) async {
    final r = await _db.rpc<dynamic>('create_order_from_request',
        params: {'p_request_id': talepId});
    final m = (r as Map).cast<String, dynamic>();
    return (id: m['id'] as String,
            kalem: (m['kalem'] as num?)?.toInt() ?? 0,
            toplam: (m['toplam'] as num?)?.toDouble() ?? 0,
            onayGerekce: m['onay_gerekce'] as String?);
  }

  Future<void> durumDegistir(String siparisId, String durum,
          {String? gerekce}) =>
      _db.rpc<dynamic>('set_order_status', params: {
        'p_order_id': siparisId, 'p_durum': durum, 'p_gerekce': gerekce,
      });

  Future<List<SiparisOzet>> liste({
    String? storeId, String? durum, String? cariId,
    bool hazirlikKutusu = false, int limit = 50, int offset = 0,
  }) async {
    final r = await _db.rpc<dynamic>('list_orders', params: {
      'p_store_id': storeId, 'p_durum': durum, 'p_account_id': cariId,
      'p_hazirlik_kutusu': hazirlikKutusu, 'p_limit': limit,
      'p_offset': offset,
    });
    return (r as List)
        .map((e) => SiparisOzet.fromJson((e as Map).cast())).toList();
  }

  Future<SiparisDetay> detay(String siparisId) async {
    final r = await _db.rpc<dynamic>('order_detail',
        params: {'p_order_id': siparisId});
    if (r == null) throw StateError('Sipariş bulunamadı veya yetkiniz yok');
    return SiparisDetay.fromJson((r as Map).cast());
  }

  /// K26 · BORÇ BURADA DOĞAR. [borclandirir] false → konsinye bırakma.
  Future<({String id, double toplam, int kalanAdet})> teslimEt({
    required String cariId,
    required List<({String? siparisKalemId, String? urunId, int adet})> kalemler,
    String? siparisId,
    bool borclandirir = true,
    String tip = 'teslimat',
    String? teslimAlanAd,
    String? clientKey,
  }) async {
    final r = await _db.rpc<dynamic>('create_shipment', params: {
      'p_account_id': cariId,
      'p_items': [
        for (final k in kalemler)
          {
            if (k.siparisKalemId != null) 'order_item_id': k.siparisKalemId,
            if (k.urunId != null) 'product_id': k.urunId,
            'adet': k.adet,
          },
      ],
      'p_order_id': siparisId,
      'p_borclandirir': borclandirir,
      'p_tip': tip,
      'p_teslim_alan_ad': teslimAlanAd,
      'p_client_key': clientKey,
    });
    final m = (r as Map).cast<String, dynamic>();
    return (id: m['id'] as String,
            toplam: (m['toplam'] as num?)?.toDouble() ?? 0,
            kalanAdet: (m['kalan_adet'] as num?)?.toInt() ?? 0);
  }

  /// K48 · FIFO mahsup. Çek/senet ödeme değil ödeme VAADİDİR (K11).
  Future<TahsilatSonucu> tahsilEt({
    required String cariId,
    required double tutar,
    required String yontem,
    DateTime? tarih,
    String? makbuzNo,
    String? notMetni,
    DateTime? cekVade,
    String? cekBanka,
    String? cekNo,
    String? clientKey,
  }) async {
    final r = await _db.rpc<dynamic>('create_payment', params: {
      'p_account_id': cariId, 'p_tutar': tutar, 'p_yontem': yontem,
      'p_tarih': tarih?.toIso8601String().split('T').first,
      'p_makbuz_no': makbuzNo, 'p_not_metni': notMetni,
      'p_cek_vade': cekVade?.toIso8601String().split('T').first,
      'p_cek_banka': cekBanka, 'p_cek_no': cekNo, 'p_client_key': clientKey,
    });
    return TahsilatSonucu.fromJson((r as Map).cast());
  }

  Future<Ekstre> ekstre(String cariId) async {
    final r = await _db.rpc<dynamic>('account_statement',
        params: {'p_account_id': cariId});
    return Ekstre.fromJson(((r ?? {}) as Map).cast());
  }

  // K50 · Faz 4'ün çekirdek raporları (`aging_report`, `collection_summary`,
  // `revenue_report`) Faz 10'da rapor MOTORUNA devredildi; uygulama artık
  // onları çağırmıyor. SQL tarafı yerinde duruyor: pilotta koşan sürüm hâlâ
  // o RPC'lere bağlı ve uçtan uca testler onları doğruluyor. Kaldırma pilot
  // bittikten sonra yapılır.

  /// B1 · Makbuz. Fatura değildir (K26) — tahsilatın belgesidir.
  Future<Map<String, dynamic>> makbuz(String tahsilatId) async {
    final r = await _db.rpc<dynamic>('receipt_data',
        params: {'p_payment_id': tahsilatId});
    return ((r ?? {}) as Map).cast<String, dynamic>();
  }

  /// Açılış ekranları TEK ÇAĞRIDA gelir — sunucu ~340 ms uzakta.
  Future<PanelOzeti> panel(String storeId, {String? periodId}) async {
    final r = await _db.rpc<dynamic>('dashboard_owner',
        params: {'p_store_id': storeId, 'p_period_id': periodId});
    return PanelOzeti.fromJson(((r ?? {}) as Map).cast());
  }

  Future<BugunOzeti> bugun(String storeId, {String? periodId}) async {
    final r = await _db.rpc<dynamic>('dashboard_marketer',
        params: {'p_store_id': storeId, 'p_period_id': periodId});
    return BugunOzeti.fromJson(((r ?? {}) as Map).cast());
  }

  /// K48 · Mahsup sırası: en eski açık borçtan başlar. Tahsilat diyaloğu
  /// bunu ÖNCEDEN göstermek için kullanır — sıralama sunucudaki
  /// `allocate_payment_fifo` ile birebir aynı olmak zorunda.
  Future<List<AcikTeslimat>> acikTeslimatlar(String cariId) async {
    final r = await _db.rpc<dynamic>('account_open_shipments',
        params: {'p_account_id': cariId});
    return ((r ?? const []) as List)
        .map((e) => AcikTeslimat.fromJson((e as Map).cast())).toList();
  }

  Future<List<BorcluCari>> borclular(String storeId) async {
    final r = await _db.rpc<dynamic>('open_debts', params: {'p_store_id': storeId});
    return (r as List)
        .map((e) => BorcluCari.fromJson((e as Map).cast())).toList();
  }
}

final siparisRepositoryProvider = Provider<SiparisRepository>(
    (ref) => SiparisRepository(ref.watch(supabaseProvider)));

// ── Modeller ───────────────────────────────────────────────────────────────

class SiparisOzet {
  const SiparisOzet({
    required this.id, required this.durum, required this.tip,
    required this.createdAt, required this.cariId, required this.unvan,
    this.kurumAd, this.olusturan, this.hazirlayan, this.onayGerekce,
    this.kalemSayisi = 0, this.toplam = 0, this.bekleyenAdet = 0,
  });

  final String id, durum, tip, cariId, unvan;
  final DateTime createdAt;
  final String? kurumAd, olusturan, hazirlayan, onayGerekce;
  final int kalemSayisi, bekleyenAdet;
  final double toplam;

  bool get onayBekliyor => durum == 'onay_bekliyor';
  bool get hazirlikte => durum == 'hazirlaniyor';
  /// H-3 · sevk edilmemiş adet ayrı kayıt değil, türetilmiş sayıdır.
  bool get backorderVar => bekleyenAdet > 0 &&
      (durum == 'kismi_teslim' || durum == 'sevk_edildi');

  String get durumAdi => switch (durum) {
        'olusturuldu' => 'Oluşturuldu',
        'onay_bekliyor' => 'Onay bekliyor',
        'reddedildi' => 'Reddedildi',
        'hazirlaniyor' => 'Hazırlanıyor',
        'hazir' => 'Hazır',
        'sevk_edildi' => 'Sevk edildi',
        'kismi_teslim' => 'Kısmi teslim',
        'teslim_edildi' => 'Teslim edildi',
        'kapandi' => 'Kapandı',
        'iptal' => 'İptal',
        _ => durum,
      };

  static SiparisOzet fromJson(Map<String, dynamic> j) => SiparisOzet(
        id: j['id'] as String,
        durum: j['durum'] as String? ?? '',
        tip: j['tip'] as String? ?? 'satis',
        createdAt: DateTime.parse(j['created_at'] as String),
        cariId: j['account_id'] as String,
        unvan: j['unvan'] as String? ?? '',
        kurumAd: j['kurum_ad'] as String?,
        olusturan: j['olusturan'] as String?,
        hazirlayan: j['hazirlayan'] as String?,
        onayGerekce: j['onay_gerekce'] as String?,
        kalemSayisi: (j['kalem_sayisi'] as num?)?.toInt() ?? 0,
        toplam: (j['toplam'] as num?)?.toDouble() ?? 0,
        bekleyenAdet: (j['bekleyen_adet'] as num?)?.toInt() ?? 0,
      );
}

class SiparisDetay {
  const SiparisDetay({
    required this.id, required this.durum, required this.tip,
    required this.createdAt, required this.cariId, required this.cariUnvan,
    required this.kurumAd,
    this.olusturan, this.hazirlayan, this.hazirlikBasladi, this.hazirlikBitti,
    this.onayGerekce, this.requestId, this.toplam = 0,
    this.bakiye = 0, this.risk = 0, this.creditLimit = 0,
    this.kalemler = const [],
  });

  final String id, durum, tip, cariId, cariUnvan, kurumAd;
  final DateTime createdAt;
  final String? olusturan, hazirlayan, onayGerekce, requestId;
  final DateTime? hazirlikBasladi, hazirlikBitti;
  final double toplam, bakiye, risk, creditLimit;
  final List<SiparisKalemi> kalemler;

  bool get sevkEdilebilir =>
      durum == 'hazir' || durum == 'sevk_edildi' || durum == 'kismi_teslim';
  int get toplamBackorder =>
      kalemler.fold(0, (t, k) => t + k.backorder);

  static SiparisDetay fromJson(Map<String, dynamic> j) {
    final c = ((j['cari'] as Map?) ?? {}).cast<String, dynamic>();
    return SiparisDetay(
      id: j['id'] as String,
      durum: j['durum'] as String? ?? '',
      tip: j['tip'] as String? ?? 'satis',
      createdAt: DateTime.parse(j['created_at'] as String),
      cariId: c['id'] as String? ?? '',
      cariUnvan: c['unvan'] as String? ?? '',
      kurumAd: ((j['kurum'] as Map?) ?? {})['ad'] as String? ?? '',
      olusturan: j['olusturan'] as String?,
      hazirlayan: j['hazirlayan'] as String?,
      hazirlikBasladi: j['hazirlik_basladi_at'] == null
          ? null : DateTime.parse(j['hazirlik_basladi_at'] as String),
      hazirlikBitti: j['hazirlik_bitti_at'] == null
          ? null : DateTime.parse(j['hazirlik_bitti_at'] as String),
      onayGerekce: j['onay_gerekce'] as String?,
      requestId: j['request_id'] as String?,
      toplam: (j['toplam'] as num?)?.toDouble() ?? 0,
      bakiye: (c['bakiye'] as num?)?.toDouble() ?? 0,
      risk: (c['risk'] as num?)?.toDouble() ?? 0,
      creditLimit: (c['credit_limit'] as num?)?.toDouble() ?? 0,
      kalemler: ((j['kalemler'] as List?) ?? const [])
          .map((e) => SiparisKalemi.fromJson((e as Map).cast())).toList(),
    );
  }
}

class SiparisKalemi {
  const SiparisKalemi({
    required this.id, required this.urunId, required this.ad,
    required this.adet, required this.birimFiyat, required this.satirTutari,
    this.barkod, this.yayinevi, this.iskontoOrani = 0,
    this.sevkEdilen = 0, this.backorder = 0,
  });

  final String id, urunId, ad;
  final String? barkod, yayinevi;
  final int adet, sevkEdilen, backorder;
  final double birimFiyat, iskontoOrani, satirTutari;

  bool get tamSevk => backorder == 0;

  static SiparisKalemi fromJson(Map<String, dynamic> j) => SiparisKalemi(
        id: j['id'] as String,
        urunId: j['product_id'] as String,
        ad: j['ad'] as String? ?? '',
        adet: (j['adet'] as num?)?.toInt() ?? 0,
        birimFiyat: (j['birim_fiyat'] as num?)?.toDouble() ?? 0,
        iskontoOrani: (j['iskonto_orani'] as num?)?.toDouble() ?? 0,
        satirTutari: (j['satir_tutari'] as num?)?.toDouble() ?? 0,
        barkod: j['barkod'] as String?,
        yayinevi: j['yayinevi'] as String?,
        sevkEdilen: (j['sevk_edilen'] as num?)?.toInt() ?? 0,
        backorder: (j['backorder'] as num?)?.toInt() ?? 0,
      );
}

class TahsilatSonucu {
  const TahsilatSonucu({required this.id, this.cek = false,
                        this.dagitilan = 0, this.avans = 0, this.not});
  final String id;
  final bool cek;
  final double dagitilan, avans;
  final String? not;
  static TahsilatSonucu fromJson(Map<String, dynamic> j) => TahsilatSonucu(
        id: j['id'] as String,
        cek: j['cek'] as bool? ?? false,
        dagitilan: (j['dagitilan'] as num?)?.toDouble() ?? 0,
        avans: (j['avans'] as num?)?.toDouble() ?? 0,
        not: j['not'] as String?,
      );
}

class Ekstre {
  const Ekstre({this.bakiye = 0, this.risk = 0, this.acikKonsinye = 0,
                this.hareketler = const []});
  final double bakiye, risk, acikKonsinye;
  final List<EkstreSatiri> hareketler;
  static Ekstre fromJson(Map<String, dynamic> j) => Ekstre(
        bakiye: (j['bakiye'] as num?)?.toDouble() ?? 0,
        risk: (j['risk'] as num?)?.toDouble() ?? 0,
        acikKonsinye: (j['acik_konsinye'] as num?)?.toDouble() ?? 0,
        hareketler: ((j['hareketler'] as List?) ?? const [])
            .map((e) => EkstreSatiri.fromJson((e as Map).cast())).toList(),
      );
}

class EkstreSatiri {
  const EkstreSatiri({required this.tur, required this.tarih,
                      required this.aciklama, this.borc = 0, this.alacak = 0,
                      this.odemeDurumu});
  final String tur, aciklama;
  final DateTime tarih;
  final double borc, alacak;
  final String? odemeDurumu;

  String get odemeAdi => switch (odemeDurumu) {
        'odenmedi' => 'Ödenmedi',
        'kismi' => 'Kısmi',
        'odendi' => 'Ödendi',
        'vaat' => 'Ödeme vaadi',
        _ => '',
      };

  static EkstreSatiri fromJson(Map<String, dynamic> j) => EkstreSatiri(
        tur: j['tur'] as String? ?? '',
        tarih: DateTime.parse(j['tarih'] as String),
        aciklama: j['aciklama'] as String? ?? '',
        borc: (j['borc'] as num?)?.toDouble() ?? 0,
        alacak: (j['alacak'] as num?)?.toDouble() ?? 0,
        odemeDurumu: j['odeme_durumu'] as String?,
      );
}

/// Ödenmemiş kısmı kalan bir teslimat. Bakiye gibi TÜRETİLMİŞTİR: teslimat
/// tutarı eksi ona mahsup edilmiş ödemeler.
class AcikTeslimat {
  const AcikTeslimat({required this.id, required this.tarih,
                      required this.tutar, required this.odenen,
                      this.kalem = 0});
  final String id;
  final DateTime? tarih;
  final double tutar, odenen;
  final int kalem;

  double get kalan => tutar - odenen;
  bool get kismiOdenmis => odenen > 0;

  static AcikTeslimat fromJson(Map<String, dynamic> j) => AcikTeslimat(
        id: j['id'] as String,
        tarih: DateTime.tryParse(j['tarih'] as String? ?? ''),
        tutar: (j['tutar'] as num?)?.toDouble() ?? 0,
        odenen: (j['odenen'] as num?)?.toDouble() ?? 0,
        kalem: (j['kalem'] as num?)?.toInt() ?? 0,
      );
}

class BorcluCari {
  const BorcluCari({required this.id, required this.unvan, required this.tip,
                    this.kurumAd, this.bakiye = 0, this.risk = 0,
                    this.creditLimit = 0, this.pazarlamaci, this.enEskiBorc});
  final String id, unvan, tip;
  final String? kurumAd, pazarlamaci;
  final double bakiye, risk, creditLimit;
  final DateTime? enEskiBorc;

  bool get limitAsildi => creditLimit > 0 && risk > creditLimit;
  int? get gecikmeGunu => enEskiBorc == null
      ? null : DateTime.now().difference(enEskiBorc!).inDays;

  static BorcluCari fromJson(Map<String, dynamic> j) => BorcluCari(
        id: j['id'] as String,
        unvan: j['unvan'] as String? ?? '',
        tip: j['tip'] as String? ?? 'kurum',
        kurumAd: j['kurum_ad'] as String?,
        bakiye: (j['bakiye'] as num?)?.toDouble() ?? 0,
        risk: (j['risk'] as num?)?.toDouble() ?? 0,
        creditLimit: (j['credit_limit'] as num?)?.toDouble() ?? 0,
        pazarlamaci: j['pazarlamaci'] as String?,
        enEskiBorc: j['en_eski_borc'] == null
            ? null : DateTime.parse(j['en_eski_borc'] as String),
      );
}

/// K50 · Yaşlandırma. Kovalar: 0-30 · 31-60 · 61-90 · 90+


class OzetSatiri {
  const OzetSatiri({required this.etiket, this.adet = 0, this.tutar = 0,
                    this.vaat = false});
  final String etiket;
  final int adet;
  final double tutar;
  final bool vaat;
  static OzetSatiri fromJson(Map<String, dynamic> j) => OzetSatiri(
        etiket: (j['yontem'] ?? j['ad_soyad'] ?? j['etiket'] ?? '—') as String,
        adet: (j['adet'] as num?)?.toInt() ?? 0,
        tutar: (j['tutar'] as num?)?.toDouble() ?? 0,
        vaat: j['vaat'] as bool? ?? false,
      );
}



/// Sahibin açılış ekranı. K7 · buradaki tek toplam DÜKKANIN açık alacağıdır.
class PanelOzeti {
  const PanelOzeti({this.bekleyenTalep = 0, this.gecikmisTalep = 0,
      this.onayBekleyenSiparis = 0, this.hazirlanacakSiparis = 0,
      this.portfoysuzCari = 0, this.acikAlacak = 0, this.borcluCari = 0,
      this.gecikmisBorc = 0, this.donemCiro = 0, this.donemTahsilat = 0,
      this.portfoydekiCek = 0, this.huni = const Huni(),
      this.pazarlamacilar = const [], this.donemAd});

  final int bekleyenTalep, gecikmisTalep, onayBekleyenSiparis,
      hazirlanacakSiparis, portfoysuzCari, borcluCari;
  final double acikAlacak, gecikmisBorc, donemCiro, donemTahsilat,
      portfoydekiCek;
  final Huni huni;
  final List<PanelPazarlamaci> pazarlamacilar;
  final String? donemAd;

  /// Hemen bakılması gereken bir şey var mı
  bool get acilVar => gecikmisTalep > 0 || onayBekleyenSiparis > 0 ||
      portfoysuzCari > 0;

  static PanelOzeti fromJson(Map<String, dynamic> j) => PanelOzeti(
        bekleyenTalep: (j['bekleyen_talep'] as num?)?.toInt() ?? 0,
        gecikmisTalep: (j['gecikmis_talep'] as num?)?.toInt() ?? 0,
        onayBekleyenSiparis: (j['onay_bekleyen_siparis'] as num?)?.toInt() ?? 0,
        hazirlanacakSiparis: (j['hazirlanacak_siparis'] as num?)?.toInt() ?? 0,
        portfoysuzCari: (j['portfoysuz_cari'] as num?)?.toInt() ?? 0,
        acikAlacak: (j['acik_alacak'] as num?)?.toDouble() ?? 0,
        borcluCari: (j['borclu_cari'] as num?)?.toInt() ?? 0,
        gecikmisBorc: (j['gecikmis_borc'] as num?)?.toDouble() ?? 0,
        donemCiro: (j['donem_ciro'] as num?)?.toDouble() ?? 0,
        donemTahsilat: (j['donem_tahsilat'] as num?)?.toDouble() ?? 0,
        portfoydekiCek: (j['portfoydeki_cek'] as num?)?.toDouble() ?? 0,
        huni: Huni.fromJson(((j['huni'] as Map?) ?? {}).cast()),
        pazarlamacilar: ((j['pazarlamacilar'] as List?) ?? const [])
            .map((e) => PanelPazarlamaci.fromJson((e as Map).cast())).toList(),
        donemAd: j['donem_ad'] as String?,
      );
}

/// K37 · Talep hunisi: açılan → karara bağlanan → siparişe dönen
class Huni {
  const Huni({this.acilan = 0, this.kararaBaglanan = 0, this.reddedilen = 0,
              this.siparise = 0});
  final int acilan, kararaBaglanan, reddedilen, siparise;
  double get donusum => acilan == 0 ? 0 : siparise / acilan;
  static Huni fromJson(Map<String, dynamic> j) => Huni(
        acilan: (j['acilan'] as num?)?.toInt() ?? 0,
        kararaBaglanan: (j['karara_baglanan'] as num?)?.toInt() ?? 0,
        reddedilen: (j['reddedilen'] as num?)?.toInt() ?? 0,
        siparise: (j['siparise_donen'] as num?)?.toInt() ?? 0,
      );
}

class PanelPazarlamaci {
  const PanelPazarlamaci({required this.userId, required this.adSoyad,
                          this.cariSayisi = 0, this.acikTalep = 0});
  final String userId, adSoyad;
  final int cariSayisi, acikTalep;
  static PanelPazarlamaci fromJson(Map<String, dynamic> j) => PanelPazarlamaci(
        userId: j['user_id'] as String, adSoyad: j['ad_soyad'] as String? ?? '',
        cariSayisi: (j['cari_sayisi'] as num?)?.toInt() ?? 0,
        acikTalep: (j['acik_talep'] as num?)?.toInt() ?? 0,
      );
}

/// Pazarlamacının günü. Yalnızca KENDİ portföyü (K5).
class BugunOzeti {
  const BugunOzeti({this.portfoyCari = 0, this.bekleyenTalep = 0,
      this.gecikmisTalep = 0, this.hazirSiparis = 0, this.borcluCari = 0,
      this.acikAlacak = 0, this.acikKonsinyeCari = 0, this.donemCiro = 0,
      this.donemTahsilat = 0, this.gecikmisTalepler = const [],
      this.hatirlatmalar = const [], this.donemAd});

  final int portfoyCari, bekleyenTalep, gecikmisTalep, hazirSiparis,
      borcluCari, acikKonsinyeCari;
  final double acikAlacak, donemCiro, donemTahsilat;
  final List<GecikmisTalep> gecikmisTalepler;
  final List<TahsilatHatirlatmasi> hatirlatmalar;
  final String? donemAd;

  bool get isVar => gecikmisTalep > 0 || bekleyenTalep > 0 ||
      hazirSiparis > 0 || borcluCari > 0;

  static BugunOzeti fromJson(Map<String, dynamic> j) => BugunOzeti(
        portfoyCari: (j['portfoy_cari'] as num?)?.toInt() ?? 0,
        bekleyenTalep: (j['bekleyen_talep'] as num?)?.toInt() ?? 0,
        gecikmisTalep: (j['gecikmis_talep'] as num?)?.toInt() ?? 0,
        hazirSiparis: (j['hazir_siparis'] as num?)?.toInt() ?? 0,
        borcluCari: (j['borclu_cari'] as num?)?.toInt() ?? 0,
        acikAlacak: (j['acik_alacak'] as num?)?.toDouble() ?? 0,
        acikKonsinyeCari: (j['acik_konsinye_cari'] as num?)?.toInt() ?? 0,
        donemCiro: (j['donem_ciro'] as num?)?.toDouble() ?? 0,
        donemTahsilat: (j['donem_tahsilat'] as num?)?.toDouble() ?? 0,
        gecikmisTalepler: ((j['gecikmis_talepler'] as List?) ?? const [])
            .map((e) => GecikmisTalep.fromJson((e as Map).cast())).toList(),
        hatirlatmalar: ((j['tahsilat_hatirlatmalari'] as List?) ?? const [])
            .map((e) => TahsilatHatirlatmasi.fromJson((e as Map).cast())).toList(),
        donemAd: j['donem_ad'] as String?,
      );
}

class GecikmisTalep {
  const GecikmisTalep({required this.id, required this.unvan,
                       required this.createdAt, this.kalem = 0, this.saat = 0});
  final String id, unvan;
  final DateTime createdAt;
  final int kalem;
  final double saat;
  int get gun => (saat / 24).floor();
  static GecikmisTalep fromJson(Map<String, dynamic> j) => GecikmisTalep(
        id: j['id'] as String, unvan: j['unvan'] as String? ?? '',
        createdAt: DateTime.parse(j['created_at'] as String),
        kalem: (j['kalem'] as num?)?.toInt() ?? 0,
        saat: (j['saat'] as num?)?.toDouble() ?? 0,
      );
}

class TahsilatHatirlatmasi {
  const TahsilatHatirlatmasi({required this.id, required this.unvan,
                              this.bakiye = 0, this.gun});
  final String id, unvan;
  final double bakiye;
  final int? gun;
  static TahsilatHatirlatmasi fromJson(Map<String, dynamic> j) =>
      TahsilatHatirlatmasi(
        id: j['id'] as String, unvan: j['unvan'] as String? ?? '',
        bakiye: (j['bakiye'] as num?)?.toDouble() ?? 0,
        gun: (j['gun'] as num?)?.toInt(),
      );
}
