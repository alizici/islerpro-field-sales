import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session.dart';
import '../../../core/test_keys.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/repositories/siparis_repository.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/widgets/baslangic.dart';
import '../../../shared/widgets/cam.dart';
import '../../../shared/widgets/liste.dart';
import '../../../shared/widgets/bolum.dart';
import '../../../shared/widgets/form_kabuk.dart';
import '../../../shared/widgets/mono.dart';
import '../../../shared/widgets/parcalar.dart';
import '../../../shared/widgets/satir.dart';
import '../../notifications/presentation/bildirimler.dart';

final panelProvider = FutureProvider.autoDispose((ref) {
  final o = ref.watch(sessionProvider);
  if (o?.storeId == null) return Future.value(const PanelOzeti());
  return ref.watch(siparisRepositoryProvider)
      .panel(o!.storeId!, periodId: o.periodId);
});

/// Sahibin açılış ekranı: "bugün neye bakmalıyım".
/// Tek çağrıda gelir — sunucu ~340 ms uzakta, açılışta sekiz istek atılmaz.
///
/// Ekran cam dilinde: içerik başlığın ve alt çubuğun ALTINDAN akıyor, kartlar
/// [CamZemin]'in üstünde yüzüyor. Sıra değişmedi — önce bekleyen iş, sonra
/// para: sahip sabah önce "bugün ne yapmam gerek" diye soruyor.
class PanelEkrani extends ConsumerWidget {
  const PanelEkrani({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(panelProvider);

    return CamSayfa(
      baslik: 'Panel',
      onYenile: () async => ref.invalidate(panelProvider),
      eylemler: [
        IconButton(
          tooltip: 'Yenile',
          onPressed: () => ref.invalidate(panelProvider),
          icon: const Icon(Icons.refresh, size: 20),
        ),
        const BildirimZili(),
        const SizedBox(width: T.s2),
      ],
      cocuklar: p.when(
        // `sayfa: false`: iskelet burada ekranın tamamı değil, listenin bir
        // çocuğu. Kaydırılabilir bir sarmalayıcı, kaydırılabilir bir ebeveynin
        // içinde sınırsız yükseklik istiyor ve patlıyor.
        loading: () => const [CamKart(dolgu: false, child: IskeletListe(satir: 4))],
        error: (e, _) => [Bildirim(e.toString(), tip: BildirimTip.hata)],
        data: (d) => [
          // Dükkan yepyeniyse rehber ÖNCE gelir: arkasındaki bütün kartlar
          // sıfır gösteriyor ve sıfırlar hiçbir soruyu cevaplamıyor.
          if (_bos(d)) ...[
            _Baslangic(d: d),
            const SizedBox(height: T.s4),
          ],
          _Kuyruk(d: d),
          const SizedBox(height: T.s4),
          _Para(d: d),
          const SizedBox(height: T.s4),
          _HuniBolumu(h: d.huni),
          if (d.pazarlamacilar.isNotEmpty) ...[
            const SizedBox(height: T.s4),
            _Ekip(d: d),
          ],
          const SonBosluk(),
        ],
      ),
    );
  }
}

/// Dükkanda hiç hareket olmuş mu. Tek tek sayı saymak yerine "bir şey
/// olmuş mu" diye soruyoruz: ekip yok, talep açılmamış, para dönmemiş.
bool _bos(PanelOzeti d) =>
    d.pazarlamacilar.isEmpty &&
    d.huni.acilan == 0 &&
    d.acikAlacak == 0 &&
    d.donemCiro == 0 &&
    d.bekleyenTalep == 0;

/// Yeni dükkanın ilk günü.
///
/// Sıra rastgele değil, ZORUNLULUK sırası: kurum olmadan cari açılamaz,
/// fiyat olmadan sipariş verilemez, ekip olmadan saha çalışmaz.
class _Baslangic extends StatelessWidget {
  const _Baslangic({required this.d});
  final PanelOzeti d;

