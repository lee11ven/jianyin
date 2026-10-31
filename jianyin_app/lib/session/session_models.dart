class UserProfile {
  const UserProfile({
    required this.userId,
    required this.username,
    required this.phone,
    required this.sex,
    required this.plan,
    this.planExpiresAt,
  });

  final String userId;
  final String username;
  final String phone;
  final String sex;
  final String plan;
  final int? planExpiresAt;

  String get maskedPhone {
    final p = phone;
    if (p.length < 7) return p;
    return '${p.substring(0, 3)}****${p.substring(p.length - 4)}';
  }

  String get avatarLetter {
    final t = username.trim();
    if (t.isEmpty) return '?';
    return t.substring(0, 1);
  }

  String get planLabel {
    switch (plan) {
      case 'pro_month':
        return '专业月卡';
      case 'pro_year':
        return '专业年卡';
      case 'free':
      default:
        return '免费版';
    }
  }

  String get sexLabel {
    switch (sex) {
      case 'male':
        return '男';
      case 'female':
        return '女';
      case 'unknown':
      default:
        return '保密';
    }
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      userId: '${json['userId'] ?? ''}',
      username: '${json['username'] ?? ''}',
      phone: '${json['phone'] ?? ''}',
      sex: '${json['sex'] ?? 'unknown'}',
      plan: '${json['plan'] ?? json['planId'] ?? 'free'}',
      planExpiresAt: (json['planExpiresAt'] as num?)?.toInt() ??
          (json['expiresAt'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'username': username,
        'phone': phone,
        'sex': sex,
        'plan': plan,
        if (planExpiresAt != null) 'planExpiresAt': planExpiresAt,
      };
}

class AuthToken {
  const AuthToken({
    required this.token,
    required this.role,
    required this.deviceId,
    required this.protocolVersion,
    required this.expiresInSec,
    this.user,
  });

  final String token;
  final String role;
  final String deviceId;
  final int protocolVersion;
  final int expiresInSec;
  final UserProfile? user;

  factory AuthToken.fromJson(Map<String, dynamic> json) {
    final userRaw = json['user'];
    return AuthToken(
      token: json['token'] as String,
      role: json['role'] as String? ?? 'app',
      deviceId: json['deviceId'] as String,
      protocolVersion: (json['protocolVersion'] as num?)?.toInt() ?? 1,
      expiresInSec: (json['expiresInSec'] as num?)?.toInt() ?? 86400,
      user: userRaw is Map
          ? UserProfile.fromJson(Map<String, dynamic>.from(userRaw))
          : null,
    );
  }
}

class SessionInfo {
  const SessionInfo({
    required this.sessionId,
    required this.protocolVersion,
    required this.wsUrl,
  });

  final String sessionId;
  final int protocolVersion;
  final String wsUrl;

  factory SessionInfo.fromJson(Map<String, dynamic> json) {
    return SessionInfo(
      sessionId: json['sessionId'] as String,
      protocolVersion: (json['protocolVersion'] as num?)?.toInt() ?? 1,
      wsUrl: json['wsUrl'] as String? ?? '',
    );
  }
}

class HistoryItem {
  const HistoryItem({
    required this.id,
    required this.time,
    required this.text,
    required this.ts,
  });

  final String id;
  final String time;
  final String text;
  final int ts;

  factory HistoryItem.fromJson(Map<String, dynamic> json) {
    return HistoryItem(
      id: '${json['id'] ?? ''}',
      time: '${json['time'] ?? ''}',
      text: '${json['text'] ?? ''}',
      ts: (json['ts'] as num?)?.toInt() ?? 0,
    );
  }
}

class HistoryDay {
  const HistoryDay({
    required this.iso,
    required this.label,
    required this.items,
  });

  final String iso;
  final String label;
  final List<HistoryItem> items;

  factory HistoryDay.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    return HistoryDay(
      iso: '${json['iso'] ?? ''}',
      label: '${json['label'] ?? ''}',
      items: raw is List
          ? raw
              .whereType<Map>()
              .map((e) => HistoryItem.fromJson(Map<String, dynamic>.from(e)))
              .toList(growable: false)
          : const [],
    );
  }
}

class MembershipPlan {
  const MembershipPlan({
    required this.id,
    required this.title,
    required this.price,
    required this.unit,
    required this.features,
    required this.featured,
  });

  final String id;
  final String title;
  final String price;
  final String unit;
  final List<String> features;
  final bool featured;

  factory MembershipPlan.fromJson(Map<String, dynamic> json) {
    final feats = json['features'];
    return MembershipPlan(
      id: '${json['id'] ?? ''}',
      title: '${json['title'] ?? ''}',
      price: '${json['price'] ?? ''}',
      unit: '${json['unit'] ?? ''}',
      features: feats is List
          ? feats.map((e) => '$e').toList(growable: false)
          : const [],
      featured: json['featured'] == true,
    );
  }
}

class MembershipStatus {
  const MembershipStatus({
    required this.planId,
    required this.title,
    this.expiresAt,
  });

  final String planId;
  final String title;
  final int? expiresAt;

  factory MembershipStatus.fromJson(Map<String, dynamic> json) {
    return MembershipStatus(
      planId: '${json['planId'] ?? 'free'}',
      title: '${json['title'] ?? ''}',
      expiresAt: (json['expiresAt'] as num?)?.toInt(),
    );
  }
}

class ApiException implements Exception {
  const ApiException({
    required this.code,
    required this.message,
    this.statusCode,
  });

  final String code;
  final String message;
  final int? statusCode;

  factory ApiException.fromBody(int statusCode, Object? body) {
    if (body is Map) {
      return ApiException(
        code: '${body['code'] ?? 'http_$statusCode'}',
        message: '${body['message'] ?? body}',
        statusCode: statusCode,
      );
    }
    return ApiException(
      code: 'http_$statusCode',
      message: body?.toString() ?? 'request failed',
      statusCode: statusCode,
    );
  }

  @override
  String toString() => 'ApiException($code, $message, status=$statusCode)';
}
