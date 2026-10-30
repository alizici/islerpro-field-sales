import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session.dart';
import '../../../core/security/kilit_politikasi.dart';
import '../../../core/security/oturum_kilidi.dart';
import '../../../core/test_keys.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/local/sifreleme.dart';
import '../../../data/local/yerel_db.dart';
import '../../../data/repositories/senkron_repository.dart';
import '../../../data/services/yerel_referans.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/widgets/cam.dart';
import '../../../shared/widgets/dokunus.dart';
import '../../../shared/widgets/bolum.dart';
import '../../../shared/widgets/diyalog.dart';
import '../../../shared/widgets/form_kabuk.dart';
import '../../../shared/widgets/liste.dart';
import '../../../shared/widgets/satir.dart';
import 'senkron_durumu.dart';

const _fnAdi = <String, String>{
  'start_visit': 'Ziyaret açma',
  'end_visit': 'Ziyaret kapama',
  'plan_visit': 'Rota durağı',
  'create_request': 'Talep',
  'submit_request': 'Talep gönderme',
  'create_shipment': 'Teslimat',
  'create_payment': 'Tahsilat',
};

/// K43 · Senkron ekranı.
///
/// Buranın tek işi kuyruğu GÖRÜNÜR kılmak. Sözleşmenin dördüncü kuralı
/// "başarısız kayıt sessizce kaybolmaz" diyor; sessizce kaybolmamanın tek
/// yolu kullanıcının onu bir yerde görmesi.
class SenkronEkrani extends ConsumerWidget {
  const SenkronEkrani({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final durum = ref.watch(senkronProvider);
    final oturum = ref.watch(sessionProvider);
    final yonetici = oturum?.aktifRol == AppRole.isletmeSahibi ||
        oturum?.aktifRol == AppRole.dukkanMuduru;

    return CamSayfa(
      baslik: 'Senkron',
      cocuklar: [
          if (kIsWeb)
            const Padding(
              padding: EdgeInsets.only(bottom: T.s3),
              child: Bildirim(
                  'Tarayıcıda çevrimdışı kuyruk yoktur — kayıtlar doğrudan '
                  'sunucuya yazılır.',
                  tip: BildirimTip.bilgi),
            ),
          _Durum(durum: durum),
          const SizedBox(height: T.s3),
          const _Kuyruk(),
          const SizedBox(height: T.s3),
          const _Guvenlik(),
          if (yonetici) ...[
            const SizedBox(height: T.s3),
            const CihazlarBolumu(),
          ],
          const SonBosluk(),
      ],
    );
  }
}

class _Durum extends ConsumerWidget {
  const _Durum({required this.durum});
  final SenkronDurum durum;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = Theme.of(context).colorScheme;
    final bekleyen = ref.watch(bekleyenSayisiProvider).value ?? 0;
    final r = durum.rapor;

    return Bolum(
      key: K.senkronDurum,
      baslik: 'Durum',
      altBaslik: durum.sonZaman == null
          ? 'Bu oturumda henüz eşitlenmedi'
          : 'Son eşitleme ${Fmt.tarihSaat(durum.sonZaman)}',
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(T.s4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: SayiBloku(
                etiket: 'Bekleyen kayıt',
                deger: '$bekleyen',
                renk: bekleyen > 0 ? s.uyari : s.basarili,
                altBilgi: bekleyen > 0
                    ? 'Sunucuya yüklenmeyi bekliyor'
                    : 'Her şey yüklendi',
              ),
            ),
            FilledButton.icon(
              key: K.senkronCalistir,
              onPressed: durum.calisiyor || kIsWeb
                  ? null
                  : () => ref.read(senkronProvider.notifier).calistir(),
              icon: durum.calisiyor
                  ? const Bekleme(boy: 16)
                  : const Icon(Icons.sync, size: 18),
              label: Text(durum.calisiyor ? 'Eşitleniyor' : 'Şimdi eşitle'),
            ),
          ]),
        ),
        if (durum.hata != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(T.s4, 0, T.s4, T.s4),
            child: Bildirim(durum.hata!, tip: BildirimTip.hata),
          ),
        if (r != null && durum.hata == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(T.s4, 0, T.s4, T.s4),
            child: Bildirim(r.ozet,
                tip: r.sorunVar ? BildirimTip.uyari : BildirimTip.basari),
          ),
        // K43 · kural 4: rapor sunucu saatini kullanır, cihazınki sapabilir.
        if (r?.sunucuSaati != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(T.s4, 0, T.s4, T.s4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                  'Sunucu saati ${Fmt.tarihSaat(r!.sunucuSaati)} — '
                  'raporlar bu saati kullanır',
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          ),
      ]),
    );
  }
}

class _Kuyruk extends ConsumerWidget {
  const _Kuyruk();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final k = ref.watch(kuyrukProvider);
    final s = Theme.of(context).colorScheme;

