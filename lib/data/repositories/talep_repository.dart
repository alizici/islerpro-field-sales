import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/network/supabase.dart';
import 'katalog_repository.dart';

/// Talep akışı — ürünün kalbi (Faz 3).
///
/// K36 · Kalemler yalnızca katalogdan seçilir; serbest metin yoktur.
/// K37 · Karar KALEM bazındadır; 5 kalemin 3'ü onaylanıp 2'si reddedilebilir.
/// K41 · Bildirim carinin portföy sahibine gider, kurumun değil.
class TalepRepository {
  TalepRepository(this._db);
  final SupabaseClient _db;

  /// K5 · K19 · Öğretmen okul adına yetkili değilse kurumsal cari çıkmaz.
  Future<List<Muhatap>> muhataplar() async {
    final r = await _db.rpc<dynamic>('my_request_accounts');
    return (r as List).map((e) => Muhatap.fromJson((e as Map).cast())).toList();
  }

  /// K22 · Dört kademeli yedek zincir. Öneri hiçbir koşulda tıkanmaz.
  Future<AdetOnerisi> adetOnerisi({
    required String cariId, required String urunId, String? periodId,
  }) async {
    final r = await _db.rpc<dynamic>('suggest_quantity', params: {
      'p_account_id': cariId, 'p_product_id': urunId, 'p_period_id': periodId,
    });
    return AdetOnerisi.fromJson((r as Map).cast());
  }

  Future<({String id, bool yeni})> olustur({
    required String cariId,
    required List<({String urunId, int adet})> kalemler,
    String? notMetni,
    DateTime? istenenTarih,
    bool gonder = true,
    String? clientKey,
  }) async {
    final r = await _db.rpc<dynamic>('create_request', params: {
      'p_account_id': cariId,
      'p_items': [
        for (final k in kalemler) {'product_id': k.urunId, 'adet': k.adet},
      ],
      'p_not_metni': notMetni,
      'p_istenen_tarih': istenenTarih?.toIso8601String().split('T').first,
      'p_gonder': gonder,
      'p_client_key': clientKey,
    });
    final m = (r as Map).cast<String, dynamic>();
    return (id: m['id'] as String, yeni: m['yeni'] as bool? ?? true);
  }

  Future<void> gonder(String talepId) =>
      _db.rpc<dynamic>('submit_request', params: {'p_request_id': talepId});

  Future<void> eleAl(String talepId) =>
      _db.rpc<dynamic>('claim_request', params: {'p_request_id': talepId});

  Future<void> iptal(String talepId, {String? gerekce}) =>
      _db.rpc<dynamic>('cancel_request',
          params: {'p_request_id': talepId, 'p_gerekce': gerekce});

  /// K37 · Kısmi karar mümkündür: bekleyen kalem kalırsa talep kapanmaz.
  Future<KararSonucu> kararVer({
    required String talepId,
    required List<KalemKarari> kararlar,
  }) async {
    final r = await _db.rpc<dynamic>('decide_request_items', params: {
      'p_request_id': talepId,
      'p_kararlar': [
        for (final k in kararlar)
          {
            'item_id': k.kalemId,
            'durum': k.onay ? 'onaylandi' : 'reddedildi',
            if (!k.onay) 'red_nedeni': k.redNedeni,
          },
      ],
    });
    return KararSonucu.fromJson((r as Map).cast());
  }

  Future<List<TalepOzet>> liste({
    String? storeId, String? durum, String? cariId,
    bool sadeceBekleyen = false, int limit = 50, int offset = 0,
  }) async {
    final r = await _db.rpc<dynamic>('list_requests', params: {
      'p_store_id': storeId, 'p_durum': durum, 'p_account_id': cariId,
      'p_sadece_bekleyen': sadeceBekleyen, 'p_limit': limit, 'p_offset': offset,
    });
    return (r as List).map((e) => TalepOzet.fromJson((e as Map).cast())).toList();
  }

  Future<TalepDetay> detay(String talepId) async {
    final r = await _db.rpc<dynamic>('request_detail',
        params: {'p_request_id': talepId});
    if (r == null) throw StateError('Talep bulunamadı veya yetkiniz yok');
    return TalepDetay.fromJson((r as Map).cast());
  }

  Future<List<Bildirim0>> bildirimler({bool sadeceOkunmamis = false}) async {
    final r = await _db.rpc<dynamic>('my_notifications',
        params: {'p_sadece_okunmamis': sadeceOkunmamis, 'p_limit': 30});
    return (r as List)
        .map((e) => Bildirim0.fromJson((e as Map).cast())).toList();
  }

  Future<int> bildirimleriOkundu({List<String>? idler}) async {
    final r = await _db.rpc<dynamic>('mark_notifications_read',
        params: {'p_ids': idler});
    return ((r as Map)['okunan'] as num?)?.toInt() ?? 0;
  }
}

final talepRepositoryProvider =
    Provider<TalepRepository>((ref) => TalepRepository(ref.watch(supabaseProvider)));

