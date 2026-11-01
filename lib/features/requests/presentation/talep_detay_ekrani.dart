import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/test_keys.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/repositories/talep_repository.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/widgets/cam.dart';
import '../../../shared/widgets/detay.dart';
import '../../../shared/widgets/form_kabuk.dart';
import '../../../shared/widgets/liste.dart';
import '../../../shared/widgets/mono.dart';
import '../../../shared/widgets/parcalar.dart';

final talepDetayProvider = FutureProvider.autoDispose
    .family<TalepDetay, String>(
        (ref, id) => ref.watch(talepRepositoryProvider).detay(id));

/// K37 · Karar KALEM bazındadır. 5 kalemin 3'ü onaylanıp 2'si reddedilebilir;
/// en az bir onaylı kalem varsa sipariş doğar.
class TalepDetayEkrani extends ConsumerStatefulWidget {
  const TalepDetayEkrani({required this.talepId, super.key});
  final String talepId;

  @override
  ConsumerState<TalepDetayEkrani> createState() => _TalepDetayEkraniState();
}

class _TalepDetayEkraniState extends ConsumerState<TalepDetayEkrani> {
  /// kalem id → karar (true = onay). Kaydedilene kadar yerelde tutulur.
  final _kararlar = <String, bool>{};
  final _redNedenleri = <String, String>{};
  bool _kaydediyor = false;
  String? _hata;
  bool _degisti = false;

  @override
  Widget build(BuildContext context) {
    final detay = ref.watch(talepDetayProvider(widget.talepId));

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (_, _) {},
      child: CamSayfa(
        baslik: 'Talep',
        // Platformun geri simgesi — kendiliğinden gelen geri düğmesiyle aynı.
        oncul: IconButton(
          icon: const BackButtonIcon(),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () => Navigator.pop(context, _degisti),
        ),
        altSerit: switch (detay.value) {
          final d? when d.karaBaglanabilir => _KararCubugu(
              d: d,
              kararlar: _kararlar,
              redNedenleri: _redNedenleri,
              kaydediyor: _kaydediyor,
              hata: _hata,
              onKaydet: () => _kaydet(d),
              onEleAl: d.durum == 'gonderildi' ? _eleAl : null,
            ),
          _ => null,
        },
        cocuklar: detay.when(
          loading: () => const [
            CamKart(dolgu: false, child: IskeletListe(satir: 5)),
          ],
          error: (e, _) => [Bildirim(e.toString(), tip: BildirimTip.hata)],
          data: (d) => [
              _Baslik(d: d),
              _Cari(d: d),
              _Kalemler(
                d: d,
                kararlar: _kararlar,
                onKarar: (id, onay) => setState(() {
                  if (_kararlar[id] == onay) {
                    _kararlar.remove(id);
                    _redNedenleri.remove(id);
                  } else {
                    _kararlar[id] = onay;
                  }
                }),
                // setState ŞART: gerekçe yazılınca 'Kararı kaydet' açılmalı.
                // Bu olmadan kullanıcı gerekçeyi yazar ama buton kapalı kalır.
                onRedNedeni: (id, neden) =>
                    setState(() => _redNedenleri[id] = neden),
              ),
              if (d.durum == 'karara_baglandi')
                Padding(
                  padding: const EdgeInsets.all(T.s4),
                  child: Bildirim(
                      'Talep karara bağlandı. Onaylanan kalemler '
                      '${Fmt.para(d.onayliTutar)} tutarında siparişe '
                      'dönüşebilir.',
                      tip: BildirimTip.basari),
                ),
              if (d.durum == 'tamamen_reddedildi')
                const Padding(
                  padding: EdgeInsets.all(T.s4),
                  child: Bildirim(
                      'Talebin tüm kalemleri reddedildi; sipariş doğmadı.',
                      tip: BildirimTip.uyari),
                ),
              const SonBosluk(),
          ],
        ),
      ),
    );
  }

  Future<void> _eleAl() async {
    try {
      await ref.read(talepRepositoryProvider).eleAl(widget.talepId);
      _degisti = true;
      ref.invalidate(talepDetayProvider(widget.talepId));
    } catch (e) {
      if (mounted) setState(() => _hata = e.toString());
    }
  }

  Future<void> _kaydet(TalepDetay d) async {
    setState(() { _kaydediyor = true; _hata = null; });
    try {
      final sonuc = await ref.read(talepRepositoryProvider).kararVer(
            talepId: widget.talepId,
            kararlar: [
              for (final e in _kararlar.entries)
                KalemKarari(kalemId: e.key, onay: e.value,
                    redNedeni: _redNedenleri[e.key]),
            ],
          );
      _degisti = true;
      _kararlar.clear();
      _redNedenleri.clear();
      ref.invalidate(talepDetayProvider(widget.talepId));
      if (!mounted) return;
      setState(() => _kaydediyor = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(sonuc.sonuclandi
            ? '${sonuc.onaylanan} onaylandı, ${sonuc.reddedilen} reddedildi'
            : '${sonuc.bekleyen} kalem hâlâ bekliyor'),
      ));
    } catch (e) {
      if (mounted) setState(() { _kaydediyor = false; _hata = e.toString(); });
    }
  }
}

