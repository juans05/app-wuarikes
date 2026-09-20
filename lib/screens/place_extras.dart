import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import '../core/api_client.dart';
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
          longitude: position.longitude);
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
      Wrap(spacing: 8, children: [
        OutlinedButton.icon(
            onPressed: _busy ? null : _toggle,
            icon: Icon(_interested ? Icons.bookmark : Icons.bookmark_outline),
            label: Text('Quiero ir · $_count')),
        FilledButton.icon(
            onPressed: _busy ? null : _quick,
            icon: const Icon(Icons.my_location),
            label: const Text('Estoy aquí')),
        OutlinedButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => MediaScreen(
                    placeId: _id,
                    ownerId:
                        widget.place.details['claimedByUserId'] as String?))),
            child: const Text('Fotos y videos')),
        OutlinedButton(
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => FeedScreen(placeId: _id))),
            child: const Text('Todas las reseñas')),
        TextButton(
            onPressed: _busy
                ? null
                : () async {
                    if (!await _login() || !mounted) return;
                    final sent = await showDialog<bool>(
                        context: context,
                        builder: (_) => InfoSuggestionDialog(placeId: _id));
                    if (sent == true && mounted)
                      setState(
                          () => _message = 'Gracias. Recibimos tu sugerencia.');
                  },
            child: const Text('Reportar información desactualizada')),
      ]),
      if (_busy) const LinearProgressIndicator(),
      if (_message != null) Text(_message!),
      AsyncSection(
          title: 'Verificación',
          load: () => _api.get('/places/$_id/trust-stage'),
          builder: (data) => Text('${data['label']}')),
      if (context.watch<AuthProvider>().isLoggedIn)
        AsyncSection(
            key: ValueKey('friends-$_revision'),
            title: 'Amigos que lo visitaron',
            load: () => _api.get('/places/$_id/friends-visited'),
            builder: (data) => Column(children: [
                  Text('${data['count']} visitas de amigos'),
                  for (final friend in data['friends'] ?? [])
                    ListTile(
                        title: Text('${friend['fullName']}'),
                        onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) =>
                                    SocialScreen(userId: friend['id']))))
                ])),
      AsyncSection(
          title: 'Promociones',
          load: () => _api.get('/places/$_id/promotions'),
          builder: (data) => Column(children: [
                if ((data as List).isEmpty)
                  const Text('No hay promociones vigentes.'),
                for (final promo in data)
                  ListTile(
                      leading: const Icon(Icons.local_offer),
                      title: Text('${promo['title']}'),
                      subtitle: Text('${promo['description'] ?? ''}'))
              ])),
      AsyncSection(
          title: 'Carta',
          load: () => _api.get('/places/$_id/menu'),
          builder: (data) =>
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final url in data['place']?['menuImageUrls'] ?? [])
                  InkWell(
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => Scaffold(
                              appBar: AppBar(title: const Text('Carta')),
                              body: InteractiveViewer(
                                  child: Image.network(url))))),
                      child:
                          Image.network(url, height: 200, fit: BoxFit.contain)),
                if ((data['categories'] as List? ?? []).isEmpty &&
                    (data['place']?['menuImageUrls'] as List? ?? []).isEmpty)
                  const Text('Todavía no hay carta disponible.'),
                for (final category in data['categories'] ?? [])
                  ExpansionTile(
                      initiallyExpanded: true,
                      title: Text('${category['name']}'),
                      children: [
                        for (final dish in category['dishes'] ?? [])
                          ListTile(
                              title: Text('${dish['name']}'),
                              subtitle: Text([
                                dish['description'],
                                if ((dish['ingredients'] as List? ?? [])
                                    .isNotEmpty)
                                  'Ingredientes: ${(dish['ingredients'] as List).join(', ')}',
                                if ((dish['allergens'] as List? ?? [])
                                    .isNotEmpty)
                                  'Alérgenos: ${(dish['allergens'] as List).join(', ')}',
                                if (dish['isAvailable'] == false)
                                  'No disponible'
                              ].whereType<String>().join('\n')),
                              trailing: Text('S/ ${dish['price'] ?? '-'}'))
                      ]),
              ])),
      AsyncSection(
          key: ValueKey('dishes-$_revision'),
          title: 'Lo más pedido',
          load: () => _api.get('/checkins/places/$_id/top-dishes'),
          builder: (data) => Column(children: [
                if ((data as List).isEmpty)
                  const Text('Aún no hay platos registrados.'),
                for (final dish in data)
                  ListTile(
                      title: Text('${dish['dishName']}'),
                      trailing: Text('${dish['orders']} pedidos'))
              ])),
      AsyncSection(
          title: 'Valoraciones',
          load: () => _api.get('/places/$_id/rating-distribution'),
          builder: (data) => Column(children: [
                for (final row in data)
                  ListTile(
                      title: Text('${row['rating']} ★'),
                      trailing: Text('${row['count']} reseñas'))
              ])),
      AsyncSection(
          title: 'TikTok',
          load: () => _api.post('/places/$_id/tiktok-search'),
          builder: (data) => Column(children: [
                if ((data['videos'] as List? ?? []).isEmpty)
                  Text(data['available'] == false
                      ? 'TikTok no está disponible en este momento.'
                      : 'No hay videos disponibles.'),
                for (final video in data['videos'] ?? [])
                  ListTile(
                      title: Text('${video['caption'] ?? 'Ver video'}'),
                      subtitle: Text('${video['authorName'] ?? ''}'),
                      trailing: const Icon(Icons.open_in_new),
                      onTap: () => openExternal(context, video['url']))
              ])),
      Text('Horario y contacto', style: Theme.of(context).textTheme.titleLarge),
      if ((details['googleReviews'] as List? ?? []).isNotEmpty)
        ExpansionTile(title: const Text('Reseñas de Google'), children: [
          for (final review in details['googleReviews'])
            ListTile(
                title: Text('${review['authorName']} · ${review['rating']} ★'),
                subtitle: Text(
                    '${review['text'] ?? ''}\n${review['relativeTimeDescription'] ?? ''}')),
        ]),
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
    ]);
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
