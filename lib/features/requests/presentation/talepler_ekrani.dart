import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session.dart';
import '../../../core/test_keys.dart';
import '../../notifications/presentation/bildirimler.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/repositories/talep_repository.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/widgets/bolum.dart';
import '../../../shared/widgets/cam.dart';
import '../../../shared/widgets/liste.dart';
import '../../../shared/widgets/parcalar.dart';
import '../../../shared/widgets/satir.dart';
import 'talep_detay_ekrani.dart';
import 'talep_olustur_ekrani.dart';

class TalepFiltre {
  const TalepFiltre({this.sadeceAcik = true, this.sadeceGecikmis = false});
  final bool sadeceAcik, sadeceGecikmis;
  TalepFiltre kopya({bool? sadeceAcik, bool? sadeceGecikmis}) => TalepFiltre(
        sadeceAcik: sadeceAcik ?? this.sadeceAcik,
        sadeceGecikmis: sadeceGecikmis ?? this.sadeceGecikmis,
      );
}

class TalepFiltreNotifier extends Notifier<TalepFiltre> {
  @override
  TalepFiltre build() => const TalepFiltre();
  void ayarla(TalepFiltre f) => state = f;
}

final talepFiltreProvider = NotifierProvider<TalepFiltreNotifier, TalepFiltre>(
    TalepFiltreNotifier.new, isAutoDispose: true);

final taleplerProvider = FutureProvider.autoDispose((ref) {
  final f = ref.watch(talepFiltreProvider);
  final o = ref.watch(sessionProvider);
  return ref.watch(talepRepositoryProvider).liste(
        storeId: o?.storeId, sadeceBekleyen: f.sadeceAcik, limit: 100,
      );
});

/// Talep akışı — ürünün kalbi.
/// Pazarlamacı için gelen kutusu, öğretmen için "taleplerim".
class TaleplerEkrani extends ConsumerWidget {
  const TaleplerEkrani({super.key});

  /// Yeni talep akışı — hem başlık çubuğundan hem BOŞ EKRANDAN.
  Future<void> _yeniTalep(BuildContext context, WidgetRef ref) async {
    final acildi = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const TalepOlusturEkrani()));
    if (acildi == true) ref.invalidate(taleplerProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liste = ref.watch(taleplerProvider);
    final filtre = ref.watch(talepFiltreProvider);
    final oturum = ref.watch(sessionProvider);
    final s = Theme.of(context).colorScheme;
    final ogretmen = oturum?.aktifRol == AppRole.ogretmen;

    return CamSayfa(
      baslik: ogretmen ? 'Taleplerim' : 'Talepler',
      onYenile: () async => ref.invalidate(taleplerProvider),
      eylemler: [
          TextButton.icon(
            key: K.talepYeni,
            onPressed: () => _yeniTalep(context, ref),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Yeni talep'),
          ),
        const BildirimZili(),
        const SizedBox(width: T.s2),
      ],
      slivers: [
        ListeGovdesi<TalepOzet>(
        veri: liste.esle((hepsi) => filtre.sadeceGecikmis
            ? hepsi.where((t) => t.gecikmis).toList()
            : hepsi),
        listeKey: K.talepListesi,
        // Süzgeç çipleri SAYIYI da taşır: "kaç gecikmiş talep var" sorusu
        // süzgeci açmadan cevaplanmalı.
        ust: SuzgecSeridi(cipler: [
          SuzgecCipi(
            key: K.talepFiltreAcik,
            etiket: 'Açık talepler',
            sayi: liste.value?.where((x) => x.acik).length,
            secili: filtre.sadeceAcik,
            onTap: () => ref
                .read(talepFiltreProvider.notifier)
                .ayarla(filtre.kopya(sadeceAcik: !filtre.sadeceAcik)),
          ),
          // V7 · 24 saattir dokunulmamış talepler sahibe eskale olur
          SuzgecCipi(
            key: K.talepFiltreGecikmis,
            etiket: 'Gecikmiş',
            sayi: liste.value?.where((x) => x.gecikmis).length,
            renk: s.error,
            secili: filtre.sadeceGecikmis,
            onTap: () => ref
                .read(talepFiltreProvider.notifier)
                .ayarla(filtre.kopya(sadeceGecikmis: !filtre.sadeceGecikmis)),
          ),
        ]),
        bos: BosDurum(
          filtre.sadeceGecikmis ? 'Gecikmiş talep yok' : 'Bekleyen talep yok',
          ikon: Icons.inbox_outlined,
          aciklama: filtre.sadeceGecikmis
              ? '24 saattir dokunulmamış talep kalmadı — hepsi ele alınmış.'
              : 'Talep, bir kurumun "şu kitaplardan şu kadar istiyorum" '
                  'demesidir. Sahadan ya da öğretmenden gelir; onaylanınca '
                  'siparişe döner.',
          eylem: ogretmen
              ? null
              : FilledButton.icon(
                  onPressed: () => _yeniTalep(context, ref),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Talep aç'),
                ),
        ),
        satir: (_, t, _) => _TalepSatiri(t: t),
        ),
      ],
    );
  }
}

