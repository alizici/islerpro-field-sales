import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:islerpro/core/auth/session.dart';
import 'package:islerpro/core/test_keys.dart';
import 'package:islerpro/data/local/yerel_saglayici.dart';
import 'package:islerpro/data/repositories/siparis_repository.dart';
import 'package:islerpro/data/repositories/talep_repository.dart';
import 'package:islerpro/features/dashboard/presentation/bugun_ekrani.dart';
import 'package:islerpro/features/dashboard/presentation/panel_ekrani.dart';

import 'sahte_depolar.dart';

/// Açılış ekranları. Bunlar bir kullanıcının uygulamayı açtığında GÖRDÜĞÜ
/// ilk şey; boş kalırlarsa gerisi çalışsa bile uygulama boş görünür.
void main() {
  Future<SahteSiparisRepo> ac(WidgetTester t, Widget w,
      {SahteSiparisRepo? repo, AppRole rol = AppRole.isletmeSahibi}) async {
    final r = repo ?? SahteSiparisRepo();
    t.view.physicalSize = const Size(1000, 2400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [
        siparisRepositoryProvider.overrideWithValue(r),
        talepRepositoryProvider.overrideWithValue(SahteTalepRepo()),
        sessionProvider.overrideWithValue(testOturumu(rol: rol)),
        // Widget testinde dosya sistemi yok; yerel veritabanı
        // web'deki gibi kapalı çalışır (bkz. ac_stub.dart).
        yerelDbProvider.overrideWithValue(null),
      ],
      child: MaterialApp(home: w),
    ));
    await t.pumpAndSettle();
    return r;
  }

  group('Panel · sahip', () {
    testWidgets('bekleyen işler sayılarla ve gerekçeleriyle listelenir',
        (t) async {
      await ac(t, const PanelEkrani(),
          repo: SahteSiparisRepo()..panelOzeti = const PanelOzeti(
              bekleyenTalep: 12, gecikmisTalep: 3, onayBekleyenSiparis: 2,
              hazirlanacakSiparis: 5, portfoysuzCari: 4));

      expect(find.byKey(K.panelKuyruk), findsOneWidget);
      expect(find.textContaining('Acil bakılması gerekenler var'), findsOneWidget);
      // V7 · gecikmişin sebebi yazılı
      expect(find.textContaining('24 saattir dokunulmadı'), findsOneWidget);
      // K25/K11 · onaya düşme sebebi yazılı
      expect(find.textContaining('iskonto tavanı veya kredi limiti'),
          findsOneWidget);
      // W-2 · portföysüzün sonucu yazılı
      expect(find.textContaining('kimsenin kutusuna düşmez'), findsOneWidget);
    });

    testWidgets('yepyeni dükkanda NEREDEN BAŞLANACAĞI yazar', (t) async {
      await ac(t, const PanelEkrani());

      // Yeni dükkanda her ekran boş; on iki boş ekranı tek tek gezip
      // duran bir kullanıcı uygulamayı öğrenemiyor.
      expect(find.textContaining('Dükkanı kurmaya başla'), findsOneWidget);
      expect(find.textContaining('Kurumları ekle'), findsOneWidget);
      expect(find.textContaining('Cari aç'), findsOneWidget);
    });

    testWidgets('iş görünce rehber KENDİLİĞİNDEN gider', (t) async {
      await ac(t, const PanelEkrani(),
          repo: SahteSiparisRepo()..panelOzeti = const PanelOzeti(
              donemCiro: 12000, bekleyenTalep: 2));

      // Kalıcı bir "gördüm" işareti tutmuyoruz: gösterilme şartı verinin
      // kendisi. Kapatılabilen bir rehber, yanlışlıkla kapatılıp bir daha
      // bulunamayan rehberdir.
      expect(find.textContaining('Dükkanı kurmaya başla'), findsNothing);
    });

    testWidgets('bekleyen iş yoksa akışta olduğu söylenir', (t) async {
      await ac(t, const PanelEkrani());
      expect(find.textContaining('Her şey akışında'), findsOneWidget);
    });

    testWidgets('K26 · cironun teslimattan okunduğu yazılı', (t) async {
      await ac(t, const PanelEkrani(),
          repo: SahteSiparisRepo()..panelOzeti = const PanelOzeti(
              donemCiro: 125000, donemTahsilat: 90000));

      expect(find.byKey(K.panelPara), findsOneWidget);
      expect(find.textContaining('teslimattan okunur, siparişten değil'),
          findsOneWidget);
      expect(find.textContaining('125.000,00'), findsOneWidget);
    });

    testWidgets('K7 · açık alacak DÜKKANIN alacağı diye etiketli', (t) async {
      await ac(t, const PanelEkrani(),
          repo: SahteSiparisRepo()..panelOzeti = const PanelOzeti(
              acikAlacak: 48000, borcluCari: 12));

      expect(find.textContaining('dükkanın toplam alacağı'), findsOneWidget,
          reason: 'bu sayı bir kurumun borcu değildir');
      expect(find.textContaining('12 cari'), findsOneWidget);
    });

    testWidgets('K11 · portföydeki çek ödeme vaadi diye açıklanır', (t) async {
      await ac(t, const PanelEkrani(),
          repo: SahteSiparisRepo()..panelOzeti = const PanelOzeti(
              portfoydekiCek: 15000));

      expect(find.textContaining('ödeme değil ödeme vaadi'), findsOneWidget);
      expect(find.textContaining('15.000,00'), findsOneWidget);
    });

    testWidgets('K37 · talep hunisi dönüşüm oranıyla gösterilir', (t) async {
      await ac(t, const PanelEkrani(),
          repo: SahteSiparisRepo()..panelOzeti = const PanelOzeti(
              huni: Huni(acilan: 100, kararaBaglanan: 80, reddedilen: 12,
                  siparise: 68)));

      expect(find.byKey(K.panelHuni), findsOneWidget);
      expect(find.textContaining('Dönüşüm %68'), findsOneWidget);
      expect(find.text('Siparişe dönen'), findsOneWidget);
      expect(find.text('Tamamen reddedilen'), findsOneWidget);
    });

    testWidgets('talep yoksa huni boş durum gösterir', (t) async {
      await ac(t, const PanelEkrani());
      expect(find.textContaining('henüz talep yok'), findsOneWidget);
    });
  });

  group('Bugün · pazarlamacı', () {
    testWidgets('yalnızca kendi portföyünü gösterir', (t) async {
      await ac(t, const BugunEkrani(), rol: AppRole.pazarlamaci,
          repo: SahteSiparisRepo()..bugunOzeti = const BugunOzeti(
              portfoyCari: 37, donemCiro: 42000, donemTahsilat: 31000));

      expect(find.byKey(K.bugunOzet), findsOneWidget);
      expect(find.textContaining('37 cari'), findsOneWidget);
      expect(find.textContaining('42.000,00'), findsOneWidget);
    });

    testWidgets('işi yoksa açıkça söylenir', (t) async {
      await ac(t, const BugunEkrani(), rol: AppRole.pazarlamaci,
          repo: SahteSiparisRepo()..bugunOzeti = const BugunOzeti(
              portfoyCari: 12));
      expect(find.textContaining('Bekleyen işin yok'), findsOneWidget);
    });

    testWidgets('portföyü boşsa BEKLEMESİ gerektiği yazar', (t) async {
      await ac(t, const BugunEkrani(), rol: AppRole.pazarlamaci);

      expect(find.textContaining('Portföyün henüz boş'), findsOneWidget);
      // Portföyü pazarlamacı kendisi atayamıyor. Sahte bir "başla" düğmesi
      // koymak, tıklayıp hiçbir şey olmadığını görmekten beter.
      expect(find.textContaining('sahibinin sana cari ataması'), findsOneWidget);
    });

    testWidgets('portföyü varsa rehber çıkmaz', (t) async {
      await ac(t, const BugunEkrani(), rol: AppRole.pazarlamaci,
          repo: SahteSiparisRepo()..bugunOzeti = const BugunOzeti(
              portfoyCari: 37));
      expect(find.textContaining('Portföyün henüz boş'), findsNothing);
    });

    testWidgets('V7 · gecikmiş talepler gün sayısıyla listelenir', (t) async {
      await ac(t, const BugunEkrani(), rol: AppRole.pazarlamaci,
          repo: SahteSiparisRepo()..bugunOzeti = BugunOzeti(
              gecikmisTalep: 2,
              gecikmisTalepler: [
                GecikmisTalep(id: 't1', unvan: 'Y Lisesi',
                    createdAt: DateTime(2026, 8, 20), kalem: 3, saat: 96),
                GecikmisTalep(id: 't2', unvan: 'X Ortaokulu',
                    createdAt: DateTime(2026, 8, 25), kalem: 1, saat: 30),
              ]));

      expect(find.byKey(K.bugunGecikmis), findsOneWidget);
      expect(find.textContaining('sahibe bildirilir'), findsOneWidget);
      expect(find.text('4 gün'), findsOneWidget);
      expect(find.text('1 gün'), findsOneWidget);
    });

    testWidgets('tahsilat hatırlatmaları borç yaşıyla gelir', (t) async {
      await ac(t, const BugunEkrani(), rol: AppRole.pazarlamaci,
          repo: SahteSiparisRepo()..bugunOzeti = const BugunOzeti(
              borcluCari: 1, acikAlacak: 240,
              hatirlatmalar: [
                TahsilatHatirlatmasi(id: 'c1', unvan: 'Kısmi Okul',
                    bakiye: 240, gun: 45),
              ]));

      expect(find.byKey(K.bugunTahsilat), findsOneWidget);
      expect(find.textContaining('45 gündür açık'), findsOneWidget);
      expect(find.textContaining('240,00'), findsWidgets);
    });

    testWidgets('K45 · açık konsinye kapatılması hatırlatılır', (t) async {
      await ac(t, const BugunEkrani(), rol: AppRole.pazarlamaci,
          repo: SahteSiparisRepo()..bugunOzeti = const BugunOzeti(
              acikKonsinyeCari: 3));

      expect(find.textContaining('satıldı/iade kaydı girilmeli'), findsOneWidget);
    });
  });
}
