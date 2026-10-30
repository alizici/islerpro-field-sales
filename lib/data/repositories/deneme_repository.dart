import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/network/supabase.dart';

/// Deneme takvimi (Faz 9).
///
/// K20 · Takvim bir VERİ KÜMESİDİR, ekran değil. Omurga **stok tarihidir**
/// (267/267 dolu); uygulama tarihi yalnızca %55 dolu ve türe bağlıdır.
/// K21 · Takvim işletmeye aittir — bir sahibin üç dükkanı varsa bir kez
/// yüklenir, üçü de görür.
class DenemeRepository {
  DenemeRepository(this._db);
  final SupabaseClient _db;

  Future<DenemeTakvimi> takvim(
    String storeId, {
    DateTime? ay,
    String eksen = 'stok',
    String? kademe,
    String? turu,
    String? publisherId,
    bool sadecePortfoy = false,
  }) async {
    final r = await _db.rpc<dynamic>('exam_calendar', params: {
      'p_store_id': storeId,
      'p_ay': _gun(ay),
      'p_eksen': eksen,
      'p_kademe': kademe,
      'p_turu': turu,
      'p_publisher_id': publisherId,
      'p_sadece_portfoy': sadecePortfoy,
    });
    return DenemeTakvimi.fromJson(((r ?? {}) as Map).cast());
  }

  Future<List<Deneme>> yaklasanlar(String storeId, {int gun = 7}) async {
    final r = await _db.rpc<dynamic>('exam_upcoming',
        params: {'p_store_id': storeId, 'p_gun': gun});
    return ((r as List?) ?? const [])
        .map((e) => Deneme.fromJson((e as Map).cast())).toList();
  }

  /// K22 · Adet önerisi dört kademeli yedek zincirle gelir; hiçbir koşulda
  /// tıkanmaz.
  Future<List<DenemeHedefi>> hedefler(String denemeId, String storeId) async {
    final r = await _db.rpc<dynamic>('exam_targets',
        params: {'p_product_id': denemeId, 'p_store_id': storeId});
    return ((r as List?) ?? const [])
        .map((e) => DenemeHedefi.fromJson((e as Map).cast())).toList();
  }

  /// "Geçen sefer" — aynı yayınevinin bir önceki denemesindeki cari ve adetler.
  Future<Map<String, int>> gecenSefer(String denemeId) async {
    final r = await _db.rpc<dynamic>('exam_last_time',
        params: {'p_product_id': denemeId});
    return {
      for (final e in ((r as List?) ?? const []))
        (e as Map)['account_id'] as String: (e['adet'] as num).toInt()
    };
  }

  Future<TopluTalepSonucu> topluTalep({
    required String denemeId,
    required List<({String cariId, int adet})> hedefler,
    DateTime? istenenTarih,
    String? notMetni,
    String? clientKey,
  }) async {
    final r = await _db.rpc<dynamic>('bulk_request_from_exam', params: {
      'p_product_id': denemeId,
      'p_items': [
        for (final h in hedefler) {'account_id': h.cariId, 'adet': h.adet}
      ],
      'p_istenen_tarih': _gun(istenenTarih),
      'p_not_metni': notMetni,
      'p_client_key': clientKey,
    });
    return TopluTalepSonucu.fromJson(((r ?? {}) as Map).cast());
  }

  // ── K22 · Sınıf mevcutları ───────────────────────────────────────────────
  Future<Mevcutlar> mevcutlar(String cariId) async {
    final r = await _db.rpc<dynamic>('get_enrollments',
        params: {'p_account_id': cariId});
    return Mevcutlar.fromJson(((r ?? {}) as Map).cast());
  }

  Future<int> mevcutYaz(
      String cariId, List<({int sinif, int ogrenciSayisi})> satirlar) async {
    final r = await _db.rpc<dynamic>('set_enrollments', params: {
      'p_account_id': cariId,
      'p_items': [
        for (final s in satirlar)
          {'sinif': s.sinif, 'ogrenci_sayisi': s.ogrenciSayisi}
      ],
    });
    return ((r as Map?)?['toplam'] as num?)?.toInt() ?? 0;
  }

