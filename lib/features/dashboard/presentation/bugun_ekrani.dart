import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session.dart';
import '../../../core/test_keys.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/repositories/siparis_repository.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/widgets/liste.dart';
import '../../../shared/widgets/dokunus.dart';
import '../../../shared/widgets/bolum.dart';
import '../../../shared/widgets/baslangic.dart';
import '../../../shared/widgets/cam.dart';
import '../../../shared/widgets/form_kabuk.dart';
import '../../../shared/widgets/parcalar.dart';
import '../../../shared/widgets/satir.dart';
import '../../notifications/presentation/bildirimler.dart';
import '../../requests/presentation/talep_detay_ekrani.dart';
import '../../exams/presentation/deneme_durumu.dart';
import '../../exams/presentation/deneme_takvimi_ekrani.dart';
import '../../sync/presentation/senkron_durumu.dart';
import '../../sync/presentation/senkron_ekrani.dart';
import '../../visits/presentation/rota_ekrani.dart';
import '../../visits/presentation/ziyaret_durumu.dart';

final bugunProvider = FutureProvider.autoDispose((ref) {
  final o = ref.watch(sessionProvider);
  if (o?.storeId == null) return Future.value(const BugunOzeti());
  return ref.watch(siparisRepositoryProvider)
      .bugun(o!.storeId!, periodId: o.periodId);
});

/// Pazarlamacının günü. Yalnızca KENDİ portföyü (K5).
///
/// Sıra bilinçlidir: önce NEREYE gidileceği (rota), sonra orada NE yapılacağı
/// (gecikmiş talepler, tahsilat hatırlatmaları). Sabah açılan ekranda ilk
/// görülmesi gereken şey listeler değil güzergâhtır.
class BugunEkrani extends ConsumerWidget {
  const BugunEkrani({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = ref.watch(bugunProvider);
    final oturum = ref.watch(sessionProvider);

    return CamSayfa(
      baslik: 'Bugün',
      eylemler: [
        IconButton(
          tooltip: 'Yenile',
          onPressed: () => ref.invalidate(bugunProvider),
          icon: const Icon(Icons.refresh, size: 20),
        ),
        const BildirimZili(),
        const SizedBox(width: T.s2),
      ],
      onYenile: () async => ref.invalidate(bugunProvider),
      cocuklar: b.when(
        loading: () => const [
          CamKart(dolgu: false, child: IskeletListe(satir: 4)),
        ],
        error: (e, _) => [Bildirim(e.toString(), tip: BildirimTip.hata)],
        data: (d) => [
              const _KuyrukUyarisi(),
              // Portföyü boş bir pazarlamacı için bütün ekran sıfır gösterir
              // ve sıfırlar hiçbir soruyu cevaplamaz. Rehber önce gelir.
              if (d.portfoyCari == 0) ...[
                const _Baslangic(),
                const SizedBox(height: T.s4),
              ],
              _Ozet(d: d, ad: oturum?.data.adSoyad),
              const SizedBox(height: T.s3),
              const _Rota(),
              const SizedBox(height: T.s3),
              const _Denemeler(),
              if (d.gecikmisTalepler.isNotEmpty) ...[
                const SizedBox(height: T.s3),
                _Gecikmisler(d: d),
              ],
              if (d.hatirlatmalar.isNotEmpty) ...[
                const SizedBox(height: T.s3),
                _Hatirlatmalar(d: d),
              ],
              if (!d.isVar) ...[
                const SizedBox(height: T.s3),
                const BosDurum('Bekleyen işin yok — portföyün temiz',
                    ikon: Icons.check_circle_outline),
              ],
          const SonBosluk(),
        ],
      ),
    );
  }
}

/// Portföyü henüz atanmamış pazarlamacı.
///
/// Burada YAPILACAK BİR ŞEY YOK ve bunu söylemek gerekiyor: portföyü
/// pazarlamacı kendisi atayamıyor, sahibi atıyor. Sahte bir "başla" düğmesi
/// koymak, tıklayıp hiçbir şey olmadığını görmekten beter.
class _Baslangic extends ConsumerWidget {
  const _Baslangic();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Baslangic(
        baslik: 'Portföyün henüz boş',
        aciklama: 'Bu ekran senin günün: hangi kuruma uğrayacağın, kimden '
            'ne alacağın, hangi talebin beklediği. Dolması için dükkan '
            'sahibinin sana cari ataması gerekiyor — atandığı anda burada '
            'görünür.',
        adimlar: [
          BaslangicAdimi('Kurumlara göz at — sahayı tanı',
              onTap: () => context.go('/kurumlar')),
          BaslangicAdimi('Deneme takvimine bak — hangi deneme ne zaman',
              onTap: () => context.go('/deneme-takvimi')),
        ],
      );
}

/// Pazarlamacının açılış özeti.
///
/// Panel'le aynı ilke: **tek baskın sayı**, sonra sıradaki işler. Eskiden iki
/// eşit kutu ve dört ListTile vardı; hepsi aynı ağırlıktaydı ve göz nereye
/// bakacağını bilmiyordu.
class _Ozet extends StatelessWidget {
  const _Ozet({required this.d, this.ad});
  final BugunOzeti d;
  final String? ad;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final isler = <({String anahtar, String baslik, String? alt, int sayi,
                    Color renk, String yol})>[
      if (d.hazirSiparis > 0)
        (anahtar: 'hazir', baslik: 'Hazır sipariş',
         alt: 'teslim edilmeyi bekliyor', sayi: d.hazirSiparis,
         renk: s.basarili, yol: '/siparisler'),
      if (d.borcluCari > 0)
        (anahtar: 'borclu', baslik: 'Borçlu cari',
         alt: '${Fmt.para(d.acikAlacak)} açık alacak', sayi: d.borcluCari,
         renk: s.error, yol: '/tahsilat'),
      if (d.bekleyenTalep > 0)
        (anahtar: 'talep', baslik: 'Açık talep', alt: null,
         sayi: d.bekleyenTalep, renk: s.bilgi, yol: '/talepler'),
      // K45 · açık konsinye türetilir; kapatılması hatırlatılır
      if (d.acikKonsinyeCari > 0)
        (anahtar: 'konsinye', baslik: 'Açık konsinye',
         alt: 'satıldı/iade kaydı girilmeli', sayi: d.acikKonsinyeCari,
         renk: s.uyari, yol: '/konsinye'),
    ];

