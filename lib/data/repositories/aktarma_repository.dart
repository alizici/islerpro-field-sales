import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/network/supabase.dart';

/// K49 · Toplu aktarma. Tek ekran altı veri türünü karşılar.
///
/// 24.632 satır tek istekte gönderilemez; [_parcaBoyu]'luk parçalar hâlinde
/// aynı batch'e yollanır. Önizleme ile uygulama AYNI sunucu kodunu çalıştırır
/// (`kuruKosu`), böylece önizlemenin doğru olduğu garanti edilir.
class AktarmaRepository {
  AktarmaRepository(this._db);
  final SupabaseClient _db;

  static const parcaBoyu = 400;

  Future<String> batchAc({
    required String storeId,
    required String tur,
    String? dosyaAdi,
    int satirSayisi = 0,
  }) async {
    final r = await _db.rpc<dynamic>('create_import_batch', params: {
      'p_store_id': storeId, 'p_tur': tur,
      'p_dosya_adi': dosyaAdi, 'p_satir_sayisi': satirSayisi,
    });
    return r as String;
  }

  /// Deneme takvimi ayrı bir RPC'ye gider: `import_chunk` zaten dört dallı ve
  /// 250 satır; beşinci dalı içine yazmak dosyayı okunmaz yapardı. Sözleşme
  /// aynı — önizleme ve uygulama tek kod, `kuruKosu` yalnızca yazmayı kapatır.
  Future<AktarmaOzet> parca({
    required String batchId,
    required List<Map<String, dynamic>> satirlar,
    String politika = 'guncelle',
    bool kuruKosu = false,
    String? tur,
  }) async {
    if (tur == 'deneme_takvimi') {
      final r = await _db.rpc<dynamic>('import_chunk_deneme', params: {
        'p_batch_id': batchId, 'p_satirlar': satirlar,
        'p_kuru_kosu': kuruKosu,
      });
      return AktarmaOzet.fromJson((r as Map).cast());
    }
    final r = await _db.rpc<dynamic>('import_chunk', params: {
      'p_batch_id': batchId, 'p_rows': satirlar,
      'p_politika': politika, 'p_kuru_kosu': kuruKosu,
    });
    return AktarmaOzet.fromJson((r as Map).cast());
  }

  /// Tüm satırları parçalayarak gönderir. [ilerleme] işlenen satır sayısını
  /// bildirir — 24 bin satırda kullanıcı donmuş ekrana bakmasın.
  Future<AktarmaOzet> tumunuGonder({
    required String batchId,
    required List<Map<String, dynamic>> satirlar,
    String politika = 'guncelle',
    bool kuruKosu = false,
    String? tur,
    void Function(int islenen, int toplam)? ilerleme,
  }) async {
    var toplam = const AktarmaOzet();
    for (var i = 0; i < satirlar.length; i += parcaBoyu) {
      final son = (i + parcaBoyu).clamp(0, satirlar.length);
      final o = await parca(
        batchId: batchId,
        satirlar: satirlar.sublist(i, son),
        politika: politika,
        kuruKosu: kuruKosu,
        tur: tur,
      );
      toplam = toplam + o;
      ilerleme?.call(son, satirlar.length);
    }
    return toplam;
  }

  Future<AktarmaOzet> batchKapat(String batchId) async {
    final r = await _db.rpc<dynamic>('finish_import_batch',
        params: {'p_batch_id': batchId});
    final m = (r as Map).cast<String, dynamic>();
    return AktarmaOzet(
      yeni: (m['eklenen'] as num?)?.toInt() ?? 0,
      guncelleme: (m['guncellenen'] as num?)?.toInt() ?? 0,
      hatali: (m['hatali'] as num?)?.toInt() ?? 0,
    );
  }

  /// K49 · 400 satırlık yanlış yükleme elle düzeltilemez — tek tıkla geri alınır.
  Future<({int silinen, int geriAlinan})> geriAl(String batchId) async {
    final r = await _db.rpc<dynamic>('undo_import',
        params: {'p_batch_id': batchId});
    final m = (r as Map).cast<String, dynamic>();
    return (silinen: (m['silinen'] as num?)?.toInt() ?? 0,
            geriAlinan: (m['geri_alinan'] as num?)?.toInt() ?? 0);
  }

  Future<List<AktarmaKaydi>> gecmis({String? storeId, int limit = 25}) async {
    final r = await _db.rpc<dynamic>('list_import_batches',
        params: {'p_store_id': storeId, 'p_limit': limit});
    return (r as List)
        .map((e) => AktarmaKaydi.fromJson((e as Map).cast())).toList();
  }

  Future<List<({int satir, String hata})>> hatalar(String batchId) async {
    final r = await _db.rpc<dynamic>('import_batch_errors',
        params: {'p_batch_id': batchId});
    return (r as List).map((e) {
      final m = (e as Map).cast<String, dynamic>();
      return (satir: (m['satir'] as num?)?.toInt() ?? 0,
              hata: m['hata'] as String? ?? '');
    }).toList();
  }