  // ── Abonelik programı (C-3 · Y-8 · K47) ──────────────────────────────────
  Future<String> programAc({
    required String cariId,
    String modu = 'takvim_bagli',
    required int ogrenciSayisi,
    int? denemeAdedi,
    int? periyotGun,
    double? birimFiyat,
  }) async {
    final r = await _db.rpc<dynamic>('create_exam_program', params: {
      'p_account_id': cariId,
      'p_modu': modu,
      'p_ogrenci_sayisi': ogrenciSayisi,
      'p_deneme_adedi': denemeAdedi,
      'p_periyot_gun': periyotGun,
      'p_birim_fiyat': birimFiyat,
    });
    return ((r ?? {}) as Map)['id'] as String;
  }

  /// Ö-9 · Öğrenci sayısı değişikliği YALNIZCA teslim edilmemiş kalemlere
  /// uygulanır; teslim edilenler damgalı kalır (K28).
  Future<({int guncellenen, int degismeyen})> programGuncelle(
      String programId, {int? ogrenciSayisi, double? birimFiyat}) async {
    final r = await _db.rpc<dynamic>('update_exam_program', params: {
      'p_program_id': programId,
      'p_ogrenci_sayisi': ogrenciSayisi,
      'p_birim_fiyat': birimFiyat,
    });
    final m = ((r ?? {}) as Map).cast<String, dynamic>();
    return (guncellenen: (m['guncellenen_kalem'] as num?)?.toInt() ?? 0,
            degismeyen: (m['degismeyen_kalem'] as num?)?.toInt() ?? 0);
  }

  Future<({int dusen, int teslimEdilmis})> programIptal(
      String programId, {String? gerekce}) async {
    final r = await _db.rpc<dynamic>('cancel_exam_program',
        params: {'p_program_id': programId, 'p_gerekce': gerekce});
    final m = ((r ?? {}) as Map).cast<String, dynamic>();
    return (dusen: (m['dusen_kalem'] as num?)?.toInt() ?? 0,
            teslimEdilmis: (m['teslim_edilmis_kalem'] as num?)?.toInt() ?? 0);
  }

  Future<int> teslimPlanla(String programId,
      List<({String denemeId, DateTime? tarih, int? adet})> kalemler,
      {DateTime? baslangic}) async {
    final r = await _db.rpc<dynamic>('plan_exam_deliveries', params: {
      'p_program_id': programId,
      'p_items': [
        for (final k in kalemler)
          {
            'product_id': k.denemeId,
            if (k.tarih != null) 'tarih': _gun(k.tarih),
            if (k.adet != null) 'adet': k.adet,
          }
      ],
      'p_baslangic': _gun(baslangic),
    });
    return ((r ?? {}) as Map)['eklenen'] as int? ?? 0;
  }

  /// K47 · `teslim_edildi` bu yoldan geçmez — teslimat kaydı [teslimEt] ile
  /// üretilir, borç oradan doğar (C-3).
  Future<String> teslimDurumu(String kalemId, String durum,
      {String? not, DateTime? yeniTarih}) async {
    final r = await _db.rpc<dynamic>('set_exam_delivery_status', params: {
      'p_delivery_id': kalemId,
      'p_durum': durum,
      'p_not': not,
      'p_yeni_tarih': _gun(yeniTarih),
    });
    return ((r ?? {}) as Map)['durum'] as String? ?? durum;
  }

  Future<({String teslimatId, int adet, double? bakiye})> teslimEt(
      String kalemId, {int? adet, String? teslimAlanAd,
      String? clientKey}) async {
    final r = await _db.rpc<dynamic>('deliver_exam', params: {
      'p_delivery_id': kalemId,
      'p_adet': adet,
      'p_teslim_alan_ad': teslimAlanAd,
      'p_client_key': clientKey,
    });
    final m = ((r ?? {}) as Map).cast<String, dynamic>();
    return (teslimatId: m['shipment_id'] as String,
            adet: (m['adet'] as num?)?.toInt() ?? 0,
            bakiye: (m['bakiye'] as num?)?.toDouble());
  }

