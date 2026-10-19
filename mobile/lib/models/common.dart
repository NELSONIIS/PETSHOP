import '../core/json.dart';

class Meta {
  const Meta({this.page = 1, this.perPage = 20, this.total = 0, this.totalPages = 1});
  final int page, perPage, total, totalPages;
  factory Meta.fromJson(Json? j) => Meta(
    page: J.integer(j, 'page', 1),
    perPage: J.integer(j, 'per_page', 20),
    total: J.integer(j, 'total'),
    totalPages: J.integer(j, 'total_pages', 1),
  );
  bool get hasMore => page < totalPages;
}

class Paged<T> {
  const Paged(this.items, this.meta);
  final List<T> items;
  final Meta meta;
}

class User {
  const User({
    required this.id,
    required this.email,
    required this.name,
    required this.accountType,
    this.phone,
    this.roles = const [],
    this.permissions = const [],
    this.emailVerified = false,
    this.mfaEnabled = false,
    this.avatarUrl,
  });
  final String id, email, name, accountType;
  final String? phone, avatarUrl;
  final List<String> roles, permissions;
  final bool emailVerified, mfaEnabled;

  bool get isBuyer => accountType == 'buyer';
  bool get isSeller => accountType == 'seller';
  bool get isStaff => accountType == 'staff';

  factory User.fromJson(Json j) => User(
    id: J.str(j, 'id'),
    email: J.str(j, 'email'),
    name: J.str(j, 'name'),
    accountType: J.str(j, 'account_type', 'buyer'),
    phone: J.strN(j, 'phone'),
    roles: J.strings(j, 'roles'),
    permissions: J.strings(j, 'permissions'),
    emailVerified: J.boolean(j, 'email_verified'),
    mfaEnabled: J.boolean(j, 'mfa_enabled'),
    avatarUrl: J.strN(j, 'avatar_url'),
  );
}

class SessionInfo {
  const SessionInfo({
    required this.id,
    required this.client,
    required this.userAgent,
    required this.ip,
    this.lastUsedAt,
    required this.current,
  });
  final String id, client, userAgent, ip;
  final DateTime? lastUsedAt;
  final bool current;
  factory SessionInfo.fromJson(Json j) => SessionInfo(
    id: J.str(j, 'id'),
    client: J.str(j, 'client'),
    userAgent: J.str(j, 'user_agent'),
    ip: J.str(j, 'ip'),
    lastUsedAt: J.dt(j, 'last_used_at'),
    current: J.boolean(j, 'current'),
  );
}

class PublicConfig {
  const PublicConfig({
    this.brandName = 'PETORA',
    this.currency = 'INR',
    this.maintenance = false,
    this.paymentProvider = 'testmode',
    this.razorpayKeyId = '',
    this.maxImages = 8,
    this.maxImageMb = 8,
  });
  final String brandName, currency, paymentProvider, razorpayKeyId;
  final bool maintenance;
  final int maxImages, maxImageMb;
  factory PublicConfig.fromJson(Json j) => PublicConfig(
    brandName: J.str(j, 'brand_name', 'PETORA'),
    currency: J.str(j, 'currency', 'INR'),
    maintenance: J.boolean(j, 'maintenance'),
    paymentProvider: J.str(j, 'payment_provider', 'testmode'),
    razorpayKeyId: J.str(j, 'razorpay_key_id'),
    maxImages: J.integer(j, 'max_images_per_listing', 8),
    maxImageMb: J.integer(j, 'max_image_mb', 8),
  );
}

class Notice {
  const Notice({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.read,
    this.createdAt,
    this.data = const {},
  });
  final String id, kind, title, body;
  final bool read;
  final DateTime? createdAt;
  final Json data;
  factory Notice.fromJson(Json j) => Notice(
    id: J.str(j, 'id'),
    kind: J.str(j, 'kind'),
    title: J.str(j, 'title'),
    body: J.str(j, 'body'),
    read: J.boolean(j, 'read'),
    createdAt: J.dt(j, 'created_at'),
    data: J.map(j, 'data'),
  );
}

class Dispute {
  const Dispute({
    required this.id,
    required this.kind,
    required this.subject,
    required this.message,
    required this.status,
    this.resolution,
    this.createdAt,
  });
  final String id, kind, subject, message, status;
  final String? resolution;
  final DateTime? createdAt;
  factory Dispute.fromJson(Json j) => Dispute(
    id: J.str(j, 'id'),
    kind: J.str(j, 'kind'),
    subject: J.str(j, 'subject'),
    message: J.str(j, 'message'),
    status: J.str(j, 'status'),
    resolution: J.strN(j, 'resolution'),
    createdAt: J.dt(j, 'created_at'),
  );
}
