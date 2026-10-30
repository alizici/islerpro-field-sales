import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/session.dart';
import '../../features/auth/presentation/giris_ekrani.dart';
import '../../features/dashboard/presentation/bugun_ekrani.dart';
import '../../features/dashboard/presentation/kabuk.dart';
import '../../features/dashboard/presentation/panel_ekrani.dart';
import '../../features/dashboard/presentation/yer_tutucu.dart';
import '../../features/onboarding/presentation/kurulum_ekrani.dart';
import '../../features/catalog/presentation/katalog_ekrani.dart';
import '../../features/accounts/presentation/cariler_ekrani.dart';
import '../../features/collections/presentation/tahsilat_ekrani.dart';
import '../../features/import/presentation/aktarma_ekrani.dart';
import '../../features/orders/presentation/siparisler_ekrani.dart';
import '../../features/reports/presentation/raporlar_ekrani.dart';
import '../../features/requests/presentation/talepler_ekrani.dart';
import '../../features/institutions/presentation/kurumlar_ekrani.dart';
import '../../features/onboarding/presentation/kvkk_ekrani.dart';
import '../../features/commercial/presentation/konsinye_ekrani.dart';
import '../../features/exams/presentation/deneme_takvimi_ekrani.dart';
import '../../features/exams/presentation/programlar_ekrani.dart';
import '../../features/commercial/presentation/vade_takvimi_ekrani.dart';
import '../../features/sync/presentation/senkron_ekrani.dart';
import '../../features/visits/presentation/rota_ekrani.dart';
import '../../features/settings/presentation/ayarlar_ekrani.dart';

/// Rol bazlı gezinme hedefi.
/// Menüdeki öbek. 15 hedefi düz bir listeye dökmek, kullanıcıyı her seferinde
/// baştan okumaya zorluyordu; öbekler aramayı yön bulmaya çevirir.
enum NavObek {
  gunluk('GÜNLÜK'),
  satis('SATIŞ'),
  para('PARA'),
  deneme('DENEME'),
  katalog('KATALOG'),
  arac('ARAÇLAR');

  const NavObek(this.ad);
  final String ad;
}

class NavHedef {
  const NavHedef(
    this.yol,
    this.etiket,
    this.ikon,
    this.roller, [
    this.obek = NavObek.gunluk,
    this.doluIkon,
  ]);
  final String yol;
  final String etiket;
  final IconData ikon;
  final Set<AppRole> roller;
  final NavObek obek;

  /// Sekme seçiliyken kullanılan DOLU ikon. iOS tab bar'da seçimi anlatan
  /// asıl sinyal budur — sembolün içi dolar. Renk tek başına yetmez: renk
  /// körlüğünde iki sekme aynı görünür, dolu/boş ayrımı ise biçimdir.
  final IconData? doluIkon;
}

