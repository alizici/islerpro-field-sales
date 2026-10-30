import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/test_keys.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/local/yerel_saglayici.dart';
import '../../../data/repositories/ziyaret_repository.dart';
import '../../../shared/widgets/diyalog.dart';
import '../../../shared/widgets/form_kabuk.dart';
import '../../../shared/widgets/dokunus.dart';
import '../../../shared/widgets/parcalar.dart';
import 'ziyaret_detay_ekrani.dart';
import 'ziyaret_durumu.dart';

/// Açık ziyaret çubuğu — kabuğun en üstünde, HER ekranda.
///
/// K10 · Ziyaretin damgası açıkken oluşan kayıtlara otomatik düşer. Bu yüzden
/// "ziyaret açık mı" bilgisi ekranın kenarında değil GÖZ HİZASINDA durmalı:
/// açık kaldığı fark edilmeyen ziyaret, sonraki günün kayıtlarını da damgalar.
class ZiyaretCubugu extends ConsumerWidget {
  const ZiyaretCubugu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final z = ref.watch(acikZiyaretProvider).value;
    if (z == null) return const SizedBox.shrink();
    return _Cubuk(z: z);
  }
}

class _Cubuk extends ConsumerStatefulWidget {
  const _Cubuk({required this.z});
  final AcikZiyaret z;
  @override
  ConsumerState<_Cubuk> createState() => _CubukState();
}

class _CubukState extends ConsumerState<_Cubuk> {
  Timer? _saat;