class _TalepSatiri extends ConsumerWidget {
  const _TalepSatiri({required this.t});
  final TalepOzet t;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = Theme.of(context).colorScheme;
    // Durum SOL ŞERİTTE. Eskiden iki-üç rozet yan yana diziliyordu ve göz
    // hangisinin önemli olduğunu seçemiyordu; şerit tek renk, tek anlam.
    // "Gönderildi" TURUNCU DEĞİL. Süzgeç "açık talepler" olduğunda listenin
    // tamamı gönderilmiş olur; hepsini uyarı rengiyle boyamak rengi
    // anlamsızlaştırıyor — her şey uyarıysa hiçbir şey uyarı değildir.
    // Renk yalnızca sıradan olmayanı işaretler:
    //   kırmızı = 24 saati geçti · mavi = biri ele almış · yeşil = karara
    //   bağlanmış · nötr = sırada bekliyor, olağan hâli
    final durum = switch (t.durum) {
      _ when t.gecikmis => s.error,
      'incelemede' => s.bilgi,
      'karara_baglandi' => s.basarili,
      'tamamen_reddedildi' => s.error,
      _ => s.onSurfaceVariant,
    };
    // Durum hep YAZILI ama iki farklı yerde: sıradan durum alt bilgi
    // satırında sessizce, dikkat isteyen durum ayrı renkli satırda.
    //
    // İlk denemede durum HER SATIRDA ayrı satırdı ve süzgeç "açık talepler"
    // olunca on satır birden "Gönderildi" diyordu — bilgi değil gürültü.
    // Yalnızca renge bırakmak da olmazdı: renk tek başına durum anlatamaz.
    final (String? vurgu, Color? vurguRenk) = switch (t) {
      _ when t.gecikmis => ('24 saati geçti', s.error),
      _ when t.bekleyen > 0 && t.durum == 'incelemede' =>
        ('${Fmt.adet(t.bekleyen)} kalem bekliyor', s.uyari),
      _ when t.durum == 'karara_baglandi' => (t.durumAdi, s.basarili),
      _ when t.durum == 'tamamen_reddedildi' => (t.durumAdi, s.error),
      _ => (null, null),
    };

    return KayitSatiri(
      key: K.talepSatiri(t.id),
      baslik: t.unvan,
      altBilgi: [
        if (vurgu == null) t.durumAdi,
        '${Fmt.adet(t.kalemSayisi)} kalem',
        if (t.acan != null) t.acan!,
      ].join(' · '),
      vurgu: vurgu,
      vurguRengi: vurguRenk,
      ikon: t.tip == 'ogretmen' ? Icons.person_outline : Icons.business_outlined,
      durumRengi: durum,
      deger: '${Fmt.adet(t.toplamAdet)} adet',
      degerAlti: Fmt.tarih(t.createdAt),
      onTap: () async {
        final degisti = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => TalepDetayEkrani(talepId: t.id)));
        if (degisti == true) ref.invalidate(taleplerProvider);
      },
    );
  }
}