    return Column(
      key: K.bugunOzet,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(T.s4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SayiBloku(
                  etiket: ad == null
                      ? 'AÇIK ALACAĞIM'
                      : '${ad!.split(' ').first.toUpperCase()} · AÇIK ALACAK',
                  deger: Fmt.para(d.acikAlacak),
                  altBilgi: '${Fmt.adet(d.portfoyCari)} cari portföyümde'
                      '${d.borcluCari > 0 ? ' · ${Fmt.adet(d.borcluCari)} '
                          'tanesi borçlu' : ''}',
                  altBilgiRengi: d.borcluCari > 0 ? s.error : null,
                ),
                const SizedBox(height: T.s4),
                Divider(height: 1, color: s.outlineVariant),
                const SizedBox(height: T.s3),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: SayiCifti(
                      etiket: 'Dönem ciron', deger: Fmt.para(d.donemCiro),
                      altBilgi: d.donemAd)),
                  Expanded(child: SayiCifti(
                      etiket: 'Tahsilatın', deger: Fmt.para(d.donemTahsilat),
                      renk: s.basarili,
                      altBilgi: d.donemCiro > 0
                          ? '%${(d.donemTahsilat / d.donemCiro * 100).round()}'
                              ' tahsil oranı'
                          : null)),
                ]),
              ],
            ),
          ),
        ),
        if (isler.isNotEmpty) ...[
          const SizedBox(height: T.s4),
          const BolumBasligi('SIRADAKİ İŞLER'),
          IsGrubu(satirlar: [
            for (final x in isler)
              IsSatiri(
                key: K.panelKart(x.anahtar),
                baslik: x.baslik,
                altBilgi: x.alt,
                sayi: x.sayi,
                renk: x.renk,
                onTap: () => context.go(x.yol),
              ),
          ]),
        ],
      ],
    );
  }
}

