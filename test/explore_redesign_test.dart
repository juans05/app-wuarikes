import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wuarikes_app/core/api_client.dart';
import 'package:wuarikes_app/core/models.dart';
import 'package:wuarikes_app/screens/discovery_screen.dart';
import 'package:wuarikes_app/screens/explore_screen.dart';
import 'package:wuarikes_app/screens/main_shell.dart';
import 'package:wuarikes_app/screens/place_detail_screen.dart';
import 'package:wuarikes_app/screens/profile_screen.dart';
import 'package:wuarikes_app/state/auth_provider.dart';
import 'package:wuarikes_app/widgets/explore_bottom_list.dart';
import 'package:wuarikes_app/widgets/mode_switch.dart';
import 'package:wuarikes_app/widgets/place_list_tile.dart';

Map<String, dynamic> _placeJson(String id, String name,
        {bool benefit = false}) =>
    {
      'id': id,
      'name': name,
      'rating': '4.6',
      'priceMin': '18.00',
      'latitude': '-12.12',
      'longitude': '-77.03',
      'category': {'id': 'c1', 'name': 'Cevichería', 'slug': 'cevicheria'},
      'hasActiveBenefit': benefit,
    };

List<Place> _places() => [
      Place.fromJson(_placeJson('p1', 'El Chinito', benefit: true)),
      Place.fromJson(_placeJson('p2', 'Don Lucho')),
      Place.fromJson(_placeJson('p3', 'La Mar')),
    ];

/// Datos de mentira para Explorar: `/places` devuelve [places]; el resto, [].
ApiClient _mockApi(List<Map<String, dynamic>> places,
    {List<http.Request>? seen}) {
  return ApiClient(
      client: MockClient((req) async {
    seen?.add(req);
    final body = req.url.path.endsWith('/places')
        ? {
            'data': places,
            'meta': {'total': places.length, 'page': 1, 'totalPages': 1}
          }
        : [];
    return http.Response(jsonEncode(body), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});
  }));
}

/// Como [_mockApi], pero cada petición a `/places` espera a [release] antes de
/// responder: la primera devuelve [first]; las demás [second] (o 500 si falla).
class _GatedApi {
  final _gates = <Completer<void>>[];
  final seen = <http.Request>[];
  final List<Map<String, dynamic>> first;
  final List<Map<String, dynamic>> second;
  final bool failSecond;
  _GatedApi(this.first, {this.second = const [], this.failSecond = false});

  /// Una por cada petición a `/places`, en orden.
  int get pending => _gates.length;