  @override
  Widget build(BuildContext context) => Baslangic(
        baslik: 'Dükkanı kurmaya başla',
        aciklama: 'İşlerPro sahadaki satışı takip eder: kurumlara açılan '
            'cariler, onlardan gelen talepler, teslimat ve tahsilat. '
            'Sıra şöyle:',
        adimlar: [
          BaslangicAdimi('Kurumları ekle — okullar ve kurs merkezleri',
              onTap: () => context.go('/kurumlar')),
          BaslangicAdimi('Cari aç — alışverişin muhatabı',
              onTap: () => context.go('/cariler')),
          BaslangicAdimi('Katalogu doldur, fiyatları gir',
              onTap: () => context.go('/katalog')),
          BaslangicAdimi('Ekibini davet et',
              tamam: d.pazarlamacilar.isNotEmpty,
              onTap: () => context.go('/ayarlar')),
        ],
      );
}

/// Bekleyen işler.
///
/// Eskiden BEŞ satır vardı ve **sıfır olanlar da** tam boy yer kaplıyordu:
/// ekranın yarısı beş tane "0" gösteriyordu. Sıfır bir bilgidir ama beş satır
/// hak etmiyor — artık tek cümlede toplanıyor, yer kalanlara kalıyor.
class _Kuyruk extends StatelessWidget {
  const _Kuyruk({required this.d});
  final PanelOzeti d;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final isler = <({String anahtar, String baslik, String? alt, int sayi,
                    Color renk, String yol})>[
      (anahtar: 'gecikmis', baslik: 'Gecikmiş talep',
       alt: '24 saattir dokunulmadı', sayi: d.gecikmisTalep,
       renk: s.error, yol: '/talepler'),
      (anahtar: 'onay', baslik: 'Onay bekleyen sipariş',
       alt: 'iskonto tavanı veya kredi limiti aşıldı',
       sayi: d.onayBekleyenSiparis, renk: s.uyari, yol: '/siparisler'),
      (anahtar: 'hazirlik', baslik: 'Hazırlanacak sipariş', alt: null,
       sayi: d.hazirlanacakSiparis, renk: s.bilgi, yol: '/hazirlik'),
      (anahtar: 'bekleyen', baslik: 'Açık talep', alt: null,
       sayi: d.bekleyenTalep, renk: s.bilgi, yol: '/talepler'),
      // W-2 · portföysüz cariden gelen talep hiçbir kutuya düşmez
      (anahtar: 'portfoysuz', baslik: 'Portföysüz cari',
       alt: 'talepleri kimsenin kutusuna düşmez', sayi: d.portfoysuzCari,
       renk: s.uyari, yol: '/cariler'),
    ];
    final dolu = isler.where((x) => x.sayi > 0).toList();
    final bos = isler.where((x) => x.sayi == 0).toList();

    return Column(
      key: K.panelKuyruk,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BolumBasligi('BEKLEYEN İŞLER',
            sag: d.acilVar ? 'Acil bakılması gerekenler var' : null,
            sagRengi: s.error),
        IsGrubu(satirlar: [
          for (final x in dolu)
            IsSatiri(
              key: K.panelKart(x.anahtar),
              baslik: x.baslik,
              altBilgi: x.alt,
              sayi: x.sayi,
              renk: x.renk,
              onTap: () => context.go(x.yol),
            ),
        ]),
        if (bos.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: dolu.isEmpty ? 0 : T.s1),
            child: SifirOzeti(dolu.isEmpty
                ? 'Her şey akışında — bekleyen iş yok'
                : '${_liste(bos.map((x) => x.baslik.toLowerCase()))} yok'),
          ),
      ],
    );
  }

  /// "a, b ve c" — üç maddeyi virgülle dizmek Türkçede kulağa yanlış geliyor.
  static String _liste(Iterable<String> x) {
    final l = x.toList();
    if (l.length == 1) return l.first;
    return '${l.take(l.length - 1).join(', ')} ve ${l.last}';
  }
}

/// Para — ekranın TEK baskın kartı.
///
/// Eskiden ciro, tahsilat ve alacak aynı puntoda yan yana duruyordu ve göz
/// hangisinin önemli olduğunu seçemiyordu. Ekranın tek baskın sayısı açık
/// alacak: sahibin sabah sorduğu soru o.
///
/// Kart KOYU BORDO ([CamTon.marka]) — ekrandaki tek koyu yüzey. Baskınlık
/// yalnızca puntoyla kurulmuyor: göz, açık kartlardan oluşan bir sayfada koyu
/// olana önce gidiyor. Bu yüzden ekranda ikinci bir marka kartı olamaz;
/// olursa ikisi de baskın olmaz.
class _Para extends StatelessWidget {
  const _Para({required this.d});
  final PanelOzeti d;

