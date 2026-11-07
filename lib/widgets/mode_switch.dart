import 'package:flutter/material.dart';
import '../core/app_theme.dart';

/// Lo que muestra Explorar: los locales de siempre o lo que pasa "Ahora".
enum ExploreMode { places, now }

/// Interruptor "🍽️ Locales / ⚡ Ahora" de Explorar.
class ModeSwitch extends StatelessWidget {
  final ExploreMode value;
  final ValueChanged<ExploreMode> onChanged;

  const ModeSwitch({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppShadows.card,
      ),
      child: Row(children: [
        _Segment(
            label: '🍽️ Locales',
            selected: value == ExploreMode.places,
            onTap: () => _pick(ExploreMode.places)),
        _Segment(
            label: '⚡ Ahora',
            selected: value == ExploreMode.now,
            onTap: () => _pick(ExploreMode.now)),
      ]),
    );
  }

  void _pick(ExploreMode mode) {
    if (mode != value) onChanged(mode);
  }
}

class _Segment extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Segment(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : AppColors.onSurfaceVariant)),
        ),
      ),
    );
  }
}
