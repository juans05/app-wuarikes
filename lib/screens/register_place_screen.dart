import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import '../core/api_client.dart';
import '../core/app_theme.dart';
import '../core/map_config.dart';
import '../core/models.dart';

const _defaultCenter = LatLng(-12.1211, -77.0296);
const _maxPhotos = 6;
const _maxMenuPhotos = 6;

class RegisterPlaceScreen extends StatefulWidget {
  const RegisterPlaceScreen({super.key});

  @override
  State<RegisterPlaceScreen> createState() => _RegisterPlaceScreenState();
}

class _RegisterPlaceScreenState extends State<RegisterPlaceScreen> {
  final ApiClient _api = ApiClient();
  final MapController _mapController = MapController();
  LatLng _center = _defaultCenter;
  bool _locationConfirmed = false;
  bool _mapReady = false;
  bool _confirming = false;

  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _openHoursCtrl = TextEditingController();
  List<Category> _categories = [];
  String? _categoryId;
  int _priceRange = 1; // 1 = $, 2 = $$, 3 = $$$
  final List<XFile> _photos = [];
  final List<XFile> _menuPhotos = [];
  XFile? _video;
  List<Amenity> _amenityOptions = [];
  final Set<String> _amenities = {};
  bool _submitting = false;
  String? _error;

  List<String> _departments = [];
  List<String> _provinces = [];
  List<String> _districts = [];
  String? _department;
  String? _province;
  String? _district;

  @override
  void initState() {
    super.initState();
    _api.getCategories().then((c) => mounted ? setState(() => _categories = c) : null).catchError((_) {});
    _api.getAmenities().then((a) => mounted ? setState(() => _amenityOptions = a) : null).catchError((_) {});
    _api.getDepartments().then((d) => mounted ? setState(() => _departments = d) : null).catchError((_) {});
    _resolveInitialLocation();
  }

  Future<void> _onDepartmentChanged(String? department) async {
    setState(() {
      _department = department;
      _province = null;
      _district = null;
      _provinces = [];
      _districts = [];
    });
    if (department == null) return;
    try {
      final provinces = await _api.getProvinces(department);
      if (mounted) setState(() => _provinces = provinces);
    } catch (_) {}
  }

  Future<void> _onProvinceChanged(String? province) async {
    setState(() {
      _province = province;
      _district = null;
      _districts = [];
    });
    if (province == null || _department == null) return;
    try {
      final districts = await _api.getDistrictsByProvince(_department!, province);
      if (mounted) setState(() => _districts = districts);
    } catch (_) {}
  }

