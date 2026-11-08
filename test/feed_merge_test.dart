import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wuarikes_app/core/api_client.dart';
import 'package:wuarikes_app/core/models.dart';
import 'package:wuarikes_app/core/now_models.dart';
import 'package:wuarikes_app/screens/feed_screen.dart';
import 'package:wuarikes_app/screens/now/now_post_screen.dart';
import 'package:wuarikes_app/state/auth_provider.dart';

Map<String, dynamic> _checkinJson(String id, DateTime at,
        {String comment = 'Rico el ceviche', String user = 'Carlos'}) =>
    {
      'id': id,
      'placeId': 'pl-1',
      'comment': comment,
      'rating': 5,
      'likesCount': 0,
      'createdAt': at.toUtc().toIso8601String(),
      'user': {'id': 'u-$user', 'fullName': user},
    };

Map<String, dynamic> _postJson(String id, DateTime at,
        {String text = 'Feria en el parque', String author = 'Maritza'}) =>
    {
      'id': id,
      'kind': 'text',
      'text': text,
      'mediaUrl': null,
      'latitude': -12.1211,
      'longitude': -77.0296,
      'visibility': 'all',
      'likes': 3,
      'dislikes': 1,
      'checks': 2,
      'expiresAt': DateTime.now()
          .add(const Duration(hours: 19, minutes: 30))
          .toUtc()
          .toIso8601String(),
      'createdAt': at.toUtc().toIso8601String(),
      'author': {'id': 'a-1', 'fullName': author, 'avatarUrl': null},
      'myReaction': null,
    };

CheckinItem _checkin(String id, DateTime at) =>
    CheckinItem.fromJson(_checkinJson(id, at));
NowPost _post(String id, DateTime at) => NowPost.fromJson(_postJson(id, at));

const _json = {'content-type': 'application/json; charset=utf-8'};
http.Response _ok(Object body) =>
    http.Response(jsonEncode(body), 200, headers: _json);

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

/// Backend de mentira: check-ins por `/checkins/feed[/following]`, Ahora por
/// `/now/feed?scope=` y una publicación por `/now/posts/:id`. Anota todo.
class _Fake {
  final seen = <http.Request>[];
  var checkins = <Map<String, dynamic>>[];
  final now = <String, List<Map<String, dynamic>>>{};
  bool failCheckins = false, failNow = false;

  /// Páginas totales que declara cada fuente (1 = no hay más).
  int checkinPages = 1, nowPages = 1;

  late final api = ApiClient(client: MockClient((req) async {
    seen.add(req);
    final path = req.url.path;
    if (path.endsWith('/checkins/feed') ||
        path.endsWith('/checkins/feed/following') ||
        path.endsWith('/users/me/checkins')) {
      if (failCheckins) return http.Response('{"message":"boom"}', 500);
      return _ok({
        'data': checkins,
        'total': checkins.length,
        'page': 1,
        'totalPages': checkinPages,
      });
    }
    if (path.endsWith('/now/feed')) {
      if (failNow) return http.Response('{"message":"boom"}', 500);
      final posts = now[req.url.queryParameters['scope']] ?? [];
      // Sin `page` ni `totalPages`, como el backend: la app lo calcula con total/20.
      return _ok({'data': posts, 'total': nowPages > 1 ? 21 : posts.length});
    }
    if (path.contains('/now/posts/')) {
      return _ok(now.values.expand((l) => l).first);
    }
    return _ok({});
  }));

  List<http.Request> calls(String suffix) =>
      seen.where((r) => r.url.path.endsWith(suffix)).toList();
}

AuthProvider _auth({bool loggedIn = true}) {
  final auth = AuthProvider(ApiClient());
  if (loggedIn) {
    auth.user = AppUser(id: 'me-1', email: 'a@b.pe', fullName: 'Ana Prueba');
  }
  return auth;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _pump(WidgetTester tester, _Fake fake,
    {AuthProvider? auth,
    Future<Position?> Function()? locate,
    String? placeId,
    bool history = false}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ChangeNotifierProvider<AuthProvider>.value(
    value: auth ?? _auth(),
    child: MaterialApp(
      home: FeedScreen(
          api: fake.api,
          locate: locate ?? () async => null,
          placeId: placeId,
          history: history),
    ),
  ));
  await _settle(tester);
}

