import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';
import 'models.dart';
import 'notification_service.dart';

const _prefix = 'reward_ready_notified_';

/// "¡Completaste tus sellos!" una vez por premio: se marca al avisar y se
/// desmarca cuando la tarjeta vuelve a tener sellos pendientes (canjeó).
/// Corre al abrir la app y al volver a ella; sin sesión o sin red no hace nada.
Future<void> notifyCompletedStamps(
  Future<List<MyLoyaltyCard>> Function() loadCards,
  Future<void> Function(String title, String body) notify,
) async {
  try {
    final cards = await loadCards();
    final prefs = await SharedPreferences.getInstance();
    for (final c in cards.where((c) => c.programType == 'stamps' && c.stampsRemaining != null)) {
      final key = '$_prefix${c.placeId}';
      if (!c.rewardReady) {
        await prefs.remove(key);
      } else if (prefs.getBool(key) != true) {
        await notify('¡Completaste tus sellos!',
            'Ya puedes canjear ${c.rewardTitle ?? 'tu premio'} en ${c.placeName}.');
        await prefs.setBool(key, true);
      }
    }
  } catch (_) {
    // Sin sesión (401) o sin red: se intenta la próxima vez que se abra la app.
  }
}

Future<void> checkCompletedStamps() => notifyCompletedStamps(
      ApiClient().getMyLoyaltyCards,
      (title, body) => NotificationService().showNotification(title: title, body: body),
    );
