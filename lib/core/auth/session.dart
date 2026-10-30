import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/session_data.dart';
import '../../data/repositories/auth_repository.dart';
import '../network/supabase.dart';
import '../security/oturum_kilidi.dart';

/// Uygulama rolleri — `app_role` enum'ıyla birebir (0001_enums.sql).
enum AppRole {
  platformAdmin, isletmeSahibi, dukkanMuduru, pazarlamaci, hazirlik, ogretmen;

  static AppRole? fromDb(String? v) => switch (v) {
        'platform_admin' => AppRole.platformAdmin,
        'isletme_sahibi' => AppRole.isletmeSahibi,
        'dukkan_muduru' => AppRole.dukkanMuduru,
        'pazarlamaci' => AppRole.pazarlamaci,
        'hazirlik' => AppRole.hazirlik,
        _ => null,
      };

  String get ad => switch (this) {
        AppRole.platformAdmin => 'Platform Yöneticisi',
        AppRole.isletmeSahibi => 'İşletme sahibi',
        AppRole.dukkanMuduru => 'Dükkan müdürü',
        AppRole.pazarlamaci => 'Pazarlamacı',
        AppRole.hazirlik => 'Hazırlık',
        AppRole.ogretmen => 'Öğretmen',
      };

  /// Öğretmen `memberships` değil `institution_memberships` üzerinden gelir (K19).
  bool get isletmeTarafi => this != AppRole.ogretmen;
}

/// Aktif oturumun kapsamı.
/// Bir kullanıcı birden çok rolde olabilir (K19) — [aktifRol] seçilidir.
class Session {
  const Session({
    required this.data,
    required this.aktifRol,
    this.storeId,
    this.periodId,
  });

  final SessionData data;
  final AppRole aktifRol;
  final String? storeId;
  final String? periodId;

  String get userId => data.userId;
  Set<AppRole> get roller => data.roller;
  bool get cokRollu => roller.length > 1;
  bool has(AppRole r) => roller.contains(r);

  String? get tenantId => data.memberships.isNotEmpty
      ? data.memberships.first.tenantId
      : null;

  StoreRef? get store =>
      data.stores.where((s) => s.id == storeId).firstOrNull ??
      data.stores.firstOrNull;

  PeriodRef? get period =>
      data.activePeriods.where((p) => p.id == periodId).firstOrNull ??
      data.activePeriods.firstOrNull;

  Session copyWith({AppRole? aktifRol, String? storeId, String? periodId}) =>
      Session(
        data: data,
        aktifRol: aktifRol ?? this.aktifRol,
        storeId: storeId ?? this.storeId,
        periodId: periodId ?? this.periodId,
      );

  static Session? fromData(SessionData d) {
    final roller = d.roller;
    if (roller.isEmpty) return null;
    // Öncelik: işletme rolleri, sonra öğretmen.
    final aktif = [
      AppRole.isletmeSahibi, AppRole.dukkanMuduru,
      AppRole.pazarlamaci, AppRole.hazirlik, AppRole.ogretmen,
      AppRole.platformAdmin,
    ].firstWhere(roller.contains, orElse: () => roller.first);
    return Session(
      data: d,
      aktifRol: aktif,
      storeId: d.stores.firstOrNull?.id,
      periodId: d.activePeriods.firstOrNull?.id,
    );
  }
}

/// Oturum durumu: null = giriş yapılmamış · data var ama Session null = kurulum gerekli
class SessionState {
  const SessionState({this.session, this.data, this.yukleniyor = false, this.hata});
  final Session? session;
  final SessionData? data;
  final bool yukleniyor;
  final String? hata;

  bool get girisYapildi => data != null;
  bool get kurulumGerekli => data?.kurulumGerekli ?? false;
  bool get onayBekliyor => data?.onayBekliyor ?? false;
}

/// Kullanıcının seçtiği bağlam cihazda kalır.
///
/// Seçim yalnızca bellekte tutulunca dükkan değiştirici işe yaramıyordu:
/// uygulama her açılışta ilk dükkana dönüyor ve kullanıcı her sabah aynı
/// seçimi yeniden yapıyordu. Bu bir tercih, bir sır değil — ama zaten
/// kurulu olan kasayı kullanmak yeni bir bağımlılıktan ucuz.
class BaglamTercihi {
  const BaglamTercihi(this._depo);
  final KilitDeposu _depo;

  static const _dukkan = 'tercih_dukkan';
  static const _donem = 'tercih_donem';
  static const _rol = 'tercih_rol';