  /// Asks the user before sending them to a system settings screen, since
  /// leaving the app mid-form is disruptive if they didn't ask for it.
  Future<void> _offerToEnable(String title, String message, Future<bool> Function() open) async {
    if (!mounted) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Ahora no')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Activar')),
        ],
      ),
    );
    if (accepted == true) await open();
  }

  Future<Position?> _resolveCurrentPosition({bool prompt = false}) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      if (prompt) {
        await _offerToEnable(
          'Activa la ubicación',
          'Tu GPS está apagado, por eso el mapa no puede centrarse donde estás. ¿Lo activamos?',
          Geolocator.openLocationSettings,
        );
      }
      return null;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      if (prompt) {
        await _offerToEnable(
          'Permiso de ubicación',
          'Bloqueaste el permiso de ubicación para Wuarikes. Ábrelo en Ajustes para centrar el mapa donde estás.',
          Geolocator.openAppSettings,
        );
      }
      return null;
    }
    if (permission == LocationPermission.denied) return null;
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  Future<void> _goToCurrentPosition({bool prompt = false}) async {
    try {
      final pos = await _resolveCurrentPosition(prompt: prompt);
      if (pos == null || !mounted) return;
      setState(() {
        _center = LatLng(pos.latitude, pos.longitude);
        _locationConfirmed = false;
      });
      if (_mapReady) _mapController.move(_center, 16);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo obtener tu ubicación.')),
        );
      }
    }
  }

  Future<void> _resolveInitialLocation() => _goToCurrentPosition(prompt: true);

  /// Accent- and case-insensitive, and tolerant of the "Provincia de X" /
  /// "Distrito de X" wrappers Mapbox sometimes returns.
  static String _norm(String value) {
    const accented = 'áàäâãéèëêíìïîóòöôõúùüûñ';
    const plain = 'aaaaaeeeeiiiiooooouuuun';
    var out = value.toLowerCase().trim();
    for (var i = 0; i < accented.length; i++) {
      out = out.replaceAll(accented[i], plain[i]);
    }
    for (final prefix in ['departamento de ', 'provincia de ', 'distrito de ', 'region ']) {
      if (out.startsWith(prefix)) out = out.substring(prefix.length);
    }
    return out.trim();
  }

  static String? _matchIn(List<String> options, List<String> candidates) {
    for (final candidate in candidates) {
      final target = _norm(candidate);
      for (final option in options) {
        if (_norm(option) == target) return option;
      }
    }
    return null;
  }

  /// Reverse-geocodes the pin and fills address + ubigeo dropdowns. Only
  /// assigns values that exist in the backend's lists — a dropdown whose value
  /// isn't among its items throws.
  Future<void> _fillAddressFromPin() async {
    final uri = Uri.parse(
      'https://api.mapbox.com/search/geocode/v6/reverse'
      '?longitude=${_center.longitude}&latitude=${_center.latitude}'
      '&language=es&access_token=$mapboxAccessToken',
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) return;
    final features = jsonDecode(response.body)['features'] as List?;
    if (features == null || features.isEmpty) return;

    final context = (features.first['properties']?['context'] as Map<String, dynamic>?) ?? {};
    String? level(String key) => (context[key] as Map<String, dynamic>?)?['name'] as String?;

    final street = level('address') ?? level('street');
    if (street != null && _addressCtrl.text.trim().isEmpty) _addressCtrl.text = street;

    // Mapbox doesn't map its levels onto Peru's ubigeo consistently, so every
    // level is a candidate and the backend lists decide which one fits where.
    final candidates = ['region', 'district', 'place', 'locality', 'neighborhood']
        .map(level)
        .whereType<String>()
        .toList();

    final department = _matchIn(_departments, candidates);
    if (department == null) return;
    await _onDepartmentChanged(department);

    final province = _matchIn(_provinces, candidates);
    if (province == null) return;
    await _onProvinceChanged(province);

    final district = _matchIn(_districts, candidates);
    if (district != null && mounted) setState(() => _district = district);
  }

  Future<void> _confirmLocation() async {
    setState(() {
      _locationConfirmed = true;
      _confirming = true;
    });
    try {
      await _fillAddressFromPin();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No pudimos completar la dirección sola. Complétala a mano.')),
        );
      }
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  Future<void> _pickPhoto(List<XFile> target, int max) async {
    if (target.length >= max) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (context) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined, color: AppColors.primary),
            title: const Text('Tomar foto'),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined, color: AppColors.primary),
            title: const Text('Elegir de galería'),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
        ]),
      ),
    );
    if (source == null) return;

    final remaining = max - target.length;
    if (source == ImageSource.gallery) {
      final files = await ImagePicker().pickMultiImage(imageQuality: 80, maxWidth: 1600, limit: remaining);
      if (files.isNotEmpty && mounted) setState(() => target.addAll(files.take(remaining)));
    } else {
      final file = await ImagePicker().pickImage(source: source, imageQuality: 80, maxWidth: 1600);
      if (file != null && mounted) setState(() => target.add(file));
    }
  }

  void _removePhoto(int index) {
    setState(() => _photos.removeAt(index));
  }

  void _removeMenuPhoto(int index) {
    setState(() => _menuPhotos.removeAt(index));
  }

  Future<void> _pickVideo() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (context) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.videocam_outlined, color: AppColors.primary),
            title: const Text('Grabar video'),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.video_library_outlined, color: AppColors.primary),
            title: const Text('Elegir de galería'),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
        ]),
      ),
    );
    if (source == null) return;
    final file = await ImagePicker().pickVideo(source: source, maxDuration: const Duration(seconds: 60));
    if (file == null || !mounted) return;
    final size = await file.length();
    if (size > 20 * 1024 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('El video no puede pesar más de 20MB.')),
        );
      }
      return;
    }
    setState(() => _video = file);
  }

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty || _categoryId == null || _district == null) {
      setState(() => _error = 'Completa nombre, categoría y distrito.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final photoUrls = <String>[];
      for (final photo in _photos) {
        final bytes = await photo.readAsBytes();
        photoUrls.add(await _api.uploadImage(bytes, photo.name, mimeType: photo.mimeType));
      }
      final menuImageUrls = <String>[];
      for (final photo in _menuPhotos) {
        final bytes = await photo.readAsBytes();
        menuImageUrls.add(await _api.uploadImage(bytes, photo.name, mimeType: photo.mimeType));
      }
      String? videoUrl;
      if (_video != null) {
        final bytes = await _video!.readAsBytes();
        videoUrl = await _api.uploadVideo(bytes, _video!.name, mimeType: _video!.mimeType);
      }
      await _api.submitPlace(
        name: _nameCtrl.text.trim(),
        categoryId: _categoryId!,
        district: _district!,
        address: _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
        latitude: _center.latitude,
        longitude: _center.longitude,
        coverImageUrl: photoUrls.isEmpty ? null : photoUrls.first,
        photoUrls: photoUrls,
        openHoursText: _openHoursCtrl.text.trim().isEmpty ? null : _openHoursCtrl.text.trim(),
        menuImageUrls: menuImageUrls,
        videoUrl: videoUrl,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('¡Gracias! Tu huarique quedó enviado para revisión.')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() => _error = e is ApiException ? e.message : 'No se pudo enviar el lugar. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.of(context).pop()),
        title: const Text('Nuevo Huarique'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                const Icon(Icons.location_on_outlined, color: AppColors.primary, size: 18),
                const SizedBox(width: 6),
                Text('Ubicación', style: AppText.titleLg),
              ]),
              const SizedBox(height: 8),
              Stack(
                alignment: Alignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    child: SizedBox(
                      height: 200,
                      child: FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: _center,
                          initialZoom: 15,
                          interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                          onMapReady: () {
                            _mapReady = true;
                            if (_center != _defaultCenter) _mapController.move(_center, 16);
                          },
                          onPositionChanged: (pos, hasGesture) {
                            _center = pos.center;
                            if (hasGesture) setState(() => _locationConfirmed = false);
                          },
                        ),
                        children: [buildMapboxTileLayer()],
                      ),
                    ),
                  ),
                  const Icon(Icons.restaurant_rounded, color: AppColors.primary, size: 34, shadows: [Shadow(color: Colors.black26, blurRadius: 6)]),
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: FloatingActionButton.small(
                      heroTag: 'locateNewPlace',
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.primary,
                      onPressed: () => _goToCurrentPosition(prompt: true),
                      child: const Icon(Icons.my_location_rounded),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: _confirming ? null : _confirmLocation,
                style: OutlinedButton.styleFrom(
                  backgroundColor: _locationConfirmed ? AppColors.primaryContainer : null,
                ),
                child: _confirming
                    ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                        const SizedBox(width: 10),
                        Text('Buscando dirección...', style: AppText.bodyMd),
                      ])
                    : Text(_locationConfirmed ? 'Ubicación confirmada ✓' : 'Confirmar ubicación'),
              ),
              const SizedBox(height: 24),
              Row(children: [
                const Icon(Icons.edit_note_rounded, color: AppColors.primary, size: 18),
                const SizedBox(width: 6),
                Text('Información básica', style: AppText.titleLg),
              ]),
              const SizedBox(height: 12),
              Text('Nombre del lugar', style: AppText.bodyMd.copyWith(color: AppColors.onSurface, fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
              TextField(controller: _nameCtrl, decoration: const InputDecoration(hintText: 'Ej: El Rinconcito del Sabor')),
              const SizedBox(height: 14),
              Text('Departamento', style: AppText.bodyMd.copyWith(color: AppColors.onSurface, fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _department,
                hint: const Text('Selecciona uno'),
                items: _departments.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                onChanged: _onDepartmentChanged,
              ),
              const SizedBox(height: 14),
              Text('Provincia', style: AppText.bodyMd.copyWith(color: AppColors.onSurface, fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _province,
                hint: const Text('Selecciona una'),
                items: _provinces.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                onChanged: _department == null ? null : _onProvinceChanged,
              ),
              const SizedBox(height: 14),
              Text('Distrito', style: AppText.bodyMd.copyWith(color: AppColors.onSurface, fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _district,
                hint: const Text('Selecciona uno'),
                items: _districts.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                onChanged: _province == null ? null : (v) => setState(() => _district = v),
              ),
              const SizedBox(height: 14),
              Text('Dirección (opcional)', style: AppText.bodyMd.copyWith(color: AppColors.onSurface, fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
              TextField(controller: _addressCtrl, decoration: const InputDecoration(hintText: 'Ej: Av. José Larco 1232')),
              const SizedBox(height: 14),
              Text('Horario (opcional)', style: AppText.bodyMd.copyWith(color: AppColors.onSurface, fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
              TextField(controller: _openHoursCtrl, decoration: const InputDecoration(hintText: 'Ej: 12:00 PM - 10:00 PM')),
              const SizedBox(height: 14),
              Text('Categoría', style: AppText.bodyMd.copyWith(color: AppColors.onSurface, fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _categoryId,
                hint: const Text('Selecciona una'),
                items: _categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                onChanged: (v) => setState(() => _categoryId = v),
              ),
              const SizedBox(height: 14),
              Text('Rango de precio', style: AppText.bodyMd.copyWith(color: AppColors.onSurface, fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
              Row(
                children: [1, 2, 3].map((v) {
                  final selected = _priceRange == v;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _priceRange = v),
                      child: Container(
                        margin: EdgeInsets.only(right: v == 3 ? 0 : 8),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: selected ? AppColors.primary : const Color(0xFFF3F3F3),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: Text(r'$' * v, style: TextStyle(color: selected ? Colors.white : AppColors.onSurfaceVariant, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              Row(children: [
                const Icon(Icons.add_a_photo_outlined, color: AppColors.primary, size: 18),
                const SizedBox(width: 6),
                Text('Fotos (hasta $_maxPhotos)', style: AppText.titleLg),
              ]),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < _photos.length; i++)
                    Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.file(File(_photos[i].path), width: 100, height: 100, fit: BoxFit.cover),
                        ),
                        if (i == 0)
                          Positioned(
                            left: 4,
                            bottom: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                              child: const Text('Portada', style: TextStyle(color: Colors.white, fontSize: 10)),
                            ),
                          ),
                        Positioned(
                          right: -6,
                          top: -6,
                          child: IconButton(
                            icon: const Icon(Icons.cancel, color: Colors.black87, size: 22),
                            onPressed: () => _removePhoto(i),
                          ),
                        ),
                      ],
                    ),
                  if (_photos.length < _maxPhotos)
                    GestureDetector(
                      onTap: () => _pickPhoto(_photos, _maxPhotos),
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.outline)),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.upload_file_rounded, color: AppColors.primary, size: 24),
                            const SizedBox(height: 4),
                            Text('Agregar', style: AppText.labelMd),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Row(children: [
                const Icon(Icons.menu_book_outlined, color: AppColors.primary, size: 18),
                const SizedBox(width: 6),
                Text('Fotos de la carta (opcional, hasta $_maxMenuPhotos)', style: AppText.titleLg),
              ]),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < _menuPhotos.length; i++)
                    Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.file(File(_menuPhotos[i].path), width: 100, height: 100, fit: BoxFit.cover),
                        ),
                        Positioned(
                          right: -6,
                          top: -6,
                          child: IconButton(
                            icon: const Icon(Icons.cancel, color: Colors.black87, size: 22),
                            onPressed: () => _removeMenuPhoto(i),
                          ),
                        ),
                      ],
                    ),
                  if (_menuPhotos.length < _maxMenuPhotos)
                    GestureDetector(
                      onTap: () => _pickPhoto(_menuPhotos, _maxMenuPhotos),
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.outline)),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.upload_file_rounded, color: AppColors.primary, size: 24),
                            const SizedBox(height: 4),
                            Text('Agregar', style: AppText.labelMd),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Row(children: [
                const Icon(Icons.videocam_outlined, color: AppColors.primary, size: 18),
                const SizedBox(width: 6),
                Text('Video (opcional)', style: AppText.titleLg),
              ]),
              const SizedBox(height: 8),
              if (_video != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.outline)),
                  child: Row(children: [
                    const Icon(Icons.movie_outlined, color: AppColors.primary, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_video!.name, overflow: TextOverflow.ellipsis)),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => setState(() => _video = null),
                    ),
                  ]),
                )
              else
                GestureDetector(
                  onTap: _pickVideo,
                  child: Container(
                    height: 64,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.outline)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.videocam_outlined, color: AppColors.primary, size: 22),
                        const SizedBox(width: 8),
                        Text('Subir un video del local', style: AppText.bodyMd.copyWith(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              Row(children: [
                const Icon(Icons.checklist_rounded, color: AppColors.primary, size: 18),
                const SizedBox(width: 6),
                Text('Extras / Amenities', style: AppText.titleLg),
              ]),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _amenityOptions.map((a) {
                  final selected = _amenities.contains(a.id);
                  return FilterChip(
                    label: Text(a.name),
                    selected: selected,
                    onSelected: (v) => setState(() => v ? _amenities.add(a.id) : _amenities.remove(a.id)),
                    selectedColor: AppColors.primaryContainer,
                    checkmarkColor: AppColors.primary,
                  );
                }).toList(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting ? null : const Icon(Icons.send_rounded, size: 18),
                label: Text(_submitting ? 'Guardando...' : 'Guardar Huarique'),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
