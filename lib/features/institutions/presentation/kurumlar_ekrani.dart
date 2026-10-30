import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/test_keys.dart';
import '../../../data/repositories/kurum_repository.dart';
import '../../../data/services/saha_kuyrugu.dart' show sunucuyaUlasilamadi;
import '../../../data/services/yerel_referans.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/widgets/bolum.dart';
import '../../../shared/widgets/cam.dart';
import '../../../shared/widgets/liste.dart';
import '../../../shared/widgets/parcalar.dart';
import '../../../shared/widgets/satir.dart';
import '../../../shared/widgets/yerel_uyari.dart';
import 'kurum_detay_ekrani.dart';
import 'kurum_ekle_diyalogu.dart';

class KurumFiltre {
  const KurumFiltre({this.q, this.ilce, this.kurumTipi});
  final String? q, ilce, kurumTipi;
  KurumFiltre kopya({String? q, String? ilce, String? kurumTipi, bool temizle = false}) =>
      temizle ? const KurumFiltre()
              : KurumFiltre(q: q ?? this.q, ilce: ilce ?? this.ilce,
                            kurumTipi: kurumTipi ?? this.kurumTipi);
}

/// Riverpod 3'te StateProvider kaldırıldı; autoDispose artık bir parametre.
class KurumFiltreNotifier extends Notifier<KurumFiltre> {
  @override
  KurumFiltre build() => const KurumFiltre();
  void ayarla(KurumFiltre f) => state = f;
  void temizle() => state = const KurumFiltre();
}

final kurumFiltreProvider =
    NotifierProvider<KurumFiltreNotifier, KurumFiltre>(
        KurumFiltreNotifier.new, isAutoDispose: true);

typedef KurumSonucu = (List<KurumOzet> liste, bool yerel);

final kurumAramaProvider = FutureProvider.autoDispose<KurumSonucu>((ref) async {
  final f = ref.watch(kurumFiltreProvider);
  try {
    final l = await ref.watch(kurumRepositoryProvider)
        .ara(q: f.q, ilce: f.ilce, kurumTipi: f.kurumTipi);
    return (l, false);
  } catch (e) {
    if (!sunucuyaUlasilamadi(e)) rethrow;
    // İl/ilçe ve kurum tipi süzgeçleri yerelde eksik kalır: cihaza yalnızca
    // PORTFÖYÜMDEKİ carilerin kurumları iner, dizinin tamamı değil. Süzgeç
    // seçiliyken bunu "eşleşen kurum yok" diye göstermek yanlış olurdu.
    if (f.ilce != null || f.kurumTipi != null) rethrow;
    final yerel = await ref.watch(yerelReferansProvider).kurumAra(q: f.q);
    if (yerel.isEmpty) rethrow;
    return (yerel, true);
  }
});

final bolgelerProvider = FutureProvider.autoDispose(
    (ref) => ref.watch(kurumRepositoryProvider).bolgeler());

/// K18 · Okul ve özel kurs merkezi tek dizinde.
class KurumlarEkrani extends ConsumerStatefulWidget {
  const KurumlarEkrani({super.key});
  @override
  ConsumerState<KurumlarEkrani> createState() => _KurumlarEkraniState();
}

class _KurumlarEkraniState extends ConsumerState<KurumlarEkrani> {
  /// Kurum ekleme — başlık çubuğundan da, boş ekrandan da.
  Future<void> _kurumEkle(String storeId) async {
    final id = await showDialog<String>(
      context: context,
      builder: (_) => KurumEkleDiyalogu(storeId: storeId),
    );
    if (id != null) ref.invalidate(kurumAramaProvider);
  }

  final _arama = TextEditingController();

