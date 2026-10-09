import 'package:flutter/material.dart';

/// Uses the legible green/black artwork on light surfaces and keeps the
/// existing brand artwork in dark mode. The fallback protects older bundles
/// while the new PNG is being distributed with the application.
class OtoTagBrandLogo extends StatelessWidget {
  const OtoTagBrandLogo({
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
  });

  final double? width;
  final double? height;
  final BoxFit fit;
  final AlignmentGeometry alignment;

  static const lightAsset = 'assets/images/ototag_logo_light.png';
  static const darkAsset = 'assets/images/logo.png';

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    Widget image(String asset, {bool fallback = false}) => Image.asset(
      asset,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, trace) {
        if (!fallback) return image(darkAsset, fallback: true);
        return Icon(
          Icons.directions_car_rounded,
          size: height ?? width ?? 28,
          color: Theme.of(context).colorScheme.primary,
        );
      },
    );
    return image(isLight ? lightAsset : darkAsset, fallback: !isLight);
  }
}
