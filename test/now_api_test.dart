import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wuarikes_app/core/api_client.dart';
import 'package:wuarikes_app/core/now_api.dart';

Map<String, dynamic> _post({String? myReaction}) => {
      'id': 'post-1',
      'kind': 'text',
      'text': 'Hola',
      'mediaUrl': null,
      'latitude': -12.046,
      'longitude': -77.042,
      'visibility': 'all',
      'likes': 1,
      'dislikes': 0,
      'checks': 0,
      'expiresAt': '2026-11-08T12:00:00.000Z',
      'createdAt': '2026-11-07T12:00:00.000Z',
      'author': {'id': 'u1', 'fullName': 'Ana', 'avatarUrl': null},
      'myReaction': myReaction,
    };

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('getNowFeed manda scope/page/lat/lng y conserva la página pedida', () async {
    late http.Request seen;
    final api = ApiClient(
        client: MockClient((req) async {
      seen = req;
      return http.Response(
          jsonEncode({'data': [_post()], 'total': 45}), 200);
    }));

    final page = await api.getNowFeed('nearby', lat: -12.0, lng: -77.0, page: 2);

    expect(seen.method, 'GET');
    expect(seen.url.path, '/api/now/feed');
    expect(seen.url.queryParameters,
        {'scope': 'nearby', 'page': '2', 'lat': '-12.0', 'lng': '-77.0'});
    expect(page.data.single.id, 'post-1');
    expect(page.total, 45);
    expect(page.page, 2);
    expect(page.totalPages, 3); // 45 / 20 por página
  });

  test('reactNow usa PUT /reaction y devuelve la publicación', () async {
    late http.Request seen;
    final api = ApiClient(
        client: MockClient((req) async {
      seen = req;
      return http.Response(jsonEncode(_post(myReaction: 'check')), 200);
    }));

    final p = await api.reactNow('post-1', 'check', lat: -12.0, lng: -77.0);

    expect(seen.method, 'PUT');
    expect(seen.url.path, '/api/now/posts/post-1/reaction');
    expect(jsonDecode(seen.body),
        {'type': 'check', 'latitude': -12.0, 'longitude': -77.0});
    expect(p.myReaction, 'check');
  });

  test('createNowPost de texto va como JSON sin archivo', () async {
    late http.Request seen;
    final api = ApiClient(
        client: MockClient((req) async {
      seen = req;
      return http.Response(jsonEncode(_post()), 201);
    }));

    final p = await api.createNowPost(
        kind: 'text',
        text: ' Hola ',
        visibility: 'friends',
        latitude: -12.046,
        longitude: -77.042);

    expect(seen.method, 'POST');
    expect(seen.url.path, '/api/now/posts');
    expect(jsonDecode(seen.body), {
      'kind': 'text',
      'text': 'Hola',
      'visibility': 'friends',
      'latitude': -12.046,
      'longitude': -77.042,
    });
    expect(p.id, 'post-1');
  });
}
