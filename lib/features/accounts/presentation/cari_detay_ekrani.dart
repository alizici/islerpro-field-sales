import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session.dart';
import '../../../core/test_keys.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/repositories/cari_repository.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/widgets/bolum.dart';
import '../../../shared/widgets/cam.dart';
import '../../../shared/widgets/detay.dart';
import '../../../shared/widgets/form_kabuk.dart';
import '../../../shared/widgets/liste.dart';
import '../../../shared/widgets/parcalar.dart';
import '../../../shared/widgets/satir.dart';
import '../../commercial/presentation/iade_diyalogu.dart';
import '../../exams/presentation/mevcut_diyalogu.dart';
import 'cari_tasima_diyalogu.dart';
import 'ekstre_ekrani.dart';

final cariDetayProvider =
    FutureProvider.autoDispose.family<CariDetay, String>(
        (ref, id) => ref.watch(cariRepositoryProvider).detay(id));

class CariDetayEkrani extends ConsumerWidget {
  const CariDetayEkrani({required this.cariId, super.key});
  final String cariId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detay = ref.watch(cariDetayProvider(cariId));
    final oturum = ref.watch(sessionProvider);
    final yetkili = oturum?.aktifRol == AppRole.isletmeSahibi ||
        oturum?.aktifRol == AppRole.dukkanMuduru;

    return CamSayfa(
      baslik: detay.value?.unvan ?? 'Cari',
      cocuklar: detay.when(
        loading: () => const [
          _BantIskeleti(),
          SizedBox(height: T.s4),
          CamKart(dolgu: false, child: IskeletListe(satir: 4, ikon: false)),
        ],
        error: (e, _) => [Bildirim(e.toString(), tip: BildirimTip.hata)],
        data: (d) => [
            _Bant(d: d),
            EylemCipleri([
              Eylem(Icons.receipt_outlined, 'Ekstre',
                  dugmeKey: K.ekstreAc,
                  () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) =>
                          EkstreEkrani(cariId: cariId, unvan: d.unvan)))),
              Eylem(Icons.groups_outlined, 'Mevcutlar',
                  dugmeKey: K.cariMevcut,
                  () => mevcutAkisi(context, ref, cariId, d.unvan)),
              Eylem(Icons.undo, 'İade', dugmeKey: K.cariIade, () async {
                final ok = await iadeAkisi(context, ref, cariId, d.unvan);
                if (ok) ref.invalidate(cariDetayProvider(cariId));
              }),
              if (yetkili)
                Eylem(Icons.swap_horiz, 'Kurum değiştir',
                    dugmeKey: K.cariTasi, () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => CariTasimaDiyalogu(cari: d),
                  );
                  if (ok == true) ref.invalidate(cariDetayProvider(cariId));
                }),
            ]),
            _Risk(d: d),
            _Portfoy(d: d),
            if (d.kardesCariler.isNotEmpty) _Kardesler(d: d),
            if (d.tasimalar.isNotEmpty) _Tasimalar(d: d),
            const SonBosluk(),
        ],
      ),
    );
  }
}

class _BantIskeleti extends StatelessWidget {
  const _BantIskeleti();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(T.s4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Iskelet(200, 16),
          SizedBox(height: T.s2),
          Iskelet(140, 11),
          SizedBox(height: T.s5),
          Iskelet(160, 28),
        ]),
      );
}

class _Bant extends StatelessWidget {
  const _Bant({required this.d});
  final CariDetay d;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final durumAdi = switch (d.durum) {
      'aktif' => 'Aktif',
      'tahsilatta' => 'Tahsilatta',
      'pasif' => 'Pasif',
      _ => 'Kapalı',
    };
    final durumRenk = switch (d.durum) {
      _ when d.limitAsildi => s.error,
      'aktif' => s.basarili,
      'tahsilatta' => s.uyari,
      _ => s.onSurfaceVariant,
    };

    return DetayBandi(
      baslik: d.unvan,
      altBilgi: [
        d.tip == 'ogretmen' ? 'Öğretmen carisi' : 'Kurumsal cari',
        d.kurumAd,
        ?d.ilce,
        if (d.discountTier != null) 'Kademe ${d.discountTier}',
      ].join(' · '),
      durum: d.limitAsildi ? '$durumAdi · limit aşıldı' : durumAdi,
      durumRengi: durumRenk,
      ikon: d.tip == 'ogretmen'
          ? Icons.person_outline
          : Icons.business_outlined,
      etiket: 'Bakiye',
      deger: Fmt.para(d.bakiye),
      degerRengi: d.bakiye > 0 ? s.error : null,
      degerAlti: [?d.kisiAd, ?d.kisiTelefon].join(' · '),
      yanlar: [
        ('Risk', Fmt.para(d.risk), d.limitAsildi ? s.error : null),
        ('Limit', d.creditLimit == 0 ? 'yok' : Fmt.para(d.creditLimit), null),
        if (d.acikKonsinye > 0)
          ('Konsinye', '${Fmt.adet(d.acikKonsinye)} adet', s.bilgi),
      ],
      // K11 · limit BAKİYEYE değil TOPLAM RİSKE bakar. Çizgi bunu tek
      // bakışta gösterir.
      //
      // Aşım AYRI bir dilim: ilk denemede risk limite kırpılıyordu ve
      // etiket "kullanılan risk 3,1b" yazıyordu — oysa gerçek risk 12,1b'ydi.
      // Sayının yalan söylemesindense çizginin taşması yeğdir.
      alt: d.creditLimit <= 0
          ? null
          : OranSeridi([
              ('Limit içinde', d.risk.clamp(0, d.creditLimit), s.primary),
              if (d.risk > d.creditLimit)
                ('Limit aşımı', d.risk - d.creditLimit, s.error)
              else
                ('Kalan limit', d.creditLimit - d.risk,
                    s.surfaceContainerHigh),
            ]),
    );
  }
}

