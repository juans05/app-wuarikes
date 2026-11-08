import 'package:flutter_test/flutter_test.dart';
import 'package:wuarikes_app/core/geofence_callback_handler.dart';
import 'package:wuarikes_app/core/geofence_sync_service.dart';

void main() {
  final now = DateTime(2026, 11, 2, 12);

  test('shouldNotify: reward ready notifies, points programs do not', () {
    expect(shouldNotify({'stampsRemaining': 0}, null, now, 12), isTrue);
    expect(shouldNotify({'stampsRemaining': 3}, null, now, 12), isTrue);
    expect(shouldNotify({'stampsRemaining': null}, null, now, 12), isFalse);
  });

  test('shouldNotify respects the cooldown', () {
    final card = {'stampsRemaining': 2};
    expect(shouldNotify(card, now.subtract(const Duration(hours: 1)), now, 12), isFalse);
    expect(shouldNotify(card, now.subtract(const Duration(hours: 12)), now, 12), isTrue);
  });

  test('proximityMessage says what is missing, or that the reward is ready', () {
    final ready = proximityMessage({'placeName': 'Don Pepe', 'stampsRemaining': 0, 'rewardTitle': 'Ceviche gratis'});
    expect(ready.title, '¡Tienes para canjear en Don Pepe!');
    expect(ready.body, 'Muestra tu tarjeta y canjea: Ceviche gratis');
    final one = proximityMessage({'placeName': 'Don Pepe', 'stampsRemaining': 1});
    expect(one.body, 'Te falta 1 sello para tu premio');
    final many = proximityMessage({'placeName': 'Don Pepe', 'stampsRemaining': 4, 'rewardTitle': 'Postre'});
    expect(many.title, 'Estás cerca de Don Pepe');
    expect(many.body, 'Te faltan 4 sellos para Postre');
  });
}
