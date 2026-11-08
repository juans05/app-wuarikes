import 'api_client.dart';
import 'models.dart' show Paginated;
import 'now_models.dart';

/// Llamadas de "Ahora" (huarique_backend, módulo `now`). Las rutas van sin
/// `/api`: ya viene en [ApiConfig.baseUrl].
extension NowApi on ApiClient {
  /// Publicaciones y promos dentro de la caja visible del mapa.
  Future<NowArea> getNowArea({
    required double minLat,
    required double minLng,
    required double maxLat,
    required double maxLng,
  }) async {
    final result = await get('/now', query: {
      'minLat': '$minLat',
      'minLng': '$minLng',
      'maxLat': '$maxLat',
      'maxLng': '$maxLng',
    });
    return NowArea.fromJson(result as Map<String, dynamic>);
  }

  Future<NowPost> getNowPost(String id) async =>
      NowPost.fromJson(await get('/now/posts/$id') as Map<String, dynamic>);

  /// Publica. Con [bytes] va como multipart (`file` + campos de texto); sin
  /// archivo (kind 'text') va como JSON, que el backend acepta igual.
  Future<NowPost> createNowPost({
    required String kind,
    String? text,
    required String visibility,
    required double latitude,
    required double longitude,
    List<int>? bytes,
    String? filename,
    String? mimeType,
  }) async {
    final trimmed = text?.trim();
    final result = bytes == null
        ? await post('/now/posts', {
            'kind': kind,
            if (trimmed != null && trimmed.isNotEmpty) 'text': trimmed,
            'visibility': visibility,
            'latitude': latitude,
            'longitude': longitude,
          })
        : await uploadMedia(
            '/now/posts',
            'file',
            bytes,
            filename ?? (kind == 'video' ? 'ahora.mp4' : 'ahora.jpg'),
            mimeType ?? (kind == 'video' ? 'video/mp4' : 'image/jpeg'),
            fields: {
              'kind': kind,
              if (trimmed != null && trimmed.isNotEmpty) 'text': trimmed,
              'visibility': visibility,
              'latitude': '$latitude',
              'longitude': '$longitude',
            },
          );
    return NowPost.fromJson(result as Map<String, dynamic>);
  }

  /// [type]: 'like' | 'dislike' | 'check'. El 'check' exige [lat]/[lng] y estar
  /// a 300 m o menos. Devuelve la publicación con los contadores nuevos.
  Future<NowPost> reactNow(String id, String type,
      {double? lat, double? lng}) async {
    final result = await put('/now/posts/$id/reaction', {
      'type': type,
      if (lat != null) 'latitude': lat,
      if (lng != null) 'longitude': lng,
    });
    return NowPost.fromJson(result as Map<String, dynamic>);
  }

  Future<NowPost> unreactNow(String id) async => NowPost.fromJson(
      await delete('/now/posts/$id/reaction') as Map<String, dynamic>);

  /// El backend acepta hasta 200 caracteres de motivo (si no, 400): se recorta.
  Future<void> reportNow(String id, String reason) async {
    final trimmed = reason.trim();
    await post('/now/posts/$id/report', {
      'reason': trimmed.length > 200 ? trimmed.substring(0, 200) : trimmed,
    });
  }

  /// [scope]: 'following' | 'nearby' | 'friends'. 'nearby' exige [lat]/[lng].
  Future<Paginated<NowPost>> getNowFeed(String scope,
      {double? lat, double? lng, int page = 1}) async {
    final result = await get('/now/feed', query: {
      'scope': scope,
      'page': '$page',
      if (lat != null) 'lat': '$lat',
      if (lng != null) 'lng': '$lng',
    });
    return _nowPage(result, page);
  }

  Future<Paginated<NowPost>> getMyNowPosts({int page = 1}) async =>
      _nowPage(await get('/now/mine', query: {'page': '$page'}), page);

  /// Mi lista de amigos de Ahora: `{id, fullName, avatarUrl}` por cada uno.
  Future<List<Map<String, dynamic>>> getFriends() async =>
      ((await get('/now/friends')) as List).cast<Map<String, dynamic>>();

  /// Solo se puede agregar a quien ya me sigue (si no, 400).
  Future<void> addFriend(String userId) async {
    await post('/now/friends/$userId');
  }

  Future<void> removeFriend(String userId) async {
    await delete('/now/friends/$userId');
  }
}

/// El backend responde `{data, total}` sin `page`: se completa con la pedida
/// para que [Paginated] no marque siempre la página 1.
Paginated<NowPost> _nowPage(dynamic result, int page) => Paginated.fromJson(
    {...(result as Map<String, dynamic>), 'page': page}, NowPost.fromJson);