/// Talebin yaşam çizgisi. K37 · karar KALEM bazındadır, bu yüzden "karara
/// bağlandı" tek adım değil bir eşik: bekleyen kalem kaldıkça talep kapanmaz.
const _asamalar = ['Gönderildi', 'İncelemede', 'Karara bağlandı'];

int _asama(String durum) => switch (durum) {
      'gonderildi' => 0,
      'incelemede' => 1,
      'karara_baglandi' || 'tamamen_reddedildi' => 2,
      _ => 0,
    };

class _Baslik extends StatelessWidget {
  const _Baslik({required this.d});
  final TalepDetay d;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final renk = switch (d.durum) {
      'gonderildi' => s.uyari,
      'incelemede' => s.bilgi,
      'karara_baglandi' => s.basarili,
      'tamamen_reddedildi' => s.error,
      _ => s.onSurfaceVariant,
    };
    final istenen = d.kalemler.fold<double>(0, (a, k) => a + (k.satirTutari ?? 0));

    return DetayBandi(
      baslik: d.cari.unvan,
      altBilgi: [
        if (d.kurumAd.isNotEmpty) d.kurumAd,
        d.kaynak == 'ogretmen' ? 'Öğretmen açtı' : 'Pazarlamacı açtı',
        ?d.acan,
        Fmt.tarihSaat(d.createdAt),
      ].join(' · '),
      durum: switch (d.durum) {
        'gonderildi' => 'Gönderildi',
        'incelemede' => 'İncelemede',
        'karara_baglandi' => 'Karara bağlandı',
        'tamamen_reddedildi' => 'Reddedildi',
        _ => d.durum,
      },
      durumRengi: renk,
      ikon: d.kaynak == 'ogretmen'
          ? Icons.person_outline
          : Icons.business_outlined,
      etiket: 'İstenen tutar',
      deger: Fmt.para(istenen),
      degerAlti: d.istenenTarih == null
          ? null
          : 'İstenen teslim ${Fmt.tarih(d.istenenTarih)}',
      yanlar: [
        ('Kalem', '${d.kalemler.length}', null),
        if (d.bekleyen > 0) ('Bekleyen', '${d.bekleyen}', s.uyari),
        if (d.onayliTutar > 0)
          ('Onaylanan', Fmt.para(d.onayliTutar), s.basarili),
      ],
      alt: Column(mainAxisSize: MainAxisSize.min, children: [
        AsamaCizgisi(
          asamalar: _asamalar,
          aktif: _asama(d.durum),
          kirik: d.durum == 'tamamen_reddedildi',
          renk: renk,
        ),
        // Talebi açan kişinin yazdığı not, karar verenin en çok ihtiyaç
        // duyduğu bağlam — rozetlerin arasında kaybolmamalı.
        if (d.notMetni != null) ...[
          const SizedBox(height: T.s3),
          KuralNotu(d.notMetni!,
              ikon: Icons.format_quote, renk: s.onSurfaceVariant),
        ],
      ]),
    );
  }
}

/// K7 · Yalnızca BU carinin durumu. Kurum toplamı gösterilmez.
/// K11 · Limit kontrolü toplam riske bakar.
class _Cari extends StatelessWidget {
  const _Cari({required this.d});
  final TalepDetay d;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return CamKart(
      key: K.talepCariRisk,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BolumBasligi('Carinin durumu'),
          AlanSatiri('Bakiye', Fmt.para(d.cari.bakiye),
              mono: true, kalin: true,
              renk: d.cari.bakiye > 0 ? s.error : null),
          // K11 · limit kontrolü bakiyeye değil toplam riske bakar.
          AlanSatiri('Toplam risk', Fmt.para(d.cari.risk),
              mono: true, ikincil: 'bakiye + vadesi gelmemiş çek'),
          if (d.cari.creditLimit > 0)
            AlanSatiri('Kredi limiti', Fmt.para(d.cari.creditLimit),
                mono: true),
          const SizedBox(height: T.s3),
          // İki kural AYNI ANDA doğru ve ayrı soruları cevaplıyor: biri
          // "kimin borcu" (K7), öbürü "ne olacak" (K11). Biri öbürünün
          // yerine geçemez.
          const KuralNotu('Yalnızca bu cari — kardeş cariler etkilemez.'),
          if (d.cari.limitAsildi) ...[
            const SizedBox(height: T.s2),
            KuralNotu(
                'Risk kredi limitini aşıyor — bu talepten doğacak sipariş '
                'onaya düşer.',
                ikon: Icons.gpp_maybe_outlined, renk: s.uyari),
          ],
        ],
      ),
    );
  }
}

