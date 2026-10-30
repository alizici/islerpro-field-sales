import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:islerpro/core/auth/session.dart';
import 'package:islerpro/core/test_keys.dart';
import 'package:islerpro/data/repositories/aktarma_repository.dart';
import 'package:islerpro/features/import/presentation/aktarma_durumu.dart';
import 'package:islerpro/features/import/presentation/aktarma_ekrani.dart';

import 'sahte_depolar.dart';

/// K49 · Toplu aktarma sihirbazı.
///
/// En kritik davranış: ÖNİZLEME HİÇBİR ŞEY YAZMAZ. Kullanıcı 24 bin satırı
/// görmeden uygulamak zorunda kalmamalı.
void main() {
  Uint8List csv(String s) => Uint8List.fromList(utf8.encode(s));

  const urunDosyasi =
      'Barkod;Ürün Adı;Yayınevi;Etiket Fiyatı\n'
      '9781;Matematik SB;Bes Kurumsal;120,50\n'
      '9782;Türkçe SB;Bes Kurumsal;99\n'
      '9783;;Bes Kurumsal;50\n';

  Future<(SahteAktarmaRepo, ProviderContainer)> ac(WidgetTester t,
      {SahteAktarmaRepo? repo}) async {
    final r = repo ?? SahteAktarmaRepo();
    late ProviderContainer kap;
    // Aktarma ekranı üç bölümden oluşuyor ve hepsi 800x600'e sığmıyor;
    // tembel liste görünmeyeni hiç kurmadığı için "geçmiş yüklemeler var mı"
    // sorusu kısa pencerede cevaplanamıyor.
    t.view.physicalSize = const Size(1000, 2400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [
        aktarmaRepositoryProvider.overrideWithValue(r),
        sessionProvider.overrideWithValue(testOturumu()),
      ],
      child: Builder(builder: (c) {
        kap = ProviderScope.containerOf(c);
        return const MaterialApp(home: AktarmaEkrani());
      }),
    ));
    await t.pumpAndSettle();
    return (r, kap);
  }

  /// Ekran uzun bir ListView; hedef görünür alanın dışındaysa dokunuş ıskalar.
  Future<void> tikla(WidgetTester t, Finder f) async {
    await t.ensureVisible(f);
    await t.pumpAndSettle();
    await t.tap(f);
    await t.pumpAndSettle();
  }

  VoidCallback? buton(WidgetTester t, Key k) {
    final w = t.widget(find.byKey(k));
    return switch (w) {
      FilledButton b => b.onPressed,
      _ => (w as dynamic).onPressed as VoidCallback?,
    };
  }

  testWidgets('dosya yüklenince sütunlar otomatik eşlenir', (t) async {
    final (_, kap) = await ac(t);
    kap.read(aktarmaProvider.notifier).dosyaYukle(csv(urunDosyasi), 'urunler.csv');
    await t.pumpAndSettle();

    expect(find.byKey(K.aktarmaEslesme), findsOneWidget);
    expect(find.textContaining('4/4 sütun eşlendi'), findsOneWidget,
        reason: 'kullanıcı 4 sütunu elle eşlemek zorunda kalmamalı');
    expect(find.textContaining('3 satır'), findsOneWidget);
    expect(find.text('örn: 9781'), findsOneWidget,
        reason: 'her sütunun örnek değeri gösterilmeli');
  });

  testWidgets('anahtar sütun eşlenmeden önizlenemez', (t) async {
    final (_, kap) = await ac(t);
    final n = kap.read(aktarmaProvider.notifier);
    n.dosyaYukle(csv(urunDosyasi), 'urunler.csv');
    await t.pumpAndSettle();

    n.eslesmeAyarla('Ürün Adı', null);      // ad eşlemesini kaldır
    await t.pumpAndSettle();

    expect(find.byKey(K.aktarmaAnahtarUyari), findsOneWidget);
    expect(find.text('Ürün adı sütunu eşlenmeli'), findsOneWidget);
    expect(buton(t, K.aktarmaOnizle), isNull,
        reason: 'anahtarsız yükleme her seferinde mükerrer üretir');
  });

  testWidgets('önizleme KURU KOŞUDUR — hiçbir şey yazılmaz', (t) async {
    final (repo, kap) = await ac(t);
    kap.read(aktarmaProvider.notifier).dosyaYukle(csv(urunDosyasi), 'x.csv');
    await t.pumpAndSettle();

    await tikla(t, find.byKey(K.aktarmaOnizle));

    expect(repo.kuruSatirlar.length, 3);
    expect(repo.yazilanSatirlar, isEmpty,
        reason: 'önizlemede tek satır bile yazılmamalı');
    expect(find.byKey(K.aktarmaOzet), findsOneWidget);
    expect(find.textContaining('henüz hiçbir şey yazılmadı'), findsOneWidget);
  });

  testWidgets('önizleme özeti sayılarla ve hatalarla gelir', (t) async {
    final (_, kap) = await ac(t);
    kap.read(aktarmaProvider.notifier).dosyaYukle(csv(urunDosyasi), 'x.csv');
    await t.pumpAndSettle();
    await tikla(t, find.byKey(K.aktarmaOnizle));

    // Rozet yığını yerine tek oran şeridi: etiket + sayı yan yana.
    expect(find.text('Yeni 2'), findsOneWidget);
    expect(find.text('Güncelleme 1'), findsOneWidget);
    expect(find.text('Hatalı 1'), findsOneWidget);
    expect(find.byKey(K.aktarmaHatalar), findsOneWidget);
    expect(find.text('Ürün adı boş'), findsOneWidget,
        reason: 'hata sebebi satır numarasıyla listelenmeli');
    expect(find.text('4'), findsWidgets, reason: 'satır numarası');
  });

  testWidgets('uygula gerçek koşuyu yapar ve batch kapanır', (t) async {
    final (repo, kap) = await ac(t);
    kap.read(aktarmaProvider.notifier).dosyaYukle(csv(urunDosyasi), 'x.csv');
    await t.pumpAndSettle();
    await tikla(t, find.byKey(K.aktarmaOnizle));

    expect(find.text('3 satırı uygula'), findsOneWidget,
        reason: 'kaç satırın yazılacağı butonda yazmalı');
    await tikla(t, find.byKey(K.aktarmaUygula));

    expect(repo.yazilanSatirlar.length, 3);
    expect(repo.cagrilar, contains('batchKapat:b1'));
    expect(find.textContaining('Tamamlandı'), findsOneWidget);
    expect(find.byKey(K.aktarmaHataIndir), findsOneWidget,
        reason: 'hatalı satır varsa rapor indirilebilmeli');
  });

  testWidgets('satırlar Excel satır numarasıyla gönderilir', (t) async {
    final (repo, kap) = await ac(t);
    kap.read(aktarmaProvider.notifier).dosyaYukle(csv(urunDosyasi), 'x.csv');
    await t.pumpAndSettle();
    await tikla(t, find.byKey(K.aktarmaOnizle));

    expect(repo.kuruSatirlar.first['_satir'], 2,
        reason: 'hata mesajı kullanıcının Excel\'de gördüğü satırı göstermeli');
    expect(repo.kuruSatirlar.first['barkod'], '9781');
    expect(repo.kuruSatirlar.first['etiket_fiyat'], '120,50');
    expect(repo.kuruSatirlar[2].containsKey('ad'), isFalse,
        reason: 'boş hücre gönderilmemeli — mevcut değer korunsun');
  });

  testWidgets('çakışma politikası sunucuya iletilir', (t) async {
    final (repo, kap) = await ac(t);
    kap.read(aktarmaProvider.notifier).dosyaYukle(csv(urunDosyasi), 'x.csv');
    await t.pumpAndSettle();

    await tikla(t, find.text('Atla'));
    await tikla(t, find.byKey(K.aktarmaOnizle));

    expect(repo.sonPolitika, 'atla');
  });

  testWidgets('tür değişince akış sıfırlanır', (t) async {
    final (_, kap) = await ac(t);
    kap.read(aktarmaProvider.notifier).dosyaYukle(csv(urunDosyasi), 'x.csv');
    await t.pumpAndSettle();
    expect(find.byKey(K.aktarmaEslesme), findsOneWidget);

    await t.tap(find.text('Fiyat & iskonto'));
    await t.pumpAndSettle();

    expect(find.byKey(K.aktarmaEslesme), findsNothing,
        reason: 'ürün eşlemesi fiyat aktarımında geçersiz');
    expect(find.byKey(K.aktarmaDosyaSec), findsOneWidget);
  });

  testWidgets('geçmiş yüklemeler listelenir ve geri alınabilir', (t) async {
    final repo = SahteAktarmaRepo(gecmisListesi: [
      aktarma('urunler.xlsx'),
      aktarma('fiyat.xlsx', id: 'b2', durum: 'geri_alindi',
          eklenen: 12, guncellenen: 3, hatali: 0),
    ]);
    await ac(t, repo: repo);

    expect(find.textContaining('Ürün · urunler.xlsx'), findsOneWidget);
    expect(find.textContaining('340 yeni'), findsOneWidget);
    expect(find.text('Geri alındı'), findsOneWidget);

    await tikla(t, find.byKey(K.aktarmaGeriAl('b1')));
    expect(find.textContaining('340 kayıt silinir'), findsOneWidget,
        reason: 'geri almanın etkisi önceden söylenmeli');

    await t.tap(find.widgetWithText(FilledButton, 'Geri al'));
    await t.pumpAndSettle();
    expect(repo.cagrilar, contains('geriAl:b1'));
  });

  testWidgets('okunamayan dosya sebebiyle bildirilir', (t) async {
    final (_, kap) = await ac(t);
    kap.read(aktarmaProvider.notifier)
        .dosyaYukle(Uint8List.fromList([0, 1, 2]), 'bozuk.xlsx');
    await t.pumpAndSettle();

    expect(find.textContaining('Dosya okunamadı'), findsOneWidget);
    expect(find.byKey(K.aktarmaDosyaSec), findsOneWidget);
  });
}
