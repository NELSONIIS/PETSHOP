import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';

import '../core/api_client.dart';
import '../core/json.dart';
import '../core/token_store.dart';
import '../models/billing.dart';
import '../models/common.dart';
import '../models/engagement.dart';
import '../models/listing.dart';
import '../models/seller.dart';

Paged<T> _paged<T>(ApiResponse r, T Function(Json) f) => Paged(r.list.map(f).toList(), Meta.fromJson(r.meta));

/// A file chosen by the user (from camera, gallery or file picker).
class UploadFile {
  const UploadFile({required this.name, required this.mime, this.path, this.bytes, this.size = 0});
  final String name, mime;
  final String? path;
  final Uint8List? bytes;
  final int size;

  Future<MultipartFile> toMultipart() async {
    final type = MediaType.parse(mime);
    if (bytes != null) {
      return MultipartFile.fromBytes(bytes!, filename: name, contentType: type);
    }
    return MultipartFile.fromFile(path!, filename: name, contentType: type);
  }
}

class AuthResult {
  const AuthResult(this.user, {this.access, this.refresh, this.expiresAt});
  final User user;
  final String? access, refresh;
  final DateTime? expiresAt;
}

class AuthRepository {
  AuthRepository(this.api);
  final ApiClient api;

  Future<AuthResult> _auth(ApiResponse r) async {
    final m = r.map;
    final res = AuthResult(
      User.fromJson(J.map(m, 'user')),
      access: J.strN(m, 'access_token'),
      refresh: J.strN(m, 'refresh_token'),
      expiresAt: J.dt(m, 'expires_at'),
    );
    if (res.access != null && res.refresh != null) {
      await api.setTokens(StoredTokens(access: res.access!, refresh: res.refresh!, expiresAt: res.expiresAt));
    }
    return res;
  }

  Future<AuthResult> login(String email, String password) async =>
      _auth(await api.post('/auth/login', body: {'email': email.trim(), 'password': password}));

  Future<AuthResult> register({
    required String name,
    required String email,
    String phone = '',
    required String password,
    required String role,
  }) async => _auth(
    await api.post(
      '/auth/register',
      body: {
        'name': name.trim(),
        'email': email.trim(),
        if (phone.trim().isNotEmpty) 'phone': phone.trim(),
        'password': password,
        'role': role,
        'accept_terms': true,
      },
    ),
  );

  Future<User> me() async => User.fromJson((await api.get('/me')).map);
  Future<User> updateMe({String? name, String? phone}) async =>
      User.fromJson((await api.patch('/me', body: {'name': ?name, 'phone': ?phone})).map);

  Future<void> logout() async {
    try {
      await api.post('/auth/logout');
    } finally {
      await api.clearSession();
    }
  }

  Future<void> verifyEmail(String code) => api.post('/auth/verify-email', body: {'code': code.trim()});
  Future<void> resendVerification() => api.post('/auth/resend-verification');
  Future<void> forgotPassword(String email) => api.post('/auth/forgot-password', body: {'email': email.trim()});
  Future<void> resetPassword(String email, String code, String password) =>
      api.post('/auth/reset-password', body: {'email': email.trim(), 'code': code.trim(), 'password': password});
  Future<void> changePassword(String current, String next) =>
      api.post('/me/change-password', body: {'current_password': current, 'new_password': next});
  Future<List<SessionInfo>> sessions() async => (await api.get('/me/sessions')).list.map(SessionInfo.fromJson).toList();
  Future<void> revokeSession(String id) => api.delete('/me/sessions/$id');
  Future<void> deleteAccount(String password) async {
    await api.post('/me/delete-account', body: {'password': password});
    await api.clearSession();
  }
}

class CatalogRepository {
  CatalogRepository(this.api);
  final ApiClient api;

  Future<PublicConfig> config() async => PublicConfig.fromJson((await api.get('/config')).map);
  Future<List<Category>> categories() async => (await api.get('/categories')).list.map(Category.fromJson).toList();

