import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wuarikes_app/core/api_client.dart';
import 'package:wuarikes_app/core/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Favorites decode the same flat places returned to the web', () async {
    final api = ApiClient(client: MockClient((request) async {
      expect(request.url.path, '/api/users/me/favorites');
      return http.Response(
          jsonEncode({
            'data': [
              {
                'id': 'p1',
                'name': 'Cevichería',
                'rating': '4.8',
                'latitude': '-12.1',
                'district': {'name': 'Lima'},
                'amenities': [
                  {'id': 'a', 'name': 'Wifi'},
                  'Terraza'
                ]
              }
            ]
          }),
          200);
    }));
    final result = await api.getMyFavorites();
    expect(result.single.id, 'p1');
    expect(result.single.rating, 4.8);
    expect(result.single.district!.district, 'Lima');
    expect(result.single.amenities, ['Wifi', 'Terraza']);
  });

  test('History and feed support both pagination response shapes', () {
    final flat = Paginated.fromJson(
        {'data': [], 'total': 45, 'page': 2, 'limit': 20},
        CheckinItem.fromJson);
    final nested = Paginated.fromJson({
      'data': [],
      'meta': {'total': 45, 'page': 2, 'size': 20}
    }, CheckinItem.fromJson);
    expect(flat.totalPages, 3);
    expect(nested.totalPages, 3);
    expect(flat.page, 2);
    final history = CheckinItem.fromJson({
      'id': 'c1',
      'place': {
        'id': 'p1',
        'name': 'Local',
        'photoUrl': 'https://example.com/photo.jpg'
      }
    });
    expect(history.placeId, 'p1');
    expect(history.place!.coverImageUrl, 'https://example.com/photo.jpg');
  });

  test('Check-in sends location, dish and price; following uses its endpoint',
      () async {
    final api = ApiClient(client: MockClient((request) async {
      if (request.method == 'POST') {
        final body = jsonDecode(request.body);
        expect(body['latitude'], -12.1);
        expect(body['longitude'], -77.1);
        expect(body['dishName'], 'Ceviche');
        expect(body['dishPrice'], 28.5);
        return http.Response('{"id":"c1"}', 201);
      }
      expect(request.url.path, '/api/checkins/feed/following');
      expect(request.url.queryParameters['page'], '2');
      return http.Response(
          '{"data":[],"meta":{"total":0,"page":2,"totalPages":2}}', 200);
    }));
    await api.createCheckin(
        placeId: 'p1',
        latitude: -12.1,
        longitude: -77.1,
        dishName: 'Ceviche',
        dishPrice: 28.5);
    await api.getFeed(following: true, page: 2);
  });

  test(
      'Likes accept a successful response without a count and propagate failures',
      () async {
    final api = ApiClient(
        client: MockClient((request) async => request.method == 'POST'
            ? http.Response('{"message":"ok"}', 200)
            : http.Response('{"message":"No permitido"}', 403)));
    await api.likeCheckin('c1');
    await expectLater(api.unlikeCheckin('c1'),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 403)));
  });
}
