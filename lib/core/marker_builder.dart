import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'place_image.dart';

/// Circular avatar map pin (photo + ring + pointer) matching the "Map Pins"
/// spec in the Stitch design system. Falls back to the Wuarikes logo when the
/// place has no photo.
class MapPin extends StatelessWidget {
  final String? imageUrl;
  final double size;
  final VoidCallback? onTap;

  const MapPin({super.key, this.imageUrl, this.size = 44, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary,
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 4, offset: const Offset(0, 2))],
            ),
            child: ClipOval(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(2),
                child: ClipOval(
                  child: PlaceImage(imageUrl: imageUrl, logoPadding: 1),
                ),
              ),
            ),
          ),
          CustomPaint(size: const Size(10, 6), painter: _PointerPainter()),
        ],
      ),
    );
  }
}

class _PointerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = AppColors.primary);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