/// V7 · 24 saati geçen talepler. Bunlar sahibe eskale olur; pazarlamacı
/// önce buradan görsün.
class _Gecikmisler extends ConsumerWidget {
  const _Gecikmisler({required this.d});
  final BugunOzeti d;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = Theme.of(context).colorScheme;
    return Bolum(
      key: K.bugunGecikmis,
      baslik: 'Gecikmiş talepler',
      altBaslik: '24 saati geçenler sahibe bildirilir',
      eylem: Rozet('${d.gecikmisTalepler.length}', renk: s.error),
      child: Column(children: [
        for (final g in d.gecikmisTalepler)
          KayitSatiri(
            baslik: g.unvan,
            altBilgi: '${Fmt.adet(g.kalem)} kalem · ${Fmt.tarih(g.createdAt)}',
            // Bekleme süresi kararı verdiren sayı: sağ sütunda, hizalı.
            deger: g.gun > 0
                ? '${g.gun} gün'
                : '${g.saat.toStringAsFixed(0)} saat',
            degerRengi: g.gun >= 3 ? s.error : s.uyari,
            durumRengi: g.gun >= 3 ? s.error : s.uyari,
            ikon: Icons.schedule_outlined,
            onTap: () async {
              await Navigator.of(context).push<bool>(MaterialPageRoute(
                  builder: (_) => TalepDetayEkrani(talepId: g.id)));
              ref.invalidate(bugunProvider);
            },
          ),
      ]),
    );
  }
}

class _Hatirlatmalar extends StatelessWidget {
  const _Hatirlatmalar({required this.d});
  final BugunOzeti d;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Bolum(
      key: K.bugunTahsilat,
      baslik: 'Tahsilat hatırlatmaları',
      altBaslik: 'Portföyündeki açık bakiyeler — en büyükten',
      child: Column(children: [
        for (final h in d.hatirlatmalar)
          KayitSatiri(
            baslik: h.unvan,
            altBilgi: h.gun == null ? null : '${h.gun} gündür açık',
            deger: Fmt.para(h.bakiye),
            degerRengi: s.error,
            // Şerit yalnızca GECİKMİŞ olanda: hepsi kırmızıysa hiçbiri
            // dikkat çekmiyor.
            durumRengi: (h.gun ?? 0) >= 30 ? s.error : null,
            ikon: Icons.payments_outlined,
            onTap: () => context.go('/tahsilat'),
          ),
      ]),
    );
  }
}

/// Günün rotası — özet. Tam liste ve öneriler /rota ekranında.
///
/// Burada yalnızca "kaç durak, hangileri, biri açık mı" gösterilir; rotayı
/// düzenleme ve öneri seçme işi ayrı ekranda kalır ki sabah bakışı kısa olsun.
class _Rota extends ConsumerWidget {
  const _Rota();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(rotaProvider(null)).value;
    final acik = ref.watch(acikZiyaretProvider).value;
    final s = Theme.of(context).colorScheme;
    if (r == null) return const SizedBox.shrink();

    void rotayaGit() => Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => const RotaEkrani()));

    return Bolum(
      key: K.bugunRota,
      baslik: 'Rotan',
      altBaslik: r.bos
          ? 'Bugün için durak yok'
          : '${r.tamamlanan}/${r.planlanan} tamamlandı',
      eylem: TextButton(
          onPressed: rotayaGit,
          child: Text(r.bos ? 'Rota kur' : 'Tümü')),
      child: r.bos
          ? const BosDurum('Uğranması gerekenleri rota ekranı öneriyor',
              ikon: Icons.route_outlined)
          : Column(children: [
              for (final d in r.duraklar.take(5))
                KayitSatiri(
                  baslik: d.kurumAd,
                  altBilgi: [
                    if (d.ilce != null) d.ilce!,
                    if (d.bekleyenTalep > 0) '${d.bekleyenTalep} talep',
                  ].join(' · '),
                  // Şu an içinde olunan kurum en güçlü işaret: yeşil şerit
                  // ve yazısı. Tamamlanan durak soluk kalır.
                  vurgu: d.kurumId == acik?.kurumId ? 'Şu an buradasın' : null,
                  vurguRengi: s.basarili,
                  deger: d.borc > 0 ? Fmt.para(d.borc) : null,
                  degerRengi: s.error,
                  ikon: d.tamam ? Icons.check_circle_outline
                                : Icons.place_outlined,
                  durumRengi: d.kurumId == acik?.kurumId
                      ? s.basarili
                      : (d.tamam ? null : s.bilgi),
                  onTap: rotayaGit,
                ),
              if (r.duraklar.length > 5)
                TextButton(
                    onPressed: rotayaGit,
                    child: Text('+${r.duraklar.length - 5} durak daha')),
            ]),
    );
  }
}

