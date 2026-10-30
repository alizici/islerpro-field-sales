import 'package:islerpro/core/auth/session.dart';
import 'package:islerpro/data/models/session_data.dart';
import 'package:islerpro/data/repositories/aktarma_repository.dart';
import 'package:islerpro/data/repositories/cari_repository.dart';
import 'package:islerpro/data/repositories/siparis_repository.dart';
import 'package:islerpro/data/repositories/talep_repository.dart';
import 'package:islerpro/data/repositories/katalog_repository.dart';
import 'package:islerpro/data/repositories/org_repository.dart';
import 'package:islerpro/data/repositories/rapor_repository.dart';
import 'package:islerpro/data/repositories/deneme_repository.dart';
import 'package:islerpro/data/repositories/ticari_repository.dart';
import 'package:islerpro/data/repositories/ziyaret_repository.dart';

/// `implements` kullanıyoruz: özel alanlar (_db) arayüzün parçası olmadığı için
/// yalnızca genel metotları karşılamak yeterli — sahte Supabase gerekmiyor.
class SahteOrgRepo implements OrgRepository {
  SahteOrgRepo({
    this.dukkanListesi = const [],
    this.ekipListesi = const [],
    this.donemListesi = const [],
    this.bekleyenListesi = const [],
    this.pasifeAlHatasi,
    this.etki = const DukkanEtki(aktifCari: 3, aktifAtama: 2),
  });

  final List<StoreRow> dukkanListesi;
  final List<StaffRow> ekipListesi;
  final List<PeriodRow> donemListesi;
  final List<PendingTeacher> bekleyenListesi;
  final String? pasifeAlHatasi;
  final DukkanEtki etki;

  // Çağrı kaydı — testler ne yapıldığını doğrular.
  final cagrilar = <String>[];
  String? sonDevralan;

  @override
  Future<List<StoreRow>> dukkanlar() async => dukkanListesi;
  @override
  Future<List<StaffRow>> ekip({String? storeId}) async => ekipListesi;
  @override
  Future<List<PeriodRow>> donemler() async => donemListesi;
  @override
  Future<List<PendingTeacher>> bekleyenOgretmenler() async => bekleyenListesi;

  @override
  Future<void> dukkanEkle(String tenantId, String ad, {String? il, String? ilce}) async {
    cagrilar.add('dukkanEkle:$ad');
  }

  @override
  Future<void> dukkanGuncelle(String id,
      {required String ad, String? il, String? ilce, String? adres}) async {
    cagrilar.add('dukkanGuncelle:$id:$ad');
  }

  @override
  Future<DukkanEtki> pasifEtkisi(String storeId) async {
    cagrilar.add('pasifEtkisi:$storeId');
    return etki;
  }

  @override
  Future<({int kapananCari, int kapananAtama})> dukkanDurumu(
      String storeId, bool aktif) async {
    cagrilar.add('dukkanDurumu:$storeId:$aktif');
    return (kapananCari: 3, kapananAtama: 2);
  }

  @override
  Future<String> ekipDavetiOlustur({
    required String storeId, required AppRole rol,
    String? adSoyad, String? telefon,
  }) async {
    cagrilar.add('davet:${rol.name}');
    return 'TESTKOD1';
  }

  @override
  Future<int> uyeyiPasifeAl(String userId, {String? devralanUserId}) async {
    cagrilar.add('pasifeAl:$userId');
    sonDevralan = devralanUserId;
    if (pasifeAlHatasi != null) throw Exception(pasifeAlHatasi);
    return devralanUserId == null ? 0 : 7;
  }

  @override
  Future<String> sonrakiDonemiAc(String tenantId) async {
    cagrilar.add('sonrakiDonem');
    return '2026-2027 / 1. Dönem';
  }

  @override
  Future<void> donemDurumu(String periodId, String durum) async {
    cagrilar.add('donemDurumu:$durum');
  }

  @override
  Future<void> ogretmenOnayla({
    required String userId, required String institutionId,
    required String storeId, bool kurumAdinaSiparis = false,
  }) async {
    cagrilar.add('onayla:$userId:kurumAdina=$kurumAdinaSiparis');
  }
}

/// Test oturumu üretir.
Session testOturumu({AppRole rol = AppRole.isletmeSahibi}) => Session(
      data: SessionData.fromJson({
        'user': {'id': 'u1', 'ad_soyad': 'Mahmut Kaya', 'eposta': 'm@x.com'},
        'memberships': [
          {'tenant_id': 't1', 'tenant_unvan': 'İşler Yayınları',
           'role': _db(rol), 'status': 'aktif', 'store_id': 's1', 'store_ad': 'Merkez'}
        ],
        'institution_memberships': [],
        'stores': [{'id': 's1', 'ad': 'Merkez Şube', 'tenant_id': 't1'}],
        'active_periods': [
          {'id': 'p1', 'ad': '2025-2026 / 2. Dönem', 'tenant_id': 't1',
           'starts_on': '2026-02-01', 'ends_on': '2026-08-31'}
        ],
        'consent_ok': true,
      }),
      aktifRol: rol,
      storeId: 's1',
      periodId: 'p1',
    );

String _db(AppRole r) => switch (r) {
      AppRole.isletmeSahibi => 'isletme_sahibi',
      AppRole.dukkanMuduru => 'dukkan_muduru',
      AppRole.pazarlamaci => 'pazarlamaci',
      AppRole.hazirlik => 'hazirlik',
      _ => 'pazarlamaci',
    };

StaffRow uye(String ad, {int portfoy = 0, AppRole rol = AppRole.pazarlamaci,
                        String id = 'u2', bool aktif = true}) =>
    StaffRow(userId: id, adSoyad: ad, role: rol,
             status: aktif ? 'aktif' : 'pasif', portfoy: portfoy);

/// Katalog deposu sahtesi — fiyat katmanı ve K25 zinciri için.
class SahteKatalogRepo implements KatalogRepository {
  SahteKatalogRepo({
    this.urunler = const [],
    this.toplam,
    this.yayineviListesi = const [],
    this.cakisanBarkod,
    this.iskontoSonuc =
        const IskontoSonuc(oran: 0, kaynak: 'yok', kaynakAd: 'Tanımlı iskonto yok'),
  });

  final List<UrunOzet> urunler;
  final int? toplam;
  final List<Yayinevi> yayineviListesi;
  /// Doluysa urunEkle çakışma döndürür (K24).
  final String? cakisanBarkod;
  final IskontoSonuc iskontoSonuc;

  final cagrilar = <String>[];
  double? sonSatis, sonIskonto;
  bool? sonStokTakibi;

  @override
  Future<List<UrunOzet>> ara({
    required String storeId, String? q, String? katalog, String? publisherId,
    int? sinif, String? fiyatDurumu, bool arsiv = false,
    int limit = 50, int offset = 0,
  }) async {
    cagrilar.add('ara:q=$q:katalog=$katalog:fiyat=$fiyatDurumu:offset=$offset');
    if (offset >= urunler.length) return const [];
    return urunler.skip(offset).take(limit).toList();
  }

