import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session.dart';
import '../../../core/test_keys.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/repositories/rapor_repository.dart';
import '../../../data/services/dosya_indir.dart';
import '../../../data/services/rapor_disa_aktar.dart';
import '../../../shared/widgets/cam.dart';
import '../../../shared/widgets/bolum.dart';
import '../../../shared/widgets/diyalog.dart';
import '../../../shared/widgets/liste.dart';
import '../../../shared/widgets/form_kabuk.dart';
import '../../../shared/widgets/mono.dart';
import 'rapor_durumu.dart';

/// K50 · Tek rapor ekranı — TÜM raporlar için.
///
/// Bu ekranın rapora özel hiçbir dalı yoktur: sütunları, kırılım seçeneklerini
/// ve süzgeçleri sunucudan gelen tanım söyler. Yeni rapor eklemek için buraya
/// dokunmak gerekiyorsa motor bozulmuş demektir.
class RaporEkrani extends ConsumerStatefulWidget {
  const RaporEkrani({required this.tanim, this.kayitli, super.key});
  final RaporTanimi tanim;
  /// Kaydedilmiş rapordan açıldıysa kurulumu ondan gelir.
  final KayitliRapor? kayitli;

  @override
  ConsumerState<RaporEkrani> createState() => _RaporEkraniState();
}

class _RaporEkraniState extends ConsumerState<RaporEkrani> {
  bool _indiriliyor = false;

  @override
  void initState() {
    super.initState();
    // Kurulum ekran açılırken bir kez yazılır: build sırasında provider
    // değiştirmek Riverpod'da "build sırasında setState" hatası verir.
    final k = widget.kayitli;
    Future.microtask(() {
      if (!mounted) return;
      ref.read(raporKurulumProvider.notifier).ayarla(RaporKurulumu(
            kirilim: k?.kirilim ?? widget.tanim.varsayilanKirilim,
            filtreler: k?.filtreler ?? const {},
          ));
    });
  }

  @override
  Widget build(BuildContext context) {
    final sonuc = ref.watch(raporSonucProvider(widget.tanim.kod));
    return CamSayfa(
      baslik: widget.kayitli?.ad ?? widget.tanim.ad,
      eylemler: [
          IconButton(
            key: K.raporKaydet,
            tooltip: 'Raporu kaydet',
            onPressed: sonuc.value == null ? null : _kaydet,
            icon: const Icon(Icons.bookmark_add_outlined, size: 20),
          ),
          IconButton(
            key: K.raporExcel,
            tooltip: 'Excel',
            onPressed: _indiriliyor || sonuc.value == null
                ? null : () => _disaAktar(excel: true),
            icon: const Icon(Icons.table_view_outlined, size: 20),
          ),
          IconButton(
            key: K.raporPdf,
            tooltip: 'PDF',
            onPressed: _indiriliyor || sonuc.value == null
                ? null : () => _disaAktar(excel: false),
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
          ),
        const SizedBox(width: T.s2),
      ],
      cocuklar: sonuc.when(
        loading: () => const [
          CamKart(dolgu: false, child: IskeletListe(satir: 7)),
        ],
        error: (e, _) => [Bildirim(e.toString(), tip: BildirimTip.hata)],
        data: (r) => [
            if (widget.tanim.aciklama != null)
              Padding(
                padding: const EdgeInsets.only(bottom: T.s3),
                child: Text(widget.tanim.aciklama!,
                    style: Theme.of(context).textTheme.bodySmall),
              ),
            // Kural devreye girdiyse SÖYLENİR. Sessizce düzeltmek, kullanıcıya
            // istediği raporu gördüğünü sandırır.
            for (final u in r.uyarilar)
              Padding(
                padding: const EdgeInsets.only(bottom: T.s3),
                child: Bildirim(u, key: K.raporUyari, tip: BildirimTip.uyari),
              ),
            if (r.onbellekten)
              const Padding(
                padding: EdgeInsets.only(bottom: T.s3),
                child: Bildirim(
                    'Kapalı dönem: bu özet bir kez hesaplandı ve '
                    'saklandı. Kapalı dönemde veri değişmez.',
                    key: K.raporOnbellek, tip: BildirimTip.bilgi),
              ),
            _Kirilim(tanim: widget.tanim, sonuc: r),
            const SizedBox(height: T.s3),
            _Tablo(sonuc: r),
          const SonBosluk(),
        ],
      ),
    );
  }

