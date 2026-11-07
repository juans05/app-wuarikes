import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../core/api_client.dart';
import '../core/app_theme.dart';
import '../core/map_config.dart';
import '../core/marker_builder.dart';
import '../core/models.dart';
import '../core/place_image.dart';
import '../state/auth_provider.dart';
import '../widgets/explore_bottom_list.dart';
import '../widgets/mode_switch.dart';
import 'advanced_filters_screen.dart';
import 'filter_screen.dart';
import 'place_detail_screen.dart';
import 'search_results_screen.dart';
import 'discovery_screen.dart';

/// Default map center: Miraflores, Lima — used until the user's location
/// resolves (or if location permission is denied).
const _defaultCenter = LatLng(-12.1211, -77.0296);

/// Why we couldn't place the user on the map. Each case needs a different
/// fix, so the banner can send them to the right place instead of a generic
/// "enable location" message.
enum _LocationIssue { serviceOff, denied, blocked, unavailable }

class ExploreScreen extends StatefulWidget {
  /// Abre la pestaña Perfil (la pone el shell). Sin ella el avatar no hace nada.
  final VoidCallback? onOpenProfile;

  /// Solo para pruebas: cliente de API con datos de mentira.
  final ApiClient? api;

  const ExploreScreen({super.key, this.onOpenProfile, this.api});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  late final ApiClient _api = widget.api ?? ApiClient();
  final MapController _mapController = MapController();

  /// Locales o Ahora. En `now` Explorar sigue mostrando el mapa y la lista de
  /// locales: la capa Ahora (pines, franja "Hoy cerca de ti") se engancha en
  /// los puntos marcados "AHORA" de [build].
  ExploreMode _mode = ExploreMode.places;

  /// Alto actual de la lista deslizable (fracción 0..1), para subir el botón
  /// "mi ubicación" junto con ella.
  final ValueNotifier<double> _sheetExtent =
      ValueNotifier(ExploreBottomList.initialExtent);

  List<Place> _places = [];
  List<Category> _categories = [];
  List<Amenity> _amenities = [];
  String? _activeCategory;
  List<Marker> _markers = [];
  Position? _position;
  _LocationIssue? _locationIssue;
  bool _mapReady = false;
  double _radiusKm = 5;
  bool _openNow = false;
  double? _minRating;
  num? _priceMin;
  num? _priceMax;
  String? _priceLabel;
  Set<String> _amenitySlugs = {};

  bool get _hasAdvancedFilters =>
      _priceLabel != null || _minRating != null || _amenitySlugs.isNotEmpty;

  String? get _activeCategoryName {
    if (_activeCategory == null) return null;
    return _categories
        .firstWhere((c) => c.slug == _activeCategory,
            orElse: () => Category(
                id: '', name: _activeCategory!, slug: _activeCategory!))
        .name;
  }

  GamificationStats? _stats;

  void _loadStats() {
    if (!context.read<AuthProvider>().isLoggedIn) return;
    _api
        .getMyStats()
        .then((s) => mounted ? setState(() => _stats = s) : null)
        .catchError((_) {});
  }

  @override
  void dispose() {
    ApiClient.checkinCreated.removeListener(_loadStats);
    _sheetExtent.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadStats();
    ApiClient.checkinCreated.addListener(_loadStats);
    _api
        .getCategories()
        .then((c) => mounted ? setState(() => _categories = c) : null)
        .catchError((_) {});
    _api
        .getAmenities()
        .then((a) => mounted ? setState(() => _amenities = a) : null)
        .catchError((_) {});
    // Show something immediately instead of waiting up to 20s for GPS: load
    // the general listing right away, then refine (recentered + radius
    // filter) once real location resolves in the background.
    _loadPlaces();
    _resolveLocation().then((_) {
      if (!mounted || _position == null) return;
      if (_mapReady) {
        _mapController.move(
            LatLng(_position!.latitude, _position!.longitude), 15);
      }
      _loadPlaces();
    });
  }

  AdvancedFilters get _currentFilters => AdvancedFilters(
        category: _activeCategory,
        radiusKm: _radiusKm,
        priceMin: _priceMin,
        priceMax: _priceMax,
        priceLabel: _priceLabel,
        minRating: _minRating,
        amenitySlugs: _amenitySlugs,
        openNow: _openNow,
      );

