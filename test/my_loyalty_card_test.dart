import 'package:flutter_test/flutter_test.dart';
import 'package:wuarikes_app/core/models.dart';

void main() {
  test('MyLoyaltyCard.fromJson parses latitude/longitude', () {
    final card = MyLoyaltyCard.fromJson({
      'placeId': 'place-1',
      'placeName': 'Wuarike Don José',
      'placeCoverImageUrl': null,
      'latitude': -12.046,
      'longitude': -77.042,
      'programType': 'stamps',
      'stamps': 8,
      'points': 0,
      'stampsToReward': 10,
      'stampsRemaining': 2,
      'level': 'PLATA',
      'rewardTitle': 'Postre gratis',
    });

    expect(card.latitude, -12.046);
    expect(card.longitude, -77.042);
  });

  test('MyLoyaltyCard.toJson round-trips through fromJson', () {
    final original = MyLoyaltyCard(
      placeId: 'place-1',
      placeName: 'Wuarike Don José',
      programType: 'stamps',
      stamps: 8,
      points: 0,
      stampsToReward: 10,
      stampsRemaining: 2,
      level: 'PLATA',
      rewardTitle: 'Postre gratis',
      latitude: -12.046,
      longitude: -77.042,
    );

    final roundTripped = MyLoyaltyCard.fromJson(original.toJson());

    expect(roundTripped.placeId, original.placeId);
    expect(roundTripped.latitude, original.latitude);
    expect(roundTripped.rewardReady, original.rewardReady);
  });
}
