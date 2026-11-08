// Modelos de "Ahora": publicaciones de corta vida en el mapa y promos de locales.
// Los nombres salen de lo que envía huarique_backend (src/modules/now/now.service.ts).

/// Igual que `_parseNum` de models.dart (privado): lat/lng y contadores pueden
/// llegar como número o como texto.
num? _num(dynamic v) => v is num ? v : (v is String ? num.tryParse(v) : null);

class NowPost {
  final String id;

  /// 'photo' | 'video' | 'text'
  final String kind;
  final String? text;
  final String? mediaUrl;
  final double latitude;
  final double longitude;

  /// 'all' | 'followers' | 'friends'
  final String visibility;
  final int likes;
  final int dislikes;
  final int checks;
  final DateTime expiresAt;
  final DateTime createdAt;
  final String authorId;
  final String authorName;
  final String? authorAvatar;

  /// 'like' | 'dislike' | 'check' | null (sin reacción o sin sesión)
  final String? myReaction;

  NowPost({
    required this.id,
    required this.kind,
    this.text,
    this.mediaUrl,
    required this.latitude,
    required this.longitude,
    required this.visibility,
    required this.likes,
    required this.dislikes,
    required this.checks,
    required this.expiresAt,
    required this.createdAt,
    required this.authorId,
    required this.authorName,
    this.authorAvatar,
    this.myReaction,
  });

  factory NowPost.fromJson(Map<String, dynamic> json) {
    final author = json['author'] as Map<String, dynamic>? ?? const {};
    return NowPost(
      id: json['id'] as String,
      kind: json['kind'] as String? ?? 'text',
      text: json['text'] as String?,
      mediaUrl: json['mediaUrl'] as String?,
      latitude: (_num(json['latitude']) ?? 0).toDouble(),
      longitude: (_num(json['longitude']) ?? 0).toDouble(),
      visibility: json['visibility'] as String? ?? 'all',
      likes: (_num(json['likes']) ?? 0).toInt(),
      dislikes: (_num(json['dislikes']) ?? 0).toInt(),
      checks: (_num(json['checks']) ?? 0).toInt(),
      expiresAt: DateTime.parse(json['expiresAt'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      authorId: author['id'] as String? ?? '',
      authorName: author['fullName'] as String? ?? '',
      authorAvatar: author['avatarUrl'] as String?,
      myReaction: json['myReaction'] as String?,
    );
  }

  /// Lo que le queda de vida a [now]; nunca negativo.
  Duration timeLeft(DateTime now) {
    final left = expiresAt.difference(now);
    return left.isNegative ? Duration.zero : left;
  }
}

class NowPromo {
  final String id;
  final String title;
  final String? description;
  final String? imageUrl;
  final DateTime visibleUntil;
  final String placeId;
  final String? placeName;
  final double latitude;
  final double longitude;

  NowPromo({
    required this.id,
    required this.title,
    this.description,
    this.imageUrl,
    required this.visibleUntil,
    required this.placeId,
    this.placeName,
    required this.latitude,
    required this.longitude,
  });

  factory NowPromo.fromJson(Map<String, dynamic> json) {
    final place = json['place'] as Map<String, dynamic>? ?? const {};
    return NowPromo(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      description: json['description'] as String?,
      imageUrl: json['imageUrl'] as String?,
      visibleUntil: DateTime.parse(json['visibleUntil'] as String),
      placeId: place['id'] as String? ?? '',
      placeName: place['name'] as String?,
      latitude: (_num(place['latitude']) ?? 0).toDouble(),
      longitude: (_num(place['longitude']) ?? 0).toDouble(),
    );
  }
}

class NowArea {
  final List<NowPost> posts;
  final List<NowPromo> promos;

  NowArea({required this.posts, required this.promos});

  factory NowArea.fromJson(Map<String, dynamic> json) => NowArea(
        posts: (json['posts'] as List? ?? [])
            .map((e) => NowPost.fromJson(e as Map<String, dynamic>))
            .toList(),
        promos: (json['promos'] as List? ?? [])
            .map((e) => NowPromo.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// "Cerca" de Ahora: radio en metros para dar ✅ (el backend aplica el mismo).
const nowRadiusMeters = 300;

/// ¿Se puede dar ✅ estando a [distanceMeters] de la publicación?
bool canConfirm(double distanceMeters) => distanceMeters <= nowRadiusMeters;

/// "quedan 19 h"; bajo 1 h, "quedan 25 min"; sin vida, "venció".
String timeLeftLabel(Duration left) {
  if (left <= Duration.zero) return 'venció';
  if (left.inHours >= 1) return 'quedan ${left.inHours} h';
  return 'quedan ${left.inMinutes < 1 ? 1 : left.inMinutes} min';
}

/// "termina 23:59" si acaba hoy; si no, "termina 08/11".
String promoEndsLabel(DateTime until, DateTime now) {
  String two(int n) => n.toString().padLeft(2, '0');
  final local = until.toLocal();
  final today = local.year == now.year &&
      local.month == now.month &&
      local.day == now.day;
  return today
      ? 'termina ${two(local.hour)}:${two(local.minute)}'
      : 'termina ${two(local.day)}/${two(local.month)}';
}

/// Tipo MIME para subir [filename]: el [declared] por el selector si lo hay
/// (en Android casi nunca viene) y, si no, el de la extensión. El backend
/// acepta jpeg/png/webp y mp4/quicktime según el tipo que declare el archivo.
String nowMimeType(String filename, {required bool video, String? declared}) {
  if (declared != null && declared.isNotEmpty) return declared;
  final dot = filename.lastIndexOf('.');
  final ext = dot < 0 ? '' : filename.substring(dot + 1).toLowerCase();
  return switch (ext) {
    'png' => 'image/png',
    'webp' => 'image/webp',
    'jpg' || 'jpeg' => 'image/jpeg',
    'mov' => 'video/quicktime',
    'mp4' => 'video/mp4',
    _ => video ? 'video/mp4' : 'image/jpeg',
  };
}
