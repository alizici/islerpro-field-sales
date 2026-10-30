import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/tokens.dart';
import '../formatters/formatters.dart';
import 'form_kabuk.dart';
import 'dokunus.dart';
import 'mono.dart';

/// Uygulamanın TEK diyalog kabuğu.
///
/// On altı diyalog vardı ve altı farklı genişlik kullanıyorlardı: 380, 400,
/// 420, 440, 460, 480. Kimi gövdeyi kaydırıyordu kimi kaydırmıyor, kimi hatayı
/// en üste koymuş kimi en alta, kimi meşgulken "Vazgeç"i kapatıyor kimi
/// kapatmıyordu. Hepsi tek tek makuldü; yan yana konunca arayüz dağılıyordu.
///
/// Hata GÖVDENİN DIŞINDA, kaydırma alanının üstünde duruyor. Uzun bir formda
/// hatayı içeriye koymak, kullanıcının göremediği bir yerde bırakmak demek:
/// düğmeye basıyor, bir şey olmuyor, sebep ekranın dışında kalıyor.
class Diyalog extends StatelessWidget {
  const Diyalog({
    required this.baslik,
    required this.children,
    this.altBaslik,
    this.hata,
    this.onayEtiketi = 'Kaydet',
    this.onOnay,
    this.onayKey,
    this.mesgul = false,
    this.vazgecEtiketi = 'Vazgeç',
    this.onVazgec,
    this.ikincilEylem,
    this.genislik = 440,
    super.key,
  });

  final String baslik;
  final String? altBaslik;

  /// Gövde öğeleri — aralarına tutarlı boşluk KENDİLİĞİNDEN konur; çağıran
  /// `SizedBox(height: …)` yazmaz.
  final List<Widget> children;

  /// Sunucudan ya da doğrulamadan gelen hata. Kaydırma alanının ÜSTÜNDE,
  /// her zaman görünür.
  final String? hata;

  final String onayEtiketi;

  /// null ise onay düğmesi kapalıdır.
  final VoidCallback? onOnay;
  final Key? onayKey;

  /// Kaydediliyor: onay düğmesi çark gösterir, vazgeçme kapanır — yarım
  /// kalmış bir yazma işleminden kaçmak veri kaybettirebilir.
  final bool mesgul;

  final String vazgecEtiketi;
  final VoidCallback? onVazgec;

  /// Onayın solunda duran ikinci eylem (ör. "Geçen sefer").
  final Widget? ikincilEylem;
  final double genislik;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AlertDialog(
      // Gölge yerine DERİNLİK: diyalog kartlarla aynı yuvarlaklıkta ve aynı
      // ışıkta, ama arkasındaki perde daha koyu. Camın öne çıkması için
      // arkasının uzaklaşması gerekiyor — Material'ın hafif perdesi bunu
      // yapmıyordu ve diyalog sayfaya yapışık duruyordu.
      titlePadding: const EdgeInsets.fromLTRB(T.s5, T.s5, T.s5, T.s3),
      contentPadding: const EdgeInsets.symmetric(horizontal: T.s5),
      actionsPadding: const EdgeInsets.fromLTRB(T.s5, T.s4, T.s5, T.s4),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(baslik, maxLines: 2, overflow: TextOverflow.ellipsis),
          if (altBaslik != null)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(altBaslik!, style: t.bodySmall),
            ),
        ],
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: genislik,
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hata != null) Bildirim(hata!, tip: BildirimTip.hata),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < children.length; i++) ...[
                      if (i > 0) const SizedBox(height: T.s3),
                      children[i],
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed:
              mesgul ? null : (onVazgec ?? () => Navigator.pop(context, false)),
          child: Text(vazgecEtiketi),
        ),
        ?ikincilEylem,
        FilledButton(
          key: onayKey,
          onPressed: mesgul ? null : onOnay,
          child: mesgul
              ? const SizedBox(width: 16, height: 16, child: Bekleme(boy: 14))
              : Text(onayEtiketi),
        ),
      ],
    );
  }
}

/// Diyalog içindeki yüklenme — gövdenin yerini tutar, diyaloğu zıplatmaz.
class DiyalogYukleniyor extends StatelessWidget {
  const DiyalogYukleniyor({this.boy = 120, super.key});
  final double boy;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: boy,
        child: const Center(
          child: Bekleme(boy: 20),
        ),
      );
}

/// Para alanı.
///
/// Türkçe ondalık ayracı yedi ayrı yerde elle kuruluyordu; biri unutulduğunda
/// "100.00" değeri 10.000'e dönüşüyor ve kimse fark etmiyor. Ayrıştırma
/// [Fmt.sayiOku] ile tek yerde.
class ParaAlani extends StatelessWidget {
  const ParaAlani({
    required this.controller,
    required this.etiket,
    this.yardim,
    this.birim = '₺',
    this.alanKey,
    this.otomatikOdak = false,
    super.key,
  });

  final TextEditingController controller;
  final String etiket;
  final String? yardim;
  final String birim;
  final Key? alanKey;
  final bool otomatikOdak;

  @override
  Widget build(BuildContext context) => TextField(
        key: alanKey,
        controller: controller,
        autofocus: otomatikOdak,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
        ],
        decoration: InputDecoration(
          labelText: etiket,
          suffixText: birim,
          helperText: yardim,
          helperMaxLines: 3,
        ),
      );
}

/// Diyalogda "etiket … tutar" satırı — bakiye, tavan, doğacak borç.
class DiyalogOlcu extends StatelessWidget {
  const DiyalogOlcu(this.etiket, this.deger,
      {this.renk, this.altBilgi, this.kalin = false, super.key});
  final String etiket, deger;
  final Color? renk;
  final String? altBilgi;
  final bool kalin;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              MikroEtiket(etiket),
              if (altBilgi != null)
                Text(altBilgi!, style: t.bodySmall),
            ],
          ),
        ),
        const SizedBox(width: T.s3),
        Mono(deger,
            size: kalin ? 17 : 14, weight: FontWeight.w600, color: renk),
      ],
    );
  }
}