  Future<DenemeProgrami> programDetay(String programId) async {
    final r = await _db.rpc<dynamic>('exam_program_detail',
        params: {'p_program_id': programId});
    if (r == null) throw StateError('Program bulunamadı veya yetkiniz yok');
    return DenemeProgrami.fromJson((r as Map).cast());
  }

  Future<List<ProgramOzeti>> programlar(String storeId,
      {String? cariId, bool? aktif}) async {
    final r = await _db.rpc<dynamic>('list_exam_programs', params: {
      'p_store_id': storeId, 'p_account_id': cariId, 'boolean_aktif': aktif,
    });
    return ((r as List?) ?? const [])
        .map((e) => ProgramOzeti.fromJson((e as Map).cast())).toList();
  }

  Future<DonemOzeti> donemOzeti(String storeId, {String? periodId}) async {
    final r = await _db.rpc<dynamic>('exam_program_summary',
        params: {'p_store_id': storeId, 'p_period_id': periodId});
    return DonemOzeti.fromJson(((r ?? {}) as Map).cast());
  }

  static String? _gun(DateTime? t) => t == null
      ? null
      : '${t.year.toString().padLeft(4, '0')}-'
        '${t.month.toString().padLeft(2, '0')}-'
        '${t.day.toString().padLeft(2, '0')}';
}

final denemeRepositoryProvider =
    Provider<DenemeRepository>((ref) => DenemeRepository(ref.watch(supabaseProvider)));

// ── Modeller ───────────────────────────────────────────────────────────────

const denemeTuruAdi = <String, String>{
  'turkiye_geneli': 'Türkiye Geneli',
  'takvim': 'Takvim',
  'deneme_kulubu': 'Deneme Kulübü',
  'resmi_sinav': 'Resmî sınav',
};

class Deneme {
  const Deneme({required this.id, required this.ad, required this.turu,
                required this.stokTarihi, this.yayinevi, this.duzey,
                this.kademe, this.kapsam, this.sinavTipi,
                this.sinif = const [], this.uygulamaBaslangic,
                this.uygulamaBitis, this.uygulamaMetin, this.gun,
                this.fiyatli = true});
  final String id, ad, turu;
  final String? yayinevi, duzey, kademe, kapsam, sinavTipi, uygulamaMetin;
  final List<int> sinif;
  final DateTime stokTarihi;
  final DateTime? uygulamaBaslangic, uygulamaBitis;
  final int? gun;

  /// K12 · Takvim import'u ürünü açar ama FİYAT açmaz. Fiyatsız denemeden
  /// talep açılamaz — ekran bunu önceden gösterir, kullanıcı "Öner"e basıp
  /// reddedilmeyi öğrenmesin.
  final bool fiyatli;

  /// K20 · Sabit tarihli sınav KAÇIRILAMAZ; ekranda her zaman öne çıkar.
  bool get sabit => turu == 'turkiye_geneli' || turu == 'resmi_sinav';

  /// Uygulama gününü kurum seçiyorsa bu bir eksiklik değil, bir bilgidir.
  bool get uygulamaKurumBelirler => uygulamaBaslangic == null;

  String get uygulamaMetniGoster => uygulamaMetin?.isNotEmpty == true
      ? uygulamaMetin!
      : uygulamaKurumBelirler ? 'kurum belirler' : '';

  static Deneme fromJson(Map<String, dynamic> j) => Deneme(
        id: j['id'] as String,
        ad: j['ad'] as String? ?? '',
        turu: j['deneme_turu'] as String? ?? 'takvim',
        yayinevi: j['yayinevi'] as String?,
        duzey: j['duzey'] as String?,
        kademe: j['kademe'] as String?,
        kapsam: j['kapsam'] as String?,
        sinavTipi: j['sinav_tipi'] as String?,
        sinif: ((j['sinif'] as List?) ?? const [])
            .map((e) => (e as num).toInt()).toList(),
        stokTarihi: DateTime.parse(j['stok_tarihi'] as String),
        uygulamaBaslangic: j['uygulama_baslangic'] == null
            ? null : DateTime.parse(j['uygulama_baslangic'] as String),
        uygulamaBitis: j['uygulama_bitis'] == null
            ? null : DateTime.parse(j['uygulama_bitis'] as String),
        uygulamaMetin: j['uygulama_metin'] as String?,
        gun: (j['gun'] as num?)?.toInt(),
        fiyatli: j['fiyatli'] as bool? ?? true,
      );
}

