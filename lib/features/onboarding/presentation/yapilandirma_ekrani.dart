import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/network/supabase.dart';
import '../../../core/theme/tokens.dart';

/// Supabase anahtarları `--dart-define` ile verilir; kaynak koda gömülmez (K1).
/// Anahtarlar olmadan çalıştırılırsa uygulama ÇÖKMEK yerine ne eksik olduğunu
/// ve nasıl çalıştırılacağını söyler.
///
/// Bu ekran olmadan `Supabase.instance` çağrısı 900 satırlık bir yığın izi
/// üretiyordu — hata doğruydu ama okunmuyordu.
class YapilandirmaEksikEkrani extends StatelessWidget {
  const YapilandirmaEksikEkrani({super.key});

  /// Anahtarlar `.env`den okunur — Flutter `KEY=değer` satırlarını
  /// `--dart-define-from-file` ile doğrudan alıyor. VS Code'da F5 aynı şeyi
  /// yapar; bu komut terminalden çalıştıranlar için.
  static const _komut =
      'flutter run --dart-define-from-file=.env --dart-define=DEV_LOGIN=true';

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final eksik = <String>[
      if (SupabaseConfig.url.isEmpty) 'SUPABASE_URL',
      if (SupabaseConfig.publishableKey.isEmpty) 'SUPABASE_ANON_KEY',
    ];

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(T.s5),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.settings_ethernet, size: 34, color: s.outline),
                const SizedBox(height: T.s4),
                Text('Sunucu yapılandırması eksik',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: T.s2),
                Text(
                  'Supabase anahtarları kaynak koda gömülmez; derleme sırasında '
                  '--dart-define ile verilir. Şu değerler eksik:',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: T.s3),
                for (final e in eksik)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(children: [
                      Icon(Icons.close, size: 14, color: s.error),
                      const SizedBox(width: T.s2),
                      Text(e, style: TextStyle(
                          fontFamily: T.fontMono, fontSize: 13, color: s.error)),
                    ]),
                  ),
                const SizedBox(height: T.s4),
                Text('Nasıl çalıştırılır',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: T.s2),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(T.s3),
                  decoration: BoxDecoration(
                    color: s.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(T.rKucuk),
                  ),
                  child: Row(children: [
                    Expanded(
                      child: SelectableText(_komut,
                          style: const TextStyle(
                              fontFamily: T.fontMono, fontSize: 12)),
                    ),
                    IconButton(
                      tooltip: 'Kopyala',
                      icon: const Icon(Icons.copy, size: 16),
                      onPressed: () =>
                          Clipboard.setData(const ClipboardData(text: _komut)),
                    ),
                  ]),
                ),
                const SizedBox(height: T.s3),
                Text(
                  '.env yoksa .env.example dosyasını kopyalayıp değerleri '
                  'doldur (Supabase → Project Settings → API). VS Code\'ta '
                  'cihazı seçip F5\'e basman yeterli: yapılandırmalar '
                  '.vscode/launch.json içinde hazır.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