  Future<void> _disaAktar({required bool excel}) async {
    final r = ref.read(raporSonucProvider(widget.tanim.kod)).value;
    if (r == null) return;
    setState(() => _indiriliyor = true);
    final mesajci = ScaffoldMessenger.of(context);
    try {
      final o = ref.read(sessionProvider);
      final kunye = RaporKunyesi(
        raporAd: widget.kayitli?.ad ?? r.ad,
        isletme: o?.data.memberships.firstOrNull?.tenantUnvan ?? '—',
        dukkan: o?.store?.ad ?? '—',
        uretildi: r.uretildiAt,
        satirlar: [
          ('Kırılım', r.kirilim.join(' → ')),
          if (r.eksikSayfa)
            ('Kapsam',
             '${r.satirlar.length} / ${r.kirilimSayisi} kırılım gösterildi '
             '— TOPLAM satırı tümünü kapsar'),
        ],
        uyarilar: r.uyarilar,
      );
      final ad = '${r.kod}-${DateTime.now().toIso8601String().split("T").first}';
      final Uint8List veri;
      final String dosya;
      if (excel) {
        veri = RaporDisaAktar.excel(r, kunye);
        dosya = '$ad.xlsx';
      } else {
        // Türkçe karakter için gömülü yazı tipi: paketin varsayılan
        // Helvetica'sı ş/ğ/İ/ı yerine sessizce boş kare basıyor.
        final font = await rootBundle.load('assets/fonts/IBMPlexSans.ttf');
        veri = await RaporDisaAktar.pdf(r, kunye,
            yaziTipi: font.buffer.asUint8List());
        dosya = '$ad.pdf';
      }
      final yer = await dosyaIndir(veri, dosya,
          mime: excel ? null : 'application/pdf');
      mesajci.showSnackBar(SnackBar(content: Text('İndirildi: $yer')));
    } catch (e) {
      mesajci.showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _indiriliyor = false);
    }
  }

  Future<void> _kaydet() async {
    final kurulum = ref.read(raporKurulumProvider);
    final sonuc = await showDialog<(String, String)>(
      context: context,
      builder: (_) => _KaydetDiyalogu(
          onerilenAd: widget.kayitli?.ad ?? widget.tanim.ad),
    );
    if (sonuc == null || !mounted) return;
    final o = ref.read(sessionProvider);
    if (o?.storeId == null) return;
    final mesajci = ScaffoldMessenger.of(context);
    try {
      await ref.read(raporRepositoryProvider).kaydet(
            ad: sonuc.$1, kod: widget.tanim.kod, storeId: o!.storeId!,
            kirilim: kurulum.kirilim, filtreler: kurulum.filtreler,
            paylasim: sonuc.$2,
            // Başkasının kaydı ÜZERİNE yazılmaz; kendi kaydım güncellenir.
            id: (widget.kayitli?.benim ?? false) ? widget.kayitli!.id : null,
          );
      ref.invalidate(kayitliRaporlarProvider);
      mesajci.showSnackBar(const SnackBar(content: Text('Rapor kaydedildi')));
    } catch (e) {
      mesajci.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }
}

/// Kırılım seçimi. Çok seviyeli olabilir: *yayınevi → ürün*.
class _Kirilim extends ConsumerWidget {
  const _Kirilim({required this.tanim, required this.sonuc});
  final RaporTanimi tanim;
  final RaporSonucu sonuc;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final k = ref.watch(raporKurulumProvider);
    final secili = k.kirilim.isEmpty ? sonuc.kirilim : k.kirilim;
    return Bolum(
      key: K.raporKirilim,
      baslik: 'Kırılım',
      altBaslik: secili.isEmpty
          ? 'Kırılım seçilmedi'
          : secili.join(' → '),
      child: Padding(
        padding: const EdgeInsets.all(T.s4),
        child: Wrap(spacing: T.s2, runSpacing: T.s2, children: [
          for (final b in tanim.boyutlar)
            FilterChip(
              key: K.raporBoyut(b.anahtar),
              label: Text(b.ad),
              selected: secili.contains(b.anahtar),
              onSelected: (s) {
                final y = [...secili];
                if (s) {
                  y.add(b.anahtar);
                } else {
                  y.remove(b.anahtar);
                }
                // Kırılımsız rapor tek satırlık bir toplamdır; boşaltmak
                // yerine son seçim korunur.
                if (y.isEmpty) return;
                ref.read(raporKurulumProvider.notifier)
                    .ayarla(k.kopya(kirilim: y));
              },
            ),
        ]),
      ),
    );
  }
}

class _Tablo extends ConsumerWidget {
  const _Tablo({required this.sonuc});
  final RaporSonucu sonuc;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = Theme.of(context).colorScheme;
    if (sonuc.bos) {
      return const Bolum(
        key: K.raporTablo,
        baslik: 'Sonuç',
        child: BosDurum('Bu süzgeçlerle eşleşen kayıt yok',
            ikon: Icons.query_stats_outlined,
            aciklama: 'Tarih aralığını genişletmeyi ya da bir süzgeci '
                'kaldırmayı dene.'),
      );
    }