class DenemeGunu {
  const DenemeGunu({required this.tarih, required this.adet,
                    this.turkiyeGeneli = 0, this.denemeler = const []});
  final DateTime tarih;
  final int adet, turkiyeGeneli;
  final List<Deneme> denemeler;

  static DenemeGunu fromJson(Map<String, dynamic> j) => DenemeGunu(
        tarih: DateTime.parse(j['tarih'] as String),
        adet: (j['adet'] as num?)?.toInt() ?? 0,
        turkiyeGeneli: (j['turkiye_geneli'] as num?)?.toInt() ?? 0,
        denemeler: ((j['denemeler'] as List?) ?? const [])
            .map((e) => Deneme.fromJson((e as Map).cast())).toList(),
      );
}

class DenemeTakvimi {
  const DenemeTakvimi({this.ay, this.eksen = 'stok', this.gunler = const [],
                       this.tarihsiz = const [], this.toplam = 0});
  final DateTime? ay;
  final String eksen;
  final List<DenemeGunu> gunler;
  /// Uygulama ekseninde tarihi olmayanlar — eksik değil, "kurum belirler".
  final List<Deneme> tarihsiz;
  final int toplam;

  bool get bos => gunler.isEmpty && tarihsiz.isEmpty;

  DenemeGunu? gun(DateTime t) {
    for (final g in gunler) {
      if (g.tarih.year == t.year && g.tarih.month == t.month &&
          g.tarih.day == t.day) {
        return g;
      }
    }
    return null;
  }

  static DenemeTakvimi fromJson(Map<String, dynamic> j) => DenemeTakvimi(
        ay: j['ay'] == null ? null : DateTime.parse(j['ay'] as String),
        eksen: j['eksen'] as String? ?? 'stok',
        gunler: ((j['gunler'] as List?) ?? const [])
            .map((e) => DenemeGunu.fromJson((e as Map).cast())).toList(),
        tarihsiz: ((j['tarihsiz'] as List?) ?? const [])
            .map((e) => Deneme.fromJson((e as Map).cast())).toList(),
        toplam: (j['toplam'] as num?)?.toInt() ?? 0,
      );
}

class DenemeHedefi {
  const DenemeHedefi({required this.cariId, required this.unvan,
                      required this.tip, this.kurumAd, this.bakiye = 0,
                      this.mevcut, this.oneri = 0, this.oneriKaynak,
                      this.oneriEtiket});
  final String cariId, unvan, tip;
  final String? kurumAd, oneriKaynak, oneriEtiket;
  final double bakiye;
  /// K22 · Kurumun bildirdiği sınıf mevcudu. Null = hiç bildirilmemiş.
  final int? mevcut;
  final int oneri;

  static DenemeHedefi fromJson(Map<String, dynamic> j) {
    final o = (j['oneri'] as Map?)?.cast<String, dynamic>() ?? const {};
    return DenemeHedefi(
      cariId: j['account_id'] as String,
      unvan: j['unvan'] as String? ?? '',
      tip: j['tip'] as String? ?? 'kurum',
      kurumAd: j['kurum_ad'] as String?,
      bakiye: (j['bakiye'] as num?)?.toDouble() ?? 0,
      mevcut: (j['mevcut'] as num?)?.toInt(),
      oneri: (o['adet'] as num?)?.toInt() ?? 0,
      oneriKaynak: o['kaynak'] as String?,
      oneriEtiket: o['etiket'] as String?,
    );
  }
}

class TopluTalepSonucu {
  const TopluTalepSonucu({this.acilan = 0, this.hatali = 0,
                          this.toplamAdet = 0, this.deneme,
                          this.sonuclar = const []});
  final int acilan, hatali, toplamAdet;
  final String? deneme;
  final List<TopluTalepSatiri> sonuclar;

