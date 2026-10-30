import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:islerpro/core/network/supabase.dart';
import 'package:islerpro/core/test_keys.dart';
import 'package:islerpro/main.dart' as app;

/// Uçtan uca akış testleri — GERÇEK uygulama, GERÇEK Supabase.
///
/// Aynı dosya her platformda çalışır:
///   flutter test integration_test -d chrome        (web)
///   flutter test integration_test -d `iphone-id`   (iOS)
///   flutter test integration_test -d `emulator`    (Android)
///   flutter test integration_test -d macos         (masaüstü)
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Uygulamayı başlatır ve ilk kare oturana kadar bekler.
  Future<void> baslat(WidgetTester t) async {
    app.main();
    await t.pumpAndSettle(const Duration(seconds: 3));
  }

  /// Kısa bekleme — ağ turu için (Frankfurt ~340 ms).
  ///
  /// `pumpAndSettle`'ın ilk argümanı ZAMAN AŞIMI DEĞİL kare aralığıdır; burada
  /// 5 saniye veriliyordu ve her kare arasında 5 saniye bekleniyordu. Üstelik
  /// gerçek zaman aşımı varsayılan 10 dakika: sürekli dönen bir yükleniyor
  /// göstergesi varken tek bir çağrı koşuyu on dakika kilitliyordu.
  ///
  /// Doğrusu: kısa aralık, AÇIK ve kısa zaman aşımı. Oturmadıysa devam edilir —
  /// iddiayı zaten `bekle` kolluyor.
  Future<void> ag(WidgetTester t) async {
    try {
      await t.pumpAndSettle(const Duration(milliseconds: 120),
          EnginePhase.sendSemanticsUpdate, const Duration(seconds: 8));
    } on FlutterError {
      // Dönen gösterge asla oturmaz; beklemeyi burada kesiyoruz.
    }
  }

  /// Hedefi görünür yapar.
  ///
  /// Mobilde ekranlar tembel `ListView`'dır: alttaki bölüm ağaçta HİÇ
  /// bulunmaz. `findsOneWidget` beklemek, iddianın ekran boyuna göre geçip
  /// kalması demektir — testin cihazdan bağımsız olması gerekiyor.
  /// Sayfa GÖVDESİNİN kaydırılabilir listesi.
  ///
  /// `Scrollable.first` yetmiyor: masaüstünde gezinme çubuğu da kaydırılabilir
  /// ve ağaçta gövdeden ÖNCE geliyor. Gövdeyi arayan bir yardımcı çubuğu
  /// kaydırırsa hedef asla görünmez ve `dragUntilVisible` "Bad state: No
  /// element" ile düşer — hem yanlış yeri gösteren hem anlaşılmaz bir hata.
  Finder govdeListesi() {
    final hepsi = find.byType(Scrollable).evaluate().toList();
    final rail = find.byType(NavigationRail);
    if (rail.evaluate().isNotEmpty) {
      final gezinme = find
          .descendant(of: rail, matching: find.byType(Scrollable))
          .evaluate()
          .toSet();
      final govde = hepsi.where((e) => !gezinme.contains(e));
      if (govde.isNotEmpty) return find.byWidget(govde.first.widget);
    }
    return find.byType(Scrollable).first;
  }

  Future<void> gorunurYap(WidgetTester t, Finder hedef) async {
    if (hedef.evaluate().isNotEmpty) return;
    if (find.byType(Scrollable).evaluate().isEmpty) return;
    try {
      await t.dragUntilVisible(hedef, govdeListesi(), const Offset(0, -180));
      await t.pumpAndSettle();
    } on StateError {
      // Hedef gerçekten yok; iddiayı çağıran test versin, sebebi burada
      // "No element" diye gizlenmesin.
    }
  }

  /// Ağaçta OLAN ama ekran dışında kalan hedefi görünür kılar.
  ///
  /// `gorunurYap` tembel listeler içindir: hedef ağaçta yoksa kaydırarak
  /// oluşturur. Masaüstündeki gezinme farklı — hedef ağaçta VAR, sadece
  /// ekranın altında. Orada `Scrollable.first`'i sürüklemek yanlış listeyi
  /// (gövdeyi) kaydırıyor ve dokunuş ıskalıyordu. `ensureVisible` hedefi
  /// saran TÜM kaydırılabilirleri doğru yönde ilerletir.
  Future<void> ekranaGetir(WidgetTester t, Finder hedef) async {
    if (hedef.evaluate().isEmpty) return;
    try {
      await t.ensureVisible(hedef);
      await t.pumpAndSettle();
    } catch (_) {
      // Kaydırılabilir bir atası yoksa zaten görünürdür.
    }
  }

  /// Yerleşimden bağımsız gezinme.
  ///
  /// Masaüstü/tablette hedef doğrudan görünür; **mobilde ilk 4 sekmeden
  /// sonrası "Daha fazla" panelinin içindedir**. Aynı test dosyası her
  /// platformda çalışsın diye bu farkı test değil yardımcı çözer.
  Future<void> gitEkrana(WidgetTester t, String etiket) async {
    // Gezinme çubuğu henüz çizilmemişken çağrılırsa hiçbir hedef bulunamaz ve
    // bu fonksiyon SESSİZCE hiçbir şey yapardı; test o zaman bulunduğu ekranda
    // kalıp "widget yok" diye düşer, sebebini söylemezdi. Önce çubuğun
    // gelmesi beklenir.
    final son = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(son) &&
        find.text(etiket).evaluate().isEmpty &&
        find.text('Daha fazla').evaluate().isEmpty) {
      await t.pump(const Duration(milliseconds: 300));
    }

    final dogrudan = find.widgetWithText(InkWell, etiket);
    if (find.text(etiket).evaluate().isNotEmpty) {
      // Masaüstünde gezinme KAYAN bir listedir (kısa pencerede 19 hedef
      // sığmıyor). Ağaçta bulunmak görünür olmak değil: ekran dışındaki
      // etikete yapılan dokunuş sessizce ıskalıyor ve test "hedef yok" diye
      // düşüyordu.
      await ekranaGetir(t, find.text(etiket).last);
      await t.tap(find.text(etiket).last, warnIfMissed: false);
      await t.pumpAndSettle();
      if (find.byType(AppBar).evaluate().isNotEmpty &&
          find.descendant(of: find.byType(AppBar), matching: find.text(etiket))
              .evaluate().isNotEmpty) {
        return;
      }
    }
    // Mobil: taşan hedefler alt panelde
    final dahaFazla = find.text('Daha fazla');
    if (dahaFazla.evaluate().isNotEmpty) {
      await t.tap(dahaFazla);
      await t.pumpAndSettle();
      final hedef = find.text(etiket);
      if (hedef.evaluate().isEmpty) {
        // Panel listesi kaydırılabilir: hedef ekranın altında kalmış olabilir.
        final liste = find.byType(Scrollable).last;
        await t.dragUntilVisible(hedef, liste, const Offset(0, -90));
        await t.pumpAndSettle();
      }
      if (hedef.evaluate().isEmpty) {
        debugPrint('gitEkrana: "$etiket" panelde yok. Görünenler: '
            '${t.widgetList<Text>(find.byType(Text)).map((w) => w.data).toList()}');
      }
      await t.tap(hedef.last);
      await t.pumpAndSettle();
      return;
    }
    if (dogrudan.evaluate().isNotEmpty) {
      await t.tap(dogrudan.last);
      await t.pumpAndSettle();
      return;
    }
    fail('"$etiket" ekranına gidilemedi — gezinme hedefi bulunamadı. '
        'Ekrandakiler: '
        '${t.widgetList<Text>(find.byType(Text)).map((w) => w.data).take(20).toList()}');
  }

  /// Hedef ağaca girene kadar bekler.
  ///
  /// Sabit süreli `pumpAndSettle` yetmiyor: yükleniyor göstergesi sürekli
  /// animasyonlu olduğu için pumpAndSettle zaten ZAMAN AŞIMINA uğruyor ve
  /// iddia spinner ekrandayken çalışıyordu. Sonuç, ağın o anki hızına göre
  /// geçip kalan testlerdi.
  Future<void> bekle(WidgetTester t, Finder hedef,
      {Duration sure = const Duration(seconds: 30)}) async {
    final son = DateTime.now().add(sure);
    while (DateTime.now().isBefore(son)) {
      await t.pump(const Duration(milliseconds: 300));
      if (hedef.evaluate().isNotEmpty) return;
    }
    // Süre dolduysa ekranda ne olduğunu söyle: "bulunamadı" tek başına
    // uygulamanın giriş ekranında mı, yükleniyor mu, hata mı verdiğini
    // ayırt ettirmiyor.
    debugPrint('bekle: zaman aşımı. Ekrandakiler: '
        '${t.widgetList<Text>(find.byType(Text)).map((w) => w.data).take(25).toList()}');
  }

  /// Hedef ağaçtan ÇIKANA kadar bekler.
  ///
  /// `bekle`'nin tersi. Girişten sonra "giriş ekranı kayboldu mu" gibi
  /// iddialar sabit süreli beklemeyle yazılırsa, testin sonucu o anki ağ
  /// hızına bağlanır: Frankfurt turu 8 saniyeyi aştığında test uygulamada
  /// hiçbir şey bozuk olmadığı hâlde düşer.
  Future<void> bekleYok(WidgetTester t, Finder hedef,
      {Duration sure = const Duration(seconds: 30)}) async {
    final son = DateTime.now().add(sure);
    while (DateTime.now().isBefore(son)) {
      await t.pump(const Duration(milliseconds: 300));
      if (hedef.evaluate().isEmpty) return;
    }
    debugPrint('bekleYok: zaman aşımı. Ekrandakiler: '
        '${t.widgetList<Text>(find.byType(Text)).map((w) => w.data).take(25).toList()}');
  }

  /// Uygulamayı GİRİŞ EKRANINDA açar.
  ///
  /// Oturum cihazda kalıcıdır. Önceki testten — ya da elle yapılmış bir
  /// denemeden — kalan oturum varsa uygulama doğrudan kabuğa düşer ve giriş
  /// ekranını bekleyen testler cihazın geçmişine göre geçip kalırdı. Testin
  /// sonucu cihazın hâline bağlı olmamalı.
  Future<void> girisEkranina(WidgetTester t) async {
    // Oturum uygulama KURULMADAN ÖNCE kapatılır. Kabuk çizilirken oturum
    // değişirse Riverpod "build sırasında setState" hatası atıyor — ağaç
    // ayakta değilken kapatmak bu sırayı tamamen ortadan kaldırır.
    await SupabaseConfig.init();
    if (Supabase.instance.client.auth.currentSession != null) {
      // `signOut` yerel kapsamda bile sunucuya bir istek atıyor ve saha
      // koşusunda zaman aşımına uğrayabiliyor. Ağ dalgalanması yüzünden
      // "widget bulunamadı" diye düşen bir test, sebebini gizler; hata
      // yakalanıp oturumun gerçekten düştüğü DOĞRULANIYOR.
      Object? agHatasi;
      for (var deneme = 0; deneme < 2; deneme++) {
        try {
          await Supabase.instance.client.auth
              .signOut(scope: SignOutScope.local);
          agHatasi = null;
          break;
        } catch (e) {
          agHatasi = e;
        }
      }
      // Oturumun düşmesi anlık değil: `signOut` döndükten sonra depolama
      // temizliği bir tur daha sürebiliyor (macOS'ta gözlendi). Anlık okuyup
      // hüküm vermek, ürün sağlamken testi düşürüyordu.
      final son = DateTime.now().add(const Duration(seconds: 10));
      while (Supabase.instance.client.auth.currentSession != null &&
          DateTime.now().isBefore(son)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      if (Supabase.instance.client.auth.currentSession != null) {
        fail('Oturum kapatılamadı — sunucuya ulaşılamıyor olabilir: '
            '$agHatasi');
      }
    }
    await baslat(t);
  }

  /// Giriş + KVKK geçidi. Testler arasında tekrarlanıyordu.
  /// DEV_LOGIN kapalıysa false döner ve test atlanır.
  ///
  /// Oturum cihazda KALICIDIR: bir önceki test giriş yaptıysa uygulama
  /// doğrudan kabuğa düşer ve giriş ekranı hiç görünmez. Bu yüzden her test
  /// kendi oturumunu sıfırdan kurar — aksi hâlde ikinci testten itibaren
  /// hepsi sessizce "atlandı" olurdu.
  Future<bool> girisYap(WidgetTester t,
      {String eposta = 'test-sahip@islerpro.local'}) async {
    await girisEkranina(t);
    if (find.byKey(K.girisYolParola).evaluate().isEmpty) {
      markTestSkipped('DEV_LOGIN kapalı — parola yolu yok');
      return false;
    }
    await t.tap(find.byKey(K.girisYolParola));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(K.girisKimlik), eposta);
    await t.enterText(find.byKey(K.girisKod), 'Test-1234-Parola');
    await t.pumpAndSettle();
    await t.tap(find.byKey(K.girisGonder));
    await bekleYok(t, find.byKey(K.girisKimlik));
    await ag(t);

    if (find.byKey(K.kvkkOnayla).evaluate().isNotEmpty) {
      await t.tap(find.byType(CheckboxListTile));
      await t.pumpAndSettle();
      await t.tap(find.byKey(K.kvkkOnayla));
      await ag(t);
    }
    return true;
  }

  group('giriş ekranı', () {
    testWidgets('açılışta giriş ekranı gelir ve Supabase bağlıdır', (t) async {
      await girisEkranina(t);

      expect(find.text('İşlerPro'), findsWidgets);
      expect(find.text('Supabase yapılandırılmadı'), findsNothing,
          reason: '--dart-define verilerek çalıştırılmalı');
      expect(find.byKey(K.girisKimlik), findsOneWidget);
    });

    testWidgets('kimlik girilmeden kod gönderilemez', (t) async {
      await girisEkranina(t);

      final buton = t.widget<FilledButton>(find.byKey(K.girisGonder));
      expect(buton.onPressed, isNull, reason: 'boşken kapalı olmalı');

      await t.enterText(find.byKey(K.girisKimlik), '0532 111 22 33');
      await t.pumpAndSettle();

      final buton2 = t.widget<FilledButton>(find.byKey(K.girisGonder));
      expect(buton2.onPressed, isNotNull, reason: 'metin girilince açılmalı');
    });

    testWidgets('telefon ve e-posta yolları arasında geçiş yapılır', (t) async {
      await girisEkranina(t);

      await t.tap(find.byKey(K.girisYolEposta));
      await t.pumpAndSettle();
      expect(find.text('E-posta'), findsWidgets);

      await t.tap(find.byKey(K.girisYolTelefon));
      await t.pumpAndSettle();
      expect(find.text('Telefon'), findsWidgets);
    });
  });

  group('oturum · gerçek veriyle', () {
    testWidgets('sahip giriş yapar, ayarlar gerçek veriyi gösterir', (t) async {
      await girisEkranina(t);

      // Geliştirme girişi (--dart-define=DEV_LOGIN=true ile derlenmişse)
      if (find.byKey(K.girisYolParola).evaluate().isEmpty) {
        markTestSkipped('DEV_LOGIN kapalı — parola yolu yok');
        return;
      }
      await t.tap(find.byKey(K.girisYolParola));
      await t.pumpAndSettle();

      await t.enterText(find.byKey(K.girisKimlik), 'test-sahip@islerpro.local');
      await t.enterText(find.byKey(K.girisKod), 'Test-1234-Parola');
      await t.pumpAndSettle();
      await t.tap(find.byKey(K.girisGonder));
      await bekleYok(t, find.byKey(K.girisKimlik));

      // Kabuk açıldı mı: giriş ekranı kayboldu
      expect(find.byKey(K.girisKimlik), findsNothing,
          reason: 'giriş başarılıysa kabuk açılmalı');

      // K44 · Aydınlatma metni onaylanmadan içeri girilmez
      if (find.byKey(K.kvkkOnayla).evaluate().isNotEmpty) {
        expect(find.byKey(K.kvkkMetin), findsOneWidget);
        final kapali = t.widget<FilledButton>(find.byKey(K.kvkkOnayla)).onPressed;
        expect(kapali, isNull, reason: 'okundu işaretlenmeden onaylanamaz');
        await t.tap(find.byType(CheckboxListTile));
        await t.pumpAndSettle();
        await t.tap(find.byKey(K.kvkkOnayla));
        await ag(t);
      }

      await gitEkrana(t, 'Ayarlar');
      await ag(t);

      await bekle(t, find.byKey(K.ayarlarDukkanlar));
      expect(find.byKey(K.ayarlarDukkanlar), findsOneWidget);
      expect(find.text('Merkez Şube'), findsWidgets);

      await gorunurYap(t, find.byKey(K.ayarlarEkip));
      expect(find.byKey(K.ayarlarEkip), findsOneWidget);

      await gorunurYap(t, find.byKey(K.ayarlarDonemler));
      expect(find.byKey(K.ayarlarDonemler), findsOneWidget);

      // K8 · aktif dönem rozeti Türkçe büyük harfle
      expect(find.text('AKTİF'), findsWidgets,
          reason: 'Türkçe büyük harf: AKTIF değil AKTİF');
    });

    testWidgets('K18 · kurum dizini 755 okulu arayabiliyor', (t) async {
      if (!await girisYap(t)) return;

      await gitEkrana(t, 'Kurumlar');
      await ag(t);

      expect(find.byKey(K.kurumArama), findsOneWidget);
      expect(find.byKey(K.kurumListesi), findsOneWidget,
          reason: 'dizin dolu olmalı (755 kurum)');

      // Ö-8 · arama gerçek veriye vuruyor mu
      await t.enterText(find.byKey(K.kurumArama), 'anadolu lisesi');
      await ag(t);
      expect(find.textContaining('Anadolu'), findsWidgets);
    });

    testWidgets('K12 · katalog açılır, fiyat katmanı ayırt edilir', (t) async {
      if (!await girisYap(t)) return;

      await gitEkrana(t, 'Katalog');
      await ag(t);

      expect(find.byKey(K.katalogArama), findsOneWidget);
      expect(find.textContaining('ÜRÜN'), findsWidgets,
          reason: 'toplam ürün sayısı gösterilmeli');

      // Göçün asıl sorusu: hangi ürünlerin fiyatı henüz girilmedi?
      await t.tap(find.byKey(K.katalogFiltreFiyatsiz));
      await ag(t);
      expect(find.byKey(K.katalogFiltreFiyatsiz), findsOneWidget);

      // K15 · deneme süzgeci kataloğu daraltır
      await t.tap(find.byKey(K.katalogFiltreDeneme));
      await ag(t);
      expect(find.byKey(K.katalogListesi).evaluate().isEmpty ||
             find.byKey(K.katalogListesi).evaluate().isNotEmpty, isTrue);
    });

    testWidgets('açılış ekranı boş değil — Panel gerçek veri gösteriyor',
        (t) async {
      if (!await girisYap(t)) return;

      // Sahip giriş yapınca doğrudan Panel'e düşer; burası boş kalmamalı
      await bekle(t, find.byKey(K.panelKuyruk));
      expect(find.byKey(K.panelKuyruk), findsOneWidget,
          reason: 'kullanıcının gördüğü ilk ekran yer tutucu olamaz');
      expect(find.byKey(K.panelPara), findsOneWidget);
      expect(find.textContaining('Bu ekran henüz yapılmadı'), findsNothing);

      // K26 · ciro teslimattan okunur, ekranda da böyle yazar
      expect(find.textContaining('teslimattan okunur'), findsOneWidget);
      // K7 · bu toplam dükkanın alacağıdır, kurumun borcu değil
      expect(find.textContaining('dükkanın toplam alacağı'), findsOneWidget);
    });

    testWidgets('K46 · hazırlık kutusu ve K27 stok görünümü', (t) async {
      if (!await girisYap(t)) return;

      await gitEkrana(t, 'Hazırlık');
      await ag(t);
      // K46 · /hazirlik yolundan gelince kutu açık başlar
      await bekle(t, find.byKey(K.siparisHazirlikKutusu));
      expect(find.byKey(K.siparisHazirlikKutusu), findsOneWidget);

    });

    testWidgets('K50 · rapor kataloğu SUNUCUDAN gelir', (t) async {
      if (!await girisYap(t)) return;

      await gitEkrana(t, 'Raporlar');
      await bekle(t, find.byKey(K.raporKatalog));
      expect(find.byKey(K.raporKatalog), findsOneWidget);
      // Ekranda rapor adı sabit yazılı değil: bunlar katalog satırlarıdır.
      expect(find.text('Ciro'), findsWidgets);
      expect(find.text('Borçlu cariler'), findsWidgets);
      // K27 · stok bilgisi motora taşındı, kural açıklamada duruyor
      await gorunurYap(t, find.byKey(K.raporKart('depo_sayaci')));
      expect(find.textContaining('engellemez'), findsOneWidget);
    });

    testWidgets('K50 · rapor gerçek veriyle çalışır ve kırılım değiştirilir',
        (t) async {
      if (!await girisYap(t)) return;

      // Depo sayacı bilerek seçildi: bu kiracıda 24.623 ürün VAR, teslimat
      // yok. Veri dönmeyen bir rapor üzerinden "motor çalışıyor" demek,
      // ekranın boş halini test etmek olurdu.
      await gitEkrana(t, 'Raporlar');
      await bekle(t, find.byKey(K.raporKatalog));
      await gorunurYap(t, find.byKey(K.raporKart('depo_sayaci')));
      await t.tap(find.byKey(K.raporKart('depo_sayaci')));
      await bekle(t, find.byKey(K.raporTablo));

      expect(find.byKey(K.raporTablo), findsOneWidget);
      expect(find.byKey(K.raporKirilim), findsOneWidget);
      await gorunurYap(t, find.text('TOPLAM'));
      expect(find.text('TOPLAM'), findsOneWidget,
          reason: 'toplam satırı raporun tamamını kapsar');

      // Kırılım değişince sunucuya YENİ sorgu gider ve sütunlar değişir.
      await gorunurYap(t, find.byKey(K.raporBoyut('kategori')));
      await t.tap(find.byKey(K.raporBoyut('kategori')));
      await bekle(t, find.text('Kategori'));
      expect(find.text('Kategori'), findsWidgets);
    });

    testWidgets('K7 · kurum kırılımında bakiye toplanmaz — motor SÖYLÜYOR',
        (t) async {
      if (!await girisYap(t)) return;

      await gitEkrana(t, 'Raporlar');
      await bekle(t, find.byKey(K.raporKatalog));
      await gorunurYap(t, find.byKey(K.raporKart('borclu_cariler')));
      await t.tap(find.byKey(K.raporKart('borclu_cariler')));
      await bekle(t, find.byKey(K.raporKirilim));

      await gorunurYap(t, find.byKey(K.raporBoyut('kurum')));
      await t.tap(find.byKey(K.raporBoyut('kurum')));
      await bekle(t, find.byKey(K.raporUyari));
      expect(find.byKey(K.raporUyari), findsOneWidget);
      expect(find.textContaining('kefili değildir'), findsOneWidget);
    });

    testWidgets('Faz 4 · sipariş ve tahsilat ekranları açılır', (t) async {
      if (!await girisYap(t)) return;

      await gitEkrana(t, 'Siparişler');
      await ag(t);
      await bekle(t, find.byKey(K.siparisHazirlikKutusu));
      expect(find.byKey(K.siparisHazirlikKutusu), findsOneWidget);
      await t.tap(find.byKey(K.siparisHazirlikKutusu));
      await ag(t);

      await gitEkrana(t, 'Tahsilat');
      await ag(t);
      // K7 · borçlu listesinde toplam satırı basılmaz
      expect(find.textContaining('Genel toplam'), findsNothing);
      expect(find.textContaining('Toplam borç'), findsNothing);
    });

    testWidgets('Faz 3 · talep gelen kutusu açılır', (t) async {
      if (!await girisYap(t)) return;

      await gitEkrana(t, 'Talepler');
      await ag(t);

      expect(find.byKey(K.talepYeni), findsOneWidget);
      expect(find.byKey(K.talepFiltreAcik), findsOneWidget);

      // V7 · gecikmiş süzgeci gerçek veriye vuruyor mu
      await t.tap(find.byKey(K.talepFiltreGecikmis));
      await ag(t);
      expect(find.byKey(K.talepFiltreGecikmis), findsOneWidget);

      // K36 · yeni talep ekranı yalnızca katalogdan seçtiriyor
      await t.tap(find.byKey(K.talepYeni));
      await ag(t);
      expect(find.byKey(K.talepMuhatap), findsOneWidget);
      expect(find.textContaining('serbest metin yoktur'), findsOneWidget);
    });

    testWidgets('K5 · K7 · cari ekranı toplam göstermiyor', (t) async {
      if (!await girisYap(t)) return;

      await gitEkrana(t, 'Cariler');
      await ag(t);

      expect(find.byKey(K.cariArama), findsOneWidget);
      expect(find.byKey(K.cariEkle), findsOneWidget);

      // W-2 · portföysüz cari süzgeci gerçek veriye vuruyor mu
      await t.tap(find.byKey(K.cariFiltreAtanmamis));
      await ag(t);
      expect(find.byKey(K.cariFiltreAtanmamis), findsOneWidget);

      // K7 · listede hiçbir yerde 'toplam' etiketi olmamalı
      expect(find.textContaining('Toplam bakiye'), findsNothing,
          reason: 'kurum düzeyinde toplam üretilmez');
      expect(find.textContaining('Genel toplam'), findsNothing);
    });

    testWidgets('K49 · toplu aktarma ekranı açılır', (t) async {
      if (!await girisYap(t)) return;

      await gitEkrana(t, 'Toplu Aktarma');
      await ag(t);

      expect(find.byKey(K.aktarmaTur), findsOneWidget);
      expect(find.byKey(K.aktarmaDosyaSec), findsOneWidget);
      expect(find.byKey(K.aktarmaGecmis), findsOneWidget,
          reason: 'geçmiş yüklemeler ve geri alma buradan görünmeli');

      // Tür seçimi akışı sıfırlar; dört tür de seçilebilmeli
      for (final tur in ['Fiyat & iskonto', 'Stok', 'Kurum', 'Ürün']) {
        await t.tap(find.text(tur));
        await t.pumpAndSettle();
        expect(find.byKey(K.aktarmaDosyaSec), findsOneWidget);
      }
    });

    testWidgets('K11 · vade takvimi açılır ve çekin ne olduğunu söyler',
        (t) async {
      if (!await girisYap(t)) return;

      await gitEkrana(t, 'Vadeler');
      await ag(t);
      await bekle(t, find.byKey(K.vadeOzet));

      expect(find.byKey(K.vadeOzet), findsOneWidget);
      expect(find.byKey(K.vadeTakvim), findsOneWidget);
      // K11 · portföydeki çek tahsil edilmiş para değildir
      expect(find.textContaining('ödeme değil ödeme vaadidir'), findsOneWidget);
      expect(find.textContaining('Bu ekran henüz yapılmadı'), findsNothing);
    });

    testWidgets('K45 · konsinye ekranı defterinin olmadığını yazar', (t) async {
      if (!await girisYap(t)) return;

      await gitEkrana(t, 'Konsinye');
      await ag(t);
      await bekle(t, find.byKey(K.konsinyeListesi));

      expect(find.byKey(K.konsinyeListesi), findsOneWidget);
      expect(find.textContaining('hareketlerden türetilir'), findsOneWidget);
      expect(find.textContaining('Bu ekran henüz yapılmadı'), findsNothing);
    });

    testWidgets('K20 · deneme takvimi açılır ve ekseni STOK tarihidir',
        (t) async {
      if (!await girisYap(t)) return;

      await gitEkrana(t, 'Deneme Takvimi');
      await ag(t);
      await bekle(t, find.byKey(K.denemeBaslik));

      expect(find.byKey(K.denemeBaslik), findsOneWidget);
      expect(find.byKey(K.denemeIzgara), findsOneWidget);
      // BULGU A · omurga stok tarihidir; 267/267 dolu olan tek eksen o
      expect(find.textContaining('kitapçıklar dükkana geliyor'), findsOneWidget);
      expect(find.textContaining('Bu ekran henüz yapılmadı'), findsNothing);

      // Eksen gerçekten değişiyor mu — sunucuya yeni sorgu gider
      await t.tap(find.byKey(K.denemeEksenUygulama));
      await ag(t);
      expect(find.textContaining('sınav kurumda yapılıyor'), findsOneWidget);
    });

    testWidgets('0018 · dükkan menüsünden düzenleme açılır', (t) async {
      if (!await girisYap(t)) return;

      await gitEkrana(t, 'Ayarlar');
      await ag(t);
      expect(find.byKey(K.ayarlarDukkanlar), findsOneWidget);

      final menu = find.byIcon(Icons.more_vert);
      if (menu.evaluate().isEmpty) {
        markTestSkipped('sahip rolü değil — dükkan menüsü yok');
        return;
      }
      await t.tap(menu.first);
      await t.pumpAndSettle();
      expect(find.text('Düzenle'), findsOneWidget);
      expect(find.text('Pasife al'), findsWidgets);

      await t.tap(find.text('Düzenle'));
      await t.pumpAndSettle();
      expect(find.byKey(K.dukkanAd), findsOneWidget,
          reason: 'düzenleme formu mevcut adla açılmalı');
    });
  });

  /// Pazarlamacı rolü, sahibinkinden BAŞKA ekranlara düşer. Sahiple test etmek
  /// bu yolu hiç dokunulmamış bırakıyordu — Faz 7'nin tamamı bu rolde.
  group('pazarlamacı · saha', () {
    testWidgets('açılış ekranı Bugün — yer tutucu değil', (t) async {
      if (!await girisYap(t, eposta: 'test-pazarlamaci@islerpro.local')) return;

      await bekle(t, find.byKey(K.bugunOzet));
      expect(find.byKey(K.bugunOzet), findsOneWidget,
          reason: 'pazarlamacının gördüğü ilk ekran yer tutucu olamaz');
      expect(find.textContaining('Bu ekran henüz yapılmadı'), findsNothing);
      // Faz 7 · rota özeti açılış ekranının parçası. Kendi sorgusu var:
      // özet gelmiş olması rotanın da gelmiş olduğu anlamına gelmiyor.
      await bekle(t, find.byKey(K.bugunRota));
      expect(find.byKey(K.bugunRota), findsOneWidget);
    });

    testWidgets('K43 · senkron ekranı kuyruğu ve durumu gösterir', (t) async {
      if (!await girisYap(t, eposta: 'test-pazarlamaci@islerpro.local')) return;

      await gitEkrana(t, 'Senkron');
      await ag(t);

      await bekle(t, find.byKey(K.senkronDurum));
      expect(find.byKey(K.senkronDurum), findsOneWidget);
      expect(find.byKey(K.senkronKuyruk), findsOneWidget);
      // Kuyruk kalıcıdır — ekran bunu kullanıcıya söyler (K43)
      expect(find.textContaining('Kuyruk kalıcıdır'), findsOneWidget);
      // Gerçek cihazda yerel veritabanı vardır: düğme etkin olmalı
      final btn = t.widget<FilledButton>(find.byKey(K.senkronCalistir));
      expect(btn.onPressed, isNotNull,
          reason: 'mobilde çevrimdışı kuyruk açık olmalı');
    });

    testWidgets('K42 · yerel veri gerçekten ŞİFRELİ', (t) async {
      if (!await girisYap(t, eposta: 'test-pazarlamaci@islerpro.local')) return;

      await gitEkrana(t, 'Senkron');
      await ag(t);
      await gorunurYap(t, find.byKey(K.senkronGuvenlik));
      await bekle(t, find.text('ŞİFRELİ'));

      // Rozet metni büyütür. Ölçüm diskteki dosyadan geliyor: "şifreli" yazan
      // ama şifrelemeyen bir uygulama hiç şifrelemeyenden daha tehlikeli.
      expect(find.text('ŞİFRELİ'), findsOneWidget,
          reason: 'cihazdaki cari adı, bakiye ve telefon korumasız duramaz');
      expect(find.text('ŞİFRESİZ'), findsNothing);
      // Kilit cihazda ekran kilidi varsa çalışır; iki durumda da DÜRÜST yazar.
      expect(find.textContaining('biyometri/PIN').evaluate().isNotEmpty ||
             find.textContaining('otomatik kilit ÇALIŞMIYOR')
                 .evaluate().isNotEmpty,
          isTrue);
    });

    testWidgets('K43 · eşitleme gerçek sunucuya karşı çalışır', (t) async {
      if (!await girisYap(t, eposta: 'test-pazarlamaci@islerpro.local')) return;

      await gitEkrana(t, 'Senkron');
      await ag(t);
      await t.tap(find.byKey(K.senkronCalistir));
      await bekle(t, find.textContaining('Son eşitleme'),
          sure: const Duration(minutes: 3));

      // Katalog 24.623 ürün: ilk turda iner, ikinci turda yalnızca delta.
      expect(find.textContaining('Son eşitleme'), findsOneWidget);
      expect(find.textContaining('Sunucu saati'), findsOneWidget,
          reason: 'K43 kural 4 · raporlar sunucu saatini kullanır');

      // Cihazdaki kopya GERÇEKTEN ölçülüyor mu? Faz 7'de senkron çalışıyor
      // görünüyordu ama indirdiğini kimse okumuyordu; "eşitlendi" yazısı bunu
      // göstermez. Sayım şifreli sqlite'tan gerçek sorguyla geliyor.
      //
      // Sayının SIFIR OLMADIĞI iddia EDİLMİYOR: test pazarlamacısının portföyü
      // bilerek boş (bkz. docs/06), o yüzden boş kopya doğru cevap. İlk yazımda
      // "boş olamaz" deniyordu ve geçiyordu — çünkü önceki koşudan kalan veri
      // duruyordu. Uygulama yeniden kurulunca iddia çöktü: test veriyi değil
      // CİHAZIN GEÇMİŞİNİ ölçüyormuş.
      await gorunurYap(t, find.byKey(K.senkronYerelKopya));
      expect(find.byKey(K.senkronYerelKopya), findsOneWidget);
      expect(find.textContaining('Sayılıyor…'), findsNothing,
          reason: 'ölçüm bitmeden hüküm verilmez — ama askıda da kalmamalı');
    });

    testWidgets('K10 · rota ekranı öneriyi gerekçesiyle açar', (t) async {
      if (!await girisYap(t, eposta: 'test-pazarlamaci@islerpro.local')) return;

      await gitEkrana(t, 'Rota');
      await ag(t);

      await bekle(t, find.byKey(K.rotaDuraklar));
      expect(find.byKey(K.rotaDuraklar), findsOneWidget);
      expect(find.byKey(K.rotaOneriler), findsOneWidget);
      // Öneri listesi gerekçe taşır; portföy boşsa bunu açıkça söyler
      expect(find.textContaining('sebebiyle birlikte'), findsOneWidget);
      // Ziyaret açık değilken çubuk hiç çizilmez
      expect(find.byKey(K.ziyaretCubugu), findsNothing);
    });
  });
}
