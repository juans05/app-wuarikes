import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'app_theme.dart';

/// A place's photo, falling back to the Wuarikes pin when there is none or
/// the URL fails to load, so a place without a cover still looks branded
/// instead of showing a generic grey box.
class PlaceImage extends StatelessWidget {
  final String? imageUrl;
  final BoxFit fit;

  /// Breathing room around the logo in the fallback. Small surfaces (map pins)
  /// want less than large ones (cover headers).
  final double logoPadding;

  const PlaceImage({
    super.key,
    this.imageUrl,
    this.fit = BoxFit.cover,
    this.logoPadding = 10,
  });

  @override
  Widget build(BuildContext context) {
    final fallback = _WuarikesLogo(padding: logoPadding);
    if (imageUrl == null || imageUrl!.isEmpty) return fallback;
    return CachedNetworkImage(
      imageUrl: imageUrl!,
      fit: fit,
      placeholder: (_, __) => Container(color: AppColors.primaryContainer),
      errorWidget: (_, __, ___) => fallback,
    );
  }
}

class _WuarikesLogo extends StatelessWidget {
  final double padding;
  const _WuarikesLogo({required this.padding});

  @override
  Widget build(BuildContext context) => Container(
        color: Colors.white,
        padding: EdgeInsets.all(padding),
        alignment: Alignment.center,
        child: Image.asset('assets/logo-icon.png', fit: BoxFit.contain),
      );
}
