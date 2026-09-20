import 'dart:async';
import 'package:flutter/material.dart';
import '../core/api_client.dart';
import '../core/app_theme.dart';
import '../core/models.dart';
import 'place_detail_screen.dart' show amenityIcons;

/// Bundle of every criterion the advanced filter screen can set, returned
/// to the caller when the user taps "Ver X resultados".
class AdvancedFilters {
  final String? category;
  final double radiusKm;
  final num? priceMin;
  final num? priceMax;
  final String? priceLabel;
  final double? minRating;
  final Set<String> amenitySlugs;
  final bool openNow;

  const AdvancedFilters({
    this.category,
    required this.radiusKm,
    this.priceMin,
    this.priceMax,
    this.priceLabel,
    this.minRating,
    this.amenitySlugs = const {},
    this.openNow = false,
  });
}

/// Full-screen "Filtros Avanzados" — matches the Stitch mock: category
/// chips, a distance slider, a $/$$/$$$ price toggle, minimum-rating
/// chips, amenity chips, an "abierto ahora" switch, and a footer CTA that
/// shows a live count of matching places as filters change.
class AdvancedFiltersScreen extends StatefulWidget {
  final List<Category> categories;
  final List<Amenity> amenities;
  final double? latitude;
  final double? longitude;
  final AdvancedFilters initial;

  const AdvancedFiltersScreen({
    super.key,
    required this.categories,
    required this.amenities,
    required this.initial,
    this.latitude,
    this.longitude,
  });

  @override
  State<AdvancedFiltersScreen> createState() => _AdvancedFiltersScreenState();
}

class _AdvancedFiltersScreenState extends State<AdvancedFiltersScreen> {
  final ApiClient _api = ApiClient();

  static const _priceTiers = [('\$', 0.0, 20.0), ('\$\$', 20.0, 50.0), ('\$\$\$', 50.0, null)];
  static const _ratingOptions = [3.0, 4.0, 4.5];

  late String? _category = widget.initial.category;
  late double _radiusKm = widget.initial.radiusKm;
  late String? _priceLabel = widget.initial.priceLabel;
  late num? _priceMin = widget.initial.priceMin;
  late num? _priceMax = widget.initial.priceMax;
  late double? _minRating = widget.initial.minRating;
  late Set<String> _amenitySlugs = Set.from(widget.initial.amenitySlugs);
  late bool _openNow = widget.initial.openNow;