  void _openSearchResults({String query = '', AdvancedFilters? filters}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SearchResultsScreen(
        query: query,
        initialFilters: filters ?? _currentFilters,
        latitude: _position?.latitude,
        longitude: _position?.longitude,
      ),
    ));
  }

  Future<void> _resolveLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) setState(() => _locationIssue = _LocationIssue.serviceOff);
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() => _locationIssue =
              permission == LocationPermission.deniedForever
                  ? _LocationIssue.blocked
                  : _LocationIssue.denied);
        }
        return;
      }
      _position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 20)),
      );
      if (mounted) setState(() => _locationIssue = null);
    } catch (_) {
      _position = null;
      if (mounted) {
        setState(() => _locationIssue = _LocationIssue.unavailable);
      }
    }
  }

  /// Sends the user straight to whatever is actually blocking us, then
  /// re-resolves so the map recenters without needing a manual retry.
  Future<void> _fixLocation() async {
    if (_locationIssue == _LocationIssue.serviceOff) {
      await Geolocator.openLocationSettings();
    } else if (_locationIssue == _LocationIssue.blocked) {
      await Geolocator.openAppSettings();
    }
    await _resolveLocation();
    if (!mounted || _position == null) return;
    if (_mapReady) {
      _mapController.move(
          LatLng(_position!.latitude, _position!.longitude), 15);
    }
    _loadPlaces();
  }

  Future<void> _loadPlaces() async {
    try {
      final result = await _api.getPlaces(
        category: _activeCategory,
        latitude: _position?.latitude,
        longitude: _position?.longitude,
        radius: _position != null ? _radiusKm : null,
        priceMin: _priceMin,
        priceMax: _priceMax,
        minRating: _minRating,
        amenities: _amenitySlugs.isEmpty ? null : _amenitySlugs.toList(),
        openNow: _openNow,
      );
      if (!mounted) return;
      setState(() => _places = result.data);
      _buildMarkers();
    } catch (_) {
      if (mounted) setState(() => _places = []);
    }
  }

  void _buildMarkers() {
    final markers = <Marker>[];
    for (final place in _places) {
      if (place.latitude == null || place.longitude == null) continue;
      markers.add(Marker(
        point: LatLng(place.latitude!, place.longitude!),
        alignment: Alignment.topCenter,
        width: 44,
        height: 56,
        child: MapPin(
            imageUrl: place.coverImageUrl, onTap: () => _openPlace(place)),
      ));
    }
    if (mounted) setState(() => _markers = markers);
  }

  void _openPlace(Place place) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 72,
                      height: 72,
                      child: PlaceImage(
                          imageUrl: place.coverImageUrl, logoPadding: 6),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(place.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.titleLg),
                        const SizedBox(height: 4),
                        Row(children: [
                          const Icon(Icons.star_rounded,
                              size: 16, color: AppColors.amber),
                          Text(' ${place.rating.toStringAsFixed(1)}',
                              style: AppText.bodyMd),
                        ]),
                        if ((place.district?.district ?? '').isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(place.district!.district!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.labelMd),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('Cerrar')),
                  const SizedBox(width: 4),
                  FilledButton(
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) =>
                              PlaceDetailScreen(placeId: place.id)));
                    },
                    child: const Text('Ver detalles'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openPlaceDetail(Place place) {
    Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PlaceDetailScreen(placeId: place.id)));
  }

  void _openDiscovery() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const DiscoveryScreen()));
  }

  /// Metros del usuario al local; null si no se sabe dónde está alguno.
  double? _distanceTo(Place place) {
    final position = _position;
    if (position == null || place.latitude == null || place.longitude == null) {
      return null;
    }
    return Geolocator.distanceBetween(position.latitude, position.longitude,
        place.latitude!, place.longitude!);
  }

  @override
  Widget build(BuildContext context) {
    final initialTarget = _position != null
        ? LatLng(_position!.latitude, _position!.longitude)
        : _defaultCenter;

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) => Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: initialTarget,
                initialZoom: 14,
                onMapReady: () {
                  _mapReady = true;
                  if (_position != null) {
                    _mapController.move(
                        LatLng(_position!.latitude, _position!.longitude), 15);
                  }
                },
                interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
              ),
              children: [
                buildMapboxTileLayer(),
                // AHORA (Task 9): aquí, antes de los pines de locales, va la
                // capa de pines de _mode == ExploreMode.now.
                MarkerLayer(markers: _markers),
                if (_position != null)
                  MarkerLayer(markers: [
                    Marker(
                      point: LatLng(_position!.latitude, _position!.longitude),
                      child: const Icon(Icons.circle,
                          color: AppColors.primary, size: 16),
                    ),
                  ]),
              ],
            ),

            // Lista deslizable. Va antes del buscador para que éste quede encima
            // cuando la lista se estira.
            Positioned.fill(
              child: ExploreBottomList(
                places: _places,
                openNow: _openNow,
                distanceMeters: _distanceTo,
                onPlaceTap: _openPlaceDetail,
                onSurprise: _openDiscovery,
                onExtentChanged: (e) => _sheetExtent.value = e,
              ),
            ),

            // Buscador + avatar, interruptor Locales/Ahora y filtros.
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Column(
                  children: [
                    Row(children: [
                      Expanded(child: _SearchPill(onTap: _openSearchResults)),
                      const SizedBox(width: 8),
                      _ProfileAvatar(onTap: widget.onOpenProfile),
                    ]),
                    const SizedBox(height: 8),
                    ModeSwitch(
                        value: _mode,
                        onChanged: (m) => setState(() => _mode = m)),
                    // AHORA (Task 9): la franja "Hoy cerca de ti" va aquí
                    // cuando _mode == ExploreMode.now.
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 40,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          _TuneButton(
                              onTap: () => _showAdvancedFilters(context),
                              active: _hasAdvancedFilters),
                          const SizedBox(width: 8),
                          _FilterChip(
                            label: _activeCategoryName ?? 'Categoría',
                            icon: Icons.expand_more_rounded,
                            onTap: () => _showCategoryPicker(context),
                            active: _activeCategory != null,
                          ),
                          const SizedBox(width: 8),
                          _FilterChip(
                            label: 'Abierto ahora',
                            icon: Icons.schedule_outlined,
                            active: _openNow,
                            onTap: () {
                              setState(() => _openNow = !_openNow);
                              _loadPlaces();
                            },
                          ),
                          const SizedBox(width: 8),
                          _FilterChip(
                            label: _position != null
                                ? '${_radiusKm.toStringAsFixed(0)} km'
                                : 'Distancia',
                            icon: Icons.social_distance_outlined,
                            active: _position != null,
                            onTap: () => _showRadiusPicker(context),
                          ),
                        ],
                      ),
                    ),
                    if (_stats != null) ...[
                      const SizedBox(height: 8),
                      _ProgressPill(stats: _stats!),
                    ],
                    if (_locationIssue != null) ...[
                      const SizedBox(height: 10),
                      _LocationBanner(
                          issue: _locationIssue!, onFix: _fixLocation),
                    ],
                  ],
                ),
              ),
            ),

            // My-location FAB: sube y baja con la lista; se esconde si ésta
            // cubre media pantalla.
            ValueListenableBuilder<double>(
              valueListenable: _sheetExtent,
              builder: (context, extent, _) {
                if (extent > 0.5) return const SizedBox.shrink();
                return Positioned(
                  right: 16,
                  bottom: extent * constraints.maxHeight + 12,
                  child: FloatingActionButton(
                    heroTag: 'locate',
                    mini: true,
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.primary,
                    onPressed: () {
                      if (_position == null) {
                        _fixLocation();
                        return;
                      }
                      _mapController.move(
                          LatLng(_position!.latitude, _position!.longitude),
                          _mapController.camera.zoom);
                    },
                    child: const Icon(Icons.my_location_rounded),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCategoryPicker(BuildContext context) async {
    final result = await Navigator.of(context).push<String?>(
      MaterialPageRoute(
          builder: (_) => FilterScreen(
              categories: _categories, initialCategory: _activeCategory)),
    );
    if (!mounted) return;
    setState(() => _activeCategory = result);
    _loadPlaces();
  }

  static const _radiusOptions = [1.0, 2.0, 5.0, 10.0, 20.0, 50.0];

  Future<void> _showRadiusPicker(BuildContext context) async {
    if (_position == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Activa tu ubicación para filtrar por distancia.')),
      );
      return;
    }
    final result = await showModalBottomSheet<double>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadius.lg))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Distancia máxima', style: AppText.titleLg)),
            ),
            for (final km in _radiusOptions)
              ListTile(
                title: Text('${km.toStringAsFixed(0)} km a la redonda',
                    style: AppText.bodyLg),
                trailing: km == _radiusKm
                    ? const Icon(Icons.check_rounded, color: AppColors.primary)
                    : null,
                onTap: () => Navigator.of(context).pop(km),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _radiusKm = result);
    _loadPlaces();
  }

  Future<void> _showAdvancedFilters(BuildContext context) async {
    final result = await Navigator.of(context).push<AdvancedFilters>(
      MaterialPageRoute(
        builder: (_) => AdvancedFiltersScreen(
          categories: _categories,
          amenities: _amenities,
          latitude: _position?.latitude,
          longitude: _position?.longitude,
          initial: _currentFilters,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _activeCategory = result.category;
      _radiusKm = result.radiusKm;
      _priceMin = result.priceMin;
      _priceMax = result.priceMax;
      _priceLabel = result.priceLabel;
      _minRating = result.minRating;
      _amenitySlugs = result.amenitySlugs;
      _openNow = result.openNow;
    });
    _loadPlaces();
    _openSearchResults(filters: result);
  }
}

