import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import 'cam.dart';
import 'dokunus.dart';
import 'mono.dart';

/// Listelerin TEK satır bileşeni.
///
/// Eski liste satırları dört olguyu tek gri satıra diziyordu
/// ("3 kalem · 25 adet · 27 Ağu · Emre Şahin") ve durumu rozet yığınıyla
/// anlatıyordu. Telefonda taranamıyordu: göz nereye bakacağını bilmiyor.
///
/// Bu satırın üç işi var ve üçü ayrı yerde durur:
///   sol şerit  → DURUM (tek renk, rozet yerine)
///   orta       → kimlik + bağlam
///   sağ sütun  → KARARI VERDİREN sayı ve tarihi, hizalı
class KayitSatiri extends StatelessWidget {
  const KayitSatiri({
    required this.baslik,
    this.altBilgi,
    this.vurgu,
    this.vurguRengi,
    this.deger,
    this.degerRengi,
    this.degerAlti,
    this.ikon,
    this.oncul,
    this.durumRengi,
    this.onTap,
    this.sondaki,
    super.key,
  });

  final String baslik;

  /// İkincil bilgi satırı — "6 kalem · 120 adet · Emre Şahin".
  final String? altBilgi;

  /// Dikkat çeken üçüncü satır: "3 gündür bekliyor", "1 kalem reddedildi".
  final String? vurgu;
  final Color? vurguRengi;

  /// Sağdaki asıl sayı. Mono hizalanır ki sütun taranabilsin.
  final String? deger;
  final Color? degerRengi;

  /// Sağ sütunun İKİNCİ satırı. Çoğu listede tarih; sayı sütununa ait
  /// olan başka bir ölçü de olabilir ("risk ₺12.164,09"). Adı bu yüzden
  /// `tarih` değil: yeri belli, içeriği ekranın işine göre değişir.
  final String? degerAlti;
  final IconData? ikon;

  /// İkon karesinin YERİNE konan öğe — sıra numarası, taşıma tutamağı,
  /// onay kutusu. [ikon] ile birlikte verilmez.
  final Widget? oncul;

  /// Sol şerit ve ikon zemininin rengi. Null ise şerit çizilmez.
  final Color? durumRengi;
  final VoidCallback? onTap;
  final Widget? sondaki;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final durum = durumRengi;

    return Dokunus(
      onTap: onTap,
      child: Container(
        // Şerit kenarlığın kendisi: ayrı bir kutu eklemek satırı şişiriyor.
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: durum ?? Colors.transparent,
              width: durum == null ? 0 : 3,
            ),
          ),
        ),
        padding: EdgeInsets.fromLTRB(
          durum == null ? T.s4 : T.s3,
          T.s3,
          T.s4,
          T.s3,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (oncul != null) ...[
              oncul!,
              const SizedBox(width: T.s3),
            ] else if (ikon != null) ...[
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: (durum ?? s.onSurfaceVariant).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(T.rDugme),
                ),
                child: Icon(ikon, size: 17, color: durum ?? s.onSurfaceVariant),
              ),
              const SizedBox(width: T.s3),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // İKİ satır: "15 Temmuz Şehitleri Ortaokulu Kurumsal"
                  // tek satıra sığmıyor ve her kurum adı "…Kuru…" diye
                  // kesiliyordu — okul adları burada kimliğin kendisi.
                  Text(
                    baslik,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.titleMedium,
                  ),
                  if (altBilgi != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        altBilgi!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodySmall,
                      ),
                    ),
                  if (vurgu != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        vurgu!,
                        style: t.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: vurguRengi ?? durum ?? s.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (deger != null || degerAlti != null) ...[
              const SizedBox(width: T.s3),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (deger != null)
                    Mono(
                      deger!,
                      size: 14,
                      weight: FontWeight.w600,
                      color: degerRengi,
                    ),
                  if (degerAlti != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(degerAlti!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.bodySmall),
                    ),
                ],
              ),
            ],
            ?sondaki,
          ],
        ),
      ),
    );
  }
}

