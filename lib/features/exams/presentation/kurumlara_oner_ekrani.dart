import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/test_keys.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/repositories/deneme_repository.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/widgets/liste.dart';
import '../../../shared/widgets/cam.dart';
import '../../../shared/widgets/dokunus.dart';
import '../../../shared/widgets/bolum.dart';
import '../../../shared/widgets/detay.dart';
import '../../../shared/widgets/satir.dart';
import '../../../shared/widgets/form_kabuk.dart';
import 'deneme_durumu.dart';

/// Deneme takviminin ASIL İŞİ: bir denemeden tek hamlede çok cariye talep.
///
/// Üç kural ekranda görünür durur:
///   1. Liste **portföydeki** carilerden gelir (K5) — kurumsal ve öğretmen.
///   2. Düzeyi tutmayan cari gösterilmez; hiç mevcut bildirmemiş cari
///      GÖSTERİLİR — bildirmemek eşleşmemek değildir.
///   3. Adet `account_enrollments`'tan otomatik dolar (K22); yoksa dört
///      kademeli yedek zincir devreye girer ve önerinin KAYNAĞI yazılır.
///
/// Sonuç: her cari için **ayrı talep**. Tek bir çok-carili talep üretmek daha
/// verimli görünürdü ama K37'nin kalem bazlı karar makinesini ve K7'nin cari
/// ayrımını birden bozardı.
class KurumlaraOnerEkrani extends ConsumerStatefulWidget {
  const KurumlaraOnerEkrani({required this.deneme, super.key});
  final Deneme deneme;

  @override
  ConsumerState<KurumlaraOnerEkrani> createState() => _OnerState();
}

class _OnerState extends ConsumerState<KurumlaraOnerEkrani> {
  final _secili = <String>{};
  final _adet = <String, int>{};
  bool _kaydediyor = false;
  bool _ilkDoldurmaYapildi = false;
  String? _hata;
  TopluTalepSonucu? _sonuc;

  int _a(String id) => _adet[id] ?? 0;

  int get _toplam =>
      _secili.fold(0, (t, id) => t + _a(id));

  bool _gecerli() =>
      !_kaydediyor && _secili.isNotEmpty &&
      _secili.every((id) => _a(id) > 0);

  /// Öneriler ilk gelişte adet alanlarına yazılır; kullanıcı üzerine
  /// yazabilir. Sonraki tazelemelerde ELLE girilen değer korunur.
  void _ilkDoldur(List<DenemeHedefi> l) {
    if (_ilkDoldurmaYapildi) return;
    _ilkDoldurmaYapildi = true;
    for (final h in l) {
      _adet[h.cariId] = h.oneri;
    }
  }

  Future<void> _gecenSefer(List<DenemeHedefi> l) async {
    final g = await ref.read(denemeRepositoryProvider)
        .gecenSefer(widget.deneme.id);
    if (!mounted) return;
    if (g.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Bu yayınevinin önceki denemesinde talep yok')));
      return;
    }
    setState(() {
      for (final h in l) {
        if (g.containsKey(h.cariId)) {
          _secili.add(h.cariId);
          _adet[h.cariId] = g[h.cariId]!;
        }
      }
    });
  }

