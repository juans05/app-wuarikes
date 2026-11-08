import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wuarikes_app/core/api_client.dart';
import 'package:wuarikes_app/core/models.dart';
import 'package:wuarikes_app/screens/explore_screen.dart';
import 'package:wuarikes_app/screens/favorites_screen.dart';
import 'package:wuarikes_app/screens/feed_screen.dart';
import 'package:wuarikes_app/screens/main_shell.dart';
import 'package:wuarikes_app/screens/my_loyalty_screen.dart';
import 'package:wuarikes_app/screens/profile_screen.dart';
import 'package:wuarikes_app/screens/register_place_screen.dart';
import 'package:wuarikes_app/state/auth_provider.dart';

/// AuthProvider sin red: `user` se fija a mano (null = invitado).
AuthProvider _auth({bool loggedIn = false}) {
  final auth = AuthProvider(ApiClient());
  if (loggedIn) {
    auth.user = AppUser(id: 'u1', email: 'a@b.pe', fullName: 'Ana Prueba');
  }
  return auth;
}

/// RegisterPlaceScreen y ProfileScreen ya desbordan con la fuente de prueba
/// (Ahem, muy ancha); no tiene que ver con lo que se prueba aquí.
void _ignoreOverflow() {
  final onError = FlutterError.onError;
  FlutterError.onError = (details) {
    if (!details.exceptionAsString().contains('overflowed')) {
      onError!(details);
    }
  };
  addTearDown(() => FlutterError.onError = onError);
}

Future<void> _pump(WidgetTester tester, Widget home, AuthProvider auth,
    {double bottomInsetPx = 0}) async {
  // Tamaño de celular: el de prueba por defecto (800x600) desborda Explorar.
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  if (bottomInsetPx > 0) {
    // Barra de gestos / navegación del sistema abajo.
    tester.view.padding = FakeViewPadding(bottom: bottomInsetPx);
    tester.view.viewPadding = FakeViewPadding(bottom: bottomInsetPx);
  }
  addTearDown(tester.view.reset);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);
  await tester.pumpWidget(ChangeNotifierProvider<AuthProvider>.value(
    value: auth,
    child: MaterialApp(home: home),
  ));
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'la barra muestra Explorar, Actividad, Premios y Perfil, y no Favoritos',
      (tester) async {
    await _pump(tester, const MainShell(), _auth());

    for (final label in ['Explorar', 'Actividad', 'Premios', 'Perfil']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('Favoritos'), findsNothing);
  });

  testWidgets('las pestañas abren Actividad, Premios y Perfil en ese orden',
      (tester) async {
    await _pump(tester, const MainShell(), _auth());

    expect(find.byType(ExploreScreen), findsOneWidget); // pestaña inicial

    double x(Finder f) => tester.getCenter(f).dx;
    final xs = [
      x(find.text('Explorar')),
      x(find.text('Actividad')),
      x(find.byIcon(Icons.add_rounded)),
      x(find.text('Premios')),
      x(find.text('Perfil')),
    ];
    expect(xs, orderedEquals([...xs]..sort()),
        reason: 'Explorar < Actividad < ＋ < Premios < Perfil');
    expect(xs.toSet().length, 5);

    await tester.tap(find.text('Actividad'));
    await tester.pump();
    expect(find.byType(FeedScreen), findsOneWidget);

    await tester.tap(find.text('Premios'));
    await tester.pump();
    expect(find.byType(MyLoyaltyScreen), findsOneWidget);
    // Invitado: igual que antes, pide iniciar sesion.
    expect(find.textContaining('Inicia sesión para ver todas tus tarjetas'),
        findsOneWidget);

    await tester.tap(find.text('Perfil'));
    await tester.pump();
    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(find.textContaining('Inicia sesión para ver tu perfil'),
        findsOneWidget);
  });

  testWidgets('el ＋ ofrece publicar y sugerir un lugar', (tester) async {
    await _pump(tester, const MainShell(), _auth());
    expect(find.text('Publicar lo que pasa aquí'), findsNothing);

    final plusCenter = tester.getCenter(find.byIcon(Icons.add_rounded));
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Publicar lo que pasa aquí'), findsOneWidget);
    expect(find.text('Sugerir un lugar nuevo'), findsOneWidget);
    // El ＋ se vuelve × en el mismo lugar.
    expect(tester.getCenter(find.byIcon(Icons.close_rounded)), plusCenter);

    // Tocar el fondo oscuro lo cierra.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('Sugerir un lugar nuevo'), findsNothing);
  });

  testWidgets('con barra de gestos el × queda sobre el ＋ y las opciones arriba',
      (tester) async {
    // 102 px físicos = 34 px lógicos de inset inferior.
    await _pump(tester, const MainShell(), _auth(), bottomInsetPx: 102);

    final plusCenter = tester.getCenter(find.byIcon(Icons.add_rounded));
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();

    final closeCenter = tester.getCenter(find.byIcon(Icons.close_rounded));
    expect(closeCenter, plusCenter);
    // Las opciones quedan por encima del botón (su borde superior: -28).
    expect(tester.getBottomLeft(find.text('Sugerir un lugar nuevo')).dy,
        lessThan(closeCenter.dy - 28));
  });

  testWidgets('el menú se cierra con el × y con atrás, y el shell se queda',
      (tester) async {
    await _pump(tester, const MainShell(), _auth());

    // Con el ×.
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Sugerir un lugar nuevo'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Sugerir un lugar nuevo'), findsNothing);
    expect(find.byType(MainShell), findsOneWidget);
    expect(find.byType(RegisterPlaceScreen), findsNothing);

    // Con el botón atrás del sistema.
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Sugerir un lugar nuevo'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Sugerir un lugar nuevo'), findsNothing);
    expect(find.byType(MainShell), findsOneWidget);
    expect(find.byType(RegisterPlaceScreen), findsNothing);
  });

  testWidgets('"Sugerir un lugar nuevo" abre RegisterPlaceScreen',
      (tester) async {
    _ignoreOverflow();
    await _pump(tester, const MainShell(), _auth());

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sugerir un lugar nuevo'));
    await tester.pumpAndSettle();

    expect(find.byType(RegisterPlaceScreen), findsOneWidget);
  });

  testWidgets('la fila Guardados del perfil abre FavoritesScreen',
      (tester) async {
    _ignoreOverflow();
    await _pump(tester, const ProfileScreen(), _auth(loggedIn: true));

    final guardados = find.text('Guardados');
    await tester.scrollUntilVisible(guardados, 200,
        scrollable: find.byType(Scrollable).first);
    // La fila quedó más abajo (tras las insignias): la lista estima el largo
    // mientras se arma y asienta el desplazamiento recién en el cuadro siguiente.
    await tester.pump();
    await tester.tap(guardados);
    await tester.pumpAndSettle();

    expect(find.byType(FavoritesScreen), findsOneWidget);
  });
}
