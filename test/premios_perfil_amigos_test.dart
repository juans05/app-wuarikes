import 'dart:async';
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
import 'package:wuarikes_app/screens/favorites_screen.dart';
import 'package:wuarikes_app/screens/friends_screen.dart';
import 'package:wuarikes_app/screens/messages_screen.dart';
import 'package:wuarikes_app/screens/my_loyalty_screen.dart';
import 'package:wuarikes_app/screens/my_posts_screen.dart';
import 'package:wuarikes_app/screens/now/now_post_screen.dart';
import 'package:wuarikes_app/screens/profile_screen.dart';
import 'package:wuarikes_app/screens/social_screen.dart';
import 'package:wuarikes_app/state/auth_provider.dart';

const _json = {'content-type': 'application/json; charset=utf-8'};
http.Response _ok(Object body) =>
    http.Response(jsonEncode(body), 200, headers: _json);
http.Response _fail(int status) =>
    http.Response('{"message":"boom"}', status, headers: _json);

AuthProvider _auth({bool loggedIn = true}) {
  final auth = AuthProvider(ApiClient());
  if (loggedIn) {
    auth.user = AppUser(id: 'me-1', email: 'a@b.pe', fullName: 'Ana Prueba');
  }
  return auth;
}

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

Future<void> _pump(WidgetTester tester, Widget home, AuthProvider auth) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ChangeNotifierProvider<AuthProvider>.value(
    value: auth,
    child: MaterialApp(home: home),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// ProfileScreen ya desborda con la fuente de prueba (Ahem, muy ancha).
void _ignoreOverflow() {
  final onError = FlutterError.onError;
  FlutterError.onError = (details) {
    if (!details.exceptionAsString().contains('overflowed')) {
      onError!(details);
    }
  };
  addTearDown(() => FlutterError.onError = onError);
}

// ---------------------------------------------------------------- Premios

/// Los sellos de las tarjetas: `stamp-full-N` / `stamp-empty-N`.
Finder _stamps(String kind) => find.byWidgetPredicate((w) =>
    w.key is ValueKey<String> &&
    (w.key as ValueKey<String>).value.startsWith('stamp-$kind-'));

Map<String, dynamic> _card(String placeId, String name,
        {String type = 'stamps',
        int stamps = 0,
        int? goal,
        int? remaining,
        double lat = -12.046,
        double lng = -77.042,
        int points = 0}) =>
    {
      'placeId': placeId,
      'placeName': name,
      'placeCoverImageUrl': null,
      'latitude': lat,
      'longitude': lng,
      'programType': type,
      'stamps': stamps,
      'points': points,
      'stampsToReward': goal,
      'stampsRemaining': remaining,
      'level': 'BRONCE',
      'rewardTitle': 'Postre gratis',
    };

ApiClient _cardsApi(List<Map<String, dynamic>> cards) => ApiClient(
    client: MockClient((req) async => req.url.path.endsWith('/loyalty/my-cards')
        ? _ok(cards)
        : _ok({})));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Premios', () {
    testWidgets('titulo "Mis premios" y "Listo para canjear" solo en las completas',
        (tester) async {
      await _pump(
          tester,
          MyLoyaltyScreen(
              api: _cardsApi([
                // 6 de 8: faltan 2.
                _card('p1', 'El Chinito', stamps: 6, goal: 8, remaining: 2),
                // Completa como la manda el backend: meta - (sellos % meta) = meta.
                _card('p2', 'Cafe Bisetti', stamps: 4, goal: 4, remaining: 4),
                // Completa con faltan 0 (el backend no lo manda, pero sigue siendo completa).
                _card('p3', 'Barberia Don Lucho',
                    stamps: 5, goal: 5, remaining: 0),
                // Puntos: no hay sellos que completar.
                _card('p4', 'Pizzeria', type: 'points', points: 120),
              ]),
              locate: () async => null),
          _auth());

      expect(find.text('Mis premios'), findsOneWidget);
      expect(find.text('Mis Fidelizaciones'), findsNothing);
      for (final n in ['El Chinito', 'Cafe Bisetti', 'Barberia Don Lucho']) {
        expect(find.text(n), findsOneWidget, reason: n);
      }
      expect(find.text('🎉 ¡Listo para canjear!'), findsNWidgets(2));
      expect(find.text('2 sellos para "Postre gratis"'), findsOneWidget);
      expect(find.text('120 puntos acumulados'), findsOneWidget);
    });

    testWidgets(
        'con sellos de sobra (10 de 8, el backend manda faltan 6) esta listo',
        (tester) async {
      await _pump(
          tester,
          MyLoyaltyScreen(
              api: _cardsApi(
                  [_card('p1', 'El Chinito', stamps: 10, goal: 8, remaining: 6)]),
              locate: () async => null),
          _auth());

      expect(find.text('🎉 ¡Listo para canjear!'), findsOneWidget);
      expect(_stamps('full'), findsNWidgets(8));
      expect(_stamps('empty'), findsNothing);
    });

    testWidgets('sin tarjetas completas no sale "Listo para canjear"',
        (tester) async {
      await _pump(
          tester,
          MyLoyaltyScreen(
              api: _cardsApi(
                  [_card('p1', 'El Chinito', stamps: 7, goal: 8, remaining: 1)]),
              locate: () async => null),
          _auth());

      expect(find.text('El Chinito'), findsOneWidget);
      expect(find.text('1 sello para "Postre gratis"'), findsOneWidget);
      expect(find.text('🎉 ¡Listo para canjear!'), findsNothing);
    });

    testWidgets('sellos llenos y vacios segun el avance', (tester) async {
      await _pump(
          tester,
          MyLoyaltyScreen(
              api: _cardsApi(
                  [_card('p1', 'El Chinito', stamps: 6, goal: 8, remaining: 2)]),
              locate: () async => null),
          _auth());

      expect(_stamps('full'), findsNWidgets(6));
      expect(_stamps('empty'), findsNWidgets(2));
    });

    testWidgets('una tarjeta completa pinta todos los sellos llenos',
        (tester) async {
      await _pump(
          tester,
          MyLoyaltyScreen(
              api: _cardsApi(
                  [_card('p1', 'Cafe', stamps: 4, goal: 4, remaining: 4)]),
              locate: () async => null),
          _auth());

      expect(_stamps('full'), findsNWidgets(4));
      expect(_stamps('empty'), findsNothing);
    });

    testWidgets('"a X m" solo si hay posicion y el local esta cerca',
        (tester) async {
      await _pump(
          tester,
          MyLoyaltyScreen(
              api: _cardsApi([
                _card('p1', 'Cerca', stamps: 1, goal: 8, remaining: 7),
                _card('p2', 'Lejos',
                    stamps: 1, goal: 8, remaining: 7, lat: -11.5, lng: -77.0),
              ]),
              // ~350 m al norte de "Cerca".
              locate: () async => _at(-12.046 + 0.00315, -77.042)),
          _auth());

      // Solo "Cerca" (~350 m); "Lejos" está a más de 5 km y no lleva la etiqueta.
      expect(find.textContaining('📍'), findsOneWidget);
      expect(
          find.byWidgetPredicate((w) =>
              w is Text && RegExp(r'^📍 a \d+ m$').hasMatch(w.data ?? '')),
          findsOneWidget);
    });

    testWidgets('sin posicion no sale distancia', (tester) async {
      await _pump(
          tester,
          MyLoyaltyScreen(
              api: _cardsApi([_card('p1', 'Cerca', stamps: 1, goal: 8, remaining: 7)]),
              locate: () async => null),
          _auth());

      expect(find.text('Cerca'), findsOneWidget);
      expect(find.textContaining('📍'), findsNothing);
    });

    testWidgets('el GPS no bloquea: las tarjetas salen aunque nunca responda',
        (tester) async {
      await _pump(
          tester,
          MyLoyaltyScreen(
              api: _cardsApi([_card('p1', 'Cerca', stamps: 1, goal: 8, remaining: 7)]),
              locate: () => Completer<Position?>().future),
          _auth());

      expect(find.text('Cerca'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('invitado: pide iniciar sesion como antes', (tester) async {
      await _pump(tester, MyLoyaltyScreen(api: _cardsApi([])),
          _auth(loggedIn: false));

      expect(find.text('Mis premios'), findsOneWidget);
      expect(find.textContaining('Inicia sesión para ver todas tus tarjetas'),
          findsOneWidget);
      expect(find.text('Iniciar sesión'), findsOneWidget);
    });

    testWidgets('sin tarjetas: mensaje de siempre', (tester) async {
      await _pump(tester, MyLoyaltyScreen(api: _cardsApi([])), _auth());

      expect(find.textContaining('Aún no tienes tarjetas de fidelización'),
          findsOneWidget);
    });
  });

  // ----------------------------------------------------------------- Perfil

  group('Perfil', () {
    final seen = <http.Request>[];

    Map<String, dynamic> post() => {
          'id': 'post-1',
          'kind': 'text',
          'text': 'Feria en el parque',
          'mediaUrl': null,
          'latitude': -12.1211,
          'longitude': -77.0296,
          'visibility': 'friends',
          'likes': 3,
          'dislikes': 0,
          'checks': 1,
          'expiresAt':
              DateTime.now().add(const Duration(hours: 5)).toUtc().toIso8601String(),
          'createdAt': DateTime.now().toUtc().toIso8601String(),
          'author': {'id': 'me-1', 'fullName': 'Ana Prueba', 'avatarUrl': null},
          'myReaction': null,
        };

    ApiClient profileApi() => ApiClient(
            client: MockClient((req) async {
          seen.add(req);
          final path = req.url.path;
          if (path.endsWith('/users/me/profile')) {
            return _ok({
              'id': 'me-1',
              'email': 'a@b.pe',
              'fullName': 'Ana Prueba',
              'bio': 'Comelona de Barranco',
              'followersCount': 12,
              'followingCount': 7,
            });
          }
          if (path.endsWith('/gamification/my-stats')) {
            return _ok({
              'level': 3,
              'xp': 320,
              'nextLevelXp': 500,
              'checkinsCount': 38,
              'weeklyStreak': 4,
            });
          }
          if (path.endsWith('/gamification/badges')) {
            return _ok([
              {
                'id': 'b1',
                'name': 'Ceviche',
                'icon': '🐟',
                'unlockedAt': '2026-11-01T00:00:00Z'
              },
              {'id': 'b2', 'name': 'Sin ganar', 'icon': '🏅'},
            ]);
          }
          if (path.endsWith('/users/me/checkins')) {
            return _ok({'data': [], 'total': 0, 'page': 1, 'totalPages': 1});
          }
          if (path.endsWith('/now/mine')) {
            return _ok({'data': [post()], 'total': 1});
          }
          if (path.contains('/now/posts/')) return _ok(post());
          return _ok({});
        }));

    setUp(seen.clear);

    Future<void> openRow(WidgetTester tester, String label) async {
      final row = find.text(label);
      await tester.scrollUntilVisible(row, 300,
          scrollable: find.byType(Scrollable).first);
      await tester.pump(); // la lista asienta el desplazamiento al cuadro siguiente
      await tester.tap(row);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('muestra avatar, nombre, bio, nivel, racha, check-ins y barra',
        (tester) async {
      _ignoreOverflow();
      await _pump(tester, ProfileScreen(api: profileApi()), _auth());

      expect(find.text('Ana Prueba'), findsOneWidget);
      expect(find.text('Comelona de Barranco'), findsOneWidget);
      expect(find.text('Nivel'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('🔥 4'), findsOneWidget);
      expect(find.text('Semanas'), findsOneWidget);
      expect(find.text('38'), findsOneWidget);
      expect(find.text('Check-ins'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('320 / 500 XP para Nivel Plata'), findsOneWidget);
      expect(find.text('Insignias'), findsOneWidget);
      expect(find.text('Ceviche'), findsOneWidget);
    });

    testWidgets('tiene las cinco filas', (tester) async {
      _ignoreOverflow();
      await _pump(tester, ProfileScreen(api: profileApi()), _auth());

      for (final label in [
        'Mi mapa',
        'Guardados',
        'Mis amigos',
        'Mis publicaciones',
        'Mensajes'
      ]) {
        expect(find.text(label, skipOffstage: false), findsOneWidget,
            reason: label);
      }
    });

    testWidgets('lo que ya existia sigue a mano', (tester) async {
      _ignoreOverflow();
      await _pump(tester, ProfileScreen(api: profileApi()), _auth());

      expect(find.byTooltip('Ajustes'), findsOneWidget);
      expect(find.byTooltip('Editar perfil'), findsOneWidget);
      expect(find.byTooltip('Invitar amigos'), findsOneWidget);
      // Seguidores / Seguidos son un Text.rich ("12 " + "Seguidores").
      for (final t in ['Seguidores', 'Seguidos']) {
        expect(find.textContaining(t, findRichText: true), findsOneWidget,
            reason: t);
      }
      // Abajo del todo: la lista arma sus filas al desplazarse.
      for (final t in [
        'Check-ins Recientes',
        'Ver historial completo',
        'Cerrar sesión'
      ]) {
        await tester.scrollUntilVisible(find.text(t), 300,
            scrollable: find.byType(Scrollable).first);
        expect(find.text(t), findsOneWidget, reason: t);
      }
    });

    testWidgets('Seguidores abre la lista de seguidores', (tester) async {
      _ignoreOverflow();
      await _pump(tester, ProfileScreen(api: profileApi()), _auth());

      await tester.tap(find.textContaining('Seguidores', findRichText: true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(SocialScreen), findsOneWidget);
    });

    testWidgets('Guardados abre FavoritesScreen', (tester) async {
      _ignoreOverflow();
      await _pump(tester, ProfileScreen(api: profileApi()), _auth());

      await openRow(tester, 'Guardados');
      expect(find.byType(FavoritesScreen), findsOneWidget);
    });

    testWidgets('Mensajes abre MessagesScreen', (tester) async {
      _ignoreOverflow();
      await _pump(tester, ProfileScreen(api: profileApi()), _auth());

      await openRow(tester, 'Mensajes');
      expect(find.byType(MessagesScreen), findsOneWidget);
    });

    testWidgets('Mi mapa abre el mapa y, sin check-ins, avisa', (tester) async {
      _ignoreOverflow();
      await _pump(tester, ProfileScreen(api: profileApi()), _auth());

      expect(find.text('0 lugares visitados', skipOffstage: false),
          findsOneWidget);
      await openRow(tester, 'Mi mapa');
      expect(find.text('Haz tu primer check-in para ver tu mapa'),
          findsOneWidget);
    });

    testWidgets('Mis amigos abre FriendsScreen', (tester) async {
      _ignoreOverflow();
      await _pump(tester, ProfileScreen(api: profileApi()), _auth());

      await openRow(tester, 'Mis amigos');
      expect(find.byType(FriendsScreen), findsOneWidget);
    });

    testWidgets('Mis publicaciones lista /now/mine y abre la publicacion',
        (tester) async {
      _ignoreOverflow();
      await _pump(tester, ProfileScreen(api: profileApi()), _auth());

      await openRow(tester, 'Mis publicaciones');
      expect(find.byType(MyPostsScreen), findsOneWidget);
      expect(find.text('Feria en el parque'), findsOneWidget);
      expect(find.textContaining('Amigos · ⚡ quedan'), findsOneWidget);
      expect(seen.where((r) => r.url.path.endsWith('/now/mine')), isNotEmpty);

      await tester.tap(find.text('Feria en el parque'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(NowPostScreen), findsOneWidget);
      expect(
          seen.where((r) => r.url.path.endsWith('/now/posts/post-1')), isNotEmpty);
    });

    testWidgets('Mis publicaciones sin nada: mensaje', (tester) async {
      final api = ApiClient(
          client: MockClient((req) async => req.url.path.endsWith('/now/mine')
              ? _ok({'data': [], 'total': 0})
              : _ok({})));
      await _pump(tester, MyPostsScreen(api: api), _auth());

      expect(find.textContaining('Todavía no publicaste nada en Ahora'),
          findsOneWidget);
    });

    testWidgets('Mis publicaciones vacia: jalar vuelve a pedir /now/mine',
        (tester) async {
      final asked = <http.Request>[];
      final api = ApiClient(client: MockClient((req) async {
        if (req.url.path.endsWith('/now/mine')) {
          asked.add(req);
          return _ok({'data': [], 'total': 0});
        }
        return _ok({});
      }));
      await _pump(tester, MyPostsScreen(api: api), _auth());
      expect(asked, hasLength(1));
      expect(find.textContaining('Todavía no publicaste nada en Ahora'),
          findsOneWidget);

      await tester.drag(find.byType(ListView), const Offset(0, 400));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      expect(asked, hasLength(2));
      expect(find.textContaining('Todavía no publicaste nada en Ahora'),
          findsOneWidget);
    });

    testWidgets('invitado: pide iniciar sesion como antes', (tester) async {
      await _pump(tester, ProfileScreen(api: profileApi()),
          _auth(loggedIn: false));

      expect(find.textContaining('Inicia sesión para ver tu perfil'),
          findsOneWidget);
      expect(find.text('Ingresar'), findsOneWidget);
      expect(find.text('Mis amigos'), findsNothing);
    });
  });

  // ---------------------------------------------------------------- Amigos

  group('FriendsScreen', () {
    final seen = <http.Request>[];

    /// Seguidores Ana y Beto; Ana ya está en Amigos. [onWrite] decide qué
    /// responde el backend a POST/DELETE /now/friends/:id.
    ApiClient friendsApi({
      List<Map<String, dynamic>>? followers,
      Future<http.Response> Function(http.Request req)? onWrite,
    }) {
      final list = followers ??
          [
            {'id': 'a1', 'fullName': 'Ana', 'avatarUrl': null},
            {'id': 'b1', 'fullName': 'Beto', 'avatarUrl': null},
          ];
      return ApiClient(client: MockClient((req) async {
        seen.add(req);
        final path = req.url.path;
        if (path.endsWith('/users/me/followers')) {
          return _ok({'data': list, 'total': list.length});
        }
        if (path.endsWith('/now/friends') && req.method == 'GET') {
          return _ok([
            {'id': 'a1', 'fullName': 'Ana', 'avatarUrl': null}
          ]);
        }
        if (path.contains('/now/friends/')) {
          if (onWrite != null) return await onWrite(req);
          return _ok({'ok': true});
        }
        return _ok({});
      }));
    }

    setUp(seen.clear);

    Finder tile(String name) => find.widgetWithText(SwitchListTile, name);
    bool on(WidgetTester tester, String name) =>
        tester.widget<SwitchListTile>(tile(name)).value;
    Future<void> flip(WidgetTester tester, String name) async {
      await tester.tap(find.descendant(
          of: tile(name), matching: find.byType(Switch)));
      await tester.pump();
    }

    testWidgets('explica la regla, lista seguidores y refleja getFriends',
        (tester) async {
      await _pump(tester, FriendsScreen(api: friendsApi()), _auth());

      expect(find.text('Tus Amigos ven lo que publicas solo para Amigos.'),
          findsOneWidget);
      expect(find.text('En mis Amigos'), findsNWidgets(2));
      expect(on(tester, 'Ana'), isTrue);
      expect(on(tester, 'Beto'), isFalse);
    });

    testWidgets('el interruptor llama addFriend y luego removeFriend',
        (tester) async {
      await _pump(tester, FriendsScreen(api: friendsApi()), _auth());

      await flip(tester, 'Beto');
      await tester.pump(const Duration(milliseconds: 100));
      var writes = seen.where((r) => r.url.path.contains('/now/friends/'));
      expect(writes.single.method, 'POST');
      expect(writes.single.url.path, '/api/now/friends/b1');
      expect(on(tester, 'Beto'), isTrue);

      await flip(tester, 'Beto');
      await tester.pump(const Duration(milliseconds: 100));
      writes = seen.where((r) => r.url.path.contains('/now/friends/'));
      expect(writes.map((r) => r.method), ['POST', 'DELETE']);
      expect(writes.last.url.path, '/api/now/friends/b1');
      expect(on(tester, 'Beto'), isFalse);
    });

    testWidgets('cambia al instante y vuelve atras con un aviso si falla agregar',
        (tester) async {
      final gate = Completer<http.Response>();
      await _pump(
          tester, FriendsScreen(api: friendsApi(onWrite: (_) => gate.future)),
          _auth());

      await flip(tester, 'Beto');
      expect(on(tester, 'Beto'), isTrue, reason: 'optimista');

      gate.complete(_fail(400));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(on(tester, 'Beto'), isFalse, reason: 'vuelve atras');
      expect(find.text('No se pudo agregar a Amigos. Intenta de nuevo.'),
          findsOneWidget);
    });

    testWidgets('si falla quitar, Ana vuelve a quedar en Amigos',
        (tester) async {
      await _pump(
          tester,
          FriendsScreen(api: friendsApi(onWrite: (_) async => _fail(500))),
          _auth());

      await flip(tester, 'Ana');
      await tester.pump(const Duration(milliseconds: 100));

      expect(on(tester, 'Ana'), isTrue);
      expect(find.text('No se pudo quitar de Amigos. Intenta de nuevo.'),
          findsOneWidget);
    });

    testWidgets('sin seguidores: explica y avisa que no hay nadie',
        (tester) async {
      await _pump(
          tester, FriendsScreen(api: friendsApi(followers: [])), _auth());

      expect(find.text('Tus Amigos ven lo que publicas solo para Amigos.'),
          findsOneWidget);
      expect(find.textContaining('Todavía no tienes seguidores'),
          findsOneWidget);
      expect(find.byType(SwitchListTile), findsNothing);
    });

    testWidgets('si no carga: error con Reintentar', (tester) async {
      final api = ApiClient(client: MockClient((req) async => _fail(500)));
      await _pump(tester, FriendsScreen(api: api), _auth());

      expect(find.text('boom'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
    });
  });
}
