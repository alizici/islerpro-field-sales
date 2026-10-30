import 'package:flutter/material.dart';
import '../../core/theme/tokens.dart';
import '../formatters/turkce.dart';

/// Para ve adet sütunları hizalı dursun diye monospace.
/// Tasarımda tüm sayısal alanlar IBM Plex Mono ile yazılıyor.
class Mono extends StatelessWidget {
  const Mono(this.text, {this.style, this.color, this.weight, this.size, super.key});

  final String text;
  final TextStyle? style;
  final Color? color;
  final FontWeight? weight;
  final double? size;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: (style ?? Theme.of(context).textTheme.bodyMedium)?.copyWith(
          fontFamily: T.fontMono,
          fontWeight: weight ?? FontWeight.w500,
          fontSize: size,
          color: color,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
}

/// Mikro etiket — tasarımdaki "NAVİGASYON", "DÜKKAN", "CİRO" başlıkları.
class MikroEtiket extends StatelessWidget {
  const MikroEtiket(this.text, {this.color, super.key});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
        text.buyuk,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
              letterSpacing: 0.9,
            ),
      );
}