/// K43 · "Başarısız kayıt sessizce kaybolmaz." Sessizce kaybolmamanın tek
/// yolu kullanıcının onu her gün açtığı ekranda görmesi.
class _KuyrukUyarisi extends ConsumerStatefulWidget {
  const _KuyrukUyarisi();
  @override
  ConsumerState<_KuyrukUyarisi> createState() => _KuyrukUyarisiState();
}

class _KuyrukUyarisiState extends ConsumerState<_KuyrukUyarisi> {
  @override
  void initState() {
    super.initState();
    // Kuyruk yalnızca kullanıcı düğmeye bastığında boşalıyorsa boşalmaz.
    // Bugün ekranı her sabah açılıyor; bekleyen kayıt varsa sessizce denenir.
    // Katalog indirilmez — amaç kuyruğu yollamak, 24.623 ürünü tazelemek değil.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final n = await ref.read(bekleyenSayisiProvider.future);
      if (n > 0 && mounted) {
        await ref.read(senkronProvider.notifier).calistir(katalog: false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final n = ref.watch(bekleyenSayisiProvider).value ?? 0;
    if (n == 0) return const SizedBox.shrink();
    return Padding(
      key: K.bugunKuyrukUyarisi,
      padding: const EdgeInsets.only(bottom: T.s3),
      child: Dokunus(
        tur: DokunusTuru.nesne,
        onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute(builder: (_) => const SenkronEkrani())),
        child: Bildirim(
            '$n kayıt sunucuya yüklenmedi — bağlantı gelince eşitleyin.',
            tip: BildirimTip.uyari),
      ),
    );
  }
}

/// K20 · "Önümüzdeki 7 gün" şeridi.
///
/// Sabit tarihli Türkiye Geneli denemeleri ÖNDE durur: kaçırılırsa telafisi
/// yok. Takvim türü denemeler bir "stokta olacak" bildirimidir — uygulama
/// gününü kurum seçer, o yüzden aynı aciliyette değildir.
class _Denemeler extends ConsumerWidget {
  const _Denemeler();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = ref.watch(yaklasanDenemelerProvider).value ?? const [];
    if (l.isEmpty) return const SizedBox.shrink();
    final s = Theme.of(context).colorScheme;

    return Bolum(
      key: K.bugunDeneme,
      baslik: 'Yaklaşan denemeler',
      altBaslik: 'Önümüzdeki 7 günde stoka girenler',
      eylem: TextButton(
        onPressed: () => Navigator.of(context).push<void>(
            MaterialPageRoute(builder: (_) => const DenemeTakvimiEkrani())),
        child: const Text('Takvim'),
      ),
      child: Column(children: [
        for (final d in l.take(5))
          KayitSatiri(
            baslik: d.ad,
            altBilgi: [
              if (d.yayinevi != null) d.yayinevi!,
              if (d.duzey != null) d.duzey!,
            ].join(' · '),
            // K20 · Sabit tarihli deneme kaçırılırsa telafisi yok; takvim
            // türü yalnızca "stokta olacak" bildirimidir.
            vurgu: d.sabit ? 'Sabit tarih — kaçırılamaz' : null,
            vurguRengi: s.error,
            deger: switch (d.gun) {
              0 => 'bugün',
              1 => 'yarın',
              _ => '${d.gun} gün',
            },
            degerRengi: d.sabit ? s.error : null,
            ikon: d.sabit ? Icons.change_history : Icons.calendar_today_outlined,
            durumRengi: d.sabit ? s.error : null,
            onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => const DenemeTakvimiEkrani())),
          ),
      ]),
    );
  }
}