  @override
  Widget build(BuildContext context) {
    return CamKart(
      ton: CamTon.marka,
      // Renkler kartın İÇİNDEN okunmalı: `CamTon.marka` çocuklarına koyu
      // şemayı veriyor ve dışarıdan okunan `s.error` (#B0332B) bordo zeminde
      // görünmüyor. `Builder` o eşiği geçiriyor.
      child: Builder(builder: (context) {
        final s = Theme.of(context).colorScheme;
        return Column(
          key: K.panelPara,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SayiBloku(
              etiket: 'AÇIK ALACAK',
              deger: Fmt.para(d.acikAlacak),
              boy: 36,
              // K7 · bu DÜKKANIN alacağıdır, bir kurumun borcu değil
              altBilgi: d.gecikmisBorc > 0
                  ? '${Fmt.adet(d.borcluCari)} cari · '
                      '${Fmt.para(d.gecikmisBorc)} gecikmiş'
                  : '${Fmt.adet(d.borcluCari)} cari · dükkanın toplam alacağı',
              altBilgiRengi: d.gecikmisBorc > 0 ? s.error : null,
            ),
            // Alacağın NE KADARI gecikmiş — tek şeritte. Dört satır sayı
            // yazmak yerine bir çizgi; oran göz kararı okunuyor.
            if (d.acikAlacak > 0) ...[
              const SizedBox(height: T.s4),
              OranSeridi([
                ('güncel', d.acikAlacak - d.gecikmisBorc, s.basarili),
                ('gecikmiş', d.gecikmisBorc, s.error),
              ]),
            ],
            const SizedBox(height: T.s4),
            Divider(height: 1, color: s.outlineVariant),
            const SizedBox(height: T.s3),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: SayiCifti(
                  etiket: 'Dönem cirosu',
                  deger: Fmt.para(d.donemCiro),
                  // K26 · borç teslimatla doğar; ciro da teslimattan okunur
                  altBilgi: 'teslimattan okunur, siparişten değil',
                ),
              ),
              Expanded(
                child: SayiCifti(
                  etiket: 'Tahsilat',
                  deger: Fmt.para(d.donemTahsilat),
                  renk: s.basarili,
                  altBilgi: d.donemCiro > 0
                      ? '%${(d.donemTahsilat / d.donemCiro * 100).round()}'
                          ' tahsil oranı'
                      : '—',
                ),
              ),
            ]),
            // K11 · çek ödeme değil ödeme vaadidir
            if (d.portfoydekiCek > 0) ...[
              const SizedBox(height: T.s3),
              KuralNotu(
                'Portföyde ${Fmt.para(d.portfoydekiCek)} çek var — ödeme değil '
                'ödeme vaadi; tahsil edilince bakiyeden düşer.',
                ikon: Icons.account_balance_wallet_outlined,
                renk: s.uyari,
              ),
            ],
          ],
        );
      }),
    );
  }
}

/// K37 · Talep hunisi. Kalem bazlı karar sayesinde "kısmen onaylandı" da
/// siparişe döner; huni bunu gösterir.
class _HuniBolumu extends StatelessWidget {
  const _HuniBolumu({required this.h});
  final Huni h;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    if (h.acilan == 0) {
      return CamBolum(
        key: K.panelHuni,
        baslik: 'Talep hunisi',
        child: const BosDurum('Bu dönemde henüz talep yok',
            ikon: Icons.filter_alt_outlined),
      );
    }
    return CamBolum(
      key: K.panelHuni,
      baslik: 'Talep hunisi',
      altBaslik: 'Dönüşüm %${(h.donusum * 100).toStringAsFixed(0)}',
      child: Padding(
        padding: const EdgeInsets.only(bottom: T.s2),
        child: Column(children: [
          _Basamak('Açılan talep', h.acilan, h.acilan, s.onSurfaceVariant),
          _Basamak('Karara bağlanan', h.kararaBaglanan, h.acilan, s.bilgi),
          _Basamak('Siparişe dönen', h.siparise, h.acilan, s.basarili),
          if (h.reddedilen > 0)
            _Basamak('Tamamen reddedilen', h.reddedilen, h.acilan, s.error),
        ]),
      ),
    );
  }
}

class _Basamak extends StatelessWidget {
  const _Basamak(this.etiket, this.deger, this.toplam, this.renk);
  final String etiket;
  final int deger, toplam;
  final Color renk;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(T.s4, T.s2, T.s4, T.s2),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(etiket, style: Theme.of(context).textTheme.bodyMedium),
          const Spacer(),
          Mono(Fmt.adet(deger), size: 13, weight: FontWeight.w600),
        ]),
        const SizedBox(height: 6),
        // Material'ın `LinearProgressIndicator`ı artık ucunda bir nokta ve
        // dolu kısımla arasında bir boşluk çiziyor — M3'ün yeni imzası.
        // Burada olması gereken sade bir çubuk: iki katman, tam yuvarlak uç.
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            height: 6,
            child: Stack(children: [
              ColoredBox(
                color: s.onSurfaceVariant.withValues(alpha: 0.13),
                child: const SizedBox.expand(),
              ),
              FractionallySizedBox(
                widthFactor:
                    toplam == 0 ? 0 : (deger / toplam).clamp(0.0, 1.0),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: renk,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _Ekip extends StatelessWidget {
  const _Ekip({required this.d});
  final PanelOzeti d;

  @override
  Widget build(BuildContext context) => CamBolum(
        key: K.panelEkip,
        baslik: 'Ekip',
        altBaslik: 'Portföy büyüklüğü ve açık talepler',
        child: Column(children: [
          for (final p in d.pazarlamacilar)
            KayitSatiri(
              baslik: p.adSoyad,
              altBilgi: '${Fmt.adet(p.cariSayisi)} cari',
              ikon: Icons.person_outline,
              durumRengi: p.acikTalep == 0
                  ? Theme.of(context).colorScheme.basarili
                  : Theme.of(context).colorScheme.bilgi,
              deger: p.acikTalep == 0
                  ? null
                  : '${Fmt.adet(p.acikTalep)} açık talep',
            ),
        ]),
      );
}
