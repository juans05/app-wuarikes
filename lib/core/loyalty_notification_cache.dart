import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class LoyaltyNotificationCache {
  static final LoyaltyNotificationCache _instance =
      LoyaltyNotificationCache._internal();

  LoyaltyNotificationCache._internal();

  factory LoyaltyNotificationCache() {
    return _instance;
  }

  Future<Map<String, dynamic>?> getCard(String placeId) async {
    final prefs = await SharedPreferences.getInstance();
    final cardJson = prefs.getString('loyalty_card_$placeId');
    if (cardJson == null) return null;
    return jsonDecode(cardJson) as Map<String, dynamic>;
  }

  Future<void> putCard(
    String placeId,
    Map<String, dynamic> cardData,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('loyalty_card_$placeId', jsonEncode(cardData));
  }

  Future<void> updateNotifiedAt(String placeId, DateTime time) async {
    final card = await getCard(placeId);
    if (card == null) return;
    card['notifiedAt'] = time.toIso8601String();
    await putCard(placeId, card);
  }
}
