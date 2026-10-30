import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../shared/formatters/formatters.dart';
import '../repositories/rapor_repository.dart';

/// K50 §3 · Rapor dışa aktarma.
///
/// **Excel ile PDF asla farklı rakam göstermez.** Bu cümle bir temenni değil,
/// bu dosyanın yapısı: ikisi de `RaporTablosu`'nu okur ve o tablo TEK yerde
/// üretilir. İki ayrı yazıcının aynı `RaporSonucu`'nu kendi başına yorumlaması
/// serbest bırakılsaydı, biri yuvarlar öteki yuvarlamaz ve fark yıllar sonra
/// bir denetimde ortaya çıkardı.
class RaporTablosu {
  const RaporTablosu({
    required this.basliklar,
    required this.satirlar,
    required this.toplam,
    required this.sayisal,
  });

  final List<String> basliklar;
  /// Ham değerler: metin `String`, sayısal alanlar `num`. Biçimlendirme
  /// yazıcının işi — Excel sayıyı SAYI olarak almalı ki pivot çekilebilsin.
  final List<List<Object?>> satirlar;
  final List<Object?> toplam;
  /// Sütun sayısal mı — hizalama ve hücre tipi buna bakar.
  final List<bool> sayisal;

  bool get toplamVar => toplam.any((e) => e != null);

  static RaporTablosu kur(RaporSonucu r) => RaporTablosu(
        basliklar: [for (final s in r.sutunlar) s.ad],
        sayisal: [for (final s in r.sutunlar) s.sayisal],
        satirlar: [
          for (final satir in r.satirlar)
            [for (final s in r.sutunlar) _deger(satir[s.anahtar], s)],
        ],
        toplam: [
          for (final s in r.sutunlar)
            s.kirilim ? null : _deger(r.toplam[s.anahtar], s),
        ],
      );

  static Object? _deger(Object? ham, RaporSutunu s) {
    if (ham == null) return s.kirilim ? '' : 0;
    if (s.kirilim) return ham.toString();
    if (ham is num) return ham;
    return num.tryParse(ham.toString()) ?? 0;
  }

  /// Ekranda ne yazıyorsa dosyada da o yazsın diye biçimlendirme burada.
  static String yaz(Object? d, String tip) => switch (tip) {
        'para' => Fmt.para((d as num?)?.toDouble()),
        'oran' => '%${(((d as num?)?.toDouble() ?? 0) * 100).toStringAsFixed(1)}',
        'sayi' => Fmt.adet((d as num?)?.toInt() ?? 0),
        _ => d?.toString() ?? '',
      };
}

/// Dosyaların başında duran künye. "Hangi rapor, hangi süzgeçle, ne zaman" —
/// bu üçü olmadan çıktı bir hafta sonra kime ait olduğu bilinmeyen bir tablo.
class RaporKunyesi {
  const RaporKunyesi({
    required this.raporAd, required this.isletme, required this.dukkan,
    this.uretildi, this.satirlar = const [], this.uyarilar = const [],
  });
  final String raporAd, isletme, dukkan;
  final DateTime? uretildi;
  /// ('Dönem', '2025-2026 / 1. Dönem') gibi.
  final List<(String, String)> satirlar;
  final List<String> uyarilar;

  List<(String, String)> get tumu => [
        ('Rapor', raporAd),
        ('İşletme', isletme),
        ('Dükkan', dukkan),
        ('Oluşturma', Fmt.tarihSaat(uretildi ?? DateTime.now())),
        ...satirlar,
      ];
}

abstract final class RaporDisaAktar {
  /// Excel: ham satırlar + kırılım toplamı, ve İLK SAYFADA filtre özeti.
  ///
  /// Sayısal alanlar `DoubleCellValue`/`IntCellValue` olarak yazılır. Metin
  /// olarak yazmak Excel'de pivot çekmeyi imkânsız kılıyor — kullanıcının
  /// raporu dışarı almaktaki asıl amacı da genelde budur.
  static Uint8List excel(RaporSonucu r, RaporKunyesi k) {
    final t = RaporTablosu.kur(r);
    final kitap = Excel.createExcel();
    final ilk = kitap.getDefaultSheet() ?? 'Sheet1';
    kitap.rename(ilk, 'Künye');

    final ozet = kitap['Künye'];
    for (final (etiket, deger) in k.tumu) {
      ozet.appendRow([TextCellValue(etiket), TextCellValue(deger)]);
    }
    if (k.uyarilar.isNotEmpty) {
      ozet.appendRow([TextCellValue('')]);
      for (final u in k.uyarilar) {
        ozet.appendRow([TextCellValue('Uyarı'), TextCellValue(u)]);
      }
    }

    final s = kitap['Veri'];
    s.appendRow([for (final b in t.basliklar) TextCellValue(b)]);
    for (final satir in t.satirlar) {
      s.appendRow([for (var i = 0; i < satir.length; i++) _hucre(satir[i])]);
    }
    if (t.toplamVar) {
      s.appendRow([
        for (var i = 0; i < t.toplam.length; i++)
          i == 0 ? TextCellValue('TOPLAM') : _hucre(t.toplam[i]),
      ]);
    }
    return Uint8List.fromList(kitap.encode() ?? const []);
  }