  @override
  Future<int> say({
    required String storeId, String? q, String? katalog, String? publisherId,
    int? sinif, String? fiyatDurumu, bool arsiv = false,
  }) async => toplam ?? urunler.length;

  @override
  Future<UrunOzet?> barkodla(String storeId, String barkod) async =>
      urunler.where((u) => u.barkod == barkod).firstOrNull;

  @override
  Future<({String id, bool yeni, String? mesaj})> urunEkle({
    required String storeId, required String ad, String katalog = 'kitap',
    String? barkod, String? urunKod, String? yayinevi, String? kategori,
    String? ders, List<int>? sinif, String? sinavTipi,
    double? etiketFiyat, String? baskiEtiketi,
  }) async {
    cagrilar.add('urunEkle:$ad:$katalog');
    if (cakisanBarkod != null && barkod == cakisanBarkod) {
      return (id: 'mevcut', yeni: false, mesaj: 'Bu barkod katalogda zaten var');
    }
    return (id: 'yeni', yeni: true, mesaj: null);
  }

  @override
  Future<void> fiyatKaydet({
    required String storeId, required String productId,
    double? satisFiyat, double? alisFiyat, double? varsayilanIskonto,
    bool? stokTakibi, bool? aktif,
  }) async {
    cagrilar.add('fiyatKaydet:$productId');
    sonSatis = satisFiyat;
    sonIskonto = varsayilanIskonto;
    sonStokTakibi = stokTakibi;
  }

  @override
  Future<IskontoSonuc> iskonto({
    required String storeId, required String accountId,
    required String productId, int adet = 1,
  }) async => iskontoSonuc;

  @override
  Future<({double? tavan, bool asildi})> tavanKontrol(
          String storeId, double iskonto) async =>
      (tavan: 0.30, asildi: iskonto > 0.30);

  @override
  Future<List<Yayinevi>> yayinevleri({String? storeId}) async => yayineviListesi;

  // ── K23 · baskı grupları ──────────────────────────────────────────────
  List<Baski> baskiListesi = const [];
  BaskiUyarisi uyari = const BaskiUyarisi();
  String? sonBaskiEtiketi;
  String? sonBaskiBarkod;
  bool sonArsivle = false;

  @override
  Future<({String grupId, String id, int sira})> baskiEkle({
    required String storeId, required String kaynakUrunId,
    required String baskiEtiketi, String? barkod, double? etiketFiyat,
    bool eskiyiArsivle = false,
  }) async {
    cagrilar.add('baskiEkle:$baskiEtiketi:arsivle=$eskiyiArsivle');
    sonBaskiEtiketi = baskiEtiketi;
    sonBaskiBarkod = barkod;
    sonArsivle = eskiyiArsivle;
    return (id: 'yeni', grupId: 'g1', sira: 2);
  }

  @override
  Future<List<Baski>> baskilar(String urunId, String storeId) async =>
      baskiListesi;

  @override
  Future<BaskiUyarisi> baskiUyarisi(String urunId, String storeId) async =>
      uyari;

  @override
  Future<void> baskiyaBagla(String urunId, String hedefUrunId) async {
    cagrilar.add('baskiyaBagla:$urunId→$hedefUrunId');
  }

  @override
  Future<void> baskidanCikar(String urunId) async {
    cagrilar.add('baskidanCikar:$urunId');
  }

}

Baski baski(String etiket, {String id = 'b1', int sira = 1,
    String? barkod, double? satisFiyat, int? stok, bool guncel = false,
    bool secili = false, bool arsivlendi = false, String? guncelEtiket}) =>
    Baski(id: id, ad: 'Test Kitabı', baskiEtiketi: etiket, baskiSirasi: sira,
        barkod: barkod, satisFiyat: satisFiyat, stokAdedi: stok,
        guncel: guncel, secili: secili, arsivlendi: arsivlendi,
        guncelEtiket: guncelEtiket);

UrunOzet urun(String ad, {
  String id = 'pr1', String? barkod, String? yayinevi,
  double? satisFiyat, double varsayilanIskonto = 0,
  double? etiketFiyat, String katalog = 'kitap',
  int? stokAdedi, bool stokTakibi = true,
}) =>
    UrunOzet(id: id, ad: ad, katalog: katalog, barkod: barkod,
             yayinevi: yayinevi, satisFiyat: satisFiyat,
             varsayilanIskonto: varsayilanIskonto, etiketFiyat: etiketFiyat,
             stokAdedi: stokAdedi, stokTakibi: stokTakibi,
             fiyatli: satisFiyat != null);

StoreRow dukkan(String ad, {String id = 's1', bool aktif = true,
                            String? il, String? ilce}) =>
    StoreRow(id: id, ad: ad, tenantId: 't1', il: il, ilce: ilce, aktif: aktif);

/// Aktarma deposu sahtesi. Kuru koşu ile gerçek koşuyu AYRI kaydeder —
/// önizlemenin gerçekten yazmadığını test edebilelim diye.
class SahteAktarmaRepo implements AktarmaRepository {
  SahteAktarmaRepo({
    this.ozet = const AktarmaOzet(yeni: 2, guncelleme: 1, hatali: 1,
        hatalar: [SatirHatasi(satir: 4, sebep: 'Ürün adı boş')]),
    this.gecmisListesi = const [],
    this.hataListesi = const [],
  });

  final AktarmaOzet ozet;
  final List<AktarmaKaydi> gecmisListesi;
  final List<({int satir, String hata})> hataListesi;

  final cagrilar = <String>[];
  List<Map<String, dynamic>> kuruSatirlar = const [];
  List<Map<String, dynamic>> yazilanSatirlar = const [];
  String? sonPolitika;
  String? sonTur;

  @override
  Future<String> batchAc({required String storeId, required String tur,
      String? dosyaAdi, int satirSayisi = 0}) async {
    cagrilar.add('batchAc:$tur:$satirSayisi');
    return 'b1';
  }

  @override
  Future<AktarmaOzet> parca({required String batchId,
      required List<Map<String, dynamic>> satirlar,
      String politika = 'guncelle', bool kuruKosu = false,
      String? tur}) async {
    cagrilar.add('parca:kuru=$kuruKosu:${satirlar.length}');
    sonTur = tur;
    sonPolitika = politika;
    if (kuruKosu) {
      kuruSatirlar = [...kuruSatirlar, ...satirlar];
    } else {
      yazilanSatirlar = [...yazilanSatirlar, ...satirlar];
    }
    return ozet;
  }

