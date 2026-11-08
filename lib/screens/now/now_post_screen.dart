import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/now_api.dart';
import '../../core/now_location.dart';
import '../../core/now_models.dart';
import '../../state/auth_provider.dart';
import '../login_screen.dart';
import '../media_screen.dart' show VideoTile;
import '../place_detail_screen.dart' show timeAgo;

/// Una publicación de Ahora: media, autor, vida que le queda, 👍 👎 ✅ y Reportar.
class NowPostScreen extends StatefulWidget {
  final String postId;

  /// Solo para pruebas: API y GPS de mentira.
  final ApiClient? api;
  final NowLocator? locate;

  const NowPostScreen({super.key, required this.postId, this.api, this.locate});

  @override
  State<NowPostScreen> createState() => _NowPostScreenState();
}

class _NowPostScreenState extends State<NowPostScreen> {
  late final ApiClient _api = widget.api ?? ApiClient();
  NowPost? _post;
  bool _loading = true;
  bool _gone = false;
  String? _error;
  bool _busy = false;
  Position? _position;
  bool _locating = true;

  @override
  void initState() {
    super.initState();
    _load();
    _locator().then((p) {
      if (mounted) {
        setState(() {
          _position = p;
          _locating = false;
        });
      }
    }).catchError((_) {
      if (mounted) setState(() => _locating = false);
    });
  }

