import 'package:geolocator/geolocator.dart';

/// Quién da la posición del celular. En producción [currentNowPosition]; las
/// pruebas ponen una de mentira (el GPS real no corre en `flutter test`).
typedef NowLocator = Future<Position?> Function();

/// Posición actual, pidiendo permiso si falta (mismo flujo que Explorar).
/// Null si el GPS está apagado, el permiso se niega o no responde a tiempo.
Future<Position?> currentNowPosition() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)),
    );
  } catch (_) {
    return null;
  }
}