  @override
  Future<AktarmaOzet> tumunuGonder({required String batchId,
      required List<Map<String, dynamic>> satirlar,
      String politika = 'guncelle', bool kuruKosu = false, String? tur,
      void Function(int, int)? ilerleme}) async {
    final o = await parca(batchId: batchId, satirlar: satirlar,
        politika: politika, kuruKosu: kuruKosu, tur: tur);
    ilerleme?.call(satirlar.length, satirlar.length);
    return o;
  }

  @override
  Future<AktarmaOzet> batchKapat(String batchId) async {
    cagrilar.add('batchKapat:$batchId');
    return ozet;
  }

  @override
  Future<({int silinen, int geriAlinan})> geriAl(String batchId) async {
    cagrilar.add('geriAl:$batchId');
    return (silinen: 5, geriAlinan: 2);
  }

  @override
  Future<List<AktarmaKaydi>> gecmis({String? storeId, int limit = 25}) async =>
      gecmisListesi;

  @override
  Future<List<({int satir, String hata})>> hatalar(String batchId) async =>
      hataListesi;

  @override
  Future<void> sablonKaydet(String tur, String ad, Map<String, String> e) async {
    cagrilar.add('sablonKaydet:$ad');
  }

  @override
  Future<List<AktarmaSablonu>> sablonlar({String? tur}) async => const [];
}

AktarmaKaydi aktarma(String dosya, {String id = 'b1', String tur = 'urun',
    String durum = 'onaylandi', int eklenen = 340, int guncellenen = 68,
    int hatali = 4}) =>
    AktarmaKaydi(id: id, tur: tur, durum: durum,
        createdAt: DateTime(2026, 8, 25, 14, 30), dosyaAdi: dosya,
        yapan: 'Mahmut Kaya', eklenen: eklenen, guncellenen: guncellenen,
        hatali: hatali);

class SahteCariRepo implements CariRepository {
  SahteCariRepo({
    this.cariler = const [],
    this.detayKaydi,
    this.ozet = const PortfoyOzeti(),
    this.kontrol = const TasimaKontrol(),
    this.aramaHatasi,
  });

  final List<CariOzet> cariler;
  /// Verilirse `ara` bunu fırlatır — çevrimdışı yolu sınamak için.
  final Object? aramaHatasi;
  final CariDetay? detayKaydi;
  final PortfoyOzeti ozet;
  final TasimaKontrol kontrol;

  final cagrilar = <String>[];
  List<String>? sonAtananlar;
  String? sonAtananKisi;
  String? sonTasimaGerekce;

  @override
  Future<List<CariOzet>> ara({required String storeId, String? q, String? tip,
      String? durum, String? pazarlamaciId, bool atanmamis = false,
      bool borclu = false, String? periodId, int limit = 50,
      int offset = 0}) async {
    cagrilar.add('ara:q=$q:tip=$tip:borclu=$borclu:atanmamis=$atanmamis');
    if (aramaHatasi != null) throw aramaHatasi!;
    return cariler;
  }

  @override
  Future<int> say({required String storeId, String? q, String? tip,
      String? durum, String? pazarlamaciId, bool atanmamis = false,
      bool borclu = false, String? periodId}) async => cariler.length;

  @override
  Future<CariDetay> detay(String id) async =>
      detayKaydi ?? (throw StateError('detay yok'));

  @override
  Future<String> ekle({required String storeId, required String institutionId,
      required String tip, required String unvan, String? contactId,
      String? userId, String? discountTier, double creditLimit = 0}) async {
    cagrilar.add('ekle:$tip:$unvan:limit=$creditLimit');
    return 'yeni';
  }

  @override
  Future<void> guncelle(String id, {String? unvan, String? discountTier,
      double? creditLimit, String? invoiceTitle, String? taxId,
      String? taxOffice}) async {
    cagrilar.add('guncelle:$id');
  }

  @override
  Future<({double bakiye, String durum, String istenen})> durumDegistir(
      String id, String durum) async {
    cagrilar.add('durum:$id:$durum');
    return (durum: durum == 'pasif' ? 'tahsilatta' : durum,
            istenen: durum, bakiye: 12000.0);
  }

  @override
  Future<({int atanan, int devralinan})> portfoyAta({
      required List<String> cariIdler, required String? userId,
      required String periodId}) async {
    cagrilar.add('portfoyAta:${cariIdler.length}:$userId');
    sonAtananlar = cariIdler;
    sonAtananKisi = userId;
    return (atanan: userId == null ? 0 : cariIdler.length, devralinan: 1);
  }

  @override
  Future<PortfoyOzeti> portfoyOzeti(String storeId, String periodId) async =>
      ozet;

  @override
  Future<TasimaKontrol> tasimaKontrol(String cariId) async => kontrol;

  @override
  Future<void> tasi(String cariId, String hedefKurumId, String gerekce) async {
    cagrilar.add('tasi:$cariId:$hedefKurumId');
    sonTasimaGerekce = gerekce;
  }
}

CariOzet cari(String unvan, {String id = 'c1', String tip = 'kurum',
    double bakiye = 0, double limit = 0, bool limitAsildi = false,
    String durum = 'aktif', String? pazarlamaci, String? kurumAd = 'Test Okulu',
    String? kademe}) =>
    CariOzet(id: id, tip: tip, unvan: unvan, durum: durum,
        institutionId: 'i1', kurumAd: kurumAd, bakiye: bakiye,
        creditLimit: limit, risk: bakiye, limitAsildi: limitAsildi,
        pazarlamaciId: pazarlamaci == null ? null : 'u9',
        pazarlamaci: pazarlamaci, discountTier: kademe);

CariDetay cariDetay({String unvan = 'Test Okulu Kurumsal',
    double bakiye = 45000, double risk = 45000, double limit = 60000,
    List<CariOzet> kardesler = const [], List<TasimaKaydi> tasimalar = const [],
    List<PortfoySatiri> portfoy = const []}) =>
    CariDetay(id: 'c1', tip: 'kurum', unvan: unvan, durum: 'aktif',
        kurumId: 'i1', kurumAd: 'Test Okulu', ilce: 'HALİLİYE',
        creditLimit: limit, bakiye: bakiye, risk: risk,
        kardesCariler: kardesler, tasimalar: tasimalar, portfoy: portfoy);

class SahteTalepRepo implements TalepRepository {
  SahteTalepRepo({
    this.talepler = const [],
    this.detayKaydi,
    this.muhatapListesi = const [],
    this.oneri = const AdetOnerisi(),
    this.sonuc = const KararSonucu(durum: 'karara_baglandi',
        onaylanan: 1, reddedilen: 1),
    this.muhatapHatasi,
    this.yazmaHatasi,
  });

  final List<TalepOzet> talepler;
  /// Verilirse `muhataplar` bunu fırlatır — çevrimdışı yolu sınamak için.
  final Object? muhatapHatasi;
  /// Verilirse `olustur` bunu fırlatır — kuyruk yolunu sınamak için.
  final Object? yazmaHatasi;
  final TalepDetay? detayKaydi;
  final List<Muhatap> muhatapListesi;
  final AdetOnerisi oneri;
  final KararSonucu sonuc;

