import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session.dart';
import '../../../core/test_keys.dart';
import '../../notifications/presentation/bildirimler.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/repositories/cari_repository.dart';
import '../../../data/services/saha_kuyrugu.dart' show sunucuyaUlasilamadi;
import '../../../data/services/yerel_referans.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/widgets/bolum.dart';
import '../../../shared/widgets/cam.dart';
import '../../../shared/widgets/liste.dart';
import '../../../shared/widgets/parcalar.dart';
import '../../../shared/widgets/satir.dart';
import '../../../shared/widgets/yerel_uyari.dart';
import 'cari_detay_ekrani.dart';
import 'cari_ekle_diyalogu.dart';
import 'portfoy_atama_diyalogu.dart';

class CariFiltre {
  const CariFiltre({this.q, this.tip, this.borclu = false,
                    this.atanmamis = false});
  final String? q, tip;
  final bool borclu, atanmamis;

  CariFiltre kopya({Object? q = _yok, Object? tip = _yok,
                    bool? borclu, bool? atanmamis}) =>
      CariFiltre(
        q: q == _yok ? this.q : q as String?,
        tip: tip == _yok ? this.tip : tip as String?,
        borclu: borclu ?? this.borclu,
        atanmamis: atanmamis ?? this.atanmamis,
      );
  /// Hiçbir süzgeç uygulanmamış — liste boşsa sebebi arama değil, ortada
  /// gerçekten cari olmamasıdır. Boş ekranın hangi cümleyi kuracağını bu
  /// ayırıyor: "aramanı daralt" ile "henüz kimse yok" aynı şey değil.
  bool get bos => q == null && tip == null && !borclu && !atanmamis;

  static const _yok = Object();
}

class CariFiltreNotifier extends Notifier<CariFiltre> {
  @override
  CariFiltre build() => const CariFiltre();
  void ayarla(CariFiltre f) => state = f;
}

final cariFiltreProvider = NotifierProvider<CariFiltreNotifier, CariFiltre>(
    CariFiltreNotifier.new, isAutoDispose: true);

/// Toplu portföy ataması için seçim. Saha gerçeği: 300 cari tek tek atanmaz.
class CariSecimNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};
  void degistir(String id) =>
      state = state.contains(id) ? ({...state}..remove(id)) : {...state, id};
  void temizle() => state = const {};
  void hepsi(Iterable<String> idler) => state = idler.toSet();
}

/// Seçim MODU açık mı.
///
/// Onay kutusu her satırda sürekli duruyordu ve listenin asıl sorusunu
/// ("hangi cariye bakmam gerekiyor") bastırıyordu: göz önce kutulara
/// çarpıyor, sonra unvanı arıyordu. Toplu atama ayda birkaç kez yapılan
/// bir iş; listeyi her gün okuyan kişiye bedelini ödetmemeli.
class SecimModuNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void degistir() => state = !state;
  void kapat() => state = false;
}

final secimModuProvider =
    NotifierProvider<SecimModuNotifier, bool>(SecimModuNotifier.new,
        isAutoDispose: true);

final cariSecimProvider = NotifierProvider<CariSecimNotifier, Set<String>>(
    CariSecimNotifier.new, isAutoDispose: true);

/// İkinci alan "liste cihazdaki kopyadan mı geldi" — bakiyenin ne kadar taze
/// olduğunu kullanıcı bilmeli.
typedef CariSonucu = (List<CariOzet> liste, bool yerel);

final carilerProvider = FutureProvider.autoDispose<CariSonucu>((ref) async {
  final f = ref.watch(cariFiltreProvider);
  final o = ref.watch(sessionProvider);
  if (o?.storeId == null) return (const <CariOzet>[], false);
  try {
    final l = await ref.watch(cariRepositoryProvider).ara(
          storeId: o!.storeId!, q: f.q, tip: f.tip,
          borclu: f.borclu, atanmamis: f.atanmamis, periodId: o.periodId,
          limit: 200,
        );
    return (l, false);
  } catch (e) {
    if (!sunucuyaUlasilamadi(e)) rethrow;
    // `atanmamis` yerelde CEVAPLANAMAZ: portföy sahibi bilgisi cihaza inmiyor.
    // Süzgeci sessizce yok sayıp liste göstermek "atanmamış cari kalmamış"
    // yanılgısını üretirdi — hata olduğu gibi yükselir.
    if (f.atanmamis) rethrow;
    final yerel = await ref.watch(yerelReferansProvider)
        .cariAra(q: f.q, tip: f.tip, borclu: f.borclu);
    if (yerel.isEmpty) rethrow;   // kopya da yoksa hatayı gizleme
    return (yerel, true);
  }
});