/// Her rolün gördüğü ekranlar (§5 Ekranlar).
const navHedefleri = <NavHedef>[
  NavHedef(
    '/bugun',
    'Bugün',
    Icons.today_outlined,
    {AppRole.pazarlamaci},
    NavObek.gunluk,
    Icons.today,
  ),
  NavHedef(
    '/rota',
    'Rota',
    Icons.route_outlined,
    {AppRole.pazarlamaci},
    NavObek.gunluk,
    Icons.route,
  ), // K10
  NavHedef(
    '/panel',
    'Panel',
    Icons.dashboard_outlined,
    {AppRole.isletmeSahibi, AppRole.dukkanMuduru},
    NavObek.gunluk,
    Icons.dashboard,
  ),
  NavHedef(
    '/kurumlar',
    'Kurumlar',
    Icons.school_outlined,
    {AppRole.pazarlamaci, AppRole.isletmeSahibi, AppRole.dukkanMuduru},
    NavObek.gunluk,
    Icons.school,
  ),
  NavHedef(
    '/cariler',
    'Cariler',
    Icons.account_balance_wallet_outlined,
    {AppRole.pazarlamaci, AppRole.isletmeSahibi, AppRole.dukkanMuduru},
    NavObek.gunluk,
    Icons.account_balance_wallet,
  ),
  NavHedef(
    '/talepler',
    'Talepler',
    Icons.inbox_outlined,
    {
      AppRole.pazarlamaci,
      AppRole.isletmeSahibi,
      AppRole.dukkanMuduru,
      AppRole.ogretmen,
    },
    NavObek.gunluk,
    Icons.inbox,
  ),
  NavHedef(
    '/hazirlik',
    'Hazırlık',
    Icons.inventory_2_outlined,
    {AppRole.hazirlik, AppRole.dukkanMuduru, AppRole.isletmeSahibi},
    NavObek.satis,
    Icons.inventory_2,
  ), // K46
  NavHedef(
    '/siparisler',
    'Siparişler',
    Icons.receipt_long_outlined,
    {AppRole.pazarlamaci, AppRole.isletmeSahibi, AppRole.dukkanMuduru},
    NavObek.satis,
    Icons.receipt_long,
  ),
  NavHedef(
    '/konsinye',
    'Konsinye',
    Icons.assignment_return_outlined,
    {AppRole.pazarlamaci, AppRole.isletmeSahibi, AppRole.dukkanMuduru},
    NavObek.satis,
    Icons.assignment_return,
  ), // C-9
  NavHedef(
    '/tahsilat',
    'Tahsilat',
    Icons.payments_outlined,
    {AppRole.pazarlamaci, AppRole.isletmeSahibi, AppRole.dukkanMuduru},
    NavObek.para,
    Icons.payments,
  ),
  NavHedef(
    '/vadeler',
    'Vadeler',
    Icons.event_note_outlined,
    {AppRole.isletmeSahibi, AppRole.dukkanMuduru},
    NavObek.para,
    Icons.event_note,
  ), // K11
  NavHedef(
    '/deneme-takvimi',
    'Deneme Takvimi',
    Icons.calendar_month_outlined,
    {
      AppRole.pazarlamaci,
      AppRole.isletmeSahibi,
      AppRole.dukkanMuduru,
      AppRole.ogretmen,
    },
    NavObek.deneme,
    Icons.calendar_month,
  ),
  NavHedef(
    '/deneme-programlari',
    'Programlar',
    Icons.event_repeat_outlined,
    {AppRole.pazarlamaci, AppRole.isletmeSahibi, AppRole.dukkanMuduru},
    NavObek.deneme,
    Icons.event_repeat,
  ), // C-3
  NavHedef(
    '/katalog',
    'Katalog',
    Icons.menu_book_outlined,
    {AppRole.isletmeSahibi, AppRole.dukkanMuduru},
    NavObek.katalog,
    Icons.menu_book,
  ),
  NavHedef(
    '/aktarma',
    'Toplu Aktarma',
    Icons.upload_file_outlined,
    {AppRole.isletmeSahibi, AppRole.dukkanMuduru},
    NavObek.katalog,
    Icons.upload_file,
  ), // K49
  NavHedef(
    '/raporlar',
    'Raporlar',
    Icons.insights_outlined,
    {AppRole.isletmeSahibi, AppRole.dukkanMuduru},
    NavObek.para,
    Icons.insights,
  ), // K50
  // SIRA ÖNEMLİ: rolün açılış ekranı bu listenin İLK öğesidir. Senkron bir
  // araç ekranıdır, kimsenin günü onunla başlamaz — Ayarlar'ın yanına.
  NavHedef(
    '/senkron',
    'Senkron',
    Icons.sync_outlined,
    {AppRole.pazarlamaci, AppRole.isletmeSahibi, AppRole.dukkanMuduru},
    NavObek.arac,
    Icons.sync,
  ), // K43
  NavHedef(
    '/ayarlar',
    'Ayarlar',
    Icons.settings_outlined,
    {
      AppRole.isletmeSahibi,
      AppRole.dukkanMuduru,
      AppRole.pazarlamaci,
      AppRole.ogretmen,
    },
    NavObek.arac,
    Icons.settings,
  ),
];

/// Çubuğun İLK DÖRT sekmesi role göre.
///
/// Sıra ekranların önem sırası değil, o rolün GÜNLÜK dokunduğu yerler.
/// Pazarlamacının çubuğunda "Kurumlar" duruyordu — okunan, üstünde iş
/// yapılmayan bir dizin; gelen kutusu olan "Talepler" ise taşma menüsünde,
/// üstündeki rozetle birlikte gizliydi. Bir işin bekliyorsa onu görmek için
/// menü açman gerekmemeli.
const _sekmeOnceligi = <AppRole, List<String>>{
  AppRole.pazarlamaci: ['/bugun', '/rota', '/talepler', '/cariler'],
  AppRole.isletmeSahibi: ['/panel', '/talepler', '/siparisler', '/cariler'],
  AppRole.dukkanMuduru: ['/panel', '/talepler', '/hazirlik', '/cariler'],
};

