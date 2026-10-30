import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/test_keys.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/repositories/ticari_repository.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/widgets/cam.dart';
import '../../../shared/widgets/bolum.dart';
import '../../../shared/widgets/form_kabuk.dart';
import '../../../shared/widgets/liste.dart';
import '../../../shared/widgets/mono.dart';
import '../../../shared/widgets/parcalar.dart';
import '../../../shared/widgets/satir.dart';
import 'cek_diyalogu.dart';
import 'ticari_durumu.dart';

/// K11 · Vade takvimi.
///
/// Rapor değil TAKVİM: gün gün gruplanır. "Bu hafta kasaya ne giriyor"
/// sorusunun cevabı bir listeyi tarayarak değil, bir tarihe bakarak alınmalı.
///
/// Gecikmişler takvimin İÇİNDE değil ÜSTÜNDE durur — takvimde aşağı
/// kaydırılınca gözden kaybolan bir gecikmiş çek, gecikmemiş sayılır.
class VadeTakvimiEkrani extends ConsumerWidget {
  const VadeTakvimiEkrani({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = ref.watch(vadeTakvimiProvider);
    return CamSayfa(
      baslik: 'Vadeler',
      onYenile: () async => ref.invalidate(vadeTakvimiProvider),
      eylemler: [
        IconButton(
          tooltip: 'Yenile',
          onPressed: () => ref.invalidate(vadeTakvimiProvider),
          icon: const Icon(Icons.refresh, size: 20),
        ),
        const SizedBox(width: T.s2),
      ],
      cocuklar: v.when(
        loading: () => const [
          _OzetIskeleti(),
          SizedBox(height: T.s4),
          CamKart(dolgu: false, child: IskeletListe(satir: 5, ikon: false)),
        ],
        error: (e, _) => [Bildirim(e.toString(), tip: BildirimTip.hata)],
        data: (d) => [
          _Ozet(d: d),
          if (d.gecikmis.isNotEmpty) ...[
            const SizedBox(height: T.s4),
            _Gecikmisler(d: d),
          ],
          const SizedBox(height: T.s4),
          _Takvim(d: d),
          const SonBosluk(),
        ],
      ),
    );
  }
}

class _OzetIskeleti extends StatelessWidget {
  const _OzetIskeleti();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: T.s3),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Iskelet(90, 10),
          SizedBox(height: T.s2),
          Iskelet(170, 26),
          SizedBox(height: T.s4),
          Iskelet(double.infinity, 7, yuvarlak: 4),
        ]),
      );
}

class _Ozet extends StatelessWidget {
  const _Ozet({required this.d});
  final VadeTakvimi d;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return CamKart(
      key: K.vadeOzet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: SayiBloku(
                etiket: 'Portföyde',
                deger: Fmt.para(d.portfoyde),
                altBilgi: 'Vadesi gelmemiş çek ve senet',
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (d.tahsilde > 0)
                  _Yan('Tahsilde', Fmt.para(d.tahsilde), s.bilgi),
                if (d.karsiliksiz > 0)
                  _Yan('Karşılıksız', Fmt.para(d.karsiliksiz), s.error),
                if (d.gecikmisTutar > 0)
                  _Yan('Vadesi geçmiş', Fmt.para(d.gecikmisTutar), s.error),
              ],
            ),
          ]),
          // Üç sayıyı üç kutuya yazmak yerine tek çizgi: hangi kova ağır
          // basıyor, okumadan görülüyor.
          if (d.portfoyde + d.tahsilde + d.karsiliksiz > 0) ...[
            const SizedBox(height: T.s4),
            OranSeridi([
              ('Portföyde', d.portfoyde, s.primary),
              ('Tahsilde', d.tahsilde, s.bilgi),
              ('Karşılıksız', d.karsiliksiz, s.error),
            ]),
          ],
          const SizedBox(height: T.s4),
          // K11 · Bu tutar tahsil edilmiş para DEĞİLDİR.
          const KuralNotu(
              'Portföydeki çek ödeme değil ödeme vaadidir — risk hesabına '
              'girer, bakiyeden düşmez.'),
        ],
      ),
    );
  }
}

class _Yan extends StatelessWidget {
  const _Yan(this.etiket, this.deger, this.renk);
  final String etiket, deger;
  final Color renk;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(etiket, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(width: T.s2),
          Mono(deger, size: 13, weight: FontWeight.w600, color: renk),
        ]),
      );
}