  Future<void> _talepAc() async {
    setState(() { _kaydediyor = true; _hata = null; });
    try {
      final r = await ref.read(denemeRepositoryProvider).topluTalep(
        denemeId: widget.deneme.id,
        hedefler: [
          for (final id in _secili) (cariId: id, adet: _a(id))
        ],
        istenenTarih: widget.deneme.uygulamaBaslangic ??
            widget.deneme.stokTarihi,
      );
      if (!mounted) return;
      setState(() { _kaydediyor = false; _sonuc = r; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _kaydediyor = false; _hata = _temiz(e.toString()); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = ref.watch(denemeHedefleriProvider(widget.deneme.id));
    return CamSayfa(
      baslik: widget.deneme.ad,
      cocuklar: _sonuc != null
          ? [_Sonuc(s: _sonuc!)]
          : h.when(
              loading: () => const [Padding(
                  padding: EdgeInsets.symmetric(vertical: T.s6),
                  child: Bekleme())],
              error: (e, _) => [Bildirim(e.toString(), tip: BildirimTip.hata)],
              data: (l) {
                _ilkDoldur(l);
                return [_Form(
                  deneme: widget.deneme,
                  hedefler: l,
                  secili: _secili,
                  adet: _adet,
                  toplam: _toplam,
                  kaydediyor: _kaydediyor,
                  hata: _hata,
                  gecerli: _gecerli(),
                  onSec: (id, v) => setState(
                      () => v ? _secili.add(id) : _secili.remove(id)),
                  onAdet: (id, v) => setState(() => _adet[id] = v),
                  onTumu: (v) => setState(() {
                    _secili
                      ..clear()
                      ..addAll(v ? l.map((e) => e.cariId) : const <String>[]);
                  }),
                  onGecenSefer: () => _gecenSefer(l),
                  onAc: _talepAc,
                )];
              },
            ),
    );
  }
}

String _temiz(String m) {
  final i = m.indexOf('message: ');
  if (i >= 0) return m.substring(i + 9).split(', code:').first;
  return m.replaceFirst('Bad state: ', '').replaceFirst('Exception: ', '');
}

class _Form extends StatelessWidget {
  const _Form({required this.deneme, required this.hedefler,
               required this.secili, required this.adet, required this.toplam,
               required this.kaydediyor, required this.hata,
               required this.gecerli, required this.onSec,
               required this.onAdet, required this.onTumu,
               required this.onGecenSefer, required this.onAc});
  final Deneme deneme;
  final List<DenemeHedefi> hedefler;
  final Set<String> secili;
  final Map<String, int> adet;
  final int toplam;
  final bool kaydediyor, gecerli;
  final String? hata;
  final void Function(String, bool) onSec;
  final void Function(String, int) onAdet;
  final ValueChanged<bool> onTumu;
  final VoidCallback onGecenSefer, onAc;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    // `ListView` DEĞİL: gövde sayfanın kaydırma görünümünün içinde duruyor
    // ve iç içe iki kaydırıcı içtekine sınırsız yükseklik veriyor.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Bolum(
          key: K.onerBaslik,
          baslik: deneme.ad,
          altBaslik: [
            denemeTuruAdi[deneme.turu] ?? deneme.turu,
            if (deneme.yayinevi != null) deneme.yayinevi!,
            if (deneme.duzey != null) deneme.duzey!,
          ].join(' · '),
          eylem: deneme.sabit ? Rozet('Sabit tarih', renk: s.error) : null,
          child: Padding(
            padding: const EdgeInsets.all(T.s4),
            child: Text(
                'Stok ${Fmt.tarih(deneme.stokTarihi)}'
                '${deneme.uygulamaMetniGoster.isEmpty ? ""
                    : " · uygulama ${deneme.uygulamaMetniGoster}"}',
                style: Theme.of(context).textTheme.bodySmall),
          ),
        ),
        const SizedBox(height: T.s3),
        Bolum(
          key: K.onerListe,
          baslik: 'Kime?',
          altBaslik: 'Portföyündeki cariler — düzeyi tutmayanlar gizlendi',
          eylem: Row(mainAxisSize: MainAxisSize.min, children: [
            TextButton(
              key: K.onerGecenSefer,
              onPressed: onGecenSefer,
              child: const Text('Geçen sefer'),
            ),
            TextButton(
              key: K.onerTumu,
              onPressed: () => onTumu(secili.length != hedefler.length),
              child: Text(secili.length == hedefler.length
                  ? 'Seçimi kaldır' : 'Tümünü seç'),
            ),
          ]),
          child: hedefler.isEmpty
              ? const BosDurum(
                  'Portföyünde bu düzeye uygun cari yok',
                  ikon: Icons.school_outlined,
                  aciklama: 'Denemenin düzeyi kurumun kademesiyle '
                      'eşleşmiyorsa öneri listesine girmez.')
              : Column(children: [
                  for (final h in hedefler)
                    _Satir(
                      h: h,
                      secili: secili.contains(h.cariId),
                      adet: adet[h.cariId] ?? 0,
                      onSec: (v) => onSec(h.cariId, v),
                      onAdet: (v) => onAdet(h.cariId, v),
                    ),
                ]),
        ),
        const SizedBox(height: T.s3),
        Bolum(
          key: K.onerOzet,
          baslik: 'Sonuç',
          altBaslik: 'Her cari için AYRI talep açılır — normal talep akışına '
              'girer (K37)',
          child: Padding(
            padding: const EdgeInsets.all(T.s4),
            child: Column(children: [
              AlanSatiri('Seçilen cari', '${secili.length}',
                  mono: true, kalin: true),
              AlanSatiri('Toplam adet', '$toplam', mono: true, kalin: true),
            ]),
          ),
        ),
        if (hata != null) ...[
          const SizedBox(height: T.s3),
          Bildirim(hata!, tip: BildirimTip.hata),
        ],
        const SizedBox(height: T.s4),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            key: K.onerAc,
            onPressed: gecerli ? onAc : null,
            child: Text(kaydediyor ? 'Açılıyor…' : 'Talep aç'),
          ),
        ),
        const SonBosluk(),
      ],
    );
  }
}

