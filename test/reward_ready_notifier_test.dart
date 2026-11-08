import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wuarikes_app/core/models.dart';
import 'package:wuarikes_app/core/reward_ready_notifier.dart';

MyLoyaltyCard card(String id, int stamps, int? remaining, {String type = 'stamps'}) => MyLoyaltyCard(
      placeId: id,
      placeName: 'Don José',
      programType: type,
      stamps: stamps,
      points: 0,
      stampsToReward: 10,
      stampsRemaining: remaining,
      rewardTitle: 'Postre gratis',
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('avisa una sola vez por premio completado, y otra vez tras canjear y volver a completar', () async {
    final sent = <String>[];
    Future<void> notify(String title, String body) async => sent.add('$title|$body');

    await notifyCompletedStamps(() async => [card('a', 10, 0), card('b', 4, 6), card('c', 0, null, type: 'points')], notify);
    expect(sent, ['¡Completaste tus sellos!|Ya puedes canjear Postre gratis en Don José.']);

    await notifyCompletedStamps(() async => [card('a', 10, 0)], notify);
    expect(sent, hasLength(1)); // ya avisado

    await notifyCompletedStamps(() async => [card('a', 0, 10)], notify); // canjeó
    await notifyCompletedStamps(() async => [card('a', 10, 0)], notify); // completó de nuevo
    expect(sent, hasLength(2));
  });

  test('sin sesión o sin red no hace nada ni lanza', () async {
    final sent = <String>[];
    await notifyCompletedStamps(() async => throw Exception('401'), (t, b) async => sent.add(t));
    expect(sent, isEmpty);
  });
}
