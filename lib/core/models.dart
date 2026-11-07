/// Postgres NUMERIC columns (lat/lng, rating, prices) come back from the
/// API as strings, not JSON numbers — parse either.
num? _parseNum(dynamic v) =>
    v is num ? v : (v is String ? num.tryParse(v) : null);

class Category {
  final String id;
  final String name;
  final String slug;
  final String? icon;

  Category(
      {required this.id, required this.name, required this.slug, this.icon});

  factory Category.fromJson(Map<String, dynamic> json) => Category(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        slug: json['slug'] as String? ?? '',
        icon: json['icon'] as String?,
      );
}

class Amenity {
  final String id;
  final String name;
  final String slug;
  final String? iconUrl;

  Amenity(
      {required this.id, required this.name, required this.slug, this.iconUrl});

  factory Amenity.fromJson(Map<String, dynamic> json) => Amenity(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        slug: json['slug'] as String? ?? '',
        iconUrl: json['iconUrl'] as String?,
      );
}

class District {
  final String? department;
  final String? province;
  final String? district;

  District({this.department, this.province, this.district});

  factory District.fromJson(Map<String, dynamic> json) => District(
        department: json['department'] as String?,
        province: json['province'] as String?,
        district: (json['district'] ?? json['name']) as String?,
      );
}

class Dish {
  final String id;
  final String name;
  final String? description;
  final num? price;
  final String? imageUrl;

  Dish(
      {required this.id,
      required this.name,
      this.description,
      this.price,
      this.imageUrl});

  factory Dish.fromJson(Map<String, dynamic> json) => Dish(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        description: json['description'] as String?,
        price: _parseNum(json['price']),
        imageUrl: json['imageUrl'] as String?,
      );
}

class Place {
  final Map<String, dynamic> details;
  final String id;
  final String name;
  final String? description;
  final Category? category;
  final District? district;
  final String? address;
  final double? latitude;
  final double? longitude;
  final String? phone;
  final String? coverImageUrl;
  final bool isVerified;
  final double rating;
  final int totalReviews;
  final num? priceMin;
  final num? priceMax;
  final String? openHoursText;
  final List<String> amenities;
  final List<Dish> dishes;
  final double? googleRating;
  final int googleTotalReviews;
  final List<GoogleReview> googleReviews;
  final bool hasActiveBenefit;

  Place({
    this.details = const {},
    required this.id,
    required this.name,
    this.description,
    this.category,
    this.district,
    this.address,
    this.latitude,
    this.longitude,
    this.phone,
    this.coverImageUrl,
    this.isVerified = false,
    this.rating = 0,
    this.totalReviews = 0,
    this.priceMin,
    this.priceMax,
    this.openHoursText,
    this.amenities = const [],
    this.dishes = const [],
    this.googleRating,
    this.googleTotalReviews = 0,
    this.googleReviews = const [],
    this.hasActiveBenefit = false,
  });

  factory Place.fromJson(Map<String, dynamic> json) => Place(
        details: json,
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Sin nombre',
        description: json['description'] as String?,
        category: json['category'] != null
            ? Category.fromJson(json['category'])
            : null,
        district: json['district'] != null
            ? District.fromJson(json['district'])
            : null,
        address: json['address'] as String?,
        latitude: _parseNum(json['latitude'])?.toDouble(),
        longitude: _parseNum(json['longitude'])?.toDouble(),
        phone: json['phone'] as String?,
        coverImageUrl: (json['coverImageUrl'] ?? json['photoUrl']) as String?,
        isVerified: json['isVerified'] as bool? ?? false,
        rating: _parseNum(json['rating'])?.toDouble() ?? 0,
        totalReviews: (json['totalReviews'] as num?)?.toInt() ?? 0,
        priceMin: _parseNum(json['priceMin']),
        priceMax: _parseNum(json['priceMax']),
        openHoursText: json['openHoursText'] as String?,
        amenities: (json['amenities'] as List?)
                ?.map((e) => e is Map ? '${e['name'] ?? ''}' : e.toString())
                .toList() ??
            const [],
        dishes:
            (json['dishes'] as List?)?.map((e) => Dish.fromJson(e)).toList() ??
                const [],
        googleRating: _parseNum(json['googleRating'])?.toDouble(),
        googleTotalReviews:
            (json['googleTotalReviews'] as num?)?.toInt() ?? 0,
        googleReviews: (json['googleReviews'] as List?)
                ?.map((e) => GoogleReview.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        hasActiveBenefit: json['hasActiveBenefit'] as bool? ?? false,
      );
}

class GoogleReview {
  final String id;
  final String authorName;
  final String? authorPhotoUrl;
  final int rating;
  final String? text;
  final String? relativeTimeDescription;