  late final api = ApiClient(
      client: MockClient((req) async {
    seen.add(req);
    if (!req.url.path.endsWith('/places')) {
      return http.Response('[]', 200);
    }
    final index = _gates.length;
    final gate = Completer<void>();
    _gates.add(gate);
    await gate.future;
    if (index > 0 && failSecond) return http.Response('{}', 500);
    final data = index == 0 ? first : second;
    return http.Response(
        jsonEncode({
          'data': data,
          'meta': {'total': data.length, 'page': 1, 'totalPages': 1}
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'});
  }));

  Future<void> release(WidgetTester tester, int index) async {
    _gates[index].complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pump(WidgetTester tester, Widget home) async {
  // Tamaño de celular: el de prueba por defecto (800x600) desborda Explorar.
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ChangeNotifierProvider<AuthProvider>.value(
    value: AuthProvider(ApiClient()),
    child: MaterialApp(home: home),
  ));
  // Deja resolver las llamadas de mentira (sin pumpAndSettle: el mapa anima).
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// Corre la fila de filtros hasta el final (con la fuente de prueba, muy
/// ancha, los últimos chips quedan fuera de la pantalla).
Future<void> _scrollChipsToEnd(WidgetTester tester) async {
  final row = find.byWidgetPredicate(
      (w) => w is ListView && w.scrollDirection == Axis.horizontal);
  await tester.drag(row, const Offset(-600, 0));
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ModeSwitch', () {
    testWidgets('al tocar Ahora avisa con ExploreMode.now', (tester) async {
      final calls = <ExploreMode>[];
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: ModeSwitch(
                  value: ExploreMode.places, onChanged: calls.add))));

      expect(find.text('🍽️ Locales'), findsOneWidget);
      expect(find.text('⚡ Ahora'), findsOneWidget);

      await tester.tap(find.text('⚡ Ahora'));
      expect(calls, [ExploreMode.now]);

      // Tocar el que ya está activo no avisa.
      await tester.tap(find.text('🍽️ Locales'));
      expect(calls, [ExploreMode.now]);
    });

    testWidgets('desde Ahora, tocar Locales avisa con ExploreMode.places',
        (tester) async {
      final calls = <ExploreMode>[];
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: ModeSwitch(value: ExploreMode.now, onChanged: calls.add))));

      await tester.tap(find.text('🍽️ Locales'));
      expect(calls, [ExploreMode.places]);
    });
  });

  group('ExploreBottomList', () {
    Future<void> pumpList(
      WidgetTester tester, {
      required List<Place> places,
      ValueChanged<Place>? onPlaceTap,
      VoidCallback? onSurprise,
      bool openNow = false,
    }) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ExploreBottomList(
            places: places,
            openNow: openNow,
            distanceMeters: (p) => p.id == 'p1' ? 350 : null,
            onPlaceTap: onPlaceTap ?? (_) {},
            onSurprise: onSurprise ?? () {},
          ),
        ),
      ));
      await tester.pump();
    }

    testWidgets('el título cuenta los locales: "Cerca de ti · N"',
        (tester) async {
      await pumpList(tester, places: _places());
      expect(find.text('Cerca de ti · 3'), findsOneWidget);
    });

    testWidgets('sin locales dice "Cerca de ti · 0" y avisa que no hay',
        (tester) async {
      await pumpList(tester, places: const []);
      expect(find.text('Cerca de ti · 0'), findsOneWidget);
      expect(find.text('No hay locales para mostrar por ahora.'),
          findsOneWidget);
    });

    testWidgets('"✨ Sorpréndeme" avisa para abrir Sorpréndeme', (tester) async {
      var taps = 0;
      await pumpList(tester, places: _places(), onSurprise: () => taps++);
      await tester.tap(find.text('✨ Sorpréndeme'));
      expect(taps, 1);
    });

    testWidgets('la tarjeta muestra nombre, ⭐, categoría, distancia y "Desde S/"',
        (tester) async {
      await pumpList(tester, places: _places());

      final tile = find.byKey(const ValueKey('place-tile-p1'));
      expect(find.descendant(of: tile, matching: find.text('El Chinito')),
          findsOneWidget);
      expect(find.descendant(of: tile, matching: find.byIcon(Icons.star_rounded)),
          findsOneWidget);
      expect(find.descendant(of: tile, matching: find.text(' 4.6')),
          findsOneWidget);
      // p1 tiene distancia; p2 no, y entonces no se muestra ese pedazo.
      expect(
          find.descendant(
              of: tile, matching: find.text('Cevichería · 350 m · Desde S/ 18')),
          findsOneWidget);
      expect(find.text('Cevichería · Desde S/ 18'), findsNWidgets(2));
    });

    testWidgets('"🔥" sale solo en los locales con hasActiveBenefit',
        (tester) async {
      await pumpList(tester, places: _places());

      expect(find.textContaining('🔥'), findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('place-tile-p1')),
              matching: find.textContaining('🔥')),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('place-tile-p2')),
              matching: find.textContaining('🔥')),
          findsNothing);
    });

    testWidgets('"Abierto" sale solo cuando la lista viene filtrada por abierto',
        (tester) async {
      await pumpList(tester, places: _places());
      expect(find.text('Abierto'), findsNothing);

      await pumpList(tester, places: _places(), openNow: true);
      expect(find.text('Abierto'), findsNWidgets(3));
    });

    testWidgets('mientras carga y sin locales dice "Cargando…", no "No hay"',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      Future<void> pumpState({bool loading = false, bool failed = false}) =>
          tester.pumpWidget(MaterialApp(
            home: Scaffold(
              body: ExploreBottomList(
                places: const [],
                loading: loading,
                failed: failed,
                onPlaceTap: (_) {},
                onSurprise: () {},
              ),
            ),
          ));

      await pumpState(loading: true);
      expect(find.text('Cargando…'), findsOneWidget);
      expect(find.textContaining('No hay locales'), findsNothing);

      await pumpState(failed: true);
      expect(find.text('No pudimos cargar los locales'), findsOneWidget);
      expect(find.text('Cargando…'), findsNothing);

      await pumpState();
      expect(find.text('No hay locales para mostrar por ahora.'),
          findsOneWidget);
    });

    testWidgets('sin precio ni categoría esas partes no se inventan',
        (tester) async {
      await pumpList(tester, places: [
        Place(id: 'x', name: 'Sin datos'),
      ]);
      expect(find.text('Sin datos'), findsOneWidget);
      expect(find.textContaining('Desde S/'), findsNothing);
      expect(find.byIcon(Icons.star_rounded), findsNothing);
    });

    testWidgets('tocar una tarjeta avisa con ese local', (tester) async {
      final tapped = <String>[];
      await pumpList(tester,
          places: _places(), onPlaceTap: (p) => tapped.add(p.id));

      await tester.tap(find.byKey(const ValueKey('place-tile-p2')));
      expect(tapped, ['p2']);
    });
  });

  test('formatDistance y formatPrice', () {
    expect(formatDistance(350.4), '350 m');
    expect(formatDistance(1234), '1.2 km');
    expect(formatPrice(18), '18');
    expect(formatPrice(18.5), '18.50');
  });

  test('Place.fromJson lee hasActiveBenefit (y por defecto es falso)', () {
    expect(Place.fromJson(_placeJson('a', 'A', benefit: true)).hasActiveBenefit,
        isTrue);
    expect(Place.fromJson({'id': 'b', 'name': 'B'}).hasActiveBenefit, isFalse);
  });

  group('ExploreScreen', () {
    testWidgets('buscador, interruptor y filtros que ya existían', (tester) async {
      await _pump(tester, ExploreScreen(api: _mockApi([])));

      expect(find.text('¿Qué se te antoja?'), findsOneWidget);
      expect(find.byKey(const Key('explore-avatar')), findsOneWidget);
      expect(find.text('🍽️ Locales'), findsOneWidget);
      expect(find.text('⚡ Ahora'), findsOneWidget);
      // Categoría, abierto y distancia (+ filtros avanzados) siguen.
      expect(find.byIcon(Icons.tune_rounded), findsOneWidget);
      expect(find.text('Categoría'), findsOneWidget);
      await _scrollChipsToEnd(tester);
      expect(find.text('Abierto ahora'), findsOneWidget);
      expect(find.text('Distancia'), findsOneWidget);
      expect(find.byIcon(Icons.my_location_rounded), findsOneWidget);
    });

    testWidgets('la lista se llena con los locales cargados y se recarga al filtrar',
        (tester) async {
      final seen = <http.Request>[];
      await _pump(
          tester,
          ExploreScreen(
              api: _mockApi([
            _placeJson('p1', 'El Chinito', benefit: true),
            _placeJson('p2', 'Don Lucho'),
          ], seen: seen)));

      expect(find.text('Cerca de ti · 2'), findsOneWidget);
      expect(find.text('El Chinito'), findsOneWidget);
      expect(find.text('Abierto'), findsNothing);

      // Filtro "Abierto ahora": pide de nuevo con openNow y la lista lo refleja.
      seen.clear();
      await _scrollChipsToEnd(tester);
      await tester.tap(find.text('Abierto ahora'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final places = seen.where((r) => r.url.path.endsWith('/places')).toList();
      expect(places, hasLength(1));
      expect(places.single.url.queryParameters['openNow'], 'true');
      expect(find.text('Abierto'), findsNWidgets(2));
    });

    testWidgets(
        'al activar "Abierto ahora" la lista vieja no dice "Abierto" hasta que llega la respuesta',
        (tester) async {
      final gated = _GatedApi([
        _placeJson('p1', 'El Chinito'),
        _placeJson('p2', 'Don Lucho'),
      ], second: [
        _placeJson('p1', 'El Chinito'),
      ]);
      await _pump(tester, ExploreScreen(api: gated.api));
      await gated.release(tester, 0);
      expect(find.text('Cerca de ti · 2'), findsOneWidget);

      await _scrollChipsToEnd(tester);
      await tester.tap(find.text('Abierto ahora'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // La petición con openNow sigue pendiente: lista vieja, sin etiqueta.
      expect(gated.pending, 2);
      expect(find.text('Cerca de ti · 2'), findsOneWidget);
      expect(find.text('Abierto'), findsNothing);

      await gated.release(tester, 1);
      expect(find.text('Cerca de ti · 1'), findsOneWidget);
      expect(find.text('Abierto'), findsOneWidget);
    });

    testWidgets('texto de la lista vacía: "Cargando…" y luego el fallo',
        (tester) async {
      final gated =
          _GatedApi([_placeJson('p1', 'El Chinito')], failSecond: true);
      await _pump(tester, ExploreScreen(api: gated.api));

      // Primera carga en vuelo.
      expect(find.text('Cargando…'), findsOneWidget);
      expect(find.textContaining('No hay locales'), findsNothing);
      await gated.release(tester, 0);
      expect(find.text('Cargando…'), findsNothing);
      expect(find.text('El Chinito'), findsOneWidget);

      // Segunda carga (filtro) que falla: la lista queda vacía con el aviso.
      await _scrollChipsToEnd(tester);
      await tester.tap(find.text('Abierto ahora'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('El Chinito'), findsOneWidget); // todavía la vieja
      await gated.release(tester, 1);

      expect(find.text('No pudimos cargar los locales'), findsOneWidget);
      expect(find.text('Cargando…'), findsNothing);
      expect(find.textContaining('No hay locales'), findsNothing);
      expect(find.text('Cerca de ti · 0'), findsOneWidget);
    });

    testWidgets('tocar una tarjeta abre la ficha del local', (tester) async {
      await _pump(
          tester, ExploreScreen(api: _mockApi([_placeJson('p1', 'El Chinito')])));

      await tester.tap(find.byKey(const ValueKey('place-tile-p1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final detail =
          tester.widget<PlaceDetailScreen>(find.byType(PlaceDetailScreen));
      expect(detail.placeId, 'p1');
    });

    testWidgets('"✨ Sorpréndeme" abre DiscoveryScreen', (tester) async {
      await _pump(tester, ExploreScreen(api: _mockApi([])));

      await tester.tap(find.text('✨ Sorpréndeme'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(DiscoveryScreen), findsOneWidget);
    });

    testWidgets('el interruptor cambia de modo y la pantalla sigue mostrando locales',
        (tester) async {
      await _pump(
          tester, ExploreScreen(api: _mockApi([_placeJson('p1', 'El Chinito')])));

      await tester.tap(find.text('⚡ Ahora'));
      await tester.pump();

      // Hasta que llegue la capa Ahora, se ve lo mismo.
      expect(find.text('Cerca de ti · 1'), findsOneWidget);
      expect(find.text('El Chinito'), findsOneWidget);
    });

    testWidgets('el avatar avisa para abrir el perfil', (tester) async {
      var opened = 0;
      await _pump(tester,
          ExploreScreen(api: _mockApi([]), onOpenProfile: () => opened++));

      await tester.tap(find.byKey(const Key('explore-avatar')));
      expect(opened, 1);
    });
  });

  testWidgets('en el shell, el avatar de Explorar cambia a la pestaña Perfil',
      (tester) async {
    // ProfileScreen ya desborda con la fuente de prueba (muy ancha).
    final onError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (!details.exceptionAsString().contains('overflowed')) {
        onError!(details);
      }
    };
    addTearDown(() => FlutterError.onError = onError);

    await _pump(tester, const MainShell());
    expect(find.byType(ExploreScreen), findsOneWidget);
    expect(find.byType(ProfileScreen), findsNothing);

    await tester.tap(find.byKey(const Key('explore-avatar')));
    await tester.pump();

    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(find.byType(ExploreScreen), findsNothing);
  });
}