  Future<Paged<Listing>> pets(PetFilter f, {int page = 1, int perPage = 20}) async =>
      _paged(await api.get('/pets', query: {...f.toQuery(), 'page': page, 'per_page': perPage}), Listing.fromJson);

  Future<Listing> pet(String idOrSlug) async => Listing.fromJson((await api.get('/pets/$idOrSlug')).map);
  Future<List<Listing>> similar(String id) async =>
      (await api.get('/pets/$id/similar')).list.map(Listing.fromJson).toList();
  Future<void> recordView(String id) async {
    try {
      await api.post('/pets/$id/view');
    } catch (_) {
      /* analytics must never block the UI */
    }
  }

  Future<Paged<SellerBadge>> sellers({String city = '', int page = 1, int perPage = 20}) async =>
      _paged(await api.get('/sellers', query: {'city': city, 'page': page, 'per_page': perPage}), SellerBadge.fromJson);
  Future<SellerBadge> seller(String slug) async => SellerBadge.fromJson((await api.get('/sellers/$slug')).map);
  Future<Paged<Listing>> sellerPets(String slug, {int page = 1}) async =>
      _paged(await api.get('/sellers/$slug/pets', query: {'page': page, 'per_page': 20}), Listing.fromJson);

  Future<List<Plan>> plans(String audience) async =>
      (await api.get('/subscription-plans', query: {'audience': audience})).list.map(Plan.fromJson).toList();

  Future<({String title, String body})> legal(String slug) async {
    final m = (await api.get('/legal/$slug')).map;
    return (title: J.str(m, 'title'), body: J.str(m, 'body_md'));
  }

  Future<Json> content(String key) async => (await api.get('/content/$key')).map;

  Future<void> supportContact({
    required String name,
    required String email,
    String subject = '',
    required String message,
  }) => api.post('/support/contact', body: {'name': name, 'email': email, 'subject': subject, 'message': message});
}

class BuyerRepository {
  BuyerRepository(this.api);
  final ApiClient api;

  Future<Paged<Listing>> favourites({int page = 1}) async =>
      _paged(await api.get('/favourites', query: {'page': page, 'per_page': 20}), Listing.fromJson);
  Future<void> addFavourite(String listingId) => api.post('/favourites', body: {'listing_id': listingId});
  Future<void> removeFavourite(String listingId) => api.delete('/favourites/$listingId');
  Future<List<Listing>> recentlyViewed() async =>
      (await api.get('/buyer/recently-viewed')).list.map(Listing.fromJson).toList();

  Future<BuyerProfile> profile() async => BuyerProfile.fromJson((await api.get('/buyer/profile')).map);
  Future<BuyerProfile> saveProfile(BuyerProfile p) async =>
      BuyerProfile.fromJson((await api.put('/buyer/profile', body: p.toJson())).map);
  Future<BuyerDashboard> dashboard() async => BuyerDashboard.fromJson((await api.get('/buyer/dashboard')).map);

  /// Returns contact details only when the backend authorises it; otherwise throws
  /// AppException(kind: membershipRequired, extra.suggested_plans).
  Future<ContactInfo> unlockContact(String listingId) async =>
      ContactInfo.fromJson((await api.post('/pets/$listingId/contact-unlock')).map);

  Future<Enquiry> createEnquiry(String listingId, String message) async =>
      Enquiry.fromJson((await api.post('/pets/$listingId/enquiries', body: {'message': message.trim()})).map);

  Future<Paged<Enquiry>> enquiries({String? status, int page = 1}) async => _paged(
    await api.get('/buyer/enquiries', query: {'status': status, 'page': page, 'per_page': 20}),
    Enquiry.fromJson,
  );
  Future<Enquiry> enquiry(String id) async => Enquiry.fromJson((await api.get('/buyer/enquiries/$id')).map);
  Future<Message> sendMessage(String id, String body) async =>
      Message.fromJson((await api.post('/buyer/enquiries/$id/messages', body: {'body': body.trim()})).map);
  Future<void> closeEnquiry(String id) => api.post('/buyer/enquiries/$id/close');

