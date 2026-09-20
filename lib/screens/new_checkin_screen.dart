import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import '../core/api_client.dart';
import '../core/app_theme.dart';
import '../core/models.dart';

class NewCheckinScreen extends StatefulWidget {
  final Place place;
  const NewCheckinScreen({super.key, required this.place});

  @override
  State<NewCheckinScreen> createState() => _NewCheckinScreenState();
}

class _NewCheckinScreenState extends State<NewCheckinScreen> {
  final ApiClient _api = ApiClient();
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
  XFile? _photo;
  bool _submitting = false;
  bool _done = false;
  int _earnedPoints = 0;
  String? _error;

  Future<void> _pickPhoto() async {
    final file = await ImagePicker().pickImage(
        source: ImageSource.gallery, imageQuality: 80, maxWidth: 1600);
    if (file != null) setState(() => _photo = file);
  }

  Future<void> _submit() async {
    final price = num.tryParse(_priceCtrl.text.replaceAll(',', '.'));
    if (_priceCtrl.text.isNotEmpty &&
        (price == null || price < 0 || _dishCtrl.text.trim().isEmpty)) {
      setState(() => _error = 'Ingresa el plato y un precio válido.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied)
        permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw ApiException(
            400, 'Activa el permiso de ubicación para registrar tu visita.');
      }
      final position = await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(timeLimit: Duration(seconds: 20)));
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
        comment:
            _commentCtrl.text.trim().isEmpty ? null : _commentCtrl.text.trim(),
        photoUrl: photoUrl,
        dishName: _dishCtrl.text.trim(),
        dishPrice: price,
      );
      if (!mounted) return;
      setState(() {
        _done = true;
        _earnedPoints = 10 + (photoUrl != null ? 5 : 0);
      });
      await Future.delayed(const Duration(milliseconds: 1200));
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted)
        setState(() => _error =
            e is ApiException ? e.message : 'No se pudo crear el check-in');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_done) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.celebration_rounded,
                  color: AppColors.primary, size: 56),
              const SizedBox(height: 12),
              Text('¡Check-in registrado!', style: AppText.headlineMobile),
              const SizedBox(height: 4),
              Text('Ganaste +$_earnedPoints puntos', style: AppText.bodyMd),
            ],
          ),
        ),
      );
    }

    final projectedPoints = 10 + (_photo != null ? 5 : 0);

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
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: AppColors.border)),
                child: Row(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: widget.place.coverImageUrl != null
                        ? Image.network(widget.place.coverImageUrl!,
                            width: 56, height: 56, fit: BoxFit.cover)
                        : Container(
                            width: 56,
                            height: 56,
                            color: AppColors.primaryContainer),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.place.name,
                            style: AppText.titleLg.copyWith(
                                color: AppColors.primary, fontSize: 17)),
                        Text(widget.place.district?.district ?? '',
                            style: AppText.bodyMd),
                      ],
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 24),
              Center(
                  child: Text('¿QUÉ TAL ESTUVO TU EXPERIENCIA?',
                      style: AppText.labelMd)),
              const SizedBox(height: 8),
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
              const SizedBox(height: 20),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('FOTOS DEL WUARIKE', style: AppText.labelMd),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: const Color(0xFFFFF3D6),
                      borderRadius: BorderRadius.circular(12)),
                  child: const Text('+15 pts con foto',
                      style: TextStyle(
                          color: Color(0xFF8A6100),
                          fontWeight: FontWeight.w600,
                          fontSize: 12)),
                ),
              ]),
              const SizedBox(height: 8),
              _photo != null
                  ? Stack(children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.file(File(_photo!.path),
                            height: 160,
                            width: double.infinity,
                            fit: BoxFit.cover),
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
                        height: 110,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: AppColors.outline,
                              style: BorderStyle.solid),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.add_a_photo_outlined,
                                color: AppColors.onSurfaceVariant),
                            const SizedBox(height: 4),
                            Text('Subir', style: AppText.bodyMd),
                          ],
                        ),
                      ),
                    ),
              const SizedBox(height: 20),
              Text('TU COMENTARIO', style: AppText.labelMd),
              const SizedBox(height: 8),
              TextField(
                controller: _commentCtrl,
                maxLength: 140,
                maxLines: 4,
                decoration: const InputDecoration(
                    hintText: 'Cuéntanos qué pediste y si lo recomendarías...'),
              ),
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
              if (_error != null)
                Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? null
                    : const Icon(Icons.send_rounded, size: 18),
                label: Text(_submitting ? 'Enviando...' : 'Publicar Check-in'),
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
}
