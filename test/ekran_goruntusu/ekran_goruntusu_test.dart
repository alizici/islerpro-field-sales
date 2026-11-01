/// README'deki telefon ekran görüntülerini üretir (`docs/screenshots/`).
///
/// Normal koşuda ATLANIR: `ekran` etiketi `dart_test.yaml`'da atlanıyor, test
/// takımı hızlı kalsın diye. Görüntüleri yeniden üretmek için:
///
///   flutter test --tags ekran --run-skipped --update-goldens test/ekran_goruntusu
///
/// `--update-goldens` olmadan koşarsa görüntüleri kıyaslar; yazı tipi
/// işleme platforma göre değiştiği için kıyas yalnızca aynı makinede anlamlı.
///
/// Ekranlar GERÇEK widget'lar: uygulamanın kabuğu (bağlam şeridi, alt
/// gezinme), teması ve yazı tipleri; yalnızca depolar sahte. Veriler
/// uydurmadır — kurum, kişi ve yayınevi adları gerçek kayıtlara ait değildir.
///
/// Telefon: 390×844 mantıksal nokta, 3× yoğunluk (1170×2532 piksel), iPhone
/// güvenli alan payları. Üstteki saat/pil şeridi görüntüye çizilen bir
/// çerçevedir, uygulamanın parçası değil.
@Tags(['ekran'])
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:islerpro/core/auth/session.dart';
import 'package:islerpro/core/router/app_router.dart';
import 'package:islerpro/core/theme/app_theme.dart';
import 'package:islerpro/data/local/yerel_saglayici.dart';
import 'package:islerpro/data/models/session_data.dart';
import 'package:islerpro/data/repositories/cari_repository.dart';
import 'package:islerpro/data/repositories/deneme_repository.dart';
import 'package:islerpro/data/repositories/siparis_repository.dart';
import 'package:islerpro/data/repositories/talep_repository.dart';
import 'package:islerpro/data/repositories/ziyaret_repository.dart';
import 'package:islerpro/features/accounts/presentation/cari_detay_ekrani.dart';
import 'package:islerpro/features/dashboard/presentation/bugun_ekrani.dart';
import 'package:islerpro/features/dashboard/presentation/kabuk.dart';
import 'package:islerpro/features/dashboard/presentation/panel_ekrani.dart';
import 'package:islerpro/features/orders/presentation/siparis_detay_ekrani.dart';

import '../widgets/sahte_depolar.dart';

void main() {
  setUpAll(_yaziTipleriniYukle);

  final iPhone = TargetPlatformVariant.only(TargetPlatform.iOS);

  testWidgets('Bugün · pazarlamacının sabahı', variant: iPhone, (t) async {
    await _telefonda(t);
    await _kabukta(
      t,
      oturum: _oturum(AppRole.pazarlamaci, 'Emre Aydın'),
      yol: '/bugun',
      siparis: SahteSiparisRepo()..bugunOzeti = _bugun,
      ziyaret: SahteZiyaretRepo(acik: _acikZiyaret, rotaKaydi: _rota),
      deneme: SahteDenemeRepo(yaklasanlar_: _yaklasanDenemeler),
    );

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../../docs/screenshots/today.png'),
    );
  });

  testWidgets('Panel · sahibin açılışı', variant: iPhone, (t) async {
    await _telefonda(t);
    await _kabukta(
      t,
      oturum: _oturum(AppRole.isletmeSahibi, 'Selin Arslan'),
      yol: '/panel',
      siparis: SahteSiparisRepo()..panelOzeti = _panel,
    );

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../../docs/screenshots/dashboard.png'),
    );
  });

  testWidgets('Sipariş · kısmi teslim', variant: iPhone, (t) async {
    await _telefonda(t);
    await _kabukta(
      t,
      oturum: _oturum(AppRole.pazarlamaci, 'Emre Aydın'),
      yol: '/siparisler',
      siparis: SahteSiparisRepo(detayKaydi: _siparis)..bugunOzeti = _bugun,
      ustune: const SiparisDetayEkrani(siparisId: 'o1'),
    );

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../../docs/screenshots/order.png'),
    );
  });

  testWidgets('Cari · okulun hesabı', variant: iPhone, (t) async {
    await _telefonda(t);
    await _kabukta(
      t,
      oturum: _oturum(AppRole.pazarlamaci, 'Emre Aydın'),
      yol: '/cariler',
      siparis: SahteSiparisRepo()..bugunOzeti = _bugun,
      cari: SahteCariRepo(detayKaydi: _cari),
      ustune: const CariDetayEkrani(cariId: 'c1'),
    );

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../../docs/screenshots/account.png'),
    );
  });
}

