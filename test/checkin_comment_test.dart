import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wuarikes_app/core/api_client.dart';
import 'package:wuarikes_app/core/models.dart';
import 'package:wuarikes_app/screens/new_checkin_screen.dart';

const _json = {'content-type': 'application/json; charset=utf-8'};

Position _at(double lat, double lng) => Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime(2026, 11, 7),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

Place _place(
        {List<String> dishes = const ['Ceviche clásico', 'Leche de tigre']}) =>
    Place(id: 'p1', name: 'El Chinito', dishes: [
      for (var i = 0; i < dishes.length; i++) Dish(id: 'd$i', name: dishes[i]),
    ]);

/// Servidor de mentira: anota las peticiones y contesta el check-in y las stats.
class _Fake {
  final seen = <http.Request>[];

  /// Respuesta de `POST /checkins`; por defecto, creado.
  http.Response Function()? onCheckin;
  var _stats = 0;

  late final api = ApiClient(client: MockClient((req) async {
    seen.add(req);
    if (req.url.path.endsWith('/gamification/my-stats')) {
      _stats++;
      return http.Response(
          jsonEncode({
            'level': 1,
            'xp': _stats == 1 ? 100 : 110,
            'nextLevelXp': 1000,
            'checkinsCount': 1,
          }),
          200,
          headers: _json);
    }
    if (req.method == 'POST' && req.url.path.endsWith('/checkins')) {
      return onCheckin?.call() ??
          http.Response(
              jsonEncode({
                'id': 'c1',
                'placeId': 'p1',
                'createdAt': '2026-11-07T10:00:00Z',
              }),
              201,
              headers: _json);
    }
    return http.Response('{}', 404);
  }));

  Map<String, dynamic> get checkinBody => jsonDecode(seen
      .lastWhere((r) => r.method == 'POST' && r.url.path.endsWith('/checkins'))
      .body) as Map<String, dynamic>;

  bool get postedCheckin =>
      seen.any((r) => r.method == 'POST' && r.url.path.endsWith('/checkins'));
}

Future<void> _pump(WidgetTester tester, _Fake fake,
    {Place? place, XFile? photo}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: NewCheckinScreen(
      place: place ?? _place(),
      api: fake.api,
      locate: () async => _at(-12.12, -77.03),
      pickPhoto: () async => photo,
    ),
  ));
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
  await tester.pump();
}

