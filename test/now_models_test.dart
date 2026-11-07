import 'package:flutter_test/flutter_test.dart';
import 'package:wuarikes_app/core/now_models.dart';

Map<String, dynamic> postJson({Map<String, dynamic> extra = const {}}) => {
      'id': 'post-1',
      'kind': 'photo',
      'text': 'Cola larga en el local',
      'mediaUrl': 'https://img.test/a.jpg',
      'latitude': -12.046,
      'longitude': -77.042,
      'visibility': 'all',
      'likes': 3,
      'dislikes': 1,
      'checks': 2,
      'expiresAt': '2026-11-08T12:00:00.000Z',
      'createdAt': '2026-11-07T12:00:00.000Z',
      'author': {
        'id': 'user-1',
        'fullName': 'Ana Quispe',
        'avatarUrl': 'https://img.test/ana.jpg',
      },
      'myReaction': 'like',
      ...extra,
    };

void main() {
  test('NowPost.fromJson lee autor, contadores y expiresAt', () {
    final p = NowPost.fromJson(postJson());

    expect(p.id, 'post-1');
    expect(p.kind, 'photo');
    expect(p.text, 'Cola larga en el local');
    expect(p.mediaUrl, 'https://img.test/a.jpg');
    expect(p.latitude, -12.046);
    expect(p.longitude, -77.042);
    expect(p.visibility, 'all');
    expect(p.likes, 3);
    expect(p.dislikes, 1);
    expect(p.checks, 2);
    expect(p.expiresAt, DateTime.utc(2026, 11, 8, 12));
    expect(p.createdAt, DateTime.utc(2026, 11, 7, 12));
    expect(p.authorId, 'user-1');
    expect(p.authorName, 'Ana Quispe');
    expect(p.authorAvatar, 'https://img.test/ana.jpg');
    expect(p.myReaction, 'like');
  });

  test('NowPost.fromJson tolera text, mediaUrl, avatar y myReaction nulos', () {
    final p = NowPost.fromJson(postJson(extra: {
      'kind': 'text',
      'text': null,
      'mediaUrl': null,
      'myReaction': null,
      'author': {'id': 'user-1', 'fullName': 'Ana Quispe', 'avatarUrl': null},
    }));

    expect(p.text, isNull);
    expect(p.mediaUrl, isNull);
    expect(p.myReaction, isNull);
    expect(p.authorAvatar, isNull);
  });

  test('NowPost.fromJson acepta números como texto', () {
    final p = NowPost.fromJson(postJson(extra: {
      'latitude': '-12.046',
      'longitude': '-77.042',
      'likes': '3',
      'dislikes': '1',
      'checks': '2',
    }));

    expect(p.latitude, -12.046);
    expect(p.longitude, -77.042);
    expect(p.likes, 3);
    expect(p.dislikes, 1);
    expect(p.checks, 2);
  });

  test('timeLeft devuelve Duration.zero si ya venció', () {
    final p = NowPost.fromJson(postJson());

    expect(p.timeLeft(DateTime.utc(2026, 11, 8, 13)), Duration.zero);
    expect(p.timeLeft(DateTime.utc(2026, 11, 8, 12)), Duration.zero);
    expect(p.timeLeft(DateTime.utc(2026, 11, 8, 10)), const Duration(hours: 2));
  });

  test('NowPromo.fromJson lee place.latitude/longitude', () {
    final promo = NowPromo.fromJson({
      'id': 'promo-1',
      'title': '2x1 en ceviche',
      'description': null,
      'imageUrl': null,
      'discountType': 'percentage',
      'discountValue': 50,
      'visibleUntil': '2026-11-08T03:00:00.000Z',
      'place': {
        'id': 'place-1',
        'name': 'Cevichería Don José',
        'latitude': '-12.1',
        'longitude': -77.03,
        'coverImageUrl': null,
      },
    });

    expect(promo.id, 'promo-1');
    expect(promo.title, '2x1 en ceviche');
    expect(promo.description, isNull);
    expect(promo.imageUrl, isNull);
    expect(promo.visibleUntil, DateTime.utc(2026, 11, 8, 3));
    expect(promo.placeId, 'place-1');
    expect(promo.placeName, 'Cevichería Don José');
    expect(promo.latitude, -12.1);
    expect(promo.longitude, -77.03);
  });

  test('NowArea.fromJson separa publicaciones y promos', () {
    final area = NowArea.fromJson({
      'posts': [postJson()],
      'promos': <dynamic>[],
    });

    expect(area.posts.single.id, 'post-1');
    expect(area.promos, isEmpty);
  });
}
