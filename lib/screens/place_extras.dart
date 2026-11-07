import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import '../core/api_client.dart';
import '../core/app_theme.dart';
import '../core/models.dart';
import '../core/external_actions.dart';
import '../state/auth_provider.dart';
import '../widgets/async_section.dart';
import 'login_screen.dart';
import 'media_screen.dart';
import 'feed_screen.dart';
import 'social_screen.dart';
import 'info_suggestion_dialog.dart';

class PlaceExtras extends StatefulWidget {
  final Place place;
  const PlaceExtras({super.key, required this.place});
  @override
  State<PlaceExtras> createState() => _PlaceExtrasState();
}

class _PlaceExtrasState extends State<PlaceExtras> {
  final _api = ApiClient();
  bool _interested = false, _busy = false;
  int _count = 0, _revision = 0;
  String? _message;
  String get _id => widget.place.id;
  @override
  void initState() {
    super.initState();
    _interest();
  }

  Future<bool> _login() async {
    if (context.read<AuthProvider>().isLoggedIn) return true;
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const LoginScreen()));
    return mounted && context.read<AuthProvider>().isLoggedIn;
  }

  Future<void> _interest() async {
    try {
      final data = await _api.get('/places/$_id/interest');
      if (mounted)
        setState(() {
          _interested = data['isInterested'] == true;
          _count = data['count'] ?? 0;
        });
    } catch (_) {
      /* Public detail remains available when authentication is required. */
    }
  }

  Future<void> _toggle() async {
    if (!await _login() || !mounted) return;
    setState(() => _busy = true);
    try {
      await _interest();
      if (_interested) {
        await _api.delete('/places/$_id/interest');
      } else {
        await _api.post('/places/$_id/interest');
      }
      await _interest();
    } catch (e) {
      if (mounted) setState(() => _message = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _quick() async {
    if (!await _login() || !mounted) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied)
        permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever)
        throw ApiException(
            400, 'Activa el permiso de ubicación para registrar tu visita.');
      final position = await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(timeLimit: Duration(seconds: 20)));
      final checkin = await _api.createCheckin(
          placeId: _id,
          latitude: position.latitude,
          longitude: position.longitude,
          isMocked: position.isMocked,
          accuracyMeters: position.accuracy);
      if (!mounted) return;
      setState(() {
        _message = '¡Visita registrada!';
        _revision++;
      });
      await showDialog<void>(
          context: context, builder: (_) => DishDialog(checkinId: checkin.id));
    } catch (e) {
      if (mounted) setState(() => _message = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final place = widget.place;
    final details = place.details;
    final meta = details['metadata'] as Map? ?? {};
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: FilledButton.icon(
              onPressed: _busy ? null : _quick,
              icon: const Icon(Icons.my_location, size: 18),
              label: const Text('Estoy aquí')),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
              onPressed: _busy ? null : _toggle,
              icon: Icon(
                  _interested ? Icons.bookmark : Icons.bookmark_outline,
                  size: 18),
              label: Text('Quiero ir · $_count')),
        ),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => MediaScreen(
                      placeId: _id,
                      ownerId:
                          widget.place.details['claimedByUserId'] as String?))),
              icon: const Icon(Icons.photo_library_outlined, size: 18),
              label: const Text('Fotos')),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => FeedScreen(placeId: _id))),
              icon: const Icon(Icons.reviews_outlined, size: 18),
              label: const Text('Reseñas')),
        ),
      ]),
      if (_busy)
        const Padding(
            padding: EdgeInsets.only(top: 10),
            child: LinearProgressIndicator()),
      if (_message != null)
        Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(_message!, style: AppText.bodyMd)),
      AsyncSection(
          title: 'Verificación',
          load: () => _api.get('/places/$_id/trust-stage'),
          builder: (data) => Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                      color: AppColors.primaryContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(999)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.verified_outlined,
                        size: 15, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Text('${data['label']}',
                        style: AppText.labelMd.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600)),
                  ]),
                ),
              )),
      if (context.watch<AuthProvider>().isLoggedIn)
        AsyncSection(
            key: ValueKey('friends-$_revision'),
            title: 'Amigos que lo visitaron',
            load: () => _api.get('/places/$_id/friends-visited'),
            builder: (data) {
              final friends = (data['friends'] as List? ?? []);
              if (friends.isEmpty) {
                return const _EmptyHint(
                    icon: Icons.group_outlined,
                    text:
                        'Ningún amigo tuyo ha registrado una visita todavía.');
              }
              return _SectionBox(
                  child: Column(children: [
                for (var i = 0; i < friends.length; i++) ...[
                  if (i > 0)
                    const Divider(height: 14, color: AppColors.border),
                  InkWell(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) =>
                            SocialScreen(userId: friends[i]['id']))),
                    child: Row(children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: AppColors.primaryContainer,
                        child: Text(
                            _initial('${friends[i]['fullName'] ?? ''}'),
                            style: AppText.bodyMd.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text('${friends[i]['fullName']}',
                              style: AppText.bodyLg)),
                      const Icon(Icons.chevron_right_rounded,
                          color: AppColors.onSurfaceVariant),
                    ]),
                  ),
                ],
              ]));
            }),
      AsyncSection(
          title: 'Promociones',
          load: () => _api.get('/places/$_id/promotions'),
          builder: (data) {
            final promos = data as List;
            if (promos.isEmpty) {
              return const _EmptyHint(
                  icon: Icons.local_offer_outlined,
                  text: 'No hay promociones vigentes.');
            }
            return Column(children: [
              for (final promo in promos)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _SectionBox(
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.local_offer_rounded,
                              size: 18, color: AppColors.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${promo['title']}',
                                      style: AppText.bodyLg.copyWith(
                                          fontWeight: FontWeight.w600)),
                                  if ((promo['description'] ?? '')
                                      .toString()
                                      .isNotEmpty)
                                    Text('${promo['description']}',
                                        style: AppText.bodyMd),
                                ]),
                          ),
                        ]),
                  ),
                ),
            ]);
          }),
      AsyncSection(
          title: 'Carta',
          load: () => _api.get('/places/$_id/menu'),
          builder: (data) {
            final images = data['place']?['menuImageUrls'] as List? ?? [];
            final categories = data['categories'] as List? ?? [];
            if (images.isEmpty && categories.isEmpty) {
              return const _EmptyHint(
                  icon: Icons.menu_book_outlined,
                  text: 'Todavía no hay carta disponible.');
            }
            return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final url in images)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => Scaffold(
                                    appBar:
                                        AppBar(title: const Text('Carta')),
                                    body: InteractiveViewer(
                                        child: Image.network(url))))),
                        child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image.network(url,
                                height: 200, fit: BoxFit.contain)),
                      ),
                    ),
                  for (final category in categories)
                    ExpansionTile(
                        initiallyExpanded: true,
                        tilePadding: EdgeInsets.zero,
                        shape: const Border(),
                        collapsedShape: const Border(),
                        title: Text('${category['name']}',
                            style: AppText.bodyLg
                                .copyWith(fontWeight: FontWeight.w600)),
                        children: [
                          for (final dish in category['dishes'] ?? [])
                            ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text('${dish['name']}',
                                    style: AppText.bodyLg),
                                subtitle: Text(
                                    [
                                      dish['description'],
                                      if ((dish['ingredients'] as List? ?? [])
                                          .isNotEmpty)
                                        'Ingredientes: ${(dish['ingredients'] as List).join(', ')}',
                                      if ((dish['allergens'] as List? ?? [])
                                          .isNotEmpty)
                                        'Alérgenos: ${(dish['allergens'] as List).join(', ')}',
                                      if (dish['isAvailable'] == false)
                                        'No disponible'
                                    ].whereType<String>().join('\n'),
                                    style: AppText.bodyMd),
                                trailing: Text('S/ ${dish['price'] ?? '-'}',
                                    style: AppText.bodyMd.copyWith(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w700)))
                        ]),
                ]);
          }),
      AsyncSection(
          key: ValueKey('dishes-$_revision'),
          title: 'Lo más pedido',
          load: () => _api.get('/checkins/places/$_id/top-dishes'),
          builder: (data) {
            final dishes = data as List;
            if (dishes.isEmpty) {
              return const _EmptyHint(
                  icon: Icons.ramen_dining_outlined,
                  text: 'Aún no hay platos registrados.');
            }
            return _SectionBox(
                child: Column(children: [
              for (var i = 0; i < dishes.length; i++) ...[
                if (i > 0) const Divider(height: 14, color: AppColors.border),
                Row(children: [
                  Text('${i + 1}',
                      style: AppText.bodyMd.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text('${dishes[i]['dishName']}',
                          style: AppText.bodyLg)),
                  Text('${dishes[i]['orders']} pedidos',
                      style: AppText.labelMd),
                ]),
              ],
            ]));
          }),
      AsyncSection(
          title: 'Valoraciones',
          load: () => _api.get('/places/$_id/rating-distribution'),
          builder: (data) => _RatingBreakdown(rows: data as List)),
      Text('Horario y contacto', style: Theme.of(context).textTheme.titleLarge),
      if ((details['openingHours'] as List? ?? []).isNotEmpty)
        for (final day in details['openingHours'])
          Text('${const {
                'mon': 'Lunes',
                'tue': 'Martes',
                'wed': 'Miércoles',
                'thu': 'Jueves',
                'fri': 'Viernes',
                'sat': 'Sábado',
                'sun': 'Domingo'
              }[day['day']] ?? day['day']}: ${day['open']} – ${day['close']}')
      else
        Text(place.openHoursText ?? 'Horario no disponible'),
      if (place.phone != null)
        TextButton.icon(
            onPressed: () => openExternal(context, 'tel:${place.phone}'),
            icon: const Icon(Icons.call),
            label: Text(place.phone!)),
      if (details['website'] != null)
        TextButton(
            onPressed: () => openExternal(context, '${details['website']}'),
            child: const Text('Sitio web')),
      if (place.latitude != null && place.longitude != null)
        TextButton.icon(
            onPressed: () => openExternal(context,
                'https://www.google.com/maps/dir/?api=1&destination=${place.latitude},${place.longitude}'),
            icon: const Icon(Icons.directions),
            label: const Text('Cómo llegar')),
      for (final key in ['historia', 'especialidades', 'chef'])
        if (meta[key] != null)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('${meta[key]}')),
      for (final key in ['premios', 'certificaciones'])
        for (final value in meta[key] as List? ?? [])
          ListTile(leading: const Icon(Icons.verified), title: Text('$value')),
      const SizedBox(height: 8),
      Center(
        child: TextButton.icon(
          onPressed: _busy
              ? null
              : () async {
                  if (!await _login() || !mounted) return;
                  final sent = await showDialog<bool>(
                      context: context,
                      builder: (_) => InfoSuggestionDialog(placeId: _id));
                  if (sent == true && mounted) {
                    setState(
                        () => _message = 'Gracias. Recibimos tu sugerencia.');
                  }
                },
          icon: const Icon(Icons.flag_outlined, size: 16),
          label: Text('Reportar información desactualizada',
              style: AppText.labelMd.copyWith(color: AppColors.primary)),
        ),
      ),
    ]);
  }
}