  static TopluTalepSonucu fromJson(Map<String, dynamic> j) => TopluTalepSonucu(
        acilan: (j['acilan'] as num?)?.toInt() ?? 0,
        hatali: (j['hatali'] as num?)?.toInt() ?? 0,
        toplamAdet: (j['toplam_adet'] as num?)?.toInt() ?? 0,
        deneme: j['deneme'] as String?,
        sonuclar: ((j['sonuclar'] as List?) ?? const [])
            .map((e) => TopluTalepSatiri.fromJson((e as Map).cast())).toList(),
      );
}

class TopluTalepSatiri {
  const TopluTalepSatiri({required this.cariId, required this.durum,
                          this.talepId, this.hata});
  final String cariId, durum;
  final String? talepId, hata;
  bool get basarili => durum == 'ok';

  static TopluTalepSatiri fromJson(Map<String, dynamic> j) => TopluTalepSatiri(
        cariId: j['account_id'] as String? ?? '',
        durum: j['durum'] as String? ?? 'hata',
        talepId: j['request_id'] as String?,
        hata: j['hata'] as String?,
      );
}

class Mevcutlar {
  const Mevcutlar({this.siniflar = const [], this.toplam = 0});
  final List<SinifMevcudu> siniflar;
  final int toplam;
  bool get bos => siniflar.isEmpty;

  static Mevcutlar fromJson(Map<String, dynamic> j) => Mevcutlar(
        siniflar: ((j['siniflar'] as List?) ?? const [])
            .map((e) => SinifMevcudu.fromJson((e as Map).cast())).toList(),
        toplam: (j['toplam'] as num?)?.toInt() ?? 0,
      );
}

class SinifMevcudu {
  const SinifMevcudu({required this.sinif, required this.ogrenciSayisi,
                      this.bildiren, this.tarih});
  final int sinif, ogrenciSayisi;
  final String? bildiren;
  final DateTime? tarih;

  static SinifMevcudu fromJson(Map<String, dynamic> j) => SinifMevcudu(
        sinif: (j['sinif'] as num).toInt(),
        ogrenciSayisi: (j['ogrenci_sayisi'] as num?)?.toInt() ?? 0,
        bildiren: j['bildiren'] as String?,
        tarih: j['tarih'] == null
            ? null : DateTime.parse(j['tarih'] as String).toLocal(),
      );
}

// ── Abonelik programı (C-3 · K47) ──────────────────────────────────────────

const teslimDurumAdi = <String, String>{
  'planlandi': 'Planlandı',
  'hazirlaniyor': 'Hazırlanıyor',
  'teslim_edildi': 'Teslim edildi',
  'uygulandi': 'Uygulandı',
  'kapandi': 'Kapandı',
  'ertelendi': 'Ertelendi',
  'iptal': 'İptal',
};

/// Sunucudaki `exam_transition_ok` ile AYNI tablo; e2e ikisini yan yana
/// koyup karşılaştırıyor. `teslim_edildi` listede YOK — o durum elle
/// yazılamaz, teslimat kaydından geçer (C-3).
const teslimGecisleri = <String, List<String>>{
  'planlandi': ['hazirlaniyor', 'ertelendi', 'iptal'],
  'ertelendi': ['planlandi', 'hazirlaniyor', 'iptal'],
  'hazirlaniyor': ['ertelendi', 'iptal', 'planlandi'],
  'teslim_edildi': ['uygulandi', 'kapandi'],
  'uygulandi': ['kapandi'],
  'kapandi': [],
  'iptal': [],
};

class TeslimKalemi {
  const TeslimKalemi({required this.id, required this.denemeId,
                      required this.ad, required this.tarih,
                      required this.adet, required this.durum,
                      this.yayinevi, this.denemeTuru, this.oncekiTarih,
                      this.notMetni, this.uygulandiAt, this.teslimatId,
                      this.odemeDurumu, this.tutar});
  final String id, denemeId, ad, durum;
  final String? yayinevi, denemeTuru, notMetni, teslimatId, odemeDurumu;
  final DateTime tarih;
  final DateTime? oncekiTarih, uygulandiAt;
  final int adet;
  final double? tutar;