  int? _count;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _fetchCount();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _scheduleCount() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _fetchCount);
  }

  Future<void> _fetchCount() async {
    setState(() => _count = null);
    try {
      final result = await _api.getPlaces(
        category: _category,
        latitude: widget.latitude,
        longitude: widget.longitude,
        radius: widget.latitude != null ? _radiusKm : null,
        priceMin: _priceMin,
        priceMax: _priceMax,
        minRating: _minRating,
        amenities: _amenitySlugs.isEmpty ? null : _amenitySlugs.toList(),
        openNow: _openNow,
      );
      if (mounted) setState(() => _count = result.total);
    } catch (_) {
      if (mounted) setState(() => _count = 0);
    }
  }

  void _clearAll() {
    setState(() {
      _category = null;
      _radiusKm = 5;
      _priceLabel = null;
      _priceMin = null;
      _priceMax = null;
      _minRating = null;
      _amenitySlugs = {};
      _openNow = false;
    });
    _fetchCount();
  }

  void _apply() {
    Navigator.of(context).pop(AdvancedFilters(
      category: _category,
      radiusKm: _radiusKm,
      priceMin: _priceMin,
      priceMax: _priceMax,
      priceLabel: _priceLabel,
      minRating: _minRating,
      amenitySlugs: _amenitySlugs,
      openNow: _openNow,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Filtros'),
        actions: [
          TextButton(onPressed: _clearAll, child: const Text('Limpiar')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          _SectionTitle('Categoría'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in widget.categories)
                _Chip(
                  label: c.name,
                  selected: _category == c.slug,
                  onTap: () {
                    setState(() => _category = _category == c.slug ? null : c.slug);
                    _scheduleCount();
                  },
                ),
            ],
          ),
          const _Divider(),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _SectionTitle('Distancia', padded: false),
              Text('${_radiusKm.toStringAsFixed(1)} km', style: AppText.labelMd.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700)),
            ],
          ),
          Slider(
            value: _radiusKm.clamp(0, 15),
            min: 0,
            max: 15,
            divisions: 30,
            activeColor: AppColors.primary,
            label: '${_radiusKm.toStringAsFixed(1)} km',
            onChanged: widget.latitude == null ? null : (v) => setState(() => _radiusKm = v),
            onChangeEnd: (_) => _scheduleCount(),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('0 km', style: AppText.labelMd),
                Text('15 km', style: AppText.labelMd),
              ],
            ),
          ),
          const _Divider(),

          _SectionTitle('Rango de precio'),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: AppColors.border.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(AppRadius.lg)),
            child: Row(
              children: [
                for (final tier in _priceTiers)
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          final selecting = _priceLabel != tier.$1;
                          _priceLabel = selecting ? tier.$1 : null;
                          _priceMin = selecting ? tier.$2 : null;
                          _priceMax = selecting ? tier.$3 : null;
                        });
                        _scheduleCount();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _priceLabel == tier.$1 ? AppColors.primaryContainer : Colors.transparent,
                          borderRadius: BorderRadius.circular(AppRadius.lg - 4),
                        ),
                        child: Text(tier.$1,
                            style: AppText.titleLg.copyWith(color: _priceLabel == tier.$1 ? AppColors.onPrimaryContainer : AppColors.onSurfaceVariant)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const _Divider(),

          _SectionTitle('Calificación'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final r in _ratingOptions)
                _Chip(
                  label: '${r.toStringAsFixed(1)}+',
                  icon: Icons.star_rounded,
                  selected: _minRating == r,
                  onTap: () {
                    setState(() => _minRating = _minRating == r ? null : r);
                    _scheduleCount();
                  },
                ),
            ],
          ),
          const _Divider(),

          _SectionTitle('Servicios'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final a in widget.amenities)
                _Chip(
                  label: a.name,
                  icon: amenityIcons[a.name.toLowerCase()] ?? Icons.check_circle_outline_rounded,
                  selected: _amenitySlugs.contains(a.slug),
                  onTap: () {
                    setState(() {
                      if (_amenitySlugs.contains(a.slug)) {
                        _amenitySlugs = {..._amenitySlugs}..remove(a.slug);
                      } else {
                        _amenitySlugs = {..._amenitySlugs, a.slug};
                      }
                    });
                    _scheduleCount();
                  },
                ),
            ],
          ),
          const _Divider(),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Abierto ahora', style: AppText.titleLg),
                      Text('Solo mostrar lugares disponibles', style: AppText.bodyMd),
                    ],
                  ),
                ),
                Switch(
                  value: _openNow,
                  activeThumbColor: AppColors.primary,
                  onChanged: (v) {
                    setState(() => _openNow = v);
                    _scheduleCount();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: FilledButton(
            onPressed: _count == 0 ? null : _apply,
            child: Text(_count == null ? 'Buscando...' : 'Ver $_count resultados'),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  final bool padded;
  const _SectionTitle(this.text, {this.padded = true});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: padded ? 12 : 0, top: 4),
      child: Text(text, style: AppText.titleLg),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Divider(height: 1, color: AppColors.border),
      );
}

class _Chip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;
  const _Chip({required this.label, this.icon, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryContainer : AppColors.border.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: selected ? Border.all(color: AppColors.primary, width: 1.5) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: selected ? AppColors.onPrimaryContainer : AppColors.onSurfaceVariant),
              const SizedBox(width: 6),
            ],
            Text(label, style: AppText.labelMd.copyWith(color: selected ? AppColors.onPrimaryContainer : AppColors.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