class _Satir extends StatelessWidget {
  const _Satir({required this.h, required this.secili, required this.adet,
                required this.onSec, required this.onAdet});
  final DenemeHedefi h;
  final bool secili;
  final int adet;
  final ValueChanged<bool> onSec;
  final ValueChanged<int> onAdet;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(T.s3, T.s2, T.s4, T.s2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Checkbox(
          key: K.onerSec(h.cariId),
          value: secili,
          onChanged: (v) => onSec(v ?? false),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min, children: [
            Text(h.unvan, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text([
              if (h.kurumAd != null) h.kurumAd!,
              // K22 · Mevcut bildirilmişse yazılır; bildirilmemişse önerinin
              // hangi basamaktan geldiği yazılır. Kullanıcı sayının nereden
              // geldiğini görmeden ona güvenemez.
              if (h.mevcut != null) 'mevcut ${h.mevcut}'
              else if (h.oneriEtiket != null) h.oneriEtiket!,
            ].join(' · '), style: Theme.of(context).textTheme.bodySmall),
            if (h.bakiye > 0)
              Text('bakiye ${Fmt.para(h.bakiye)}',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: s.error)),
          ]),
        ),
        const SizedBox(width: T.s2),
        SizedBox(
          width: 84,
          child: TextFormField(
            key: K.onerAdet(h.cariId),
            initialValue: adet == 0 ? '' : '$adet',
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'adet', isDense: true),
            onChanged: (v) => onAdet(int.tryParse(v) ?? 0),
          ),
        ),
      ]),
    );
  }
}

/// Toplu işlem yarım kalabilir; hangi cariye talep açıldığı KALEM KALEM
/// gösterilir. "3 talep açıldı" demek, hangi üçü olduğunu söylemez.
class _Sonuc extends ConsumerWidget {
  const _Sonuc({required this.s});
  final TopluTalepSonucu s;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Bolum(
          key: K.onerSonuc,
          baslik: s.hatali == 0 ? 'Talepler açıldı' : 'Kısmen açıldı',
          altBaslik: '${s.acilan} cari · ${s.toplamAdet} adet',
          eylem: s.hatali > 0
              ? Rozet('${s.hatali} hata', renk: c.error)
              : Rozet('Tamam', renk: c.basarili),
          child: Column(children: [
            // Toplu işlemin sonucu KALEM KALEM gösterilir: "3 talep açıldı"
            // demek, hangi üçü olduğunu söylemez.
            for (final r in s.sonuclar)
              KayitSatiri(
                baslik: r.basarili ? 'Talep açıldı' : 'Açılamadı',
                vurgu: r.hata,
                vurguRengi: c.error,
                ikon: r.basarili
                    ? Icons.check_circle_outline
                    : Icons.error_outline,
                durumRengi: r.basarili ? c.basarili : c.error,
              ),
          ]),
        ),
        const SizedBox(height: T.s4),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Takvime dön'),
          ),
        ),
      ],
    );
  }
}