    return Bolum(
      key: K.senkronKuyruk,
      baslik: 'Bekleyen kayıtlar',
      altBaslik: 'Kuyruk kalıcıdır — uygulama kapansa da kaybolmaz',
      child: k.when(
        loading: () => const IskeletListe(satir: 3),
        error: (e, _) => Padding(
            padding: const EdgeInsets.all(T.s4),
            child: Bildirim(e.toString(), tip: BildirimTip.hata)),
        data: (l) => l.isEmpty
            ? const BosDurum('Yüklenmeyi bekleyen kayıt yok',
                ikon: Icons.cloud_done_outlined,
                aciklama: 'Sahada açılan her kayıt önce cihazda kuyruğa '
                    'girer; kuyruk boşsa hepsi sunucuda.')
            : Column(children: [
                for (final q in l) _KuyrukSatiri(q: q, renk: s),
              ]),
      ),
    );
  }
}

class _KuyrukSatiri extends ConsumerWidget {
  const _KuyrukSatiri({required this.q, required this.renk});
  final KuyrukData q;
  final ColorScheme renk;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hataliMi = q.durum == 'hata';
    // K43 · kural 4: başarısız kayıt SESSİZCE KAYBOLMAZ. Hatanın kendisi
    // satırın vurgusunda; kullanıcı ne olduğunu okumak için dokunmak
    // zorunda kalmıyor.
    return KayitSatiri(
      key: K.senkronSatir(q.localSeq),
      baslik: q.ozet,
      altBilgi: '${_fnAdi[q.fn] ?? q.fn} · ${Fmt.tarihSaat(q.olusturmaLocal)}',
      vurgu: hataliMi ? q.hata : null,
      vurguRengi: renk.error,
      ikon: hataliMi ? Icons.error_outline : Icons.schedule,
      durumRengi: hataliMi ? renk.error : renk.onSurfaceVariant,
      sondaki: hataliMi
          ? IconButton(
              key: K.senkronSil(q.localSeq),
              tooltip: 'Kuyruktan sil',
              onPressed: () async {
                final db = ref.read(yerelDbProvider);
                await db?.kuyruktanSil(q.localSeq);
                ref.invalidate(kuyrukProvider);
                ref.invalidate(bekleyenSayisiProvider);
              },
              icon: const Icon(Icons.delete_outline, size: 20),
            )
          : null,
    );
  }
}

/// K42 · Cihaz kayıtları sahibe görünür; iptal edilen cihaz ilk bağlanışında
/// yerel veriyi siler.
class CihazlarBolumu extends ConsumerWidget {
  const CihazlarBolumu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(cihazlarProvider);
    final s = Theme.of(context).colorScheme;

    return Bolum(
      key: K.senkronCihazlar,
      baslik: 'Cihazlar',
      altBaslik: 'İptal edilen cihaz ilk bağlanışında yerel veriyi siler',
      child: c.when(
        loading: () => const IskeletListe(satir: 3),
        error: (e, _) => Padding(
            padding: const EdgeInsets.all(T.s4),
            child: Bildirim(e.toString(), tip: BildirimTip.hata)),
        data: (l) => l.isEmpty
            ? const BosDurum('Kayıtlı cihaz yok',
                ikon: Icons.devices_outlined,
                aciklama: 'Ekip uygulamaya girdikçe cihazları burada '
                    'listelenir.')
            : Column(children: [
                for (final d in l)
                  KayitSatiri(
                    key: K.senkronCihaz(d.id),
                    baslik: d.adSoyad,
                    altBilgi: [
                      d.cihaz,
                      if (d.surum != null) 'v${d.surum}',
                      d.gun == 0 ? 'bugün görüldü' : '${d.gun} gün önce',
                    ].join(' · '),
                    // K42 · iptal edilen cihaz ilk bağlanışında yerel veriyi
                    // siler; bu bir bayrak değil, olacak olan şey.
                    vurgu: d.iptal
                        ? 'İptal edildi — ilk bağlanışında yerel verisi silinir'
                        : null,
                    vurguRengi: s.error,
                    ikon: d.iptal ? Icons.phonelink_erase : Icons.smartphone,
                    durumRengi: d.iptal ? s.error : s.basarili,
                    sondaki: d.iptal
                        ? null
                        : IconButton(
                            key: K.senkronCihazIptal(d.id),
                            tooltip: 'Cihazı iptal et',
                            onPressed: () => _iptalSor(context, ref, d),
                            icon: const Icon(Icons.block, size: 18),
                          ),
                  ),
              ]),
      ),
    );
  }

  Future<void> _iptalSor(
      BuildContext context, WidgetRef ref, CihazSatiri d) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (_) => Diyalog(
        baslik: 'Cihazı iptal et',
        altBaslik: '${d.adSoyad} · ${d.cihaz}',
        genislik: 400,
        onayEtiketi: 'İptal et',
        onayKey: K.senkronCihazIptalOnay,
        onVazgec: () => Navigator.pop(context, false),
        onOnay: () => Navigator.pop(context, true),
        children: const [
          // K42 · geri alınamaz bir işlem: NE KAYBEDİLECEĞİ önceden yazılı.
          Bildirim(
              'Bu cihaz bir daha kayıt yükleyemez ve ilk bağlanışında '
              'üzerindeki yerel veri silinir. Henüz yüklenmemiş kayıtları '
              'varsa onlar da kaybolur.',
              tip: BildirimTip.uyari),
        ],
      ),
    );
    if (onay != true) return;
    await ref.read(senkronRepositoryProvider).cihazIptal(d.id);
    ref.invalidate(cihazlarProvider);
  }
}

