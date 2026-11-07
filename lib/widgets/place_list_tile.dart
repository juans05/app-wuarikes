import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../core/models.dart';
import '../core/place_image.dart';

/// Tarjeta de la lista de Explorar: foto, nombre, ⭐, categoría, distancia,
/// "Desde S/" y las etiquetas "🔥" y "Abierto". Lo que el local no tiene
/// (precio, categoría, distancia) simplemente no se muestra.
class PlaceListTile extends StatelessWidget {
  final Place place;
  final VoidCallback onTap;

  /// Metros desde el usuario; null si no se sabe dónde está.
  final double? distanceMeters;

  /// El servidor ya filtró por "abierto ahora", así que todo lo listado lo está.
  final bool isOpen;

  const PlaceListTile({
    super.key,
    required this.place,
    required this.onTap,
    this.distanceMeters,
    this.isOpen = false,
  });

  @override
  Widget build(BuildContext context) {
    // Muchos locales importados solo tienen la nota de Google.
    final rating = place.rating > 0 ? place.rating : (place.googleRating ?? 0);
    final price = place.priceMin;
    final meta = [
      if ((place.category?.name ?? '').isNotEmpty) place.category!.name,
      if (distanceMeters != null) formatDistance(distanceMeters!),
      if (price != null && price > 0) 'Desde S/ ${formatPrice(price)}',
    ].join(' · ');

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.5))),
        ),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 52,
              height: 52,
              child: PlaceImage(imageUrl: place.coverImageUrl, logoPadding: 6),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(place.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.bodyLg.copyWith(
                            fontSize: 14, fontWeight: FontWeight.w700)),
                  ),
                  if (rating > 0) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.star_rounded,
                        size: 14, color: AppColors.amber),
                    Text(' ${rating.toStringAsFixed(1)}',
                        style: AppText.labelMd),
                  ],
                ]),
                if (meta.isNotEmpty)
                  Text(meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.labelMd),
                if (place.hasActiveBenefit || isOpen)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(spacing: 6, children: [
                      if (place.hasActiveBenefit)
                        const _Tag(
                            label: '🔥 Beneficio',
                            background: AppColors.secondary,
                            foreground: AppColors.onSurface),
                      if (isOpen)
                        _Tag(
                            label: 'Abierto',
                            background:
                                AppColors.accent.withValues(alpha: 0.12),
                            foreground: AppColors.accent),
                    ]),
                  ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

/// "350 m" bajo 1 km; "1.2 km" desde ahí.
String formatDistance(double meters) => meters < 1000
    ? '${meters.round()} m'
    : '${(meters / 1000).toStringAsFixed(1)} km';

/// 18 -> "18"; 18.5 -> "18.50".
String formatPrice(num price) =>
    price == price.roundToDouble() ? '${price.round()}' : price.toStringAsFixed(2);

class _Tag extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;
  const _Tag(
      {required this.label, required this.background, required this.foreground});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
          color: background, borderRadius: BorderRadius.circular(8)),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700, color: foreground)),
    );
  }
}
