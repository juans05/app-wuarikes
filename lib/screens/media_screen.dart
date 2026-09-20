import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:provider/provider.dart';
import '../core/api_client.dart';
import '../state/auth_provider.dart';
import 'login_screen.dart';

class MediaScreen extends StatefulWidget {
  final String placeId;
  final String? ownerId;
  const MediaScreen({super.key, required this.placeId, this.ownerId});
  @override
  State<MediaScreen> createState() => _MediaScreenState();
}

class _MediaScreenState extends State<MediaScreen> {
  final _api = ApiClient();
  final _items = <dynamic>[];
  bool _video = false, _busy = false, _more = true;
  int _page = 0;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final page = reset ? 1 : _page + 1;
      final data = await _api.get(
          '/places/${widget.placeId}/${_video ? 'videos' : 'photos'}',
          query: {'page': '$page', 'limit': '12'});
      if (!mounted) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(data['data']);
        _page = page;
        _more = _items.length <
            (data['total'] ?? data['meta']?['total'] ?? _items.length);
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _upload() async {
    if (widget.ownerId == null ||
        context.read<AuthProvider>().user?.id != widget.ownerId) return;
    if (!context.read<AuthProvider>().isLoggedIn) {
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const LoginScreen()));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final picker = ImagePicker();
      final file = _video
          ? await picker.pickVideo(source: ImageSource.gallery)
          : await picker.pickImage(
              source: ImageSource.gallery, maxWidth: 2000, imageQuality: 90);
      if (file == null) return;
      if (await file.length() > (_video ? 20 : 10) * 1024 * 1024)
        throw ApiException(400,
            'El archivo supera el tamaño permitido (${_video ? 20 : 10} MB).');
      await _api.uploadMedia(
          '/places/${widget.placeId}/${_video ? 'videos' : 'photos'}',
          _video ? 'video' : 'photo',
          await file.readAsBytes(),
          file.name,
          file.mimeType ?? (_video ? 'video/mp4' : 'image/jpeg'));
      await _load(reset: true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Fotos y videos')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Fotos')),
              ButtonSegment(value: true, label: Text('Videos'))
            ],
            selected: {
              _video
            },
            onSelectionChanged: _busy
                ? null
                : (s) {
                    setState(() => _video = s.first);
                    _load(reset: true);
                  }),
        if (widget.ownerId != null &&
            context.watch<AuthProvider>().user?.id == widget.ownerId)
          FilledButton.icon(
              onPressed: _busy ? null : _upload,
              icon: const Icon(Icons.upload),
              label: Text(_video ? 'Subir video' : 'Subir foto')),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          Text(_error!, style: const TextStyle(color: Colors.red)),
        for (final item in _items)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: _video
                  ? VideoTile(key: ValueKey(item['id']), url: item['url'])
                  : InkWell(
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => Scaffold(
                              appBar: AppBar(title: const Text('Foto')),
                              body: Center(
                                  child: InteractiveViewer(
                                      child: Image.network(item['url'])))))),
                      child: Image.network(item['url'],
                          height: 240,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.broken_image)))),
        if (!_busy && _items.isEmpty && _error == null)
          const Text('Todavía no hay archivos en esta galería.'),
        if (!_busy && (_more || _error != null))
          TextButton(
              onPressed: () => _load(reset: _error != null),
              child: Text(_error == null ? 'Cargar más' : 'Reintentar')),
      ]));
}

class VideoTile extends StatefulWidget {
  final String url;
  const VideoTile({super.key, required this.url});
  @override
  State<VideoTile> createState() => _VideoTileState();
}

class _VideoTileState extends State<VideoTile> {
  late final _controller =
      VideoPlayerController.networkUrl(Uri.parse(widget.url));
  late final _ready = _controller.initialize();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
      future: _ready,
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return const Text('No se pudo reproducir este video.');
        if (snapshot.connectionState != ConnectionState.done)
          return const LinearProgressIndicator();
        return Column(children: [
          AspectRatio(
              aspectRatio: _controller.value.aspectRatio,
              child: VideoPlayer(_controller)),
          VideoProgressIndicator(_controller, allowScrubbing: true),
          ValueListenableBuilder(
              valueListenable: _controller,
              builder: (context, value, _) => IconButton(
                  tooltip: value.isPlaying ? 'Pausar' : 'Reproducir',
                  onPressed: () => value.isPlaying
                      ? _controller.pause()
                      : _controller.play(),
                  icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow)))
        ]);
      });
}