String _initial(String name) {
  final trimmed = name.trim();
  return trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
}

class _SectionBox extends StatelessWidget {
  final Widget child;
  const _SectionBox({required this.child});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.border),
        ),
        child: child,
      );
}

/// Shared "nothing here yet" row, so every empty section reads the same
/// instead of each one inventing its own bare sentence.
class _EmptyHint extends StatelessWidget {
  final IconData icon;
  final String text;
  const _EmptyHint({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(children: [
          Icon(icon, size: 18, color: AppColors.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: AppText.bodyMd)),
        ]),
      );
}

class _RatingBreakdown extends StatelessWidget {
  final List rows;
  const _RatingBreakdown({required this.rows});

  @override
  Widget build(BuildContext context) {
    final counts = <int, int>{for (var star = 1; star <= 5; star++) star: 0};
    for (final row in rows) {
      final star = (row['rating'] as num?)?.toInt();
      if (star != null && star >= 1 && star <= 5) {
        counts[star] = (row['count'] as num?)?.toInt() ?? 0;
      }
    }
    final total = counts.values.fold<int>(0, (sum, count) => sum + count);
    if (total == 0) {
      return const _EmptyHint(
          icon: Icons.star_outline_rounded,
          text: 'Todavía no hay valoraciones registradas.');
    }
    final average =
        counts.entries.fold<double>(0, (sum, e) => sum + e.key * e.value) /
            total;

    return _SectionBox(
      child: Row(children: [
        Column(children: [
          Text(average.toStringAsFixed(1),
              style: AppText.headlineLg.copyWith(color: AppColors.primary)),
          Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(
                  5,
                  (i) => Icon(
                      i < average.round()
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      size: 13,
                      color: AppColors.amber))),
          const SizedBox(height: 3),
          Text('$total ${total == 1 ? 'reseña' : 'reseñas'}',
              style: AppText.labelMd),
        ]),
        const SizedBox(width: 18),
        Expanded(
          child: Column(children: [
            for (var star = 5; star >= 1; star--)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  SizedBox(
                      width: 10,
                      child: Text('$star',
                          style: AppText.labelMd,
                          textAlign: TextAlign.right)),
                  const SizedBox(width: 3),
                  const Icon(Icons.star_rounded,
                      size: 11, color: AppColors.amber),
                  const SizedBox(width: 7),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: counts[star]! / total,
                        minHeight: 7,
                        backgroundColor: AppColors.border,
                        color: AppColors.amber,
                      ),
                    ),
                  ),
                  SizedBox(
                      width: 26,
                      child: Text('${counts[star]}',
                          style: AppText.labelMd,
                          textAlign: TextAlign.right)),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }
}

class DishDialog extends StatefulWidget {
  final String checkinId;
  const DishDialog({super.key, required this.checkinId});
  @override
  State<DishDialog> createState() => _DishDialogState();
}

class _DishDialogState extends State<DishDialog> {
  final _name = TextEditingController(), _price = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final price = num.tryParse(_price.text.replaceAll(',', '.'));
    if (_name.text.trim().isEmpty ||
        (_price.text.isNotEmpty && (price == null || price < 0))) {
      setState(() => _error = 'Ingresa un plato y un precio válido.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ApiClient().patch('/checkins/${widget.checkinId}/dish', {
        'dishName': _name.text.trim(),
        if (price != null) 'dishPrice': price
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('¿Qué pediste?'),
          content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: _name,
                maxLength: 100,
                decoration: const InputDecoration(labelText: 'Plato')),
            TextField(
                controller: _price,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration:
                    const InputDecoration(labelText: 'Precio S/ (opcional)')),
            if (_error != null) Text(_error!)
          ])),
          actions: [
            TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                child: const Text('Omitir')),
            FilledButton(
                onPressed: _busy ? null : _save, child: const Text('Guardar'))
          ]);
}