  Future<Position?> _locator() => (widget.locate ?? currentNowPosition)();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final post = await _api.getNowPost(widget.postId);
      if (mounted) setState(() => _post = post);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.status == 404) {
          _gone = true;
        } else {
          _error = 'No se pudo cargar la publicación';
        }
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo cargar la publicación');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Manda al invitado a iniciar sesión; true si ya hay sesión.
  Future<bool> _ensureLoggedIn() async {
    if (context.read<AuthProvider>().isLoggedIn) return true;
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const LoginScreen()));
    if (!mounted) return false;
    // Con sesión nueva cambia myReaction (y quizá el autor): se vuelve a leer.
    if (context.read<AuthProvider>().isLoggedIn) _load();
    return false;
  }

  /// Metros del usuario a la publicación; null si no se sabe dónde está.
  double? _distance(NowPost post) {
    final p = _position;
    if (p == null) return null;
    return Geolocator.distanceBetween(
        p.latitude, p.longitude, post.latitude, post.longitude);
  }

  Future<void> _react(String type) async {
    if (!await _ensureLoggedIn()) return;
    final post = _post;
    if (post == null || _busy) return;
    setState(() => _busy = true);
    try {
      // ✅ se decide con la posición de este momento, no con la de al abrir:
      // quien se acercó puede confirmar, y quien se alejó ya no.
      if (type == 'check' && post.myReaction != 'check') {
        final fresh = await _locator();
        if (!mounted) return;
        setState(() => _position = fresh);
        if (fresh != null && fresh.isMocked) {
          _snack(nowMockedLocationMessage);
          return;
        }
        final d = _distance(post);
        if (d == null || !canConfirm(d)) {
          _snack('Acércate para confirmar');
          return;
        }
      }
      final updated = post.myReaction == type
          ? await _api.unreactNow(post.id)
          : await _api.reactNow(post.id, type,
              lat: type == 'check' ? _position?.latitude : null,
              lng: type == 'check' ? _position?.longitude : null);
      if (mounted) setState(() => _post = updated);
    } on ApiException catch (e) {
      _snack(switch (e.status) {
        403 => 'Acércate para confirmar',
        404 => 'Esta publicación ya no está disponible',
        400 => e.message,
        _ => 'No se pudo registrar tu reacción',
      });
    } catch (_) {
      _snack('No se pudo registrar tu reacción');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _report() async {
    if (!await _ensureLoggedIn()) return;
    final post = _post;
    if (post == null || !mounted) return;
    final reason = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadius.lg))),
      builder: (_) => const _ReportSheet(),
    );
    if (reason == null) return;
    try {
      await _api.reportNow(post.id, reason);
      _snack('Gracias, lo revisaremos');
    } on ApiException catch (e) {
      _snack(switch (e.status) {
        429 => 'Llegaste al límite de reportes de hoy',
        404 => 'Esta publicación ya no está disponible',
        400 => e.message,
        _ => 'No se pudo enviar el reporte',
      });
    } catch (_) {
      _snack('No se pudo enviar el reporte');
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewerId = context.watch<AuthProvider>().user?.id;
    return Scaffold(
      appBar: AppBar(title: const Text('Ahora')),
      body: _loading && _post == null
          ? const Center(child: CircularProgressIndicator())
          : _gone
              ? const _Message(
                  icon: Icons.timer_off_outlined,
                  text: 'Esta publicación ya no está disponible')
              : _post == null
                  ? _Message(
                      icon: Icons.cloud_off_outlined,
                      text: _error ?? 'No se pudo cargar la publicación',
                      action: _load)
                  : _body(_post!, viewerId),
    );
  }

  Widget _body(NowPost post, String? viewerId) {
    final isAuthor = viewerId != null && viewerId == post.authorId;
    final distance = _distance(post);
    final near = distance != null && canConfirm(distance);
    final checkHint = isAuthor || near
        ? '+1 h c/u'
        : post.myReaction == 'check'
            ? 'Toca para quitar'
            : (_position == null && _locating
                ? 'Ubicando…'
                : 'Acércate para confirmar');

    // `dimmed`: se ve apagado pero se puede tocar (un ✅ lejano vuelve a
    // ubicar y decide con la posición nueva).
    Widget reaction(String type, String emoji, int count, String hint,
        {bool dimmed = false}) {
      return _ReactionButton(
        key: ValueKey('react-$type'),
        label: '$emoji $count',
        hint: hint,
        selected: post.myReaction == type,
        enabled: !isAuthor && !dimmed,
        onTap: isAuthor || _busy ? null : () => _react(type),
      );
    }

    final avatar = post.authorAvatar;
    return ListView(
      children: [
        if (post.kind == 'video' && post.mediaUrl != null)
          VideoTile(url: post.mediaUrl!)
        else if (post.mediaUrl != null)
          SizedBox(
            height: 260,
            width: double.infinity,
            child: CachedNetworkImage(
              imageUrl: post.mediaUrl!,
              fit: BoxFit.cover,
              placeholder: (_, __) =>
                  Container(color: AppColors.primaryContainer),
              errorWidget: (_, __, ___) => Container(
                  color: AppColors.primaryContainer,
                  alignment: Alignment.center,
                  child: const Icon(Icons.broken_image_outlined,
                      color: AppColors.primary)),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                CircleAvatar(
                  radius: 15,
                  backgroundColor: AppColors.secondary,
                  backgroundImage: avatar != null && avatar.isNotEmpty
                      ? CachedNetworkImageProvider(avatar)
                      : null,
                  child: avatar == null || avatar.isEmpty
                      ? const Icon(Icons.person, size: 16, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('@${post.authorName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.bodyLg
                              .copyWith(fontWeight: FontWeight.w700)),
                      Text(timeAgo(post.createdAt.toIso8601String()) ?? '',
                          style: AppText.labelMd),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  key: const Key('now-time-left'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: AppColors.primaryContainer,
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(timeLeftLabel(post.timeLeft(DateTime.now())),
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary)),
                ),
              ]),
              if ((post.text ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(post.text!.trim(), style: AppText.bodyLg),
              ],
              const SizedBox(height: 14),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                reaction('like', '👍', post.likes, '+1 h c/u'),
                const SizedBox(width: 8),
                reaction('dislike', '👎', post.dislikes, '−1 h c/u'),
                const SizedBox(width: 8),
                // Quien ya dio ✅ siempre puede quitarlo, esté donde esté.
                reaction('check', '✅', post.checks, checkHint,
                    dimmed: !near && post.myReaction != 'check'),
              ]),
              const SizedBox(height: 10),
              Text(
                  isAuthor
                      ? 'Es tu publicación: no puedes reaccionar a ella.'
                      : '✅ = "confirmo que es cierto". Solo a menos de $nowRadiusMeters m.',
                  style: AppText.labelMd),
              if (!isAuthor) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _report,
                  style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      padding: EdgeInsets.zero,
                      alignment: Alignment.centerLeft),
                  child: const Text('⚑ Reportar',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ReactionButton extends StatelessWidget {
  final String label;
  final String hint;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  const _ReactionButton(
      {super.key,
      required this.label,
      required this.hint,
      required this.selected,
      required this.enabled,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
            decoration: BoxDecoration(
              color: selected ? AppColors.primaryContainer : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: selected ? AppColors.primary : AppColors.border,
                  width: 1.5),
            ),
            child: Column(children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color:
                          selected ? AppColors.primary : AppColors.onSurface)),
              Text(hint,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 10, color: AppColors.onSurfaceVariant)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback? action;
  const _Message({required this.icon, required this.text, this.action});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 44, color: AppColors.primary),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: AppText.bodyMd),
          if (action != null) ...[
            const SizedBox(height: 16),
            FilledButton(onPressed: action, child: const Text('Reintentar')),
          ],
        ]),
      ),
    );
  }
}

/// Motivo del reporte: obligatorio, hasta 200 caracteres.
class _ReportSheet extends StatefulWidget {
  const _ReportSheet();

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Reportar publicación', style: AppText.titleLg),
          const SizedBox(height: 12),
          TextField(
            key: const Key('report-reason'),
            controller: _reason,
            maxLength: 200,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
                hintText: '¿Qué pasa con esta publicación?'),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _reason,
            builder: (_, value, __) => SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: value.text.trim().isEmpty
                    ? null
                    : () => Navigator.of(context).pop(_reason.text.trim()),
                child: const Text('Enviar reporte'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