final portfoyOzetiProvider = FutureProvider.autoDispose((ref) {
  final o = ref.watch(sessionProvider);
  if (o?.storeId == null || o?.periodId == null) {
    return Future.value(const PortfoyOzeti());
  }
  return ref.watch(cariRepositoryProvider)
      .portfoyOzeti(o!.storeId!, o.periodId!);
});

/// K5 · Muhatap caridir. K7 · Kurum bazlı TOPLAM burada asla gösterilmez.
class CarilerEkrani extends ConsumerStatefulWidget {
  const CarilerEkrani({super.key});
  @override
  ConsumerState<CarilerEkrani> createState() => _CarilerEkraniState();
}

class _CarilerEkraniState extends ConsumerState<CarilerEkrani> {
  final _arama = TextEditingController();
  Timer? _gecikme;

  @override
  void dispose() {
    _gecikme?.cancel();
    _arama.dispose();
    super.dispose();
  }

  void _ara(String v) {
    _gecikme?.cancel();
    _gecikme = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      final f = ref.read(cariFiltreProvider);
      ref.read(cariFiltreProvider.notifier)
          .ayarla(f.kopya(q: v.trim().isEmpty ? null : v.trim()));
    });
    setState(() {});
  }

  /// Cari açma — hem başlık çubuğundan hem BOŞ EKRANDAN çağrılıyor.
  /// "Sağ üstten ekleyebilirsin" diye yazmak, düğmeyi göstermek yerine
  /// tarif etmek demek; boş ekranın kendisi düğme olmalı.
  Future<void> _cariAc() async {
    final o = ref.read(sessionProvider);
    if (o?.storeId == null) return;
    final id = await showDialog<String>(
      context: context,
      builder: (_) => CariEkleDiyalogu(storeId: o!.storeId!),
    );
    if (id != null) {
      ref.invalidate(carilerProvider);
      ref.invalidate(portfoyOzetiProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final liste = ref.watch(carilerProvider);
    final filtre = ref.watch(cariFiltreProvider);
    final secim = ref.watch(cariSecimProvider);
    final secimModu = ref.watch(secimModuProvider);
    final oturum = ref.watch(sessionProvider);
    final yetkili = oturum?.aktifRol == AppRole.isletmeSahibi ||
        oturum?.aktifRol == AppRole.dukkanMuduru;

    return CamSayfa(
      baslik: 'Cariler',
      eylemler: [
          TextButton.icon(
            key: K.cariEkle,
            onPressed: oturum?.storeId == null ? null : _cariAc,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Cari aç'),
          ),
          if (yetkili)
            IconButton(
              key: K.cariSecimModu,
              tooltip: secimModu ? 'Seçimi kapat' : 'Toplu seç',
              onPressed: () {
                ref.read(secimModuProvider.notifier).degistir();
                ref.read(cariSecimProvider.notifier).temizle();
              },
              icon: Icon(
                  secimModu ? Icons.close : Icons.checklist_rtl_outlined,
                  size: 20),
            ),
        const BildirimZili(),
        const SizedBox(width: T.s2),
      ],
      slivers: [
        ListeGovdesi<CariOzet>(
          veri: liste.esle((sonuc) => sonuc.$1),
          listeKey: K.cariListesi,
          // Arama, süzgeç ve portföy özeti listeyle BİRLİKTE kayar. Sabit
          // tutulunca telefonda listeye üç satır kalıyordu.
          ust: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: T.s2),
          child: TextField(
            key: K.cariArama,
            controller: _arama,
            onChanged: _ara,
            decoration: InputDecoration(
              hintText: 'Cari unvanı veya kurum ara…',
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _arama.text.isEmpty ? null : IconButton(
                icon: const Icon(Icons.clear, size: 16),
                onPressed: () { _arama.clear(); _ara(''); },
              ),
            ),
          ),
        ),
        _Filtreler(filtre: filtre),
        if (yetkili && !secimModu) const _PortfoyOzeti(),
        if (secimModu) _SecimCubugu(secim: secim, yetkili: yetkili),
        // `liste.value` KULLANILAMAZ: hata hâlinde Riverpod önceki değeri
        // taşımaya devam ediyor ve süzgeç değişip istek reddedildiğinde
        // bayat "kopya gösteriliyor" uyarısı ekranda kalıyordu. `esle`
        // hatayı taze bir `AsyncError`e çeviriyor; onun değeri yok.
        if (liste.esle((sonuc) => sonuc.$2).value == true)
          const Padding(
            padding: EdgeInsets.only(top: T.s2),
            child: YerelKopyaUyarisi(
                ek: 'Bakiyeler o andan bu yana değişmiş olabilir; '
                    'pasif ve kapalı cariler bu listede yok.'),
          ),
          ]),
          bos: BosDurum(
            filtre.bos ? 'Henüz cari yok' : 'Eşleşen cari yok',
            ikon: Icons.account_balance_wallet_outlined,
            aciklama: filtre.bos
                // Uygulamanın en temel kelimesi ve hiçbir yerde
                // açıklanmıyordu: yeni bir kullanıcı "cari"nin ne olduğunu
                // tahmin edemez.
                ? 'Cari, alışverişin muhatabı: bir okulun kendi hesabı ya da '
                    'tek tek bir öğretmen. Bakiye, sipariş ve tahsilat hep '
                    'cariye işlenir.'
                : 'Aramayı daralt ya da süzgeçleri temizle.',
            eylem: filtre.bos
                ? (oturum?.storeId == null
                    ? null
                    : FilledButton.icon(
                        onPressed: _cariAc,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('İlk cariyi aç'),
                      ))
                : OutlinedButton(
                    onPressed: () {
                      _arama.clear();
                      ref.read(cariFiltreProvider.notifier)
                          .ayarla(const CariFiltre());
                      setState(() {});
                    },
                    child: const Text('Süzgeçleri temizle'),
                  ),
          ),
          satir: (_, c, _) => _CariSatiri(
              c: c,
              secili: secim.contains(c.id),
              secilebilir: yetkili && secimModu),
        ),
      ],
    );
  }
}