  GoogleReview({
    required this.id,
    required this.authorName,
    this.authorPhotoUrl,
    required this.rating,
    this.text,
    this.relativeTimeDescription,
  });

  factory GoogleReview.fromJson(Map<String, dynamic> json) => GoogleReview(
        id: json['id'] as String? ?? '',
        authorName: json['authorName'] as String? ?? 'Usuario de Google',
        authorPhotoUrl: json['authorPhotoUrl'] as String?,
        rating: (json['rating'] as num?)?.toInt() ?? 0,
        text: json['text'] as String?,
        relativeTimeDescription: json['relativeTimeDescription'] as String?,
      );
}

class LoyaltyProgram {
  final String type; // 'stamps' | 'points'
  final int stampsToReward;
  final int pointsPerVisit;
  final String? rewardTitle;
  final String? rewardDescription;
  final bool isActive;

  LoyaltyProgram({
    required this.type,
    required this.stampsToReward,
    required this.pointsPerVisit,
    this.rewardTitle,
    this.rewardDescription,
    required this.isActive,
  });

  factory LoyaltyProgram.fromJson(Map<String, dynamic> json) => LoyaltyProgram(
        type: json['type'] as String? ?? 'stamps',
        stampsToReward: (json['stampsToReward'] as num?)?.toInt() ?? 10,
        pointsPerVisit: (json['pointsPerVisit'] as num?)?.toInt() ?? 10,
        rewardTitle: json['rewardTitle'] as String?,
        rewardDescription: json['rewardDescription'] as String?,
        isActive: json['isActive'] as bool? ?? true,
      );
}

class LoyaltyCard {
  final LoyaltyProgram program;
  final int? stamps;
  final int? points;
  final String? level;
  final bool isNew;

  LoyaltyCard({
    required this.program,
    this.stamps,
    this.points,
    this.level,
    required this.isNew,
  });

  factory LoyaltyCard.fromJson(Map<String, dynamic> json) {
    final card = json['card'] as Map<String, dynamic>?;
    return LoyaltyCard(
      program: LoyaltyProgram.fromJson(json['program'] as Map<String, dynamic>),
      stamps: (card?['stamps'] as num?)?.toInt(),
      points: (card?['points'] as num?)?.toInt(),
      level: card?['level'] as String?,
      isNew: json['isNew'] as bool? ?? card == null,
    );
  }
}

/// One entry of `GET /loyalty/my-cards` — this user's loyalty card at one
/// restaurant, aggregated across every restaurant they've visited.
class MyLoyaltyCard {
  final String placeId;
  final String placeName;
  final String? placeCoverImageUrl;
  final String programType; // 'stamps' | 'points'
  final int stamps;
  final int points;
  final int? stampsToReward;
  final int? stampsRemaining;
  final String? level;
  final String? rewardTitle;
  final double? latitude;
  final double? longitude;

  MyLoyaltyCard({
    required this.placeId,
    required this.placeName,
    this.placeCoverImageUrl,
    required this.programType,
    required this.stamps,
    required this.points,
    this.stampsToReward,
    this.stampsRemaining,
    this.level,
    this.rewardTitle,
    this.latitude,
    this.longitude,
  });

  /// True once the reward is earned and ready to redeem. Only computed for
  /// stamp-based programs — points programs have no redemption threshold yet.
  bool get rewardReady => stampsRemaining == 0;

  /// True when there's enough location data to register a geofence for this card.
  bool get hasLocation => latitude != null && longitude != null;

  factory MyLoyaltyCard.fromJson(Map<String, dynamic> json) => MyLoyaltyCard(
        placeId: json['placeId'] as String,
        placeName: json['placeName'] as String? ?? '',
        placeCoverImageUrl: json['placeCoverImageUrl'] as String?,
        programType: json['programType'] as String? ?? 'stamps',
        stamps: (json['stamps'] as num?)?.toInt() ?? 0,
        points: (json['points'] as num?)?.toInt() ?? 0,
        stampsToReward: (json['stampsToReward'] as num?)?.toInt(),
        stampsRemaining: (json['stampsRemaining'] as num?)?.toInt(),
        level: json['level'] as String?,
        rewardTitle: json['rewardTitle'] as String?,
        latitude: _parseNum(json['latitude'])?.toDouble(),
        longitude: _parseNum(json['longitude'])?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'placeId': placeId,
        'placeName': placeName,
        'placeCoverImageUrl': placeCoverImageUrl,
        'programType': programType,
        'stamps': stamps,
        'points': points,
        'stampsToReward': stampsToReward,
        'stampsRemaining': stampsRemaining,
        'level': level,
        'rewardTitle': rewardTitle,
        'latitude': latitude,
        'longitude': longitude,
      };
}

class Paginated<T> {
  final List<T> data;
  final int total;
  final int page;
  final int totalPages;

