import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/now_api.dart';
import '../../core/now_location.dart';
import '../../core/now_models.dart';
import '../../state/auth_provider.dart';
import '../login_screen.dart';
import 'now_layer.dart' show nowPostPublished;

/// Elige foto o video. Solo para pruebas se cambia por uno de mentira.
typedef NowMediaPicker = Future<XFile?> Function(ImageSource source,
    {required bool video});

Future<XFile?> _pickWithImagePicker(ImageSource source,
        {required bool video}) =>
    video
        ? ImagePicker()
            .pickVideo(source: source, maxDuration: const Duration(seconds: 15))
        : ImagePicker()
            .pickImage(source: source, imageQuality: 85, maxWidth: 1600);

const _maxPhotoBytes = 10 * 1024 * 1024;
const _maxVideoBytes = 20 * 1024 * 1024;

/// Mensaje para el usuario según lo que respondió el backend al publicar.
/// Tiempo máximo para publicar: con la red colgada la hoja no queda bloqueada.
Duration publishTimeout(String kind) => switch (kind) {
      'video' => const Duration(seconds: 120),
      'photo' => const Duration(seconds: 60),
      _ => const Duration(seconds: 20),
    };

String publishErrorMessage(Object error) {
  if (error is TimeoutException) {
    // El servidor pudo recibirla igual: mejor revisar antes de duplicarla.
    return 'La conexión está muy lenta. Revisa "Mis publicaciones" antes de reintentar: puede que sí se haya publicado.';
  }
  if (error is ApiException) {
    switch (error.status) {
      case 429:
        return 'Llegaste al límite de 5 publicaciones por hora';
      case 413:
        return 'El archivo es muy grande';
      case 400:
        return 'Revisa la foto o el texto';
      case 401:
        return 'Tu sesión venció. Inicia sesión de nuevo.';
    }
  }
  return 'No se pudo publicar. Revisa tu conexión e inténtalo de nuevo.';
}

/// Hoja "¿Qué está pasando?" del ＋. Un invitado va primero a iniciar sesión:
/// sin sesión no se publica y no se llama a la API.
///
/// [api], [locate] y [pick] solo se cambian en pruebas.
Future<void> showPublishNowSheet(BuildContext context,
    {ApiClient? api, NowLocator? locate, NowMediaPicker? pick}) async {
  if (!context.read<AuthProvider>().isLoggedIn) {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const LoginScreen()));
    if (!context.mounted || !context.read<AuthProvider>().isLoggedIn) return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.lg))),
    builder: (_) => _PublishSheet(
      api: api ?? context.read<AuthProvider>().api,
      locate: locate ?? currentNowPosition,
      pick: pick ?? _pickWithImagePicker,
    ),
  );
}

class _PublishSheet extends StatefulWidget {
  final ApiClient api;
  final NowLocator locate;
  final NowMediaPicker pick;
  const _PublishSheet(
      {required this.api, required this.locate, required this.pick});

  @override
  State<_PublishSheet> createState() => _PublishSheetState();
}

class _PublishSheetState extends State<_PublishSheet> {
  final _text = TextEditingController();

  /// 'photo' | 'video' | 'text'
  String _kind = 'photo';

  /// 'all' | 'followers' | 'friends'
  String _visibility = 'all';

  Uint8List? _bytes;
  String _fileName = '';
  String? _fileMime;

  Position? _position;
  bool _locating = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _locate();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _locate() async {
    setState(() => _locating = true);
    final p = await widget.locate();
    if (!mounted) return;
    setState(() {
      _position = p;
      _locating = false;
    });
  }

  void _setKind(String kind) {
    if (kind == _kind) return;
    setState(() {
      _kind = kind;
      // La foto no sirve de video ni al revés: se suelta el archivo completo.
      _bytes = null;
      _fileName = '';
      _fileMime = null;
      _error = null;
    });
  }

