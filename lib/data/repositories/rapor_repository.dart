import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/network/supabase.dart';

/// K50 · Rapor motoru istemcisi.
///
/// Burada rapor BAŞINA metot yoktur ve olmamalı: motorun tamamı `report_run`
/// üzerinden çalışır, rapor eklemek sunucuda katalog satırı yazmaktır. Yeni
/// rapor için bu dosyanın değişmesi gerekiyorsa motor bozulmuş demektir.
class RaporRepository {
  RaporRepository(this._db);
  final SupabaseClient _db;

  Future<List<RaporTanimi>> katalog() async {
    final r = await _db.rpc<dynamic>('report_catalog');
    return (r as List)
        .map((e) => RaporTanimi.fromJson((e as Map).cast()))
        .toList();
  }

  /// [kirilim] boşsa raporun varsayılanı kullanılır.
  ///
  /// Kapalı dönem seçiliyse `report_run_cached` hazır özeti okur (K8 · K50
  /// §4.2): kapalı dönemde veri değişmez, aynı rapor iki kez hesaplanmaz.
  Future<RaporSonucu> calistir({
    required String kod,
    required String storeId,
    List<String> kirilim = const [],
    Map<String, dynamic> filtreler = const {},
    String? sirala,
    bool artan = false,
    int limit = 100,
    int offset = 0,
  }) async {
    final r = await _db.rpc<dynamic>('report_run_cached', params: {
      'p_kod': kod,
      'p_store_id': storeId,
      'p_kirilim': kirilim.isEmpty ? null : kirilim,
      'p_filtreler': filtreler,
      'p_sirala': sirala,
      'p_artan': artan,
      'p_limit': limit,
      'p_offset': offset,
    });
    return RaporSonucu.fromJson((r as Map).cast());
  }

  Future<List<KayitliRapor>> kayitlilar(String storeId) async {
    final r = await _db.rpc<dynamic>('saved_reports_list',
        params: {'p_store_id': storeId});
    return (r as List)
        .map((e) => KayitliRapor.fromJson((e as Map).cast()))
        .toList();
  }

  Future<String> kaydet({
    required String ad,
    required String kod,
    required String storeId,
    List<String> kirilim = const [],
    Map<String, dynamic> filtreler = const {},
    List<String> sutunlar = const [],
    String paylasim = 'kisisel',
    String? id,
  }) async {
    final r = await _db.rpc<dynamic>('save_report', params: {
      'p_ad': ad, 'p_kod': kod, 'p_store_id': storeId,
      'p_kirilim': kirilim, 'p_filtreler': filtreler,
      'p_sutunlar': sutunlar, 'p_paylasim': paylasim, 'p_id': id,
    });
    return r as String;
  }

  Future<void> sil(String id) =>
      _db.rpc<dynamic>('delete_saved_report', params: {'p_id': id});
}

// ── Modeller ───────────────────────────────────────────────────────────────

class RaporTanimi {
  const RaporTanimi({
    required this.kod, required this.ad, required this.grup,
    required this.kaynak, this.aciklama,
    this.boyutlar = const [], this.varsayilanKirilim = const [],
    this.olculer = const [], this.suzgecler = const [],
  });

  final String kod, ad, grup, kaynak;
  final String? aciklama;
  final List<RaporBoyutu> boyutlar;
  final List<String> varsayilanKirilim;
  final List<RaporOlcusu> olculer;
  final List<String> suzgecler;

  bool destekler(String suzgec) => suzgecler.contains(suzgec);

  static const grupAdlari = {
    'cari': 'Cari ve tahsilat',
    'satis': 'Satış ve kârlılık',
    'saha': 'Saha',
    'deneme': 'Deneme',
    'katalog': 'Katalog ve stok',
  };

  static RaporTanimi fromJson(Map<String, dynamic> j) => RaporTanimi(
        kod: j['kod'] as String,
        ad: j['ad'] as String,
        grup: j['grup'] as String? ?? 'cari',
        kaynak: j['kaynak'] as String? ?? '',
        aciklama: j['aciklama'] as String?,
        boyutlar: ((j['boyutlar'] as List?) ?? const [])
            .map((e) => RaporBoyutu.fromJson((e as Map).cast()))
            .toList(),
        varsayilanKirilim: ((j['varsayilan_kirilim'] as List?) ?? const [])
            .cast<String>(),
        olculer: ((j['olculer'] as List?) ?? const [])
            .map((e) => RaporOlcusu.fromJson((e as Map).cast()))
            .toList(),
        suzgecler: ((j['suzgecler'] as List?) ?? const []).cast<String>(),
      );
}

class RaporBoyutu {
  const RaporBoyutu({required this.anahtar, required this.ad});
  final String anahtar, ad;
  static RaporBoyutu fromJson(Map<String, dynamic> j) =>
      RaporBoyutu(anahtar: j['anahtar'] as String, ad: j['ad'] as String);
}

