import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session.dart';
import '../../../core/test_keys.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/repositories/aktarma_repository.dart';
import '../../../data/services/dosya_indir.dart';
import '../../../data/services/tablo_okuyucu.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/widgets/cam.dart';
import '../../../shared/widgets/bolum.dart';
import '../../../shared/widgets/diyalog.dart';
import '../../../shared/widgets/liste.dart';
import '../../../shared/widgets/parcalar.dart';
import '../../../shared/widgets/satir.dart';
import '../../../shared/widgets/form_kabuk.dart';
import '../../../shared/widgets/mono.dart';
import 'aktarma_durumu.dart';

final aktarmaGecmisiProvider = FutureProvider.autoDispose((ref) {
  final store = ref.watch(sessionProvider)?.storeId;
  return ref.watch(aktarmaRepositoryProvider).gecmis(storeId: store);
});

const _turler = <(String, String, String)>[
  ('urun', 'Ürün', 'Yeni kitap ve denemeler — anahtar barkod'),
  ('fiyat_iskonto', 'Fiyat & iskonto', 'Alış, satış, varsayılan iskonto'),
  ('stok', 'Stok', 'Depo sayacı — mutabakat anı, sıfırdan yazar'),
  ('kurum', 'Kurum', 'Okul ve kurs merkezi listesi'),
  // K20 · Yılda 267 kalem. "Az sayıda, elle girilir" varsayımı yanlıştı.
  ('deneme_takvimi', 'Deneme takvimi',
      'Yıllık deneme listesi — anahtar ad + stok tarihi'),
];

/// K49 · Tek ekran, altı veri türü. Göç ayrı bir iş değildir — 24.632 ürünlük
/// ilk aktarım da buradan yapılır.
class AktarmaEkrani extends ConsumerWidget {
  const AktarmaEkrani({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(aktarmaProvider);

    return CamSayfa(
      baslik: 'Toplu Aktarma',
      cocuklar: [
        _TurSecimi(durum: d),
        const SizedBox(height: T.s4),
        _Adim(durum: d),
        const SizedBox(height: T.s4),
        const _Gecmis(),
        const SonBosluk(),
      ],
    );
  }
}

class _TurSecimi extends ConsumerWidget {
  const _TurSecimi({required this.durum});
  final AktarmaDurumu durum;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final secili = _turler.firstWhere((t) => t.$1 == durum.tur);
    return Bolum(
      key: K.aktarmaTur,
      baslik: 'Ne aktarılıyor?',
      altBaslik: secili.$3,
      child: Padding(
        padding: const EdgeInsets.all(T.s4),
        child: Wrap(spacing: T.s2, runSpacing: T.s2, children: [
          for (final t in _turler)
            ChoiceChip(
              label: Text(t.$2),
              selected: durum.tur == t.$1,
              onSelected: durum.adim is Uygulaniyor
                  ? null
                  : (v) { if (v) ref.read(aktarmaProvider.notifier).turSec(t.$1); },
            ),
        ]),
      ),
    );
  }
}

class _Adim extends ConsumerWidget {
  const _Adim({required this.durum});
  final AktarmaDurumu durum;

  @override
  Widget build(BuildContext context, WidgetRef ref) => switch (durum.adim) {
        DosyaSecimi a => _DosyaAdimi(hata: a.hata),
        SutunEslemesi a => _EslesmeAdimi(adim: a, durum: durum),
        Uygulaniyor a => _IlerlemeAdimi(adim: a),
        Onizleme a => _OnizlemeAdimi(adim: a, durum: durum),
        Sonuclandi a => _SonucAdimi(adim: a, durum: durum),
        AktarmaHatasi a => Bolum(
            baslik: 'Aktarma başarısız',
            child: Padding(
              padding: const EdgeInsets.all(T.s4),
              child: Column(children: [
                Bildirim(a.mesaj, tip: BildirimTip.hata),
                const SizedBox(height: T.s3),
                OutlinedButton(
                  key: K.aktarmaYeniden,
                  onPressed: () => ref.read(aktarmaProvider.notifier).sifirla(),
                  child: const Text('Baştan başla'),
                ),
              ]),
            ),
          ),
      };
}

