import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();

  NotificationService._internal();

  factory NotificationService() {
    return _instance;
  }

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'wuarikes_main',
      'Wuarikes',
      channelDescription: 'Recordatorios y avisos de fidelización',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  // Lazy and idempotent: the geofence handler can run before main() finished.
  Future<void> init() async {
    if (_ready) return;
    tz_data.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _ready = true;
  }

  Future<void> showNotification({
    required String title,
    required String body,
    Map<String, String>? payload,
  }) async {
    await init();
    await _plugin.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body,
      notificationDetails: _details,
      payload: payload?['placeId'],
    );
  }

  /// Daily lunch/dinner nudges. Safe to call on every launch: same ids replace
  /// the previous schedule. Lima has no DST, so a fixed zone is exact.
  Future<void> scheduleMealReminders() async {
    await init();
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _daily(1, 12, '¿Dónde almorzamos hoy?',
        'Mira el huarique del día cerca de ti 🍽️');
    await _daily(2, 19, '¿Qué te provoca cenar?',
        'Descubre un huarique nuevo y suma XP en tu racha 🔥');
  }

  Future<void> _daily(int id, int hour, String title, String body) async {
    final lima = tz.getLocation('America/Lima');
    final now = tz.TZDateTime.now(lima);
    var at = tz.TZDateTime(lima, now.year, now.month, now.day, hour);
    if (at.isBefore(now)) at = at.add(const Duration(days: 1));
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: at,
      notificationDetails: _details,
      // Inexact: avoids the exact-alarm permission; ±few minutes is fine here.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }
}