  final cagrilar = <String>[];
  List<KalemKarari>? sonKararlar;
  String? sonCariId;
  List<({int adet, String urunId})>? sonKalemler;

  @override
  Future<List<Muhatap>> muhataplar() async {
    if (muhatapHatasi != null) throw muhatapHatasi!;
    return muhatapListesi;
  }

  @override
  Future<AdetOnerisi> adetOnerisi({required String cariId,
      required String urunId, String? periodId}) async => oneri;

  @override
  Future<({String id, bool yeni})> olustur({
    required String cariId,
    required List<({int adet, String urunId})> kalemler,
    String? notMetni, DateTime? istenenTarih, bool gonder = true,
    String? clientKey,
  }) async {
    cagrilar.add('olustur:$cariId:${kalemler.length}');
    if (yazmaHatasi != null) throw yazmaHatasi!;
    sonCariId = cariId;
    sonKalemler = kalemler;
    return (id: 't1', yeni: true);
  }

  @override
  Future<void> gonder(String talepId) async { cagrilar.add('gonder:$talepId'); }

  @override
  Future<void> eleAl(String talepId) async { cagrilar.add('eleAl:$talepId'); }

  @override
  Future<void> iptal(String talepId, {String? gerekce}) async {
    cagrilar.add('iptal:$talepId');
  }

  @override
  Future<KararSonucu> kararVer({required String talepId,
      required List<KalemKarari> kararlar}) async {
    cagrilar.add('kararVer:${kararlar.length}');
    sonKararlar = kararlar;
    return sonuc;
  }

  @override
  Future<List<TalepOzet>> liste({String? storeId, String? durum,
      String? cariId, bool sadeceBekleyen = false, int limit = 50,
      int offset = 0}) async {
    cagrilar.add('liste:bekleyen=$sadeceBekleyen');
    return talepler;
  }

  @override
  Future<TalepDetay> detay(String talepId) async =>
      detayKaydi ?? (throw StateError('detay yok'));

  List<Bildirim0> bildirimListesi = const [];

  @override
  Future<List<Bildirim0>> bildirimler({bool sadeceOkunmamis = false}) async =>
      sadeceOkunmamis
          ? bildirimListesi.where((b) => !b.okundu).toList()
          : bildirimListesi;

  @override
  Future<int> bildirimleriOkundu({List<String>? idler}) async {
    cagrilar.add('okundu:${idler == null ? 'hepsi' : idler.join(',')}');
    return idler?.length ?? bildirimListesi.length;
  }
}

TalepOzet talep(String unvan, {String id = 't1', String durum = 'gonderildi',
    int kalem = 2, int adet = 42, int bekleyen = 2, bool gecikmis = false,
    String tip = 'kurum'}) =>
    TalepOzet(id: id, durum: durum, kaynak: 'ogretmen',
        createdAt: DateTime(2026, 8, 25, 10), cariId: 'c1', unvan: unvan,
        tip: tip, kurumAd: 'Test Okulu', acan: 'Ahmet Öğretmen',
        kalemSayisi: kalem, bekleyen: bekleyen, toplamAdet: adet,
        gecikmis: gecikmis);

TalepKalemi kalem(String ad, {String id = 'k1', int adet = 30,
    String durum = 'beklemede', double? satisFiyat = 100,
    double? iskonto = 0.20, String? iskontoKaynak = 'Bes Kurumsal anlaşması',
    double? satirTutari = 2400, String? redNedeni, BaskiUyarisi? uyari}) =>
    TalepKalemi(id: id, urunId: 'p1', ad: ad, adet: adet, durum: durum,
        yayinevi: 'Bes Kurumsal', satisFiyat: satisFiyat, iskonto: iskonto,
        iskontoKaynak: iskontoKaynak, satirTutari: satirTutari,
        redNedeni: redNedeni, baskiUyarisi: uyari);

TalepDetay talepDetay({String durum = 'incelemede',
    List<TalepKalemi> kalemler = const [], double bakiye = 0,
    double limit = 0, double risk = 0}) =>
    TalepDetay(id: 't1', durum: durum, kaynak: 'ogretmen',
        createdAt: DateTime(2026, 8, 25, 10),
        cari: TalepCari(id: 'c1', unvan: 'Test Okulu Kurumsal', tip: 'kurum',
            bakiye: bakiye, creditLimit: limit, risk: risk),
        kurumAd: 'Test Okulu', acan: 'Ahmet Öğretmen',
        notMetni: '8. sınıflar için', kalemler: kalemler);

Bildirim0 bildirim(String baslik, {String id = 'b1',
    String olay = 'talep_acildi', String? govde, String? hedefTur = 'request',
    String? hedefId = 't1', bool okundu = false}) =>
    Bildirim0(id: id, olay: olay, baslik: baslik,
        createdAt: DateTime(2026, 8, 25, 14), govde: govde,
        hedefTur: hedefTur, hedefId: hedefId, okundu: okundu);

AcikTeslimat acikTeslimat({String id = 's1', double tutar = 1000,
    double odenen = 0, int gunOnce = 30, int kalem = 2}) =>
    AcikTeslimat(
      id: id,
      tarih: DateTime(2026, 8, 27).subtract(Duration(days: gunOnce)),
      tutar: tutar, odenen: odenen, kalem: kalem,
    );

class SahteSiparisRepo implements SiparisRepository {
  SahteSiparisRepo({this.siparisler = const [], this.detayKaydi,
                    this.borcluListesi = const [],
                    this.acikTeslimatListesi = const [],
                    this.tahsilat = const TahsilatSonucu(id: 'p1',
                        dagitilan: 250),
                    this.yazmaHatasi});

  final List<SiparisOzet> siparisler;
  final SiparisDetay? detayKaydi;
  final List<BorcluCari> borcluListesi;
  final List<AcikTeslimat> acikTeslimatListesi;
  final TahsilatSonucu tahsilat;
  /// Verilirse `teslimEt`/`tahsilEt` bunu fırlatır — kuyruk yolunu sınamak
  /// için.
  final Object? yazmaHatasi;

  final cagrilar = <String>[];
  Map<String, int>? sonTeslimat;
  bool? sonBorclandirir;
  double? sonTutar;
  String? sonYontem;
  DateTime? sonVade;

  @override
  Future<({int kalem, String id, String? onayGerekce, double toplam})>
      talebiSiparisEt(String talepId) async {
    cagrilar.add('siparisEt:$talepId');
    return (id: 'o1', kalem: 2, toplam: 400.0, onayGerekce: null);
  }

  @override
  Future<void> durumDegistir(String siparisId, String durum,
      {String? gerekce}) async {
    cagrilar.add('durum:$siparisId:$durum');
  }

