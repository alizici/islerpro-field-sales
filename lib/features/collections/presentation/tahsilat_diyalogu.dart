import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/test_keys.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/local/yerel_saglayici.dart';
import '../../../data/repositories/siparis_repository.dart';
import '../../../data/services/saha_kuyrugu.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/widgets/diyalog.dart';
import '../../../shared/widgets/form_kabuk.dart';
import '../../../shared/widgets/mono.dart';
import '../../../shared/widgets/parcalar.dart';
import 'makbuz_ekrani.dart';

const _yontemler = <(String, String)>[
  ('nakit', 'Nakit'), ('havale', 'Havale'), ('kart', 'Kart'),
  ('cek', 'Çek'), ('senet', 'Senet'),
];

final _acikTeslimatlarProvider = FutureProvider.autoDispose
    .family<List<AcikTeslimat>, String>((ref, cariId) =>
        ref.watch(siparisRepositoryProvider).acikTeslimatlar(cariId));

/// Girilen tutarın hangi teslimatlara gideceği.
///
/// K48'in kuralını İSTEMCİDE tekrarlar: en eski açık borçtan başla, her
/// teslimata kalanın yettiği kadarını ver. Sunucudaki
/// `allocate_payment_fifo` ile aynı sırayı kullanmak zorunda — farklı
/// sıralarsa önizleme yalan söyler.
typedef Mahsup = ({AcikTeslimat teslimat, double tutar, bool kapanir});

({List<Mahsup> mahsuplar, double avans}) fifoDagit(
    List<AcikTeslimat> acik, double tutar) {
  var kalan = tutar;
  final m = <Mahsup>[];
  for (final t in acik) {
    if (kalan <= 0) break;
    final pay = kalan < t.kalan ? kalan : t.kalan;
    m.add((teslimat: t, tutar: pay, kapanir: pay >= t.kalan));
    kalan -= pay;
  }
  return (mahsuplar: m, avans: kalan > 0 ? kalan : 0);
}

/// K48 · Tahsilat parçalıdır; mahsup FIFO ile en eski borçtan yapılır.
/// K11 · Çek ve senet ödeme değil ödeme VAADİDİR — bakiye tahsil edildiğinde
/// düşer, çek alındığında değil.
class TahsilatDiyalogu extends ConsumerStatefulWidget {
  const TahsilatDiyalogu({required this.cari, super.key});
  final BorcluCari cari;

  @override
  ConsumerState<TahsilatDiyalogu> createState() => _TahsilatDiyaloguState();
}

class _TahsilatDiyaloguState extends ConsumerState<TahsilatDiyalogu> {
  late final _tutar = TextEditingController(text: Fmt.sayiYaz(widget.cari.bakiye));
  final _makbuz = TextEditingController();
  String _yontem = 'nakit';
  DateTime? _vade;
  bool _kaydediyor = false;
  String? _hata;

  @override
  void initState() {
    super.initState();
    _tutar.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tutar.dispose();
    _makbuz.dispose();
    super.dispose();
  }

  double? get _deger => Fmt.sayiOku(_tutar.text);
  bool get _cek => _yontem == 'cek' || _yontem == 'senet';
  bool get _gecerli => (_deger ?? 0) > 0 && (!_cek || _vade != null) &&
      !_kaydediyor;