/// Buscador de arriba: toda la pastilla abre la búsqueda.
class _SearchPill extends StatelessWidget {
  final VoidCallback onTap;
  const _SearchPill({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppShadows.card,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(children: [
              const Icon(Icons.search_rounded,
                  color: AppColors.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text('¿Qué se te antoja?',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.bodyLg
                        .copyWith(color: AppColors.onSurfaceVariant)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Avatar de la cuenta; toca para ir a la pestaña Perfil. Sin [onTap] es solo
/// decorativo.
class _ProfileAvatar extends StatelessWidget {
  final VoidCallback? onTap;
  const _ProfileAvatar({this.onTap});

  @override
  Widget build(BuildContext context) {
    final url = context.watch<AuthProvider>().user?.avatarUrl;
    final hasPhoto = url != null && url.isNotEmpty;
    return Semantics(
      button: onTap != null,
      label: 'Abrir mi perfil',
      child: GestureDetector(
        key: const Key('explore-avatar'),
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.secondary,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: AppShadows.card,
            image: hasPhoto
                ? DecorationImage(
                    image: CachedNetworkImageProvider(url), fit: BoxFit.cover)
                : null,
          ),
          child: hasPhoto
              ? null
              : const Icon(Icons.person, size: 20, color: Colors.white),
        ),
      ),
    );
  }
}

/// Persistent (not a snackbar) because without location the whole nearby
/// search is degraded, and the user needs the fix within reach, not a
/// message that disappears after four seconds.
/// Level/XP bar + weekly streak: keeps progress visible on the screen users
/// open most, so there's always a "next milestone" in sight.
class _ProgressPill extends StatelessWidget {
  final GamificationStats stats;
  const _ProgressPill({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppShadows.card,
      ),
      child: Row(children: [
        Text('Nv ${stats.level}',
            style: const TextStyle(
                fontWeight: FontWeight.w700, color: AppColors.primary)),
        const SizedBox(width: 10),
        Expanded(
          child: LinearProgressIndicator(
            value: stats.nextLevelXp == 0
                ? 0
                : (stats.xp / stats.nextLevelXp).clamp(0.0, 1.0),
            minHeight: 8,
            borderRadius: BorderRadius.circular(8),
            color: AppColors.primary,
            backgroundColor: AppColors.primaryContainer,
          ),
        ),
        if (stats.weeklyStreak > 0) ...[
          const SizedBox(width: 10),
          Text('🔥 ${stats.weeklyStreak}',
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ]),
    );
  }
}

class _LocationBanner extends StatelessWidget {
  final _LocationIssue issue;
  final VoidCallback onFix;
  const _LocationBanner({required this.issue, required this.onFix});

  @override
  Widget build(BuildContext context) {
    final (message, action) = switch (issue) {
      _LocationIssue.serviceOff => (
          'Tu GPS está apagado. Actívalo para ver los huariques cerca de ti y filtrar por distancia.',
          'Activar'
        ),
      _LocationIssue.blocked => (
          'Bloqueaste el permiso de ubicación. Sin él no podemos mostrarte lo que tienes cerca.',
          'Ajustes'
        ),
      _LocationIssue.denied => (
          'Necesitamos tu ubicación para mostrarte huariques cerca de ti. Sin ella la búsqueda no funciona bien.',
          'Permitir'
        ),
      _LocationIssue.unavailable => (
          'No pudimos obtener tu ubicación. La búsqueda por cercanía no funcionará correctamente.',
          'Reintentar'
        ),
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: Row(children: [
        const Icon(Icons.location_off_rounded,
            size: 18, color: AppColors.primary),
        const SizedBox(width: 10),
        Expanded(child: Text(message, style: AppText.labelMd)),
        const SizedBox(width: 4),
        FilledButton(
          onPressed: onFix,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            textStyle: AppText.labelMd.copyWith(fontWeight: FontWeight.w700),
          ),
          child: Text(action),
        ),
      ]),
    );
  }
}

class _TuneButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool active;
  const _TuneButton({required this.onTap, this.active = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? AppColors.primary : AppColors.primaryContainer,
          shape: BoxShape.circle,
          border: Border.all(
              color: AppColors.primary.withValues(alpha: active ? 1 : 0.2)),
        ),
        child: Icon(Icons.tune_rounded,
            size: 20, color: active ? Colors.white : AppColors.primary),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback? onTap;

  const _FilterChip(
      {required this.label,
      required this.icon,
      this.active = false,
      this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: active ? AppColors.onSurface : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: active ? null : Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 6,
                offset: const Offset(0, 2))
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 16,
                color: active ? Colors.white : AppColors.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(label,
                style: AppText.labelMd.copyWith(
                    color: active ? Colors.white : AppColors.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