// ── Modeller ───────────────────────────────────────────────────────────────

class Muhatap {
  const Muhatap({required this.id, required this.tip, required this.unvan,
                 required this.storeId, this.kurumAd, this.ilce,
                 this.kendi = false});
  final String id, tip, unvan, storeId;
  final String? kurumAd, ilce;
  final bool kendi;
  bool get kurumsal => tip == 'kurum';
  String get altBilgi => [?kurumAd, ?ilce].join(' · ');
  static Muhatap fromJson(Map<String, dynamic> j) => Muhatap(
        id: j['id'] as String, tip: j['tip'] as String? ?? 'kurum',
        unvan: j['unvan'] as String? ?? '',
        storeId: j['store_id'] as String,
        kurumAd: j['kurum_ad'] as String?, ilce: j['ilce'] as String?,
        kendi: j['kendi'] as bool? ?? false,
      );
}

class AdetOnerisi {
  const AdetOnerisi({this.adet, this.kaynak = 'yok', this.etiket});
  final int? adet;
  final String kaynak;
  final String? etiket;
  bool get var_ => adet != null && adet! > 0;
  static AdetOnerisi fromJson(Map<String, dynamic> j) => AdetOnerisi(
        adet: (j['adet'] as num?)?.toInt(),
        kaynak: j['kaynak'] as String? ?? 'yok',
        etiket: j['etiket'] as String?,
      );
}

class KalemKarari {
  const KalemKarari({required this.kalemId, required this.onay, this.redNedeni});
  final String kalemId;
  final bool onay;
  final String? redNedeni;
}

class KararSonucu {
  const KararSonucu({required this.durum, this.bekleyen = 0,
                     this.onaylanan = 0, this.reddedilen = 0});
  final String durum;
  final int bekleyen, onaylanan, reddedilen;
  bool get sonuclandi => bekleyen == 0;
  static KararSonucu fromJson(Map<String, dynamic> j) => KararSonucu(
        durum: j['durum'] as String? ?? '',
        bekleyen: (j['bekleyen'] as num?)?.toInt() ?? 0,
        onaylanan: (j['onaylanan'] as num?)?.toInt() ?? 0,
        reddedilen: (j['reddedilen'] as num?)?.toInt() ?? 0,
      );
}

class TalepOzet {
  const TalepOzet({
    required this.id, required this.durum, required this.kaynak,
    required this.createdAt, required this.cariId, required this.unvan,
    required this.tip, this.kurumAd, this.acan, this.notMetni,
    this.istenenTarih, this.kalemSayisi = 0, this.bekleyen = 0,
    this.toplamAdet = 0, this.gecikmis = false,
  });

  final String id, durum, kaynak, cariId, unvan, tip;
  final DateTime createdAt;
  final String? kurumAd, acan, notMetni;
  final DateTime? istenenTarih;
  final int kalemSayisi, bekleyen, toplamAdet;
  final bool gecikmis;

  bool get acik => durum == 'gonderildi' || durum == 'incelemede';
  bool get dokunulmamis => durum == 'gonderildi';

  String get durumAdi => switch (durum) {
        'taslak' => 'Taslak',
        'gonderildi' => 'Gönderildi',
        'incelemede' => 'İncelemede',
        'karara_baglandi' => 'Karara bağlandı',
        'tamamen_reddedildi' => 'Reddedildi',
        'iptal' => 'İptal',
        _ => durum,
      };

  static TalepOzet fromJson(Map<String, dynamic> j) => TalepOzet(
        id: j['id'] as String,
        durum: j['durum'] as String? ?? '',
        kaynak: j['kaynak'] as String? ?? '',
        createdAt: DateTime.parse(j['created_at'] as String),
        cariId: j['account_id'] as String,
        unvan: j['unvan'] as String? ?? '',
        tip: j['tip'] as String? ?? 'kurum',
        kurumAd: j['kurum_ad'] as String?,
        acan: j['acan'] as String?,
        notMetni: j['not_metni'] as String?,
        istenenTarih: j['istenen_tarih'] == null
            ? null : DateTime.parse(j['istenen_tarih'] as String),
        kalemSayisi: (j['kalem_sayisi'] as num?)?.toInt() ?? 0,
        bekleyen: (j['bekleyen'] as num?)?.toInt() ?? 0,
        toplamAdet: (j['toplam_adet'] as num?)?.toInt() ?? 0,
        gecikmis: j['gecikmis'] as bool? ?? false,
      );
}

class TalepDetay {
  const TalepDetay({
    required this.id, required this.durum, required this.kaynak,
    required this.createdAt, required this.cari, required this.kurumAd,
    this.acan, this.notMetni, this.istenenTarih, this.kalemler = const [],
  });

  final String id, durum, kaynak, kurumAd;
  final DateTime createdAt;
  final TalepCari cari;
  final String? acan, notMetni;
  final DateTime? istenenTarih;
  final List<TalepKalemi> kalemler;

