import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/test_keys.dart';
import '../../../data/repositories/org_repository.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/widgets/cam.dart';
import '../../../shared/widgets/bolum.dart';
import '../../../shared/widgets/diyalog.dart';
import '../../../shared/widgets/liste.dart';
import '../../../shared/widgets/satir.dart';
import '../../../shared/widgets/form_kabuk.dart';
import 'davet_diyalogu.dart';
import 'dukkan_diyalogu.dart';
import 'devir_diyalogu.dart';

final _dukkanlarProvider = FutureProvider.autoDispose(
    (ref) => ref.watch(orgRepositoryProvider).dukkanlar());
final _ekipProvider = FutureProvider.autoDispose(
    (ref) => ref.watch(orgRepositoryProvider).ekip());
final _donemlerProvider = FutureProvider.autoDispose(
    (ref) => ref.watch(orgRepositoryProvider).donemler());
final _bekleyenProvider = FutureProvider.autoDispose(
    (ref) => ref.watch(orgRepositoryProvider).bekleyenOgretmenler());

class AyarlarEkrani extends ConsumerWidget {
  const AyarlarEkrani({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final oturum = ref.watch(sessionProvider);
    if (oturum == null) return const SizedBox.shrink();
    final sahip = oturum.aktifRol == AppRole.isletmeSahibi;

    return CamSayfa(
      baslik: 'Ayarlar',
      eylemler: [
          IconButton(
            tooltip: 'Yenile',
            onPressed: () {
              ref.invalidate(_dukkanlarProvider);
              ref.invalidate(_ekipProvider);
              ref.invalidate(_donemlerProvider);
              ref.invalidate(_bekleyenProvider);
            },
          icon: const Icon(Icons.refresh, size: 20),
        ),
      ],
      cocuklar: [
          _Kimlik(oturum: oturum),
          const SizedBox(height: T.s3),
          if (sahip) ...[
            const _BekleyenOnaylar(),
            const SizedBox(height: T.s3),
          ],
          const _Dukkanlar(),
          const SizedBox(height: T.s3),
          const _Ekip(),
          const SizedBox(height: T.s3),
          const _Donemler(),
          const SizedBox(height: T.s5),
          OutlinedButton.icon(
            key: K.ayarlarCikis,
            onPressed: () => ref.read(sessionStateProvider.notifier).cikis(),
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('Çıkış yap'),
          ),
          const SonBosluk(),
      ],
    );
  }
}

class _Kimlik extends StatelessWidget {
  const _Kimlik({required this.oturum});
  final Session oturum;