  Future<void> _chooseMedia() async {
    final video = _kind == 'video';
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: Icon(
                video ? Icons.videocam_outlined : Icons.photo_camera_outlined,
                color: AppColors.primary),
            title: Text(video ? 'Grabar video' : 'Tomar foto'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined,
                color: AppColors.primary),
            title: const Text('Elegir de la galería'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
        ]),
      ),
    );
    if (source == null || !mounted) return;
    try {
      final file = await widget.pick(source, video: video);
      if (file == null || !mounted) return;
      if (await file.length() > (video ? _maxVideoBytes : _maxPhotoBytes)) {
        if (mounted) setState(() => _error = 'El archivo es muy grande');
        return;
      }
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _fileName = file.name;
        _fileMime =
            nowMimeType(file.name, video: video, declared: file.mimeType);
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo abrir el archivo');
    }
  }

  Future<void> _publish() async {
    if (_busy) return;
    final text = _text.text.trim();
    final String? problem;
    if (_kind == 'text' && text.isEmpty) {
      problem = 'Escribe algo para publicar';
    } else if (_kind != 'text' && _bytes == null) {
      problem = _kind == 'photo'
          ? 'Elige una foto o cambia a Texto'
          : 'Elige un video o cambia a Texto';
    } else {
      problem = null;
    }
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      // Siempre la posición de ahora: la de al abrir la hoja pudo quedar vieja
      // (se publica donde uno está, no donde estaba).
      final here = await widget.locate();
      if (!mounted) return;
      setState(() => _position = here);
      if (here == null) {
        setState(() => _error = 'Activa tu ubicación para publicar');
        return;
      }
      if (here.isMocked) {
        setState(() => _error = nowMockedLocationMessage);
        return;
      }
      final post = await widget.api.createNowPost(
        kind: _kind,
        text: text,
        visibility: _visibility,
        latitude: here.latitude,
        longitude: here.longitude,
        bytes: _kind == 'text' ? null : _bytes,
        filename: _fileName.isEmpty ? null : _fileName,
        mimeType: _fileMime,
      ).timeout(publishTimeout(_kind));
      // Si la hoja ya se cerró por arrastre, no sacar la pantalla de debajo.
      if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) navigator.pop();
      messenger
          .showSnackBar(const SnackBar(content: Text('Publicado. Dura 24 h.')));
      nowPostPublished.value = post;
    } catch (e) {
      if (mounted) setState(() => _error = publishErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = context.watch<AuthProvider>().user?.fullName ?? '';
    final media = _kind != 'text';
    // Mientras se publica la hoja no se cierra: si no, la publicación sale
    // sin que el usuario vea el resultado ni un error.
    return PopScope(
      canPop: !_busy,
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(4))),
              ),
              const SizedBox(height: 12),
              Text('¿Qué está pasando?', style: AppText.titleLg),
              const SizedBox(height: 10),
              Row(children: [
                _Option(
                    key: const Key('kind-photo'),
                    label: '📷 Foto',
                    selected: _kind == 'photo',
                    onTap: () => _setKind('photo')),
                const SizedBox(width: 8),
                _Option(
                    key: const Key('kind-video'),
                    label: '🎥 Video',
                    selected: _kind == 'video',
                    onTap: () => _setKind('video')),
                const SizedBox(width: 8),
                _Option(
                    key: const Key('kind-text'),
                    label: '✏️ Texto',
                    selected: _kind == 'text',
                    onTap: () => _setKind('text')),
              ]),
              if (media) ...[
                const SizedBox(height: 10),
                _MediaTile(
                  video: _kind == 'video',
                  bytes: _bytes,
                  fileName: _fileName,
                  onTap: _busy ? null : _chooseMedia,
                ),
              ],
              const SizedBox(height: 10),
              TextField(
                key: const Key('now-text'),
                controller: _text,
                maxLength: 500,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  counterText: '',
                  hintText: media
                      ? 'Cuéntalo en pocas palabras (opcional)'
                      : '¿Alguien sabe qué evento hay en la plaza?',
                ),
              ),
              const SizedBox(height: 8),
              Text('¿QUIÉN LO VE?',
                  style: AppText.labelMd.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Row(children: [
                _Option(
                    key: const Key('vis-all'),
                    label: '🌎 Todos',
                    selected: _visibility == 'all',
                    onTap: () => setState(() => _visibility = 'all')),
                const SizedBox(width: 8),
                _Option(
                    key: const Key('vis-followers'),
                    label: '👤 Seguidores',
                    selected: _visibility == 'followers',
                    onTap: () => setState(() => _visibility = 'followers')),
                const SizedBox(width: 8),
                _Option(
                    key: const Key('vis-friends'),
                    label: '👥 Amigos',
                    selected: _visibility == 'friends',
                    onTap: () => setState(() => _visibility = 'friends')),
              ]),
              const SizedBox(height: 10),
              _LocationNote(
                  locating: _locating,
                  located: _position != null,
                  onRetry: _locate),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    key: const Key('publish-error'),
                    style: AppText.bodyMd.copyWith(
                        color: AppColors.primary, fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('publish-button'),
                  onPressed: _busy ? null : _publish,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text('Publicar como @$name',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Option(
      {super.key,
      required this.label,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.primaryContainer : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: selected ? AppColors.primary : AppColors.border,
                width: 1.5),
          ),
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected ? AppColors.primary : AppColors.onSurface)),
        ),
      ),
    );
  }
}

class _MediaTile extends StatelessWidget {
  final bool video;
  final Uint8List? bytes;
  final String fileName;
  final VoidCallback? onTap;
  const _MediaTile(
      {required this.video,
      required this.bytes,
      required this.fileName,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final b = bytes;
    return GestureDetector(
      key: const Key('media-tile'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border, width: 1.5),
        ),
        child: Row(children: [
          if (b != null && !video)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(b,
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.image)),
            )
          else
            Icon(
                b != null
                    ? Icons.videocam_rounded
                    : (video
                        ? Icons.videocam_outlined
                        : Icons.add_a_photo_outlined),
                color: AppColors.primary,
                size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
                b != null
                    ? '$fileName · toca para cambiar'
                    : (video
                        ? 'Toca para grabar o elegir un video'
                        : 'Toca para tomar o elegir una foto'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppText.bodyMd),
          ),
        ]),
      ),
    );
  }
}

class _LocationNote extends StatelessWidget {
  final bool locating;
  final bool located;
  final VoidCallback onRetry;
  const _LocationNote(
      {required this.locating, required this.located, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final failed = !locating && !located;
    final text = locating
        ? '📍 Buscando tu ubicación…'
        : located
            ? '📍 Se publica donde estás ($nowRadiusMeters m) · dura 24 h'
            : '📍 No pudimos ubicarte. Activa el GPS y toca para reintentar';
    return GestureDetector(
      key: const Key('location-note'),
      behavior: HitTestBehavior.opaque,
      onTap: failed ? onRetry : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: (failed ? AppColors.primary : AppColors.accent)
              .withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: failed ? AppColors.primary : AppColors.accent)),
      ),
    );
  }
}
