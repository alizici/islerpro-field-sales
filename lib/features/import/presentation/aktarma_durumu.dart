import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session.dart';
import '../../../data/repositories/aktarma_repository.dart';
import '../../../data/services/tablo_okuyucu.dart';

/// K49 aktarma akışının durum makinesi.
///
/// Adımlar `bool yukleniyor` bayraklarıyla değil AÇIK TİPLERLE modellendi:
/// "eşleme ekranındayken önizleme sonucu var" gibi imkânsız durumlar
/// derleme zamanında dışarıda kalır.
sealed class AktarmaAdim {
  const AktarmaAdim();
}

class DosyaSecimi extends AktarmaAdim {
  const DosyaSecimi({this.hata});
  final String? hata;
}

class SutunEslemesi extends AktarmaAdim {
  const SutunEslemesi({required this.veri, required this.eslesme});
  final TabloVeri veri;
  final Map<String, String> eslesme;

  /// Anahtar sütun eşlenmeden ilerlenemez — yoksa her yükleme mükerrer üretir.
  bool anahtarVar(String tur) => switch (tur) {
        'urun' => eslesme.containsValue('ad'),
        'fiyat_iskonto' || 'stok' =>
          eslesme.containsValue('barkod') || eslesme.containsValue('urun_kod'),
        'kurum' => eslesme.containsValue('ad') || eslesme.containsValue('meb_kodu'),
        _ => eslesme.isNotEmpty,
      };

  String anahtarUyarisi(String tur) => switch (tur) {
        'urun' => 'Ürün adı sütunu eşlenmeli',
        'fiyat_iskonto' || 'stok' => 'Barkod veya ürün kodu sütunu eşlenmeli',
        'kurum' => 'Kurum adı veya MEB kodu sütunu eşlenmeli',
        _ => 'En az bir sütun eşlenmeli',
      };
}

class Onizleme extends AktarmaAdim {
  const Onizleme({required this.veri, required this.eslesme,
                  required this.ozet, required this.batchId});
  final TabloVeri veri;
  final Map<String, String> eslesme;
  final AktarmaOzet ozet;
  final String batchId;
}

class Uygulaniyor extends AktarmaAdim {
  const Uygulaniyor({required this.islenen, required this.toplam});
  final int islenen, toplam;
  double get oran => toplam == 0 ? 0 : islenen / toplam;
}

class Sonuclandi extends AktarmaAdim {
  const Sonuclandi({required this.batchId, required this.ozet});
  final String batchId;
  final AktarmaOzet ozet;
}

class AktarmaHatasi extends AktarmaAdim {
  const AktarmaHatasi(this.mesaj);
  final String mesaj;
}

class AktarmaDurumu {
  const AktarmaDurumu({
    this.tur = 'urun',
    this.politika = 'guncelle',
    this.dosyaAdi,
    this.adim = const DosyaSecimi(),
  });

  final String tur, politika;
  final String? dosyaAdi;
  final AktarmaAdim adim;

  AktarmaDurumu kopya({String? tur, String? politika,
                       String? dosyaAdi, AktarmaAdim? adim}) =>
      AktarmaDurumu(
        tur: tur ?? this.tur,
        politika: politika ?? this.politika,
        dosyaAdi: dosyaAdi ?? this.dosyaAdi,
        adim: adim ?? this.adim,
      );
}

class AktarmaNotifier extends Notifier<AktarmaDurumu> {
  @override
  AktarmaDurumu build() => const AktarmaDurumu();

  void turSec(String tur) =>
      state = AktarmaDurumu(tur: tur, politika: state.politika);

  void politikaSec(String p) => state = state.kopya(politika: p);

  void sifirla() =>
      state = AktarmaDurumu(tur: state.tur, politika: state.politika);