List<NavHedef> hedeflerFor(AppRole rol) {
  final hepsi = navHedefleri.where((h) => h.roller.contains(rol)).toList();
  final oncelik = _sekmeOnceligi[rol];
  if (oncelik == null) return hepsi;

  // Öncelikli olanlar başa, gerisi tanım sırasında. Öncelik listesinde olup
  // da rolün göremediği bir yol varsa sessizce atlanır: yetki listesi tek
  // doğru kaynak, sıralama onu genişletemez.
  final basta = [
    for (final y in oncelik)
      ...hepsi.where((h) => h.yol == y),
  ];
  return [...basta, ...hepsi.where((h) => !oncelik.contains(h.yol))];
}

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/giris',
    refreshListenable: _SessionListenable(ref),
    redirect: (context, state) {
      final st = ref.read(sessionStateProvider);
      final yol = state.matchedLocation;
      final girisSayfasinda = yol == '/giris';
      final kurulumSayfasinda = yol == '/kurulum';

      // Giriş yapılmadı
      if (!st.girisYapildi) return girisSayfasinda ? null : '/giris';

      // Giriş yapıldı ama henüz bir işletme/kurum bağı yok → kurulum
      // (öğretmen için: davet kodu girme ekranı)
      if (st.kurulumGerekli || st.onayBekliyor) {
        return kurulumSayfasinda ? null : '/kurulum';
      }

      final oturum = st.session;
      if (oturum == null) return kurulumSayfasinda ? null : '/kurulum';

      // K44 · Aydınlatma metni onaylanmadan içeri girilmez
      if (st.data?.consentOk == false) {
        return yol == '/kvkk' ? null : '/kvkk';
      }
      if (yol == '/kvkk') return hedeflerFor(oturum.aktifRol).first.yol;
      if (girisSayfasinda || kurulumSayfasinda) {
        return hedeflerFor(oturum.aktifRol).first.yol;
      }

      // Rol guard: kullanıcının rolünde olmayan yola erişim engellenir.
      final hedef = navHedefleri
          .where((h) => yol.startsWith(h.yol))
          .firstOrNull;
      if (hedef != null && !hedef.roller.contains(oturum.aktifRol)) {
        return hedeflerFor(oturum.aktifRol).first.yol;
      }
      return null;
    },
    routes: [
      GoRoute(path: '/giris', builder: (_, _) => const GirisEkrani()),
      GoRoute(path: '/kurulum', builder: (_, _) => const KurulumEkrani()),
      GoRoute(path: '/kvkk', builder: (_, _) => const KvkkEkrani()),
      ShellRoute(
        builder: (context, state, child) => Kabuk(child: child),
        routes: [
          for (final h in navHedefleri)
            GoRoute(
              path: h.yol,
              builder: (_, _) => switch (h.yol) {
                '/ayarlar' => const AyarlarEkrani(),
                '/bugun' => const BugunEkrani(),
                '/rota' => const RotaEkrani(),
                '/senkron' => const SenkronEkrani(),
                '/konsinye' => const KonsinyeEkrani(),
                '/vadeler' => const VadeTakvimiEkrani(),
                '/deneme-takvimi' => const DenemeTakvimiEkrani(),
                '/deneme-programlari' => const ProgramlarEkrani(),
                '/panel' => const PanelEkrani(),
                '/kurumlar' => const KurumlarEkrani(),
                '/cariler' => const CarilerEkrani(),
                '/talepler' => const TaleplerEkrani(),
                '/siparisler' => const SiparislerEkrani(),
                '/hazirlik' => const SiparislerEkrani(hazirlikKutusu: true),
                '/tahsilat' => const TahsilatEkrani(),
                '/raporlar' => const RaporlarEkrani(),
                '/katalog' => const KatalogEkrani(),
                '/aktarma' => const AktarmaEkrani(),
                _ => YerTutucuEkran(baslik: h.etiket, ikon: h.ikon),
              },
            ),
        ],
      ),
    ],
  );
});

class _SessionListenable extends ChangeNotifier {
  _SessionListenable(Ref ref) {
    ref.listen(sessionStateProvider, (_, _) => notifyListeners());
  }
}