  @override
  void initState() {
    super.initState();
    // Süre sunucudan değil cihazdan sayılır: her dakika bir istek atmak
    // yalnızca "kaç dakikadır içerideyim" sorusu için pahalıdır.
    _saat = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _saat?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final z = widget.z;
    final dk = DateTime.now().difference(z.girisSaati).inMinutes;
    final sure = dk < 60 ? '$dk dk' : '${dk ~/ 60} sa ${dk % 60} dk';

    return Material(
      key: K.ziyaretCubugu,
      color: T.bordo,
      child: SafeArea(
        bottom: false,
        child: Dokunus(
          // Kuyruktaki ziyaretin sunucuda kaydı yok; detay ekranı açılamaz.
          onTap: z.yerel
              ? null
              : () => Navigator.of(context).push<void>(MaterialPageRoute(
                  builder: (_) => ZiyaretDetayEkrani(ziyaretId: z.id))),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(T.s4, T.s2, T.s2, T.s2),
            child: Row(children: [
              Container(
                width: 8, height: 8,
                decoration: const BoxDecoration(
                    color: Colors.white, shape: BoxShape.circle),
              ),
              const SizedBox(width: T.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(z.kurumAd,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 13,
                            fontWeight: FontWeight.w600)),
                    Text(
                        '$sure · ${z.yerel
                            ? "çevrimdışı — senkronda yüklenecek"
                            : z.cikti.bos ? "henüz kayıt yok"
                                          : "${z.cikti.toplam} kayıt"}',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.75),
                            fontSize: 11.5)),
                  ],
                ),
              ),
              TextButton(
                key: K.ziyaretBitir,
                onPressed: () => ziyaretBitirAkisi(context, ref,
                    ziyaretId: z.id, yerel: z.yerel, kurumAd: z.kurumAd),
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                child: const Text('Bitir'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Ziyaret kapatma akışı: not/sonuç sorulur, kapanır, ÇIKTISI gösterilir.
/// Çıktı özeti bilinçli olarak kapanışta gösterilir — K10 ölçütü ziyaretin
/// hemen ardından görünür olmazsa kimse ona bakmaz.
Future<void> ziyaretBitirAkisi(
    BuildContext context, WidgetRef ref,
    {String? ziyaretId, bool yerel = false, String? kurumAd}) async {
  final sonuc = await showDialog<(String?, String?)>(
    context: context,
    builder: (_) => const _BitirDiyalogu(),
  );
  if (sonuc == null) return;
  if (!context.mounted) return;

  final kuyruk = ref.read(sahaKuyruguProvider);
  final cikis = DateTime.now();
  // K43 · Çevrimdışı açılmış ziyaretin sunucuda kimliği yok. Kapatma isteği
  // `visit_id: null` ile gider; sunucu onu açık ziyaretten çözer ve kuyruk
  // SIRAYLA işlendiği için o ziyaret bir önceki işlemin açtığıdır.
  final args = {
    'visit_id': yerel ? null : ziyaretId,
    'not_metni': sonuc.$1,
    'sonuc': sonuc.$2,
    'checked_out_at': cikis.toIso8601String(),
  };

  try {
    final r = yerel
        ? null
        : await kuyruk.dene(
            () => ref.read(ziyaretRepositoryProvider).bitir(
                ziyaretId: ziyaretId, notMetni: sonuc.$1, sonuc: sonuc.$2,
                cikisSaati: cikis),
            fn: 'end_visit', args: args, ozet: _ozet(kurumAd));
    if (yerel) {
      await kuyruk.db?.kuyrugaYaz('end_visit', args, _ozet(kurumAd),
          saat: cikis);
    }
    if (r == null) await kuyruk.yerelZiyaretKapat();
    ziyaretTazeleW(ref);
    if (!context.mounted) return;
    if (r == null) {
      // Çıktı özeti gösterilemez: damgayı sunucu, kuyruk yüklenince atacak.
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Ziyaret kapatıldı — senkronda yüklenecek')));
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => _OzetDiyalogu(
          kurumAd: r.kurumAd, dakika: r.dakika, cikti: r.cikti),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(e.toString())));
  }
}

/// Kuyruk satırı kullanıcıya gösterilecek: hangi kurum olduğu yazmalı.
String _ozet(String? kurumAd) =>
    kurumAd == null ? 'Ziyaret kapatma' : '$kurumAd · ziyaret kapatma';

class _BitirDiyalogu extends StatefulWidget {
  const _BitirDiyalogu();
  @override
  State<_BitirDiyalogu> createState() => _BitirDiyalogState();
}

const _sonuclar = <(String, String)>[
  ('olumlu', 'Olumlu — iş çıktı'),
  ('takip', 'Takip gerekiyor'),
  ('bulunamadi', 'Yetkili bulunamadı'),
  ('olumsuz', 'Olumsuz'),
];

class _BitirDiyalogState extends State<_BitirDiyalogu> {
  final _not = TextEditingController();
  String? _sonuc;

  @override
  void dispose() {
    _not.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Diyalog(
        baslik: 'Ziyareti bitir',
        // K10 · ziyaret ÇIKTIYLA ölçülür; sonuç kodu o çıktının özeti.
        altBaslik: 'Sonuç, bir sonraki ziyareti planlarken kullanılır',
        genislik: 400,
        onayEtiketi: 'Bitir',
        onayKey: K.ziyaretBitirOnay,
        onVazgec: () => Navigator.pop(context),
        onOnay: () => Navigator.pop(context, (_not.text, _sonuc)),
        children: [
          Wrap(spacing: T.s2, runSpacing: T.s2, children: [
            for (final s in _sonuclar)
              SuzgecCipi(
                key: K.ziyaretSonuc(s.$1),
                etiket: s.$2,
                secili: _sonuc == s.$1,
                onTap: () =>
                    setState(() => _sonuc = _sonuc == s.$1 ? null : s.$1),
              ),
          ]),
          TextField(
            key: K.ziyaretNot,
            controller: _not,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Not (isteğe bağlı)',
              hintText: 'Bir sonraki ziyarette hatırlanması gereken',
            ),
          ),
        ],
      );
}

class _OzetDiyalogu extends StatelessWidget {
  const _OzetDiyalogu(
      {required this.kurumAd, required this.dakika, required this.cikti});
  final String kurumAd;
  final int dakika;
  final ZiyaretCikti cikti;

  @override
  Widget build(BuildContext context) {
    final satirlar = <(String, int)>[
      ('Talep', cikti.talep),
      ('Sipariş', cikti.siparis),
      ('Teslimat', cikti.teslimat),
      ('Tahsilat', cikti.tahsilat),
      ('Eklenen kişi', cikti.kisi),
    ].where((e) => e.$2 > 0).toList();

    return Diyalog(
      key: K.ziyaretOzet,
      baslik: kurumAd,
      altBaslik: '$dakika dakika sürdü',
      genislik: 380,
      vazgecEtiketi: 'Tamam',
      onVazgec: () => Navigator.pop(context),
      children: [
        if (satirlar.isEmpty)
          // K10 · çıktısı olmayan ziyaret gizlenmez ve suçlanmaz: olgusal.
          const Bildirim('Bu ziyaretten kayıt çıkmadı.',
              tip: BildirimTip.bilgi)
        else
          for (final s in satirlar) DiyalogOlcu(s.$1, '${s.$2}'),
      ],
    );
  }
}