Future<void> _publish(WidgetTester tester) async {
  await _tap(tester, find.text('Publicar check-in'));
  // Deja resolver las llamadas de mentira (sin pumpAndSettle).
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

bool _on(WidgetTester tester, String label) =>
    tester.widget<FilterChip>(find.widgetWithText(FilterChip, label)).selected;

void main() {
  group('buildCheckinComment', () {
    test('chips y texto', () {
      expect(buildCheckinComment(['😋 Rico'], 'Top'), '😋 Rico — Top');
      expect(buildCheckinComment(['😋 Rico', '💸 Buen precio'], 'Top'),
          '😋 Rico · 💸 Buen precio — Top');
    });

    test('sin chips, solo el texto', () {
      expect(buildCheckinComment([], 'Top'), 'Top');
      expect(buildCheckinComment([], '  Top  '), 'Top');
      expect(buildCheckinComment([], ''), '');
    });

    test('sin texto, solo los chips', () {
      expect(buildCheckinComment(['😋 Rico', '⚡ Rápido'], ''),
          '😋 Rico · ⚡ Rápido');
      expect(buildCheckinComment(['😋 Rico'], '   '), '😋 Rico');
    });

    test('los 4 chips y el texto más largo caben en los 200 del backend', () {
      final c = buildCheckinComment(checkinChips, 'x' * checkinTextMax);
      expect(c.length, lessThanOrEqualTo(200));
    });
  });

  test('puntos: 10, y 5 más con foto (los del backend)', () {
    expect(checkinPoints(hasPhoto: false), 10);
    expect(checkinPoints(hasPhoto: true), 15);
  });

  group('pantalla', () {
    testWidgets('los chips de opinión se prenden y se apagan', (tester) async {
      await _pump(tester, _Fake());

      for (final c in checkinChips) {
        expect(_on(tester, c), isFalse);
      }
      await _tap(tester, find.text('😋 Rico'));
      expect(_on(tester, '😋 Rico'), isTrue);
      expect(_on(tester, '⚡ Rápido'), isFalse);
      await _tap(tester, find.text('😋 Rico'));
      expect(_on(tester, '😋 Rico'), isFalse);
    });

    testWidgets('los puntos son 10 y 15 con foto, antes de publicar',
        (tester) async {
      await _pump(tester, _Fake(), photo: XFile('/no/existe.jpg'));

      expect(find.text('+10 pts'), findsOneWidget);
      expect(find.text('+15 pts'), findsNothing);

      await _tap(tester, find.byIcon(Icons.add_a_photo_outlined));
      expect(find.text('+15 pts'), findsOneWidget);
      expect(find.text('+10 pts'), findsNothing);

      await _tap(tester, find.byIcon(Icons.close)); // quita la foto
      expect(find.text('+10 pts'), findsOneWidget);
    });

    testWidgets('el comentario enviado es buildCheckinComment(chips, texto)',
        (tester) async {
      final fake = _Fake();
      await _pump(tester, fake);

      await _tap(tester, find.text('⚡ Rápido'));
      await _tap(tester, find.text('😋 Rico')); // el orden no depende del toque
      await tester.enterText(
          find.widgetWithText(TextField, 'Cuéntale a la comunidad… (opcional)'),
          'Top');
      await _tap(
          tester, find.byIcon(Icons.star_outline_rounded).at(3)); // 4 estrellas
      await _tap(tester, find.text('Leche de tigre'));
      await _publish(tester);

      final body = fake.checkinBody;
      expect(
          body['comment'], buildCheckinComment(['😋 Rico', '⚡ Rápido'], 'Top'));
      expect(body['comment'], '😋 Rico · ⚡ Rápido — Top');
      expect(body['dishName'], 'Leche de tigre');
      expect(body['placeId'], 'p1');
      expect(body['rating'], 4);
      expect(body['latitude'], -12.12);
      expect(body['longitude'], -77.03);
      expect(body['accuracyMeters'], 5);
      expect(body['isMocked'], false);
    });

    testWidgets('sin chips ni texto no manda comentario, como antes',
        (tester) async {
      final fake = _Fake();
      await _pump(tester, fake);

      await _publish(tester);

      expect(fake.postedCheckin, isTrue);
      expect(fake.checkinBody.containsKey('comment'), isFalse);
      expect(fake.checkinBody.containsKey('dishName'), isFalse);
      expect(fake.checkinBody.containsKey('rating'), isFalse);
    });

    testWidgets('"+ Otro" deja escribir el plato; el chip se apaga',
        (tester) async {
      final fake = _Fake();
      await _pump(tester, fake);

      expect(find.widgetWithText(TextField, '¿Qué pediste? (opcional)'),
          findsNothing);
      await _tap(tester, find.text('Ceviche clásico'));
      expect(_on(tester, 'Ceviche clásico'), isTrue);

      await _tap(tester, find.text('+ Otro'));
      expect(_on(tester, 'Ceviche clásico'), isFalse);
      await tester.enterText(
          find.widgetWithText(TextField, '¿Qué pediste? (opcional)'),
          'Arroz con mariscos');
      await _publish(tester);

      expect(fake.checkinBody['dishName'], 'Arroz con mariscos');
    });

    testWidgets('un local sin platos deja escribir el plato de entrada',
        (tester) async {
      final fake = _Fake();
      await _pump(tester, fake, place: _place(dishes: const []));

      expect(find.text('+ Otro'), findsNothing);
      await tester.enterText(
          find.widgetWithText(TextField, '¿Qué pediste? (opcional)'), 'Lomo');
      await _publish(tester);

      expect(fake.checkinBody['dishName'], 'Lomo');
    });

    testWidgets('precio sin plato se rechaza igual que antes', (tester) async {
      final fake = _Fake();
      await _pump(tester, fake);

      await tester.enterText(
          find.widgetWithText(TextField, 'Precio del plato S/ (opcional)'),
          '28,5');
      await _publish(tester);

      expect(find.text('Ingresa el plato y un precio válido.'), findsOneWidget);
      expect(fake.postedCheckin, isFalse);

      await _tap(tester, find.text('Ceviche clásico'));
      await _publish(tester);
      expect(fake.checkinBody['dishPrice'], 28.5);
      expect(fake.checkinBody['dishName'], 'Ceviche clásico');
    });

    testWidgets('al publicar muestra los puntos reales y avisa del check-in',
        (tester) async {
      final fake = _Fake();
      final before = ApiClient.checkinCreated.value;
      await _pump(tester, fake);

      await _publish(tester);

      expect(find.text('¡Check-in registrado!'), findsOneWidget);
      expect(find.text('+10 XP'), findsOneWidget); // 110 - 100 de las stats
      expect(ApiClient.checkinCreated.value, before + 1);
    });

    testWidgets(
        'el error del servidor se muestra tal cual y se puede reintentar',
        (tester) async {
      final fake = _Fake()
        ..onCheckin = () => http.Response(
            jsonEncode({
              'message': 'Estás muy lejos de El Chinito para hacer check-in.'
            }),
            400,
            headers: _json);
      await _pump(tester, fake);
      await _tap(tester, find.text('😋 Rico'));

      await _publish(tester);

      expect(find.text('Estás muy lejos de El Chinito para hacer check-in.'),
          findsOneWidget);
      expect(find.text('¡Check-in registrado!'), findsNothing);
      expect(_on(tester, '😋 Rico'), isTrue); // lo elegido sigue ahí
      expect(find.text('Publicar check-in'), findsOneWidget);
    });
  });
}
