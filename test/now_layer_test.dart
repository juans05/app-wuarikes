import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wuarikes_app/core/api_client.dart';
import 'package:wuarikes_app/core/models.dart';
import 'package:wuarikes_app/core/now_location.dart';
import 'package:wuarikes_app/core/now_models.dart';
import 'package:wuarikes_app/screens/explore_screen.dart';
import 'package:wuarikes_app/screens/login_screen.dart';
import 'package:wuarikes_app/screens/main_shell.dart';
import 'package:wuarikes_app/screens/now/now_layer.dart';
import 'package:wuarikes_app/screens/now/now_post_screen.dart';
import 'package:wuarikes_app/screens/now/publish_now_sheet.dart';
import 'package:wuarikes_app/screens/place_detail_screen.dart';
import 'package:wuarikes_app/state/auth_provider.dart';

// Centro por defecto de Explorar (Miraflores) y un punto de publicación.
const _centerLat = -12.1211;
const _centerLng = -77.0296;

Map<String, dynamic> _postJson(
  String id, {
  String kind = 'text',
  String? text = 'Feria en el parque',
  double lat = _centerLat,
  double lng = _centerLng,
  int likes = 3,
  int dislikes = 1,
  int checks = 2,
  String? myReaction,
  String authorId = 'author-1',
  String authorName = 'Maritza',
}) =>
    {
      'id': id,
      'kind': kind,
      'text': text,
      'mediaUrl': null,
      'latitude': lat,
      'longitude': lng,
      'visibility': 'all',
      'likes': likes,
      'dislikes': dislikes,
      'checks': checks,
      'expiresAt': DateTime.now()
          .add(const Duration(hours: 19, minutes: 30))
          .toUtc()
          .toIso8601String(),
      'createdAt': DateTime.now()
          .subtract(const Duration(hours: 2))
          .toUtc()
          .toIso8601String(),
      'author': {'id': authorId, 'fullName': authorName, 'avatarUrl': null},
      'myReaction': myReaction,
    };

Map<String, dynamic> _promoJson(String id, String placeId,
        {double lat = _centerLat, double lng = _centerLng}) =>
    {
      'id': id,
      'title': '2x1 en ceviches',
      'description': null,
      'imageUrl': null,
      'visibleUntil': DateTime.now()
          .add(const Duration(hours: 5))
          .toUtc()
          .toIso8601String(),
      'place': {
        'id': placeId,
        'name': 'El Chinito',
        'latitude': lat,
        'longitude': lng,
      },
    };

const _json = {'content-type': 'application/json; charset=utf-8'};

http.Response _ok(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: _json);

http.Response _err(int status, String message) =>
    http.Response(jsonEncode({'message': message}), status, headers: _json);

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

AuthProvider _auth({String? userId = 'me-1', String name = 'Ana Prueba'}) {
  final auth = AuthProvider(ApiClient());
  if (userId != null) {
    auth.user = AppUser(id: userId, email: 'a@b.pe', fullName: name);
  }
  return auth;
}

/// Servidor de mentira de "Ahora" para una publicación: lleva los contadores
/// como el backend (una reacción por usuario) y anota cada petición.
class _FakeNow {
  final seen = <http.Request>[];
  late Map<String, dynamic> post;
  http.Response Function(http.Request)? onReport;
  http.Response Function(http.Request)? onGetPost;

  _FakeNow({Map<String, dynamic>? post}) {
    this.post = post ?? _postJson('post-1');
  }

  List<http.Request> where(String method, String suffix) => seen
      .where((r) => r.method == method && r.url.path.endsWith(suffix))
      .toList();

  void _setReaction(String? type) {
    final old = post['myReaction'] as String?;
    void bump(String? t, int d) {
      if (t == 'like') post['likes'] = (post['likes'] as int) + d;
      if (t == 'dislike') post['dislikes'] = (post['dislikes'] as int) + d;
      if (t == 'check') post['checks'] = (post['checks'] as int) + d;
    }

    bump(old, -1);
    bump(type, 1);
    post['myReaction'] = type;
  }

  late final api = ApiClient(client: MockClient((req) async {
    seen.add(req);
    final path = req.url.path;
    if (req.method == 'GET' && path.endsWith('/now/posts/post-1')) {
      return onGetPost?.call(req) ?? _ok(post);
    }
    if (req.method == 'PUT' && path.endsWith('/reaction')) {
      _setReaction((jsonDecode(req.body) as Map)['type'] as String);
      return _ok(post);
    }
    if (req.method == 'DELETE' && path.endsWith('/reaction')) {
      _setReaction(null);
      return _ok(post);
    }
    if (req.method == 'POST' && path.endsWith('/report')) {
      return onReport?.call(req) ?? _ok({'ok': true}, 201);
    }
    return http.Response('[]', 200);
  }));
}

