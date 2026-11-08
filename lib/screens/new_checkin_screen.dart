import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import '../core/api_client.dart';
import '../core/app_theme.dart';
import '../core/models.dart';

/// Chips de opinión del check-in (el de restaurantes, el que da puntos).
const checkinChips = [
  '😋 Rico',
  '💸 Buen precio',
  '⚡ Rápido',
  '🫶 Buena atención'
];

/// Puntos que da el backend (`CheckinsService.create`): 10, más 5 con foto.
const checkinBasePoints = 10;
const checkinPhotoPoints = 5;
int checkinPoints({required bool hasPhoto}) =>
    checkinBasePoints + (hasPhoto ? checkinPhotoPoints : 0);

/// Largo del texto libre. El backend acepta 200 caracteres en el comentario
/// (`CreateCheckinDto`); con los 4 chips (55) y el " — " (3) sobran 142.
const checkinTextMax = 140;

/// El comentario que se envía: los chips van como texto al inicio, sin columna
/// nueva: `"😋 Rico · 💸 Buen precio — {texto}"`.
String buildCheckinComment(List<String> chips, String text) {
  final t = text.trim();
  if (chips.isEmpty) return t;
  final c = chips.join(' · ');
  return t.isEmpty ? c : '$c — $t';
}

class NewCheckinScreen extends StatefulWidget {
  final Place place;

  /// Las pruebas ponen un cliente, un GPS y una galería de mentira.
  final ApiClient? api;
  final Future<Position> Function()? locate;
  final Future<XFile?> Function()? pickPhoto;
  const NewCheckinScreen(
      {super.key, required this.place, this.api, this.locate, this.pickPhoto});

  @override
  State<NewCheckinScreen> createState() => _NewCheckinScreenState();
}

class _NewCheckinScreenState extends State<NewCheckinScreen> {
  late final ApiClient _api = widget.api ?? ApiClient();
  final _commentCtrl = TextEditingController();
  final _dishCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();