class _DosyaAdimi extends ConsumerWidget {
  const _DosyaAdimi({this.hata});
  final String? hata;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Bolum(
        baslik: '1 · Dosya seç',
        altBaslik: '.xlsx · .csv — ilk satır sütun başlıkları olmalı',
        child: Padding(
          padding: const EdgeInsets.all(T.s4),
          child: Column(children: [
            if (hata != null) ...[
              Bildirim(hata!, tip: BildirimTip.hata),
              const SizedBox(height: T.s3),
            ],
            FilledButton.icon(
              key: K.aktarmaDosyaSec,
              onPressed: () => ref.read(aktarmaProvider.notifier).dosyaSec(),
              icon: const Icon(Icons.upload_file, size: 18),
              label: const Text('Dosya seç'),
            ),
            const SizedBox(height: T.s3),
            const Bildirim(
              'Aynı dosyayı ikinci kez yüklemek katalogu ikiye katlamaz — '
              'anahtar eşleşen satırlar güncellenir. Yükleme sonrası her şey '
              'tek tıkla geri alınabilir.',
              tip: BildirimTip.bilgi),
          ]),
        ),
      );
}

class _EslesmeAdimi extends ConsumerWidget {
  const _EslesmeAdimi({required this.adim, required this.durum});
  final SutunEslemesi adim;
  final AktarmaDurumu durum;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.read(aktarmaProvider.notifier);
    final alanlar = SutunTahmini.turAlanlari[durum.tur] ?? const <String>[];
    final anahtarVar = adim.anahtarVar(durum.tur);