  @override
  void dispose() { _arama.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final sonuc = ref.watch(kurumAramaProvider);
    final filtre = ref.watch(kurumFiltreProvider);
    final oturum = ref.watch(sessionProvider);
    final bagli =
        sonuc.value?.$1.where((k) => k.cariSayisi > 0).length ?? 0;

    return CamSayfa(
      baslik: 'Kurumlar',
      eylemler: [
          TextButton.icon(
            key: K.kurumEkle,
            onPressed:
                oturum == null ? null : () => _kurumEkle(oturum.storeId!),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Kurum ekle'),
          ),
          const SizedBox(width: T.s2),
      ],
      slivers: [
        ListeGovdesi<KurumOzet>(
          veri: sonuc.esle((r) => r.$1),
          listeKey: K.kurumListesi,
          // Arama ve süzgeçler listeyle BİRLİKTE kayar: telefonda ekranın
          // üçte birini sabit başlığa vermek listeyi okunmaz yapıyor.
          ust: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: T.s2),
          child: TextField(
            key: K.kurumArama,
            controller: _arama,
            onChanged: (v) => ref.read(kurumFiltreProvider.notifier).ayarla(filtre.kopya(q: v)),
            decoration: InputDecoration(
              hintText: 'Kurum adı ara…',
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _arama.text.isEmpty ? null : IconButton(
                icon: const Icon(Icons.clear, size: 16),
                onPressed: () {
                  _arama.clear();
                  ref.read(kurumFiltreProvider.notifier).temizle();
                  setState(() {});
                },
              ),
            ),
          ),
        ),
        _Filtreler(filtre: filtre),
              if (sonuc.value?.$2 == true)
                const Padding(
                  padding: EdgeInsets.fromLTRB(T.s4, T.s3, T.s4, 0),
                  child: YerelKopyaUyarisi(
                      ek: 'Yalnızca portföyündeki carilerin kurumları var — '
                          'dizinin tamamı cihazda tutulmuyor.'),
                ),
              SayacSeridi(
                '${Fmt.adet(sonuc.value?.$1.length ?? 0)} kurum',
                sag: bagli == 0 ? null : '$bagli tanesinde cari var',
              ),
            ]),
            bos: BosDurum(
              filtre.q == null && filtre.ilce == null && filtre.kurumTipi == null
                  ? 'Dizinde kurum yok'
                  : 'Eşleşen kurum yok',
              ikon: Icons.school_outlined,
              aciklama: 'Kurum, gittiğin YER: okul ya da kurs merkezi. '
                  'Alışveriş kurumla değil, kurumun altındaki carilerle '
                  'yapılır.',
              eylem: oturum == null
                  ? null
                  : FilledButton.icon(
                      onPressed: () => _kurumEkle(oturum.storeId!),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Kurum ekle'),
                    ),
            ),
            satir: (_, k, _) => _KurumSatiri(k: k),
        ),
      ],
    );
  }
}

class _Filtreler extends ConsumerWidget {
  const _Filtreler({required this.filtre});
  final KurumFiltre filtre;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bolgeler = ref.watch(bolgelerProvider);
    final ilceler = bolgeler.maybeWhen(
        data: (b) => b.map((e) => e.$2).where((e) => e.isNotEmpty).toSet().toList()..sort(),
        orElse: () => <String>[]);

    void ayarla(KurumFiltre f) =>
        ref.read(kurumFiltreProvider.notifier).ayarla(f);

    return SuzgecSeridi(cipler: [
      SuzgecCipi(
        etiket: 'Okul',
        secili: filtre.kurumTipi == 'okul',
        onTap: () => ayarla(KurumFiltre(
            q: filtre.q, ilce: filtre.ilce,
            kurumTipi: filtre.kurumTipi == 'okul' ? null : 'okul')),
      ),
      SuzgecCipi(
        etiket: 'Kurs merkezi',
        secili: filtre.kurumTipi == 'kurs_merkezi',
        onTap: () => ayarla(KurumFiltre(
            q: filtre.q, ilce: filtre.ilce,
            kurumTipi:
                filtre.kurumTipi == 'kurs_merkezi' ? null : 'kurs_merkezi')),
      ),
      for (final ilce in ilceler)
        SuzgecCipi(
          etiket: ilce,
          secili: filtre.ilce == ilce,
          onTap: () => ayarla(KurumFiltre(
              q: filtre.q, kurumTipi: filtre.kurumTipi,
              ilce: filtre.ilce == ilce ? null : ilce)),
        ),
    ]);
  }
}

class _KurumSatiri extends StatelessWidget {
  const _KurumSatiri({required this.k});
  final KurumOzet k;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    // Şerit "bu kurumla iş yapıyor muyuz" sorusunu cevaplar: cari bağlı
    // olan kurum dizinde bir kayıt değil, bir müşteridir.
    return KayitSatiri(
      key: ValueKey('kurum.${k.id}'),
      baslik: k.ad,
      altBilgi: k.altBilgi,
      vurgu: k.dogrulandi ? null : 'Doğrulanmadı — bilgileri teyit edilmeli',
      vurguRengi: s.uyari,
      ikon: k.kursMerkezi
          ? Icons.cast_for_education_outlined
          : Icons.school_outlined,
      durumRengi: k.bagli ? s.primary : null,
      deger: k.cariSayisi > 0 ? '${Fmt.adet(k.cariSayisi)} cari' : null,
      degerRengi: s.primary,
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => KurumDetayEkrani(kurumId: k.id))),
    );
  }
}
