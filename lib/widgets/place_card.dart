import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../core/models.dart';

class PlaceCard extends StatelessWidget {
  final Place place;
  final VoidCallback onTap;

  const PlaceCard({super.key, required this.place, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: AppShadows.card,
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 76,
                height: 76,
                child: place.coverImageUrl != null
                    ? CachedNetworkImage(
                        imageUrl: place.coverImageUrl!,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => const Icon(Icons.restaurant),
                      )
                    : Container(
                        color: AppColors.primaryContainer,
                        child: const Icon(Icons.restaurant, size: 28, color: AppColors.primary),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          place.name,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (place.isVerified)
                        const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Icon(Icons.verified, size: 16, color: Colors.blue),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      place.category?.name ?? 'Restaurante',
                      if (place.district?.district != null) place.district!.district,
                    ].join(' · '),
                    style: const TextStyle(color: AppColors.onSurfaceVariant, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.star_rounded, color: AppColors.amber, size: 16),
                      Text(' ${place.rating.toStringAsFixed(1)}', style: const TextStyle(fontSize: 13)),
                      Text(' (${place.totalReviews})', style: const TextStyle(color: AppColors.onSurfaceVariant, fontSize: 13)),
                      if (place.priceMin != null) ...[
                        const SizedBox(width: 6),
                        Text('· S/ ${place.priceMin}-${place.priceMax}',
                            style: const TextStyle(color: AppColors.onSurfaceVariant, fontSize: 13)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