  Paginated(
      {required this.data,
      required this.total,
      required this.page,
      required this.totalPages});

  factory Paginated.fromJson(
      Map<String, dynamic> json, T Function(Map<String, dynamic>) fromJson) {
    final meta = json['meta'] as Map<String, dynamic>? ?? json;
    final total = (meta['total'] as num?)?.toInt() ?? 0;
    final size = (meta['size'] ?? meta['limit'] ?? 20) as num;
    return Paginated(
      data: (json['data'] as List? ?? [])
          .map((e) => fromJson(e as Map<String, dynamic>))
          .toList(),
      total: total,
      page: (meta['page'] as num?)?.toInt() ?? 1,
      totalPages: (meta['totalPages'] as num?)?.toInt() ??
          (size > 0 ? (total / size).ceil() : 1),
    );
  }
}

class AppUser {
  final Map<String, dynamic> details;
  final String id;
  final String email;
  final String fullName;
  final String? avatarUrl;
  final String? bio;
  final int? currentLevel;
  final int? xp;

  AppUser({
    this.details = const {},
    required this.id,
    required this.email,
    required this.fullName,
    this.avatarUrl,
    this.bio,
    this.currentLevel,
    this.xp,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        details: json,
        id: json['id'] as String? ?? '',
        email: json['email'] as String? ?? '',
        fullName: json['fullName'] as String? ?? '',
        avatarUrl: json['avatarUrl'] as String?,
        bio: json['bio'] as String?,
        currentLevel:
            ((json['currentLevel'] ?? json['level']) as num?)?.toInt(),
        xp: (json['xp'] as num?)?.toInt(),
      );
}

class GamificationStats {
  final int level;
  final int xp;
  final int nextLevelXp;
  final int checkinsCount;
  final int weeklyStreak;

  GamificationStats({
    required this.level,
    required this.xp,
    required this.nextLevelXp,
    required this.checkinsCount,
    this.weeklyStreak = 0,
  });

  factory GamificationStats.fromJson(Map<String, dynamic> json) =>
      GamificationStats(
        level: (json['level'] as num?)?.toInt() ?? 1,
        xp: (json['xp'] as num?)?.toInt() ?? 0,
        nextLevelXp: (json['nextLevelXp'] as num?)?.toInt() ?? 1000,
        checkinsCount: (json['checkinsCount'] as num?)?.toInt() ?? 0,
        weeklyStreak: (json['weeklyStreak'] as num?)?.toInt() ?? 0,
      );
}

class AppBadge {
  final String id;
  final String name;
  final String icon;
  final String? description;
  final bool unlocked;

  AppBadge({
    required this.id,
    required this.name,
    required this.icon,
    this.description,
    required this.unlocked,
  });

  factory AppBadge.fromJson(Map<String, dynamic> json) => AppBadge(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? 'Insignia',
        icon: json['icon'] as String? ?? '🏅',
        description: json['description'] as String?,
        unlocked: json['unlockedAt'] != null,
      );
}

class CheckinItem {
  final String? userId;
  final String? dishName;
  final num? dishPrice;
  final String id;
  final String placeId;
  final String? comment;
  final int? rating;
  final String? photoUrl;
  final int likesCount;
  final String createdAt;
  final String? userFullName;
  final Place? place;
  final bool isLikedByMe;

  CheckinItem({
    this.userId,
    this.dishName,
    this.dishPrice,
    required this.id,
    required this.placeId,
    this.comment,
    this.rating,
    this.photoUrl,
    this.likesCount = 0,
    required this.createdAt,
    this.userFullName,
    this.place,
    this.isLikedByMe = false,
  });

  factory CheckinItem.fromJson(Map<String, dynamic> json) => CheckinItem(
        userId: json['user']?['id'] as String?,
        dishName: json['dishName'] as String?,
        dishPrice: _parseNum(json['dishPrice']),
        id: json['id'] as String,
        placeId: (json['placeId'] ?? json['place']?['id']) as String? ?? '',
        comment: json['comment'] as String?,
        rating: (json['rating'] as num?)?.toInt(),
        photoUrl: json['photoUrl'] as String?,
        likesCount: (json['likesCount'] as num?)?.toInt() ?? 0,
        createdAt: json['createdAt'] as String? ?? '',
        userFullName:
            (json['user'] as Map<String, dynamic>?)?['fullName'] as String?,
        place: json['place'] != null ? Place.fromJson(json['place']) : null,
        isLikedByMe: json['isLikedByMe'] as bool? ?? false,
      );
}