  Future<void> sablonKaydet(String tur, String ad, Map<String, String> eslesme) =>
      _db.rpc<dynamic>('save_import_template',
          params: {'p_tur': tur, 'p_ad': ad, 'p_eslesme': eslesme});

  Future<List<AktarmaSablonu>> sablonlar({String? tur}) async {
    final r = await _db.rpc<dynamic>('list_import_templates',
        params: {'p_tur': tur});
    return (r as List)
        .map((e) => AktarmaSablonu.fromJson((e as Map).cast())).toList();
  }
}

final aktarmaRepositoryProvider = Provider<AktarmaRepository>(
    (ref) => AktarmaRepository(ref.watch(supabaseProvider)));

// ── Modeller ───────────────────────────────────────────────────────────────

class AktarmaOzet {
  const AktarmaOzet({this.yeni = 0, this.guncelleme = 0,
                     this.atlanan = 0, this.hatali = 0,
                     this.hatalar = const []});
  final int yeni, guncelleme, atlanan, hatali;
  final List<SatirHatasi> hatalar;

  int get toplam => yeni + guncelleme + atlanan + hatali;
  bool get temiz => hatali == 0;

  AktarmaOzet operator +(AktarmaOzet o) => AktarmaOzet(
        yeni: yeni + o.yeni,
        guncelleme: guncelleme + o.guncelleme,
        atlanan: atlanan + o.atlanan,
        hatali: hatali + o.hatali,
        // Hata listesi ekranda gösterilecek; ilk 200 yeter, gerisi rapora gider.
        hatalar: [...hatalar, ...o.hatalar].take(200).toList(),
      );

  /// "412 satır: 340 yeni · 68 güncelleme · 4 hatalı"
  String get ozet => [
        '$toplam satır',
        if (yeni > 0) '$yeni yeni',
        if (guncelleme > 0) '$guncelleme güncelleme',
        if (atlanan > 0) '$atlanan atlanan',
        if (hatali > 0) '$hatali hatalı',
      ].join(' · ');

  static AktarmaOzet fromJson(Map<String, dynamic> j) => AktarmaOzet(
        yeni: (j['yeni'] as num?)?.toInt() ?? 0,
        guncelleme: (j['guncelleme'] as num?)?.toInt() ?? 0,
        atlanan: (j['atlanan'] as num?)?.toInt() ?? 0,
        hatali: (j['hatali'] as num?)?.toInt() ?? 0,
        hatalar: ((j['hatalar'] as List?) ?? const [])
            .map((e) => SatirHatasi.fromJson((e as Map).cast())).toList(),
      );
}

class SatirHatasi {
  const SatirHatasi({required this.satir, required this.sebep, this.deger = ''});
  final int satir;
  final String sebep, deger;
  static SatirHatasi fromJson(Map<String, dynamic> j) => SatirHatasi(
        satir: (j['satir'] as num?)?.toInt() ?? 0,
        sebep: j['sebep'] as String? ?? '',
        deger: j['deger'] as String? ?? '',
      );
}

class AktarmaKaydi {
  const AktarmaKaydi({required this.id, required this.tur, required this.durum,
                      required this.createdAt, this.dosyaAdi, this.yapan,
                      this.eklenen = 0, this.guncellenen = 0, this.hatali = 0});
  final String id, tur, durum;
  final DateTime createdAt;
  final String? dosyaAdi, yapan;
  final int eklenen, guncellenen, hatali;

  bool get geriAlinabilir => durum == 'onaylandi';
  bool get geriAlindi => durum == 'geri_alindi';

  String get turAdi => switch (tur) {
        'urun' => 'Ürün',
        'fiyat_iskonto' => 'Fiyat & iskonto',
        'stok' => 'Stok',
        'kurum' => 'Kurum',
        'deneme_takvimi' => 'Deneme takvimi',
        'acilis_bakiyesi' => 'Açılış bakiyesi',
        _ => tur,
      };

  static AktarmaKaydi fromJson(Map<String, dynamic> j) => AktarmaKaydi(
        id: j['id'] as String,
        tur: j['tur'] as String? ?? '',
        durum: j['durum'] as String? ?? '',
        createdAt: DateTime.parse(j['created_at'] as String),
        dosyaAdi: j['dosya_adi'] as String?,
        yapan: j['yapan'] as String?,
        eklenen: (j['eklenen'] as num?)?.toInt() ?? 0,
        guncellenen: (j['guncellenen'] as num?)?.toInt() ?? 0,
        hatali: (j['hatali'] as num?)?.toInt() ?? 0,
      );
}

class AktarmaSablonu {
  const AktarmaSablonu({required this.id, required this.tur, required this.ad,
                        required this.eslesme});
  final String id, tur, ad;
  final Map<String, String> eslesme;
  static AktarmaSablonu fromJson(Map<String, dynamic> j) => AktarmaSablonu(
        id: j['id'] as String, tur: j['tur'] as String? ?? '',
        ad: j['ad'] as String? ?? '',
        eslesme: ((j['eslesme'] as Map?) ?? {})
            .map((k, v) => MapEntry(k as String, v as String)),
      );
}