  bool get karaBaglanabilir =>
      durum == 'gonderildi' || durum == 'incelemede';
  int get bekleyen => kalemler.where((k) => k.bekliyor).length;
  double get onayliTutar => kalemler
      .where((k) => k.durum == 'onaylandi')
      .fold(0.0, (t, k) => t + (k.satirTutari ?? 0));

  static TalepDetay fromJson(Map<String, dynamic> j) => TalepDetay(
        id: j['id'] as String,
        durum: j['durum'] as String? ?? '',
        kaynak: j['kaynak'] as String? ?? '',
        createdAt: DateTime.parse(j['created_at'] as String),
        cari: TalepCari.fromJson(((j['cari'] as Map?) ?? {}).cast()),
        kurumAd: ((j['kurum'] as Map?) ?? {})['ad'] as String? ?? '',
        acan: j['acan'] as String?,
        notMetni: j['not_metni'] as String?,
        istenenTarih: j['istenen_tarih'] == null
            ? null : DateTime.parse(j['istenen_tarih'] as String),
        kalemler: ((j['kalemler'] as List?) ?? const [])
            .map((e) => TalepKalemi.fromJson((e as Map).cast())).toList(),
      );
}

class TalepCari {
  const TalepCari({required this.id, required this.unvan, required this.tip,
                   this.bakiye = 0, this.creditLimit = 0, this.risk = 0});
  final String id, unvan, tip;
  final double bakiye, creditLimit, risk;
  /// K11 · Limit kontrolü toplam riske bakar.
  bool get limitAsildi => creditLimit > 0 && risk > creditLimit;
  static TalepCari fromJson(Map<String, dynamic> j) => TalepCari(
        id: j['id'] as String? ?? '',
        unvan: j['unvan'] as String? ?? '',
        tip: j['tip'] as String? ?? 'kurum',
        bakiye: (j['bakiye'] as num?)?.toDouble() ?? 0,
        creditLimit: (j['credit_limit'] as num?)?.toDouble() ?? 0,
        risk: (j['risk'] as num?)?.toDouble() ?? 0,
      );
}

class TalepKalemi {
  const TalepKalemi({
    required this.id, required this.urunId, required this.ad,
    required this.adet, required this.durum,
    this.barkod, this.yayinevi, this.baskiEtiketi, this.redNedeni,
    this.satisFiyat, this.iskonto, this.iskontoKaynak, this.satirTutari,
    this.baskiUyarisi,
  });

  final String id, urunId, ad;
  final int adet;
  final String durum;
  final String? barkod, yayinevi, baskiEtiketi, redNedeni, iskontoKaynak;
  final double? satisFiyat, iskonto, satirTutari;
  final BaskiUyarisi? baskiUyarisi;

  bool get bekliyor => durum == 'beklemede';
  bool get onayli => durum == 'onaylandi';
  bool get reddedildi => durum == 'reddedildi';
  /// Fiyatı olmayan ürün siparişe dönüşemez.
  bool get fiyatsiz => satisFiyat == null;

  String get altBilgi =>
      [?yayinevi, ?baskiEtiketi, ?barkod].join(' · ');

  static TalepKalemi fromJson(Map<String, dynamic> j) => TalepKalemi(
        id: j['id'] as String,
        urunId: j['product_id'] as String,
        ad: j['ad'] as String? ?? '',
        adet: (j['adet'] as num?)?.toInt() ?? 0,
        durum: j['durum'] as String? ?? 'beklemede',
        barkod: j['barkod'] as String?,
        yayinevi: j['yayinevi'] as String?,
        baskiEtiketi: j['baski_etiketi'] as String?,
        redNedeni: j['red_nedeni'] as String?,
        satisFiyat: (j['satis_fiyat'] as num?)?.toDouble(),
        iskonto: (j['iskonto'] as num?)?.toDouble(),
        iskontoKaynak: j['iskonto_kaynak'] as String?,
        satirTutari: (j['satir_tutari'] as num?)?.toDouble(),
        baskiUyarisi: j['baski_uyarisi'] == null
            ? null : BaskiUyarisi.fromJson((j['baski_uyarisi'] as Map).cast()),
      );
}

class Bildirim0 {
  const Bildirim0({required this.id, required this.olay, required this.baslik,
                   required this.createdAt, this.govde, this.hedefTur,
                   this.hedefId, this.okundu = false});
  final String id, olay, baslik;
  final DateTime createdAt;
  final String? govde, hedefTur, hedefId;
  final bool okundu;
  static Bildirim0 fromJson(Map<String, dynamic> j) => Bildirim0(
        id: j['id'] as String, olay: j['olay'] as String? ?? '',
        baslik: j['baslik'] as String? ?? '',
        createdAt: DateTime.parse(j['created_at'] as String),
        govde: j['govde'] as String?, hedefTur: j['hedef_tur'] as String?,
        hedefId: j['hedef_id'] as String?,
        okundu: j['okundu'] as bool? ?? false,
      );
}