// ── Düzenek ────────────────────────────────────────────────────────────────

/// Test yazı tipi her harfi kutu olarak çizer. Uygulamanın gömülü yazı
/// tipleri ve ikon yazı tipi, test paketinin kendi `FontManifest.json`'ından
/// yüklenir — ikili dosya kopyalamaya gerek yok.
Future<void> _yaziTipleriniYukle() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final liste =
      json.decode(await rootBundle.loadString('FontManifest.json'))
          as List<dynamic>;
  for (final aile in liste.cast<Map<String, dynamic>>()) {
    final yukleyici = FontLoader(aile['family'] as String);
    for (final f in (aile['fonts'] as List).cast<Map<String, dynamic>>()) {
      yukleyici.addFont(rootBundle.load(f['asset'] as String));
    }
    await yukleyici.load();
  }
}

/// iPhone 14 boyutları: 390×844 nokta, 3×, çentik ve ev çizgisi payı.
Future<void> _telefonda(WidgetTester t) async {
  const yogunluk = 3.0;
  const pay = FakeViewPadding(top: 47 * yogunluk, bottom: 34 * yogunluk);
  t.view.physicalSize = const Size(390 * yogunluk, 844 * yogunluk);
  t.view.devicePixelRatio = yogunluk;
  t.view.padding = pay;
  t.view.viewPadding = pay;
  addTearDown(t.view.reset);
}