/// K42 · Cihaz güvenliği. Ölçülen değerler; bayrak değil.
class _Guvenlik extends ConsumerWidget {
  const _Guvenlik();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = Theme.of(context).colorScheme;
    final sifre = ref.watch(guvenlikDurumuProvider).value;
    final kilit = ref.watch(kilitProvider);

    final (String sifreMetin, Color? sifreRenk) = switch (sifre) {
      SifrelemeDurumu.sifreli => ('Şifreli', s.basarili),
      SifrelemeDurumu.sifresiz => ('ŞİFRESİZ', s.error),
      _ => ('Yerel veri yok', null),
    };

    return Bolum(
      key: K.senkronGuvenlik,
      baslik: 'Cihaz güvenliği',
      altBaslik: 'Yerel kopyada cari adı, bakiye ve telefon durur (K44)',
      child: Column(children: [
        const _YerelKopya(),
        KayitSatiri(
          baslik: 'Yerel veri',
          altBilgi: 'Anahtar cihazın kasasında; uygulama onu hiçbir yere '
              'göndermez',
          vurgu: sifreMetin,
          vurguRengi: sifreRenk,
          ikon: sifre == SifrelemeDurumu.sifresiz
              ? Icons.lock_open_outlined
              : Icons.lock_outline,
          durumRengi: sifreRenk,
        ),
        KayitSatiri(
          baslik: 'Otomatik kilit',
          // Ölçüm bitmeden hüküm verilmez: "Açık" demek için önce cihaza
          // sormak gerekir.
          altBilgi: !kilit.hazir
              ? 'Cihaz denetleniyor…'
              : kilit.cihazDestekliyor
                  ? 'Arka planda ${KilitPolitikasi.arkaPlan.inMinutes} dk sonra '
                      'biyometri/PIN · '
                      '${KilitPolitikasi.hareketsizlik.inDays} gün '
                      'hareketsizlikte oturum kapanır'
                  : 'Cihazda ekran kilidi yok'
              ,
          vurgu: !kilit.hazir
              ? null
              : kilit.cihazDestekliyor
                  ? 'Açık'
                  : 'Kapalı — otomatik kilit ÇALIŞMIYOR',
          vurguRengi: kilit.cihazDestekliyor ? s.basarili : s.uyari,
          ikon: Icons.fingerprint,
          durumRengi: !kilit.hazir
              ? s.onSurfaceVariant
              : (kilit.cihazDestekliyor ? s.basarili : s.uyari),
        ),
      ]),
    );
  }
}

/// K42 · Cihazda ne durduğunu SÖYLEMEK yetmez, saymak gerekir.
///
/// Sahip bir cihazı iptal edip etmeyeceğine karar verirken "cari adı ve bakiye
/// durur" cümlesine değil, ölçülmüş sayıya bakmalı — bölümün geri kalanı da
/// bu ilkeyle yazıldı.
class _YerelKopya extends ConsumerWidget {
  const _YerelKopya();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sayi = ref.watch(yerelKopyaSayilariProvider).value;
    if (sayi == null) {
      return const KayitSatiri(
        baslik: 'Cihazdaki kopya',
        altBilgi: 'Sayılıyor…',
        ikon: Icons.inventory_2_outlined,
      );
    }
    final s = Theme.of(context).colorScheme;
    return KayitSatiri(
      key: K.senkronYerelKopya,
      baslik: 'Cihazdaki kopya',
      altBilgi: sayi.bos
          ? 'Boş — henüz eşitlenmedi'
          : [
              '${Fmt.adet(sayi.cari)} cari',
              '${Fmt.adet(sayi.kurum)} kurum',
              '${Fmt.adet(sayi.kisi)} kişi',
              '${Fmt.adet(sayi.urun)} ürün',
              if (sayi.tarih != null) Fmt.tarihSaat(sayi.tarih),
            ].join(' · '),
      ikon: Icons.inventory_2_outlined,
      durumRengi: sayi.bos ? s.onSurfaceVariant : s.bilgi,
    );
  }
}