  @override
  Widget build(BuildContext context) {
    final acik = ref.watch(_acikTeslimatlarProvider(widget.cari.id));

    return Diyalog(
      baslik: widget.cari.unvan,
      altBaslik: 'Tahsilat',
      hata: _hata,
      mesgul: _kaydediyor,
      onayKey: K.tahsilatKaydet,
      onayEtiketi: 'Tahsilatı kaydet',
      onOnay: _gecerli ? _kaydet : null,
      children: [
        DiyalogOlcu('Açık bakiye', Fmt.para(widget.cari.bakiye),
            kalin: true,
            renk: widget.cari.bakiye > 0
                ? Theme.of(context).colorScheme.error
                : null),
        ParaAlani(
          alanKey: K.tahsilatTutar,
          controller: _tutar,
          etiket: 'Tahsilat tutarı',
          yardim: 'Parçalı ödeme normaldir — taksit planı yoktur',
        ),
        DropdownButtonFormField<String>(
          key: K.tahsilatYontem,
          initialValue: _yontem,
          decoration: const InputDecoration(labelText: 'Ödeme yöntemi'),
          items: [
            for (final y in _yontemler)
              DropdownMenuItem(value: y.$1, child: Text(y.$2)),
          ],
          onChanged: (v) => setState(() => _yontem = v ?? 'nakit'),
        ),
        if (_cek) ...[
          const Bildirim(
            'Çek ve senet ödeme değil ödeme VAADİDİR. Bakiye tahsil '
            'edildiğinde düşer, çek alındığında değil — ama toplam riske '
            'hemen girer (K11).',
            tip: BildirimTip.uyari, key: K.tahsilatUyari),
          OutlinedButton.icon(
            key: K.tahsilatCekVade,
            onPressed: () async {
              final d = await showDatePicker(
                context: context,
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 730)),
                initialDate: DateTime.now().add(const Duration(days: 30)),
              );
              if (d != null) setState(() => _vade = d);
            },
            icon: const Icon(Icons.event, size: 16),
            label: Text(_vade == null
                ? 'Vade tarihi seç (zorunlu)'
                : 'Vade: ${Fmt.tarih(_vade)}'),
          ),
        ] else
          // K48 · Para nereye gidiyor? Eskiden bu ancak KAYDETTİKTEN sonra,
          // makbuzda öğreniliyordu — yani iş bittikten sonra.
          _MahsupOnizleme(acik: acik, tutar: _deger ?? 0),
        TextField(
          controller: _makbuz,
          decoration: const InputDecoration(labelText: 'Makbuz no'),
        ),
      ],
    );
  }

  Future<void> _kaydet() async {
    setState(() { _kaydediyor = true; _hata = null; });
    final kuyruk = ref.read(sahaKuyruguProvider);
    final makbuz = _makbuz.text.trim().isEmpty ? null : _makbuz.text.trim();
    // K43 · Anahtar çevrimiçi denemede de gider: sunucu kaydı yazıp cevap
    // yolda kaybolursa iş kuyruğa girer ve ikinci kez gönderilir. Anahtar
    // olmasa aynı tahsilat iki kez yazılırdı.
    final ck = SahaKuyrugu.anahtar('th');
    final tarih = DateTime.now();
    try {
      final r = await kuyruk.dene(
        () => ref.read(siparisRepositoryProvider).tahsilEt(
              cariId: widget.cari.id,
              tutar: _deger!,
              yontem: _yontem,
              tarih: tarih,
              makbuzNo: makbuz,
              cekVade: _vade,
              clientKey: ck,
            ),
        fn: 'create_payment',
        args: {
          'account_id': widget.cari.id,
          'tutar': _deger,
          'yontem': _yontem,
          'tarih': tarih.toIso8601String().split('T').first,
          'makbuz_no': makbuz,
          'cek_vade': _vade?.toIso8601String().split('T').first,
          'client_key': ck,
        },
        ozet: '${widget.cari.unvan} · ${Fmt.para(_deger!)} tahsilat',
      );
      if (!mounted) return;
      final nav = Navigator.of(context);
      final mesajci = ScaffoldMessenger.of(context);
      nav.pop(true);
      // Kuyruğa girdiyse mahsup DAĞILIMI bilinmiyor: FIFO'yu sunucu yapar,
      // hangi borca ne kadar gittiğini burada uydurmak yanlış olur.
      if (r == null) {
        mesajci.showSnackBar(SnackBar(
            content: Text('${Fmt.para(_deger!)} tahsilat kuyruğa alındı — '
                'çevrimdışı; mahsup ve makbuz no senkronda belli olacak')));
        return;
      }
      mesajci.showSnackBar(SnackBar(
        content: Text(r.cek
            ? 'Çek portföye alındı — bakiye tahsil edilince düşer'
            : '${Fmt.para(r.dagitilan)} mahsup edildi'
              '${r.avans > 0 ? ' · ${Fmt.para(r.avans)} avans' : ''}'),
        action: r.cek ? null : SnackBarAction(
          label: 'Makbuz',
          onPressed: () => nav.push(MaterialPageRoute<void>(
              builder: (_) => MakbuzEkrani(tahsilatId: r.id))),
        ),
      ));
    } catch (e) {
      if (mounted) setState(() { _kaydediyor = false; _hata = e.toString(); });
    }
  }
}

