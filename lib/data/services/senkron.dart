import 'package:drift/drift.dart' show InsertMode, Value;

import '../local/yerel_db.dart';
import '../repositories/senkron_repository.dart';
import 'cihaz.dart';

/// K43 · Senkron akışı.
///
/// **Sıra bilinçli olarak "önce it, sonra çek".** Sözleşme metni (docs/01
/// §4.12) tersini yazıyordu; uygulamada yanlış çıktı: önce referans çekilirse,
/// az önce girilen tahsilat sunucuya gitmeden bakiyeler indiriliyor ve
/// pazarlamacı kendi girdiği ödemeyi bakiyede GÖREMİYOR. İtme önce yapılınca
/// çekilen veri kendi yazmalarımızı da içeriyor. Tersinin bir üstünlüğü yok:
/// itme başarısız olsa da çekme adımı yine çalışıyor.
class SenkronServisi {
  SenkronServisi({required this.db, required this.repo, required this.storeId});

  final YerelDb db;
  final SenkronRepository repo;
  final String storeId;

  static const _sonReferans = 'son_referans';
  static const _katalogImlec = 'katalog_imlec';
  static const _katalogTarih = 'katalog_tarih';
  static const _yigin = 200;

  Future<SenkronRaporu> calistir({bool katalog = true}) async {
    final clientId = await CihazKimligi(db).id();

    // 1 · Cihaz kaydı. İptal edilmişse yerel veri SİLİNİR (K42) ve senkron
    //     burada biter — iptal edilmiş cihazın yazması kabul edilmiyor.
    final durum = await repo.cihazKaydet(
        clientId: clientId, ad: CihazKimligi.ad(),
        platform: CihazKimligi.platform());
    if (durum.silinsin) {
      await db.herSeyiSil();
      await repo.silmeOnayla(clientId);
    }
    if (durum.iptal) return const SenkronRaporu(cihazIptal: true);

    // 2 · Kuyruğu it
    //
    // Kuyruk BİR KEZ okunur ve yerelde dilimlenir. "Oku → gönder → tekrar oku"
    // döngüsü, hata alan satırlar kuyrukta kaldığı için aynı satırları aynı
    // koşuda defalarca gönderiyordu.
    var yuklenen = 0, hatali = 0, tekrar = 0;
    final bekleyen = await db.bekleyenler(limit: 2000);
    for (var i = 0; i < bekleyen.length; i += _yigin) {
      final dilim = bekleyen.sublist(
          i, i + _yigin > bekleyen.length ? bekleyen.length : i + _yigin);
      final sonuc = await repo.kuyrugaYolla(clientId,
          dilim.map((k) => kuyrukOp(k.localSeq, k.fn, k.args)).toList());
      for (final s in sonuc.sonuclar) {
        if (s.basarili) {
          await db.yuklendiIsaretle(s.localSeq, s.sonuc?.toString());
        } else {
          await db.hataIsaretle(s.localSeq, s.hata ?? 'bilinmeyen hata');
        }
      }
      yuklenen += sonuc.basarili;
      hatali += sonuc.hatali;
      tekrar += sonuc.tekrar;
    }
    await db.yuklenenleriTemizle();

    // 3 · Referans veri
    final ref = await repo.referans(storeId);
    final sayilar = await _referansiYaz(ref);
    await db.ayarYaz(_sonReferans, DateTime.now().toIso8601String());

    // 4 · Katalog (delta). 24.623 ürün: her senkronda baştan indirilmez.
    var urun = 0;
    if (katalog) urun = await _katalogCek();

    return SenkronRaporu(
      yuklenen: yuklenen, hatali: hatali, tekrar: tekrar,
      cari: sayilar.$1, kurum: sayilar.$2, kisi: sayilar.$3, urun: urun,
      sunucuSaati: DateTime.tryParse(ref['sunucu_saati'] as String? ?? ''),
    );
  }

