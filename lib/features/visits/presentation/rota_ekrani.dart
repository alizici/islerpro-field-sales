import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/test_keys.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/local/yerel_saglayici.dart';
import '../../../data/repositories/ziyaret_repository.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/widgets/bolum.dart';
import '../../../shared/widgets/form_kabuk.dart';
import '../../../shared/widgets/cam.dart';
import '../../../shared/widgets/liste.dart';
import '../../../shared/widgets/mono.dart';
import '../../../shared/widgets/parcalar.dart';
import '../../../shared/widgets/satir.dart';
import '../../institutions/presentation/kurum_detay_ekrani.dart';
import 'ziyaret_cubugu.dart';
import 'ziyaret_detay_ekrani.dart';
import 'ziyaret_durumu.dart';

/// Rota — günün planı ve nereye gidilmesi gerektiğinin gerekçesi.
///
/// Ekran iki soruyu ayrı tutar:
///   1. **Ne planladım?**  → duraklar
///   2. **Ne yapmalıydım?** → öneriler, her biri kendi gerekçesiyle
///
/// İkisi karıştırılmaz: sistem rotayı kendi kurmaz. Sahayı tanıyan
/// pazarlamacıdır; uygulama yalnızca unutulanı hatırlatır.
class RotaEkrani extends ConsumerWidget {
  const RotaEkrani({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rota = ref.watch(rotaProvider(null));
    final acik = ref.watch(acikZiyaretProvider).value;

    return CamSayfa(
      baslik: 'Rota',
      onYenile: () async => ziyaretTazeleW(ref),
      eylemler: [
          IconButton(
            tooltip: 'Ziyaret geçmişi',
            onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => const ZiyaretGecmisiEkrani())),
            icon: const Icon(Icons.history, size: 20),
          ),
          IconButton(
            tooltip: 'Yenile',
            onPressed: () => ziyaretTazeleW(ref),
            icon: const Icon(Icons.refresh, size: 20),
          ),
        const SizedBox(width: T.s2),
      ],
      cocuklar: rota.when(
        loading: () => const [
          _OzetIskeleti(),
          SizedBox(height: T.s4),
          CamKart(dolgu: false, child: IskeletListe(satir: 5)),
        ],
        error: (e, _) => [Bildirim(e.toString(), tip: BildirimTip.hata)],
        data: (r) => [
          _Ozet(r: r),
          const SizedBox(height: T.s4),
          _Duraklar(r: r, acikKurumId: acik?.kurumId),
          const SizedBox(height: T.s4),
          const _Oneriler(),
          const SonBosluk(),
        ],
      ),
    );
  }
}

/// Günün özeti — kaç durak var, kaçı bitti, kaçı plansız çıktı.
class _Ozet extends StatelessWidget {
  const _Ozet({required this.r});
  final Rota r;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final kalan = (r.planlanan - r.tamamlanan).clamp(0, r.planlanan);
    return CamKart(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: SayiBloku(
                etiket: 'Bugünün rotası',
                deger: r.bos ? '—' : '${r.tamamlanan}/${r.planlanan}',
                altBilgi: r.bos
                    ? 'Henüz durak eklenmedi'
                    : '${r.tamamlanan}/${r.planlanan} tamamlandı'
                        '${r.plansizZiyaret > 0
                            ? " · ${r.plansizZiyaret} plansız ziyaret" : ""}',
                renk: r.planlanan > 0 && r.tamamlanan == r.planlanan
                    ? s.basarili
                    : null,
              ),
            ),
          ]),
          if (r.planlanan > 0) ...[
            const SizedBox(height: T.s3),
            OranSeridi([
              ('Bitti', r.tamamlanan.toDouble(), s.basarili),
              ('Kalan', kalan.toDouble(), s.surfaceContainerHigh),
            ]),
          ],
        ],
      ),
    );
  }
}

class _OzetIskeleti extends StatelessWidget {
  const _OzetIskeleti();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(T.s4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Iskelet(110, 10),
          SizedBox(height: T.s2),
          Iskelet(90, 28),
          SizedBox(height: T.s4),
          Iskelet(double.infinity, 7, yuvarlak: 4),
        ]),
      );
}