Future<void> _tapScope(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.pump();
  await tester.tap(find.text(label));
  await _settle(tester);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('mergeFeed', () {
    final t = DateTime.utc(2026, 11, 7, 12);

    test('intercala por fecha descendente', () {
      final merged = mergeFeed(
        [
          _checkin('c-viejo', t.subtract(const Duration(hours: 4))),
          _checkin('c-medio', t.subtract(const Duration(hours: 2))),
        ],
        [
          _post('p-nuevo', t),
          _post('p-medio', t.subtract(const Duration(hours: 3))),
        ],
      );

      expect(merged.map((e) => switch (e) {
            CheckinEntry(:final item) => item.id,
            PostEntry(:final post) => post.id,
          }), ['p-nuevo', 'c-medio', 'p-medio', 'c-viejo']);
      expect(merged.map((e) => e.at).toList(),
          orderedEquals([...merged.map((e) => e.at)]..sort((a, b) => b.compareTo(a))));
    });

    test('a igual fecha conserva el orden de entrada (check-ins primero)', () {
      final merged = mergeFeed(
        [_checkin('c1', t), _checkin('c2', t)],
        [_post('p1', t), _post('p2', t)],
      );

      expect(merged.map((e) => e is CheckinEntry ? e.item.id : (e as PostEntry).post.id),
          ['c1', 'c2', 'p1', 'p2']);
    });

    test('listas vacías y fecha ilegible no rompen', () {
      expect(mergeFeed([], []), isEmpty);
      final broken = CheckinItem(id: 'c-roto', placeId: 'x', createdAt: 'no-es-fecha');
      final merged = mergeFeed([broken], [_post('p1', t)]);
      expect(merged.last, isA<CheckinEntry>());
    });
  });

  group('Actividad', () {
    final t = DateTime.now();

    testWidgets('Cerca de mí sin ubicación avisa y no llama a la API',
        (tester) async {
      final fake = _Fake();
      await _pump(tester, fake);
      await _tapScope(tester, 'Cerca de mí');

      expect(find.text('Activa tu ubicación para ver lo que pasa cerca'),
          findsOneWidget);
      expect(fake.calls('/now/feed'), isEmpty);
    });

    testWidgets('Cerca de mí con ubicación pide scope=nearby con lat y lng',
        (tester) async {
      final fake = _Fake()
        ..now['nearby'] = [_postJson('p1', t, text: 'Cola larga en el local')];
      await _pump(tester, fake, locate: () async => _at(-12.05, -77.04));
      await _tapScope(tester, 'Cerca de mí');

      final calls = fake.calls('/now/feed');
      expect(calls, hasLength(1));
      expect(calls.single.url.queryParameters,
          {'scope': 'nearby', 'page': '1', 'lat': '-12.05', 'lng': '-77.04'});
      expect(find.text('Cola larga en el local'), findsOneWidget);
      expect(find.text('Activa tu ubicación para ver lo que pasa cerca'),
          findsNothing);
    });

    testWidgets('Amigos pide scope=friends y solo muestra publicaciones',
        (tester) async {
      final fake = _Fake()
        ..checkins = [_checkinJson('c1', t, comment: 'No debe salir aquí')]
        ..now['friends'] = [_postJson('p1', t, text: 'Hay anticuchos')];
      await _pump(tester, fake);
      fake.seen.clear();
      await _tapScope(tester, 'Amigos');

      expect(fake.calls('/now/feed').single.url.queryParameters['scope'],
          'friends');
      expect(fake.calls('/checkins/feed'), isEmpty);
      expect(find.text('Hay anticuchos'), findsOneWidget);
      expect(find.text('No debe salir aquí'), findsNothing);
    });

    testWidgets('invitado: Amigos y Cerca piden iniciar sesión, sin llamar',
        (tester) async {
      final fake = _Fake()
        ..checkins = [_checkinJson('c1', t, comment: 'Lo ve el invitado')];
      await _pump(tester, fake, auth: _auth(loggedIn: false));

      // Hoy el invitado ve el feed general: se conserva.
      expect(find.text('Lo ve el invitado'), findsOneWidget);
      expect(fake.calls('/checkins/feed'), hasLength(1));
      fake.seen.clear();

      await _tapScope(tester, 'Amigos');
      expect(find.text('Inicia sesión para ver lo que publican tus amigos'),
          findsOneWidget);
      expect(find.text('Iniciar sesión'), findsOneWidget);

      await _tapScope(tester, 'Cerca de mí');
      expect(find.text('Inicia sesión para ver lo que pasa cerca de ti'),
          findsOneWidget);
      expect(fake.seen, isEmpty);
    });

    testWidgets('una publicación muestra "⚡ quedan" y abre NowPostScreen',
        (tester) async {
      final fake = _Fake()
        ..now['following'] = [_postJson('p1', t, text: 'Feria en el parque')];
      await _pump(tester, fake);
      await _tapScope(tester, 'Siguiendo');

      expect(find.textContaining('⚡ quedan 19 h'), findsOneWidget);
      expect(find.text('@Maritza'), findsOneWidget);
      expect(find.text('Feria en el parque'), findsOneWidget);

      await tester.tap(find.text('Feria en el parque'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(NowPostScreen), findsOneWidget);
      expect(tester.widget<NowPostScreen>(find.byType(NowPostScreen)).postId,
          'p1');
    });

    testWidgets('Siguiendo mezcla check-ins y publicaciones por fecha',
        (tester) async {
      final fake = _Fake()
        ..checkins = [
          _checkinJson('c1', t.subtract(const Duration(hours: 1)),
              comment: 'Check-in reciente'),
          _checkinJson('c2', t.subtract(const Duration(hours: 5)),
              comment: 'Check-in viejo'),
        ]
        ..now['following'] = [
          _postJson('p1', t.subtract(const Duration(hours: 3)),
              text: 'Post del medio'),
        ];
      await _pump(tester, fake);
      fake.seen.clear();
      await _tapScope(tester, 'Siguiendo');

      // Los dos orígenes con lo que ya pedía Siguiendo.
      expect(fake.calls('/checkins/feed/following'), hasLength(1));
      expect(fake.calls('/now/feed').single.url.queryParameters['scope'],
          'following');

      double y(String text) => tester.getTopLeft(find.text(text)).dy;
      expect(y('Check-in reciente'), lessThan(y('Post del medio')));
      expect(y('Post del medio'), lessThan(y('Check-in viejo')));
    });

    testWidgets('si una fuente falla se ve la otra y un aviso', (tester) async {
      final fake = _Fake()
        ..checkins = [_checkinJson('c1', t, comment: 'Check-in que sí llegó')]
        ..failNow = true;
      await _pump(tester, fake);
      await _tapScope(tester, 'Siguiendo');

      expect(find.text('Check-in que sí llegó'), findsOneWidget);
      expect(find.text('No se pudo cargar todo'), findsOneWidget);
      expect(find.text('Reintentar'), findsNothing);
    });

    testWidgets('si fallan los check-ins se ven las publicaciones',
        (tester) async {
      final fake = _Fake()
        ..failCheckins = true
        ..now['following'] = [_postJson('p1', t, text: 'Post que sí llegó')];
      await _pump(tester, fake);
      // La pestaña inicial (Todos) solo tiene check-ins: falla y se reintenta.
      expect(find.text('Reintentar'), findsOneWidget);
      await _tapScope(tester, 'Siguiendo');

      expect(find.text('Post que sí llegó'), findsOneWidget);
      expect(find.text('No se pudo cargar todo'), findsOneWidget);
    });

    testWidgets('si fallan las dos fuentes sale el error con Reintentar',
        (tester) async {
      final fake = _Fake()
        ..failCheckins = true
        ..failNow = true;
      await _pump(tester, fake);
      await _tapScope(tester, 'Siguiendo');

      expect(find.text('Reintentar'), findsOneWidget);
      expect(find.text('No se pudo cargar todo'), findsNothing);
    });

    testWidgets('Cargar más pide la página siguiente solo de la fuente que tiene',
        (tester) async {
      final fake = _Fake()
        ..checkinPages = 2
        ..checkins = [_checkinJson('c1', t, comment: 'Página uno')]
        ..now['following'] = [_postJson('p1', t, text: 'Post único')];
      await _pump(tester, fake);
      await _tapScope(tester, 'Siguiendo');
      fake.seen.clear();

      await tester.ensureVisible(find.text('Cargar más'));
      await tester.tap(find.text('Cargar más'));
      await _settle(tester);

      expect(fake.calls('/checkins/feed/following').single.url.queryParameters['page'],
          '2');
      expect(fake.calls('/now/feed'), isEmpty);
      expect(find.text('Cargar más'), findsNothing);
    });

    testWidgets('Todos sigue siendo la pestaña inicial: mismo endpoint de siempre',
        (tester) async {
      final fake = _Fake()
        ..checkins = [_checkinJson('c1', t, comment: 'Del feed general')];
      await _pump(tester, fake);

      expect(find.text('Del feed general'), findsOneWidget);
      expect(fake.seen, hasLength(1));
      final req = fake.seen.single;
      expect(req.url.path, endsWith('/checkins/feed'));
      expect(req.url.queryParameters,
          {'size': '20', 'page': '1', 'sort': 'recent'});
    });

    testWidgets('FeedScreen(placeId) no tiene pestañas de Ahora y llama a lo mismo',
        (tester) async {
      final fake = _Fake()
        ..checkins = [_checkinJson('c1', t, comment: 'Reseña del local')];
      await _pump(tester, fake, placeId: 'p1');

      expect(find.text('Reseña del local'), findsOneWidget);
      for (final label in ['Todos', 'Siguiendo', 'Cerca de mí', 'Amigos']) {
        expect(find.text(label), findsNothing, reason: label);
      }
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.text('Más recientes'), findsOneWidget); // el orden sigue ahí
      expect(fake.seen, hasLength(1));
      final req = fake.seen.single;
      expect(req.url.path, endsWith('/checkins/feed'));
      expect(req.url.queryParameters,
          {'size': '20', 'page': '1', 'sort': 'recent', 'placeId': 'p1'});
    });

    testWidgets('el historial (history) sigue llamando a /users/me/checkins',
        (tester) async {
      final fake = _Fake()
        ..checkins = [_checkinJson('c1', t, comment: 'Mi visita')];
      await _pump(tester, fake, history: true);

      expect(find.text('Mi visita'), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(fake.seen.single.url.path, endsWith('/users/me/checkins'));
      expect(fake.calls('/now/feed'), isEmpty);
    });

    testWidgets('invitado en reseñas de un local: sin pestañas ni aviso',
        (tester) async {
      final fake = _Fake()
        ..checkins = [_checkinJson('c1', t, comment: 'Reseña pública')];
      await _pump(tester, fake, auth: _auth(loggedIn: false), placeId: 'p1');

      expect(find.text('Reseña pública'), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.text('Iniciar sesión'), findsNothing);
    });
  });
}