    return Bolum(
      key: K.aktarmaEslesme,
      baslik: '2 · Sütunları eşle',
      altBaslik: '${durum.dosyaAdi ?? ''} · '
          '${Fmt.adet(adim.veri.satirSayisi)} satır · '
          '${adim.eslesme.length}/${adim.veri.basliklar.length} sütun eşlendi',
      eylem: TextButton(
        onPressed: () => n.sifirla(),
        child: const Text('Başka dosya'),
      ),
      child: Column(children: [
        // Eşleme satırı DİKEY. Açılır liste 190 piksellik bir kutuya
        // sıkıştırılmıştı ve telefonda hem sütun adı hem örnek değer
        // kırpılıyordu — oysa eşlemeyi doğru yapmak için ikisini de görmek
        // gerekiyor.
        for (final b in adim.veri.basliklar.where((x) => x.isNotEmpty))
          Padding(
            key: K.aktarmaSutun(b),
            padding: const EdgeInsets.fromLTRB(T.s4, T.s3, T.s4, T.s2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(b, style: Theme.of(context).textTheme.titleMedium),
                if (adim.veri.satirlar.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2, bottom: T.s2),
                    child: Mono(_ornek(b), size: 11),
                  )
                else
                  const SizedBox(height: T.s2),
                DropdownButtonFormField<String>(
                  initialValue: adim.eslesme[b],
                  isExpanded: true,
                  decoration: const InputDecoration(isDense: true),
                  hint: const Text('— kullanma —'),
                  items: [
                    const DropdownMenuItem(
                        value: '', child: Text('— kullanma —')),
                    for (final a in alanlar)
                      DropdownMenuItem(value: a, child: Text(_alanAdi(a))),
                  ],
                  onChanged: (v) => n.eslesmeAyarla(b, v),
                ),
              ],
            ),
          ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(T.s4),
          child: Column(children: [
            if (!anahtarVar)
              Padding(
                padding: const EdgeInsets.only(bottom: T.s3),
                child: Bildirim(adim.anahtarUyarisi(durum.tur),
                    tip: BildirimTip.uyari, key: K.aktarmaAnahtarUyari),
              ),
            _PolitikaSecimi(durum: durum),
            const SizedBox(height: T.s3),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.icon(
                key: K.aktarmaOnizle,
                onPressed: anahtarVar ? n.onizle : null,
                icon: const Icon(Icons.visibility_outlined, size: 18),
                label: const Text('Önizle'),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  String _ornek(String baslik) {
    final i = adim.veri.basliklar.indexOf(baslik);
    for (final s in adim.veri.satirlar.take(5)) {
      if (i >= 0 && i < s.length && s[i].isNotEmpty) return 'örn: ${s[i]}';
    }
    return 'boş';
  }
}

class _PolitikaSecimi extends ConsumerWidget {
  const _PolitikaSecimi({required this.durum});
  final AktarmaDurumu durum;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const MikroEtiket('Anahtar eşleşirse'),
          const SizedBox(height: T.s2),
          SegmentedButton<String>(
            key: K.aktarmaPolitika,
            segments: const [
              ButtonSegment(value: 'guncelle', label: Text('Güncelle')),
              ButtonSegment(value: 'atla', label: Text('Atla')),
              ButtonSegment(value: 'hata', label: Text('Hata ver')),
            ],
            selected: {durum.politika},
            onSelectionChanged: (v) =>
                ref.read(aktarmaProvider.notifier).politikaSec(v.first),
          ),
        ],
      );
}

class _IlerlemeAdimi extends StatelessWidget {
  const _IlerlemeAdimi({required this.adim});
  final Uygulaniyor adim;

  @override
  Widget build(BuildContext context) => Bolum(
        baslik: 'İşleniyor',
        altBaslik: '${Fmt.adet(adim.islenen)} / ${Fmt.adet(adim.toplam)} satır',
        child: Padding(
          padding: const EdgeInsets.all(T.s4),
          child: LinearProgressIndicator(
              value: adim.oran == 0 ? null : adim.oran),
        ),
      );
}

class _OnizlemeAdimi extends ConsumerWidget {
  const _OnizlemeAdimi({required this.adim, required this.durum});
  final Onizleme adim;
  final AktarmaDurumu durum;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.read(aktarmaProvider.notifier);
    final o = adim.ozet;
    final s = Theme.of(context).colorScheme;

    return Bolum(
      key: K.aktarmaOzet,
      baslik: '3 · Önizleme',
      altBaslik: 'Bu bir deneme koşusudur — henüz hiçbir şey yazılmadı',
      eylem: TextButton(
          onPressed: n.eslemeyeDon, child: const Text('Eşlemeye dön')),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(T.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SayiBloku(
                etiket: 'Dosyadaki satır',
                deger: Fmt.adet(o.toplam),
                altBilgi: o.hatali > 0
                    ? '${Fmt.adet(o.hatali)} satır hatalı — atlanacak'
                    : 'Hepsi okunabildi',
                altBilgiRengi: o.hatali > 0 ? s.error : null,
              ),
              const SizedBox(height: T.s3),
              // Dört rozet yerine tek çizgi: "ne kadarı yeni, ne kadarı
              // güncelleme" sorusu 24 bin satırlık bir dosyada sayıları
              // okuyarak değil oranı görerek cevaplanıyor.
              OranSeridi([
                ('Yeni', o.yeni.toDouble(), s.basarili),
                ('Güncelleme', o.guncelleme.toDouble(), s.bilgi),
                ('Atlanan', o.atlanan.toDouble(), s.onSurfaceVariant),
                ('Hatalı', o.hatali.toDouble(), s.error),
              ]),
            ],
          ),
        ),
        if (o.hatalar.isNotEmpty) _HataListesi(hatalar: o.hatalar),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(T.s4),
          child: Row(children: [
            if (o.hatali > 0)
              Expanded(
                child: Text(
                  'Hatalı satırlar atlanacak, gerisi yazılacak.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              )
            else
              const Spacer(),
            const SizedBox(width: T.s3),
            FilledButton.icon(
              key: K.aktarmaUygula,
              onPressed: (o.yeni + o.guncelleme) == 0 ? null : n.uygula,
              icon: const Icon(Icons.check, size: 18),
              label: Text('${Fmt.adet(o.yeni + o.guncelleme)} satırı uygula'),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _HataListesi extends StatelessWidget {
  const _HataListesi({required this.hatalar});
  final List<SatirHatasi> hatalar;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Container(
      key: K.aktarmaHatalar,
      constraints: const BoxConstraints(maxHeight: 240),
      color: s.surfaceContainerHigh,
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: hatalar.length,
        separatorBuilder: (_, _) => Divider(height: 1, color: s.outlineVariant),
        itemBuilder: (_, i) {
          final h = hatalar[i];
          // Satır numarası ÖNDE: kullanıcı hatayı dosyada bulup düzeltecek,
          // "hangi satır" sorusu en önce cevaplanmalı.
          return KayitSatiri(
            baslik: h.sebep,
            altBilgi: h.deger.isEmpty ? null : h.deger,
            oncul: SizedBox(
              width: 34,
              child: Center(
                child: Mono('${h.satir}',
                    size: 12, weight: FontWeight.w600, color: s.error),
              ),
            ),
            durumRengi: s.error,
          );
        },
      ),
    );
  }
}

class _SonucAdimi extends ConsumerWidget {
  const _SonucAdimi({required this.adim, required this.durum});
  final Sonuclandi adim;
  final AktarmaDurumu durum;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = adim.ozet;
    return Bolum(
      key: K.aktarmaOzet,
      baslik: '4 · Tamamlandı',
      altBaslik: o.ozet,
      child: Padding(
        padding: const EdgeInsets.all(T.s4),
        child: Column(children: [
          Bildirim(
              o.temiz
                  ? '${Fmt.adet(o.yeni + o.guncelleme)} satır işlendi.'
                  : '${Fmt.adet(o.yeni + o.guncelleme)} satır işlendi, '
                    '${Fmt.adet(o.hatali)} satır atlandı. '
                    'Hatalı satırları indirip düzelttikten sonra tekrar yükleyebilirsin.',
              tip: o.temiz ? BildirimTip.basari : BildirimTip.uyari),
          const SizedBox(height: T.s3),
          Wrap(spacing: T.s2, runSpacing: T.s2, children: [
            if (o.hatali > 0)
              OutlinedButton.icon(
                key: K.aktarmaHataIndir,
                onPressed: () => _hataRaporu(context, ref, adim.batchId),
                icon: const Icon(Icons.download, size: 16),
                label: const Text('Hatalı satırları indir'),
              ),
            FilledButton(
              key: K.aktarmaYeniden,
              onPressed: () {
                ref.read(aktarmaProvider.notifier).sifirla();
                ref.invalidate(aktarmaGecmisiProvider);
              },
              child: const Text('Yeni aktarma'),
            ),
          ]),
        ]),
      ),
    );
  }

  Future<void> _hataRaporu(
      BuildContext c, WidgetRef ref, String batchId) async {
    final liste = await ref.read(aktarmaRepositoryProvider).hatalar(batchId);
    final veri = TabloOkuyucu.yaz(
      const ['Satır', 'Hata'],
      [for (final h in liste) ['${h.satir}', h.hata]],
      sayfa: 'Hatalar',
    );
    final yer = await dosyaIndir(veri, 'aktarma-hatalari.xlsx');
    if (c.mounted) {
      ScaffoldMessenger.of(c)
          .showSnackBar(SnackBar(content: Text('İndirildi: $yer')));
    }
  }
}

class _Gecmis extends ConsumerWidget {
  const _Gecmis();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gecmis = ref.watch(aktarmaGecmisiProvider);
    final s = Theme.of(context).colorScheme;

    return Bolum(
      key: K.aktarmaGecmis,
      baslik: 'Geçmiş yüklemeler',
      altBaslik: 'Her aktarma bir olay kaydıdır — tek tıkla geri alınabilir',
      child: gecmis.when(
        loading: () => const IskeletListe(satir: 3, ikon: false),
        error: (e, _) => Padding(
            padding: const EdgeInsets.all(T.s4),
            child: Bildirim(e.toString(), tip: BildirimTip.hata)),
        data: (liste) => liste.isEmpty
            ? const BosDurum('Henüz yükleme yok',
                ikon: Icons.upload_file_outlined,
                aciklama: 'Her aktarma bir kayıt bırakır; buradan tek '
                    'tıkla geri alınabilir.')
            : Column(children: [
                for (final k in liste)
                  KayitSatiri(
                    baslik: '${k.turAdi} · ${k.dosyaAdi ?? '—'}',
                    altBilgi: [
                      Fmt.tarihSaat(k.createdAt),
                      if (k.eklenen > 0) '${Fmt.adet(k.eklenen)} yeni',
                      if (k.guncellenen > 0)
                        '${Fmt.adet(k.guncellenen)} güncelleme',
                      if (k.hatali > 0) '${Fmt.adet(k.hatali)} hatalı',
                      ?k.yapan,
                    ].join(' · '),
                    vurgu: k.geriAlindi
                        ? 'Geri alındı'
                        : (k.geriAlinabilir
                            ? null
                            : 'Yarım kaldı — geri alınamaz'),
                    vurguRengi: k.geriAlindi ? s.onSurfaceVariant : s.uyari,
                    ikon: Icons.upload_file_outlined,
                    durumRengi: k.geriAlindi
                        ? s.onSurfaceVariant
                        : (k.hatali > 0 ? s.uyari : s.basarili),
                    sondaki: k.geriAlindi || !k.geriAlinabilir
                        ? null
                        : TextButton(
                            key: K.aktarmaGeriAl(k.id),
                            onPressed: () => _geriAl(context, ref, k),
                            child: const Text('Geri al')),
                  ),
              ]),
      ),
    );
  }

  Future<void> _geriAl(BuildContext c, WidgetRef ref, AktarmaKaydi k) async {
    final ok = await showDialog<bool>(
      context: c,
      builder: (_) => Diyalog(
        baslik: 'Aktarma geri alınsın mı?',
        altBaslik: '${k.turAdi} · ${k.dosyaAdi ?? ''}',
        genislik: 400,
        onayEtiketi: 'Geri al',
        onVazgec: () => Navigator.pop(c),
        onOnay: () => Navigator.pop(c, true),
        children: [
          // K49 · her aktarma bir olay kaydıdır; geri alma da öyle. Kaç
          // kaydın etkileneceği ÖNCEDEN sayıyla yazılı.
          Bildirim(
              'Bu yüklemeyle eklenen ${Fmt.adet(k.eklenen)} kayıt silinir, '
              'güncellenen ${Fmt.adet(k.guncellenen)} kayıt eski hâline '
              'döner.',
              tip: BildirimTip.uyari),
        ],
      ),
    );
    if (ok != true) return;
    final r = await ref.read(aktarmaRepositoryProvider).geriAl(k.id);
    ref.invalidate(aktarmaGecmisiProvider);
    if (c.mounted) {
      ScaffoldMessenger.of(c).showSnackBar(SnackBar(
          content: Text('${r.silinen} kayıt silindi, '
              '${r.geriAlinan} kayıt eski hâline döndü')));
    }
  }
}

String _alanAdi(String a) => switch (a) {
      'ad' => 'Ad',
      'barkod' => 'Barkod',
      'urun_kod' => 'Ürün kodu',
      'yayinevi' => 'Yayınevi',
      'kategori' => 'Kategori',
      'ders' => 'Ders',
      'sinif' => 'Sınıf',
      'sinav_tipi' => 'Sınav tipi',
      'etiket_fiyat' => 'Etiket fiyatı',
      'baski_etiketi' => 'Baskı',
      'katalog' => 'Katalog (kitap/deneme)',
      'satis_fiyat' => 'Satış fiyatı',
      'alis_fiyat' => 'Alış fiyatı',
      'varsayilan_iskonto' => 'Varsayılan iskonto',
      'stok_adedi' => 'Stok adedi',
      'meb_kodu' => 'MEB kodu',
      'il' => 'İl',
      'ilce' => 'İlçe',
      'kurum_tipi' => 'Kurum tipi',
      'kademe' => 'Kademe',
      'tur' => 'Tür',
      'ogrenci_sayisi' => 'Öğrenci sayısı',
      _ => a,
    };
