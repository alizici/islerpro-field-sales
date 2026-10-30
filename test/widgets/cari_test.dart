import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:islerpro/core/auth/session.dart';
import 'package:islerpro/core/test_keys.dart';
import 'package:islerpro/data/repositories/cari_repository.dart';
import 'package:islerpro/data/repositories/org_repository.dart';
import 'package:islerpro/features/accounts/presentation/cari_detay_ekrani.dart';
import 'package:islerpro/features/accounts/presentation/cari_tasima_diyalogu.dart';
import 'package:islerpro/features/accounts/presentation/cariler_ekrani.dart';
import 'package:islerpro/features/accounts/presentation/portfoy_atama_diyalogu.dart';

import 'sahte_depolar.dart';

/// K7 · Bu dosyanın asıl işi: kurum düzeyinde TOPLAM üretilmediğini kanıtlamak.
/// Okulun temiz 45.000 ₺'lik carisi, bir öğretmenin 12.000 ₺'lik gecikmesi
/// yüzünden limit aşımına düşmemelidir.
void main() {
  Future<(SahteCariRepo, ProviderContainer)> ac(WidgetTester t, Widget w,
      {SahteCariRepo? repo, SahteOrgRepo? org,
       AppRole rol = AppRole.isletmeSahibi}) async {
    final r = repo ?? SahteCariRepo();
    late ProviderContainer kap;
    await t.pumpWidget(ProviderScope(
      overrides: [
        cariRepositoryProvider.overrideWithValue(r),
        orgRepositoryProvider.overrideWithValue(org ?? SahteOrgRepo()),
        sessionProvider.overrideWithValue(testOturumu(rol: rol)),
      ],
      child: Builder(builder: (c) {
        kap = ProviderScope.containerOf(c);
        return MaterialApp(home: w);
      }),
    ));
    await t.pumpAndSettle();
    return (r, kap);
  }

  group('Boş ekran çıkış verir', () {
    testWidgets('hiç cari yokken "cari" ne demek yazar ve düğme çıkar',
        (t) async {
      await ac(t, const CarilerEkrani());

      // Uygulamanın en temel kelimesi hiçbir yerde açıklanmıyordu; yeni bir
      // kullanıcı "cari"nin ne olduğunu tahmin edemez.
      expect(find.textContaining('alışverişin muhatabı'), findsOneWidget);
      // Boş ekran "sağ üstten ekleyebilirsin" diye TARİF etmiyor, düğmeyi
      // buraya koyuyor.
      expect(find.widgetWithText(FilledButton, 'İlk cariyi aç'), findsOneWidget);
    });
  });

  group('K7 · toplam üretilmiyor', () {
    testWidgets('kardeş cariler ayrı satır, toplam satırı YOK', (t) async {
      final repo = SahteCariRepo(detayKaydi: cariDetay(
        bakiye: 45000,
        limit: 100000,   // toplamla (60.000) çakışmasın
        kardesler: [
          cari('Ahmet Öğretmen', id: 'c2', tip: 'ogretmen', bakiye: 12000),
          cari('Ayşe Öğretmen', id: 'c3', tip: 'ogretmen', bakiye: 3000),
        ],
      ));
      await ac(t, const CariDetayEkrani(cariId: 'c1'), repo: repo);

      // Carinin KENDİ bakiyesi bandın baskın sayısı — ekranın tepesinde.
      // Kardeşlere kaydırınca bant görüş alanından çıkıyor, o yüzden burada
      // bakılıyor.
      expect(find.textContaining('45.000,00'), findsWidgets);

      await t.scrollUntilVisible(find.byKey(K.cariDetayKardesler), 300);
      await t.pumpAndSettle();
      expect(find.byKey(K.cariDetayKardesler), findsOneWidget);
      expect(find.textContaining('12.000,00'), findsOneWidget);
      expect(find.textContaining('3.000,00'), findsOneWidget);

      // 45.000 + 12.000 + 3.000 = 60.000 — bu sayı EKRANDA GÖRÜNMEMELİ
      expect(find.textContaining('60.000,00'), findsNothing,
          reason: 'kurum düzeyinde toplam üretilmemeli');
      // Hem risk hem kardeşler bölümü aynı kuralı yazıyor — ikisi de kalsın.
      expect(find.textContaining('Bakiyeler toplanmaz'), findsOneWidget,
          reason: 'kural kullanıcıya da yazılmalı');
    });

    testWidgets('risk bölümü carinin kendisiyle sınırlı olduğunu söyler',
        (t) async {
      final repo = SahteCariRepo(detayKaydi: cariDetay());
      await ac(t, const CariDetayEkrani(cariId: 'c1'), repo: repo);

      expect(find.byKey(K.cariDetayRisk), findsOneWidget);
      expect(find.textContaining('kardeş carilerle toplanmaz'), findsOneWidget);
    });

    testWidgets('K11 · limit kontrolü bakiyeye değil RİSKE bakar', (t) async {
      final repo = SahteCariRepo(detayKaydi: cariDetay(
          bakiye: 40000, risk: 70000, limit: 60000));   // bakiye limitin altında
      await ac(t, const CariDetayEkrani(cariId: 'c1'), repo: repo);

      expect(find.textContaining('Risk kredi limitini aşıyor'), findsOneWidget,
          reason: 'vadesi gelmemiş çek riske dâhildir');
      expect(find.textContaining('vadesi gelmemiş çek'), findsOneWidget);
    });

    testWidgets('limit çizgisi aşımı KIRPMAZ, ayrı dilim olarak gösterir',
        (t) async {
      // İlk sürümde risk limite kırpılıyordu ve etiket "kullanılan risk 60b"
      // yazıyordu — gerçek risk 70b iken. Sayının yalan söylemesindense
      // çizginin taşması yeğdir.
      final repo = SahteCariRepo(detayKaydi: cariDetay(
          bakiye: 40000, risk: 70000, limit: 60000));
      await ac(t, const CariDetayEkrani(cariId: 'c1'), repo: repo);

      expect(find.textContaining('Limit aşımı'), findsOneWidget);
      expect(find.textContaining('Kalan limit'), findsNothing,
          reason: 'limit aşılmışsa kalan limit diye bir şey yok');
    });
  });

  group('cari listesi', () {
    testWidgets('portföysüz cari işaretlenir (W-2)', (t) async {
      final repo = SahteCariRepo(cariler: [
        cari('Atanmış Okul', id: 'c1', pazarlamaci: 'Ali Veli'),
        cari('Portföysüz Okul', id: 'c2'),
      ]);
      await ac(t, const CarilerEkrani(), repo: repo);

      // Rozet yığını gitti: durum satırın üçüncü satırında, SEBEBİYLE yazılı.
      // (Süzgeç çipi ve cari adı da "Portföysüz" içeriyor — tam metin aranır.)
      expect(find.text('Portföysüz — talebi kutuya düşmez'), findsOneWidget,
          reason: 'atanmamış cariden gelen talep hiçbir kutuya düşmez');
      expect(find.textContaining('Ali Veli'), findsOneWidget);
    });

    testWidgets('limit aşan cari kırmızı rozet alır', (t) async {
      final repo = SahteCariRepo(cariler: [
        cari('Riskli Okul', bakiye: 80000, limit: 50000, limitAsildi: true),
      ]);
      await ac(t, const CarilerEkrani(), repo: repo);
      expect(find.text('Kredi limiti aşıldı'), findsOneWidget);
    });

    testWidgets('süzgeçler depoya iletilir', (t) async {
      final (repo, _) = await ac(t, const CarilerEkrani(),
          repo: SahteCariRepo(cariler: [cari('X')]));
      repo.cagrilar.clear();

      await t.tap(find.byKey(K.cariFiltreBorclu));
      await t.pumpAndSettle();
      expect(repo.cagrilar.any((c) => c.contains('borclu=true')), isTrue);

      await t.tap(find.byKey(K.cariFiltreAtanmamis));
      await t.pumpAndSettle();
      expect(repo.cagrilar.any((c) => c.contains('atanmamis=true')), isTrue);
    });

    testWidgets('liste toplam bakiye satırı göstermez', (t) async {
      final repo = SahteCariRepo(cariler: [
        cari('Okul A', id: 'c1', bakiye: 45000),
        cari('Okul B', id: 'c2', bakiye: 15000),
      ]);
      await ac(t, const CarilerEkrani(), repo: repo);

      expect(find.textContaining('60.000'), findsNothing,
          reason: 'cari listesinde toplam satırı basılmaz (K7)');
    });

    testWidgets('pazarlamacı cari seçip atama yapamaz', (t) async {
      final repo = SahteCariRepo(cariler: [cari('Okul A')]);
      await ac(t, const CarilerEkrani(), repo: repo,
          rol: AppRole.pazarlamaci);

      expect(find.byType(Checkbox), findsNothing,
          reason: 'portföy ataması sahip/müdür işidir');
    });

    testWidgets('onay kutuları yalnızca seçim modunda çıkar', (t) async {
      final repo = SahteCariRepo(cariler: [cari('Okul A'), cari('Okul B',
          id: 'c2')]);
      await ac(t, const CarilerEkrani(), repo: repo);

      // Liste her gün okunuyor, toplu atama ayda birkaç kez yapılıyor:
      // varsayılan hâlde kutular listenin asıl sorusunu bastırmamalı.
      expect(find.byType(Checkbox), findsNothing,
          reason: 'seçim modu kapalıyken kutu görünmemeli');
      expect(find.byKey(K.cariSecimCubugu), findsNothing);

      await t.tap(find.byKey(K.cariSecimModu));
      await t.pumpAndSettle();

      expect(find.byType(Checkbox), findsNWidgets(2));
      expect(find.byKey(K.cariSecimCubugu), findsOneWidget,
          reason: 'mod açıkken ne yapılacağı yazılı olmalı');
    });
  });

  group('portföy ataması', () {
    testWidgets('toplu atama seçilen carileri gönderir', (t) async {
      final org = SahteOrgRepo(ekipListesi: [
        uye('Ali Veli', id: 'u2', portfoy: 12),
        uye('Ayşe Can', id: 'u3', portfoy: 40),
      ]);
      final (repo, _) = await ac(t,
          const PortfoyAtamaDiyalogu(cariIdler: ['c1', 'c2', 'c3'],
              periodId: 'p1'),
          org: org);

      expect(find.textContaining('3 cari'), findsWidgets);
      expect(find.textContaining('devralınır'), findsOneWidget,
          reason: 'bir cari bir dönemde tek kişiye ait olur');

      await t.tap(find.byKey(K.atamaAday));
      await t.pumpAndSettle();
      await t.tap(find.text('Ayşe Can · 40 cari').last);
      await t.pumpAndSettle();
      await t.tap(find.byKey(K.atamaOnay));
      await t.pumpAndSettle();

      expect(repo.sonAtananlar, ['c1', 'c2', 'c3']);
      expect(repo.sonAtananKisi, 'u3');
    });

    testWidgets('portföyden çıkarmanın sonucu uyarıyla söylenir', (t) async {
      final org = SahteOrgRepo(ekipListesi: [uye('Ali Veli', id: 'u2')]);
      final (repo, _) = await ac(t,
          const PortfoyAtamaDiyalogu(cariIdler: ['c1'], periodId: 'p1'),
          org: org);

      await t.tap(find.byType(CheckboxListTile));
      await t.pumpAndSettle();
      expect(find.textContaining('hiçbir gelen kutusuna düşmez'), findsOneWidget);

      await t.tap(find.byKey(K.atamaOnay));
      await t.pumpAndSettle();
      expect(repo.sonAtananKisi, isNull);
    });
  });

  group('K6 · cari taşıma', () {
    testWidgets('açık konsinye varsa taşıma engellenir', (t) async {
      final repo = SahteCariRepo(
          kontrol: const TasimaKontrol(acikKonsinye: 42, kurumAd: 'Eski Okul'));
      await ac(t, CariTasimaDiyalogu(cari: cariDetay()), repo: repo);

      expect(find.byKey(K.cariTasiEngel), findsOneWidget);
      expect(find.textContaining('Açık konsinye var (42 adet)'), findsOneWidget);
      expect(find.textContaining('fiziken eski kurumda'), findsOneWidget);
      expect(t.widget<FilledButton>(find.byKey(K.cariTasiOnay)).onPressed,
          isNull);
    });

    testWidgets('sevk edilmemiş sipariş de engeldir', (t) async {
      final repo = SahteCariRepo(
          kontrol: const TasimaKontrol(sevkEdilmemisSiparis: 3));
      await ac(t, CariTasimaDiyalogu(cari: cariDetay()), repo: repo);

      expect(find.textContaining('Sevk edilmemiş 3 sipariş'), findsOneWidget);
    });

    testWidgets('engel yoksa geçmişin eski kurumda kalacağı yazar', (t) async {
      final repo = SahteCariRepo(
          kontrol: const TasimaKontrol(bakiye: 8500, kurumAd: 'Eski Okul'));
      await ac(t, CariTasimaDiyalogu(cari: cariDetay()), repo: repo);

      expect(find.byKey(K.cariTasiEngel), findsNothing);
      expect(find.textContaining('8.500,00'), findsOneWidget);
      expect(find.textContaining('Eski Okul altında kalır'), findsOneWidget,
          reason: 'okul bazlı iş hacmi raporunun bozulmadığı söylenmeli');
    });

    testWidgets('gerekçesiz taşıma butonu açılmaz', (t) async {
      final repo = SahteCariRepo(kontrol: const TasimaKontrol());
      await ac(t, CariTasimaDiyalogu(cari: cariDetay()), repo: repo);
      expect(t.widget<FilledButton>(find.byKey(K.cariTasiOnay)).onPressed,
          isNull, reason: 'gerekçe zorunlu ve kalıcı kayda geçer');
    });
  });

  group('cari açma', () {
    testWidgets('öğretmen carisinin okula yansımadığı yazılı', (t) async {
      await ac(t, const CarilerEkrani(),
          repo: SahteCariRepo(cariler: [cari('X')]));
      await t.tap(find.byKey(K.cariEkle));
      await t.pumpAndSettle();

      await t.tap(find.descendant(
          of: find.byKey(K.cariEkleTip), matching: find.text('Öğretmen')));
      await t.pumpAndSettle();

      expect(find.textContaining('okula yansımaz'), findsOneWidget);
      expect(find.textContaining('kefili değildir'), findsOneWidget);
    });

    testWidgets('kurum seçilmeden cari açılamaz', (t) async {
      await ac(t, const CarilerEkrani(),
          repo: SahteCariRepo(cariler: [cari('X')]));
      await t.tap(find.byKey(K.cariEkle));
      await t.pumpAndSettle();

      await t.enterText(find.byKey(K.cariEkleUnvan), 'Yeni Cari');
      await t.pumpAndSettle();
      expect(t.widget<FilledButton>(find.byKey(K.cariEkleKaydet)).onPressed,
          isNull, reason: 'cari her zaman bir kuruma bağlıdır (bağlam bağı)');
    });
  });
}
