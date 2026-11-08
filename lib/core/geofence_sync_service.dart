import 'package:flutter/widgets.dart';
import 'package:geofence_foreground_service/constants/geofence_event_type.dart';
import 'package:geofence_foreground_service/exports.dart' show LatLng;
import 'package:geofence_foreground_service/geofence_foreground_service.dart';
import 'package:geofence_foreground_service/models/zone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';
import 'geofence_callback_handler.dart';
import 'loyalty_notification_cache.dart';
import 'notification_service.dart';

const geofencingPrefKey = 'geofencing_enabled';
const _radiusMeters = 200.0;
const _cooldownHours = 12;
const _maxZones = 100; // Android's per-app geofence limit.

/// Runs in a background isolate spawned by the plugin's WorkManager worker.
@pragma('vm:entry-point')
void geofenceCallbackDispatcher() {
  GeofenceForegroundService().handleTrigger(
    backgroundTriggerHandler: (zoneId, type) async {
      if (type == GeofenceEventType.enter) {
        await GeofenceSyncService().handleGeofenceEntry(zoneId);
      }
      return true;
    },
  );
}

class GeofenceSyncService {
  static final GeofenceSyncService _instance = GeofenceSyncService._internal();
  final _api = ApiClient();
  final _cache = LoyaltyNotificationCache();
  final _notificationService = NotificationService();
  final _plugin = GeofenceForegroundService();

  GeofenceSyncService._internal();

  factory GeofenceSyncService() => _instance;

  static Future<bool> isEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(geofencingPrefKey) ??
      false;

  /// Re-registers on every app launch when enabled: Android drops all
  /// geofences on reboot and the plugin can't restart without an Activity.
  // ponytail: geofences come back on next app open after a reboot, not at boot; a native boot re-register needs a plugin that works without an Activity.
  Future<void> resumeIfEnabled() async {
    if (await isEnabled()) await start();
  }

  /// Fetches the user's loyalty cards, caches them for the background isolate
  /// and registers one geofence per restaurant. Returns false on failure.
  Future<bool> start() async {
    try {
      final cards = (await _api.getMyLoyaltyCards())
          .where((c) => c.hasLocation && c.stampsRemaining != null)
          .take(_maxZones)
          .toList();

      for (final card in cards) {
        final old = await _cache.getCard(card.placeId);
        await _cache.putCard(card.placeId, {
          'placeName': card.placeName,
          'stampsRemaining': card.stampsRemaining,
          'rewardTitle': card.rewardTitle,
          'notifiedAt': old?['notifiedAt'],
        });
      }

      final started = await _plugin.startGeofencingService(
        notificationChannelId: 'wuarikes_geofence',
        contentTitle: 'Avisos de cercanía activos',
        contentText: 'Te avisaremos cuando pases cerca de tus huariques',
        serviceId: 525600,
        callbackDispatcher: geofenceCallbackDispatcher,
      );
      if (!started) return false;

      await _plugin.removeAllGeoFences();
      for (final card in cards) {
        await _plugin.addGeofenceZone(
          zone: Zone(
            id: card.placeId,
            radius: _radiusMeters,
            coordinates: [LatLng.degree(card.latitude!, card.longitude!)],
            triggers: const [GeofenceEventType.enter],
            notificationResponsivenessMs: 60000,
          ),
        );
      }
      return true;
    } catch (e) {
      debugPrint('Geofencing not started: $e');
      return false;
    }
  }

  Future<void> stop() async {
    try {
      await _plugin.removeAllGeoFences();
      await _plugin.stopGeofencingService();
    } catch (e) {
      debugPrint('Geofencing not stopped: $e');
    }
  }

  Future<void> handleGeofenceEntry(String placeId) async {
    final card = await _cache.getCard(placeId);
    if (card == null) return;

    final now = DateTime.now();
    final last = card['notifiedAt'] != null
        ? DateTime.tryParse(card['notifiedAt'] as String)
        : null;
    if (!shouldNotify(card, last, now, _cooldownHours)) return;

    final message = proximityMessage(card);
    await _notificationService.showNotification(
      title: message.title,
      body: message.body,
      payload: {'placeId': placeId},
    );
    await _cache.updateNotifiedAt(placeId, now);
  }
}

/// Builds the notification copy. `stampsRemaining` is how many stamps are
/// still MISSING for the reward (0 = reward ready to redeem).
({String title, String body}) proximityMessage(Map<String, dynamic> card) {
  final place = card['placeName'] as String? ?? 'tu huarique';
  final reward = card['rewardTitle'] as String? ?? 'tu premio';
  final remaining = (card['stampsRemaining'] as num?)?.toInt() ?? 0;
  if (remaining <= 0) {
    return (title: '¡Tienes para canjear en $place!', body: 'Muestra tu tarjeta y canjea: $reward');
  }
  final falta = remaining == 1 ? 'Te falta 1 sello' : 'Te faltan $remaining sellos';
  return (title: 'Estás cerca de $place', body: '$falta para $reward');
}
