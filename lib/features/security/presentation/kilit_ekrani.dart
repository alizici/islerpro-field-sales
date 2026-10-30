import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/security/kilit_politikasi.dart';
import '../../../core/security/oturum_kilidi.dart';
import '../../../core/test_keys.dart';
import '../../../core/theme/tokens.dart';
import '../../../shared/widgets/cam.dart';
import '../../../shared/widgets/dokunus.dart';

/// K42 · Kilit kapısı — uygulamanın TAMAMINI örter.
///
/// `MaterialApp.builder` içinde durduğu için Navigator'ın üstündedir: açık bir
/// diyalog ya da alt panel varken bile kilit onların önüne geçer. Ekranın
/// altına yerleştirilseydi, arka planda kalan bir sipariş listesi kilitliyken
/// de okunabilirdi.
class KilitKapisiWidget extends ConsumerStatefulWidget {
  const KilitKapisiWidget({required this.child, super.key});
  final Widget child;

  @override
  ConsumerState<KilitKapisiWidget> createState() => _KilitKapisiState();
}

class _KilitKapisiState extends ConsumerState<KilitKapisiWidget>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // İlk denetimi `KilitN.build()` kendisi yapıyor; burada tekrarlanmıyor.
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState durum) {
    final n = ref.read(kilitProvider.notifier);
    switch (durum) {
      // `inactive` de sayılır: iOS'ta uygulama değiştirici açıldığında ekran
      // görüntüsü alınır ve uygulama henüz `paused` olmamıştır.
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        n.arkaPlanaGecti();
      case AppLifecycleState.resumed:
        n.oneGeldi();
    }
  }

  @override
  Widget build(BuildContext context) {
    final k = ref.watch(kilitProvider);
    return Stack(children: [
      widget.child,
      if (k.kilitli) const Positioned.fill(child: _Kilit()),
    ]);
  }
}

class _Kilit extends ConsumerStatefulWidget {
  const _Kilit();
  @override
  ConsumerState<_Kilit> createState() => _KilitState();
}

class _KilitState extends ConsumerState<_Kilit> {
  bool _deniyor = false;
  bool _basarisiz = false;

  @override
  void initState() {
    super.initState();
    // Kilit görünür görünmez sor: kullanıcı bir düğmeye daha basmak zorunda
    // kalmasın.
    WidgetsBinding.instance.addPostFrameCallback((_) => _dogrula());
  }

  Future<void> _dogrula() async {
    if (_deniyor) return;
    setState(() { _deniyor = true; _basarisiz = false; });
    final oldu = await ref.read(kilitProvider.notifier).ac();
    if (!mounted) return;
    setState(() { _deniyor = false; _basarisiz = !oldu; });
  }

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Material(
      key: K.kilitEkrani,
      color: Colors.transparent,
      child: CamZemin(
        child: Center(
        child: Padding(
          padding: const EdgeInsets.all(T.s5),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 52, height: 52, alignment: Alignment.center,
              decoration: BoxDecoration(
                color: T.bordo,
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(
                    color: T.bordo.withValues(alpha: 0.28),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(Icons.lock_outline,
                  color: Colors.white, size: 26),
            ),
            const SizedBox(height: T.s4),
            Text('İşlerPro kilitli',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: T.s2),
            Text(
                'Uygulama ${KilitPolitikasi.arkaPlan.inMinutes} dakikadan uzun '
                'süre arka planda kaldı. Devam etmek için kimliğinizi '
                'doğrulayın.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: T.s5),
            if (_deniyor)
              const Bekleme(boy: 22)
            else
              FilledButton.icon(
                key: K.kilitAc,
                onPressed: _dogrula,
                icon: const Icon(Icons.fingerprint, size: 18),
                label: const Text('Kilidi aç'),
              ),
            if (_basarisiz)
              Padding(
                padding: const EdgeInsets.only(top: T.s3),
                child: Text('Doğrulanamadı. Tekrar deneyin.',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: s.error)),
              ),
          ]),
          ),
        ),
      ),
    );
  }
}