  @override
  Future<List<AcikTeslimat>> acikTeslimatlar(String cariId) async {
    cagrilar.add('acikTeslimat:$cariId');
    return acikTeslimatListesi;
  }

  @override
  Future<List<SiparisOzet>> liste({String? storeId, String? durum,
      String? cariId, bool hazirlikKutusu = false, int limit = 50,
      int offset = 0}) async {
    cagrilar.add('liste:hazirlik=$hazirlikKutusu');
    return siparisler;
  }

  @override
  Future<SiparisDetay> detay(String siparisId) async =>
      detayKaydi ?? (throw StateError('detay yok'));

  @override
  Future<({String id, int kalanAdet, double toplam})> teslimEt({
    required String cariId,
    required List<({int adet, String? siparisKalemId, String? urunId})> kalemler,
    String? siparisId, bool borclandirir = true, String tip = 'teslimat',
    String? teslimAlanAd, String? clientKey,
  }) async {
    cagrilar.add('teslimEt:${kalemler.length}:borc=$borclandirir');
    if (yazmaHatasi != null) throw yazmaHatasi!;
    sonTeslimat = {for (final k in kalemler) k.siparisKalemId ?? '': k.adet};
    sonBorclandirir = borclandirir;
    return (id: 's1', toplam: 400.0, kalanAdet: 0);
  }

  @override
  Future<TahsilatSonucu> tahsilEt({required String cariId,
      required double tutar, required String yontem, DateTime? tarih,
      String? makbuzNo, String? notMetni, DateTime? cekVade,
      String? cekBanka, String? cekNo, String? clientKey}) async {
    cagrilar.add('tahsilEt:$tutar:$yontem');
    if (yazmaHatasi != null) throw yazmaHatasi!;
    sonTutar = tutar; sonYontem = yontem; sonVade = cekVade;
    return tahsilat;
  }

  @override
  Future<Ekstre> ekstre(String cariId) async => ekstreKaydi;

  @override
  Future<List<BorcluCari>> borclular(String storeId) async => borcluListesi;

  Map<String, dynamic> makbuzVerisi = const {};
  Ekstre ekstreKaydi = const Ekstre();

  @override
  Future<Map<String, dynamic>> makbuz(String tahsilatId) async => makbuzVerisi;

  PanelOzeti panelOzeti = const PanelOzeti();
  BugunOzeti bugunOzeti = const BugunOzeti();

  @override
  Future<PanelOzeti> panel(String storeId, {String? periodId}) async =>
      panelOzeti;

  @override
  Future<BugunOzeti> bugun(String storeId, {String? periodId}) async =>
      bugunOzeti;
}

SiparisOzet siparis(String unvan, {String id = 'o1', String durum = 'olusturuldu',
    int kalem = 2, double toplam = 400, int bekleyen = 0,
    String? hazirlayan}) =>
    SiparisOzet(id: id, durum: durum, tip: 'satis',
        createdAt: DateTime(2026, 8, 25, 11), cariId: 'c1', unvan: unvan,
        kurumAd: 'Test Okulu', olusturan: 'Ali Veli', hazirlayan: hazirlayan,
        kalemSayisi: kalem, toplam: toplam, bekleyenAdet: bekleyen);

SiparisKalemi siparisKalemi(String ad, {String id = 'ok1', int adet = 5,
    double birimFiyat = 100, double iskonto = 0.20, double tutar = 400,
    int sevkEdilen = 0, int backorder = 5}) =>
    SiparisKalemi(id: id, urunId: 'p1', ad: ad, adet: adet,
        birimFiyat: birimFiyat, iskontoOrani: iskonto, satirTutari: tutar,
        yayinevi: 'Bes Kurumsal', sevkEdilen: sevkEdilen, backorder: backorder);

SiparisDetay siparisDetay({String durum = 'hazir',
    List<SiparisKalemi> kalemler = const [], double toplam = 400,
    String? onayGerekce, String? hazirlayan}) =>
    SiparisDetay(id: 'o1', durum: durum, tip: 'satis',
        createdAt: DateTime(2026, 8, 25, 11), cariId: 'c1',
        cariUnvan: 'Y Lisesi Kurumsal', kurumAd: 'Y Lisesi',
        olusturan: 'Ali Veli', hazirlayan: hazirlayan,
        hazirlikBitti: hazirlayan == null ? null : DateTime(2026, 8, 25, 12),
        onayGerekce: onayGerekce, toplam: toplam, kalemler: kalemler);

BorcluCari borclu(String unvan, {String id = 'c1', double bakiye = 400,
    double risk = 400, double limit = 0, String? pazarlamaci = 'Ali Veli',
    DateTime? enEski}) =>
    BorcluCari(id: id, unvan: unvan, tip: 'kurum', kurumAd: 'Test Okulu',
        bakiye: bakiye, risk: risk, creditLimit: limit,
        pazarlamaci: pazarlamaci, enEskiBorc: enEski);

// ── Saha · ziyaret ve rota (Faz 7) ─────────────────────────────────────────

class SahteZiyaretRepo implements ZiyaretRepository {
  SahteZiyaretRepo({this.acik, this.rotaKaydi = const Rota(),
                    this.oneriler = const [], this.detayKaydi,
                    this.ziyaretler = const [], this.performansListesi = const [],
                    this.baslatHatasi,
                    this.bitisCikti = const ZiyaretCikti(
                        talep: 2, tahsilat: 1, toplam: 3)});

  AcikZiyaret? acik;
  final Rota rotaKaydi;
  final List<RotaOneri> oneriler;
  final ZiyaretDetay? detayKaydi;
  final List<ZiyaretOzet> ziyaretler;
  final List<ZiyaretPerformans> performansListesi;
  final String? baslatHatasi;
  final ZiyaretCikti bitisCikti;

  final cagrilar = <String>[];
  String? sonNot, sonSonuc;
  List<String>? sonSira;

  @override
  Future<AcikZiyaret?> acikZiyaret() async => acik;

  @override
  Future<({String id, bool yeni, String kurumAd})> baslat(String kurumId,
      {String? contactId, String? clientKey, DateTime? girisSaati}) async {
    cagrilar.add('baslat:$kurumId');
    if (baslatHatasi != null) throw StateError(baslatHatasi!);
    return (id: 'v1', yeni: true, kurumAd: 'Test Okulu');
  }

  @override
  Future<({String kurumAd, int dakika, ZiyaretCikti cikti})> bitir(
      {String? ziyaretId, String? notMetni, String? sonuc,
       DateTime? cikisSaati}) async {
    cagrilar.add('bitir:$ziyaretId');
    sonNot = notMetni;
    sonSonuc = sonuc;
    acik = null;
    return (kurumAd: 'Test Okulu', dakika: 27, cikti: bitisCikti);
  }

  @override
  Future<ZiyaretDetay> detay(String ziyaretId) async =>
      detayKaydi ?? (throw StateError('ziyaret yok'));

