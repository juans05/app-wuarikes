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

  test('NowPost.fromJson: hidden solo es true si el backend lo manda true', () {
    expect(NowPost.fromJson(postJson()).hidden, isFalse);
    expect(NowPost.fromJson(postJson(extra: {'hidden': false})).hidden, isFalse);
    expect(NowPost.fromJson(postJson(extra: {'hidden': true})).hidden, isTrue);
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

  test('canConfirm es true hasta 300 m y false desde 301', () {
    expect(canConfirm(0), isTrue);
    expect(canConfirm(299.9), isTrue);
    expect(canConfirm(300), isTrue);
    expect(canConfirm(300.5), isFalse);
    expect(canConfirm(301), isFalse);
  });

  test('timeLeftLabel: horas, minutos si falta menos de 1 h, y vencida', () {
    expect(timeLeftLabel(const Duration(hours: 19, minutes: 40)), 'quedan 19 h');
    expect(timeLeftLabel(const Duration(hours: 1)), 'quedan 1 h');
    expect(timeLeftLabel(const Duration(minutes: 59, seconds: 30)),
        'quedan 59 min');
    expect(timeLeftLabel(const Duration(seconds: 20)), 'quedan 1 min');
    expect(timeLeftLabel(Duration.zero), 'venció');
  });

  test('promoEndsLabel: hora si termina hoy, fecha si es otro día', () {
    final now = DateTime(2026, 11, 7, 10);
    expect(promoEndsLabel(DateTime(2026, 11, 7, 23, 59), now),
        'termina 23:59');
    expect(promoEndsLabel(DateTime(2026, 11, 8, 3, 5), now), 'termina 08/11');
  });

  test('nowMimeType usa el tipo real del archivo y cae a la extensión', () {
    expect(nowMimeType('a.png', video: false), 'image/png');
    expect(nowMimeType('a.JPG', video: false), 'image/jpeg');
    expect(nowMimeType('a.webp', video: false), 'image/webp');
    expect(nowMimeType('clip.mov', video: true), 'video/quicktime');
    expect(nowMimeType('clip.mp4', video: true), 'video/mp4');
    expect(nowMimeType('sin_extension', video: false), 'image/jpeg');
    expect(nowMimeType('sin_extension', video: true), 'video/mp4');
    expect(nowMimeType('a.png', video: false, declared: 'image/webp'),
        'image/webp');
  });
}
