import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wuarikes_app/core/api_client.dart';
import 'package:wuarikes_app/core/models.dart';
import 'package:wuarikes_app/screens/feed_screen.dart';
import 'package:wuarikes_app/screens/login_screen.dart';
import 'package:wuarikes_app/screens/media_screen.dart';
import 'package:wuarikes_app/screens/new_checkin_screen.dart';
import 'package:wuarikes_app/screens/place_detail_screen.dart';
import 'package:wuarikes_app/state/auth_provider.dart';

Map<String, dynamic> _placeJson({
  String? claimedBy,
  String? phone,
  String? address,
  bool coords = false,
  List<Map<String, String>>? hours,
}) =>
    {
      'id': 'p1',
      'name': 'El Chinito',
      'rating': '4.6',
      'totalReviews': 128,
      'category': {'id': 'c1', 'name': 'Cevichería', 'slug': 'cevicheria'},
      'claimedByUserId': claimedBy,
      'phone': phone,
      'address': address,
      if (coords) 'latitude': '-12.12',
      if (coords) 'longitude': '-77.03',
      if (hours != null) 'openingHours': hours,
    };

/// Servidor de mentira: lo que no está en [routes] responde 404.
class _Fake {
  final Map<String, Object?> routes;
  final seen = <http.Request>[];
  _Fake(Map<String, dynamic> place, {Map<String, Object?> more = const {}})
      : routes = {
          '/places/p1': place,
          '/places/p1/favorite': {'isSaved': false},
          '/checkins/feed': {
            'data': [],
            'meta': {'total': 0, 'page': 1, 'totalPages': 1}
          },
          '/public/loyalty/p1/program': null,
          '/places/p1/photos': {'data': [], 'total': 0},
          '/places/p1/promotions': [],
          ...more,
        };

  bool requested(String path) => seen.any((r) => r.url.path.endsWith(path));

  late final api = ApiClient(client: MockClient((req) async {
    seen.add(req);
    final path = req.url.path.replaceFirst('/api', '');
    if (!routes.containsKey(path)) {
      return http.Response('{"message":"no hay"}', 404);
    }
    return http.Response(jsonEncode(routes[path]), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});
  }));
}

AppUser _user({String? phone}) => AppUser(
    id: 'me-1',
    email: 'a@b.pe',
    fullName: 'Ana Prueba',
    details: {if (phone != null) 'phone': phone});

/// Anota las rutas que se abren, sin esperar a que se dibujen.
class _Pushes extends NavigatorObserver {
  final routes = <Route<dynamic>>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      routes.add(route);
}

Future<void> _pump(WidgetTester tester, _Fake fake,
    {AppUser? user, NavigatorObserver? observer}) async {
  // Tamaño de celular: el de prueba por defecto (800x600) desborda.
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final auth = AuthProvider(ApiClient())..user = user;
  await tester.pumpWidget(ChangeNotifierProvider<AuthProvider>.value(
    value: auth,
    child: MaterialApp(
        navigatorObservers: [if (observer != null) observer],
        home: PlaceDetailScreen(placeId: 'p1', api: fake.api)),
  ));
  await _settle(tester);
}

/// Deja resolver las llamadas de mentira (sin pumpAndSettle: el mapa anima).
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Baja hasta [target] (la ficha es una sola lista larga) y lo toca.
Future<void> _tapScrolled(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
}

Future<void> _openTab(WidgetTester tester, String tab) async {
  await tester.tap(find.byKey(ValueKey('tab-$tab')));
  await _settle(tester);
}