  @override
  Future<List<ZiyaretOzet>> liste({String? storeId, String? userId,
      String? kurumId, int gun = 30, int limit = 100}) async => ziyaretler;

  @override
  Future<Rota> rota({DateTime? tarih}) async => rotaKaydi;

  @override
  Future<List<RotaOneri>> oneri({int limit = 15}) async => oneriler;

  @override
  Future<String> planaEkle(String kurumId, {DateTime? tarih, String? amac}) async {
    cagrilar.add('planaEkle:$kurumId');
    return 'pl1';
  }

  @override
  Future<void> plandanCikar(String planId) async =>
      cagrilar.add('plandanCikar:$planId');

  @override
  Future<void> planDurumu(String planId, String durum) async =>
      cagrilar.add('planDurumu:$planId:$durum');

  @override
  Future<void> planSirala(List<String> planIdler) async {
    cagrilar.add('planSirala');
    sonSira = planIdler;
  }

  @override
  Future<List<ZiyaretPerformans>> performans(String storeId,
      {String? periodId, String? userId}) async => performansListesi;
}

RotaDurak durak(String ad, {String kurumId = 'k1', String planId = 'pl1',
    String durum = 'planlandi', double borc = 0, int talep = 0,
    int hazir = 0, int cari = 1, String? amac, String? ziyaretId,
    DateTime? sonZiyaret}) =>
    RotaDurak(planId: planId, kurumId: kurumId, kurumAd: ad, ilce: 'Haliliye',
        durum: durum, borc: borc, bekleyenTalep: talep, hazirSiparis: hazir,
        cari: cari, amac: amac, ziyaretId: ziyaretId, sonZiyaret: sonZiyaret);

RotaOneri oneri(String ad, {String kurumId = 'k9', String neden = '45 gündür uğranmadı',
    int gecikmisBorc = 0, int gecikmisTalep = 0, int hazirSiparis = 0,
    int konsinye = 0, bool planda = false, double borc = 0}) =>
    RotaOneri(kurumId: kurumId, kurumAd: ad, neden: neden, ilce: 'Eyyübiye',
        gecikmisBorc: gecikmisBorc, gecikmisTalep: gecikmisTalep,
        hazirSiparis: hazirSiparis, konsinye: konsinye, planda: planda,
        borc: borc);

AcikZiyaret acikZiyaret({String kurumAd = 'Fatih Anadolu Lisesi',
    int dakika = 24, ZiyaretCikti cikti = const ZiyaretCikti()}) =>
    AcikZiyaret(id: 'v1', kurumId: 'k1', kurumAd: kurumAd,
        girisSaati: DateTime.now().subtract(Duration(minutes: dakika)),
        ilce: 'Haliliye', dakika: dakika, cikti: cikti);

ZiyaretDetay ziyaretDetay({bool acik = false, String? sonuc = 'olumlu',
    String? notMetni, ZiyaretCikti cikti = const ZiyaretCikti(),
    List<ZiyaretSatir> satirlar = const []}) =>
    ZiyaretDetay(id: 'v1', kurumId: 'k1', kurumAd: 'Fatih Anadolu Lisesi',
        ilce: 'Haliliye', pazarlamaci: 'Ali Veli',
        girisSaati: DateTime(2026, 8, 25, 10, 15),
        cikisSaati: acik ? null : DateTime(2026, 8, 25, 10, 52),
        dakika: acik ? null : 37, sonuc: sonuc, notMetni: notMetni,
        cikti: cikti, satirlar: satirlar);

ZiyaretSatir ziyaretSatiri(String tur, String baslik,
    {String? aciklama, double? tutar}) =>
    ZiyaretSatir(tur: tur, id: '$tur-1', tarih: DateTime(2026, 8, 25, 10, 30),
        baslik: baslik, aciklama: aciklama, tutar: tutar);

// ── Ticari · çek, iade, konsinye (Faz 8) ───────────────────────────────────

class SahteTicariRepo implements TicariRepository {
  SahteTicariRepo({this.takvim = const VadeTakvimi(),
                   this.konsinyeler = const [], this.kalemler = const [],
                   this.iadeler = const [], this.hata,
                   this.kapanis = const KonsinyeKapanisi(borc: 400)});

  final VadeTakvimi takvim;
  final List<KonsinyeCari> konsinyeler;
  final List<KonsinyeKalemi> kalemler;
  final List<IadeKalemi> iadeler;
  final String? hata;
  final KonsinyeKapanisi kapanis;

  final cagrilar = <String>[];
  String? sonDurum, sonCiro, sonGerekce;
  List<({String urunId, int adet})>? sonSatilan, sonIade;
  bool? sonBakiyeyiAzaltir;

  @override
  Future<VadeTakvimi> vadeTakvimi(String storeId,
      {DateTime? baslangic, DateTime? bitis, String? durum}) async => takvim;

  @override
  Future<({String durum, bool degisti, double? bakiye})> cekDurumu(
      String cekId, String durum,
      {String? ciroEdilen, String? gerekce}) async {
    cagrilar.add('cekDurumu:$cekId:$durum');
    if (hata != null) throw StateError(hata!);
    sonDurum = durum; sonCiro = ciroEdilen; sonGerekce = gerekce;
    return (durum: durum, degisti: true, bakiye: 1200.0);
  }

  @override
  Future<({String id, int kalem, double toplam, double? bakiye})> iadeAl({
    required String cariId,
    required List<({String urunId, int adet, String? teslimatKalemId})> kalemler,
    String? teslimatId, bool bakiyeyiAzaltir = true,
    String? gerekce, String? clientKey}) async {
    cagrilar.add('iadeAl:${kalemler.length}:azaltir=$bakiyeyiAzaltir');
    sonBakiyeyiAzaltir = bakiyeyiAzaltir;
    sonGerekce = gerekce;
    if (hata != null) throw StateError(hata!);
    return (id: 'r1', kalem: kalemler.length, toplam: 400.0, bakiye: 800.0);
  }

  @override
  Future<List<IadeKalemi>> iadeEdilebilirler(String cariId) async => iadeler;

  @override
  Future<List<KonsinyeKalemi>> konsinyeDetay(String cariId) async => kalemler;

  @override
  Future<KonsinyeKapanisi> konsinyeKapat({required String cariId,
      List<({String urunId, int adet})> satilan = const [],
      List<({String urunId, int adet})> iade = const [],
      String? gerekce, String? clientKey}) async {
    cagrilar.add('konsinyeKapat:${satilan.length}:${iade.length}');
    sonSatilan = satilan; sonIade = iade; sonGerekce = gerekce;
    if (hata != null) throw StateError(hata!);
    return kapanis;
  }

  @override
  Future<List<KonsinyeCari>> konsinyeCariler(String storeId) async =>
      konsinyeler;
}

