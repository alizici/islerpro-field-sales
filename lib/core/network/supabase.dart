import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase yapılandırması (K1).
/// Değerler `--dart-define` ile verilir; kaynak koda anahtar gömülmez.
abstract final class SupabaseConfig {
  static const url = String.fromEnvironment('SUPABASE_URL');
  static const publishableKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static bool get yapilandirildi => url.isNotEmpty && publishableKey.isNotEmpty;

  /// Geliştirme kolaylığı: e-posta + parola ile giriş.
  /// Yalnızca `--dart-define=DEV_LOGIN=true` ile derlenirse görünür;
  /// varsayılan `false` olduğu için sürüm derlemelerine sızmaz.
  static const devLogin = bool.fromEnvironment('DEV_LOGIN');

  static Future<void> init() async {
    if (!yapilandirildi) return;
    await Supabase.initialize(url: url, publishableKey: publishableKey);
  }
}

final supabaseProvider = Provider<SupabaseClient>((ref) => Supabase.instance.client);

/// Oturum akışı — go_router yönlendirmesi bunu dinler.
final authStateProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(supabaseProvider).auth.onAuthStateChange,
);