class RaporOlcusu {
  const RaporOlcusu({required this.anahtar, required this.ad,
                     this.tip = 'sayi', this.mali = false});
  final String anahtar, ad, tip;
  /// K7 · Mali ölçü kurum kırılımında toplanamaz.
  final bool mali;
  static RaporOlcusu fromJson(Map<String, dynamic> j) => RaporOlcusu(
        anahtar: j['anahtar'] as String, ad: j['ad'] as String,
        tip: j['tip'] as String? ?? 'sayi',
        mali: j['mali'] as bool? ?? false,
      );
}

class RaporSutunu {
  const RaporSutunu({required this.anahtar, required this.ad,
                     required this.tip, required this.kirilim});
  final String anahtar, ad, tip;
  /// Kırılım sütunu mu, ölçü sütunu mu — hizalama ve dışa aktarma buna bakar.
  final bool kirilim;
  bool get sayisal => !kirilim;
  static RaporSutunu fromJson(Map<String, dynamic> j) => RaporSutunu(
        anahtar: j['anahtar'] as String, ad: j['ad'] as String,
        tip: j['tip'] as String? ?? 'metin',
        kirilim: j['kirilim'] as bool? ?? false,
      );
}

class RaporSonucu {
  const RaporSonucu({
    required this.kod, required this.ad, this.aciklama,
    this.kirilim = const [], this.sutunlar = const [],
    this.satirlar = const [], this.toplam = const {},
    this.boyutlar = const [], this.suzgecler = const [],
    this.uyarilar = const [], this.kirilimSayisi = 0,
    this.sirala, this.artan = false, this.onbellekten = false,
    this.uretildiAt,
  });

  final String kod, ad;
  final String? aciklama;
  final List<String> kirilim;
  final List<RaporSutunu> sutunlar;
  final List<Map<String, dynamic>> satirlar;
  final Map<String, dynamic> toplam;
  final List<RaporBoyutu> boyutlar;
  final List<String> suzgecler;
  /// K7 gibi kuralların devreye girdiğini SÖYLEYEN metinler. Sessizce
  /// düzeltmek, kullanıcıya yanlış rapora baktığını düşündürür.
  final List<String> uyarilar;
  final int kirilimSayisi;
  final String? sirala;
  final bool artan;
  /// K8 · Kapalı dönem özeti hazır sonuçtan okundu.
  final bool onbellekten;
  final DateTime? uretildiAt;

  bool get bos => satirlar.isEmpty;
  /// Sayfa dışında kalan kırılım var mı — "toplam sayfanın toplamı değildir".
  bool get eksikSayfa => kirilimSayisi > satirlar.length;

  static RaporSonucu fromJson(Map<String, dynamic> j) => RaporSonucu(
        kod: j['kod'] as String? ?? '',
        ad: j['ad'] as String? ?? '',
        aciklama: j['aciklama'] as String?,
        kirilim: ((j['kirilim'] as List?) ?? const []).cast<String>(),
        sutunlar: ((j['sutunlar'] as List?) ?? const [])
            .map((e) => RaporSutunu.fromJson((e as Map).cast()))
            .toList(),
        satirlar: ((j['satirlar'] as List?) ?? const [])
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList(),
        toplam: ((j['toplam'] as Map?) ?? const {}).cast<String, dynamic>(),
        boyutlar: ((j['boyutlar'] as List?) ?? const [])
            .map((e) => RaporBoyutu.fromJson((e as Map).cast()))
            .toList(),
        suzgecler: ((j['suzgecler'] as List?) ?? const []).cast<String>(),
        uyarilar: ((j['uyarilar'] as List?) ?? const []).cast<String>(),
        kirilimSayisi: (j['kirilim_sayisi'] as num?)?.toInt() ?? 0,
        sirala: j['sirala'] as String?,
        artan: j['artan'] as bool? ?? false,
        onbellekten: j['kaynak_tipi'] == 'kapali_donem_ozeti',
        uretildiAt: DateTime.tryParse(j['uretildi_at'] as String? ?? ''),
      );
}

class KayitliRapor {
  const KayitliRapor({
    required this.id, required this.ad, required this.kod,
    this.raporAd, this.kirilim = const [], this.filtreler = const {},
    this.paylasim = 'kisisel', this.benim = true, this.olusturan,
  });

  final String id, ad, kod;
  final String? raporAd, olusturan;
  final List<String> kirilim;
  final Map<String, dynamic> filtreler;
  final String paylasim;
  /// Başkasının kaydı OKUNUR, düzenlenemez.
  final bool benim;

  bool get paylasimli => paylasim == 'dukkan';

  static KayitliRapor fromJson(Map<String, dynamic> j) => KayitliRapor(
        id: j['id'] as String,
        ad: j['ad'] as String? ?? '',
        kod: j['kod'] as String? ?? '',
        raporAd: j['rapor_ad'] as String?,
        kirilim: ((j['kirilim'] as List?) ?? const []).cast<String>(),
        filtreler: ((j['filtreler'] as Map?) ?? const {})
            .cast<String, dynamic>(),
        paylasim: j['paylasim'] as String? ?? 'kisisel',
        benim: j['benim'] as bool? ?? false,
        olusturan: j['olusturan'] as String?,
      );
}

final raporRepositoryProvider = Provider<RaporRepository>(
    (ref) => RaporRepository(ref.watch(supabaseProvider)));
