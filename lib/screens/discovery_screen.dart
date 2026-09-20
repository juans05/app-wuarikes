import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../core/api_client.dart';
import '../core/models.dart';
import '../widgets/async_section.dart';
import '../widgets/place_card.dart';
import '../state/auth_provider.dart';
import 'place_detail_screen.dart';
import 'login_screen.dart';

class DiscoveryScreen extends StatefulWidget {
  const DiscoveryScreen({super.key});
  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen> {
  final _api = ApiClient();
  final _district = TextEditingController();
  String? _category;
  int? _budget;
  bool _nearby = false, _busy = false;
  String? _error;
  List<Place>? _results;
  int _revision = 0;
  @override
  void dispose() {
    _district.dispose();
    super.dispose();
  }

  Future<void> _recommend() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final query = <String, String>{
        if (_category != null) 'category': _category!,
        if (_district.text.trim().isNotEmpty) 'district': _district.text.trim()
      };
      const budgets = [
        {'priceMax': '20'},
        {'priceMin': '20', 'priceMax': '30'},
        {'priceMin': '30', 'priceMax': '50'},
        {'priceMin': '50'}
      ];
      if (_budget != null) query.addAll(budgets[_budget!]);
      if (_nearby) {
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied)
          permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever)
          throw ApiException(
              400, 'Activa el permiso de ubicación o desmarca Cerca de mí.');
        final position = await Geolocator.getCurrentPosition(
            locationSettings:
                const LocationSettings(timeLimit: Duration(seconds: 20)));
        query.addAll({
          'latitude': '${position.latitude}',
          'longitude': '${position.longitude}',
          'radius': '5'
        });
      }
      final data = await _api.get('/places/recommendations', query: query);
      if (mounted)
        setState(() =>
            _results = (data as List).map((e) => Place.fromJson(e)).toList());
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _places(dynamic data) => Column(children: [
        if ((data as List).isEmpty)
          const Text('No encontramos lugares con estos filtros.'),
        for (final raw in data) _card(raw is Place ? raw : Place.fromJson(raw))
      ]);
  Widget _card(Place place) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: PlaceCard(
          place: place,
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => PlaceDetailScreen(placeId: place.id)))));
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Descubre Wuarikes')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('¿Dónde comemos hoy?',
            style: Theme.of(context).textTheme.headlineSmall),
        AsyncSection(
            title: '¿Qué se te antoja?',
            load: () => _api.getCategories(),
            builder: (data) => Wrap(spacing: 8, children: [
                  ChoiceChip(
                      label: const Text('Sorpréndeme'),
                      selected: _category == null,
                      onSelected: (_) => setState(() => _category = null)),
                  for (final c in data as List<Category>)
                    ChoiceChip(
                        label: Text(c.name),
                        selected: _category == c.slug,
                        onSelected: (_) => setState(() => _category = c.slug))
                ])),
        DropdownButton<int>(
            isExpanded: true,
            hint: const Text('Cualquier presupuesto'),
            value: _budget,
            items: const [
              DropdownMenuItem(value: 0, child: Text('Menos de S/20')),
              DropdownMenuItem(value: 1, child: Text('S/20 – S/30')),
              DropdownMenuItem(value: 2, child: Text('S/30 – S/50')),
              DropdownMenuItem(value: 3, child: Text('Más de S/50'))
            ],
            onChanged: (v) => setState(() => _budget = v)),
        TextField(
            controller: _district,
            decoration:
                const InputDecoration(labelText: 'Distrito (opcional)')),
        SwitchListTile(
            title: const Text('Cerca de mí (5 km)'),
            value: _nearby,
            onChanged: (v) => setState(() => _nearby = v)),
        FilledButton(
            onPressed: _busy ? null : _recommend,
            child: Text(
                _results == null ? 'Ver recomendaciones' : 'Otras opciones')),
        TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                      _category = null;
                      _budget = null;
                      _nearby = false;
                      _district.clear();
                      _results = null;
                    }),
            child: const Text('Empezar de nuevo')),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          Text(_error!, style: const TextStyle(color: Colors.red)),
        if (_results != null) _places(_results!),
        OutlinedButton(
            onPressed: () => setState(() => _revision++),
            child: const Text('Actualizar descubrimientos')),
        AsyncSection(
            key: ValueKey('trending-$_revision'),
            title: 'Algo diferente',
            load: () => _api.get('/places/discovery/different', query: {
                  if (_district.text.trim().isNotEmpty)
                    'district': _district.text.trim(),
                  if (_category != null) 'category': _category!,
                  'limit': '10'
                }),
            builder: _places),
        AsyncSection(
            title: 'Los más guardados',
            load: () => _api.get('/places/discovery/most-favorited',
                query: {'limit': '10'}),
            builder: _places),
        FilledButton(
            onPressed: () async {
              if (!context.read<AuthProvider>().isLoggedIn) {
                await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const LoginScreen()));
              }
              if (context.mounted && context.read<AuthProvider>().isLoggedIn) {
                await showDialog<void>(
                    context: context,
                    builder: (_) => const WuarikesHereDialog());
              }
            },
            child: const Text('Quiero Wuarikes aquí')),
      ]));
}

class WuarikesHereDialog extends StatefulWidget {
  const WuarikesHereDialog({super.key});
  @override
  State<WuarikesHereDialog> createState() => _WuarikesHereDialogState();
}

class _WuarikesHereDialogState extends State<WuarikesHereDialog> {
  final _name = TextEditingController(),
      _district = TextEditingController(),
      _address = TextEditingController();
  bool _busy = false, _done = false;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    _district.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Ingresa el nombre del restaurante.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiClient().post('/places/wuarikes-here', {
        'restaurantName': _name.text.trim(),
        if (_district.text.trim().isNotEmpty) 'district': _district.text.trim(),
        if (_address.text.trim().isNotEmpty) 'address': _address.text.trim()
      });
      if (mounted) setState(() => _done = true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('Quiero Wuarikes aquí'),
          content: SingleChildScrollView(
              child: _done
                  ? const Text('¡Gracias! Recibimos tu solicitud.')
                  : Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(
                          controller: _name,
                          decoration:
                              const InputDecoration(labelText: 'Restaurante')),
                      TextField(
                          controller: _district,
                          decoration:
                              const InputDecoration(labelText: 'Distrito')),
                      TextField(
                          controller: _address,
                          decoration:
                              const InputDecoration(labelText: 'Dirección')),
                      if (_error != null) Text(_error!)
                    ])),
          actions: [
            TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                child: const Text('Cerrar')),
            if (!_done)
              FilledButton(
                  onPressed: _busy ? null : _send, child: const Text('Enviar'))
          ]);
}
