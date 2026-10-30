import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/test_keys.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/repositories/rapor_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/cam.dart';
import '../../../shared/widgets/bolum.dart';
import '../../../shared/widgets/form_kabuk.dart';
import '../../../shared/widgets/liste.dart';
import '../../../shared/widgets/parcalar.dart';
import '../../../shared/widgets/satir.dart';
import 'rapor_durumu.dart';
import 'rapor_ekrani.dart';

/// K50 · Rapor kataloğu.
///
/// Liste sunucudan gelir. Ekranda rapor adı SABİT YAZILI DEĞİLDİR: katalog
/// tabloya bir satır eklenince rapor burada kendiliğinden belirir — "rapor
/// eklemek yeni ekran değil, katalog kaydı yazmaktır" cümlesinin karşılığı.
///
/// K7 · Hiçbir rapor kurum düzeyinde BAKİYE toplamı üretemez; kuralı motor
/// uygular, bu ekran yalnızca sonucunu gösterir.
class RaporlarEkrani extends ConsumerWidget {
  const RaporlarEkrani({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final katalog = ref.watch(raporKatalogProvider);
    return CamSayfa(
      baslik: 'Raporlar',
      eylemler: [
          IconButton(
            tooltip: 'Yenile',
            onPressed: () {
              ref.invalidate(raporKatalogProvider);
              ref.invalidate(kayitliRaporlarProvider);
            },
          icon: const Icon(Icons.refresh, size: 20),
        ),
        const SizedBox(width: T.s2),
      ],
      cocuklar: katalog.when(
        loading: () => const [
          CamKart(dolgu: false, child: IskeletListe(satir: 7)),
        ],
        error: (e, _) => [Bildirim(e.toString(), tip: BildirimTip.hata)],
        data: (raporlar) {
          final gruplar = <String, List<RaporTanimi>>{};
          for (final r in raporlar) {
            (gruplar[r.grup] ??= []).add(r);
          }
          if (raporlar.isEmpty) {
            return const [
              CamKart(
                dolgu: false,
                child: BosDurum('Rapor kataloğu boş',
                    ikon: Icons.insights_outlined,
                    aciklama: 'Rapor eklemek yeni ekran açmak değil, katalog '
                        'kaydı yazmaktır — kayıt eklenince burada belirir.'),
              ),
            ];
          }
          return [
            const _Kayitlilar(),
            // Her grup KENDİ levhasında: katalogda beş grup var ve hepsi tek
            // levhaya dizilince ekran tek bir uzun listeye dönüşüyor, grup
            // başlıkları da o listenin içinde kayboluyor.
            for (final g in gruplar.entries)
              Padding(
                padding: const EdgeInsets.only(top: T.s4),
                child: Column(
                  key: g.key == gruplar.keys.first ? K.raporKatalog : null,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SayacSeridi(
                        '${RaporTanimi.grupAdlari[g.key] ?? g.key} · '
                        '${g.value.length}'),
                    CamKart(
                      dolgu: false,
                      child: Column(children: [
                        for (final r in g.value) _Satir(tanim: r),
                      ]),
                    ),
                  ],
                ),
              ),
            const SonBosluk(),
          ];
        },
      ),
    );
  }
}

class _Satir extends StatelessWidget {
  const _Satir({required this.tanim});
  final RaporTanimi tanim;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return KayitSatiri(
      key: K.raporKart(tanim.kod),
      baslik: tanim.ad,
      altBilgi: tanim.aciklama,
      ikon: Icons.insights_outlined,
      durumRengi: s.primary,
      sondaki: Padding(
        padding: const EdgeInsets.only(left: T.s2),
        child: Icon(Icons.chevron_right, size: 16, color: s.onSurfaceVariant),
      ),
      onTap: () => Navigator.of(context).push<void>(MaterialPageRoute(
          builder: (_) => RaporEkrani(tanim: tanim))),
    );
  }
}

/// K50 §1.3 · Kaydedilmiş raporlar. Kişisel olan yalnızca sahibinin;
/// dükkanla paylaşılan herkesin — ama başkasının kaydı OKUNUR, düzenlenmez.
class _Kayitlilar extends ConsumerWidget {
  const _Kayitlilar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liste = ref.watch(kayitliRaporlarProvider).value ?? const [];
    if (liste.isEmpty) return const SizedBox.shrink();
    return Column(
      key: K.raporKayitlilar,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SayacSeridi('Kayıtlı raporlar · ${liste.length}',
            sag: 'Süzgeç ve kırılımıyla birlikte saklandı'),
        for (final k in liste) _KayitliSatir(kayit: k),
      ],
    );
  }
}

class _KayitliSatir extends ConsumerWidget {
  const _KayitliSatir({required this.kayit});
  final KayitliRapor kayit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = Theme.of(context).colorScheme;
    final katalog = ref.watch(raporKatalogProvider).value ?? const [];
    final tanim = katalog.where((t) => t.kod == kayit.kod).firstOrNull;
    // K50 §1.3 · başkasının kaydı OKUNUR, düzenlenmez — sil düğmesi de
    // bu yüzden yalnızca sahibinde.
    return KayitSatiri(
      key: K.raporKayitli(kayit.id),
      baslik: kayit.ad,
      altBilgi: [
        kayit.raporAd ?? kayit.kod,
        if (kayit.kirilim.isNotEmpty) kayit.kirilim.join(' → '),
      ].join(' · '),
      // Paylaşım hâli HER İKİ durumda da yazılı: kendi kaydımın dükkanla
      // paylaşıldığını bilmezsem, sildiğimde başkasının da kaybettiğini
      // fark etmiyorum.
      vurgu: switch (kayit) {
        _ when !kayit.benim => 'Dükkan · paylaşan: ${kayit.olusturan ?? "—"}',
        _ when kayit.paylasimli => 'Dükkanla paylaşıldı',
        _ => null,
      },
      vurguRengi: s.bilgi,
      ikon: kayit.paylasimli ? Icons.groups_outlined : Icons.bookmark_outline,
      durumRengi: kayit.benim ? s.primary : s.bilgi,
      sondaki: kayit.benim
          ? IconButton(
              tooltip: 'Sil',
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: () async {
                await ref.read(raporRepositoryProvider).sil(kayit.id);
                ref.invalidate(kayitliRaporlarProvider);
              },
            )
          : null,
      onTap: tanim == null
          ? null
          : () => Navigator.of(context).push<void>(MaterialPageRoute(
              builder: (_) => RaporEkrani(tanim: tanim, kayitli: kayit))),
    );
  }
}