  @override
  Widget build(BuildContext context) {
    final d = oturum.data;
    return Bolum(
      baslik: d.memberships.firstOrNull?.tenantUnvan ?? 'İşletme',
      altBaslik: '${d.adSoyad} · ${oturum.aktifRol.ad}',
      child: Padding(
        padding: const EdgeInsets.all(T.s4),
        child: Wrap(spacing: T.s2, runSpacing: T.s2, children: [
          if (oturum.store != null) Rozet(oturum.store!.ad),
          if (oturum.period != null)
            Rozet(oturum.period!.ad,
                renk: Theme.of(context).colorScheme.basarili),
          if (d.telefon != null) Rozet(d.telefon!),
          if (d.eposta != null) Rozet(d.eposta!),
        ]),
      ),
    );
  }
}

/// K3 · Onay bekleyen öğretmenler. Onaysız hesap katalog ve fiyat göremez.
class _BekleyenOnaylar extends ConsumerWidget {
  const _BekleyenOnaylar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bekleyen = ref.watch(_bekleyenProvider);
    final oturum = ref.watch(sessionProvider)!;
    return bekleyen.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => const SizedBox.shrink(),
      data: (liste) {
        if (liste.isEmpty) return const SizedBox.shrink();
        final s = Theme.of(context).colorScheme;
        return Bolum(
          key: K.ayarlarBekleyenler,
          baslik: 'Onay bekleyen öğretmenler',
          altBaslik: 'Onaylanana kadar katalog ve fiyat göremezler',
          eylem: Rozet('${liste.length}', renk: s.uyari, zemin: s.uyariSoft),
          child: Column(
            children: [
              for (final t in liste)
                KayitSatiri(
                  baslik: t.adSoyad,
                  altBilgi: [t.institutionAd, t.ilce, t.telefon]
                      .nonNulls
                      .where((e) => e.isNotEmpty)
                      .join(' · '),
                  // K3 · onaya kadar katalog ve fiyat göremez.
                  vurgu: 'Onay bekliyor — katalog ve fiyat göremiyor',
                  vurguRengi: s.uyari,
                  ikon: Icons.person_outline,
                  durumRengi: s.uyari,
                  sondaki: FilledButton(
                    onPressed: () async {
                      final kurumAdina = await showDialog<bool>(
                        context: context,
                        builder: (_) => const _OnayDiyalogu(),
                      );
                      if (kurumAdina == null) return;
                      await ref.read(orgRepositoryProvider).ogretmenOnayla(
                            userId: t.userId,
                            institutionId: t.institutionId,
                            storeId: oturum.storeId!,
                            kurumAdinaSiparis: kurumAdina,
                          );
                      ref.invalidate(_bekleyenProvider);
                    },
                    child: const Text('Onayla'),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Y-15 · Kurum adına sipariş yetkisi ayrı sorulur ve audit'e yazılır.
class _OnayDiyalogu extends StatefulWidget {
  const _OnayDiyalogu();
  @override
  State<_OnayDiyalogu> createState() => _OnayDiyaloguState();
}

class _OnayDiyaloguState extends State<_OnayDiyalogu> {
  bool _kurumAdina = false;
  @override
  Widget build(BuildContext context) => Diyalog(
        baslik: 'Öğretmeni onayla',
        genislik: 400,
        onayEtiketi: 'Onayla',
        onVazgec: () => Navigator.pop(context),
        onOnay: () => Navigator.pop(context, _kurumAdina),
        children: [
          // K3 · Y-15 · kurum adına sipariş AYRI bir haktır ve kim verdiği
          // kayda geçer.
          const Bildirim(
            'Onay anında öğretmene kendi carisi açılır. Kurum adına sipariş '
            'yetkisi ayrı bir haktır — kim verdiği kayda geçer.',
            tip: BildirimTip.bilgi),
          CheckboxListTile(
            key: K.onayKurumAdina,
            value: _kurumAdina,
            onChanged: (v) => setState(() => _kurumAdina = v ?? false),
            title: const Text('Kurum adına sipariş verebilir'),
            subtitle: const Text('Okulu/kurumu bağlayan talep açabilir'),
            contentPadding: EdgeInsets.zero,
          ),
        ],
      );
}

class _Dukkanlar extends ConsumerWidget {
  const _Dukkanlar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dukkanlar = ref.watch(_dukkanlarProvider);
    final oturum = ref.watch(sessionProvider)!;
    final sahip = oturum.aktifRol == AppRole.isletmeSahibi;
    final s = Theme.of(context).colorScheme;

    Future<void> diyalog({StoreRow? dukkan}) async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => DukkanDiyalogu(
            tenantId: oturum.tenantId!, dukkan: dukkan),
      );
      if (ok == true) {
        ref.invalidate(_dukkanlarProvider);
        // Ad değişmiş olabilir — oturumdaki dükkan adı da tazelenmeli.
        await ref.read(sessionStateProvider.notifier).yenile();
      }
    }

    return Bolum(
      key: K.ayarlarDukkanlar,
      baslik: 'Dükkanlar',
      altBaslik: 'Fiyat, iskonto ve stok dükkana özeldir (K12)',
      eylem: sahip
          ? TextButton.icon(
              key: K.ayarlarDukkanEkle,
              onPressed: diyalog,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Ekle'))
          : null,
      child: dukkanlar.when(
        loading: () => const _Yukleniyor(),
        error: (e, _) => _Hata(e),
        data: (liste) => liste.isEmpty
            ? const BosDurum('Henüz dükkan yok',
                ikon: Icons.storefront_outlined,
                aciklama: 'Dükkan, satışın yapıldığı şube. Stok, fiyat ve '
                    'ekip dükkana bağlıdır; en az bir tane olmalı.')
            : Column(children: [
                for (final d in liste)
                  KayitSatiri(
                    key: K.dukkanSatiri(d.id),
                    baslik: d.ad,
                    altBilgi: d.konum.isEmpty ? null : d.konum,
                    vurgu: !d.aktif
                        ? 'Pasif'
                        : (d.id == oturum.storeId ? 'Aktif dükkan' : null),
                    vurguRengi: d.aktif ? s.primary : s.onSurfaceVariant,
                    ikon: Icons.storefront_outlined,
                    durumRengi:
                        d.aktif ? s.primary : s.onSurfaceVariant,
                    sondaki: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (sahip)
                        PopupMenuButton<String>(
                          key: K.dukkanMenu(d.id),
                          icon: const Icon(Icons.more_vert, size: 18),
                          onSelected: (v) async {
                            switch (v) {
                              case 'duzenle':
                                await diyalog(dukkan: d);
                              case 'pasif':
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (_) => DukkanPasifDiyalogu(dukkan: d),
                                );
                                if (ok == true) {
                                  ref.invalidate(_dukkanlarProvider);
                                  await ref
                                      .read(sessionStateProvider.notifier)
                                      .yenile();
                                }
                              case 'aktif':
                                await ref.read(orgRepositoryProvider)
                                    .dukkanDurumu(d.id, true);
                                ref.invalidate(_dukkanlarProvider);
                                await ref
                                    .read(sessionStateProvider.notifier)
                                    .yenile();
                            }
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                                value: 'duzenle', child: Text('Düzenle')),
                            if (d.aktif)
                              const PopupMenuItem(
                                  value: 'pasif', child: Text('Pasife al'))
                            else
                              const PopupMenuItem(
                                  value: 'aktif', child: Text('Geri aç')),
                          ],
                        ),
                    ]),
                  ),
              ]),
      ),
    );
  }
}

class _Ekip extends ConsumerWidget {
  const _Ekip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ekip = ref.watch(_ekipProvider);
    final oturum = ref.watch(sessionProvider)!;
    final yetkili = oturum.aktifRol == AppRole.isletmeSahibi ||
        oturum.aktifRol == AppRole.dukkanMuduru;
    final s = Theme.of(context).colorScheme;