/// Bekleyen iş satırı — Panel ve Bugün ekranlarının omurgası.
///
/// Eskiden her iş kalemi 113 piksellik bir `ListTile`'dı ve **sıfır olanlar da**
/// aynı yeri kaplıyordu: beş satırın tamamı "0" gösterip ekranın yarısını
/// yiyordu. Artık sıfırlar buraya hiç gelmez ([SifirOzeti] tek cümlede toplar).
///
/// Kendi yüzeyi YOK. Beş bekleyen iş, beş ayrı kenarlıklı kutu olarak
/// çizilince ekran parçalanıyordu: her kutunun kendi kenarı, kendi gölgesi,
/// aralarında kendi boşluğu. Beşi TEK cam levhanın içinde, aralarında saç
/// teli bir çizgiyle duruyor. Levha [IsGrubu].
class IsSatiri extends StatelessWidget {
  const IsSatiri({
    required this.baslik,
    required this.renk,
    this.altBilgi,
    this.sayi,
    this.deger,
    this.onTap,
    super.key,
  });

  final String baslik;
  final Color renk;
  final String? altBilgi;
  final int? sayi;
  final String? deger;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Dokunus(
      onTap: onTap,
      // `IntrinsicHeight` şart: `stretch` sınırsız yükseklikte sonsuz
      // yükseklik dayatıyor. Bedeli tek satır için ihmal edilebilir.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Durum şeridi levhanın sol kenarına dayanır: rozet yerine renk,
            // beş satırda tek bir dikey sütun olarak taranıyor.
            Container(width: 3, color: renk),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(T.s3, T.s3, T.s3, T.s3),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(baslik, style: t.titleMedium),
                          if (altBilgi != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                altBilgi!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.bodySmall,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: T.s3),
                    if (deger != null)
                      Mono(deger!, size: 15, weight: FontWeight.w600, color: renk)
                    else if (sayi != null)
                      Mono('$sayi', size: 18, weight: FontWeight.w600, color: renk),
                    if (onTap != null) ...[
                      const SizedBox(width: T.s2),
                      Icon(Icons.chevron_right, size: 16,
                          color: s.onSurfaceVariant),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// [IsSatiri]'ların durduğu cam levha.
///
/// Satırlar arasındaki çizgi kartın SOLUNDAN başlamaz: durum şeridi orada ve
/// çizgi onu kesince şerit beş parçaya bölünmüş gibi görünüyor. Çizgi şeridin
/// bittiği yerden başlar, sütun bütün kalır.
class IsGrubu extends StatelessWidget {
  const IsGrubu({required this.satirlar, super.key});
  final List<Widget> satirlar;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    if (satirlar.isEmpty) return const SizedBox.shrink();
    return CamKart(
      dolgu: false,
      child: Column(children: [
        for (final (i, x) in satirlar.indexed) ...[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.only(left: 3),
              child: Divider(
                  height: 1,
                  thickness: 1,
                  color: s.outlineVariant.withValues(alpha: 0.55)),
            ),
          x,
        ],
      ]),
    );
  }
}

/// Sıfır olan işleri TEK cümlede toplar.
///
/// "Hiçbir şey yok" bilgisi de bir bilgidir ama beş satır yer hak etmiyor.
class SifirOzeti extends StatelessWidget {
  const SifirOzeti(this.metin, {super.key});
  final String metin;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(T.s3, T.s2, T.s3, T.s2),
      child: Row(
        children: [
          Icon(Icons.check, size: 14, color: s.basarili),
          const SizedBox(width: T.s2),
          Expanded(
            child: Text(
              metin,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: s.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ekranın TEK baskın sayısı.
///
/// Her ekranda bir tane olur. Eskiden ciro, tahsilat ve alacak aynı puntoyla
/// yan yana duruyordu; göz hangisinin önemli olduğunu seçemiyordu.
class SayiBloku extends StatelessWidget {
  const SayiBloku({
    required this.etiket,
    required this.deger,
    this.renk,
    this.altBilgi,
    this.altBilgiRengi,
    this.boy = 30,
    super.key,
  });

  final String etiket, deger;
  final Color? renk;
  final String? altBilgi;
  final Color? altBilgiRengi;

  /// Punto. Ekranın baskın kartında büyür — bir sayının "baskın" olması
  /// yalnızca yerinden değil, boyundan da anlaşılır.
  final double boy;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        MikroEtiket(etiket),
        const SizedBox(height: 3),
        Mono(deger, size: boy, weight: FontWeight.w600, color: renk),
        if (altBilgi != null)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              altBilgi!,
              style: t.bodySmall?.copyWith(
                color: altBilgiRengi,
                fontWeight: altBilgiRengi == null ? null : FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}
