import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/test_keys.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/repositories/siparis_repository.dart';
import '../../../data/services/dosya_indir.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/cam.dart';
import '../../../shared/widgets/detay.dart';
import '../../../shared/widgets/form_kabuk.dart';
import '../../../shared/widgets/liste.dart';
import '../../../shared/widgets/parcalar.dart';
import '../../../shared/widgets/satir.dart';

final makbuzProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>(
        (ref, id) => ref.watch(siparisRepositoryProvider).makbuz(id));

/// B1 · Makbuz. **Fatura değildir** (K26) — fatura kesilmiyor.
/// Tahsilatın belgesidir: kim, ne zaman, ne kadar, hangi teslimatlara mahsup.
class MakbuzEkrani extends ConsumerWidget {
  const MakbuzEkrani({required this.tahsilatId, super.key});
  final String tahsilatId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = ref.watch(makbuzProvider(tahsilatId));

    return CamSayfa(
      baslik: 'Makbuz',
      eylemler: [
          if (m.value != null)
            TextButton.icon(
              key: K.makbuzIndir,
              onPressed: () => _indir(context, m.value!),
              icon: const Icon(Icons.download, size: 16),
              label: const Text('İndir'),
            ),
        const SizedBox(width: T.s2),
      ],
      cocuklar: m.when(
        loading: () => const [
          CamKart(dolgu: false, child: IskeletListe(satir: 5)),
        ],
        error: (e, _) => [Bildirim(e.toString(), tip: BildirimTip.hata)],
        data: (d) => [_Govde(d: d)],
      ),
    );
  }

  Future<void> _indir(BuildContext c, Map<String, dynamic> d) async {
    final html = _html(d);
    final yer = await dosyaIndir(
        Uint8List.fromList(utf8.encode(html)),
        'makbuz-${d['makbuz_no'] ?? d['id']}.html',
        mime: 'text/html;charset=utf-8');
    if (c.mounted) {
      ScaffoldMessenger.of(c).showSnackBar(
          SnackBar(content: Text('İndirildi: $yer · tarayıcıdan yazdırabilirsin')));
    }
  }

  /// Yazdırılabilir makbuz. PDF kütüphanesi eklemek yerine HTML üretiyoruz:
  /// tarayıcının kendi yazdırma penceresi PDF'e de basar.
  @visibleForTesting
  static String htmlUret(Map<String, dynamic> d) => _html(d);

  static String _html(Map<String, dynamic> d) {
    final cari = (d['cari'] as Map?) ?? {};
    final dukkan = (d['dukkan'] as Map?) ?? {};
    final mahsuplar = (d['mahsuplar'] as List?) ?? const [];
    String p(Object? v) => Fmt.para((v as num?)?.toDouble() ?? 0);

    return '''<!doctype html><meta charset="utf-8">
<title>Makbuz ${d['makbuz_no'] ?? ''}</title>
<style>
 body{font:13px/1.5 -apple-system,system-ui,sans-serif;max-width:520px;margin:32px auto;color:#1A1518}
 h1{font-size:15px;margin:0 0 2px} .alt{color:#6b6266;font-size:12px}
 table{width:100%;border-collapse:collapse;margin:16px 0}
 td{padding:5px 0;border-bottom:1px solid #eee} td:last-child{text-align:right}
 .tutar{font-size:22px;font-weight:600;margin:18px 0;text-align:right}
 .kutu{border:1px solid #ddd;border-radius:6px;padding:14px;margin:14px 0}
 .not{color:#6b6266;font-size:11px;margin-top:22px;border-top:1px solid #eee;padding-top:10px}
 @media print{body{margin:0}}
</style>
<h1>${d['isletme'] ?? ''}</h1>
<div class="alt">${dukkan['ad'] ?? ''}${dukkan['ilce'] == null ? '' : ' · ${dukkan['ilce']}'}</div>
<div class="kutu">
  <table>
    <tr><td>Makbuz no</td><td>${d['makbuz_no'] ?? '—'}</td></tr>
    <tr><td>Tarih</td><td>${d['tarih'] ?? ''}</td></tr>
    <tr><td>Cari</td><td>${cari['unvan'] ?? ''}</td></tr>
    ${cari['tax_id'] == null ? '' : '<tr><td>Vergi no</td><td>${cari['tax_id']}</td></tr>'}
    <tr><td>Kurum</td><td>${d['kurum'] ?? '—'}</td></tr>
    <tr><td>Yöntem</td><td>${d['yontem'] ?? ''}</td></tr>
    <tr><td>Tahsil eden</td><td>${d['alan'] ?? ''}</td></tr>
  </table>
  <div class="tutar">${p(d['tutar'])}</div>
</div>
${mahsuplar.isEmpty ? '' : '''
<div class="alt">Mahsup edilen teslimatlar</div>
<table>${mahsuplar.map((x) {
      final mm = (x as Map);
      return '<tr><td>${(mm['tarih'] ?? '').toString().split('T').first}</td>'
          '<td>${p(mm['tutar'])}</td></tr>';
    }).join()}</table>'''}
${((d['dagitilmayan'] as num?) ?? 0) > 0
        ? '<div class="alt">Mahsup edilmeyen (avans): ${p(d['dagitilmayan'])}</div>'
        : ''}
<div class="alt" style="margin-top:12px">
  Makbuz sonrası kalan bakiye: <b>${p(d['kalan_bakiye'])}</b></div>
<div class="not">
  Bu belge bir <b>tahsilat makbuzudur</b>, fatura değildir.
  Resmî belge gerekiyorsa ayrıca düzenlenir.
</div>''';
  }
}