class _Kalemler extends StatelessWidget {
  const _Kalemler({required this.d, required this.kararlar,
                   required this.onKarar, required this.onRedNedeni});
  final TalepDetay d;
  final Map<String, bool> kararlar;
  final void Function(String id, bool onay) onKarar;
  final void Function(String id, String neden) onRedNedeni;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Column(
      key: K.talepKalemler,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SayacSeridi(
          '${d.kalemler.length} kalem',
          // K37 · karar kalem bazındadır; kural ancak karar verilebilirken
          // öğretici, sonrasında sadece gürültü.
          sag: d.karaBaglanabilir
              ? 'Her kalem ayrı karara bağlanır — kısmi onay mümkündür'
              : null,
        ),
        for (final k in d.kalemler)
          _KalemSatiri(
            k: k,
            duzenlenebilir: d.karaBaglanabilir && k.bekliyor,
            karar: kararlar[k.id],
            onKarar: (onay) => onKarar(k.id, onay),
            onRedNedeni: (n) => onRedNedeni(k.id, n),
          ),
        if (d.onayliTutar > 0)
          ToplamSatiri(
            etiket: 'Onaylanan tutar',
            deger: Fmt.para(d.onayliTutar),
            renk: s.basarili,
          ),
      ],
    );
  }
}

class _KalemSatiri extends StatefulWidget {
  const _KalemSatiri({required this.k, required this.duzenlenebilir,
                      required this.karar, required this.onKarar,
                      required this.onRedNedeni});
  final TalepKalemi k;
  final bool duzenlenebilir;
  final bool? karar;
  final void Function(bool onay) onKarar;
  final void Function(String neden) onRedNedeni;

  @override
  State<_KalemSatiri> createState() => _KalemSatiriState();
}

class _KalemSatiriState extends State<_KalemSatiri> {
  final _neden = TextEditingController();

  @override
  void dispose() { _neden.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final k = widget.k;
    final s = Theme.of(context).colorScheme;
    final redSecili = widget.karar == false;

    // Kalem şeridi kararın kendisini taşır: on kalemlik bir talepte
    // "hangilerine dokundum" sorusu, çipleri tek tek okumadan
    // cevaplanabilmeli.
    final serit = switch (widget.karar) {
      true => s.basarili,
      false => s.error,
      _ => switch (k.durum) {
          'onaylandi' => s.basarili,
          'reddedildi' => s.error,
          _ when k.fiyatsiz => s.uyari,
          _ => s.outlineVariant,
        },
    };

    return Container(
      key: K.talepKalemi(k.id),
      padding: EdgeInsets.fromLTRB(T.s4 - 3, T.s3, T.s4, T.s3),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: s.outlineVariant),
          left: BorderSide(color: serit, width: 3),
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(k.ad, style: Theme.of(context).textTheme.bodyMedium),
                if (k.altBilgi.isNotEmpty)
                  Text(k.altBilgi,
                      style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: T.s3),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Mono('${Fmt.adet(k.adet)} adet', size: 13,
                weight: FontWeight.w600),
            if (!k.fiyatsiz) ...[
              Mono(Fmt.para(k.satirTutari), size: 12,
                  color: s.onSurfaceVariant),
              // K25 · "%20 — neden?" sorusunun cevabı burada
              if ((k.iskonto ?? 0) > 0)
                MikroEtiket('${Fmt.yuzde(k.iskonto)} · ${k.iskontoKaynak ?? ''}'),
            ],
          ]),
        ]),

        // K23 · eski baskı seçilmişse sessiz kalınmaz
        if (k.baskiUyarisi?.uyari == true) ...[
          const SizedBox(height: T.s2),
          Bildirim(
            'Bu ürünün ${k.baskiUyarisi!.guncel!.etiket} baskısı var'
            '${k.baskiUyarisi!.guncel!.satisFiyat == null ? '' :
               ' (${Fmt.para(k.baskiUyarisi!.guncel!.satisFiyat)})'}.',
            tip: BildirimTip.uyari),
        ],

        const SizedBox(height: T.s2),
        if (!widget.duzenlenebilir)
          Row(children: [
            Text(
              switch (k.durum) {
                'onaylandi' => 'Onaylandı',
                'reddedildi' => 'Reddedildi',
                _ => 'Bekliyor',
              },
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: switch (k.durum) {
                      'onaylandi' => s.basarili,
                      'reddedildi' => s.error,
                      _ => s.uyari,
                    },
                  ),
            ),
            if (k.redNedeni != null) ...[
              const SizedBox(width: T.s2),
              Expanded(
                child: Text('· ${k.redNedeni!}',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
            ],
          ])
        else ...[
          // K12 · fiyatı olmayan ürün siparişe dönüşemez; sebebi düğmeye
          // basmadan ÖNCE yazıyor.
          if (k.fiyatsiz)
            Padding(
              padding: const EdgeInsets.only(bottom: T.s2),
              child: Text('Fiyatı olmayan ürün onaylanamaz — '
                  'bu dükkanda fiyatı yok',
                  style: Theme.of(context).textTheme.labelMedium
                      ?.copyWith(color: s.uyari, fontWeight: FontWeight.w600)),
            ),
          Row(children: [
            Expanded(
              child: SuzgecCipi(
                key: K.kalemOnay(k.id),
                etiket: 'Onayla',
                renk: s.basarili,
                secili: widget.karar == true,
                onTap: k.fiyatsiz ? null : () => widget.onKarar(true),
              ),
            ),
            const SizedBox(width: T.s2),
            Expanded(
              child: SuzgecCipi(
                key: K.kalemRed(k.id),
                etiket: 'Reddet',
                renk: s.error,
                secili: redSecili,
                onTap: () => widget.onKarar(false),
              ),
            ),
          ]),
        ],
        if (redSecili) ...[
          const SizedBox(height: T.s2),
          TextField(
            key: K.redNedeni,
            controller: _neden,
            onChanged: widget.onRedNedeni,
            decoration: const InputDecoration(
              labelText: 'Red gerekçesi',
              helperText: 'Zorunlu — talebi açan kişi bunu görür',
              isDense: true,
            ),
          ),
        ],
      ]),
    );
  }
}