  /// Test edilebilirlik için dosya seçimi ayrıldı: [dosyaYukle] baytları alır,
  /// [dosyaSec] yalnızca seçiciyi açar.
  Future<void> dosyaSec() async {
    final d = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'xls', 'csv'],
    );
    if (d == null) return;
    dosyaYukle(await d.readAsBytes(), d.name);
  }

  void dosyaYukle(Uint8List bytes, String ad) {
    try {
      final veri = TabloOkuyucu.oku(bytes, ad);
      if (veri.bos) {
        state = state.kopya(
            adim: const DosyaSecimi(hata: 'Dosyada veri satırı bulunamadı.'));
        return;
      }
      state = state.kopya(
        dosyaAdi: ad,
        adim: SutunEslemesi(
          veri: veri,
          eslesme: SutunTahmini.tahminEt(veri.basliklar, state.tur),
        ),
      );
    } catch (e) {
      state = state.kopya(
          adim: DosyaSecimi(hata: 'Dosya okunamadı: $e'));
    }
  }

  void eslesmeAyarla(String baslik, String? alan) {
    final a = state.adim;
    if (a is! SutunEslemesi) return;
    final yeni = Map<String, String>.from(a.eslesme);
    if (alan == null || alan.isEmpty) {
      yeni.remove(baslik);
    } else {
      yeni.removeWhere((_, v) => v == alan);   // bir alan tek sütuna bağlanır
      yeni[baslik] = alan;
    }
    state = state.kopya(adim: SutunEslemesi(veri: a.veri, eslesme: yeni));
  }

  void eslesmeUygula(Map<String, String> eslesme) {
    final a = state.adim;
    if (a is! SutunEslemesi) return;
    state = state.kopya(adim: SutunEslemesi(veri: a.veri, eslesme: eslesme));
  }

  void eslemeyeDon() {
    final a = state.adim;
    final (veri, eslesme) = switch (a) {
      Onizleme o => (o.veri, o.eslesme),
      SutunEslemesi s => (s.veri, s.eslesme),
      _ => (null, null),
    };
    if (veri == null) return;
    state = state.kopya(
        adim: SutunEslemesi(veri: veri, eslesme: eslesme!));
  }

  List<Map<String, dynamic>> _satirlar(TabloVeri v, Map<String, String> e) =>
      [for (var i = 0; i < v.satirSayisi; i++) v.satirMap(i, e)];

  /// KURU KOŞU — uygulamayla aynı sunucu kodu, yazma kapalı.
  Future<void> onizle() async {
    final a = state.adim;
    if (a is! SutunEslemesi) return;
    final store = ref.read(sessionProvider)?.storeId;
    if (store == null) return;

    state = state.kopya(adim: const Uygulaniyor(islenen: 0, toplam: 1));
    try {
      final repo = ref.read(aktarmaRepositoryProvider);
      final batchId = await repo.batchAc(
        storeId: store, tur: state.tur,
        dosyaAdi: state.dosyaAdi, satirSayisi: a.veri.satirSayisi,
      );
      final satirlar = _satirlar(a.veri, a.eslesme);
      final ozet = await repo.tumunuGonder(
        batchId: batchId, satirlar: satirlar,
        politika: state.politika, kuruKosu: true, tur: state.tur,
        ilerleme: (i, t) =>
            state = state.kopya(adim: Uygulaniyor(islenen: i, toplam: t)),
      );
      state = state.kopya(adim: Onizleme(
          veri: a.veri, eslesme: a.eslesme, ozet: ozet, batchId: batchId));
    } catch (e) {
      state = state.kopya(adim: AktarmaHatasi(e.toString()));
    }
  }

  Future<void> uygula() async {
    final a = state.adim;
    if (a is! Onizleme) return;
    state = state.kopya(
        adim: Uygulaniyor(islenen: 0, toplam: a.veri.satirSayisi));
    try {
      final repo = ref.read(aktarmaRepositoryProvider);
      final ozet = await repo.tumunuGonder(
        batchId: a.batchId,
        satirlar: _satirlar(a.veri, a.eslesme),
        politika: state.politika,
        tur: state.tur,
        ilerleme: (i, t) =>
            state = state.kopya(adim: Uygulaniyor(islenen: i, toplam: t)),
      );
      await repo.batchKapat(a.batchId);
      state = state.kopya(adim: Sonuclandi(batchId: a.batchId, ozet: ozet));
    } catch (e) {
      state = state.kopya(adim: AktarmaHatasi(e.toString()));
    }
  }
}

final aktarmaProvider =
    NotifierProvider<AktarmaNotifier, AktarmaDurumu>(AktarmaNotifier.new,
        isAutoDispose: true);
