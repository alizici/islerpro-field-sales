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
import '../../../shared/widgets/diyalog.dart';
import '../../../shared/widgets/form_kabuk.dart';
import '../../../shared/widgets/liste.dart';
import '../../../shared/widgets/parcalar.dart';
import '../../../shared/widgets/satir.dart';
import 'program_durumu.dart';

const _durumAciklama = <String, String>{
  'hazirlaniyor': 'Depoda hazırlanıyor.',
  'ertelendi': 'Yeni tarihe alınır; erteleme geçmişi tutulur.',
  'planlandi': 'Plana geri döner.',
  'uygulandi': 'Sınav yapıldı. Teslimden AYRI bir durumdur.',
  'kapandi': 'Kalem kapanır, daha fazla işlem görmez.',
  'iptal': 'Kalem düşer; teslim edilmişse borcu durur.',
};

/// Program detayı — teslim planı.
///
/// C-3 · Bu ekrandaki kalemler PLANDIR. "Teslim edildi" işaretleyecek bir
/// düğme YOKTUR: teslimat kaydı üretilir, borç oradan doğar (K26). Planı
/// teslim edildi yapıp teslimat yazmamak, borcu hiç doğmamış bir satış olurdu.
class ProgramDetayEkrani extends ConsumerWidget {
  const ProgramDetayEkrani({required this.programId, super.key});
  final String programId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(programDetayProvider(programId));
    return CamSayfa(
      baslik: d.value?.unvan ?? 'Program',
      cocuklar: d.when(
        loading: () => const [
          CamKart(dolgu: false, child: IskeletListe(satir: 5)),
        ],
        error: (e, _) => [Bildirim(e.toString(), tip: BildirimTip.hata)],
        data: (p) => [
          _Baslik(p: p),
          const SizedBox(height: T.s4),
          _Kalemler(p: p),
          const SonBosluk(),
        ],
      ),
    );
  }
}

class _Baslik extends StatelessWidget {
  const _Baslik({required this.p});
  final DenemeProgrami p;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return CamKart(
      key: K.programBaslik,
      dolgu: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DetayBandi(
            baslik: p.unvan,
            altBilgi: [
              ?p.kurumAd,
              ?p.donem,
              '${p.ogrenciSayisi} öğrenci',
              if (p.denemeAdedi != null) '${p.denemeAdedi} deneme',
            ].join(' · '),
            durum: p.aktif ? 'Aktif' : 'Kapalı',
            durumRengi: p.aktif ? s.basarili : s.onSurfaceVariant,
            ikon: p.takvimBagli
                ? Icons.event_repeat_outlined
                : Icons.autorenew,
            etiket: 'Ciro',
            deger: Fmt.para(p.ozet.ciro),
            degerRengi: s.basarili,
            yanlar: [
              // K47 · uygulanan ile teslim edilen AYRI sayılır.
              ('Uygulanan / teslim',
                  '${p.ozet.uygulanan}/${p.ozet.teslimEdilen}',
                  p.ozet.uygulanan < p.ozet.teslimEdilen ? s.uyari : null),
              if (p.periyotGun != null)
                ('Periyot', '${p.periyotGun} gün', null),
              if (p.birimFiyat != null)
                ('Birim fiyat', Fmt.para(p.birimFiyat), null),
            ],
            // Y-8 · teslim takvimini hangisinin ürettiği burada yazılı.
            alt: KuralNotu(
              p.takvimBagli
                  ? 'Takvime bağlı. Kalemler deneme takviminden gelir, '
                      'tarihler de oradan.'
                  : 'Serbest periyot — kalemler elle seçilir, tarihler '
                      'programın periyodundan üretilir.',
              ikon: Icons.tune,
            ),
          ),
        ],
      ),
    );
  }
}

class _Kalemler extends StatelessWidget {
  const _Kalemler({required this.p});
  final DenemeProgrami p;

  @override
  Widget build(BuildContext context) => Column(
        key: K.programKalemler,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SayacSeridi('Teslim planı · ${p.ozet.planlanan} açık'),
          if (p.kalemler.isEmpty)
            const BosDurum('Plana kalem eklenmedi',
                ikon: Icons.event_note_outlined,
                aciklama: 'Program bir plandır: borç doğurmaz. Borç, teslimatla doğar.')
          else ...[
            for (final k in p.kalemler) _Kalem(k: k, programId: p.id),
            const Padding(
              padding: EdgeInsets.all(T.s4),
              child: KuralNotu(
                  'Plan borç doğurmaz — borç teslimattan doğar. Bu yüzden '
                  '"teslim edildi" diye işaretlenen bir düğme yok: teslimat '
                  'kaydı üretilir.'),
            ),
          ],
        ],
      );
}

class _Kalem extends ConsumerWidget {
  const _Kalem({required this.k, required this.programId});
  final TeslimKalemi k;
  final String programId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = Theme.of(context).colorScheme;
    final durumRenk = switch (k.durum) {
      'iptal' => s.onSurfaceVariant,
      'ertelendi' => s.uyari,
      'uygulandi' || 'kapandi' => s.basarili,
      _ => s.primary,
    };
    // İki olgu aynı anda dikkat isteyebiliyor: erteleme geçmişi ve ödeme.
    // Erteleme daha nadir ve daha anlatılası olduğu için öne geçiyor;
    // ödeme durumu alt bilgide sayı olarak zaten görünüyor.
    final (String? vurgu, Color? vurguRenk) = switch (k) {
      _ when k.oncekiTarih != null => (
          'Ertelendi · önceki tarih ${Fmt.tarih(k.oncekiTarih)}'
              '${k.notMetni == null ? "" : " · ${k.notMetni}"}',
          s.uyari,
        ),
      _ when k.odemeDurumu == 'odendi' => ('Ödendi', s.basarili),
      _ when k.odemeDurumu == 'kismi' => ('Kısmi ödendi', s.uyari),
      _ when k.odemeDurumu != null => ('Ödenmedi', s.error),
      _ => (null, null),
    };

