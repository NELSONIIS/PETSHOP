import '../core/json.dart';
import 'billing.dart';
import 'listing.dart';

class ContactInfo {
  const ContactInfo({
    this.sellerName = '',
    this.phone,
    this.whatsapp,
    this.email,
    this.unlockedAt,
    this.remainingUnlocks,
  });
  final String sellerName;
  final String? phone, whatsapp, email;
  final DateTime? unlockedAt;
  final int? remainingUnlocks;
  factory ContactInfo.fromJson(Json j) => ContactInfo(
    sellerName: J.str(j, 'seller_name'),
    phone: J.strN(j, 'phone'),
    whatsapp: J.strN(j, 'whatsapp'),
    email: J.strN(j, 'email'),
    unlockedAt: J.dt(j, 'unlocked_at'),
    remainingUnlocks: J.intN(j, 'remaining_unlocks'),
  );
}

class Message {
  const Message({required this.id, required this.mine, required this.body, this.createdAt, this.readAt});
  final String id, body;
  final bool mine;
  final DateTime? createdAt, readAt;
  factory Message.fromJson(Json j) => Message(
    id: J.str(j, 'id'),
    mine: J.boolean(j, 'mine'),
    body: J.str(j, 'body'),
    createdAt: J.dt(j, 'created_at'),
    readAt: J.dt(j, 'read_at'),
  );
}

class Enquiry {
  const Enquiry({
    required this.id,
    required this.status,
    this.listingId = '',
    this.listingSlug = '',
    this.listingTitle = '',
    this.cover,
    this.availability = '',
    this.counterpartyName = '',
    this.counterpartySlug,
    this.lastMessage = '',
    this.lastMessageAt,
    this.unread = 0,
    this.createdAt,
    this.messages = const [],
    this.firstResponseAt,
    this.contactUnlocked = false,
  });
  final String id, status, listingId, listingSlug, listingTitle, availability, counterpartyName, lastMessage;
  final String? counterpartySlug;
  final Img? cover;
  final DateTime? lastMessageAt, createdAt, firstResponseAt;
  final int unread;
  final List<Message> messages;
  final bool contactUnlocked;

  factory Enquiry.fromJson(Json j) {
    final l = J.map(j, 'listing');
    final c = J.map(j, 'counterparty');
    return Enquiry(
      id: J.str(j, 'id'),
      status: J.str(j, 'status'),
      listingId: J.str(l, 'id'),
      listingSlug: J.str(l, 'slug'),
      listingTitle: J.str(l, 'title'),
      cover: Img.cover(J.mapN(l, 'cover')),
      availability: J.str(l, 'availability'),
      counterpartyName: J.str(c, 'name'),
      counterpartySlug: J.strN(c, 'slug'),
      lastMessage: J.str(j, 'last_message'),
      lastMessageAt: J.dt(j, 'last_message_at'),
      unread: J.integer(j, 'unread'),
      createdAt: J.dt(j, 'created_at'),
      messages: J.list(j, 'messages', Message.fromJson),
      firstResponseAt: J.dt(j, 'first_response_at'),
      contactUnlocked: J.boolean(j, 'contact_unlocked'),
    );
  }
}

class BuyerDashboard {
  const BuyerDashboard({
    this.favourites = 0,
    this.enquiries = 0,
    this.unreadReplies = 0,
    this.unlockedContacts = 0,
    this.subscription = const SubscriptionStatus(),
    this.recent = const [],
  });
  final int favourites, enquiries, unreadReplies, unlockedContacts;
  final SubscriptionStatus subscription;
  final List<Enquiry> recent;
  factory BuyerDashboard.fromJson(Json j) => BuyerDashboard(
    favourites: J.integer(j, 'favourites'),
    enquiries: J.integer(j, 'enquiries'),
    unreadReplies: J.integer(j, 'unread_replies'),
    unlockedContacts: J.integer(j, 'unlocked_contacts'),
    subscription: SubscriptionStatus.fromJson(J.map(j, 'subscription')),
    recent: J.list(j, 'recent_enquiries', Enquiry.fromJson),
  );
}

class BuyerProfile {
  const BuyerProfile({
    this.city = '',
    this.state = '',
    this.lat,
    this.lng,
    this.radiusKm = 50,
    this.notifyEmail = true,
    this.notifySms = false,
    this.notifyPush = true,
  });
  final String city, state;
  final double? lat, lng;
  final int radiusKm;
  final bool notifyEmail, notifySms, notifyPush;
  factory BuyerProfile.fromJson(Json j) => BuyerProfile(
    city: J.str(j, 'city'),
    state: J.str(j, 'state'),
    lat: J.dblN(j, 'lat'),
    lng: J.dblN(j, 'lng'),
    radiusKm: J.integer(j, 'radius_km', 50),
    notifyEmail: J.boolean(j, 'notify_email', true),
    notifySms: J.boolean(j, 'notify_sms'),
    notifyPush: J.boolean(j, 'notify_push', true),
  );
  Json toJson() => {
    'city': city,
    'state': state,
    'lat': lat,
    'lng': lng,
    'radius_km': radiusKm,
    'notify_email': notifyEmail,
    'notify_sms': notifySms,
    'notify_push': notifyPush,
  };
  BuyerProfile copyWith({
    String? city,
    String? state,
    double? lat,
    double? lng,
    int? radiusKm,
    bool? notifyEmail,
    bool? notifySms,
    bool? notifyPush,
  }) => BuyerProfile(
    city: city ?? this.city,
    state: state ?? this.state,
    lat: lat ?? this.lat,
    lng: lng ?? this.lng,
    radiusKm: radiusKm ?? this.radiusKm,
    notifyEmail: notifyEmail ?? this.notifyEmail,
    notifySms: notifySms ?? this.notifySms,
    notifyPush: notifyPush ?? this.notifyPush,
  );
  bool get hasLocation => city.isNotEmpty;
}
