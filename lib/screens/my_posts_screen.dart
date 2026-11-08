import 'package:flutter/material.dart';
import '../core/api_client.dart';
import '../core/app_theme.dart';
import '../core/now_api.dart';
import '../core/now_models.dart';
import 'now/now_post_screen.dart';

/// Mis publicaciones de "Ahora": las que publiqué yo. Tocar una abre la
/// publicación (`GET /now/mine`).
class MyPostsScreen extends StatefulWidget {
  /// Solo para pruebas: API de mentira.
  final ApiClient? api;
  const MyPostsScreen({super.key, this.api});

  @override
  State<MyPostsScreen> createState() => _MyPostsScreenState();
}

class _MyPostsScreenState extends State<MyPostsScreen> {
  late final ApiClient _api = widget.api ?? ApiClient();
  final _posts = <NowPost>[];
  int _page = 0, _totalPages = 1;
  bool _loading = true, _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final first = await _api.getMyNowPosts();
      if (!mounted) return;
      setState(() {
        _posts
          ..clear()
          ..addAll(first.data);
        _page = 1;
        _totalPages = first.totalPages;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    try {
      final next = await _api.getMyNowPosts(page: _page + 1);
      if (!mounted) return;
      setState(() {
        _posts.addAll(next.data);
        _page++;
        _totalPages = next.totalPages;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No se pudieron cargar más. Intenta de nuevo.')));
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('Mis publicaciones')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_error!),
                    TextButton(
                        onPressed: _load, child: const Text('Reintentar'))
                  ]))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      // Siempre desplazable: vacía también se puede jalar para refrescar.
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (_posts.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 48),
                            child: Text(
                                'Todavía no publicaste nada en Ahora. Usa el ＋ para contar lo que pasa donde estás.',
                                textAlign: TextAlign.center,
                                style: AppText.bodyMd),
                          ),
                        for (final p in _posts) ...[
                          _PostRow(
                              post: p,
                              // Oculta: el detalle daría 404, así que se explica.
                              onTap: p.hidden
                                  ? () => ScaffoldMessenger.of(context)
                                    ..hideCurrentSnackBar()
                                    ..showSnackBar(const SnackBar(
                                        content: Text(
                                            'Esta publicación fue ocultada por reportes o votos')))
                                  : () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                          builder: (_) => NowPostScreen(
                                              postId: p.id, api: widget.api)))),
                          const SizedBox(height: 8),
                        ],
                        if (_page < _totalPages)
                          TextButton(
                              onPressed: _loadingMore ? null : _loadMore,
                              child: const Text('Cargar más')),
                      ],
                    ),
                  ),
      ),
    );
  }
}

const _visibilityLabels = {
  'all': 'Todos',
  'followers': 'Seguidores',
  'friends': 'Amigos',
};

class _PostRow extends StatelessWidget {
  final NowPost post;
  final VoidCallback onTap;
  const _PostRow({required this.post, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final text = (post.text ?? '').trim();
    final (icon, fallback) = switch (post.kind) {
      'photo' => (Icons.photo_camera_outlined, 'Foto'),
      'video' => (Icons.videocam_outlined, 'Video'),
      _ => (Icons.chat_bubble_outline_rounded, 'Texto'),
    };
    return Material(
      color: AppColors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
          side: const BorderSide(color: AppColors.border),
          borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Icon(icon, color: AppColors.primary),
        title: Text(text.isEmpty ? fallback : text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppText.bodyMd.copyWith(
                color: AppColors.onSurface, fontWeight: FontWeight.w600)),
        subtitle: Text(
            '${_visibilityLabels[post.visibility] ?? post.visibility} · ⚡ ${timeLeftLabel(post.timeLeft(DateTime.now()))}',
            style: AppText.labelMd),
        trailing: post.hidden
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text('Oculta',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary)),
              )
            : const Icon(Icons.chevron_right_rounded,
                color: AppColors.onSurfaceVariant),
      ),
    );
  }
}
