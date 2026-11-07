import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../core/models.dart';
import 'place_list_tile.dart';

/// Lista deslizable de Explorar: "Cerca de ti · N", el chip "✨ Sorpréndeme"
/// y una tarjeta por local. Va como hija directa de un Stack/Scaffold que le
/// dé alto (es un DraggableScrollableSheet).
class ExploreBottomList extends StatelessWidget {
  final List<Place> places;
  final ValueChanged<Place> onPlaceTap;
  final VoidCallback onSurprise;

  /// Los locales ya vienen filtrados por "abierto ahora": se marcan "Abierto".
  final bool openNow;

  /// Metros desde el usuario hasta el local; null si no se sabe.
  final double? Function(Place place)? distanceMeters;

  /// Fracción del alto que ocupa la lista (0..1) mientras se arrastra.
  final ValueChanged<double>? onExtentChanged;

  static const initialExtent = 0.35;

  const ExploreBottomList({
    super.key,
    required this.places,
    required this.onPlaceTap,
    required this.onSurprise,
    this.openNow = false,
    this.distanceMeters,
    this.onExtentChanged,
  });

  @override
  Widget build(BuildContext context) {
    return NotificationListener<DraggableScrollableNotification>(
      onNotification: (n) {
        onExtentChanged?.call(n.extent);
        return false;
      },
      child: DraggableScrollableSheet(
        initialChildSize: initialExtent,
        minChildSize: 0.12,
        maxChildSize: 0.72,
        snap: true,
        snapSizes: const [initialExtent],
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.10),
                  blurRadius: 24,
                  offset: const Offset(0, -8))
            ],
          ),
          child: CustomScrollView(
            controller: scrollController,
            slivers: [
              SliverToBoxAdapter(child: _Header(
                  count: places.length, onSurprise: onSurprise)),
              if (places.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('No hay locales para mostrar por ahora.',
                        textAlign: TextAlign.center, style: AppText.bodyMd),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                sliver: SliverList.builder(
                  itemCount: places.length,
                  itemBuilder: (_, i) {
                    final place = places[i];
                    return PlaceListTile(
                      key: ValueKey('place-tile-${place.id}'),
                      place: place,
                      isOpen: openNow,
                      distanceMeters: distanceMeters?.call(place),
                      onTap: () => onPlaceTap(place),
                    );
                  },
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final int count;
  final VoidCallback onSurprise;
  const _Header({required this.count, required this.onSurprise});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      child: Column(children: [
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
              color: AppColors.border, borderRadius: BorderRadius.circular(4)),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text('Cerca de ti · $count',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.bodyLg.copyWith(fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 8),
            Material(
              color: AppColors.primaryContainer,
              shape: const StadiumBorder(),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: onSurprise,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text('✨ Sorpréndeme',
                      style: AppText.labelMd.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ],
        ),
      ]),
    );
  }
}