Cek cek(String unvan, {String id = 'ch1', double tutar = 5000,
    String durum = 'portfoyde', String tip = 'cek', DateTime? vade,
    int? gun, String? banka = 'Ziraat'}) =>
    Cek(id: id, unvan: unvan, tutar: tutar, durum: durum, tip: tip,
        vade: vade ?? DateTime(2026, 9, 15), gun: gun, banka: banka,
        kesideci: 'Ahmet Yılmaz', cekNo: '0012345');

KonsinyeKalemi konsinyeKalemi(String ad, {String urunId = 'p1',
    int birakilan = 20, int satilan = 0, int iade = 0, int? kalan,
    double fiyat = 100, double iskonto = 0.20}) =>
    KonsinyeKalemi(urunId: urunId, ad: ad, birakilan: birakilan,
        satilan: satilan, iade: iade,
        kalan: kalan ?? (birakilan - satilan - iade),
        yayinevi: 'Bes Kurumsal', birimFiyat: fiyat, iskontoOrani: iskonto);

IadeKalemi iadeKalemi(String ad, {String urunId = 'p1', int cikan = 10,
    int iade = 0, bool borclandirdi = true, double fiyat = 100,
    double iskonto = 0.20}) =>
    IadeKalemi(urunId: urunId, ad: ad, cikan: cikan, iade: iade,
        kalan: cikan - iade, borclandirdi: borclandirdi,
        yayinevi: 'Bes Kurumsal', birimFiyat: fiyat, iskontoOrani: iskonto);

// ── Deneme takvimi (Faz 9) ─────────────────────────────────────────────────

class SahteDenemeRepo implements DenemeRepository {
  SahteDenemeRepo({this.takvimKaydi = const DenemeTakvimi(),
                   this.yaklasanlar_ = const [], this.hedefler_ = const [],
                   this.gecenSeferKaydi = const {},
                   this.mevcutlarKaydi = const Mevcutlar(),
                   this.hata,
                   this.programKaydi, this.programListesi = const [],
                   this.ozetKaydi = const DonemOzeti(),
                   this.topluSonuc = const TopluTalepSonucu(
                       acilan: 2, toplamAdet: 270)});

  final DenemeTakvimi takvimKaydi;
  final List<Deneme> yaklasanlar_;
  final List<DenemeHedefi> hedefler_;
  final Map<String, int> gecenSeferKaydi;
  final Mevcutlar mevcutlarKaydi;
  final String? hata;
  final TopluTalepSonucu topluSonuc;
  final DenemeProgrami? programKaydi;
  final List<ProgramOzeti> programListesi;
  final DonemOzeti ozetKaydi;

  final cagrilar = <String>[];
  String? sonEksen, sonKademe, sonTur;
  bool? sonPortfoy;
  DateTime? sonAy;
  List<({String cariId, int adet})>? sonHedefler;
  List<({int sinif, int ogrenciSayisi})>? sonMevcutlar;
  String? sonNot;
  DateTime? sonYeniTarih;

  @override
  Future<DenemeTakvimi> takvim(String storeId, {DateTime? ay,
      String eksen = 'stok', String? kademe, String? turu,
      String? publisherId, bool sadecePortfoy = false}) async {
    cagrilar.add('takvim:$eksen');
    sonEksen = eksen; sonKademe = kademe; sonTur = turu;
    sonPortfoy = sadecePortfoy; sonAy = ay;
    return takvimKaydi;
  }

  @override
  Future<List<Deneme>> yaklasanlar(String storeId, {int gun = 7}) async =>
      yaklasanlar_;

  @override
  Future<List<DenemeHedefi>> hedefler(String denemeId, String storeId) async =>
      hedefler_;

  @override
  Future<Map<String, int>> gecenSefer(String denemeId) async {
    cagrilar.add('gecenSefer');
    return gecenSeferKaydi;
  }

  @override
  Future<TopluTalepSonucu> topluTalep({required String denemeId,
      required List<({String cariId, int adet})> hedefler,
      DateTime? istenenTarih, String? notMetni, String? clientKey}) async {
    cagrilar.add('topluTalep:${hedefler.length}');
    sonHedefler = hedefler;
    if (hata != null) throw StateError(hata!);
    return topluSonuc;
  }

  @override
  Future<Mevcutlar> mevcutlar(String cariId) async => mevcutlarKaydi;

  @override
  Future<int> mevcutYaz(String cariId,
      List<({int sinif, int ogrenciSayisi})> satirlar) async {
    cagrilar.add('mevcutYaz:${satirlar.length}');
    sonMevcutlar = satirlar;
    if (hata != null) throw StateError(hata!);
    return satirlar.fold<int>(0, (a, b) => a + b.ogrenciSayisi);
  }

  // ── Abonelik programı ──────────────────────────────────────────────────
  @override
  Future<String> programAc({required String cariId,
      String modu = 'takvim_bagli', required int ogrenciSayisi,
      int? denemeAdedi, int? periyotGun, double? birimFiyat}) async {
    cagrilar.add('programAc:$modu');
    return 'pg1';
  }

  @override
  Future<({int guncellenen, int degismeyen})> programGuncelle(
      String programId, {int? ogrenciSayisi, double? birimFiyat}) async {
    cagrilar.add('programGuncelle');
    return (guncellenen: 3, degismeyen: 2);
  }

  @override
  Future<({int dusen, int teslimEdilmis})> programIptal(String programId,
      {String? gerekce}) async {
    cagrilar.add('programIptal');
    return (dusen: 3, teslimEdilmis: 2);
  }

  @override
  Future<int> teslimPlanla(String programId,
      List<({String denemeId, DateTime? tarih, int? adet})> kalemler,
      {DateTime? baslangic}) async {
    cagrilar.add('teslimPlanla:${kalemler.length}');
    return kalemler.length;
  }

  @override
  Future<String> teslimDurumu(String kalemId, String durum,
      {String? not, DateTime? yeniTarih}) async {
    cagrilar.add('teslimDurumu:$kalemId:$durum');
    sonNot = not;
    sonYeniTarih = yeniTarih;
    if (hata != null) throw StateError(hata!);
    return durum;
  }

  @override
  Future<({String teslimatId, int adet, double? bakiye})> teslimEt(
      String kalemId, {int? adet, String? teslimAlanAd,
      String? clientKey}) async {
    cagrilar.add('teslimEt:$kalemId');
    if (hata != null) throw StateError(hata!);
    return (teslimatId: 's1', adet: adet ?? 200, bakiye: 4000.0);
  }

  @override
  Future<DenemeProgrami> programDetay(String programId) async =>
      programKaydi ?? (throw StateError('program yok'));

  @override
  Future<List<ProgramOzeti>> programlar(String storeId,
      {String? cariId, bool? aktif}) async => programListesi;

  @override
  Future<DonemOzeti> donemOzeti(String storeId, {String? periodId}) async =>
      ozetKaydi;
}