class _Duraklar extends ConsumerWidget {
  const _Duraklar({required this.r, this.acikKurumId});
  final Rota r;
  final String? acikKurumId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = Theme.of(context).colorScheme;
    return Column(
      key: K.rotaDuraklar,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SayacSeridi('Duraklar',
            sag: r.bos ? null : '${r.planlanan} durak · sırayı sürükleyerek '
                'değiştir'),
        Divider(height: 1, color: s.outlineVariant),
        if (r.bos)
          const BosDurum(
            'Rotan boş',
            ikon: Icons.route_outlined,
            aciklama: 'Aşağıdaki önerilerden durak ekle — sistem rotayı '
                'kendi kurmaz, sahayı sen tanıyorsun.',
          )
        else
          ReorderableListView.builder(
            key: K.rotaSiralama,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: r.duraklar.length,
            onReorder: (eski, yeni) async {
              final l = [...r.duraklar];
              if (yeni > eski) yeni -= 1;
              l.insert(yeni, l.removeAt(eski));
              await ref.read(ziyaretRepositoryProvider)
                  .planSirala(l.map((e) => e.planId).toList());
              ziyaretTazeleW(ref);
            },
            itemBuilder: (_, i) => _Durak(
              key: ValueKey(r.duraklar[i].planId),
              d: r.duraklar[i],
              index: i,
              acik: r.duraklar[i].kurumId == acikKurumId,
            ),
          ),
      ],
    );
  }
}

class _Durak extends ConsumerWidget {
  const _Durak({required this.d, required this.index, required this.acik,
                super.key});
  final RotaDurak d;
  final int index;
  final bool acik;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = Theme.of(context).colorScheme;
    // Durakta BEKLEYEN İŞ tek satırda toplanır. Eskiden dört rozet yan yana
    // diziliyordu ve borç ile "2 talep" aynı sesle bağırıyordu; oysa
    // pazarlamacının gitme sebebi ikisinden biri.
    final is_ = <String>[
      if (d.borc > 0) '${Fmt.para(d.borc)} borç',
      if (d.bekleyenTalep > 0) '${d.bekleyenTalep} talep bekliyor',
      if (d.hazirSiparis > 0) '${d.hazirSiparis} hazır sipariş',
    ];

    final durumRenk = switch (d) {
      _ when acik => s.primary,
      _ when d.tamam => s.basarili,
      _ when d.durum == 'ertelendi' => s.outline,
      _ when d.borc > 0 => s.error,
      _ => s.outlineVariant,
    };

    return KayitSatiri(
      key: K.rotaDurak(d.kurumId),
      baslik: d.kurumAd,
      altBilgi: [
        if (d.ilce != null) d.ilce!,
        if (d.amac != null) d.amac!,
        if (d.sonZiyaret == null) 'ilk ziyaret',
        if (d.durum == 'ertelendi') 'ertelendi',
      ].join(' · '),
      vurgu: is_.isEmpty ? null : is_.join(' · '),
      vurguRengi: d.borc > 0 ? s.error : s.bilgi,
      durumRengi: durumRenk,
      // Sıra numarası duraklara "rota" hissi veren tek şey: liste değil,
      // gidilecek yerlerin sırası.
      oncul: ReorderableDragStartListener(
        index: index,
        child: _Sira(no: index + 1, tamam: d.tamam, acik: acik),
      ),
      sondaki: Padding(
        padding: const EdgeInsets.only(left: T.s2),
        child: _DurakEylem(d: d, acik: acik),
      ),
      onTap: () => Navigator.of(context).push<void>(MaterialPageRoute(
          builder: (_) => KurumDetayEkrani(kurumId: d.kurumId))),
    );
  }
}

class _Sira extends StatelessWidget {
  const _Sira({required this.no, required this.tamam, required this.acik});
  final int no;
  final bool tamam, acik;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final renk = acik ? s.primary : (tamam ? s.basarili : s.onSurfaceVariant);
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tamam || acik ? renk : Colors.transparent,
        border: Border.all(color: tamam || acik ? renk : s.outline),
        shape: BoxShape.circle,
      ),
      child: tamam
          ? Icon(Icons.check, size: 16, color: s.surfaceContainerLowest)
          : Mono('$no',
              size: 13,
              weight: FontWeight.w600,
              color: acik ? s.surfaceContainerLowest : renk),
    );
  }
}

