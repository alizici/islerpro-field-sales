import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/test_keys.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/repositories/deneme_repository.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/widgets/cam.dart';
import '../../../shared/widgets/bolum.dart';
import '../../../shared/widgets/detay.dart';
import '../../../shared/widgets/liste.dart';
import '../../../shared/widgets/parcalar.dart';
import '../../../shared/widgets/satir.dart';
import 'program_detay_ekrani.dart';
import 'program_durumu.dart';

/// Deneme abonelik programları (C-3).
///
/// Dönem özeti listenin ÜSTÜNDE durur: "anlaşılan ile gerçekleşen" farkı,
/// bir sonraki dönemin anlaşmasını belirleyen tek sayıdır. Program listesi
/// onun altında, tek tek incelenmek için.
class ProgramlarEkrani extends ConsumerWidget {
  const ProgramlarEkrani({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = ref.watch(programlarProvider);
    return CamSayfa(
      baslik: 'Deneme Programları',
      onYenile: () async => programTazele(ref),
      eylemler: [
        IconButton(
          tooltip: 'Yenile',
          onPressed: () => programTazele(ref),
          icon: const Icon(Icons.refresh, size: 20),
        ),
        const SizedBox(width: T.s2),
      ],
      slivers: [
        ListeGovdesi<ProgramOzeti>(
        veri: l,
        listeKey: K.programListe,
        ust: const Column(mainAxisSize: MainAxisSize.min, children: [
          _DonemOzeti(),
          SayacSeridi('Programlar',
              sag: 'Yıllık anlaşma = iki program, her yarıyıl bir tane'),
        ]),
        bos: const BosDurum('Henüz deneme programı yok',
            ikon: Icons.event_repeat_outlined,
            aciklama: 'Program bir plandır: kendi başına borç doğurmaz. '
                'Borç, denemeler teslim edildikçe doğar.'),
        satir: (_, p, _) => _Satir(p: p),
        ),
      ],
    );
  }
}

class _DonemOzeti extends ConsumerWidget {
  const _DonemOzeti();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(donemOzetiProvider).value;
    final s = Theme.of(context).colorScheme;
    if (d == null || d.bos) return const SizedBox.shrink();

    return CamKart(
      key: K.programDonemOzeti,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: SayiBloku(
                etiket: 'Dönem cirosu',
                deger: Fmt.para(d.ciro),
                renk: s.basarili,
                altBilgi: [
                  ?d.donem,
                  '${d.program} program',
                  '${Fmt.adet(d.ogrenci)} öğrenci',
                ].join(' · '),
              ),
            ),
          ]),
          const SizedBox(height: T.s4),
          // Planlanan · teslim · uygulanan farkı, bir sonraki dönemin
          // anlaşmasını belirleyen tek şey. Üç sayıyı üç satıra yazmak
          // yerine tek çizgide: aradaki boşluk göze çarpsın.
          OranSeridi([
            ('Uygulanan', d.uygulanan.toDouble(), s.basarili),
            ('Teslim, uygulanmamış',
                (d.teslimEdilen - d.uygulanan).clamp(0, d.teslimEdilen)
                    .toDouble(),
                s.uyari),
            ('Teslim edilmemiş',
                (d.planlananKalem - d.teslimEdilen).clamp(0, d.planlananKalem)
                    .toDouble(),
                s.surfaceContainerHigh),
          ]),
          const SizedBox(height: T.s4),
          AlanSatiri('Planlanan kalem', '${d.planlananKalem}', mono: true),
          AlanSatiri('Teslim edilen', '${d.teslimEdilen}', mono: true),
          // K47 · "Uygulandı" ayrı sayılır: teslim edilmiş ama uygulanmamış
          // deneme sık görülür.
          AlanSatiri('Uygulanan', '${d.uygulanan}',
              mono: true,
              kalin: true,
              renk: d.uygulanan < d.teslimEdilen ? s.uyari : s.basarili,
              ikincil: 'Teslim edilmiş ama uygulanmamış deneme '
                  'sık görülür — ikisi ayrı sayılır'),
          if (d.ertelenen > 0)
            AlanSatiri('En az bir kez ertelenen', '${d.ertelenen}',
                mono: true, renk: s.uyari),
        ],
      ),
    );
  }
}

class _Satir extends ConsumerWidget {
  const _Satir({required this.p});
  final ProgramOzeti p;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = Theme.of(context).colorScheme;
    final eksik = p.kalem - p.teslimEdilen;
    return KayitSatiri(
      key: K.programSatir(p.id),
      baslik: p.unvan,
      altBilgi: [
        ?p.kurumAd,
        '${p.ogrenciSayisi} öğrenci',
        if (p.denemeAdedi != null) '${p.denemeAdedi} deneme',
        // Y-8 · iki program modu vardır ve ikisi farklı işler.
        p.modu == 'takvim_bagli' ? 'Takvime bağlı' : 'Serbest periyot',
      ].join(' · '),
      vurgu: switch (p) {
        _ when !p.aktif => 'Kapalı',
        _ when p.sonrakiTeslim != null =>
          'Sonraki teslim ${Fmt.tarih(p.sonrakiTeslim)}',
        _ => null,
      },
      vurguRengi: p.aktif ? s.bilgi : s.onSurfaceVariant,
      ikon: p.modu == 'takvim_bagli'
          ? Icons.event_repeat_outlined
          : Icons.autorenew,
      durumRengi: switch (p) {
        _ when !p.aktif => s.onSurfaceVariant,
        _ when eksik == 0 => s.basarili,
        _ => s.primary,
      },
      deger: '${p.teslimEdilen}/${p.kalem}',
      degerRengi: eksik == 0 ? s.basarili : null,
      onTap: () async {
        await Navigator.of(context).push<void>(MaterialPageRoute(
            builder: (_) => ProgramDetayEkrani(programId: p.id)));
        programTazele(ref, p.id);
      },
    );
  }
}