  @override
  void dispose() {
    _commentCtrl.dispose();
    _dishCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  int _rating = 0;
  final _chips = <String>{};
  String? _dish; // plato elegido en los chips
  bool _otro = false; // "+ Otro": el plato se escribe
  XFile? _photo;
  bool _submitting = false;
  bool _done = false;
  int _earnedPoints = 0;
  GamificationStats? _statsBefore;
  GamificationStats? _statsAfter;
  String? _error;

  Future<GamificationStats?> _statsOrNull() async {
    try {
      return await _api.getMyStats();
    } catch (_) {
      return null;
    }
  }

  Future<void> _pickPhoto() async {
    final file = await (widget.pickPhoto?.call() ??
        ImagePicker().pickImage(
            source: ImageSource.gallery, imageQuality: 80, maxWidth: 1600));
    if (file != null) setState(() => _photo = file);
  }

  /// Los platos del local (los de su ficha), sin repetir.
  List<String> get _dishes => {
        for (final d in widget.place.dishes)
          if (d.name.trim().isNotEmpty) d.name.trim()
      }.toList();

  /// El plato que se envía: el del chip, o el escrito si se eligió "+ Otro"
  /// (o si el local no tiene platos que mostrar).
  String get _dishName {
    final typed = _otro || _dishes.isEmpty;
    final name = (typed ? _dishCtrl.text : _dish ?? '').trim();
    return name.length > 100 ? name.substring(0, 100) : name; // tope del DTO
  }

  /// Los chips elegidos, siempre en el mismo orden.
  List<String> get _picked => [
        for (final c in checkinChips)
          if (_chips.contains(c)) c
      ];

  Future<Position> _locate() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw ApiException(
          400, 'Activa el permiso de ubicación para registrar tu visita.');
    }
    return Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(timeLimit: Duration(seconds: 20)));
  }

  Future<void> _submit() async {
    final price = num.tryParse(_priceCtrl.text.replaceAll(',', '.'));
    if (_priceCtrl.text.isNotEmpty &&
        (price == null || price < 0 || _dishName.isEmpty)) {
      setState(() => _error = 'Ingresa el plato y un precio válido.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final position = await (widget.locate ?? _locate)();
      // Best effort: the reward screen degrades gracefully without stats.
      _statsBefore = await _statsOrNull();
      String? photoUrl;
      if (_photo != null) {
        final bytes = await _photo!.readAsBytes();
        photoUrl = await _api.uploadImage(bytes, _photo!.name,
            mimeType: _photo!.mimeType);
      }
      await _api.createCheckin(
        placeId: widget.place.id,
        latitude: position.latitude,
        longitude: position.longitude,
        rating: _rating == 0 ? null : _rating,
        comment: buildCheckinComment(_picked, _commentCtrl.text),
        photoUrl: photoUrl,
        dishName: _dishName,
        dishPrice: price,
        isMocked: position.isMocked,
        accuracyMeters: position.accuracy,
      );
      final after = await _statsOrNull();
      if (!mounted) return;
      setState(() {
        _done = true;
        _statsAfter = after;
        _earnedPoints = (after != null && _statsBefore != null)
            ? after.xp - _statsBefore!.xp
            : checkinPoints(hasPhoto: photoUrl != null);
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            e is ApiException ? e.message : 'No se pudo crear el check-in');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_done) {
      return _RewardView(
        points: _earnedPoints,
        before: _statsBefore,
        after: _statsAfter,
        onDone: () => Navigator.of(context).pop(),
      );
    }

    final projectedPoints = checkinPoints(hasPhoto: _photo != null);

    final dishes = _dishes;
    final showDishField = _otro || dishes.isEmpty;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop()),
        title: const Text('Nuevo Check-in'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Chip(
              avatar:
                  const Icon(Icons.star_rounded, size: 16, color: Colors.white),
              label: Text('+$projectedPoints pts',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600)),
              backgroundColor: AppColors.primary,
              side: BorderSide.none,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('¿Qué tal ${widget.place.name}?',
                  textAlign: TextAlign.center, style: AppText.headlineMobile),
              if (widget.place.district?.district != null)
                Text(widget.place.district!.district!,
                    textAlign: TextAlign.center, style: AppText.bodyMd),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  final star = i + 1;
                  return IconButton(
                    onPressed: () => setState(() => _rating = star),
                    icon: Icon(
                      star <= _rating
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: AppColors.amber,
                      size: 38,
                    ),
                  );
                }),
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                children: [
                  for (final c in checkinChips)
                    _chip(
                        c,
                        _chips.contains(c),
                        () => setState(() => _chips.contains(c)
                            ? _chips.remove(c)
                            : _chips.add(c))),
                ],
              ),
              const SizedBox(height: 20),
              Text('¿Qué pediste?',
                  style: AppText.bodyLg.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, children: [
                for (final d in dishes)
                  _chip(
                      d,
                      !_otro && _dish == d,
                      () => setState(() {
                            _otro = false;
                            _dish = _dish == d ? null : d;
                          })),
                if (dishes.isNotEmpty)
                  _chip(
                      '+ Otro',
                      _otro,
                      () => setState(() {
                            _otro = !_otro;
                            _dish = null;
                            _dishCtrl.clear();
                          })),
              ]),
              if (showDishField)
                TextField(
                    controller: _dishCtrl,
                    maxLength: 100,
                    decoration: const InputDecoration(
                        labelText: '¿Qué pediste? (opcional)')),
              TextField(
                  controller: _priceCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Precio del plato S/ (opcional)')),
              const SizedBox(height: 14),
              _photo != null
                  ? Stack(children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.file(File(_photo!.path),
                            height: 160,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const SizedBox(height: 160)),
                      ),
                      Positioned(
                        right: 6,
                        top: 6,
                        child: IconButton(
                          style: IconButton.styleFrom(
                              backgroundColor: Colors.black54),
                          icon: const Icon(Icons.close,
                              color: Colors.white, size: 18),
                          onPressed: () => setState(() => _photo = null),
                        ),
                      ),
                    ])
                  : GestureDetector(
                      onTap: _pickPhoto,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.add_a_photo_outlined,
                                color: AppColors.onSurfaceVariant),
                            const SizedBox(width: 8),
                            Text.rich(
                                const TextSpan(children: [
                                  TextSpan(text: 'Agrega foto · '),
                                  TextSpan(
                                      text: '+$checkinPhotoPoints pts',
                                      style: TextStyle(
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.w700)),
                                ]),
                                style: AppText.bodyMd),
                          ],
                        ),
                      ),
                    ),
              const SizedBox(height: 14),
              TextField(
                controller: _commentCtrl,
                maxLength: checkinTextMax,
                maxLines: 3,
                decoration: const InputDecoration(
                    hintText: 'Cuéntale a la comunidad… (opcional)'),
              ),
              if (_error != null)
                Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? null
                    : const Icon(Icons.pin_drop_rounded, size: 18),
                label: Text(_submitting ? 'Enviando...' : 'Publicar check-in'),
              ),
              const SizedBox(height: 10),
              Center(
                  child: Text('Publicarás esta reseña en tu feed de comunidad.',
                      style: AppText.labelMd)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, bool on, VoidCallback onTap) => FilterChip(
        label: Text(label),
        selected: on,
        showCheckmark: false,
        onSelected: (_) => onTap(),
        backgroundColor: Colors.white,
        selectedColor: AppColors.onSurface,
        side: BorderSide(color: on ? AppColors.onSurface : AppColors.border),
        shape: const StadiumBorder(),
        labelStyle: TextStyle(
            color: on ? Colors.white : AppColors.onSurface,
            fontWeight: FontWeight.w600,
            fontSize: 13),
      );
}