class _DurakEylem extends ConsumerWidget {
  const _DurakEylem({required this.d, required this.acik});
  final RotaDurak d;
  final bool acik;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (acik) {
      return TextButton(
        key: K.rotaBitir(d.kurumId),
        onPressed: () async {
          final z = ref.read(acikZiyaretProvider).value;
          if (z != null) {
            await ziyaretBitirAkisi(context, ref,
                ziyaretId: z.id, yerel: z.yerel, kurumAd: z.kurumAd);
          }
        },
        child: const Text('Bitir'),
      );
    }
    if (d.tamam && d.ziyaretId != null) {
      return IconButton(
        tooltip: 'Ziyareti gör',
        onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute(
            builder: (_) => ZiyaretDetayEkrani(ziyaretId: d.ziyaretId!))),
        icon: const Icon(Icons.chevron_right, size: 20),
      );
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      FilledButton.tonal(
        key: K.rotaGiris(d.kurumId),
        onPressed: () => ziyaretBaslatAkisi(context, ref, d.kurumId, d.kurumAd),
        child: const Text('Giriş'),
      ),
      PopupMenuButton<String>(
        tooltip: 'Durak',
        onSelected: (v) async {
          final rep = ref.read(ziyaretRepositoryProvider);
          if (v == 'sil') {
            await rep.plandanCikar(d.planId);
          } else {
            await rep.planDurumu(d.planId, v);
          }
          ziyaretTazeleW(ref);
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'ertelendi', child: Text('Ertele')),
          PopupMenuItem(value: 'sil', child: Text('Rotadan çıkar')),
        ],
      ),
    ]);
  }
}

/// Ziyaret açma. Açık bir ziyaret varken sunucu reddeder; hata mesajı hangi
/// kurumun açık kaldığını söyler — kullanıcı ne olduğunu tahmin etmez.
Future<void> ziyaretBaslatAkisi(BuildContext context, WidgetRef ref,
    String kurumId, String kurumAd) async {
  final kuyruk = ref.read(sahaKuyruguProvider);
  final giris = DateTime.now();
  // K43 · client_key idempotency anahtarıdır: kuyruk iki kez yüklenirse
  // sunucu ikinci isteği YENİ ZİYARET saymaz.
  final ck = 'zv-${giris.microsecondsSinceEpoch}';
  try {
    final r = await kuyruk.dene(
      () => ref.read(ziyaretRepositoryProvider)
          .baslat(kurumId, clientKey: ck, girisSaati: giris),
      fn: 'start_visit',
      args: {'institution_id': kurumId, 'client_key': ck,
             'checked_in_at': giris.toIso8601String()},
      ozet: '$kurumAd ziyareti',
    );
    if (r == null) await kuyruk.yerelZiyaretAc(kurumId, kurumAd, giris);
    ziyaretTazeleW(ref);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(r == null
            ? '$kurumAd ziyareti başladı — çevrimdışı, senkronda yüklenecek'
            : '$kurumAd ziyareti başladı')));
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_temiz(e.toString()))));
  }
}

/// Sunucu hatasını okunur hâle getirir. PostgrestException'ın `toString`'i
/// kod, detay ve ipucu da taşır; kullanıcıya yalnızca mesaj gösterilir.
String _temiz(String m) {
  final i = m.indexOf('message: ');
  if (i >= 0) return m.substring(i + 9).split(', code:').first;
  return m
      .replaceFirst('Bad state: ', '')
      .replaceFirst('Exception: ', '');
}

/// Öneriler: sistemin bildiği, pazarlamacının unutmuş olabileceği şeyler.
class _Oneriler extends ConsumerWidget {
  const _Oneriler();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = ref.watch(rotaOnerisiProvider);
    final s = Theme.of(context).colorScheme;
    final l = (o.value ?? const <RotaOneri>[])
        .where((e) => !e.planda)
        .toList();