    return KayitSatiri(
      key: K.programKalem(k.id),
      baslik: k.ad,
      altBilgi: [
        Fmt.tarih(k.tarih),
        '${k.adet} adet',
        ?k.yayinevi,
        teslimDurumAdi[k.durum] ?? k.durum,
        if (k.tutar != null) Fmt.para(k.tutar),
      ].join(' · '),
      vurgu: vurgu,
      vurguRengi: vurguRenk,
      ikon: k.teslimEdildi
          ? Icons.check_circle_outline
          : Icons.event_note_outlined,
      durumRengi: durumRenk,
      sondaki: _Eylem(k: k, programId: programId),
    );
  }
}

class _Eylem extends ConsumerWidget {
  const _Eylem({required this.k, required this.programId});
  final TeslimKalemi k;
  final String programId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (k.gidilebilir.isEmpty && k.teslimEdildi) {
      return const Icon(Icons.check_circle_outline, size: 20);
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      // Teslimat AYRI bir düğme: durum listesinde yok, çünkü elle
      // işaretlenemez (C-3).
      if (k.acik)
        TextButton(
          key: K.programTeslim(k.id),
          onPressed: () => _teslimEt(context, ref, k, programId),
          child: const Text('Teslim et'),
        ),
      if (k.gidilebilir.isNotEmpty)
        PopupMenuButton<String>(
          key: K.programDurum(k.id),
          tooltip: 'Durum',
          onSelected: (v) => _durumDegistir(context, ref, k, programId, v),
          itemBuilder: (_) => [
            for (final d in k.gidilebilir)
              PopupMenuItem(
                value: d,
                // Her seçeneğin ne YAPTIĞI yazılı: "uygulandı" ile "teslim
                // edildi" farkı menüde görünmezse kimse ayırt etmez.
                child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min, children: [
                  Text(teslimDurumAdi[d] ?? d),
                  Text(_durumAciklama[d] ?? '',
                      style: Theme.of(context).textTheme.bodySmall),
                ]),
              ),
          ],
        ),
    ]);
  }
}

Future<void> _teslimEt(BuildContext context, WidgetRef ref, TeslimKalemi k,
    String programId) async {
  final onay = await showDialog<bool>(
    context: context,
    builder: (_) => Diyalog(
      key: K.programTeslimOnay,
      baslik: 'Teslimat kaydı',
      altBaslik: k.ad,
      genislik: 400,
      onayEtiketi: 'Teslim et',
      onayKey: K.programTeslimEt,
      onVazgec: () => Navigator.pop(context, false),
      onOnay: () => Navigator.pop(context, true),
      children: [
        // C-3 · plan borç doğurmaz; teslimat doğurur. Bu yüzden burada
        // "planı işaretle" değil, TESLİMAT KAYDI üretiliyor.
        Bildirim(
            '${k.adet} adet teslim edilecek. Bu bir teslimat kaydı üretir '
            've BORÇ DOĞURUR.',
            tip: BildirimTip.uyari),
      ],
    ),
  );
  if (onay != true || !context.mounted) return;

  try {
    final r = await ref.read(denemeRepositoryProvider).teslimEt(k.id);
    programTazele(ref, programId);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${r.adet} adet teslim edildi · '
            'bakiye ${Fmt.para(r.bakiye)}')));
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(_temiz(e.toString()))));
  }
}

Future<void> _durumDegistir(BuildContext context, WidgetRef ref,
    TeslimKalemi k, String programId, String durum) async {
  String? not;
  DateTime? tarih;

  if (durum == 'ertelendi') {
    tarih = await showDatePicker(
      context: context,
      initialDate: k.tarih.add(const Duration(days: 7)),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
      helpText: 'Yeni teslim tarihi',
    );
    if (tarih == null || !context.mounted) return;
    not = await showDialog<String>(
      context: context,
      builder: (_) => const _GerekceDiyalogu(),
    );
    if (not == null || !context.mounted) return;
  }

  try {
    await ref.read(denemeRepositoryProvider)
        .teslimDurumu(k.id, durum, not: not, yeniTarih: tarih);
    programTazele(ref, programId);
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(_temiz(e.toString()))));
  }
}

class _GerekceDiyalogu extends StatefulWidget {
  const _GerekceDiyalogu();
  @override
  State<_GerekceDiyalogu> createState() => _GerekceState();
}

class _GerekceState extends State<_GerekceDiyalogu> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Diyalog(
        key: K.programErteleGerekce,
        baslik: 'Erteleme gerekçesi',
        // Erteleme GEÇMİŞİ tutulur: kaçıncı kez ertelendiği ve neden,
        // bir sonraki dönemin anlaşmasında konuşulacak şey.
        altBaslik: 'Zorunlu — erteleme geçmişinde kalıcı olarak durur',
        genislik: 400,
        onayEtiketi: 'Ertele',
        onayKey: K.programErteleOnay,
        onVazgec: () => Navigator.pop(context),
        onOnay: _c.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, _c.text.trim()),
        children: [
          TextField(
            controller: _c,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Gerekçe',
              hintText: 'Okul sınav haftası, kitapçık gecikti…',
            ),
          ),
        ],
      );
}

String _temiz(String m) {
  final i = m.indexOf('message: ');
  if (i >= 0) return m.substring(i + 9).split(', code:').first;
  return m.replaceFirst('Bad state: ', '').replaceFirst('Exception: ', '');
}