  bool get teslimEdildi =>
      durum == 'teslim_edildi' || durum == 'uygulandi' || durum == 'kapandi';
  bool get acik =>
      durum == 'planlandi' || durum == 'ertelendi' || durum == 'hazirlaniyor';
  List<String> get gidilebilir => teslimGecisleri[durum] ?? const [];

  static TeslimKalemi fromJson(Map<String, dynamic> j) => TeslimKalemi(
        id: j['id'] as String,
        denemeId: j['product_id'] as String,
        ad: j['ad'] as String? ?? '',
        yayinevi: j['yayinevi'] as String?,
        denemeTuru: j['deneme_turu'] as String?,
        tarih: DateTime.parse(j['planlanan_tarih'] as String),
        oncekiTarih: j['onceki_tarih'] == null
            ? null : DateTime.parse(j['onceki_tarih'] as String),
        adet: (j['adet'] as num?)?.toInt() ?? 0,
        durum: j['durum'] as String? ?? 'planlandi',
        notMetni: j['ertelendi_notu'] as String?,
        uygulandiAt: j['uygulandi_at'] == null
            ? null : DateTime.parse(j['uygulandi_at'] as String).toLocal(),
        teslimatId: j['shipment_id'] as String?,
        odemeDurumu: j['odeme_durumu'] as String?,
        tutar: (j['tutar'] as num?)?.toDouble(),
      );
}

class ProgramSayilari {
  const ProgramSayilari({this.planlanan = 0, this.teslimEdilen = 0,
                         this.uygulanan = 0, this.ertelenen = 0,
                         this.iptal = 0, this.ciro = 0});
  final int planlanan, teslimEdilen, uygulanan, ertelenen, iptal;
  final double ciro;

  static ProgramSayilari fromJson(Map<String, dynamic> j) => ProgramSayilari(
        planlanan: (j['planlanan'] as num?)?.toInt() ?? 0,
        teslimEdilen: (j['teslim_edilen'] as num?)?.toInt() ?? 0,
        uygulanan: (j['uygulanan'] as num?)?.toInt() ?? 0,
        ertelenen: (j['ertelenen'] as num?)?.toInt() ?? 0,
        iptal: (j['iptal'] as num?)?.toInt() ?? 0,
        ciro: (j['ciro'] as num?)?.toDouble() ?? 0,
      );
}

class DenemeProgrami {
  const DenemeProgrami({required this.id, required this.cariId,
                        required this.unvan, required this.modu,
                        this.kurumAd, this.aktif = true,
                        this.ogrenciSayisi = 0, this.denemeAdedi,
                        this.periyotGun, this.birimFiyat, this.donem,
                        this.kalemler = const [],
                        this.ozet = const ProgramSayilari()});
  final String id, cariId, unvan, modu;
  final String? kurumAd, donem;
  final bool aktif;
  final int ogrenciSayisi;
  final int? denemeAdedi, periyotGun;
  final double? birimFiyat;
  final List<TeslimKalemi> kalemler;
  final ProgramSayilari ozet;

  bool get takvimBagli => modu == 'takvim_bagli';

  static DenemeProgrami fromJson(Map<String, dynamic> j) => DenemeProgrami(
        id: j['id'] as String,
        cariId: j['account_id'] as String,
        unvan: j['unvan'] as String? ?? '',
        kurumAd: j['kurum_ad'] as String?,
        modu: j['modu'] as String? ?? 'takvim_bagli',
        aktif: j['aktif'] as bool? ?? true,
        ogrenciSayisi: (j['ogrenci_sayisi'] as num?)?.toInt() ?? 0,
        denemeAdedi: (j['deneme_adedi'] as num?)?.toInt(),
        periyotGun: (j['periyot_gun'] as num?)?.toInt(),
        birimFiyat: (j['birim_fiyat'] as num?)?.toDouble(),
        donem: j['donem'] as String?,
        kalemler: ((j['kalemler'] as List?) ?? const [])
            .map((e) => TeslimKalemi.fromJson((e as Map).cast())).toList(),
        ozet: ProgramSayilari.fromJson(
            ((j['ozet'] as Map?) ?? {}).cast()),
      );
}