    final kurulum = ref.watch(raporKurulumProvider);
    return Bolum(
      key: K.raporTablo,
      baslik: 'Sonuç',
      altBaslik: sonuc.eksikSayfa
          // "Toplam" sayfanın toplamı değil raporun toplamıdır; ikisi farklıysa
          // bunu söylemek zorundayız.
          ? '${sonuc.satirlar.length} / ${sonuc.kirilimSayisi} kırılım '
              '— TOPLAM satırı tümünü kapsar'
          : '${sonuc.satirlar.length} kırılım',
      eylem: Rozet(sonuc.sirala ?? '—'),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 38,
          dataRowMinHeight: 34,
          dataRowMaxHeight: 44,
          columns: [
            for (final c in sonuc.sutunlar)
              DataColumn(
                numeric: c.sayisal,
                onSort: c.sayisal
                    ? (_, _) => ref.read(raporKurulumProvider.notifier)
                        .sirala(c.anahtar)
                    : null,
                label: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(c.ad),
                  if (kurulum.sirala == c.anahtar)
                    Icon(kurulum.artan ? Icons.arrow_upward
                                       : Icons.arrow_downward, size: 13),
                ]),
              ),
          ],
          rows: [
            for (final satir in sonuc.satirlar)
              DataRow(
                key: ValueKey('rapor.satir.${_kimlik(satir)}'),
                cells: [
                  for (final c in sonuc.sutunlar)
                    DataCell(c.sayisal
                        ? Mono(RaporTablosu.yaz(satir[c.anahtar], c.tip),
                            size: 12)
                        : Text(satir[c.anahtar]?.toString() ?? '—')),
                ],
              ),
            DataRow(
              key: const ValueKey('rapor.toplam'),
              color: WidgetStatePropertyAll(s.surfaceContainerHigh),
              cells: [
                for (var i = 0; i < sonuc.sutunlar.length; i++)
                  DataCell(i == 0
                      ? const Text('TOPLAM',
                          style: TextStyle(fontWeight: FontWeight.w600))
                      : sonuc.sutunlar[i].sayisal
                          ? Mono(
                              RaporTablosu.yaz(sonuc.toplam[sonuc.sutunlar[i].anahtar],
                                  sonuc.sutunlar[i].tip),
                              size: 12, weight: FontWeight.w600)
                          : const SizedBox.shrink()),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Satır kimliği TÜM kırılım sütunlarından kurulur.
  ///
  /// Yalnızca ilk sütun kullanılırsa çok seviyeli kırılımda (yayınevi → ürün)
  /// aynı yayınevinin satırları aynı anahtarı alır ve Flutter "iki TableRow
  /// aynı anahtarı taşıyor" diye ekranı çizmeyi bırakır. Kırılım zaten
  /// gruplama kimliğidir; benzersizliği oradan gelir.
  String _kimlik(Map<String, dynamic> satir) => [
        for (final c in sonuc.sutunlar)
          if (c.kirilim) satir[c.anahtar]?.toString() ?? '—',
      ].join('|');
}

class _KaydetDiyalogu extends StatefulWidget {
  const _KaydetDiyalogu({required this.onerilenAd});
  final String onerilenAd;
  @override
  State<_KaydetDiyalogu> createState() => _KaydetDiyaloguState();
}

class _KaydetDiyaloguState extends State<_KaydetDiyalogu> {
  late final _ad = TextEditingController(text: widget.onerilenAd);
  String _paylasim = 'kisisel';

  @override
  void dispose() { _ad.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Diyalog(
        baslik: 'Raporu kaydet',
        // K50 §1.3 · kaydedilen şey rapor DEĞİL, raporun ayarı: kırılım ve
        // süzgeçler. Veri her açılışta yeniden çekilir.
        altBaslik: 'Kırılım ve süzgeçler saklanır, veriler her açılışta '
            'yenilenir',
        genislik: 400,
        onayKey: K.raporKaydetOnay,
        onVazgec: () => Navigator.pop(context),
        onOnay: _ad.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, (_ad.text.trim(), _paylasim)),
        children: [
          TextField(
            key: K.raporKaydetAd,
            controller: _ad,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Ad'),
            onChanged: (_) => setState(() {}),
          ),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'kisisel', label: Text('Yalnızca ben')),
              ButtonSegment(value: 'dukkan', label: Text('Dükkan')),
            ],
            selected: {_paylasim},
            onSelectionChanged: (v) => setState(() => _paylasim = v.first),
          ),
        ],
      );
}
