import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

/// Base URL of the Wuarikes backend (huarique_backend).
/// Override at build/run time with:
///   flutter run --dart-define=API_URL=https://tu-dominio.com/api
class ApiConfig {
  static const String baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://backendwarike-production.up.railway.app/api',
  );
}

class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);
  @override
  String toString() => message;
}

class ApiClient {
  final http.Client? client;
  ApiClient({this.client});
  Future<dynamic> get(String path, {Map<String, String>? query}) =>
      _request('GET', path, query: query);
  Future<dynamic> post(String path, [Map<String, dynamic>? body]) =>
      _request('POST', path, body: body);
  Future<dynamic> patch(String path, Map<String, dynamic> body) =>
      _request('PATCH', path, body: body);
  Future<dynamic> delete(String path) => _request('DELETE', path);

  Future<Map<String, dynamic>> uploadMedia(String path, String field,
      List<int> bytes, String filename, String mimeType,
      {bool retry = true}) async {
    final request =
        http.MultipartRequest('POST', Uri.parse('${ApiConfig.baseUrl}$path'));
    final token = await accessToken;
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    request.files.add(http.MultipartFile.fromBytes(field, bytes,
        filename: filename, contentType: MediaType.parse(mimeType)));
    final response = await http.Response.fromStream(await request.send());
    if (response.statusCode == 401 && retry && await _tryRefresh()) {
      return uploadMedia(path, field, bytes, filename, mimeType, retry: false);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode,
          'No se pudo subir el archivo (${response.statusCode}).');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static const _accessKey = 'wuarikes_access_token';
  static const _refreshKey = 'wuarikes_refresh_token';

  Future<String?> get accessToken async =>
      (await SharedPreferences.getInstance()).getString(_accessKey);
  Future<String?> get refreshToken async =>
      (await SharedPreferences.getInstance()).getString(_refreshKey);

  Future<void> setTokens(String access, String refresh) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accessKey, access);
    await prefs.setString(_refreshKey, refresh);
  }

  Future<void> clearTokens() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessKey);
    await prefs.remove(_refreshKey);
  }

  Future<bool> _tryRefresh() async {
    final refresh = await refreshToken;
    if (refresh == null) return false;
    final res = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/auth/refresh'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'refreshToken': refresh}),
    );
    if (res.statusCode != 200) return false;
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    await setTokens(data['accessToken'], data['refreshToken']);
    return true;
  }

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    bool retry = true,
  }) async {
    final token = await accessToken;
    var uri = Uri.parse('${ApiConfig.baseUrl}$path');
    if (query != null) {
      uri = uri.replace(queryParameters: {...uri.queryParameters, ...query});
    }
    final headers = {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };

    late http.Response res;
    switch (method) {
      case 'GET':
        res = await (client?.get(uri, headers: headers) ??
            http.get(uri, headers: headers));
        break;
      case 'POST':
        res = await (client?.post(uri,
                headers: headers,
                body: body != null ? jsonEncode(body) : null) ??
            http.post(uri,
                headers: headers,
                body: body != null ? jsonEncode(body) : null));
        break;
      case 'DELETE':
        res = await (client?.delete(uri, headers: headers) ??
            http.delete(uri, headers: headers));
        break;
      case 'PATCH':
        res = await (client?.patch(uri,
                headers: headers,
                body: body != null ? jsonEncode(body) : null) ??
            http.patch(uri,
                headers: headers,
                body: body != null ? jsonEncode(body) : null));
        break;
      default:
        throw ApiException(0, 'Método no soportado: $method');
    }

    if (res.statusCode == 401 && retry) {
      final refreshed = await _tryRefresh();
      if (refreshed)
        return _request(method, path, body: body, query: query, retry: false);
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      String message = 'Error ${res.statusCode}';
      try {
        final decoded = jsonDecode(res.body);
        final m = decoded['message'];
        if (m is List) {
          message = m.join(', ');
        } else if (m is String) {
          message = m;
        }
      } catch (_) {
        /* ignore */
      }
      throw ApiException(res.statusCode, message);
    }

    if (res.body.isEmpty) return null;
    return jsonDecode(res.body);
  }

  // ---------- Auth ----------
  Future<Map<String, dynamic>> register(
      String email, String password, String fullName) async {
    final result = await _request('POST', '/auth/register', body: {
      'email': email,
      'password': password,
      'fullName': fullName,
    });
    return result as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    final result = await _request('POST', '/auth/login', body: {
      'email': email,
      'password': password,
    });
    return result as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> verifyEmail(String email, String code) async {
    final result = await _request('POST', '/auth/verify-email', body: {
      'email': email,
      'code': code,
    });
    return result as Map<String, dynamic>;
  }

  Future<void> resendCode(String email) async {
    await _request('POST', '/auth/resend-code', body: {'email': email});
  }

  Future<void> forgotPassword(String email) async {
    await _request('POST', '/auth/forgot-password', body: {'email': email});
  }

  Future<void> resetPassword(String email, String code, String password) async {
    await _request('POST', '/auth/reset-password',
        body: {'email': email, 'code': code, 'password': password});
  }

  Future<Map<String, dynamic>> socialLogin({
    required String provider,
    required String token,
    required String email,
    String? name,
    String? photoUrl,
  }) async {
    final result = await _request('POST', '/auth/social-login', body: {
      'provider': provider,
      'token': token,
      'email': email,
      if (name != null) 'name': name,
      if (photoUrl != null) 'photoUrl': photoUrl,
    });
    return result as Map<String, dynamic>;
  }

  Future<void> logout() async {
    try {
      await _request('POST', '/auth/logout');
    } catch (_) {
      /* ignore */
    }
  }

  // ---------- Places ----------
  Future<Paginated<Place>> getPlaces({
    String? category,
    String? district,
    String? search,
    double? latitude,
    double? longitude,
    double? radius,
    num? priceMin,
    num? priceMax,
    double? minRating,
    List<String>? amenities,
    bool? openNow,
    int page = 1,
  }) async {
    final query = <String, String>{'page': '$page'};
    if (district != null && district.isNotEmpty) query['district'] = district;
    if (category != null) query['category'] = category;
    if (search != null && search.isNotEmpty) query['search'] = search;
    if (latitude != null) query['latitude'] = '$latitude';
    if (longitude != null) query['longitude'] = '$longitude';
    if (radius != null) query['radius'] = '$radius';
    if (priceMin != null) query['priceMin'] = '$priceMin';
    if (priceMax != null) query['priceMax'] = '$priceMax';
    if (minRating != null) query['minRating'] = '$minRating';
    if (amenities != null && amenities.isNotEmpty)
      query['amenities'] = amenities.join(',');
    if (openNow == true) query['openNow'] = 'true';
    final result = await _request('GET', '/places', query: query);
    return Paginated.fromJson(result as Map<String, dynamic>, Place.fromJson);
  }

  Future<List<Category>> getCategories() async {
    final result = await _request('GET', '/places/categories');
    return (result as List).map((e) => Category.fromJson(e)).toList();
  }

  Future<List<Amenity>> getAmenities() async {
    final result = await _request('GET', '/places/amenities');
    return (result as List)
        .map((e) => Amenity.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ---------- Ubigeo (Peru departamento / provincia / distrito) ----------
  Future<List<String>> getDepartments() async {
    final result = await _request('GET', '/ubigeo/departments');
    return (result as List).map((e) => e.toString()).toList();
  }

  Future<List<String>> getProvinces(String department) async {
    final result = await _request('GET', '/ubigeo/provinces',
        query: {'department': department});
    return (result as List).map((e) => e.toString()).toList();
  }

  Future<List<String>> getDistrictsByProvince(
      String department, String province) async {
    final result = await _request('GET', '/ubigeo/districts',
        query: {'department': department, 'province': province});
    return (result as List)
        .map((e) => (e as Map<String, dynamic>)['district'].toString())
        .toList();
  }

  Future<Place> getPlace(String id) async {
    final result = await _request('GET', '/places/$id');
    return Place.fromJson(result as Map<String, dynamic>);
  }

  Future<bool> isFavorite(String id) async {
    final result = await _request('GET', '/places/$id/favorite');
    return (result as Map<String, dynamic>)['isSaved'] as bool? ?? false;
  }

  Future<void> addFavorite(String id) async {
    await _request('POST', '/places/$id/favorite');
  }

  Future<void> removeFavorite(String id) async {
    await _request('DELETE', '/places/$id/favorite');
  }

  // ---------- Checkins ----------
  Future<CheckinItem> createCheckin({
    required String placeId,
    int? rating,
    String? comment,
    String? photoUrl,
    double? latitude,
    double? longitude,
    String? dishName,
    num? dishPrice,
  }) async {
    final result = await _request('POST', '/checkins', body: {
      'placeId': placeId,
      if (rating != null) 'rating': rating,
      if (comment != null && comment.isNotEmpty) 'comment': comment,
      if (photoUrl != null) 'photoUrl': photoUrl,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (dishName != null && dishName.isNotEmpty) 'dishName': dishName,
      if (dishPrice != null) 'dishPrice': dishPrice,
    });
    return CheckinItem.fromJson(result as Map<String, dynamic>);
  }

  Future<Paginated<CheckinItem>> getFeed(
      {String? placeId,
      int size = 20,
      int page = 1,
      bool following = false,
      String sort = 'recent',
      bool hasPhotos = false}) async {
    final query = <String, String>{
      'size': '$size',
      'page': '$page',
      'sort': sort,
      if (hasPhotos) 'hasPhotos': 'true'
    };
    if (placeId != null) query['placeId'] = placeId;
    final result = await _request(
        'GET', following ? '/checkins/feed/following' : '/checkins/feed',
        query: query);
    return Paginated.fromJson(
        result as Map<String, dynamic>, CheckinItem.fromJson);
  }

  Future<void> likeCheckin(String id) async {
    await _request('POST', '/checkins/$id/like');
  }

  Future<void> unlikeCheckin(String id) async {
    await _request('DELETE', '/checkins/$id/like');
  }

  // ---------- Users ----------
  Future<AppUser> getMyProfile() async {
    final result = await _request('GET', '/users/me/profile');
    return AppUser.fromJson(result as Map<String, dynamic>);
  }

  Future<void> updateProfile({String? fullName, String? bio}) async {
    await _request('PATCH', '/users/me/profile', body: {
      if (fullName != null) 'fullName': fullName,
      if (bio != null) 'bio': bio,
    });
  }

  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    final result = await _request('GET', '/users/search', query: {'q': query});
    return (result as List).cast<Map<String, dynamic>>();
  }

  Future<Paginated<CheckinItem>> getMyCheckins(
      {int page = 1, int limit = 20}) async {
    final result = await _request('GET', '/users/me/checkins',
        query: {'page': '$page', 'limit': '$limit'});
    return Paginated.fromJson(
        result as Map<String, dynamic>, CheckinItem.fromJson);
  }

  Future<List<Place>> getMyFavorites() async {
    final result =
        await _request('GET', '/users/me/favorites') as Map<String, dynamic>;
    return (result['data'] as List)
        .map((e) => Place.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ---------- Gamification ----------
  Future<GamificationStats> getMyStats() async {
    final result = await _request('GET', '/gamification/my-stats');
    return GamificationStats.fromJson(result as Map<String, dynamic>);
  }

  Future<List<AppBadge>> getBadges() async {
    final result = await _request('GET', '/gamification/badges');
    return (result as List)
        .map((e) => AppBadge.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ---------- Loyalty (fidelización) ----------
  /// Null when the restaurant has no loyalty program configured.
  Future<LoyaltyProgram?> getLoyaltyProgram(String placeId) async {
    final result = await _request('GET', '/public/loyalty/$placeId/program');
    return result == null
        ? null
        : LoyaltyProgram.fromJson(result as Map<String, dynamic>);
  }

  /// Null when the restaurant has no loyalty program at all (the endpoint
  /// 404s in that case); [LoyaltyCard.card] is null when the program exists
  /// but this phone hasn't earned a card yet.
  Future<LoyaltyCard?> getLoyaltyCard(String placeId, String phone) async {
    try {
      final result = await _request('GET', '/public/loyalty/$placeId/card/$phone');
      return LoyaltyCard.fromJson(result as Map<String, dynamic>);
    } on ApiException catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  /// All of the logged-in user's loyalty cards, across every restaurant.
  Future<List<MyLoyaltyCard>> getMyLoyaltyCards() async {
    final result = await _request('GET', '/loyalty/my-cards') as List;
    return result
        .map((e) => MyLoyaltyCard.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ---------- Place submissions ----------
  Future<void> submitPlace({
    required String name,
    String? description,
    required String categoryId,
    required String district,
    String? address,
    required double latitude,
    required double longitude,
    String? phone,
    String? coverImageUrl,
    List<String>? photoUrls,
    String? openHoursText,
    List<String>? menuImageUrls,
    String? videoUrl,
  }) async {
    await _request('POST', '/places/submit', body: {
      'name': name,
      if (description != null && description.isNotEmpty)
        'description': description,
      'categoryId': categoryId,
      'district': district,
      if (address != null && address.isNotEmpty) 'address': address,
      'latitude': latitude,
      'longitude': longitude,
      if (phone != null && phone.isNotEmpty) 'phone': phone,
      if (coverImageUrl != null) 'coverImageUrl': coverImageUrl,
      if (photoUrls != null && photoUrls.isNotEmpty) 'photoUrls': photoUrls,
      if (openHoursText != null && openHoursText.isNotEmpty)
        'openHoursText': openHoursText,
      if (menuImageUrls != null && menuImageUrls.isNotEmpty)
        'menuImageUrls': menuImageUrls,
      if (videoUrl != null) 'videoUrl': videoUrl,
    });
  }

  // ---------- Upload ----------
  Future<String> uploadImage(List<int> bytes, String filename,
      {String? mimeType}) async {
    final token = await accessToken;
    final uri = Uri.parse('${ApiConfig.baseUrl}/upload/image');
    final request = http.MultipartRequest('POST', uri);
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    request.files.add(http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: filename,
      contentType: MediaType.parse(mimeType ?? _mimeTypeFromFilename(filename)),
    ));
    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      String message = 'No se pudo subir la imagen';
      try {
        final decoded = jsonDecode(res.body);
        final m = decoded['message'];
        if (m is String) message = m;
      } catch (_) {
        /* ignore */
      }
      throw ApiException(res.statusCode, message);
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data['url'] as String;
  }

  Future<String> uploadVideo(List<int> bytes, String filename,
      {String? mimeType}) async {
    final token = await accessToken;
    final uri = Uri.parse('${ApiConfig.baseUrl}/upload/video');
    final request = http.MultipartRequest('POST', uri);
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    request.files.add(http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: filename,
      contentType: MediaType.parse(mimeType ?? 'video/mp4'),
    ));
    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      String message = 'No se pudo subir el video';
      try {
        final decoded = jsonDecode(res.body);
        final m = decoded['message'];
        if (m is String) message = m;
      } catch (_) {
        /* ignore */
      }
      throw ApiException(res.statusCode, message);
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data['url'] as String;
  }

  String _mimeTypeFromFilename(String filename) {
    final ext = filename.toLowerCase().split('.').last;
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }
}