Deneme deneme(String ad, {String id = 'd1', String turu = 'takvim',
    DateTime? stok, DateTime? uygulama, String? uygulamaMetin,
    String? duzey = '8. SINIF', int? gun, List<int> sinif = const [8],
    bool fiyatli = true}) =>
    Deneme(id: id, ad: ad, turu: turu,
        stokTarihi: stok ?? DateTime(2025, 11, 13),
        uygulamaBaslangic: uygulama, uygulamaMetin: uygulamaMetin,
        yayinevi: 'İşleyen Zeka', duzey: duzey, sinif: sinif, gun: gun,
        fiyatli: fiyatli);

DenemeHedefi denemeHedefi(String unvan, {String cariId = 'c1',
    int? mevcut = 180, int oneri = 180, String? etiket = 'sınıf mevcudu',
    double bakiye = 0}) =>
    DenemeHedefi(cariId: cariId, unvan: unvan, tip: 'kurum',
        kurumAd: 'Y Lisesi', mevcut: mevcut, oneri: oneri,
        oneriEtiket: etiket, bakiye: bakiye);

// ── Faz 10 · rapor motoru (K50) ────────────────────────────────────────────

RaporTanimi tanimCiro() => const RaporTanimi(
      kod: 'ciro', ad: 'Ciro', grup: 'satis', kaynak: 'report_satis',
      aciklama: 'K26 · Ciro teslimattan doğar, siparişten değil.',
      boyutlar: [
        RaporBoyutu(anahtar: 'pazarlamaci', ad: 'Pazarlamacı'),
        RaporBoyutu(anahtar: 'kurum', ad: 'Kurum'),
        RaporBoyutu(anahtar: 'ay', ad: 'Ay'),
      ],
      varsayilanKirilim: ['pazarlamaci'],
      olculer: [
        RaporOlcusu(anahtar: 'ciro', ad: 'Ciro', tip: 'para'),
        RaporOlcusu(anahtar: 'adet', ad: 'Adet'),
      ],
      suzgecler: ['donem', 'tarih', 'dukkan', 'pazarlamaci'],
    );

RaporTanimi tanimBorclu() => const RaporTanimi(
      kod: 'borclu_cariler', ad: 'Borçlu cariler', grup: 'cari',
      kaynak: 'report_cari',
      aciklama: 'Bakiyesi olan tüm cariler. K7 · kurum düzeyinde TOPLANMAZ.',
      boyutlar: [
        RaporBoyutu(anahtar: 'cari', ad: 'Cari'),
        RaporBoyutu(anahtar: 'kurum', ad: 'Kurum'),
      ],
      varsayilanKirilim: ['cari'],
      olculer: [
        RaporOlcusu(anahtar: 'bakiye', ad: 'Bakiye', tip: 'para', mali: true),
      ],
      suzgecler: ['dukkan', 'pazarlamaci'],
    );

RaporSonucu sonucCiro({
  List<Map<String, dynamic>>? satirlar,
  List<String> uyarilar = const [],
  int kirilimSayisi = 2,
  bool onbellekten = false,
}) =>
    RaporSonucu(
      kod: 'ciro', ad: 'Ciro',
      aciklama: 'K26 · Ciro teslimattan doğar, siparişten değil.',
      kirilim: const ['pazarlamaci'],
      sutunlar: const [
        RaporSutunu(anahtar: 'pazarlamaci', ad: 'Pazarlamacı',
            tip: 'metin', kirilim: true),
        RaporSutunu(anahtar: 'ciro', ad: 'Ciro', tip: 'para', kirilim: false),
        RaporSutunu(anahtar: 'adet', ad: 'Adet', tip: 'sayi', kirilim: false),
      ],
      satirlar: satirlar ??
          const [
            {'pazarlamaci': 'Ali Veli', 'ciro': 2000.0, 'adet': 40},
            {'pazarlamaci': 'Ayşe Kaya', 'ciro': 1000.0, 'adet': 25},
          ],
      toplam: const {'ciro': 3000.0, 'adet': 65},
      kirilimSayisi: kirilimSayisi,
      sirala: 'ciro',
      uyarilar: uyarilar,
      onbellekten: onbellekten,
      uretildiAt: DateTime(2026, 8, 27, 10, 30),
    );

class SahteRaporRepo implements RaporRepository {
  SahteRaporRepo({
    List<RaporTanimi>? katalogListesi,
    RaporSonucu? sonuc,
    this.kayitliListesi = const [],
  })  : katalogListesi = katalogListesi ?? [tanimCiro(), tanimBorclu()],
        sonuc = sonuc ?? sonucCiro();

  final List<RaporTanimi> katalogListesi;
  final RaporSonucu sonuc;
  final List<KayitliRapor> kayitliListesi;
  final cagrilar = <String>[];

  @override
  Future<List<RaporTanimi>> katalog() async => katalogListesi;

  @override
  Future<RaporSonucu> calistir({
    required String kod, required String storeId,
    List<String> kirilim = const [], Map<String, dynamic> filtreler = const {},
    String? sirala, bool artan = false, int limit = 100, int offset = 0,
  }) async {
    cagrilar.add('calistir:$kod:${kirilim.join(",")}:$sirala');
    return sonuc;
  }

  @override
  Future<List<KayitliRapor>> kayitlilar(String storeId) async => kayitliListesi;

  @override
  Future<String> kaydet({
    required String ad, required String kod, required String storeId,
    List<String> kirilim = const [], Map<String, dynamic> filtreler = const {},
    List<String> sutunlar = const [], String paylasim = 'kisisel', String? id,
  }) async {
    cagrilar.add('kaydet:$ad:$kod:$paylasim');
    return 'r1';
  }

  @override
  Future<void> sil(String id) async => cagrilar.add('sil:$id');
}

/// İlk kırılım sütunu BİLEREK tekrar ediyor: çok seviyeli kırılımda satır
/// kimliğinin benzersiz kalması gerektiğini bu veri kolluyor.
RaporSonucu sonucCokSeviyeli() => const RaporSonucu(
      kod: 'urun_satisi', ad: 'Ürün satışı',
      kirilim: ['yayinevi', 'urun'],
      sutunlar: [
        RaporSutunu(anahtar: 'yayinevi', ad: 'Yayınevi',
            tip: 'metin', kirilim: true),
        RaporSutunu(anahtar: 'urun', ad: 'Ürün', tip: 'metin', kirilim: true),
        RaporSutunu(anahtar: 'adet', ad: 'Adet', tip: 'sayi', kirilim: false),
      ],
      satirlar: [
        {'yayinevi': 'Bes', 'urun': 'TYT Matematik', 'adet': 40},
        {'yayinevi': 'Bes', 'urun': 'TYT Türkçe', 'adet': 25},
      ],
      toplam: {'adet': 65},
      kirilimSayisi: 2,
    );
