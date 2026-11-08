import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../core/app_theme.dart';
import '../../core/now_models.dart';
import '../../widgets/place_list_tile.dart' show formatDistance;

/// Aviso entre pantallas: la hoja de publicar lo sube con la publicación nueva
/// y Explorar (si está abierta) pasa a "Ahora" y recarga la zona.
final nowPostPublished = ValueNotifier<NowPost?>(null);

/// 📸 foto, 🎥 video, 💬 solo texto.
String nowPinEmoji(String kind) => switch (kind) {
      'video' => '🎥',
      'text' => '💬',
      _ => '📸',
    };

/// Pines de Ahora para el mapa: promos (fondo ají, 🔥) y publicaciones de la
/// gente (fondo hierba, 📸/🎥/💬).
class NowPinsLayer extends StatelessWidget {
  final NowArea area;
  final ValueChanged<NowPost> onPostTap;
  final ValueChanged<NowPromo> onPromoTap;

  const NowPinsLayer(
      {super.key,
      required this.area,
      required this.onPostTap,
      required this.onPromoTap});

  @override
  Widget build(BuildContext context) {
    return MarkerLayer(markers: [
      for (final promo in area.promos)
        Marker(
          point: LatLng(promo.latitude, promo.longitude),
          width: 44,
          height: 44,
          child: _NowPin(
              key: ValueKey('now-pin-promo-${promo.id}'),
              emoji: '🔥',
              color: AppColors.secondary,
              size: 36,
              onTap: () => onPromoTap(promo)),
        ),
      for (final post in area.posts)
        Marker(
          point: LatLng(post.latitude, post.longitude),
          width: 44,
          height: 44,
          child: _NowPin(
              key: ValueKey('now-pin-post-${post.id}'),
              emoji: nowPinEmoji(post.kind),
              color: AppColors.accent,
              size: 40,
              onTap: () => onPostTap(post)),
        ),
    ]);
  }
}

class _NowPin extends StatelessWidget {
  final String emoji;
  final Color color;
  final double size;
  final VoidCallback onTap;
  const _NowPin(
      {super.key,
      required this.emoji,
      required this.color,
      required this.size,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Center(
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 4))
            ],
          ),
          child: Text(emoji, style: const TextStyle(fontSize: 16)),
        ),
      ),
    );
  }
}

/// Pin chico de un local mientras se ve "Ahora": no compite con los de la gente.
class SmallPlacePin extends StatelessWidget {
  final VoidCallback onTap;
  const SmallPlacePin({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Center(
        child: Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            border: Border.all(color: AppColors.primary, width: 2),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 6,
                  offset: const Offset(0, 2))
            ],
          ),
          child: const Text('🍽️', style: TextStyle(fontSize: 12)),
        ),
      ),
    );
  }
}

/// Franja "Hoy cerca de ti": promos y publicaciones de la zona, las más cercanas
/// primero (si se sabe dónde está el usuario).
class NowStrip extends StatelessWidget {
  /// Null mientras no llega la primera respuesta.
  final NowArea? area;

  /// Metros del usuario a un punto; null si no se sabe dónde está.
  final double? Function(double lat, double lng) distanceTo;
  final ValueChanged<NowPost> onPostTap;
  final ValueChanged<NowPromo> onPromoTap;

  const NowStrip(
      {super.key,
      required this.area,
      required this.distanceTo,
      required this.onPostTap,
      required this.onPromoTap});

  @override
  Widget build(BuildContext context) {
    final area = this.area;
    if (area == null) return const SizedBox.shrink();
    final now = DateTime.now();
    final items = <_StripItem>[
      for (final p in area.promos)
        _StripItem(
          key: ValueKey('now-chip-promo-${p.id}'),
          promo: true,
          time: promoEndsLabel(p.visibleUntil, now),
          title: p.title,
          who: p.placeName ?? 'Local',
          meters: distanceTo(p.latitude, p.longitude),
          onTap: () => onPromoTap(p),
        ),
      for (final p in area.posts)
        _StripItem(
          key: ValueKey('now-chip-post-${p.id}'),
          promo: false,
          time: timeLeftLabel(p.timeLeft(now)),
          title: (p.text ?? '').trim().isNotEmpty
              ? p.text!.trim()
              : (p.kind == 'video' ? 'Video' : 'Foto'),
          who: '@${p.authorName}',
          meters: distanceTo(p.latitude, p.longitude),
          onTap: () => onPostTap(p),
        ),
    ];
    // Con distancia primero, de menor a mayor; sin distancia, al final y en el
    // orden en que llegaron (List.sort no garantiza estabilidad).
    final order = {for (var i = 0; i < items.length; i++) items[i]: i};
    items.sort((a, b) {
      final byDistance =
          (a.meters ?? double.infinity).compareTo(b.meters ?? double.infinity);
      return byDistance != 0 ? byDistance : order[a]!.compareTo(order[b]!);
    });

    if (items.isEmpty) {
      return Container(
        key: const Key('now-strip-empty'),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: AppShadows.card,
        ),
        child: Text('Aún no hay nada por esta zona. ¡Publica lo que pasa!',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppText.labelMd),
      );
    }
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.2,
      child: SizedBox(
        height: 78,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) => items[i],
        ),
      ),
    );
  }
}

class _StripItem extends StatelessWidget {
  final bool promo;
  final String time;
  final String title;
  final String who;
  final double? meters;
  final VoidCallback onTap;

  const _StripItem(
      {super.key,
      required this.promo,
      required this.time,
      required this.title,
      required this.who,
      required this.meters,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final m = meters;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 160,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: AppShadows.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              _Tag(
                  label: promo ? 'PROMO' : 'GENTE',
                  background: promo ? AppColors.secondary : AppColors.accent,
                  foreground: promo ? AppColors.onSurface : Colors.white),
              const SizedBox(width: 6),
              Flexible(
                child: _Tag(
                    label: time,
                    background: AppColors.primaryContainer,
                    foreground: AppColors.primary),
              ),
            ]),
            const SizedBox(height: 4),
            Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.bodyLg.copyWith(
                    fontSize: 12, fontWeight: FontWeight.w700, height: 1.2)),
            Text(m == null ? who : '$who · ${formatDistance(m)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.labelMd.copyWith(fontSize: 11, height: 1.2)),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;
  const _Tag(
      {required this.label,
      required this.background,
      required this.foreground});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
          color: background, borderRadius: BorderRadius.circular(8)),
      child: Text(label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700, color: foreground)),
    );
  }
}