class ProgramOzeti {
  const ProgramOzeti({required this.id, required this.cariId,
                      required this.unvan, required this.modu,
                      this.kurumAd, this.aktif = true, this.ogrenciSayisi = 0,
                      this.denemeAdedi, this.kalem = 0, this.teslimEdilen = 0,
                      this.sonrakiTeslim});
  final String id, cariId, unvan, modu;
  final String? kurumAd;
  final bool aktif;
  final int ogrenciSayisi, kalem, teslimEdilen;
  final int? denemeAdedi;
  final DateTime? sonrakiTeslim;

  static ProgramOzeti fromJson(Map<String, dynamic> j) => ProgramOzeti(
        id: j['id'] as String,
        cariId: j['account_id'] as String,
        unvan: j['unvan'] as String? ?? '',
        kurumAd: j['kurum_ad'] as String?,
        modu: j['modu'] as String? ?? 'takvim_bagli',
        aktif: j['aktif'] as bool? ?? true,
        ogrenciSayisi: (j['ogrenci_sayisi'] as num?)?.toInt() ?? 0,
        denemeAdedi: (j['deneme_adedi'] as num?)?.toInt(),
        kalem: (j['kalem'] as num?)?.toInt() ?? 0,
        teslimEdilen: (j['teslim_edilen'] as num?)?.toInt() ?? 0,
        sonrakiTeslim: j['sonraki_teslim'] == null
            ? null : DateTime.parse(j['sonraki_teslim'] as String),
      );
}

/// Dönem sonu özeti: **anlaşılan ile gerçekleşen yan yana**. Planlanan ile
/// uygulanan arasındaki fark, bir sonraki dönemin anlaşmasını belirler.
class DonemOzeti {
  const DonemOzeti({this.donem, this.program = 0, this.aktifProgram = 0,
                    this.ogrenci = 0, this.planlananKalem = 0,
                    this.teslimEdilen = 0, this.uygulanan = 0,
                    this.ertelenen = 0, this.ciro = 0,
                    this.programlar = const []});
  final String? donem;
  final int program, aktifProgram, ogrenci, planlananKalem, teslimEdilen,
      uygulanan, ertelenen;
  final double ciro;
  final List<ProgramSatiri> programlar;

  bool get bos => program == 0;

  static DonemOzeti fromJson(Map<String, dynamic> j) => DonemOzeti(
        donem: j['donem'] as String?,
        program: (j['program'] as num?)?.toInt() ?? 0,
        aktifProgram: (j['aktif_program'] as num?)?.toInt() ?? 0,
        ogrenci: (j['ogrenci'] as num?)?.toInt() ?? 0,
        planlananKalem: (j['planlanan_kalem'] as num?)?.toInt() ?? 0,
        teslimEdilen: (j['teslim_edilen'] as num?)?.toInt() ?? 0,
        uygulanan: (j['uygulanan'] as num?)?.toInt() ?? 0,
        ertelenen: (j['ertelenen'] as num?)?.toInt() ?? 0,
        ciro: (j['ciro'] as num?)?.toDouble() ?? 0,
        programlar: ((j['programlar'] as List?) ?? const [])
            .map((e) => ProgramSatiri.fromJson((e as Map).cast())).toList(),
      );
}

class ProgramSatiri {
  const ProgramSatiri({required this.id, required this.unvan,
                       this.kurumAd, this.aktif = true, this.ogrenciSayisi = 0,
                       this.planlanan = 0, this.uygulanan = 0, this.ciro = 0});
  final String id, unvan;
  final String? kurumAd;
  final bool aktif;
  final int ogrenciSayisi, planlanan, uygulanan;
  final double ciro;

  static ProgramSatiri fromJson(Map<String, dynamic> j) => ProgramSatiri(
        id: j['id'] as String,
        unvan: j['unvan'] as String? ?? '',
        kurumAd: j['kurum_ad'] as String?,
        aktif: j['aktif'] as bool? ?? true,
        ogrenciSayisi: (j['ogrenci_sayisi'] as num?)?.toInt() ?? 0,
        planlanan: (j['planlanan'] as num?)?.toInt() ?? 0,
        uygulanan: (j['uygulanan'] as num?)?.toInt() ?? 0,
        ciro: (j['ciro'] as num?)?.toDouble() ?? 0,
      );
}