  Future<void> report({
    required String targetType,
    required String targetId,
    required String reason,
    String details = '',
  }) => api.post(
    '/reports',
    body: {'target_type': targetType, 'target_id': targetId, 'reason': reason, 'details': details},
  );
  Future<void> block(String userId) => api.post('/blocks', body: {'user_id': userId});
}

class SellerRepository {
  SellerRepository(this.api);
  final ApiClient api;

  Future<SellerDashboard> dashboard() async => SellerDashboard.fromJson((await api.get('/seller/dashboard')).map);
  Future<SellerProfile> profile() async => SellerProfile.fromJson((await api.get('/seller/profile')).map);
  Future<SellerProfile> saveProfile(Json input) async =>
      SellerProfile.fromJson((await api.put('/seller/profile', body: input)).map);
  Future<SellerProfile> uploadLogo(UploadFile f) async {
    final form = FormData.fromMap({'file': await f.toMultipart()});
    return SellerProfile.fromJson((await api.upload('/seller/logo', form)).map);
  }

  Future<VerificationStatus> verification() async =>
      VerificationStatus.fromJson((await api.get('/seller/verification')).map);
  Future<VerificationStatus> submitVerification({String jurisdictionState = ''}) async => VerificationStatus.fromJson(
    (await api.post(
      '/seller/verification/submit',
      body: {if (jurisdictionState.isNotEmpty) 'jurisdiction_state': jurisdictionState},
    )).map,
  );
  Future<List<SellerDoc>> documents() async =>
      (await api.get('/seller/documents')).list.map(SellerDoc.fromJson).toList();
  Future<SellerDoc> uploadDocument(
    UploadFile f,
    String kind, {
    void Function(int, int)? onProgress,
    CancelToken? cancel,
  }) async {
    final form = FormData.fromMap({'kind': kind, 'file': await f.toMultipart()});
    return SellerDoc.fromJson(
      (await api.upload('/seller/documents', form, onProgress: onProgress, cancel: cancel)).map,
    );
  }

  Future<void> deleteDocument(String id) => api.delete('/seller/documents/$id');

  /// [status] may be draft|pending|approved|rejected|suspended|expired|sold.
  Future<Paged<Listing>> listings({String? status, int page = 1}) async => _paged(
    await api.get('/seller/listings', query: {'status': status, 'page': page, 'per_page': 20}),
    Listing.fromJson,
  );
  Future<Listing> listing(String id) async => Listing.fromJson((await api.get('/seller/listings/$id')).map);
  Future<Listing> createListing(ListingDraft d) async =>
      Listing.fromJson((await api.post('/seller/listings', body: d.toJson())).map);
  Future<Listing> updateListing(String id, ListingDraft d) async =>
      Listing.fromJson((await api.put('/seller/listings/$id', body: d.toJson())).map);
  Future<void> deleteListing(String id) => api.delete('/seller/listings/$id');
  Future<Listing> submitListing(String id) async =>
      Listing.fromJson((await api.post('/seller/listings/$id/submit')).map);
  Future<Listing> setAvailability(String id, String availability) async => Listing.fromJson(
    (await api.patch('/seller/listings/$id/availability', body: {'availability': availability})).map,
  );

  Future<Img> uploadImage(
    String listingId,
    UploadFile f, {
    void Function(int, int)? onProgress,
    CancelToken? cancel,
  }) async {
    final form = FormData.fromMap({'file': await f.toMultipart()});
    return Img.fromJson(
      (await api.upload('/seller/listings/$listingId/images', form, onProgress: onProgress, cancel: cancel)).map,
    );
  }