class _Filtreler extends ConsumerWidget {
  const _Filtreler({required this.filtre});
  final CariFiltre filtre;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void ayarla(CariFiltre f) => ref.read(cariFiltreProvider.notifier).ayarla(f);
    return SuzgecSeridi(cipler: [
      SuzgecCipi(
        key: K.cariFiltreKurum,
        etiket: 'Kurumsal',
        secili: filtre.tip == 'kurum',
        onTap: () => ayarla(
            filtre.kopya(tip: filtre.tip == 'kurum' ? null : 'kurum')),
      ),
      SuzgecCipi(
        key: K.cariFiltreOgretmen,
        etiket: 'Öğretmen',
        secili: filtre.tip == 'ogretmen',
        onTap: () => ayarla(
            filtre.kopya(tip: filtre.tip == 'ogretmen' ? null : 'ogretmen')),
      ),
      SuzgecCipi(
        key: K.cariFiltreBorclu,
        etiket: 'Bakiyesi olan',
        secili: filtre.borclu,
        onTap: () => ayarla(filtre.kopya(borclu: !filtre.borclu)),
      ),
      // W-2 · Atanmamış cari = kimsenin gelen kutusuna düşmeyen talep
      SuzgecCipi(
        key: K.cariFiltreAtanmamis,
        etiket: 'Portföysüz',
        renk: Theme.of(context).colorScheme.uyari,
        secili: filtre.atanmamis,
        onTap: () => ayarla(filtre.kopya(atanmamis: !filtre.atanmamis)),
      ),
    ]);
  }
}

/// Portföy dağılımı — BİLGİ, süzgeç değil.
///
/// Eskiden rozet yığınıydı ve hemen üstündeki süzgeç çipleriyle aynı şekle
/// sahipti: kullanıcı tıklayınca bir şey olmasını bekliyor, olmayınca
/// arayüzün bozuk olduğunu düşünüyordu. Aynı görünen iki şeyden biri
/// tıklanabilir, öbürü değilse ikisi de anlamını kaybeder.
class _PortfoyOzeti extends ConsumerWidget {
  const _PortfoyOzeti();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ozet = ref.watch(portfoyOzetiProvider).value;
    if (ozet == null) return const SizedBox.shrink();

