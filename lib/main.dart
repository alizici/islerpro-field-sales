import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/network/supabase.dart';
import 'core/router/app_router.dart';
import 'core/security/oturum_kilidi.dart';
import 'core/theme/app_theme.dart';
import 'data/local/yerel_saglayici.dart';
import 'features/onboarding/presentation/yapilandirma_ekrani.dart';
import 'features/security/presentation/kilit_ekrani.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('tr_TR');
  await SupabaseConfig.init();
  // Anahtarlar verilmeden çalıştırılırsa uygulamayı hiç kurma: aksi hâlde
  // supabaseProvider Supabase.instance'a uzanır ve okunmaz bir yığın izi
  // üretir. Ne eksik olduğunu söyleyen ekranı göster.
  runApp(SupabaseConfig.yapilandirildi
      ? ProviderScope(
          overrides: [kilitKapisiProvider.overrideWith(_kilitKapisi)],
          child: const IslerProApp())
      : const _YapilandirmaUygulamasi());
}

/// K42 · Kilit kapısı oturum kapatmayı ve yerel veri silmeyi bilir; ikisini
/// de kendi yapmaz, buradan alır. Böylece kilit mantığı test edilirken
/// Supabase'e ve dosya sistemine ihtiyaç duymuyor.
KilitKapisi _kilitKapisi(Ref ref) => KilitKapisi(
      depo: const KasaDeposu(),
      dogrulayici: CihazDogrulayici(),
      oturumuKapat: () async {
        // 30 gün hareketsizlik: oturum düşer VE yerel kopya silinir. Cihaz bir
        // yerde unutulmuşsa üzerinde cari adı, bakiye ve telefon kalmasın (K44).
        await ref.read(yerelDbProvider)?.herSeyiSil();
        await ref.read(supabaseProvider).auth.signOut();
      });

class IslerProApp extends ConsumerWidget {
  const IslerProApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'İşlerPro',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      routerConfig: ref.watch(routerProvider),
      builder: (_, child) => KilitKapisiWidget(child: child ?? const SizedBox()),
      locale: const Locale('tr', 'TR'),
      supportedLocales: const [Locale('tr', 'TR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}

class _YapilandirmaUygulamasi extends StatelessWidget {
  const _YapilandirmaUygulamasi();

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'İşlerPro',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        locale: const Locale('tr', 'TR'),
        supportedLocales: const [Locale('tr', 'TR')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const YapilandirmaEksikEkrani(),
      );
}
