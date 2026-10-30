import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/test_keys.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/repositories/deneme_repository.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/widgets/form_kabuk.dart';
import '../../../shared/widgets/dokunus.dart';
import '../../../shared/widgets/cam.dart';
import '../../../shared/widgets/liste.dart';
import '../../../shared/widgets/mono.dart';
import '../../../shared/widgets/parcalar.dart';
import '../../../shared/widgets/satir.dart';
import 'deneme_durumu.dart';
import 'kurumlara_oner_ekrani.dart';

const _aylar = ['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
                'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];
const _gunler = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];

/// K20 · Deneme takvimi.
///
/// Eksen değiştirilebilir çünkü iki tarih iki ayrı soruya cevap veriyor:
/// **stok tarihi** "kitapçıklar ne zaman dükkanda olacak", **uygulama tarihi**
/// "sınav kurumda ne zaman yapılacak". Varsayılan stok tarihidir — 267/267
/// dolu olan tek eksen o; takvimi uygulamaya göre kurmak kalemlerin yarısını
/// görünmez yapardı.
class DenemeTakvimiEkrani extends ConsumerWidget {
  const DenemeTakvimiEkrani({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(takvimFiltreProvider);
    final t = ref.watch(denemeTakvimiProvider);
    final n = ref.read(takvimFiltreProvider.notifier);

    return CamSayfa(
      baslik: 'Deneme Takvimi',
      onYenile: () async => ref.invalidate(denemeTakvimiProvider),
      eylemler: [
        IconButton(
          tooltip: 'Yenile',
          onPressed: () => ref.invalidate(denemeTakvimiProvider),
          icon: const Icon(Icons.refresh, size: 20),
        ),
        const SizedBox(width: T.s2),
      ],
      cocuklar: t.when(
        loading: () => const [
          CamKart(dolgu: false, child: IskeletListe(satir: 6)),
        ],
        error: (e, _) => [Bildirim(e.toString(), tip: BildirimTip.hata)],
        data: (d) => [
          _Baslik(f: f, n: n, toplam: d.toplam),
          const SizedBox(height: T.s4),
          _Izgara(f: f, d: d),
          if (d.tarihsiz.isNotEmpty) ...[
            const SizedBox(height: T.s4),
            _Tarihsizler(d: d),
          ],
          const SonBosluk(),
        ],
      ),
    );
  }
}

class _Baslik extends StatelessWidget {
  const _Baslik({required this.f, required this.n, required this.toplam});
  final TakvimFiltre f;
  final FiltreN n;
  final int toplam;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Column(
      key: K.denemeBaslik,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Ay çubuğu: takvimin gezinme kolu. Kart başlığının içine gömülü
        // iki ok, ekranın en sık kullanılan denetimi olamayacak kadar
        // sessizdi.
        Container(
          color: s.surfaceContainerLowest,
          padding: const EdgeInsets.fromLTRB(T.s2, T.s2, T.s2, T.s2),
          child: Row(children: [
            IconButton(
              key: K.denemeOncekiAy,
              onPressed: () => n.ayDegistir(-1),
              icon: const Icon(Icons.chevron_left, size: 22),
            ),
            Expanded(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('${_aylar[f.ay.month - 1]} ${f.ay.year}',
                    style: Theme.of(context).textTheme.titleLarge),
                Text(
                    f.eksen == 'stok'
                        ? 'Stok tarihi — kitapçıklar dükkana geliyor'
                        : 'Uygulama tarihi — sınav kurumda yapılıyor',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
            IconButton(
              key: K.denemeSonrakiAy,
              onPressed: () => n.ayDegistir(1),
              icon: const Icon(Icons.chevron_right, size: 22),
            ),
          ]),
        ),
        // K20 · Eksen bir SÜZGEÇ değil, takvimin neye göre kurulduğu.
        // Bu yüzden diğer çiplerden ayrı bir satırda ve her zaman biri
        // seçili duruyor.
        Padding(
          padding: const EdgeInsets.only(bottom: T.s3),
          child: Row(children: [
            Expanded(
              child: SuzgecCipi(
                key: K.denemeEksenStok,
                etiket: 'Stok tarihi',
                secili: f.eksen == 'stok',
                onTap: () => n.eksen('stok'),
              ),
            ),
            const SizedBox(width: T.s2),
            Expanded(
              child: SuzgecCipi(
                key: K.denemeEksenUygulama,
                etiket: 'Uygulama tarihi',
                secili: f.eksen == 'uygulama',
                onTap: () => n.eksen('uygulama'),
              ),
            ),
          ]),
        ),
        SuzgecSeridi(cipler: [
          // En işe yarayan süzgeç ÖNDE: ayda 33 kalemi ~10'a indiriyor.
          // Şeridin sonundayken telefonda ekran dışında kalıyor ve hiç
          // kullanılmıyordu.
          SuzgecCipi(
            key: K.denemePortfoy,
            etiket: 'Sadece portföyüme uygun',
            renk: s.primary,
            secili: f.sadecePortfoy,
            onTap: () => n.portfoy(!f.sadecePortfoy),
          ),
          for (final k in const [('ortaokul', 'Ortaokul'), ('lise', 'Lise')])
            SuzgecCipi(
              key: K.denemeKademe(k.$1),
              etiket: k.$2,
              secili: f.kademe == k.$1,
              onTap: () => n.kademe(f.kademe == k.$1 ? null : k.$1),
            ),
          for (final tu in denemeTuruAdi.entries)
            SuzgecCipi(
              key: K.denemeTur(tu.key),
              etiket: tu.value,
              secili: f.turu == tu.key,
              onTap: () => n.turu(f.turu == tu.key ? null : tu.key),
            ),
        ]),
        // Gösterge KENDİ satırında: sayaç şeridinin sağına konunca dar
        // ekranda üç satıra sarıyor ve sayacı eziyordu.
        SayacSeridi('$toplam deneme'),
        Container(
          width: double.infinity,
          color: s.surfaceContainerLowest,
          padding: const EdgeInsets.fromLTRB(T.s4, 0, T.s4, T.s3),
          child: Row(children: [
            _Gosterge(Icons.change_history, 'Türkiye Geneli', s.error),
            const SizedBox(width: T.s3),
            _Gosterge(Icons.circle, 'Takvim', s.primary),
          ]),
        ),
      ],
    );
  }
}

/// Izgara göstergesi — hücredeki işaretin ne anlama geldiği.
class _Gosterge extends StatelessWidget {
  const _Gosterge(this.ikon, this.etiket, this.renk);
  final IconData ikon;
  final String etiket;
  final Color renk;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ikon, size: ikon == Icons.circle ? 8 : 12, color: renk),
          const SizedBox(width: 5),
          Text(etiket, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}

/// Ay ızgarası. Gün hücresi rozet taşır: **▲ Türkiye Geneli her zaman öne**,
/// çünkü sabit tarihli sınav kaçırılamaz (K20).
class _Izgara extends ConsumerWidget {
  const _Izgara({required this.f, required this.d});
  final TakvimFiltre f;
  final DenemeTakvimi d;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = Theme.of(context).colorScheme;
    final ilk = DateTime(f.ay.year, f.ay.month);
    final gunSayisi = DateTime(f.ay.year, f.ay.month + 1, 0).day;
    final basBosluk = ilk.weekday - 1;   // Pazartesi = 0
    final hucreler = basBosluk + gunSayisi;
    final bugun = DateTime.now();