/// Mahsup önizlemesi — "5.000 ₺ aldım, hangi teslimat kapanıyor?"
class _MahsupOnizleme extends StatelessWidget {
  const _MahsupOnizleme({required this.acik, required this.tutar});
  final AsyncValue<List<AcikTeslimat>> acik;
  final double tutar;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    return switch (acik) {
      AsyncLoading() => const DiyalogYukleniyor(boy: 60),
      // Önizleme çizilemiyorsa SUSMAK doğru: yanlış bir dağılım göstermek,
      // hiç göstermemekten kötü. Sunucu FIFO'yu yine de yapacak.
      AsyncError() => const SizedBox.shrink(),
      _ => _govde(context, s, t, acik.value ?? const []),
    };
  }

  Widget _govde(BuildContext context, ColorScheme s, TextTheme t,
      List<AcikTeslimat> liste) {
    if (tutar <= 0) return const SizedBox.shrink();
    if (liste.isEmpty) {
      return KuralNotu(
          'Açık teslimat yok — bu tahsilatın tamamı ${Fmt.para(tutar)} AVANS '
          'olarak durur ve sonraki teslimatlara sayılır.',
          renk: s.uyari);
    }

    final d = fifoDagit(liste, tutar);
    final dagitilan = tutar - d.avans;

    return Container(
      key: K.tahsilatMahsup,
      padding: const EdgeInsets.all(T.s3),
      decoration: BoxDecoration(
        color: s.surfaceContainerHigh.withValues(alpha: 0.5),
        border: Border.all(color: s.outlineVariant),
        borderRadius: BorderRadius.circular(T.rDugme),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const BolumBasligi('Nereye gidecek'),
          OranSeridi([
            ('Mahsup', dagitilan, s.basarili),
            if (d.avans > 0) ('Avans', d.avans, s.uyari),
          ]),
          const SizedBox(height: T.s3),
          for (final m in d.mahsuplar)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(children: [
                Icon(
                    m.kapanir
                        ? Icons.check_circle_outline
                        : Icons.incomplete_circle,
                    size: 15,
                    color: m.kapanir ? s.basarili : s.uyari),
                const SizedBox(width: 6),
                Expanded(
                  // İKİ satır: kısmi kapanan teslimatta "kalan ₺1.500,00"
                  // kırpılıyordu — oysa satırın en önemli bilgisi o.
                  child: Text(
                    [
                      Fmt.tarih(m.teslimat.tarih),
                      '${m.teslimat.kalem} kalem',
                      if (!m.kapanir)
                        'kalan ${Fmt.para(m.teslimat.kalan - m.tutar)}',
                    ].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodySmall,
                  ),
                ),
                const SizedBox(width: T.s2),
                Mono(Fmt.para(m.tutar),
                    size: 12,
                    weight: FontWeight.w600,
                    color: m.kapanir ? s.basarili : s.uyari),
              ]),
            ),
          if (d.avans > 0)
            Padding(
              padding: const EdgeInsets.only(top: T.s2),
              child: Text(
                // K48 · borçtan fazla ödeme kaybolmaz, avans olur.
                '${Fmt.para(d.avans)} hiçbir teslimata gitmiyor — AVANS '
                'olarak durur ve sonraki teslimatlara sayılır.',
                style: t.bodySmall?.copyWith(color: s.uyari),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: T.s2),
            child: Text('En eski borçtan başlanır (FIFO).',
                style: t.bodySmall),
          ),
        ],
      ),
    );
  }
}