/// Ekranı uygulamanın kabuğunda açar — üstte bağlam şeridi, altta gezinme.
///
/// [ustune] verilirse kabuğun içinden açılır, uygulamada olduğu gibi: detay
/// ekranları kabuğun kendi gezgininde açılıyor, alt çubuk yerinde kalıyor.
Future<void> _kabukta(
  WidgetTester t, {
  required Session oturum,
  required String yol,
  required SahteSiparisRepo siparis,
  SahteZiyaretRepo? ziyaret,
  SahteDenemeRepo? deneme,
  SahteCariRepo? cari,
  Widget? ustune,
}) async {
  final kabukGezgini = GlobalKey<NavigatorState>();
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        sessionProvider.overrideWithValue(oturum),
        siparisRepositoryProvider.overrideWithValue(siparis),
        talepRepositoryProvider.overrideWithValue(
          SahteTalepRepo()..bildirimListesi = _bildirimler,
        ),
        ziyaretRepositoryProvider.overrideWithValue(
          ziyaret ?? SahteZiyaretRepo(),
        ),
        denemeRepositoryProvider.overrideWithValue(deneme ?? SahteDenemeRepo()),
        cariRepositoryProvider.overrideWithValue(cari ?? SahteCariRepo()),
        // Widget testinde dosya sistemi yok; yerel veritabanı web'deki gibi
        // kapalı çalışır (bkz. ac_stub.dart).
        yerelDbProvider.overrideWithValue(null),
      ],
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        locale: const Locale('tr', 'TR'),
        supportedLocales: const [Locale('tr', 'TR')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (_, child) => _DurumCubugu(child: child!),
        routerConfig: GoRouter(
          initialLocation: yol,
          routes: [
            ShellRoute(
              navigatorKey: kabukGezgini,
              builder: (_, _, child) => Kabuk(child: child),
              routes: [
                for (final h in hedeflerFor(oturum.aktifRol))
                  GoRoute(
                    path: h.yol,
                    builder: (_, _) => switch (h.yol) {
                      '/bugun' => const BugunEkrani(),
                      '/panel' => const PanelEkrani(),
                      // Detay ekranının altında kalan sayfa görünmüyor.
                      _ => const SizedBox.shrink(),
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  await t.pumpAndSettle();

  if (ustune != null) {
    kabukGezgini.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => ustune),
    );
    await t.pumpAndSettle();
  }
}

/// Telefonun saat/pil şeridi — yalnızca görüntünün çerçevesi. Kabuğun üst
/// şeridi koyu bordo; yazılar o yüzden beyaz.
class _DurumCubugu extends StatelessWidget {
  const _DurumCubugu({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ust = MediaQuery.viewPaddingOf(context).top;
    const renk = Colors.white;
    return Stack(
      children: [
        child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: ust,
          // Gezginin DIŞINDA çiziliyor; Material olmadan Flutter yazının altına
          // "biçemsiz metin" uyarısı olarak sarı çift çizgi çeker.
          child: IgnorePointer(
            child: Material(
              type: MaterialType.transparency,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(36, 14, 26, 0),
                child: Row(
                  children: [
                    const Text(
                      '09:41',
                      style: TextStyle(
                        fontFamily: 'IBMPlexSans',
                        color: renk,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const Spacer(),
                    const Icon(
                      Icons.signal_cellular_alt,
                      size: 17,
                      color: renk,
                    ),
                    const SizedBox(width: 5),
                    const Icon(Icons.wifi, size: 17, color: renk),
                    const SizedBox(width: 6),
                    // iOS pili yatay; Material'ın pil ikonu dikey. Elle çiziliyor.
                    Container(
                      width: 25,
                      height: 12,
                      padding: const EdgeInsets.all(1.5),
                      decoration: BoxDecoration(
                        border: Border.all(color: renk.withValues(alpha: 0.45)),
                        borderRadius: BorderRadius.circular(3.5),
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: 0.8,
                          child: Container(
                            decoration: BoxDecoration(
                              color: renk,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Container(
                      width: 1.5,
                      height: 4,
                      margin: const EdgeInsets.only(left: 1),
                      color: renk.withValues(alpha: 0.45),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Demo verisi ────────────────────────────────────────────────────────────
//
// Bir yayın dağıtıcısının ekim sonu: dönem başlamış, okullar deneme ve kaynak
// kitap siparişlerini vermiş, tahsilat sürüyor. Sayılar birbirini tutar
// (satır tutarı = adet × fiyat × (1 − iskonto), sipariş toplamı = satırlar).

const _donem = '2026-2027 / 1. Dönem';

Session _oturum(AppRole rol, String ad) => Session(
  data: SessionData.fromJson({
    'user': {'id': 'u1', 'ad_soyad': ad, 'eposta': 'demo@ornek.test'},
    'memberships': [
      {
        'tenant_id': 't1',
        'tenant_unvan': 'Pusula Kitap Dağıtım',
        'role': switch (rol) {
          AppRole.isletmeSahibi => 'isletme_sahibi',
          _ => 'pazarlamaci',
        },
        'status': 'aktif',
        'store_id': 's1',
        'store_ad': 'Merkez Şube',
      },
    ],
    'institution_memberships': [],
    'stores': [
      {'id': 's1', 'ad': 'Merkez Şube', 'tenant_id': 't1'},
    ],
    'active_periods': [
      {
        'id': 'p1',
        'ad': _donem,
        'tenant_id': 't1',
        'starts_on': '2026-09-01',
        'ends_on': '2027-01-31',
      },
    ],
    'consent_ok': true,
  }),
  aktifRol: rol,
  storeId: 's1',
  periodId: 'p1',
);

final _bildirimler = [
  bildirim('Yeşiltepe Anadolu Lisesi yeni talep açtı', id: 'b1'),
  bildirim('Sipariş onaya düştü', id: 'b2'),
];

final _bugun = BugunOzeti(
  portfoyCari: 38,
  bekleyenTalep: 6,
  gecikmisTalep: 2,
  hazirSiparis: 3,
  borcluCari: 9,
  acikAlacak: 186450,
  acikKonsinyeCari: 2,
  donemCiro: 412800,
  donemTahsilat: 298350,
  donemAd: _donem,
  gecikmisTalepler: [
    GecikmisTalep(
      id: 't1',
      unvan: 'Karşıyaka Ortaokulu',
      createdAt: DateTime(2026, 10, 28, 10),
      kalem: 4,
      saat: 98,
    ),
    GecikmisTalep(
      id: 't2',
      unvan: 'Gökkuşağı Kurs Merkezi',
      createdAt: DateTime(2026, 10, 30, 15),
      kalem: 2,
      saat: 41,
    ),
  ],
  hatirlatmalar: const [
    TahsilatHatirlatmasi(
      id: 'c1',
      unvan: 'Yeşiltepe Anadolu Lisesi',
      bakiye: 86450,
      gun: 47,
    ),
    TahsilatHatirlatmasi(
      id: 'c2',
      unvan: 'Çınaraltı Koleji',
      bakiye: 41200,
      gun: 22,
    ),
    TahsilatHatirlatmasi(
      id: 'c3',
      unvan: 'Sahil Fen Lisesi',
      bakiye: 18750,
      gun: 9,
    ),
  ],
);

final _acikZiyaret = AcikZiyaret(
  id: 'v1',
  kurumId: 'k2',
  kurumAd: 'Bahçelievler Fen Lisesi',
  ilce: 'Çankaya',
  dakika: 24,
  girisSaati: DateTime.now().subtract(const Duration(minutes: 24)),
  cikti: const ZiyaretCikti(talep: 1, tahsilat: 1, toplam: 2),
);

final _rota = Rota(
  planlanan: 5,
  tamamlanan: 1,
  duraklar: [
    durak(
      'Yeşiltepe Anadolu Lisesi',
      kurumId: 'k1',
      planId: 'pl1',
      durum: 'ziyaret_edildi',
      sonZiyaret: DateTime(2026, 10, 30),
    ),
    durak(
      'Bahçelievler Fen Lisesi',
      kurumId: 'k2',
      planId: 'pl2',
      talep: 2,
      sonZiyaret: DateTime(2026, 10, 14),
    ),
    durak(
      'Karşıyaka Ortaokulu',
      kurumId: 'k3',
      planId: 'pl3',
      borc: 12400,
      talep: 1,
      sonZiyaret: DateTime(2026, 10, 9),
    ),
    durak(
      'Çınaraltı Koleji',
      kurumId: 'k4',
      planId: 'pl4',
      borc: 41200,
      sonZiyaret: DateTime(2026, 10, 2),
    ),
    durak('Gökkuşağı Kurs Merkezi', kurumId: 'k5', planId: 'pl5'),
  ],
);

final _yaklasanDenemeler = [
  Deneme(
    id: 'd1',
    ad: 'LGS Türkiye Geneli Deneme 2',
    turu: 'turkiye_geneli',
    stokTarihi: DateTime(2026, 11, 3),
    yayinevi: 'Mavi Defter Yayınları',
    duzey: '8. SINIF',
    sinif: const [8],
    gun: 2,
  ),
  Deneme(
    id: 'd2',
    ad: 'TYT Deneme Seti · 4. Kitapçık',
    turu: 'takvim',
    stokTarihi: DateTime(2026, 11, 5),
    yayinevi: 'Kalem Ucu Yayınları',
    duzey: '12. SINIF',
    sinif: const [12],
    gun: 4,
  ),
];

const _panel = PanelOzeti(
  bekleyenTalep: 14,
  gecikmisTalep: 3,
  onayBekleyenSiparis: 2,
  hazirlanacakSiparis: 7,
  acikAlacak: 1284600,
  borcluCari: 47,
  gecikmisBorc: 312400,
  donemCiro: 2846300,
  donemTahsilat: 1962750,
  portfoydekiCek: 185000,
  huni: Huni(acilan: 126, kararaBaglanan: 108, reddedilen: 9, siparise: 94),
  pazarlamacilar: [
    PanelPazarlamaci(
      userId: 'u2',
      adSoyad: 'Emre Aydın',
      cariSayisi: 38,
      acikTalep: 6,
    ),
    PanelPazarlamaci(
      userId: 'u3',
      adSoyad: 'Zeynep Koç',
      cariSayisi: 41,
      acikTalep: 5,
    ),
    PanelPazarlamaci(
      userId: 'u4',
      adSoyad: 'Burak Şen',
      cariSayisi: 29,
      acikTalep: 3,
    ),
    PanelPazarlamaci(userId: 'u5', adSoyad: 'Elif Tunç', cariSayisi: 24),
  ],
  donemAd: _donem,
);

SiparisKalemi _kalem(
  String id,
  String ad,
  String yayinevi, {
  required int adet,
  required double fiyat,
  int sevk = 0,
}) => SiparisKalemi(
  id: id,
  urunId: 'p$id',
  ad: ad,
  yayinevi: yayinevi,
  adet: adet,
  birimFiyat: fiyat,
  iskontoOrani: 0.20,
  satirTutari: adet * fiyat * 0.80,
  sevkEdilen: sevk,
  backorder: adet - sevk,
);

final _siparisKalemleri = [
  _kalem(
    '1',
    'LGS Matematik Soru Bankası',
    'Mavi Defter Yayınları',
    adet: 120,
    fiyat: 245,
    sevk: 120,
  ),
  _kalem(
    '2',
    'LGS Fen Bilimleri Konu Anlatımı',
    'Mavi Defter Yayınları',
    adet: 120,
    fiyat: 189,
    sevk: 120,
  ),
  _kalem(
    '3',
    '8. Sınıf Türkçe Paragraf Kampı',
    'Kalem Ucu Yayınları',
    adet: 60,
    fiyat: 320,
    sevk: 60,
  ),
  _kalem(
    '4',
    'LGS 5\'li Deneme Seti',
    'Kalem Ucu Yayınları',
    adet: 200,
    fiyat: 95,
    sevk: 120,
  ),
  _kalem(
    '5',
    'İnkılap Tarihi Fasikül Seti',
    'Yıldızkent Yayınları',
    adet: 45,
    fiyat: 410,
  ),
];

final _siparis = SiparisDetay(
  id: 'o1',
  durum: 'kismi_teslim',
  tip: 'satis',
  createdAt: DateTime(2026, 10, 27, 11, 20),
  cariId: 'c1',
  cariUnvan: 'Yeşiltepe Lisesi Kurumsal',
  kurumAd: 'Yeşiltepe Lisesi',
  olusturan: 'Emre Aydın',
  hazirlayan: 'Kerem Polat',
  hazirlikBitti: DateTime(2026, 10, 28, 16, 45),
  toplam: _siparisKalemleri.fold(0.0, (t, k) => t + k.satirTutari),
  kalemler: _siparisKalemleri,
);

// Kurumsal carinin unvanı "<kurum> Kurumsal" — aynı kurumda öğretmen carileri
// de var (K7), ikisi adından ayırt edilir.
final _cari = CariDetay(
  id: 'c1',
  tip: 'kurum',
  unvan: 'Sahil Koleji Kurumsal',
  durum: 'aktif',
  kurumId: 'k6',
  kurumAd: 'Sahil Koleji',
  ilce: 'Karşıyaka',
  discountTier: 'A',
  creditLimit: 150000,
  bakiye: 86450,
  risk: 118450,
  acikKonsinye: 120,
  kisiAd: 'Hakan Çelik · müdür yardımcısı',
  portfoy: const [
    PortfoySatiri(userId: 'u2', adSoyad: 'Emre Aydın', periodAd: _donem),
  ],
  kardesCariler: const [
    CariOzet(
      id: 'c7',
      tip: 'ogretmen',
      unvan: 'Ayşe Demir',
      durum: 'aktif',
      institutionId: 'k1',
      bakiye: 4350,
    ),
    CariOzet(
      id: 'c8',
      tip: 'ogretmen',
      unvan: 'Murat Yılmaz',
      durum: 'aktif',
      institutionId: 'k1',
    ),
  ],
);