    return Bolum(
      key: K.ayarlarEkip,
      baslik: 'Ekip',
      altBaslik: 'Pazarlamacı, müdür ve hazırlık kullanıcıları',
      eylem: yetkili
          ? TextButton.icon(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => DavetDiyalogu(storeId: oturum.storeId!),
              ),
              icon: const Icon(Icons.person_add_alt, size: 16),
              label: const Text('Davet et'))
          : null,
      child: ekip.when(
        loading: () => const _Yukleniyor(),
        error: (e, _) => _Hata(e),
        data: (liste) => Column(children: [
          for (final u in liste)
            KayitSatiri(
              oncul: CircleAvatar(
                radius: 17,
                backgroundColor: u.aktif ? T.bordoSoft : s.surfaceContainerHigh,
                child: Text(_bas(u.adSoyad),
                    style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600,
                        color: u.aktif ? T.bordo : s.onSurfaceVariant)),
              ),
              baslik: u.adSoyad,
              altBilgi: [
                u.role?.ad ?? '—',
                if (u.storeAd != null) u.storeAd!,
                if (u.portfoy > 0) '${Fmt.adet(u.portfoy)} cari',
              ].join(' · '),
              vurgu: u.aktif ? null : 'Pasif',
              vurguRengi: s.onSurfaceVariant,
              durumRengi: u.aktif ? s.primary : s.onSurfaceVariant,
              sondaki: !u.aktif
                  ? null
                  : (yetkili && u.role != AppRole.isletmeSahibi
                      ? IconButton(
                          tooltip: 'Pasife al',
                          icon: const Icon(Icons.person_off_outlined, size: 18),
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (_) => DevirDiyalogu(
                                  uye: u,
                                  adaylar: liste
                                      .where((x) =>
                                          x.aktif &&
                                          x.userId != u.userId &&
                                          x.role == AppRole.pazarlamaci)
                                      .toList()),
                            );
                            if (ok == true) ref.invalidate(_ekipProvider);
                          },
                        )
                      : null),
            ),
        ]),
      ),
    );
  }

  static String _bas(String ad) {
    final p = ad.trim().split(RegExp(r'\s+'));
    return (p.length > 1 ? p.first[0] + p.last[0] : ad.characters.take(2).toString())
        .toUpperCase();
  }
}

class _Donemler extends ConsumerWidget {
  const _Donemler();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final donemler = ref.watch(_donemlerProvider);
    final oturum = ref.watch(sessionProvider)!;
    final sahip = oturum.aktifRol == AppRole.isletmeSahibi;
    final s = Theme.of(context).colorScheme;

    return Bolum(
      key: K.ayarlarDonemler,
      baslik: 'Dönemler',
      altBaslik: 'Yarıyıl · portföy dönem geçişinde otomatik kopyalanır',
      eylem: sahip
          ? TextButton.icon(
              onPressed: () async {
                final ad = await ref
                    .read(orgRepositoryProvider)
                    .sonrakiDonemiAc(oturum.tenantId!);
                ref.invalidate(_donemlerProvider);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('$ad açıldı')));
                }
              },
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Sonraki dönem'))
          : null,
      child: donemler.when(
        loading: () => const _Yukleniyor(),
        error: (e, _) => _Hata(e),
        data: (liste) => Column(children: [
          for (final d in liste)
            KayitSatiri(
              baslik: d.ad,
              altBilgi: '${Fmt.tarih(d.startsOn)} → ${Fmt.tarih(d.endsOn)}',
              // K8 · dönem kilidi: kapalı dönemde kayıt açılamaz.
              vurgu: switch (d.status) {
                'aktif' => 'Aktif dönem',
                'kapali' => 'Kapalı — yeni kayıt açılamaz',
                _ => 'Planlandı',
              },
              vurguRengi: switch (d.status) {
                'aktif' => s.basarili,
                'kapali' => s.onSurfaceVariant,
                _ => s.bilgi,
              },
              ikon: Icons.date_range_outlined,
              durumRengi: switch (d.status) {
                'aktif' => s.basarili,
                'kapali' => s.onSurfaceVariant,
                _ => s.bilgi,
              },
            ),
        ]),
      ),
    );
  }
}

class _Yukleniyor extends StatelessWidget {
  const _Yukleniyor();
  @override
  Widget build(BuildContext context) =>
      const IskeletListe(satir: 3);
}

class _Hata extends StatelessWidget {
  const _Hata(this.e);
  final Object e;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.all(T.s4),
      child: Bildirim(
          e.toString().replaceFirst(RegExp(r'^\w+Exception:?\s*'), ''),
          tip: BildirimTip.hata));
}
