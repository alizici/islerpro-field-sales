import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/test_keys.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/repositories/ziyaret_repository.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/widgets/cam.dart';
import '../../../shared/widgets/bolum.dart';
import '../../../shared/widgets/detay.dart';
import '../../../shared/widgets/form_kabuk.dart';
import '../../../shared/widgets/liste.dart';
import '../../../shared/widgets/parcalar.dart';
import '../../../shared/widgets/satir.dart';
import 'ziyaret_cubugu.dart';
import 'ziyaret_durumu.dart';

const _sonucAdi = <String, String>{
  'olumlu': 'Olumlu — iş çıktı',
  'takip': 'Takip gerekiyor',
  'bulunamadi': 'Yetkili bulunamadı',
  'olumsuz': 'Olumsuz',
};

const _turAdi = <String, (String, IconData)>{
  'talep': ('Talep', Icons.inbox_outlined),
  'siparis': ('Sipariş', Icons.receipt_long_outlined),
  'teslimat': ('Teslimat', Icons.local_shipping_outlined),
  'tahsilat': ('Tahsilat', Icons.payments_outlined),
  'kisi': ('Kişi eklendi', Icons.person_add_alt_outlined),
};

/// K10 · Ziyaretin kanıtı. Konum yok; ne yapıldığı var.
class ZiyaretDetayEkrani extends ConsumerWidget {
  const ZiyaretDetayEkrani({required this.ziyaretId, super.key});
  final String ziyaretId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(ziyaretDetayProvider(ziyaretId));
    return CamSayfa(
      baslik: 'Ziyaret',
      cocuklar: d.when(
        loading: () => const [
          CamKart(dolgu: false, child: IskeletListe(satir: 4)),
        ],
        error: (e, _) => [Bildirim(e.toString(), tip: BildirimTip.hata)],
        data: (z) => [
          _Baslik(z: z, ziyaretId: ziyaretId),
          const SizedBox(height: T.s4),
          _Ciktilar(z: z),
          const SonBosluk(),
        ],
      ),
    );
  }
}

class _Baslik extends ConsumerWidget {
  const _Baslik({required this.z, required this.ziyaretId});
  final ZiyaretDetay z;
  final String ziyaretId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = Theme.of(context).colorScheme;
    return CamKart(
      key: K.ziyaretBaslik,
      dolgu: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DetayBandi(
            baslik: z.kurumAd,
            altBilgi: [z.ilce, z.pazarlamaci]
                .nonNulls
                .where((e) => e.isNotEmpty)
                .join(' · '),
            durum: z.acik ? 'Açık — henüz bitirilmedi' : 'Kapandı',
            durumRengi: z.acik ? s.uyari : s.basarili,
            ikon: Icons.place_outlined,
            // K10 · ziyaret ÇIKTIYLA ölçülür; süresiyle değil ama süre de
            // bağlamdır. Baskın sayı çıktı sayısı.
            etiket: 'Bu ziyaretten çıkan',
            deger: '${z.cikti.toplam} kayıt',
            degerRengi: z.cikti.bos ? s.onSurfaceVariant : s.basarili,
            degerAlti: z.acik ? null : '${z.dakika ?? 0} dakika sürdü',
            alt: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                AlanSatiri('Giriş', Fmt.tarihSaat(z.girisSaati)),
                if (!z.acik) AlanSatiri('Çıkış', Fmt.tarihSaat(z.cikisSaati)),
                if (z.gorusulen != null)
                  AlanSatiri('Görüşülen', z.gorusulen!),
                if (z.sonuc != null)
                  AlanSatiri('Sonuç', _sonucAdi[z.sonuc] ?? z.sonuc!),
                if (z.notMetni != null && z.notMetni!.isNotEmpty) ...[
                  const SizedBox(height: T.s2),
                  KuralNotu(z.notMetni!,
                      ikon: Icons.format_quote, renk: s.onSurfaceVariant),
                ],
                if (z.acik) ...[
                  const SizedBox(height: T.s3),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () async {
                        await ziyaretBitirAkisi(context, ref,
                            ziyaretId: ziyaretId, kurumAd: z.kurumAd);
                        ref.invalidate(ziyaretDetayProvider(ziyaretId));
                      },
                      icon: const Icon(Icons.stop_circle_outlined, size: 18),
                      label: const Text('Ziyareti bitir'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Ziyaretin ürettikleri. Boşsa gizlenmez — ölçüt tam olarak budur (K10).
class _Ciktilar extends StatelessWidget {
  const _Ciktilar({required this.z});
  final ZiyaretDetay z;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Column(
      key: K.ziyaretCikti,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SayacSeridi('Bu ziyaretten çıkanlar · ${z.cikti.toplam}',
            sag: 'Ziyaret açıkken oluşan kayıtlar otomatik damgalanır'),
        // K10 · çıktısı olmayan ziyaret GİZLENMEZ — ölçüt tam olarak budur.
        if (z.satirlar.isEmpty)
          const BosDurum('Henüz kayıt çıkmadı',
              ikon: Icons.hourglass_empty_outlined,
              aciklama: 'Ziyaret açıkken açılan talep, sipariş, teslimat ve '
                  'tahsilat kendiliğinden buraya düşer.')
        else
          for (final r in z.satirlar)
            KayitSatiri(
              baslik: r.baslik,
              altBilgi: [
                _turAdi[r.tur]?.$1 ?? r.tur,
                if (r.aciklama != null && r.aciklama!.isNotEmpty) r.aciklama!,
              ].join(' · '),
              ikon: _turAdi[r.tur]?.$2 ?? Icons.circle_outlined,
              durumRengi: s.basarili,
              deger: r.tutar == null ? null : Fmt.para(r.tutar),
              degerRengi: s.basarili,
              degerAlti: Fmt.tarihSaat(r.tarih).split(' ').last,
            ),
      ],
    );
  }
}