  static CellValue _hucre(Object? d) => switch (d) {
        final int i => IntCellValue(i),
        final num n => DoubleCellValue(n.toDouble()),
        _ => TextCellValue(d?.toString() ?? ''),
      };

  /// PDF: başlıkta künye, her sayfada tekrarlanan tablo başlığı ve sayfa no.
  ///
  /// [yaziTipi] gömülü IBMPlexSans olmalı: paketin varsayılan Helvetica'sı
  /// ş/ğ/İ/ı taşımıyor ve bunları SESSİZCE boş kare basıyor — Türkçe bir
  /// raporda fark edilmesi en kolay, kabul edilmesi en zor hata.
  static Future<Uint8List> pdf(RaporSonucu r, RaporKunyesi k,
      {required Uint8List yaziTipi, bool yatay = true}) async {
    final t = RaporTablosu.kur(r);
    final font = pw.Font.ttf(ByteData.sublistView(yaziTipi));
    final tema = pw.ThemeData.withFont(base: font, bold: font);
    final belge = pw.Document(theme: tema);

    pw.Widget hucre(String metin, {required bool sag, bool kalin = false}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          child: pw.Text(metin,
              textAlign: sag ? pw.TextAlign.right : pw.TextAlign.left,
              style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: kalin ? pw.FontWeight.bold : pw.FontWeight.normal)),
        );

    final baslikSatiri = pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey300),
      // Başlık her sayfada tekrar eder: uzun tabloda ikinci sayfadan itibaren
      // sütunun ne olduğu bilinmezse tablo okunamaz.
      repeat: true,
      children: [
        for (var i = 0; i < t.basliklar.length; i++)
          hucre(t.basliklar[i], sag: t.sayisal[i], kalin: true),
      ],
    );

    belge.addPage(pw.MultiPage(
      pageFormat: yatay
          ? PdfPageFormat.a4.landscape
          : PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(24),
      header: (c) => c.pageNumber == 1
          ? _kunye(k)
          : pw.Container(
              padding: const pw.EdgeInsets.only(bottom: 6),
              child: pw.Text(k.raporAd,
                  style: const pw.TextStyle(fontSize: 9,
                      color: PdfColors.grey700))),
      footer: (c) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('${c.pageNumber} / ${c.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
      ),
      build: (c) => [
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey400, width: .4),
          children: [
            baslikSatiri,
            for (final satir in t.satirlar)
              pw.TableRow(children: [
                for (var i = 0; i < satir.length; i++)
                  hucre(
                      RaporTablosu.yaz(satir[i],
                          t.sayisal[i] ? r.sutunlar[i].tip : 'metin'),
                      sag: t.sayisal[i]),
              ]),
            if (t.toplamVar)
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  for (var i = 0; i < t.toplam.length; i++)
                    hucre(
                        i == 0
                            ? 'TOPLAM'
                            : RaporTablosu.yaz(t.toplam[i], r.sutunlar[i].tip),
                        sag: t.sayisal[i], kalin: true),
                ],
              ),
          ],
        ),
      ],
    ));
    return Uint8List.fromList(await belge.save());
  }

  static pw.Widget _kunye(RaporKunyesi k) => pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 10),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
          pw.Text(k.raporAd,
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 3),
          pw.Text(
              k.tumu
                  .where((e) => e.$1 != 'Rapor')
                  .map((e) => '${e.$1}: ${e.$2}')
                  .join('  ·  '),
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
          for (final u in k.uyarilar) ...[
            pw.SizedBox(height: 3),
            pw.Text(u,
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.orange900)),
          ],
          pw.SizedBox(height: 6),
          pw.Divider(height: 1, color: PdfColors.grey400),
        ]),
      );
}