/// K11 · Limit kontrolü BAKİYEYE değil TOPLAM RİSKE bakar:
/// bakiye + portföydeki vadesi gelmemiş çek.
class _Risk extends StatelessWidget {
  const _Risk({required this.d});
  final CariDetay d;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return CamKart(
      key: K.cariDetayRisk,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const BolumBasligi('Bakiye ve risk'),
          AlanSatiri('Bakiye', Fmt.para(d.bakiye),
              mono: true, kalin: true, renk: d.bakiye > 0 ? s.error : null),
          AlanSatiri('Toplam risk', Fmt.para(d.risk),
              mono: true, ikincil: 'bakiye + vadesi gelmemiş çek'),
          AlanSatiri(
              'Kredi limiti',
              d.creditLimit == 0 ? '—' : Fmt.para(d.creditLimit),
              mono: true,
              ikincil: d.creditLimit == 0 ? 'limit tanımlı değil' : null),
          if (d.acikKonsinye > 0)
            AlanSatiri('Açık konsinye', '${Fmt.adet(d.acikKonsinye)} adet',
                mono: true, ikincil: 'limite girmez, mülkiyet dükkanda'),
          const SizedBox(height: T.s3),
          if (d.limitAsildi)
            KuralNotu(
                'Risk kredi limitini aşıyor. Yeni sipariş onaya düşer.',
                ikon: Icons.gpp_maybe_outlined,
                renk: s.uyari)
          else
            const KuralNotu(
                'Yalnızca bu cariye aittir — kardeş carilerle toplanmaz.'),
        ],
      ),
    );
  }
}

class _Portfoy extends StatelessWidget {
  const _Portfoy({required this.d});
  final CariDetay d;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final aktif = d.portfoy.where((p) => p.aktif).toList();
    return CamKart(
      dolgu: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(T.s4, T.s4, T.s4, 0),
            child: BolumBasligi('Portföy'),
          ),
          if (aktif.isEmpty)
            // W-2 · atanmamış cariden gelen talep hiçbir kutuya düşmez.
            const BosDurum('Bu cari kimseye atanmamış',
                ikon: Icons.person_off_outlined,
                aciklama: 'Talepleri hiçbir gelen kutusuna düşmez — '
                    'bir pazarlamacıya atanana kadar cevapsız kalır.')
          else
            for (final p in aktif)
              KayitSatiri(
                baslik: p.adSoyad,
                altBilgi: p.periodAd,
                ikon: Icons.person_outline,
                durumRengi: s.primary,
              ),
        ],
      ),
    );
  }
}

/// K7 · Kardeş cariler AYRI satırlardır. Burada TOPLAM SATIRI YOKTUR ve
/// olmayacaktır: okulun temiz carisi, öğretmenin gecikmesiyle limit aşımına
/// düşmemelidir.
class _Kardesler extends StatelessWidget {
  const _Kardesler({required this.d});
  final CariDetay d;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return CamKart(
      key: K.cariDetayKardesler,
      dolgu: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(T.s4, T.s4, T.s4, 0),
            child: BolumBasligi('Aynı kurumdaki diğer cariler'),
          ),
          for (final k in d.kardesCariler)
            KayitSatiri(
              baslik: k.unvan,
              altBilgi: k.ogretmen ? 'Öğretmen carisi' : 'Kurumsal cari',
              ikon: k.ogretmen
                  ? Icons.person_outline
                  : Icons.business_outlined,
              durumRengi: k.bakiye > 0 ? s.uyari : s.onSurfaceVariant,
              deger: Fmt.para(k.bakiye),
              degerRengi: k.bakiye > 0 ? s.error : null,
              onTap: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute<void>(
                      builder: (_) => CariDetayEkrani(cariId: k.id))),
            ),
          const Padding(
            padding: EdgeInsets.all(T.s4),
            child: KuralNotu('Bakiyeler toplanmaz — her cari kendi başına '
                'değerlendirilir. Okul, öğretmenin borcunun kefili değildir.'),
          ),
        ],
      ),
    );
  }
}

/// K6 · Hiçbir hareket silinmez; taşıma günlüğü kalıcıdır.
class _Tasimalar extends StatelessWidget {
  const _Tasimalar({required this.d});
  final CariDetay d;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Padding(
      key: K.cariDetayTasimalar,
      padding: const EdgeInsets.only(top: T.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BolumBasligi('Kurum geçmişi'),
          for (final t in d.tasimalar)
            AlanSatiri(Fmt.tarih(t.tarih), '${t.nereden} → ${t.nereye}',
                ikincil: t.gerekce),
          const SizedBox(height: T.s3),
          KuralNotu('Geçmiş hareketler eski kurumun altında kalır — '
              'hiçbir kayıt geriye dönük taşınmaz.',
              renk: s.onSurfaceVariant),
        ],
      ),
    );
  }
}