    return CamKart(
      key: K.denemeIzgara,
      dolgu: false,
      child: Padding(
        padding: const EdgeInsets.all(T.s3),
        child: Column(children: [
          Row(children: [
            for (final g in _gunler)
              Expanded(child: Center(child: MikroEtiket(g))),
          ]),
          const SizedBox(height: T.s2),
          for (var h = 0; h < hucreler; h += 7)
            Row(children: [
              for (var i = h; i < h + 7; i++)
                Expanded(
                  // Ayın ilk günü haftanın ortasına düşebilir ve son hafta
                  // eksik biter; iki uçtaki boş hücreler yer tutar.
                  child: i < basBosluk || i - basBosluk + 1 > gunSayisi
                      ? const SizedBox(height: 52)
                      : _Hucre(
                          gun: i - basBosluk + 1,
                          veri: d.gun(DateTime(
                              f.ay.year, f.ay.month, i - basBosluk + 1)),
                          bugun: bugun.year == f.ay.year &&
                              bugun.month == f.ay.month &&
                              bugun.day == i - basBosluk + 1,
                        ),
                ),
            ]),
          if (d.gunler.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: T.s3),
              child: Text('Bu ayda deneme yok',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: s.onSurfaceVariant)),
            ),
        ]),
      ),
    );
  }
}