class _Govde extends StatelessWidget {
  const _Govde({required this.d});
  final Map<String, dynamic> d;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final cari = (d['cari'] as Map?) ?? {};
    final dukkan = (d['dukkan'] as Map?) ?? {};
    final mahsuplar = (d['mahsuplar'] as List?) ?? const [];
    double num_(Object? v) => (v as num?)?.toDouble() ?? 0;
    final kalan = num_(d['kalan_bakiye']);
    final dagitilmayan = num_(d['dagitilmayan']);

    // `ListView` DEĞİL: gövde artık sayfanın kaydırma görünümünün İÇİNDE.
    // İç içe iki kaydırıcı, içtekine sınırsız yükseklik veriyor ve
    // "Vertical viewport was given unbounded height" ile düşüyor.
    return Column(
      key: K.makbuzGovde,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DetayBandi(
          baslik: cari['unvan'] as String? ?? '',
          altBilgi: [
            d['isletme'],
            dukkan['ad'],
            dukkan['ilce'],
          ].nonNulls.join(' · '),
          durum: 'Makbuz ${d['makbuz_no'] ?? '—'}',
          durumRengi: s.primary,
          ikon: Icons.receipt_outlined,
          etiket: 'Tahsil edilen',
          deger: Fmt.para(num_(d['tutar'])),
          degerRengi: s.basarili,
          degerAlti: d['tarih'] as String?,
          yanlar: [
            ('Kalan bakiye', Fmt.para(kalan), kalan > 0 ? s.error : null),
          ],
          alt: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              AlanSatiri('Kurum', d['kurum'] as String? ?? '—'),
              AlanSatiri('Yöntem', d['yontem'] as String? ?? ''),
              AlanSatiri('Tahsil eden', d['alan'] as String? ?? ''),
            ],
          ),
        ),
        if (mahsuplar.isNotEmpty) ...[
          // K48 · FIFO: en eski borçtan başlar. Mahsubun hangi teslimata
          // gittiğini görmek, "ödedim ama bakiyem neden düşmedi" sorusunu
          // ortadan kaldırıyor.
          const SayacSeridi('Mahsup edilen teslimatlar',
              sag: 'FIFO · en eski borçtan başlar'),
          for (final x in mahsuplar)
            KayitSatiri(
              baslik: Fmt.tarih(
                  DateTime.tryParse((x as Map)['tarih'] as String? ?? '')),
              altBilgi: switch ((x)['durum']) {
                'odendi' => 'Bu teslimat kapandı',
                'kismi' => 'Kısmi kapandı',
                _ => 'Hâlâ açık',
              },
              ikon: Icons.local_shipping_outlined,
              durumRengi: switch ((x)['durum']) {
                'odendi' => s.basarili,
                'kismi' => s.uyari,
                _ => s.onSurfaceVariant,
              },
              deger: Fmt.para(num_((x)['tutar'])),
            ),
        ],
        Padding(
          padding: const EdgeInsets.all(T.s4),
          child: Column(children: [
            if (dagitilmayan > 0) ...[
              // K48 · borçtan fazla ödeme kaybolmaz, avans olur.
              KuralNotu(
                  'Bu tahsilatın ${Fmt.para(dagitilmayan)} kadarı hiçbir '
                  'teslimata mahsup edilmedi; avans olarak duruyor ve '
                  'sonraki teslimatlara sayılacak.',
                  renk: s.uyari),
              const SizedBox(height: T.s2),
            ],
            // K26 · fatura kesilmiyor; bu belge onun yerine geçmez.
            const KuralNotu(
                'Bu belge bir tahsilat makbuzudur, fatura değildir. '
                'Resmî belge gerekiyorsa ayrıca düzenlenir.'),
          ]),
        ),
        const SonBosluk(),
      ],
    );
  }
}