Future<void> _phone(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// GPS de mentira que da una posición distinta en cada llamada (la última se
/// repite) y cuenta cuántas veces se le pidió.
class _Gps {
  final List<Position?> positions;
  int calls = 0;
  _Gps(this.positions);
  Future<Position?> call() async {
    final i = calls++;
    return positions[i < positions.length ? i : positions.length - 1];
  }
}

Future<void> _pumpPost(WidgetTester tester, _FakeNow fake,
    {AuthProvider? auth, Position? position, NowLocator? locate}) async {
  await _phone(tester);
  await tester.pumpWidget(ChangeNotifierProvider<AuthProvider>.value(
    value: auth ?? _auth(),
    child: MaterialApp(
      home: NowPostScreen(
          postId: 'post-1',
          api: fake.api,
          locate: locate ?? () async => position),
    ),
  ));
  await _settle(tester);
}

double _opacityOf(WidgetTester tester, String reactKey) => tester
    .widget<Opacity>(find.descendant(
        of: find.byKey(ValueKey(reactKey)), matching: find.byType(Opacity)))
    .opacity;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    nowPostPublished.value = null;
  });

  group('NowPostScreen', () {
    // La publicación está en el centro; ~110 m al norte está "cerca", ~1,1 km no.
    final near = _at(_centerLat + 0.001, _centerLng);
    final far = _at(_centerLat + 0.01, _centerLng);

    testWidgets('muestra autor, vida que queda, texto y conteos',
        (tester) async {
      final fake = _FakeNow();
      await _pumpPost(tester, fake, position: near);

      expect(find.text('@Maritza'), findsOneWidget);
      expect(find.text('Feria en el parque'), findsOneWidget);
      expect(find.text('quedan 19 h'), findsOneWidget);
      expect(find.text('👍 3'), findsOneWidget);
      expect(find.text('👎 1'), findsOneWidget);
      expect(find.text('✅ 2'), findsOneWidget);
      expect(find.text('⚑ Reportar'), findsOneWidget);
    });

    testWidgets('lejos: ✅ apagado con "Acércate para confirmar" y no reacciona',
        (tester) async {
      final fake = _FakeNow();
      await _pumpPost(tester, fake, position: far);

      expect(find.text('Acércate para confirmar'), findsOneWidget);
      expect(_opacityOf(tester, 'react-check'), lessThan(1));
      expect(_opacityOf(tester, 'react-like'), 1);

      await tester.tap(find.text('✅ 2'));
      await _settle(tester);
      expect(fake.where('PUT', '/reaction'), isEmpty);
    });

    testWidgets('sin ubicación: ✅ apagado con "Acércate para confirmar"',
        (tester) async {
      final fake = _FakeNow();
      await _pumpPost(tester, fake, position: null);

      expect(find.text('Acércate para confirmar'), findsOneWidget);
      expect(_opacityOf(tester, 'react-check'), lessThan(1));
    });

    testWidgets('a 300 m o menos: ✅ prendido; manda lat/lng y sube el conteo',
        (tester) async {
      final fake = _FakeNow();
      await _pumpPost(tester, fake, position: near);

      expect(find.text('Acércate para confirmar'), findsNothing);
      expect(_opacityOf(tester, 'react-check'), 1);

      await tester.tap(find.text('✅ 2'));
      await _settle(tester);

      final put = fake.where('PUT', '/reaction').single;
      expect(jsonDecode(put.body), {
        'type': 'check',
        'latitude': near.latitude,
        'longitude': near.longitude,
      });
      expect(find.text('✅ 3'), findsOneWidget);
    });

    testWidgets(
        '✅ lejos al abrir pero cerca al tocar: vuelve a ubicar y confirma con la posición nueva',
        (tester) async {
      final fake = _FakeNow();
      final gps = _Gps([far, near]);
      await _pumpPost(tester, fake, locate: gps.call);
      expect(find.text('Acércate para confirmar'), findsOneWidget);
      expect(gps.calls, 1);

      // Aunque se vea apagado, tocarlo vuelve a ubicar.
      await tester.tap(find.text('✅ 2'));
      await _settle(tester);

      expect(gps.calls, 2);
      final put = fake.where('PUT', '/reaction').single;
      expect(jsonDecode(put.body), {
        'type': 'check',
        'latitude': near.latitude,
        'longitude': near.longitude,
      });
      expect(find.text('✅ 3'), findsOneWidget);
      expect(find.text('Acércate para confirmar'), findsNothing);
    });

    testWidgets('✅ cerca al abrir pero lejos al tocar: no se manda',
        (tester) async {
      final fake = _FakeNow();
      final gps = _Gps([near, far]);
      await _pumpPost(tester, fake, locate: gps.call);
      expect(find.text('Acércate para confirmar'), findsNothing);

      await tester.tap(find.text('✅ 2'));
      await _settle(tester);

      expect(gps.calls, 2);
      expect(fake.where('PUT', '/reaction'), isEmpty);
      // Aviso (snackbar) y el botón ya se ve apagado con la posición nueva.
      expect(find.text('Acércate para confirmar'), findsNWidgets(2));
      expect(_opacityOf(tester, 'react-check'), lessThan(1));
    });

    testWidgets(
        'con tu ✅ dado y lejos: "Toca para quitar" y se quita sin ubicar',
        (tester) async {
      final fake = _FakeNow(post: _postJson('post-1', myReaction: 'check'));
      final gps = _Gps([far]);
      await _pumpPost(tester, fake, locate: gps.call);

      expect(find.text('Toca para quitar'), findsOneWidget);
      expect(find.text('Acércate para confirmar'), findsNothing);
      expect(_opacityOf(tester, 'react-check'), 1);

      await tester.tap(find.text('✅ 2'));
      await _settle(tester);

      expect(gps.calls, 1); // solo la de al abrir
      expect(fake.where('DELETE', '/reaction'), hasLength(1));
      expect(find.text('✅ 1'), findsOneWidget);
    });

    testWidgets('👍 llama a reactNow y sube el conteo; otra vez lo quita',
        (tester) async {
      final fake = _FakeNow();
      await _pumpPost(tester, fake, position: far);

      await tester.tap(find.text('👍 3'));
      await _settle(tester);
      final put = fake.where('PUT', '/reaction').single;
      expect(jsonDecode(put.body), {'type': 'like'});
      expect(find.text('👍 4'), findsOneWidget);

      // Tocar la reacción actual la quita (DELETE) y baja el conteo.
      await tester.tap(find.text('👍 4'));
      await _settle(tester);
      expect(fake.where('DELETE', '/reaction'), hasLength(1));
      expect(find.text('👍 3'), findsOneWidget);
    });

    testWidgets('cambiar de 👍 a 👎 deja una sola reacción', (tester) async {
      final fake = _FakeNow(post: _postJson('post-1', myReaction: 'like'));
      await _pumpPost(tester, fake, position: far);

      await tester.tap(find.text('👎 1'));
      await _settle(tester);

      expect(find.text('👍 2'), findsOneWidget);
      expect(find.text('👎 2'), findsOneWidget);
    });

    testWidgets('el autor ve los conteos pero 👍 👎 ✅ están apagados',
        (tester) async {
      final fake = _FakeNow(post: _postJson('post-1', authorId: 'me-1'));
      await _pumpPost(tester, fake, position: near);

      expect(find.text('👍 3'), findsOneWidget);
      expect(find.text('✅ 2'), findsOneWidget);
      for (final key in ['react-like', 'react-dislike', 'react-check']) {
        expect(_opacityOf(tester, key), lessThan(1), reason: key);
      }
      await tester.tap(find.text('👍 3'));
      await tester.tap(find.text('✅ 2'));
      await _settle(tester);
      expect(fake.where('PUT', '/reaction'), isEmpty);
      // No se reporta la propia publicación (el backend respondería 400).
      expect(find.text('⚑ Reportar'), findsNothing);
    });

    testWidgets(
        'un invitado que reacciona va a iniciar sesión, sin llamar a la API',
        (tester) async {
      final fake = _FakeNow();
      await _pumpPost(tester, fake, auth: _auth(userId: null), position: near);

      await tester.tap(find.text('👍 3'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(fake.where('PUT', '/reaction'), isEmpty);
    });

    testWidgets('Reportar pide el motivo y avisa "Gracias, lo revisaremos"',
        (tester) async {
      final fake = _FakeNow();
      await _pumpPost(tester, fake, position: far);

      await tester.tap(find.text('⚑ Reportar'));
      await tester.pumpAndSettle();

      // Sin motivo no se puede enviar.
      FilledButton send() =>
          tester.widget<FilledButton>(find.byType(FilledButton));
      expect(send().onPressed, isNull);

      await tester.enterText(find.byKey(const Key('report-reason')), 'Es spam');
      await tester.pump();
      expect(send().onPressed, isNotNull);
      await tester.tap(find.text('Enviar reporte'));
      await tester.pumpAndSettle();

      final post = fake.where('POST', '/report').single;
      expect(jsonDecode(post.body), {'reason': 'Es spam'});
      expect(find.text('Gracias, lo revisaremos'), findsOneWidget);
    });

    testWidgets('Reportar: el límite diario (429) tiene su aviso',
        (tester) async {
      final fake = _FakeNow()
        ..onReport = (_) => _err(429, 'Máximo 20 reportes por día');
      await _pumpPost(tester, fake, position: far);

      await tester.tap(find.text('⚑ Reportar'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('report-reason')), 'Es spam');
      await tester.pump();
      await tester.tap(find.text('Enviar reporte'));
      await tester.pumpAndSettle();

      expect(
          find.text('Llegaste al límite de reportes de hoy'), findsOneWidget);
    });

    testWidgets('una publicación vencida u oculta (404) dice que ya no está',
        (tester) async {
      final fake = _FakeNow()
        ..onGetPost = (_) => _err(404, 'Publicación no encontrada');
      await _pumpPost(tester, fake, position: near);

      expect(
          find.text('Esta publicación ya no está disponible'), findsOneWidget);
      expect(find.text('👍 3'), findsNothing);
    });
  });

  group('Hoja de publicar', () {
    /// Un botón que abre la hoja con API, GPS y selector de mentira.
    Future<void> pumpSheet(
      WidgetTester tester, {
      required ApiClient api,
      AuthProvider? auth,
      Position? position,
      NowLocator? locate,
      NowMediaPicker? pick,
    }) async {
      await _phone(tester);
      await tester.pumpWidget(ChangeNotifierProvider<AuthProvider>.value(
        value: auth ?? _auth(),
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showPublishNowSheet(context,
                    api: api,
                    locate: locate ?? () async => position,
                    pick: pick ?? (_, {required video}) async => null),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
    }

    final here = _at(_centerLat, _centerLng);

    testWidgets(
        'trae las opciones, el aviso de 300 m y "Publicar como @nombre"',
        (tester) async {
      final seen = <http.Request>[];
      await pumpSheet(tester, api: ApiClient(client: MockClient((r) async {
        seen.add(r);
        return _ok({});
      })), position: here);

      expect(find.text('¿Qué está pasando?'), findsOneWidget);
      for (final label in [
        '📷 Foto',
        '🎥 Video',
        '✏️ Texto',
        '🌎 Todos',
        '👤 Seguidores',
        '👥 Amigos',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text('📍 Se publica donde estás (300 m) · dura 24 h'),
          findsOneWidget);
      expect(find.text('Publicar como @Ana Prueba'), findsOneWidget);
      expect(seen, isEmpty);
    });

    testWidgets('invitado: va a iniciar sesión y no se llama a la API',
        (tester) async {
      final seen = <http.Request>[];
      var located = 0;
      await _phone(tester);
      await tester.pumpWidget(ChangeNotifierProvider<AuthProvider>.value(
        value: _auth(userId: null),
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showPublishNowSheet(context,
                    api: ApiClient(client: MockClient((r) async {
                  seen.add(r);
                  return _ok({});
                })), locate: () async {
                  located++;
                  return here;
                }),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('¿Qué está pasando?'), findsNothing);
      expect(seen, isEmpty);
      expect(located, 0);
    });

    testWidgets(
        '"Publicar lo que pasa aquí" del ＋ manda al invitado a iniciar sesión',
        (tester) async {
      await _phone(tester);
      await tester.pumpWidget(ChangeNotifierProvider<AuthProvider>.value(
        value: _auth(userId: null),
        child: const MaterialApp(home: MainShell()),
      ));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Publicar lo que pasa aquí'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('¿Qué está pasando?'), findsNothing);
    });

    testWidgets('429: "Llegaste al límite de 5 publicaciones por hora"',
        (tester) async {
      final seen = <http.Request>[];
      await pumpSheet(tester, api: ApiClient(client: MockClient((r) async {
        seen.add(r);
        return _err(429, 'Máximo 5 publicaciones por hora');
      })), position: here);

      await tester.tap(find.text('✏️ Texto'));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('now-text')), 'Hay cola');
      await tester.tap(find.byKey(const Key('publish-button')));
      await tester.pumpAndSettle();

      expect(seen, hasLength(1));
      expect(find.text('Llegaste al límite de 5 publicaciones por hora'),
          findsOneWidget);
      // La hoja sigue abierta para poder reintentar.
      expect(find.text('¿Qué está pasando?'), findsOneWidget);
    });

    testWidgets('publicar texto: manda kind, visibilidad y GPS, cierra y avisa',
        (tester) async {
      final seen = <http.Request>[];
      await pumpSheet(tester, api: ApiClient(client: MockClient((r) async {
        seen.add(r);
        return _ok(_postJson('nuevo', lat: here.latitude), 201);
      })), position: here);

      await tester.tap(find.text('✏️ Texto'));
      await tester.pump();
      await tester.tap(find.text('👥 Amigos'));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('now-text')), ' Hay cola ');
      await tester.tap(find.byKey(const Key('publish-button')));
      await tester.pumpAndSettle();

      expect(seen.single.method, 'POST');
      expect(seen.single.url.path, '/api/now/posts');
      expect(jsonDecode(seen.single.body), {
        'kind': 'text',
        'text': 'Hay cola',
        'visibility': 'friends',
        'latitude': here.latitude,
        'longitude': here.longitude,
      });
      expect(find.text('¿Qué está pasando?'), findsNothing);
      expect(find.text('Publicado. Dura 24 h.'), findsOneWidget);
      expect(nowPostPublished.value?.id, 'nuevo');
    });

    testWidgets('sin ubicación no publica y lo dice', (tester) async {
      final seen = <http.Request>[];
      await pumpSheet(tester, api: ApiClient(client: MockClient((r) async {
        seen.add(r);
        return _ok({});
      })), position: null);

      expect(find.textContaining('No pudimos ubicarte'), findsOneWidget);
      await tester.tap(find.text('✏️ Texto'));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('now-text')), 'Hola');
      await tester.tap(find.byKey(const Key('publish-button')));
      await tester.pump();

      expect(find.text('Activa tu ubicación para publicar'), findsOneWidget);
      expect(seen, isEmpty);
    });

    testWidgets(
        'publica con el GPS de ese momento, no con el de al abrir la hoja',
        (tester) async {
      final seen = <http.Request>[];
      final a = _at(_centerLat, _centerLng);
      final b = _at(_centerLat + 0.01, _centerLng + 0.01);
      final gps = _Gps([a, b]);
      await pumpSheet(tester, api: ApiClient(client: MockClient((r) async {
        seen.add(r);
        return _ok(_postJson('nuevo'), 201);
      })), locate: gps.call);
      expect(gps.calls, 1);

      await tester.tap(find.text('✏️ Texto'));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('now-text')), 'Hay cola');
      await tester.tap(find.byKey(const Key('publish-button')));
      await tester.pumpAndSettle();

      expect(gps.calls, 2);
      final body = jsonDecode(seen.single.body) as Map;
      expect(body['latitude'], b.latitude);
      expect(body['longitude'], b.longitude);
    });

    testWidgets('si al publicar ya no hay GPS, no se manda y se avisa',
        (tester) async {
      final seen = <http.Request>[];
      final gps = _Gps([here, null]);
      await pumpSheet(tester, api: ApiClient(client: MockClient((r) async {
        seen.add(r);
        return _ok(_postJson('nuevo'), 201);
      })), locate: gps.call);

      await tester.tap(find.text('✏️ Texto'));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('now-text')), 'Hay cola');
      await tester.tap(find.byKey(const Key('publish-button')));
      await tester.pumpAndSettle();

      expect(find.text('Activa tu ubicación para publicar'), findsOneWidget);
      expect(seen, isEmpty);
      expect(find.text('¿Qué está pasando?'), findsOneWidget);
    });

    testWidgets('cambiar de Foto a Video suelta el archivo elegido',
        (tester) async {
      await pumpSheet(tester,
          api: ApiClient(client: MockClient((r) async => _ok({}))),
          position: here,
          pick: (source, {required video}) async => XFile.fromData(
              Uint8List.fromList(List.filled(8, 1)),
              name: 'foto.png',
              path: 'foto.png'));

      await tester.tap(find.byKey(const Key('media-tile')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Elegir de la galería'));
      await tester.pumpAndSettle();
      expect(find.textContaining('foto.png'), findsOneWidget);

      await tester.tap(find.text('🎥 Video'));
      await tester.pump();
      await tester.tap(find.text('📷 Foto'));
      await tester.pump();

      expect(find.textContaining('foto.png'), findsNothing);
      await tester.tap(find.byKey(const Key('publish-button')));
      await tester.pump();
      expect(find.text('Elige una foto o cambia a Texto'), findsOneWidget);
    });

    testWidgets('texto vacío o foto sin elegir: avisa y no llama a la API',
        (tester) async {
      final seen = <http.Request>[];
      await pumpSheet(tester, api: ApiClient(client: MockClient((r) async {
        seen.add(r);
        return _ok({});
      })), position: here);

      await tester.tap(find.byKey(const Key('publish-button')));
      await tester.pump();
      expect(find.text('Elige una foto o cambia a Texto'), findsOneWidget);

      await tester.tap(find.text('✏️ Texto'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('publish-button')));
      await tester.pump();
      expect(find.text('Escribe algo para publicar'), findsOneWidget);
      expect(seen, isEmpty);
    });

    // El multipart de createNowPost sale por `request.send()`, que usa el
    // cliente de la zona (http.runWithClient), no el del ApiClient.
    Future<void> publishFile(
      WidgetTester tester, {
      required String kindLabel,
      required XFile file,
      required void Function(http.BaseRequest, String) check,
    }) async {
      http.BaseRequest? request;
      var body = '';
      await http.runWithClient(() async {
        SharedPreferences.setMockInitialValues(
            {'wuarikes_access_token': 'tok-123'});
        await pumpSheet(tester,
            api: ApiClient(),
            position: here,
            pick: (source, {required video}) async => file);

        await tester.tap(find.text(kindLabel));
        await tester.pump();
        await tester.tap(find.byKey(const Key('media-tile')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Elegir de la galería'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('publish-button')));
        await tester.pumpAndSettle();
      },
          () => MockClient.streaming((req, bodyStream) async {
                request = req;
                body = await bodyStream.bytesToString();
                return http.StreamedResponse(
                    Stream.value(utf8.encode(jsonEncode(_postJson('foto-1')))),
                    201,
                    headers: _json);
              }));
      expect(request, isNotNull, reason: 'no salió la petición');
      check(request!, body);
    }

    testWidgets('foto png: sube multipart con su nombre y image/png',
        (tester) async {
      await publishFile(
        tester,
        kindLabel: '📷 Foto',
        file: XFile.fromData(Uint8List.fromList(List.filled(8, 1)),
            name: 'foto.png', path: 'foto.png'),
        check: (req, body) {
          expect(req.url.path, '/api/now/posts');
          expect(req.headers['Authorization'], 'Bearer tok-123');
          expect(body, contains('name="kind"\r\n\r\nphoto'));
          expect(body, contains('name="visibility"\r\n\r\nall'));
          expect(body, contains('name="latitude"'));
          expect(body, contains('name="longitude"'));
          expect(body, contains('name="file"; filename="foto.png"'));
          expect(body, contains('content-type: image/png'));
        },
      );
      expect(nowPostPublished.value?.id, 'foto-1');
    });

    testWidgets('video .mov: se declara video/quicktime, no mp4',
        (tester) async {
      await publishFile(
        tester,
        kindLabel: '🎥 Video',
        file: XFile.fromData(Uint8List.fromList(List.filled(8, 1)),
            name: 'clip.mov', path: 'clip.mov'),
        check: (req, body) {
          expect(body, contains('name="kind"\r\n\r\nvideo'));
          expect(body, contains('name="file"; filename="clip.mov"'));
          expect(body, contains('content-type: video/quicktime'));
        },
      );
    });
  });

  test('publishErrorMessage: 429, 413, 400 y lo demás', () {
    expect(publishErrorMessage(ApiException(429, 'x')),
        'Llegaste al límite de 5 publicaciones por hora');
    expect(publishErrorMessage(ApiException(413, 'x')),
        'El archivo es muy grande');
    expect(publishErrorMessage(ApiException(400, 'x')),
        'Revisa la foto o el texto');
    expect(publishErrorMessage(ApiException(500, 'x')),
        startsWith('No se pudo publicar'));
    expect(publishErrorMessage(Exception('sin red')),
        startsWith('No se pudo publicar'));
  });

  group('Explorar en modo Ahora', () {
    Map<String, dynamic> placesBody() => {
          'data': <dynamic>[],
          'meta': {'total': 0, 'page': 1, 'totalPages': 1}
        };

    /// Responde /places vacío y /now con [now]; anota todo en [seen].
    ApiClient exploreApi(List<http.Request> seen,
        {FutureOr<http.Response> Function(http.Request)? now}) {
      return ApiClient(client: MockClient((req) async {
        seen.add(req);
        final path = req.url.path;
        if (path.endsWith('/now')) {
          return await (now?.call(req) ??
              _ok({'posts': <dynamic>[], 'promos': <dynamic>[]}));
        }
        if (path.endsWith('/now/posts/post-1')) {
          return _ok(_postJson('post-1'));
        }
        if (path.endsWith('/places')) return _ok(placesBody());
        return http.Response('[]', 200);
      }));
    }

    Future<void> pumpExplore(WidgetTester tester, ApiClient api) async {
      await _phone(tester);
      await tester.pumpWidget(ChangeNotifierProvider<AuthProvider>.value(
        value: _auth(),
        child: MaterialApp(home: ExploreScreen(api: api)),
      ));
      await _settle(tester);
    }

    int nowCalls(List<http.Request> seen) =>
        seen.where((r) => r.url.path.endsWith('/now')).length;

    testWidgets('al entrar a Ahora pide /now con la caja visible del mapa',
        (tester) async {
      final seen = <http.Request>[];
      await pumpExplore(tester, exploreApi(seen));
      expect(nowCalls(seen), 0);

      await tester.tap(find.text('⚡ Ahora'));
      await _settle(tester);

      final q = seen
          .singleWhere((r) => r.url.path.endsWith('/now'))
          .url
          .queryParameters;
      final minLat = double.parse(q['minLat']!);
      final maxLat = double.parse(q['maxLat']!);
      final minLng = double.parse(q['minLng']!);
      final maxLng = double.parse(q['maxLng']!);
      expect(minLat, lessThan(_centerLat));
      expect(maxLat, greaterThan(_centerLat));
      expect(minLng, lessThan(_centerLng));
      expect(maxLng, greaterThan(_centerLng));
      // Sin nada en la zona, la franja lo dice en vez de quedar en blanco.
      expect(find.byKey(const Key('now-strip-empty')), findsOneWidget);
    });

    testWidgets('pines: promo con 🔥 y publicaciones con 📸/🎥/💬; se tocan',
        (tester) async {
      final seen = <http.Request>[];
      final api = exploreApi(seen,
          now: (_) => _ok({
                'posts': [
                  _postJson('post-1', kind: 'photo', lat: _centerLat + 0.004),
                  _postJson('post-2',
                      kind: 'video',
                      lat: _centerLat + 0.004,
                      lng: _centerLng - 0.004),
                  _postJson('post-3',
                      kind: 'text',
                      lat: _centerLat + 0.004,
                      lng: _centerLng + 0.004),
                ],
                'promos': [
                  _promoJson('promo-1', 'place-9', lng: _centerLng + 0.004),
                ],
              }));
      await pumpExplore(tester, api);

      // Locales: sin pines de Ahora.
      expect(find.byKey(const ValueKey('now-pin-post-post-1')), findsNothing);

      await tester.tap(find.text('⚡ Ahora'));
      await _settle(tester);

      String emojiIn(String key) => tester
          .widget<Text>(find.descendant(
              of: find.byKey(ValueKey(key)), matching: find.byType(Text)))
          .data!;
      expect(emojiIn('now-pin-post-post-1'), '📸');
      expect(emojiIn('now-pin-post-post-2'), '🎥');
      expect(emojiIn('now-pin-post-post-3'), '💬');
      expect(emojiIn('now-pin-promo-promo-1'), '🔥');

      // Colores de marca: promo ají, publicación hierba.
      Color bg(String key) => ((tester
              .widget<Container>(find.descendant(
                  of: find.byKey(ValueKey(key)),
                  matching: find.byType(Container)))
              .decoration) as BoxDecoration)
          .color!;
      expect(bg('now-pin-promo-promo-1'), const Color(0xFFECB365));
      expect(bg('now-pin-post-post-1'), const Color(0xFF606C38));

      // La franja "Hoy cerca de ti" lista lo mismo.
      expect(find.text('PROMO'), findsOneWidget);
      // La franja es una lista horizontal: solo se arman los chips que caben.
      expect(find.text('GENTE'), findsWidgets);
      expect(find.text('2x1 en ceviches'), findsOneWidget);

      // Tocar un pin de publicación abre NowPostScreen con su id.
      await tester.tap(find.byKey(const ValueKey('now-pin-post-post-1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.widget<NowPostScreen>(find.byType(NowPostScreen)).postId,
          'post-1');
    });

    testWidgets('tocar el pin de una promo abre la ficha de su local',
        (tester) async {
      final seen = <http.Request>[];
      final api = exploreApi(seen,
          now: (_) => _ok({
                'posts': <dynamic>[],
                'promos': [
                  _promoJson('promo-1', 'place-9', lat: _centerLat + 0.004)
                ],
              }));
      await pumpExplore(tester, api);
      await tester.tap(find.text('⚡ Ahora'));
      await _settle(tester);

      await tester.tap(find.byKey(const ValueKey('now-pin-promo-promo-1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
          tester
              .widget<PlaceDetailScreen>(find.byType(PlaceDetailScreen))
              .placeId,
          'place-9');
    });

    testWidgets('tocar un chip de la franja abre la publicación',
        (tester) async {
      final seen = <http.Request>[];
      final api = exploreApi(seen,
          now: (_) => _ok({
                'posts': [_postJson('post-1', lat: _centerLat + 0.004)],
                'promos': <dynamic>[],
              }));
      await pumpExplore(tester, api);
      await tester.tap(find.text('⚡ Ahora'));
      await _settle(tester);

      await tester.tap(find.byKey(const ValueKey('now-chip-post-post-1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(NowPostScreen), findsOneWidget);
    });

    testWidgets('error de red en la capa: aviso y el mapa sigue usable',
        (tester) async {
      final seen = <http.Request>[];
      await pumpExplore(
          tester, exploreApi(seen, now: (_) => _err(500, 'boom')));

      await tester.tap(find.text('⚡ Ahora'));
      await _settle(tester);

      expect(find.text('No se pudo cargar lo que pasa ahora'), findsOneWidget);
      // Sigue el resto: buscador, interruptor, lista y botón de ubicación.
      expect(find.text('¿Qué se te antoja?'), findsOneWidget);
      expect(find.text('Cerca de ti · 0'), findsOneWidget);
      expect(find.byIcon(Icons.my_location_rounded), findsOneWidget);
      // Y se puede volver a Locales.
      await tester.tap(find.text('🍽️ Locales'));
      await _settle(tester);
      expect(find.text('Cerca de ti · 0'), findsOneWidget);
    });

    testWidgets('Locales NO recarga al mover el mapa; Ahora sí, con espera',
        (tester) async {
      final seen = <http.Request>[];
      await pumpExplore(tester, exploreApi(seen));
      final placesBefore =
          seen.where((r) => r.url.path.endsWith('/places')).length;

      // En Locales, arrastrar el mapa no pide nada.
      await tester.dragFrom(const Offset(180, 330), const Offset(80, 0));
      await tester.pump(const Duration(milliseconds: 600));
      expect(nowCalls(seen), 0);
      expect(seen.where((r) => r.url.path.endsWith('/places')).length,
          placesBefore);

      // En Ahora, entra pide una vez y mover el mapa pide otra (con otra caja).
      await tester.tap(find.text('⚡ Ahora'));
      await _settle(tester);
      expect(nowCalls(seen), 1);

      await tester.dragFrom(const Offset(180, 330), const Offset(80, 0));
      await tester.pump(const Duration(milliseconds: 100));
      expect(nowCalls(seen), 1, reason: 'todavía en la espera de 400 ms');
      await tester.pump(const Duration(milliseconds: 600));
      expect(nowCalls(seen), 2);

      final boxes = seen
          .where((r) => r.url.path.endsWith('/now'))
          .map((r) => r.url.queryParameters['minLng'])
          .toSet();
      expect(boxes, hasLength(2));
      // Y aun en Ahora, los locales no se recargaron al mover.
      expect(seen.where((r) => r.url.path.endsWith('/places')).length,
          placesBefore);
    });

    testWidgets('una respuesta vieja no pisa a la nueva', (tester) async {
      final gates = <Completer<void>>[];
      final seen = <http.Request>[];
      final api = exploreApi(seen, now: (_) async {
        final index = gates.length;
        final gate = Completer<void>();
        gates.add(gate);
        await gate.future;
        return _ok({
          'posts': [
            _postJson(index == 0 ? 'viejo' : 'nuevo', lat: _centerLat + 0.004)
          ],
          'promos': <dynamic>[],
        });
      });
      await pumpExplore(tester, api);

      await tester.tap(find.text('⚡ Ahora'));
      await _settle(tester);
      await tester.dragFrom(const Offset(180, 330), const Offset(40, 0));
      await tester.pump(const Duration(milliseconds: 600));
      expect(gates, hasLength(2));

      // Llega primero la nueva y después la vieja.
      gates[1].complete();
      await _settle(tester);
      gates[0].complete();
      await _settle(tester);

      expect(find.byKey(const ValueKey('now-pin-post-nuevo')), findsOneWidget);
      expect(find.byKey(const ValueKey('now-pin-post-viejo')), findsNothing);
    });

    testWidgets(
        'publicar fuera de la vista: el mapa va al punto y se pide /now una sola vez',
        (tester) async {
      final seen = <http.Request>[];
      await pumpExplore(tester, exploreApi(seen));
      final far = _postJson('lejos', lat: _centerLat + 0.05);

      nowPostPublished.value = NowPost.fromJson(far);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));

      final calls = seen.where((r) => r.url.path.endsWith('/now')).toList();
      expect(calls, hasLength(1), reason: 'sin segunda petición por la espera');
      final q = calls.single.url.queryParameters;
      // La zona pedida ya es la del mapa movido: incluye el punto nuevo.
      expect(double.parse(q['minLat']!), lessThan(_centerLat + 0.05));
      expect(double.parse(q['maxLat']!), greaterThan(_centerLat + 0.05));
    });

    testWidgets('publicar estando ya en Ahora tampoco duplica la petición',
        (tester) async {
      final seen = <http.Request>[];
      await pumpExplore(tester, exploreApi(seen));
      await tester.tap(find.text('⚡ Ahora'));
      await _settle(tester);
      expect(nowCalls(seen), 1);

      nowPostPublished.value =
          NowPost.fromJson(_postJson('lejos', lat: _centerLat + 0.05));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));

      expect(nowCalls(seen), 2);
    });

    testWidgets('al publicar, Explorar pasa a Ahora y el pin nuevo aparece',
        (tester) async {
      final seen = <http.Request>[];
      var published = false;
      await pumpExplore(
          tester,
          exploreApi(seen,
              now: (_) => _ok({
                    'posts': published
                        ? [_postJson('nuevo', lat: _centerLat + 0.004)]
                        : <dynamic>[],
                    'promos': <dynamic>[],
                  })));
      expect(nowCalls(seen), 0);
      expect(find.byKey(const ValueKey('now-pin-post-nuevo')), findsNothing);

      published = true;
      nowPostPublished.value =
          NowPost.fromJson(_postJson('nuevo', lat: _centerLat + 0.004));
      await _settle(tester);

      expect(nowCalls(seen), greaterThanOrEqualTo(1));
      expect(find.byKey(const ValueKey('now-pin-post-nuevo')), findsOneWidget);
    });
  });
}