class _Hucre extends ConsumerWidget {
  const _Hucre({required this.gun, required this.veri, required this.bugun});
  final int gun;
  final DenemeGunu? veri;
  final bool bugun;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = Theme.of(context).colorScheme;
    final v = veri;
    return Dokunus(
      tur: DokunusTuru.nesne,
      key: K.denemeGun(gun),
      onTap: v == null ? null : () => _gunPaneli(context, ref, v),
      child: Container(
        height: 52,
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: bugun ? s.primary.withValues(alpha: 0.08) : null,
          border: Border.all(
              color: bugun ? s.primary : s.outlineVariant,
              width: bugun ? 1.5 : 1),
          borderRadius: BorderRadius.circular(T.rKucuk),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('$gun', style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: bugun ? FontWeight.w700 : FontWeight.w500)),
          if (v != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                if (v.turkiyeGeneli > 0)
                  Icon(Icons.change_history, size: 11, color: s.error),
                if (v.adet - v.turkiyeGeneli > 0)
                  Icon(Icons.circle, size: 7, color: s.primary),
                if (v.adet > 2)
                  Text(' ${v.adet}',
                      style: Theme.of(context).textTheme.labelSmall),
              ]),
            ),
        ]),
      ),
    );
  }
}

void _gunPaneli(BuildContext context, WidgetRef ref, DenemeGunu g) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => SafeArea(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
        child: _GunPaneli(g: g),
      ),
    ),
  );
}

class _GunPaneli extends ConsumerWidget {
  const _GunPaneli({required this.g});
  final DenemeGunu g;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
        key: K.denemeGunPaneli,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(T.s4, 0, T.s4, T.s2),
            child: Text(Fmt.tarih(g.tarih),
                style: Theme.of(context).textTheme.titleMedium),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final d in g.denemeler) _DenemeSatiri(d: d),
                const SizedBox(height: T.s4),
              ],
            ),
          ),
        ],
      );
}

class _DenemeSatiri extends ConsumerWidget {
  const _DenemeSatiri({required this.d});
  final Deneme d;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = Theme.of(context).colorScheme;
    // İki farklı sebeple dikkat isteyen iki hâl var ve ikisi de aynı
    // satırda çıkabiliyor: sabit tarih (kaçırılamaz) ve fiyatsızlık
    // (talep açılamaz). Fiyatsızlık daha ENGELLEYİCİ olduğu için öne geçer.
    final (String? vurgu, Color? vurguRenk) = switch (d) {
      // K12 · fiyatsız üründen açılan talep siparişe dönemez; sebebi
      // burada yazıyor ki kullanıcı düğmeye basıp öğrenmesin.
      _ when !d.fiyatli => ('Bu dükkanda fiyatı yok — talep açılamaz', s.uyari),
      // K20 · Türkiye Geneli tarihi ulusaldır, kurum oynatamaz.
      _ when d.sabit => ('Sabit tarih — kaçırılamaz', s.error),
      _ => (null, null),
    };

    return KayitSatiri(
      key: K.denemeSatir(d.id),
      baslik: d.ad,
      altBilgi: [
        denemeTuruAdi[d.turu] ?? d.turu,
        ?d.yayinevi,
        ?d.duzey,
        'stok ${Fmt.tarih(d.stokTarihi)}',
        if (d.uygulamaMetniGoster.isNotEmpty)
          'uygulama ${d.uygulamaMetniGoster}',
      ].join(' · '),
      vurgu: vurgu,
      vurguRengi: vurguRenk,
      ikon: d.sabit ? Icons.change_history : Icons.circle_outlined,
      durumRengi: d.sabit ? s.error : s.primary,
      sondaki: Padding(
        padding: const EdgeInsets.only(left: T.s2),
        child: TextButton(
          key: K.denemeOner(d.id),
          onPressed: !d.fiyatli
              ? null
              : () {
                  Navigator.pop(context);
                  Navigator.of(context).push<void>(MaterialPageRoute(
                      builder: (_) => KurumlaraOnerEkrani(deneme: d)));
                },
          child: const Text('Öner'),
        ),
      ),
    );
  }
}

/// Uygulama ekseninde tarihi olmayanlar. Bunlar eksik kayıt DEĞİLDİR:
/// Takvim türü denemelerde uygulama gününü kurum seçer (BULGU B).
class _Tarihsizler extends StatelessWidget {
  const _Tarihsizler({required this.d});
  final DenemeTakvimi d;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Column(
      key: K.denemeTarihsiz,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // BULGU B · bunlar eksik kayıt DEĞİL: Takvim türü denemelerde
        // uygulama gününü kurum seçer.
        SayacSeridi('Uygulama tarihi belirlenmemiş · ${d.tarihsiz.length}',
            sag: 'Bu denemelerde uygulama gününü kurum seçer'),
        Divider(height: 1, color: s.outlineVariant),
        for (final x in d.tarihsiz)
          KayitSatiri(
            baslik: x.ad,
            altBilgi: [
              ?x.yayinevi,
              'stok ${Fmt.tarih(x.stokTarihi)}',
            ].join(' · '),
            ikon: Icons.event_busy_outlined,
            durumRengi: s.onSurfaceVariant,
          ),
      ],
    );
  }
}
