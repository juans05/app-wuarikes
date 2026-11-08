import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/geofence_sync_service.dart';
import '../screens/battery_optimization_onboarding_screen.dart';

/// Prende los avisos de cercanía: aviso de Google Play, permiso "todo el
/// tiempo", pantalla de batería (una vez) y registro de zonas. Lo usan Ajustes
/// y Mis premios. Devuelve si quedaron activos.
Future<bool> enableProximityAlerts(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  void snack(String msg) => messenger.showSnackBar(SnackBar(content: Text(msg)));

  if (!await _showLocationDisclosure(context)) return false;
  if (!await _requestAlwaysLocation()) {
    snack('Necesitamos el permiso de ubicación "Todo el tiempo" para avisarte.');
    return false;
  }
  final prefs = await SharedPreferences.getInstance();
  if (!context.mounted) return false;
  if (!(prefs.getBool('battery_onboarding_shown') ?? false)) {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (c) => BatteryOptimizationOnboardingScreen(
        onDismiss: () => Navigator.of(c).pop(),
      ),
    ));
  }
  final ok = await GeofenceSyncService().start();
  await prefs.setBool(geofencingPrefKey, ok);
  if (!ok) snack('No pudimos activar los avisos de cercanía. Intenta de nuevo.');
  return ok;
}

/// Google Play requires this in-app disclosure before asking for
/// background location ("prominent disclosure").
Future<bool> _showLocationDisclosure(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Ubicación en segundo plano'),
        content: const Text(
            'Wuarikes recopila tu ubicación para avisarte cuando pases cerca de un huarique donde tienes sellos o un premio, incluso cuando la app está cerrada o no se está usando.\n\n'
            'Tu ubicación no se envía a nuestros servidores: la comparación se hace en tu teléfono. Puedes desactivarlo cuando quieras desde Ajustes.\n\n'
            'En la siguiente pantalla elige "Permitir todo el tiempo".'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('No, gracias')),
          FilledButton(
              onPressed: () => Navigator.of(c).pop(true),
              child: const Text('Continuar')),
        ],
      ),
    ) ??
    false;

/// whileInUse first, then a second request upgrades to "always" (on
/// Android 11+ this opens the system settings page).
Future<bool> _requestAlwaysLocation() async {
  var p = await Geolocator.checkPermission();
  if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
  if (p == LocationPermission.whileInUse) p = await Geolocator.requestPermission();
  return p == LocationPermission.always;
}
