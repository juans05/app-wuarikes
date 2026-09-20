import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../core/api_client.dart';
import '../core/app_theme.dart';
import '../core/models.dart';
import 'advanced_filters_screen.dart';
import 'place_detail_screen.dart';

/// Full-screen search results — reached by submitting a search, "Ver
/// todos", or "Ver X resultados" from [AdvancedFiltersScreen]. Its own tune
/// icon reopens the advanced filters to refine further. "Ver en mapa" just
/// pops back to the map.
class SearchResultsScreen extends StatefulWidget {
  final String query;
  final AdvancedFilters initialFilters;
  final double? latitude;
  final double? longitude;

  const SearchResultsScreen({
    super.key,
    this.query = '',
    this.initialFilters = const AdvancedFilters(radiusKm: 5),
    this.latitude,
    this.longitude,
  });

  @override
  State<SearchResultsScreen> createState() => _SearchResultsScreenState();
}

class _SearchResultsScreenState extends State<SearchResultsScreen> {
  final ApiClient _api = ApiClient();
  late final _searchCtrl = TextEditingController(text: widget.query);
  final _districtCtrl = TextEditingController();
  List<Category> _categories = [];
  List<Amenity> _amenities = [];

  late String? _category = widget.initialFilters.category;
  late double _radiusKm = widget.initialFilters.radiusKm;
  late num? _priceMin = widget.initialFilters.priceMin;
  late num? _priceMax = widget.initialFilters.priceMax;
  late String? _priceLabel = widget.initialFilters.priceLabel;
  late double? _minRating = widget.initialFilters.minRating;
  late Set<String> _amenitySlugs = Set.from(widget.initialFilters.amenitySlugs);
  late bool _openNow = widget.initialFilters.openNow;

  List<Place> _places = [];
  int _total = 0;
  bool _loading = true;

  String? get _categoryName {
    if (_category == null) return null;
    return _categories
        .firstWhere((c) => c.slug == _category,
            orElse: () => Category(id: '', name: _category!, slug: _category!))
        .name;
  }

  @override
  void initState() {
    super.initState();
    _api
        .getCategories()
        .then((c) => mounted ? setState(() => _categories = c) : null)
        .catchError((_) {});
    _api
        .getAmenities()
        .then((a) => mounted ? setState(() => _amenities = a) : null)
        .catchError((_) {});
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _districtCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final result = await _api.getPlaces(
        category: _category,
        district: _districtCtrl.text.trim(),
        search:
            _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
        latitude: widget.latitude,
        longitude: widget.longitude,
        radius: widget.latitude != null ? _radiusKm : null,
        priceMin: _priceMin,
        priceMax: _priceMax,
        minRating: _minRating,
        amenities: _amenitySlugs.isEmpty ? null : _amenitySlugs.toList(),
        openNow: _openNow,
      );
      if (!mounted) return;
      setState(() {
        _places = result.data;
        _total = result.total;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _places = [];
          _total = 0;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _removeCategory() {
    setState(() => _category = null);
    _load();
  }

  void _removeOpenNow() {
    setState(() => _openNow = false);
    _load();
  }

  void _removePrice() {
    setState(() {
      _priceLabel = null;
      _priceMin = null;
      _priceMax = null;
    });
    _load();
  }

  void _removeRating() {
    setState(() => _minRating = null);
    _load();
  }

  void _removeAmenity(String slug) {
    setState(() => _amenitySlugs = {..._amenitySlugs}..remove(slug));
    _load();
  }

  Future<void> _showAdvancedFilters() async {
    final result = await Navigator.of(context).push<AdvancedFilters>(
      MaterialPageRoute(
        builder: (_) => AdvancedFiltersScreen(
          categories: _categories,
          amenities: _amenities,
          latitude: widget.latitude,
          longitude: widget.longitude,
          initial: AdvancedFilters(
            category: _category,
            radiusKm: _radiusKm,
            priceMin: _priceMin,
            priceMax: _priceMax,
            priceLabel: _priceLabel,
            minRating: _minRating,
            amenitySlugs: _amenitySlugs,
            openNow: _openNow,
          ),
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _category = result.category;
      _radiusKm = result.radiusKm;
      _priceMin = result.priceMin;
      _priceMax = result.priceMax;
      _priceLabel = result.priceLabel;
      _minRating = result.minRating;
      _amenitySlugs = result.amenitySlugs;
      _openNow = result.openNow;
    });
    _load();
  }

  void _openPlace(Place place) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PlaceDetailScreen(placeId: place.id)));
  }

  @override
  Widget build(BuildContext context) {
    final activeChips = <Widget>[
      if (_category != null)
        _ActiveChip(label: _categoryName!, onRemove: _removeCategory),
      if (_openNow)
        _ActiveChip(label: 'Abierto ahora', onRemove: _removeOpenNow),
      if (_priceLabel != null)
        _ActiveChip(label: _priceLabel!, onRemove: _removePrice),
      if (_minRating != null)
        _ActiveChip(
            label: '${_minRating!.toStringAsFixed(1)}+ ★',
            onRemove: _removeRating),
      for (final slug in _amenitySlugs)
        _ActiveChip(
          label: _amenities
              .firstWhere((a) => a.slug == slug,
                  orElse: () => Amenity(id: '', name: slug, slug: slug))
              .name,
          onRemove: () => _removeAmenity(slug),
        ),
    ];

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded,
                        color: AppColors.primary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppColors.border.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.search_rounded,
                              color: AppColors.onSurfaceVariant, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _searchCtrl,
                              onSubmitted: (_) => _load(),
                              style: AppText.bodyLg
                                  .copyWith(color: AppColors.onSurface),
                              decoration: const InputDecoration(
                                  border: InputBorder.none, isDense: true),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.tune_rounded,
                        color: AppColors.primary),
                    onPressed: _showAdvancedFilters,
                  ),
                ],
              ),
            ),
            Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: TextField(
                    controller: _districtCtrl,
                    decoration: InputDecoration(
                        labelText: 'Distrito (opcional)',
                        suffixIcon: IconButton(
                            tooltip: 'Filtrar por distrito',
                            onPressed: _load,
                            icon: const Icon(Icons.search))),
                    onSubmitted: (_) => _load())),
            if (activeChips.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(spacing: 8, runSpacing: 8, children: activeChips),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _loading ? 'Buscando...' : '$_total huariques encontrados',
                  style: AppText.labelMd,
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _places.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.search_off_rounded,
                                    size: 36,
                                    color: AppColors.onSurfaceVariant),
                                const SizedBox(height: 12),
                                Text(
                                    'No encontramos huariques con esos filtros.',
                                    textAlign: TextAlign.center,
                                    style: AppText.bodyMd),
                              ],
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                          itemCount: _places.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 16),
                          itemBuilder: (context, i) => _ResultCard(
                              place: _places[i],
                              onTap: () => _openPlace(_places[i])),
                        ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).pop(),
        backgroundColor: AppColors.primaryContainer,
        foregroundColor: AppColors.onPrimaryContainer,
        icon: const Icon(Icons.map_rounded),
        label: const Text('Ver en mapa'),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}

