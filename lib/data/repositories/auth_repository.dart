import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/network/supabase.dart';
import '../models/session_data.dart';

class AuthRepository {
  AuthRepository(this._db);
  final SupabaseClient _db;

  User? get currentUser => _db.auth.currentUser;
  Stream<AuthState> get changes => _db.auth.onAuthStateChange;

  // ── Giriş ────────────────────────────────────────────────────────────────
  /// K3'e göre birincil yol telefon OTP'dir. SMS sağlayıcısı bağlanana kadar
  /// e-posta ile çalışılır; arayüz ikisini de destekler.
  Future<void> otpGonder({String? telefon, String? eposta}) async {
    if (telefon != null) {
      await _db.auth.signInWithOtp(phone: telefon);
    } else {
      await _db.auth.signInWithOtp(email: eposta);
    }
  }

  Future<void> otpDogrula({
    String? telefon,
    String? eposta,
    required String kod,
  }) async {
    await _db.auth.verifyOTP(
      type: telefon != null ? OtpType.sms : OtpType.email,
      token: kod,
      phone: telefon,
      email: eposta,
    );
  }

  Future<void> parolaIleGiris(String eposta, String parola) =>
      _db.auth.signInWithPassword(email: eposta, password: parola);

  Future<void> cikis() => _db.auth.signOut();

  // ── Oturum ───────────────────────────────────────────────────────────────
  /// Üyelikler, roller, dükkanlar ve aktif dönem — **tek turda**.
  Future<SessionData> oturumYukle() async {
    final r = await _db.rpc<dynamic>('my_session');
    return SessionData.fromJson((r as Map).cast<String, dynamic>());
  }

  /// İlk kullanıcı kendini var eder: işletme + dükkan + iki dönem + sahiplik.
  Future<void> kurulumYap({
    required String unvan,
    required String dukkanAd,
    String? il,
    String? ilce,
  }) async {
    await _db.rpc<dynamic>('bootstrap_tenant', params: {
      'p_unvan': unvan,
      'p_dukkan_ad': dukkanAd,
      'p_il': il,
      'p_ilce': ilce,
    });
  }

  /// K44 · Onay KİŞİSELDİR; hangi işletmeye yazılacağını istemci bilmek
  /// zorunda değil. Öğretmenin `memberships` satırı yoktur (K3) ve tenant
  /// zorunlu tutulunca rolün tamamı KVKK ekranında kilitleniyordu.
  Future<void> onayKaydet(String? tenantId, String surum) =>
      _db.rpc<dynamic>('record_consent',
          params: {'p_tenant_id': tenantId, 'p_surum': surum});

  /// K3 · Öğretmen davet kodunu kullanır → onay bekler
  Future<void> davetKullan(String kod) =>
      _db.rpc<dynamic>('accept_invite', params: {'p_kod': kod});
}

final authRepositoryProvider =
    Provider<AuthRepository>((ref) => AuthRepository(ref.watch(supabaseProvider)));
