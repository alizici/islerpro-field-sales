import 'package:flutter/material.dart';

import '../../../shared/widgets/bolum.dart';
import '../../../shared/widgets/cam.dart';

/// Faz 0 iskeleti — her ekran sırası geldiğinde bunun yerini alır.
///
/// Yönlendiricide artık hiçbir yol buraya düşmüyor; ağ olarak duruyor:
/// yeni bir hedef eklenip ekranı unutulursa kullanıcı boş beyaz bir sayfa
/// değil, ne olduğunu söyleyen bir sayfa görsün.
class YerTutucuEkran extends StatelessWidget {
  const YerTutucuEkran({required this.baslik, required this.ikon, super.key});
  final String baslik;
  final IconData ikon;

  @override
  Widget build(BuildContext context) => CamSayfa(
        baslik: baslik,
        cocuklar: [
          CamKart(
            dolgu: false,
            child: BosDurum(
              baslik,
              ikon: ikon,
              aciklama: 'Bu ekran henüz yapılmadı.',
            ),
          ),
        ],
      );
}