class _KararCubugu extends StatelessWidget {
  const _KararCubugu({required this.d, required this.kararlar,
                      required this.redNedenleri, required this.kaydediyor,
                      required this.hata, required this.onKaydet,
                      required this.onEleAl});
  final TalepDetay d;
  final Map<String, bool> kararlar;
  final Map<String, String> redNedenleri;
  final bool kaydediyor;
  final String? hata;
  final VoidCallback onKaydet;
  final VoidCallback? onEleAl;

  /// Reddedilen her kalem için gerekçe zorunludur (sunucu da reddeder).
  bool get _gerekceEksik => kararlar.entries.any((e) =>
      !e.value && (redNedenleri[e.key] ?? '').trim().isEmpty);

  @override
  Widget build(BuildContext context) {
    final onay = kararlar.values.where((v) => v).length;
    final red = kararlar.values.where((v) => !v).length;
    final kalanBekleyen = d.bekleyen - kararlar.length;

    return EylemSeridi(
      key: K.talepOzet,
      altMetin: kararlar.isEmpty
          ? '${d.bekleyen} kalem bekliyor'
          : '$onay onay · $red red'
              '${kalanBekleyen > 0
                  ? " · $kalanBekleyen kalem sonraya kalıyor" : ""}',
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // K37 · bekleyen kalem kaldıkça talep kapanmaz; bunu kaydetmeden
        // ÖNCE söylemek, "neden hâlâ açık" sorusunu tamamen ortadan kaldırıyor.
        if (kalanBekleyen > 0 && kararlar.isNotEmpty)
          const Bildirim(
              'Bekleyen kalem kaldığı için talep kapanmaz; kalanları sonra '
              'karara bağlayabilirsin.',
              tip: BildirimTip.bilgi),
        if (_gerekceEksik)
          const Bildirim('Reddedilen her kalem için gerekçe zorunlu.',
              tip: BildirimTip.uyari),
        if (hata != null) Bildirim(hata!, tip: BildirimTip.hata),
        Row(children: [
          if (onEleAl != null) ...[
            Expanded(
              child: OutlinedButton.icon(
                key: K.talepEleAl,
                onPressed: onEleAl,
                icon: const Icon(Icons.pan_tool_alt_outlined, size: 16),
                label: const Text('Ele al'),
              ),
            ),
            const SizedBox(width: T.s3),
          ],
          Expanded(
            flex: 2,
            child: FilledButton(
              key: K.talepKararVer,
              onPressed: (kararlar.isEmpty || _gerekceEksik || kaydediyor)
                  ? null
                  : onKaydet,
              child: Text(kaydediyor ? 'Kaydediliyor…' : 'Kararı kaydet'),
            ),
          ),
        ]),
      ]),
    );
  }
}
