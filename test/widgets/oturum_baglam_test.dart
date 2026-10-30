import 'package:flutter_test/flutter_test.dart';

import 'package:islerpro/core/auth/session.dart';
import 'package:islerpro/core/security/oturum_kilidi.dart';
import 'package:islerpro/data/models/session_data.dart';

/// Seçilen dükkan/dönem/rol cihazda KALIR.
///
/// Yalnızca bellekte tutulunca dükkan değiştirici işe yaramıyordu: uygulama
/// her açılışta ilk dükkana dönüyor, kullanıcı her sabah aynı seçimi yeniden
/// yapıyordu. Sahada bunu bir kez yaşayan bir daha o düğmeye dokunmaz.
void main() {
  SessionData veri() => SessionData.fromJson({
        'user': {'id': 'u1', 'ad_soyad': 'Mahmut Kaya', 'eposta': 'm@x.com'},
        'memberships': [
          {'tenant_id': 't1', 'tenant_unvan': 'İşler', 'role': 'isletme_sahibi',
           'status': 'aktif', 'store_id': null, 'store_ad': null},
          {'tenant_id': 't1', 'tenant_unvan': 'İşler', 'role': 'pazarlamaci',
           'status': 'aktif', 'store_id': 's1', 'store_ad': 'Merkez'},
        ],
        'institution_memberships': [],
        'stores': [
          {'id': 's1', 'ad': 'Merkez Şube', 'tenant_id': 't1'},
          {'id': 's2', 'ad': 'Karaköprü Şube', 'tenant_id': 't1'},
        ],
        'active_periods': [
          {'id': 'p1', 'ad': '1. Dönem', 'tenant_id': 't1',
           'starts_on': '2026-02-01', 'ends_on': '2026-08-31'},
          {'id': 'p2', 'ad': '2. Dönem', 'tenant_id': 't1',
           'starts_on': '2026-09-01', 'ends_on': '2027-01-31'},
        ],
        'consent_ok': true,
      });

  test('seçim yazılır ve sonraki açılışta geri gelir', () async {
    final depo = BellekDeposu();
    final tercih = BaglamTercihi(depo);
    final d = veri();

    final ilk = Session.fromData(d)!;
    expect(ilk.storeId, 's1', reason: 'varsayılan ilk dükkan');

    await tercih.yaz(ilk.copyWith(storeId: 's2', periodId: 'p2',
        aktifRol: AppRole.pazarlamaci));

    // "Yeniden açılış": sunucudan taze oturum, üstüne tercih.
    final sonra = await tercih.uygula(Session.fromData(d)!, d);
    expect(sonra.storeId, 's2');
    expect(sonra.periodId, 'p2');
    expect(sonra.aktifRol, AppRole.pazarlamaci);
  });

  test('artık var olmayan dükkan seçimi YOK SAYILIR', () async {
    final depo = BellekDeposu();
    final tercih = BaglamTercihi(depo);
    await depo.yaz('tercih_dukkan', 'silinmis-dukkan');

    final o = await tercih.uygula(Session.fromData(veri())!, veri());
    expect(o.storeId, 's1',
        reason: 'geçersiz kimliğe yapışmak kullanıcıyı boş ekranda bırakır');
  });

  test('artık sahip olunmayan rol seçimi YOK SAYILIR', () async {
    final depo = BellekDeposu();
    final tercih = BaglamTercihi(depo);
    await depo.yaz('tercih_rol', 'hazirlik');

    final o = await tercih.uygula(Session.fromData(veri())!, veri());
    expect(o.aktifRol, AppRole.isletmeSahibi);
  });

  test('hiç tercih yoksa varsayılan bozulmaz', () async {
    final tercih = BaglamTercihi(BellekDeposu());
    final o = await tercih.uygula(Session.fromData(veri())!, veri());
    expect((o.storeId, o.periodId, o.aktifRol),
        ('s1', 'p1', AppRole.isletmeSahibi));
  });
}