class _ActiveChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;
  const _ActiveChip({required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 12, right: 6, top: 6, bottom: 6),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: AppText.labelMd.copyWith(
                  color: AppColors.onPrimaryContainer,
                  fontWeight: FontWeight.w600)),
          InkWell(
            onTap: onRemove,
            customBorder: const CircleBorder(),
            child: const Padding(
              padding: EdgeInsets.all(2),
              child: Icon(Icons.close_rounded,
                  size: 16, color: AppColors.onPrimaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final Place place;
  final VoidCallback onTap;
  const _ResultCard({required this.place, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: AppShadows.card,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                SizedBox(
                  height: 160,
                  width: double.infinity,
                  child: place.coverImageUrl != null
                      ? CachedNetworkImage(
                          imageUrl: place.coverImageUrl!, fit: BoxFit.cover)
                      : Container(
                          color: AppColors.primaryContainer,
                          child: const Icon(Icons.restaurant,
                              size: 36, color: AppColors.primary)),
                ),
                Positioned(
                  right: 10,
                  top: 10,
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.white.withValues(alpha: 0.9),
                    child: const Icon(Icons.favorite_border,
                        size: 16, color: AppColors.primary),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(place.name,
                                style: AppText.titleLg,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 2),
                            Text(
                              [
                                place.category?.name ?? 'Restaurante',
                                if (place.district?.district != null)
                                  place.district!.district
                              ].join(' · '),
                              style: AppText.bodyMd,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                            color: AppColors.primaryContainer,
                            borderRadius: BorderRadius.circular(8)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star_rounded,
                                size: 16, color: AppColors.primary),
                            const SizedBox(width: 2),
                            Text(place.rating.toStringAsFixed(1),
                                style: AppText.labelMd.copyWith(
                                    color: AppColors.onPrimaryContainer,
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (place.priceMin != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.payments_outlined,
                            size: 16, color: AppColors.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text('S/ ${place.priceMin}-${place.priceMax}',
                            style: AppText.labelMd),
                      ],
                    ),
                  ],
                  if (place.amenities.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: place.amenities.take(2).map((a) {
                        final icon = amenityIcons[a.toLowerCase()] ??
                            Icons.check_circle_outline_rounded;
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(icon,
                                  size: 14, color: AppColors.onSurfaceVariant),
                              const SizedBox(width: 4),
                              Text(a, style: AppText.labelMd),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