final _quickKeys = [
  for (final l in ['Cómo llegar', 'WhatsApp', 'Reservar', 'Llamar'])
    find.byKey(ValueKey('quick-$l'))
];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('pestañas', () {
    testWidgets('local sin reclamar: no hay pestaña Carta ni se pide la carta',
        (tester) async {
      final fake = _Fake(_placeJson());
      await _pump(tester, fake);

      expect(find.byKey(const ValueKey('tab-resumen')), findsOneWidget);
      expect(find.byKey(const ValueKey('tab-fotos')), findsOneWidget);
      expect(find.byKey(const ValueKey('tab-resenas')), findsOneWidget);
      expect(find.byKey(const ValueKey('tab-carta')), findsNothing);
      expect(find.text('Carta'), findsNothing);
      expect(fake.requested('/menu'), isFalse);
    });

    testWidgets(
        'local reclamado: hay pestaña Carta y al abrirla muestra la carta',
        (tester) async {
      final fake = _Fake(_placeJson(claimedBy: 'owner-1'), more: {
        '/places/p1/menu': {
          'place': {'menuImageUrls': []},
          'categories': [
            {
              'name': 'Entradas',
              'dishes': [
                {'name': 'Ceviche clásico', 'price': 32}
              ]
            }
          ]
        },
      });
      await _pump(tester, fake);

      expect(find.byKey(const ValueKey('tab-carta')), findsOneWidget);
      // La carta se pide al abrir la pestaña, no antes.
      expect(fake.requested('/menu'), isFalse);

      await _openTab(tester, 'carta');
      expect(fake.requested('/menu'), isTrue);
      expect(find.text('Ceviche clásico'), findsOneWidget);
    });

    testWidgets('Resumen conserva visita rápida, Quiero ir, horario y reportar',
        (tester) async {
      await _pump(tester, _Fake(_placeJson(phone: '014567890')));

      expect(find.text('Visita rápida'), findsOneWidget);
      expect(find.text('Quiero ir · 0'), findsOneWidget);
      expect(find.text('Horario y contacto'), findsOneWidget);
      expect(find.text('Reportar información desactualizada'), findsOneWidget);
    });

    testWidgets('Reseñas: valoraciones, lista, vacío y Ver todas',
        (tester) async {
      await _pump(
          tester,
          _Fake(_placeJson(), more: {
            '/places/p1/rating-distribution': [
              {'rating': 5, 'count': 3}
            ],
          }));

      expect(find.text('Reseñas recientes'), findsNothing);
      await _openTab(tester, 'resenas');
      expect(find.text('Valoraciones'), findsOneWidget);
      expect(find.text('Reseñas recientes'), findsOneWidget);
      expect(find.text('No se ha registrado una reseña.'), findsOneWidget);

      await _tapScrolled(tester, find.text('Ver todas las reseñas'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(FeedScreen), findsOneWidget);
      expect(tester.widget<FeedScreen>(find.byType(FeedScreen)).placeId, 'p1');
    });

    testWidgets(
        'con fotos: el carrusel suma la portada y las fotos, y Fotos las muestra',
        (tester) async {
      await _pump(
          tester,
          _Fake({
            ..._placeJson(),
            'coverImageUrl': 'https://img.test/portada.jpg',
          }, more: {
            '/places/p1/photos': {
              'data': [
                {'id': 'a', 'url': 'https://img.test/a.jpg'},
                {'id': 'b', 'url': 'https://img.test/portada.jpg'},
                {'id': 'c', 'url': 'https://img.test/c.jpg'},
              ],
              'total': 3
            },
          }));

      // Portada + a + c (la portada repetida no se duplica): 3 páginas.
      final pager = tester.widget<PageView>(find.byType(PageView));
      expect(
          (pager.childrenDelegate as SliverChildBuilderDelegate)
              .estimatedChildCount,
          3);

      await _openTab(tester, 'fotos');
      expect(find.text('Todavía no hay fotos de este local.'), findsNothing);
      expect(find.byType(GridView), findsOneWidget);
    });

    testWidgets('Fotos: sin fotos avisa y "Ver fotos y videos" abre la galería',
        (tester) async {
      await _pump(tester, _Fake(_placeJson(claimedBy: 'owner-1')));

      await _openTab(tester, 'fotos');
      expect(find.text('Todavía no hay fotos de este local.'), findsOneWidget);

      await _tapScrolled(tester, find.text('Ver fotos y videos'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final media = tester.widget<MediaScreen>(find.byType(MediaScreen));
      expect(media.placeId, 'p1');
      expect(media.ownerId, 'owner-1');
    });
  });

  group('acciones rápidas', () {
    testWidgets(
        'sin teléfono, dirección, coordenadas ni reserva no sale ninguna',
        (tester) async {
      await _pump(tester, _Fake(_placeJson()));

      for (final f in _quickKeys) {
        expect(f, findsNothing);
      }
    });

    testWidgets('con celular, dirección y reserva salen las cuatro',
        (tester) async {
      await _pump(
          tester,
          _Fake(_placeJson(phone: '987654321', address: 'Av. Larco 123'),
              more: {
                '/public/places/p1/actions': {
                  'bookingUrl': 'https://admin.wuarikes.com/reservar/p1',
                  'orderWhatsapp': null,
                },
              }));

      for (final f in _quickKeys) {
        expect(f, findsOneWidget);
      }
    });

    testWidgets('con teléfono fijo sale Llamar pero no WhatsApp ni Reservar',
        (tester) async {
      await _pump(tester, _Fake(_placeJson(phone: '014567890')));

      expect(_quickKeys[3], findsOneWidget); // Llamar
      expect(_quickKeys[1], findsNothing); // WhatsApp
      expect(_quickKeys[2], findsNothing); // Reservar
      expect(_quickKeys[0], findsNothing); // Cómo llegar
    });

    testWidgets('el WhatsApp de pedidos del local sale aunque no haya teléfono',
        (tester) async {
      await _pump(
          tester,
          _Fake(_placeJson(), more: {
            '/public/places/p1/actions': {
              'bookingUrl': null,
              'orderWhatsapp': '51987654321'
            },
          }));

      expect(_quickKeys[1], findsOneWidget);
      expect(_quickKeys[3], findsNothing);
    });

    test('placeQuickActions: orden, enlaces y datos que faltan', () {
      final place = Place.fromJson(_placeJson(
          phone: '987 654 321', address: 'Av. Larco 123', coords: true));
      final actions = placeQuickActions(place, {
        'orderWhatsapp': null,
        'bookingUrl': 'https://admin.wuarikes.com/reservar/p1',
      });
      expect(actions.map((a) => a.label),
          ['Cómo llegar', 'WhatsApp', 'Reservar', 'Llamar']);
      expect(actions[0].url, contains('destination=-12.12,-77.03'));
      expect(actions[1].url, startsWith('https://wa.me/51987654321?text='));
      expect(actions[3].url, 'tel:987 654 321');

      // Sin coordenadas, Cómo llegar usa la dirección.
      final byAddress = placeQuickActions(
          Place.fromJson(_placeJson(address: 'Av. Larco 123')), {});
      expect(byAddress.single.label, 'Cómo llegar');
      expect(byAddress.single.url, contains('query=Av.%20Larco%20123'));

      // Una reserva que no es http(s) no se ofrece.
      expect(
          placeQuickActions(
              Place.fromJson(_placeJson()), {'bookingUrl': 'javascript:x'}),
          isEmpty);
    });

    test('whatsappNumber: solo números que pueden tener WhatsApp', () {
      expect(whatsappNumber('987654321'), '51987654321');
      expect(whatsappNumber('987 654 321'), '51987654321');
      expect(whatsappNumber('51987654321'), '51987654321');
      expect(whatsappNumber('+51 987 654 321'), '51987654321');
      expect(whatsappNumber('+34 612 345 678'), '34612345678');
      expect(whatsappNumber('014567890'), isNull); // fijo
      expect(whatsappNumber('4567890'), isNull);
      expect(whatsappNumber(''), isNull);
      expect(whatsappNumber(null), isNull);
    });
  });

  group('barra de abajo', () {
    testWidgets('con sesión, "📍 Estoy aquí · check-in" abre el check-in',
        (tester) async {
      final pushes = _Pushes();
      await _pump(tester, _Fake(_placeJson()), user: _user(), observer: pushes);
      final before = pushes.routes.length;

      // Sin pump después: la ruta se anota al abrirse y no se llega a dibujar
      // (NewCheckinScreen, sin tocar, desborda con la fuente ancha de prueba).
      await tester.tap(find.text('📍 Estoy aquí · check-in'));

      expect(pushes.routes.length, before + 1);
      final route = pushes.routes.last as MaterialPageRoute;
      final screen =
          route.builder(tester.element(find.byType(PlaceDetailScreen)));
      expect(screen, isA<NewCheckinScreen>());
      expect((screen as NewCheckinScreen).place.id, 'p1');
    });

    testWidgets('invitado: el check-in pide iniciar sesión, igual que antes',
        (tester) async {
      await _pump(tester, _Fake(_placeJson()));

      await tester.tap(find.text('📍 Estoy aquí · check-in'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(NewCheckinScreen), findsNothing);
    });

    testWidgets('📷 abre la galería Fotos y videos del local', (tester) async {
      await _pump(tester, _Fake(_placeJson(claimedBy: 'owner-1')));

      await tester.tap(find.text('📷'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final media = tester.widget<MediaScreen>(find.byType(MediaScreen));
      expect(media.placeId, 'p1');
      expect(media.ownerId, 'owner-1');
    });
  });

  group('promo del día', () {
    testWidgets('sin promociones no hay caja', (tester) async {
      await _pump(tester, _Fake(_placeJson()));

      expect(find.byKey(const ValueKey('promo-box')), findsNothing);
      expect(find.text('Más promociones'), findsNothing);
    });

    testWidgets(
        'con promociones, la caja lleva la primera y el resto va en Resumen',
        (tester) async {
      final ends = DateTime.now().add(const Duration(days: 3));
      await _pump(
          tester,
          _Fake(_placeJson(), more: {
            '/places/p1/promotions': [
              {
                'id': 'a',
                'title': '2x1 en ceviches',
                'description': 'De lunes a jueves',
                'endsAt': ends.toUtc().toIso8601String(),
              },
              {'id': 'b', 'title': 'Chicha gratis'},
            ],
          }));

      expect(find.byKey(const ValueKey('promo-box')), findsOneWidget);
      expect(find.textContaining('2x1 en ceviches'), findsOneWidget);
      expect(find.textContaining('termina'), findsOneWidget);
      expect(find.text('De lunes a jueves'), findsOneWidget);
      expect(find.text('Más promociones'), findsOneWidget);
      expect(find.text('Chicha gratis'), findsOneWidget);
    });

    testWidgets('una sola promoción no repite la sección Más promociones',
        (tester) async {
      await _pump(
          tester,
          _Fake(_placeJson(), more: {
            '/places/p1/promotions': [
              {'id': 'a', 'title': '2x1 en ceviches'},
            ],
          }));

      expect(find.byKey(const ValueKey('promo-box')), findsOneWidget);
      expect(find.text('Más promociones'), findsNothing);
    });

    testWidgets('si las promociones fallan, la ficha sigue sin caja',
        (tester) async {
      final fake = _Fake(_placeJson());
      fake.routes.remove('/places/p1/promotions');
      await _pump(tester, fake);

      expect(find.text('El Chinito'), findsOneWidget);
      expect(find.byKey(const ValueKey('promo-box')), findsNothing);
    });
  });

  group('tarjeta de premios', () {
    Map<String, Object?> card({required bool isNew, int stamps = 6}) => {
          'program': {
            'type': 'stamps',
            'stampsToReward': 8,
            'pointsPerVisit': 10,
            'rewardDescription': 'Un postre gratis',
            'isActive': true,
          },
          'card': isNew ? null : {'stamps': stamps},
          'isNew': isNew,
        };

    testWidgets('con tarjeta muestra "Tu tarjeta: 6/8 sellos"', (tester) async {
      await _pump(
          tester,
          _Fake(_placeJson(), more: {
            '/public/loyalty/p1/card/987654321': card(isNew: false),
          }),
          user: _user(phone: '987654321'));

      expect(find.byKey(const ValueKey('loyalty-card-box')), findsOneWidget);
      expect(find.textContaining('Tu tarjeta: 6/8 sellos'), findsOneWidget);
      expect(find.text('Un postre gratis'), findsOneWidget);
      // El detalle ya está arriba: la sección Fidelización no se repite.
      expect(find.text('Fidelización'), findsNothing);
    });

    testWidgets('con sesión y sin tarjeta aún, no hay caja y sigue el aviso',
        (tester) async {
      await _pump(
          tester,
          _Fake(_placeJson(), more: {
            '/public/loyalty/p1/card/987654321': card(isNew: true),
          }),
          user: _user(phone: '987654321'));

      expect(find.byKey(const ValueKey('loyalty-card-box')), findsNothing);
      expect(find.text('Fidelización'), findsOneWidget);
      expect(find.textContaining('Aún no tienes tarjeta aquí'), findsOneWidget);
    });

    testWidgets('invitado: sin caja, y el programa conserva "Agregar teléfono"',
        (tester) async {
      await _pump(
          tester,
          _Fake(_placeJson(), more: {
            '/public/loyalty/p1/program': {
              'type': 'stamps',
              'stampsToReward': 8,
              'pointsPerVisit': 10,
              'isActive': true,
            },
          }));

      expect(find.byKey(const ValueKey('loyalty-card-box')), findsNothing);
      expect(find.text('Fidelización'), findsOneWidget);
      expect(find.text('Agregar'), findsOneWidget);
    });

    testWidgets('local sin programa: no hay nada de fidelización',
        (tester) async {
      await _pump(tester, _Fake(_placeJson()), user: _user(phone: '987654321'));

      expect(find.byKey(const ValueKey('loyalty-card-box')), findsNothing);
      expect(find.text('Fidelización'), findsNothing);
    });

    test('loyaltyCardLabel: sellos, falta uno, completa y puntos', () {
      LoyaltyProgram program(String type) => LoyaltyProgram(
          type: type, stampsToReward: 8, pointsPerVisit: 10, isActive: true);
      LoyaltyCard card(int? stamps, {int? points}) => LoyaltyCard(
          program: program('stamps'),
          stamps: stamps,
          points: points,
          isNew: false);

      expect(loyaltyCardLabel(program('stamps'), card(6)),
          '🎁 Tu tarjeta: 6/8 sellos · ¡Te faltan 2 para tu premio!');
      expect(loyaltyCardLabel(program('stamps'), card(7)),
          '🎁 Tu tarjeta: 7/8 sellos · ¡Te falta 1 para tu premio!');
      expect(loyaltyCardLabel(program('stamps'), card(8)),
          '🎁 Tu tarjeta: 8/8 sellos · ¡Ya puedes canjear tu premio!');
      expect(loyaltyCardLabel(program('stamps'), card(null)),
          '🎁 Tu tarjeta: 0/8 sellos · ¡Te faltan 8 para tu premio!');
      expect(loyaltyCardLabel(program('points'), card(null, points: 120)),
          '🎁 Tu tarjeta: 120 puntos');
    });
  });

  group('guardar y compartir', () {
    testWidgets('invitado: Guardar pide iniciar sesión', (tester) async {
      await _pump(tester, _Fake(_placeJson()));

      await tester.tap(find.byTooltip('Guardar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('con sesión: Guardar marca el favorito', (tester) async {
      final fake = _Fake(_placeJson());
      await _pump(tester, fake, user: _user());

      await tester.tap(find.byTooltip('Guardar'));
      await _settle(tester);

      expect(
          fake.seen.any((r) =>
              r.method == 'POST' && r.url.path.endsWith('/places/p1/favorite')),
          isTrue);
      expect(find.byTooltip('Quitar de favoritos'), findsOneWidget);
    });

    testWidgets('Compartir y Volver están en la foto', (tester) async {
      await _pump(tester, _Fake(_placeJson()));

      expect(find.byTooltip('Compartir'), findsOneWidget);
      expect(find.byTooltip('Volver'), findsOneWidget);
    });
  });

  group('encabezado', () {
    test('openUntilLabel: abierto ahora en Lima, y nunca afirma cerrado', () {
      final hours = [
        {'day': 'mon', 'open': '08:00', 'close': '17:00'},
        {'day': 'tue', 'open': '20:00', 'close': '02:00'},
      ];
      // 2026-11-09 es lunes. 20:00 UTC = 15:00 en Lima.
      final monday3pm = DateTime.utc(2026, 11, 9, 20);
      expect(openUntilLabel(hours, now: monday3pm), 'Abierto hasta 17:00');
      // 23:00 UTC = 18:00 en Lima: ya cerró.
      expect(openUntilLabel(hours, now: DateTime.utc(2026, 11, 9, 23)), isNull);
      // Martes 22:00 en Lima (03:00 UTC del miércoles): turno de noche que cierra a las 02:00.
      expect(openUntilLabel(hours, now: DateTime.utc(2026, 11, 11, 3)),
          'Abierto hasta 02:00');
      // Sin horario por día no se dice nada.
      expect(openUntilLabel(null, now: monday3pm), isNull);
      expect(openUntilLabel(const [], now: monday3pm), isNull);
      expect(openUntilLabel('9:00 AM - 5:00 PM', now: monday3pm), isNull);
    });

    testWidgets(
        'muestra "Abierto hasta" solo si el horario por día lo confirma',
        (tester) async {
      // Todos los días, todo el día: abierto sea cual sea la hora de la prueba.
      final allDay = [
        for (final d in ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'])
          {'day': d, 'open': '00:00', 'close': '23:59'}
      ];
      await _pump(tester, _Fake(_placeJson(hours: allDay)));
      expect(find.text('Abierto hasta 23:59'), findsOneWidget);
    });

    testWidgets('sin horario por día no hay "Abierto hasta"', (tester) async {
      await _pump(tester, _Fake(_placeJson()));
      expect(find.textContaining('Abierto hasta'), findsNothing);
    });
  });
}