  Future<void> reorderImages(String listingId, List<String> ids) =>
      api.put('/seller/listings/$listingId/images/order', body: {'image_ids': ids});
  Future<void> setCover(String listingId, String imageId) =>
      api.put('/seller/listings/$listingId/images/$imageId/cover');
  Future<void> deleteImage(String listingId, String imageId) =>
      api.delete('/seller/listings/$listingId/images/$imageId');
  Future<ListingAnalytics> analytics(String id, {int days = 30}) async =>
      ListingAnalytics.fromJson((await api.get('/seller/listings/$id/analytics', query: {'days': days})).map);

  Future<Paged<Enquiry>> enquiries({String? status, bool unread = false, int page = 1}) async => _paged(
    await api.get(
      '/seller/enquiries',
      query: {'status': status, 'unread': unread ? true : null, 'page': page, 'per_page': 20},
    ),
    Enquiry.fromJson,
  );
  Future<Enquiry> enquiry(String id) async => Enquiry.fromJson((await api.get('/seller/enquiries/$id')).map);
  Future<Message> sendMessage(String id, String body) async =>
      Message.fromJson((await api.post('/seller/enquiries/$id/messages', body: {'body': body.trim()})).map);
  Future<void> closeEnquiry(String id) => api.post('/seller/enquiries/$id/close');
}

class BillingRepository {
  BillingRepository(this.api);
  final ApiClient api;

  Future<SubscriptionStatus> current() async =>
      SubscriptionStatus.fromJson((await api.get('/subscriptions/current')).map);
  Future<Checkout> checkout(String planId, String idempotencyKey) async => Checkout.fromJson(
    (await api.post('/subscriptions/checkout', body: {'plan_id': planId, 'idempotency_key': idempotencyKey})).map,
  );
  Future<Payment> payment(String id) async => Payment.fromJson((await api.get('/payments/$id')).map);
  Future<Payment> verify(String id, {String? providerPaymentId, String? providerOrderId, String? signature}) async =>
      Payment.fromJson(
        (await api.post(
          '/payments/$id/verify',
          body: {
            'provider_payment_id': ?providerPaymentId,
            'provider_order_id': ?providerOrderId,
            'signature': ?signature,
          },
        )).map,
      );
  Future<Payment> testComplete(String id, bool success) async => Payment.fromJson(
    (await api.post('/payments/$id/test-complete', body: {'outcome': success ? 'success' : 'failure'})).map,
  );
  Future<SubscriptionStatus> cancel(String subscriptionId) async =>
      SubscriptionStatus.fromJson((await api.post('/subscriptions/$subscriptionId/cancel')).map);
  Future<Paged<Payment>> payments({int page = 1}) async =>
      _paged(await api.get('/billing/payments', query: {'page': page, 'per_page': 20}), Payment.fromJson);
  Future<Paged<Invoice>> invoices({int page = 1}) async =>
      _paged(await api.get('/billing/invoices', query: {'page': page, 'per_page': 20}), Invoice.fromJson);
  Future<Invoice> invoice(String id) async => Invoice.fromJson((await api.get('/billing/invoices/$id')).map);
}

class AccountRepository {
  AccountRepository(this.api);
  final ApiClient api;

  Future<Paged<Notice>> notifications({bool unread = false, int page = 1}) async => _paged(
    await api.get('/notifications', query: {'unread': unread ? true : null, 'page': page, 'per_page': 20}),
    Notice.fromJson,
  );
  Future<int> unreadCount() async => J.integer((await api.get('/notifications/unread-count')).map, 'count');
  Future<void> markRead(String id) => api.post('/notifications/$id/read');
  Future<void> markAllRead() => api.post('/notifications/read-all');
  Future<List<Dispute>> disputes() async => (await api.get('/disputes')).list.map(Dispute.fromJson).toList();
  Future<void> openDispute({
    required String kind,
    required String subject,
    required String message,
    String? listingId,
    String? paymentId,
    String? enquiryId,
  }) => api.post(
    '/disputes',
    body: {
      'kind': kind,
      'subject': subject,
      'message': message,
      'listing_id': ?listingId,
      'payment_id': ?paymentId,
      'enquiry_id': ?enquiryId,
    },
  );
}