/// Post check-in celebration: XP earned, progress to the next level and the
/// weekly streak — the moment that makes the next visit feel worth it.
class _RewardView extends StatelessWidget {
  final int points;
  final GamificationStats? before;
  final GamificationStats? after;
  final VoidCallback onDone;
  const _RewardView(
      {required this.points,
      required this.before,
      required this.after,
      required this.onDone});

  @override
  Widget build(BuildContext context) {
    final a = after;
    final leveledUp = a != null && before != null && a.level > before!.level;
    final streakGrew =
        a != null && before != null && a.weeklyStreak > before!.weeklyStreak;
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.celebration_rounded,
                  color: AppColors.primary, size: 64),
              const SizedBox(height: 12),
              Text(leveledUp ? '¡Subiste de nivel!' : '¡Check-in registrado!',
                  textAlign: TextAlign.center, style: AppText.headlineMobile),
              const SizedBox(height: 4),
              Text('+$points XP',
                  textAlign: TextAlign.center,
                  style: AppText.titleLg.copyWith(color: AppColors.primary)),
              if (a != null) ...[
                const SizedBox(height: 24),
                LinearProgressIndicator(
                  value: a.nextLevelXp == 0
                      ? 0
                      : (a.xp / a.nextLevelXp).clamp(0.0, 1.0),
                  minHeight: 10,
                  borderRadius: BorderRadius.circular(8),
                  color: AppColors.primary,
                  backgroundColor: AppColors.primaryContainer,
                ),
                const SizedBox(height: 6),
                Text(
                    'Nivel ${a.level} · te faltan ${(a.nextLevelXp - a.xp).clamp(0, a.nextLevelXp)} XP para el siguiente',
                    textAlign: TextAlign.center,
                    style: AppText.bodyMd),
                if (a.weeklyStreak > 0) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                        color: const Color(0xFFFFF3D6),
                        borderRadius: BorderRadius.circular(16)),
                    child: Text(
                        streakGrew
                            ? '🔥 ¡Racha de ${a.weeklyStreak} semanas seguidas!'
                            : '🔥 Racha: ${a.weeklyStreak} semanas seguidas',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Color(0xFF8A6100),
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ],
              const SizedBox(height: 32),
              FilledButton(onPressed: onDone, child: const Text('Listo')),
            ],
          ),
        ),
      ),
    );
  }
}