class _Gecikmisler extends StatelessWidget {
  const _Gecikmisler({required this.d});
  final VadeTakvimi d;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return CamKart(
      key: K.vadeGecikmis,
      dolgu: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Baslik('Vadesi geçmiş', Fmt.para(d.gecikmisTutar),
              renk: s.error, zemin: s.error.withValues(alpha: 0.08)),
          for (final c in d.gecikmis) _CekSatiri(c: c, gecikmis: true),
        ],
      ),
    );
  }
}

class _Takvim extends StatelessWidget {
  const _Takvim({required this.d});
  final VadeTakvimi d;

  @override
  Widget build(BuildContext context) => CamKart(
        key: K.vadeTakvim,
        dolgu: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Baslik('Yaklaşan vadeler · 90 gün', Fmt.para(d.toplam)),
            if (d.gunler.isEmpty)
              const BosDurum('Yaklaşan vade yok',
                  ikon: Icons.event_available_outlined,
                  aciklama: 'Vade, bir çekin ya da senedin tahsil edilebilir '
                      'olacağı gün. Önümüzdeki 90 günde vadesi dolan bir şey '
                      'yok.')
            else
              for (final g in d.gunler) _Gun(g: g),
          ],
        ),
      );
}

/// Bölüm başlığı şeridi — takvimde gün başlıklarından bir ton koyu.
class _Baslik extends StatelessWidget {
  const _Baslik(this.baslik, this.deger, {this.renk, this.zemin});
  final String baslik, deger;
  final Color? renk, zemin;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Container(
      color: zemin ?? s.surfaceContainerLowest,
      padding: const EdgeInsets.fromLTRB(T.s4, T.s3, T.s4, T.s3),
      child: Row(children: [
        Expanded(child: MikroEtiket(baslik, color: renk)),
        Mono(deger, size: 14, weight: FontWeight.w600, color: renk),
      ]),
    );
  }
}

class _Gun extends StatelessWidget {
  const _Gun({required this.g});
  final VadeGunu g;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    // Bugün ve yarın ayrı okunur: "0 gün" diye bir şey yok.
    final ne = switch (g.gun) {
      0 => 'bugün',
      1 => 'yarın',
      _ => '${g.gun} gün sonra',
    };
    // Yakın vade vurgulu: bu hafta kasaya girecek para, iki ay sonrakiyle
    // aynı sesle yazılmamalı.
    final yakin = g.gun <= 7;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        decoration: BoxDecoration(
          color: s.surfaceContainerHigh,
          border: Border(
            top: BorderSide(color: s.outlineVariant),
            left: BorderSide(
                color: yakin ? s.primary : Colors.transparent, width: 3),
          ),
        ),
        padding: EdgeInsets.fromLTRB(yakin ? T.s3 : T.s4, T.s2, T.s4, T.s2),
        child: Row(children: [
          Expanded(
            child: Text('${Fmt.tarih(g.tarih)} · $ne',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: yakin ? FontWeight.w600 : null,
                      color: yakin ? s.primary : null,
                    )),
          ),
          Mono(Fmt.para(g.tutar), size: 13, weight: FontWeight.w600),
        ]),
      ),
      for (final c in g.cekler) _CekSatiri(c: c),
    ]);
  }
}

class _CekSatiri extends ConsumerWidget {
  const _CekSatiri({required this.c, this.gecikmis = false});
  final Cek c;
  final bool gecikmis;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = Theme.of(context).colorScheme;
    final renk = switch (c.durum) {
      'karsiliksiz' => s.error,
      'tahsil_edildi' => s.basarili,
      'tahsilde' => s.bilgi,
      _ when gecikmis => s.error,
      _ => s.onSurfaceVariant,
    };
    final durumAdi = cekDurumAdi[c.durum] ?? c.durum;

    return KayitSatiri(
      key: K.cekSatir(c.id),
      baslik: c.unvan,
      altBilgi: [
        c.tip == 'senet' ? 'Senet' : 'Çek',
        durumAdi,
        if (c.banka != null && c.banka!.isNotEmpty) c.banka!,
        if (c.kesideci != null && c.kesideci!.isNotEmpty) c.kesideci!,
      ].join(' · '),
      vurgu: gecikmis
          ? '${c.gun} gün gecikti'
          : (c.durum == 'karsiliksiz' ? 'Karşılıksız çıktı' : null),
      vurguRengi: s.error,
      durumRengi: renk,
      deger: Fmt.para(c.tutar),
      degerRengi: gecikmis ? s.error : null,
      onTap: () => cekDurumAkisi(context, ref, c),
    );
  }
}