    return Column(
      key: K.rotaOneriler,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: T.s4),
        SayacSeridi('Uğranması gerekenler',
            sag: 'Portföyündeki kurumlar — sebebiyle birlikte'),
        Divider(height: 1, color: s.outlineVariant),
        ...switch (o) {
          AsyncError(:final error) => [
              Padding(
                padding: const EdgeInsets.all(T.s4),
                child: Bildirim(error.toString(), tip: BildirimTip.hata),
              ),
            ],
          AsyncLoading() => const [IskeletListe(satir: 3)],
          _ when l.isEmpty => const [
              BosDurum('Portföyünde kurum bağlı cari yok',
                  ikon: Icons.school_outlined,
                  aciklama: 'Öneri, portföyündeki carilerin kurumlarından '
                      'çıkar — portföyün boşsa önerilecek bir şey de yok.'),
            ],
          _ => [
              for (var i = 0; i < l.length; i++) ...[
                if (i > 0) Divider(height: 1, color: s.outlineVariant),
                _Oneri(r: l[i]),
              ],
            ],
        },
      ],
    );
  }
}

class _Oneri extends ConsumerWidget {
  const _Oneri({required this.r});
  final RotaOneri r;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = Theme.of(context).colorScheme;
    // Öneri GEREKÇESİYLE gelir: "45 gündür uğranmadı" satırın kendisi kadar
    // önemli — sebebi olmayan öneri emirdir, öneri değil.
    return KayitSatiri(
      key: K.rotaOneri(r.kurumId),
      baslik: r.kurumAd,
      vurgu: r.neden,
      vurguRengi: r.acil ? s.error : s.onSurfaceVariant,
      ikon: r.acil ? Icons.priority_high : Icons.schedule,
      durumRengi: r.acil ? s.error : null,
      sondaki: IconButton(
        key: K.rotaEkle(r.kurumId),
        tooltip: 'Rotaya ekle',
        onPressed: () async {
          await ref.read(ziyaretRepositoryProvider).planaEkle(r.kurumId);
          ziyaretTazeleW(ref);
        },
        icon: const Icon(Icons.add_circle_outline, size: 22),
      ),
      onTap: () => Navigator.of(context).push<void>(MaterialPageRoute(
          builder: (_) => KurumDetayEkrani(kurumId: r.kurumId))),
    );
  }
}

/// Ziyaret geçmişi. Çıktısı sıfır olan ziyaret listede kalır — ölçüt budur.
class ZiyaretGecmisiEkrani extends ConsumerWidget {
  const ZiyaretGecmisiEkrani({this.userId, this.kurumId, super.key});
  final String? userId, kurumId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = ref.watch(
        ziyaretlerProvider((userId: userId, kurumId: kurumId, gun: 30)));
    final s = Theme.of(context).colorScheme;
    return CamSayfa(
      baslik: 'Ziyaretler',
      // K10 · ziyaret ÇIKTIYLA ölçülür: çıktısı sıfır olan ziyaret de
      // listede kalır, gizlenmez — ölçüt budur.
      slivers: [
        ListeGovdesi<ZiyaretOzet>(
        veri: l,
        listeKey: K.ziyaretListesi,
        bos: const BosDurum('Son 30 günde ziyaret yok',
            ikon: Icons.history,
            aciklama: 'Ziyaret, kuruma girişte açılır ve çıkışta kapanır.'),
        satir: (_, v, _) => KayitSatiri(
          baslik: v.kurumAd,
          altBilgi: [
            Fmt.tarihSaat(v.girisSaati),
            if (v.dakika != null) '${v.dakika} dk',
            if (v.pazarlamaci != null) v.pazarlamaci!,
          ].join(' · '),
          vurgu: v.acik ? 'Hâlâ açık — kapatılmadı' : null,
          vurguRengi: s.uyari,
          ikon: Icons.place_outlined,
          durumRengi: v.acik
              ? s.uyari
              : (v.cikti == 0 ? s.outline : s.basarili),
          deger: v.acik ? null : '${v.cikti} kayıt',
          degerRengi: v.cikti == 0 ? s.onSurfaceVariant : s.basarili,
          onTap: () => Navigator.of(context).push<void>(MaterialPageRoute(
              builder: (_) => ZiyaretDetayEkrani(ziyaretId: v.id))),
        ),
        ),
      ],
    );
  }
}