  Future<void> yaz(Session o) async {
    if (o.storeId != null) await _depo.yaz(_dukkan, o.storeId!);
    if (o.periodId != null) await _depo.yaz(_donem, o.periodId!);
    await _depo.yaz(_rol, o.aktifRol.name);
  }

  /// Kayıtlı seçim ARTIK GEÇERLİ DEĞİLSE yok sayılır: dükkan pasife
  /// alınmış, rol geri çekilmiş olabilir. Geçersiz bir kimliğe yapışmak,
  /// kullanıcıyı boş bir ekranda bırakır.
  Future<Session> uygula(Session o, SessionData d) async {
    final dukkan = await _depo.oku(_dukkan);
    final donem = await _depo.oku(_donem);
    final rol = await _depo.oku(_rol);
    // `copyWith` null'ı "dokunma" olarak okur — geçersiz tercihte
    // `fromData`'nın seçtiği varsayılan olduğu gibi kalır. İstediğimiz de bu.
    return o.copyWith(
      storeId: d.stores.any((x) => x.id == dukkan) ? dukkan : null,
      periodId: d.activePeriods.any((x) => x.id == donem) ? donem : null,
      aktifRol: o.roller.where((r) => r.name == rol).firstOrNull,
    );
  }
}

final baglamTercihiProvider = Provider<BaglamTercihi>(
    (ref) => const BaglamTercihi(KasaDeposu()));

class SessionNotifier extends Notifier<SessionState> {
  @override
  SessionState build() {
    // Supabase oturum değişimlerini izle.
    //
    // Olay, widget ağacı ÇİZİLİRKEN gelebiliyor: `sessionProvider` ilk kez
    // bir `build()` içinde okunduğunda bu notifier o anda kuruluyor ve
    // Supabase'in akışı elindeki son durumu hemen veriyor. `state`'e doğrudan
    // yazmak Riverpod'da "build sırasında setState" hatası atıyor ve ekran
    // kırılıyor — sahada bunu, oturumu düşmüş bir kullanıcı uygulamayı
    // açtığında görüyoruz.
    //
    // Bu yüzden durum değişimi bir mikro-göreve alınıyor: oturum olayları
    // zaten asenkron, bir kare sonra işlenmeleri davranışı değiştirmiyor.
    ref.listen(authStateProvider, (_, next) {
      next.whenData((s) => _oturumDegisti(s.session != null));
    });
    if (SupabaseConfig.yapilandirildi &&
        ref.read(authRepositoryProvider).currentUser != null) {
      Future.microtask(yenile);
    }
    return const SessionState();
  }

  void _oturumDegisti(bool oturumVar) {
    Future.microtask(() {
      if (!ref.mounted) return;
      if (oturumVar) {
        yenile();
      } else {
        state = const SessionState();
      }
    });
  }

  Future<void> yenile() async {
    if (!ref.mounted) return;
    state = SessionState(session: state.session, data: state.data, yukleniyor: true);
    try {
      final d = await ref.read(authRepositoryProvider).oturumYukle();
      // Ağ turu sürerken provider yok edilmiş olabilir (çıkış, uygulama
      // kapanışı). Yazmadan önce her `await`'ten SONRA kontrol gerekiyor.
      if (!ref.mounted) return;
      var o = Session.fromData(d);
      // Kurulum tamamlanmamışsa oturum null döner; tercih uygulanacak bir
      // bağlam da yok.
      if (o != null) {
        o = await ref.read(baglamTercihiProvider).uygula(o, d);
        if (!ref.mounted) return;
      }
      state = SessionState(session: o, data: d);
    } catch (e) {
      if (!ref.mounted) return;
      state = SessionState(hata: e.toString());
    }
  }

  void rolDegistir(AppRole r) => _sec(state.session?.copyWith(aktifRol: r));
  void dukkanDegistir(String id) => _sec(state.session?.copyWith(storeId: id));
  void donemDegistir(String id) => _sec(state.session?.copyWith(periodId: id));

  void _sec(Session? o) {
    if (o == null) return;
    state = SessionState(session: o, data: state.data);
    // Yazma beklenmiyor: seçim hemen uygulanmalı, kalıcılık arkadan gelir.
    ref.read(baglamTercihiProvider).yaz(o);
  }

  Future<void> cikis() async {
    await ref.read(authRepositoryProvider).cikis();
    state = const SessionState();
  }
}

final sessionStateProvider =
    NotifierProvider<SessionNotifier, SessionState>(SessionNotifier.new);

/// Kısayol: yalnızca oturumun kendisiyle ilgilenen widget'lar için.
final sessionProvider = Provider<Session?>((ref) => ref.watch(sessionStateProvider).session);
