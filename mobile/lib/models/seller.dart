import '../core/json.dart';
import 'billing.dart';
import 'engagement.dart';

class SellerProfile {
  const SellerProfile({
    this.id = '',
    this.slug = '',
    this.displayName = '',
    this.sellerType = 'individual',
    this.businessName,
    this.gstNumber,
    this.bio = '',
    this.city = '',
    this.state = '',
    this.lat,
    this.lng,
    this.contactPhone,
    this.contactWhatsapp,
    this.contactEmail,
    this.logoUrl,
    this.verificationStatus = 'unsubmitted',
    this.verified = false,
  });
  final String id, slug, displayName, sellerType, bio, city, state, verificationStatus;
  final String? businessName, gstNumber, contactPhone, contactWhatsapp, contactEmail, logoUrl;
  final double? lat, lng;
  final bool verified;

  bool get profileComplete =>
      displayName.isNotEmpty && city.isNotEmpty && state.isNotEmpty && (contactPhone ?? '').isNotEmpty;

  factory SellerProfile.fromJson(Json j) => SellerProfile(
    id: J.str(j, 'id'),
    slug: J.str(j, 'slug'),
    displayName: J.str(j, 'display_name'),
    sellerType: J.str(j, 'seller_type', 'individual'),
    businessName: J.strN(j, 'business_name'),
    gstNumber: J.strN(j, 'gst_number'),
    bio: J.str(j, 'bio'),
    city: J.str(j, 'city'),
    state: J.str(j, 'state'),
    lat: J.dblN(j, 'lat'),
    lng: J.dblN(j, 'lng'),
    contactPhone: J.strN(j, 'contact_phone'),
    contactWhatsapp: J.strN(j, 'contact_whatsapp'),
    contactEmail: J.strN(j, 'contact_email'),
    logoUrl: J.strN(j, 'logo_url'),
    verificationStatus: J.str(j, 'verification_status', 'unsubmitted'),
    verified: J.boolean(j, 'verified'),
  );
}

class SellerDoc {
  const SellerDoc({
    required this.id,
    required this.kind,
    required this.originalName,
    this.mimeType = '',
    this.sizeBytes = 0,
    this.uploadedAt,
  });
  final String id, kind, originalName, mimeType;
  final int sizeBytes;
  final DateTime? uploadedAt;
  factory SellerDoc.fromJson(Json j) => SellerDoc(
    id: J.str(j, 'id'),
    kind: J.str(j, 'kind'),
    originalName: J.str(j, 'original_name'),
    mimeType: J.str(j, 'mime_type'),
    sizeBytes: J.integer(j, 'size_bytes'),
    uploadedAt: J.dt(j, 'uploaded_at'),
  );
}

class VerificationStatus {
  const VerificationStatus({
    this.status = 'unsubmitted',
    this.submittedAt,
    this.reviewedAt,
    this.reason,
    this.documents = const [],
    this.requirements = const [],
  });
  final String status;
  final DateTime? submittedAt, reviewedAt;
  final String? reason;
  final List<SellerDoc> documents;
  final List<String> requirements;
  factory VerificationStatus.fromJson(Json j) => VerificationStatus(
    status: J.str(j, 'status', 'unsubmitted'),
    submittedAt: J.dt(j, 'submitted_at'),
    reviewedAt: J.dt(j, 'reviewed_at'),
    reason: J.strN(j, 'reason'),
    documents: J.list(j, 'documents', SellerDoc.fromJson),
    requirements: J.strings(j, 'requirements'),
  );
}

class SellerDashboard {
  const SellerDashboard({
    this.counts = const {},
    this.views30d = 0,
    this.enquiriesTotal = 0,
    this.unreadEnquiries = 0,
    this.verificationStatus = 'unsubmitted',
    this.subscription = const SubscriptionStatus(),
    this.recent = const [],
  });
  final Map<String, int> counts;
  final int views30d, enquiriesTotal, unreadEnquiries;
  final String verificationStatus;
  final SubscriptionStatus subscription;
  final List<Enquiry> recent;
  factory SellerDashboard.fromJson(Json j) {
    final c = <String, int>{};
    J.map(j, 'listings').forEach((k, v) => c[k] = v is num ? v.toInt() : 0);
    return SellerDashboard(
      counts: c,
      views30d: J.integer(j, 'views_30d'),
      enquiriesTotal: J.integer(j, 'enquiries_total'),
      unreadEnquiries: J.integer(j, 'unread_enquiries'),
      verificationStatus: J.str(j, 'verification_status', 'unsubmitted'),
      subscription: SubscriptionStatus.fromJson(J.map(j, 'subscription')),
      recent: J.list(j, 'recent_enquiries', Enquiry.fromJson),
    );
  }
}