    return SayacSeridi(
      'Portföy',
      key: K.cariPortfoyOzeti,
      sag: [
        for (final p in ozet.pazarlamacilar)
          '${p.adSoyad} ${Fmt.adet(p.cariSayisi)}',
        if (ozet.atanmamis > 0) '${Fmt.adet(ozet.atanmamis)} portföysüz',
      ].join('  ·  '),
      // Renk YOK: uyarı rengi bütün ismi boyuyordu, oysa uyaran şey
      // yalnızca "portföysüz" kısmı — o da süzgeç çipinde ve satırın
      // vurgusunda zaten kırmızı/turuncu duruyor.
      sagRengi: null,
    );
  }
}

class _SecimCubugu extends ConsumerWidget {
  const _SecimCubugu({required this.secim, required this.yetkili});
  final Set<String> secim;
  final bool yetkili;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = Theme.of(context).colorScheme;
    final oturum = ref.watch(sessionProvider);
    return Container(
      key: K.cariSecimCubugu,
      color: s.primaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: T.s4, vertical: T.s2),
      child: Row(children: [
        Text(
            secim.isEmpty
                ? 'Atanacak carileri seç'
                : '${Fmt.adet(secim.length)} cari seçildi',
            style: Theme.of(context).textTheme.bodyMedium),
        const Spacer(),
        TextButton(
          onPressed: () {
            ref.read(cariSecimProvider.notifier).temizle();
            ref.read(secimModuProvider.notifier).kapat();
          },
          child: const Text('Vazgeç'),
        ),
        const SizedBox(width: T.s2),
        FilledButton.icon(
          key: K.cariPortfoyAta,
          onPressed: (!yetkili || oturum?.periodId == null) ? null : () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (_) => PortfoyAtamaDiyalogu(
                  cariIdler: secim.toList(), periodId: oturum!.periodId!),
            );
            if (ok == true) {
              ref.read(cariSecimProvider.notifier).temizle();
              ref.read(secimModuProvider.notifier).kapat();
              ref.invalidate(carilerProvider);
              ref.invalidate(portfoyOzetiProvider);
            }
          },
          icon: const Icon(Icons.person_add_alt, size: 16),
          label: const Text('Portföye ata'),
        ),
      ]),
    );
  }
}

class _CariSatiri extends ConsumerWidget {
  const _CariSatiri({required this.c, required this.secili,
                     required this.secilebilir});
  final CariOzet c;
  final bool secili, secilebilir;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = Theme.of(context).colorScheme;
    // Beş rozete kadar yan yana diziliyordu ve hiçbiri öne çıkmıyordu.
    // Şerit tek bir şey söyler: bu cariye BAKMAM GEREKİYOR MU?
    final (Color? durum, String? vurgu) = switch (c) {
      _ when c.limitAsildi => (s.error, 'Kredi limiti aşıldı'),
      _ when c.tahsilatta => (s.uyari, 'Tahsilatta'),
      _ when c.atanmamis && c.aktif => (s.uyari, 'Portföysüz — talebi kutuya düşmez'),
      _ when !c.aktif => (s.outline, c.durumAdi),
      _ when c.bakiye > 0 => (s.error, null),
      _ => (null, null),
    };
    return KayitSatiri(
      key: K.cariSatiri(c.id),
      baslik: c.unvan,
      altBilgi: [
        if (c.altBilgi.isNotEmpty) c.altBilgi,
        if (c.discountTier != null) 'kademe ${c.discountTier}',
      ].join(' · '),
      vurgu: vurgu,
      ikon: secilebilir
          ? null
          : (c.ogretmen ? Icons.person_outline : Icons.business_outlined),
      // Seçim kutusu SOLDA. Sağdayken bakiye sütununu ikiye bölüyor, para
      // hizası bozuluyordu; oysa sağ sütunun tek işi taranabilir olmak.
      oncul: secilebilir
          ? SizedBox(
              width: 34,
              height: 34,
              child: Checkbox(
                  value: secili,
                  onChanged: (_) =>
                      ref.read(cariSecimProvider.notifier).degistir(c.id)),
            )
          : null,
      durumRengi: durum,
      deger: Fmt.para(c.bakiye),
      degerRengi: c.bakiye > 0 ? s.error : null,
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => CariDetayEkrani(cariId: c.id))),
    );
  }
}