  Future<(int, int, int)> _referansiYaz(Map<String, dynamic> ref) async {
    final cariler = ((ref['cariler'] as List?) ?? const []).cast<Map>();
    final kurumlar = ((ref['kurumlar'] as List?) ?? const []).cast<Map>();
    final kisiler = ((ref['kisiler'] as List?) ?? const []).cast<Map>();

    await db.transaction(() async {
      // Referans veri sunucunun aynasıdır; birleştirmek yerine değiştiriyoruz.
      // Aksi hâlde portföyden çıkan cari yerelde sonsuza dek kalırdı.
      await db.delete(db.yerelCari).go();
      await db.delete(db.yerelKurum).go();
      await db.delete(db.yerelKisi).go();
      for (final c in cariler) {
        await db.into(db.yerelCari).insert(YerelCariCompanion.insert(
              id: c['id'] as String,
              unvan: c['unvan'] as String? ?? '',
              tip: c['tip'] as String? ?? '',
              durum: c['durum'] as String? ?? 'aktif',
              kurumId: Value(c['institution_id'] as String?),
              bakiye: Value((c['bakiye'] as num?)?.toDouble() ?? 0),
              krediLimiti: Value((c['credit_limit'] as num?)?.toDouble() ?? 0),
              kademe: Value(c['discount_tier'] as String?),
            ));
      }
      for (final k in kurumlar) {
        await db.into(db.yerelKurum).insert(YerelKurumCompanion.insert(
              id: k['id'] as String,
              ad: k['ad'] as String? ?? '',
              il: Value(k['il'] as String?),
              ilce: Value(k['ilce'] as String?),
              tip: Value(k['tip'] as String?),
            ));
      }
      for (final k in kisiler) {
        await db.into(db.yerelKisi).insert(YerelKisiCompanion.insert(
              id: k['id'] as String,
              kurumId: k['institution_id'] as String,
              adSoyad: k['ad_soyad'] as String? ?? '',
              gorev: Value(k['gorev'] as String?),
              brans: Value(k['brans'] as String?),
              telefon: Value(k['telefon'] as String?),
            ));
      }
    });
    return (cariler.length, kurumlar.length, kisiler.length);
  }

  Future<int> _katalogCek() async {
    final sonStr = await db.ayarOku(_katalogTarih);
    final since = sonStr == null ? null : DateTime.tryParse(sonStr);
    // Tamamlanan tur imleci boş dizeye çeker; boş dize `p_after`'a uuid
    // olarak gidip sorguyu patlatmasın diye null'a çevriliyor.
    var imlec = await db.ayarOku(_katalogImlec);
    if (imlec != null && imlec.isEmpty) imlec = null;
    // Yeni bir delta turu başlıyorsa imleci sıfırla: imleç yalnızca YARIDA
    // kalmış turu sürdürmek içindir.
    if (since == null) imlec = null;

    var toplam = 0;
    final basladi = DateTime.now();
    while (true) {
      final sayfa = await repo.katalog(storeId, since: since, after: imlec);
      if (sayfa.satirlar.isEmpty) break;
      await db.batch((b) {
        for (final u in sayfa.satirlar) {
          b.insert(db.yerelUrun, YerelUrunCompanion.insert(
                id: u['id'] as String,
                ad: u['ad'] as String? ?? '',
                barkod: Value(u['barkod'] as String?),
                yayinevi: Value(u['yayinevi'] as String?),
                kategori: Value(u['kategori'] as String?),
                ders: Value(u['ders'] as String?),
                satisFiyat: Value((u['satis_fiyat'] as num?)?.toDouble()),
                varsayilanIskonto:
                    Value((u['varsayilan_iskonto'] as num?)?.toDouble() ?? 0),
                stokAdedi: Value((u['stok_adedi'] as num?)?.toInt() ?? 0),
                aktif: Value(u['aktif'] as bool? ?? true),
              ), mode: InsertMode.insertOrReplace);
        }
      });
      toplam += sayfa.satirlar.length;
      imlec = sayfa.sonId;
      // Yarıda kalırsa buradan devam edilir; baştan indirilmez.
      if (imlec != null) await db.ayarYaz(_katalogImlec, imlec);
      if (sayfa.bitti) break;
    }
    // Tur tamamlandı: bir sonraki senkron yalnızca bundan sonra DEĞİŞENLERİ
    // indirir. Zaman damgası turun BAŞLANGICI — tur sürerken yapılan
    // değişiklikler atlanmasın.
    await db.ayarYaz(_katalogTarih, basladi.toIso8601String());
    await db.ayarYaz(_katalogImlec, '');
    return toplam;
  }
}

class SenkronRaporu {
  const SenkronRaporu({this.yuklenen = 0, this.hatali = 0, this.tekrar = 0,
                       this.cari = 0, this.kurum = 0, this.kisi = 0,
                       this.urun = 0, this.cihazIptal = false,
                       this.sunucuSaati});
  final int yuklenen, hatali, tekrar, cari, kurum, kisi, urun;
  final bool cihazIptal;
  final DateTime? sunucuSaati;

  bool get sorunVar => hatali > 0 || cihazIptal;

  String get ozet {
    if (cihazIptal) return 'Bu cihaz iptal edilmiş — yerel veri silindi';
    final p = <String>[
      if (yuklenen > 0) '$yuklenen kayıt yüklendi',
      if (hatali > 0) '$hatali kayıt yüklenemedi',
      if (urun > 0) '$urun ürün güncellendi',
      if (cari > 0) '$cari cari indi',
    ];
    return p.isEmpty ? 'Güncel — yüklenecek kayıt yok' : p.join(' · ');
  }
}
