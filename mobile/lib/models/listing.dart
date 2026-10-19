import '../core/json.dart';

class Img {
  const Img({
    this.id = '',
    this.thumb = '',
    this.medium = '',
    this.large = '',
    this.width = 0,
    this.height = 0,
    this.position = 0,
    this.isCover = false,
    this.altText = '',
  });
  final String id, thumb, medium, large, altText;
  final int width, height, position;
  final bool isCover;
  factory Img.fromJson(Json j) => Img(
    id: J.str(j, 'id'),
    thumb: J.str(j, 'thumb'),
    medium: J.str(j, 'medium'),
    large: J.str(j, 'large'),
    width: J.integer(j, 'width'),
    height: J.integer(j, 'height'),
    position: J.integer(j, 'position'),
    isCover: J.boolean(j, 'is_cover'),
    altText: J.str(j, 'alt_text'),
  );
  static Img? cover(Json? j) => j == null ? null : Img.fromJson(j);
  bool get isEmpty => thumb.isEmpty && medium.isEmpty && large.isEmpty;
  String get best => medium.isNotEmpty ? medium : (large.isNotEmpty ? large : thumb);
  String get small => thumb.isNotEmpty ? thumb : best;
  String get full => large.isNotEmpty ? large : best;
}

class Ref {
  const Ref({this.id = '', this.slug = '', this.name = ''});
  final String id, slug, name;
  factory Ref.fromJson(Json j) => Ref(id: J.str(j, 'id'), slug: J.str(j, 'slug'), name: J.str(j, 'name'));
  static Ref? maybe(Json? j) => j == null ? null : Ref.fromJson(j);
}

class Breed {
  const Breed({required this.id, required this.slug, required this.name, this.isActive = true});
  final String id, slug, name;
  final bool isActive;
  factory Breed.fromJson(Json j) => Breed(
    id: J.str(j, 'id'),
    slug: J.str(j, 'slug'),
    name: J.str(j, 'name'),
    isActive: J.boolean(j, 'is_active', true),
  );
}

class Category {
  const Category({
    required this.id,
    required this.slug,
    required this.name,
    this.icon = 'paw',
    this.description = '',
    this.requiresVerifiedSeller = false,
    this.listingCount = 0,
    this.breeds = const [],
  });
  final String id, slug, name, icon, description;
  final bool requiresVerifiedSeller;
  final int listingCount;
  final List<Breed> breeds;
  factory Category.fromJson(Json j) => Category(
    id: J.str(j, 'id'),
    slug: J.str(j, 'slug'),
    name: J.str(j, 'name'),
    icon: J.str(j, 'icon', 'paw'),
    description: J.str(j, 'description'),
    requiresVerifiedSeller: J.boolean(j, 'requires_verified_seller'),
    listingCount: J.integer(j, 'listing_count'),
    breeds: J.list(j, 'breeds', Breed.fromJson),
  );
}

class SellerBadge {
  const SellerBadge({
    this.id = '',
    this.slug = '',
    this.displayName = '',
    this.sellerType = 'individual',
    this.verified = false,
    this.city = '',
    this.state = '',
    this.logoUrl,
    this.bio = '',
    this.activeListings = 0,
    this.memberSince,
  });
  final String id, slug, displayName, sellerType, city, state, bio;
  final bool verified;
  final String? logoUrl;
  final int activeListings;
  final DateTime? memberSince;
  factory SellerBadge.fromJson(Json j) => SellerBadge(
    id: J.str(j, 'id'),
    slug: J.str(j, 'slug'),
    displayName: J.str(j, 'display_name'),
    sellerType: J.str(j, 'seller_type', 'individual'),
    verified: J.boolean(j, 'verified'),
    city: J.str(j, 'city'),
    state: J.str(j, 'state'),
    logoUrl: J.strN(j, 'logo_url'),
    bio: J.str(j, 'bio'),
    activeListings: J.integer(j, 'active_listings'),
    memberSince: J.dt(j, 'member_since'),
  );
  String get location => [city, state].where((e) => e.isNotEmpty).join(', ');
}

class ModerationEvent {
  const ModerationEvent({required this.action, this.reason, this.createdAt});
  final String action;
  final String? reason;
  final DateTime? createdAt;
  factory ModerationEvent.fromJson(Json j) =>
      ModerationEvent(action: J.str(j, 'action'), reason: J.strN(j, 'reason'), createdAt: J.dt(j, 'created_at'));
}

/// One class for card / detail / owner views of a listing; fields absent from a view keep defaults.
class Listing {
  const Listing({
    required this.id,
    this.slug = '',
    this.title = '',
    this.listingType = 'sale',
    this.priceMinor = 0,
    this.currency = 'INR',
    this.ageMonths,
    this.gender = 'unknown',
    this.city = '',
    this.state = '',
    this.category,
    this.breed,
    this.cover,
    this.seller = const SellerBadge(),
    this.availability = 'available',
    this.vaccinationStatus = 'unspecified',
    this.featured = false,
    this.isFavourite = false,
    this.distanceKm,
    this.publishedAt,
    this.description = '',
    this.colour = '',
    this.vaccinationNotes = '',
    this.healthNotes = '',
    this.dewormed,
    this.microchipped,
    this.images = const [],
    this.attributes = const {},
    this.viewsCount = 0,
    this.contactUnlocked = false,
    this.requiresMembership = true,
    this.disclaimer = '',
    this.status = '',
    this.rejectionReason,
    this.expiredReason,
    this.favouritesCount = 0,
    this.enquiriesCount = 0,
    this.expiresAt,
    this.moderation = const [],
    this.missingForSubmission = const [],
    this.sellerProfile,
  });

  final String id,
      slug,
      title,
      listingType,
      currency,
      gender,
      city,
      state,
      availability,
      vaccinationStatus,
      description,
      colour,
      vaccinationNotes,
      healthNotes,
      disclaimer,
      status;
  final int priceMinor, viewsCount, favouritesCount, enquiriesCount;
  final int? ageMonths;
  final Ref? category, breed;
  final Img? cover;
  final SellerBadge seller;
  final SellerBadge? sellerProfile;
  final bool featured, isFavourite, contactUnlocked, requiresMembership;
  final bool? dewormed, microchipped;
  final double? distanceKm;
  final DateTime? publishedAt, expiresAt;
  final List<Img> images;
  final Map<String, String> attributes;
  final String? rejectionReason, expiredReason;
  final List<ModerationEvent> moderation;
  final List<String> missingForSubmission;

  bool get isAdoption => listingType == 'adoption';
  String get location => [city, state].where((e) => e.isNotEmpty).join(', ');

  Listing copyWith({bool? isFavourite, String? availability, bool? contactUnlocked}) => Listing(
    id: id,
    slug: slug,
    title: title,
    listingType: listingType,
    priceMinor: priceMinor,
    currency: currency,
    ageMonths: ageMonths,
    gender: gender,
    city: city,
    state: state,
    category: category,
    breed: breed,
    cover: cover,
    seller: seller,
    availability: availability ?? this.availability,
    vaccinationStatus: vaccinationStatus,
    featured: featured,
    isFavourite: isFavourite ?? this.isFavourite,
    distanceKm: distanceKm,
    publishedAt: publishedAt,
    description: description,
    colour: colour,
    vaccinationNotes: vaccinationNotes,
    healthNotes: healthNotes,
    dewormed: dewormed,
    microchipped: microchipped,
    images: images,
    attributes: attributes,
    viewsCount: viewsCount,
    contactUnlocked: contactUnlocked ?? this.contactUnlocked,
    requiresMembership: requiresMembership,
    disclaimer: disclaimer,
    status: status,
    rejectionReason: rejectionReason,
    expiredReason: expiredReason,
    favouritesCount: favouritesCount,
    enquiriesCount: enquiriesCount,
    expiresAt: expiresAt,
    moderation: moderation,
    missingForSubmission: missingForSubmission,
    sellerProfile: sellerProfile,
  );

  factory Listing.fromJson(Json j) {
    final contact = J.map(j, 'contact');
    final attrs = <String, String>{};
    J.map(j, 'attributes').forEach((k, v) => attrs[k] = '$v');
    final sp = J.mapN(j, 'seller_profile');
    return Listing(
      id: J.str(j, 'id'),
      slug: J.str(j, 'slug'),
      title: J.str(j, 'title'),
      listingType: J.str(j, 'listing_type', 'sale'),
      priceMinor: J.integer(j, 'price_minor'),
      currency: J.str(j, 'currency', 'INR'),
      ageMonths: J.intN(j, 'age_months'),
      gender: J.str(j, 'gender', 'unknown'),
      city: J.str(j, 'city'),
      state: J.str(j, 'state'),
      category: Ref.maybe(J.mapN(j, 'category')),
      breed: Ref.maybe(J.mapN(j, 'breed')),
      cover: Img.cover(J.mapN(j, 'cover')),
      seller: SellerBadge.fromJson(J.map(j, 'seller')),
      sellerProfile: sp == null ? null : SellerBadge.fromJson(sp),
      availability: J.str(j, 'availability', 'available'),
      vaccinationStatus: J.str(j, 'vaccination_status', 'unspecified'),
      featured: J.boolean(j, 'featured'),
      isFavourite: J.boolean(j, 'is_favourite'),
      distanceKm: J.dblN(j, 'distance_km'),
      publishedAt: J.dt(j, 'published_at'),
      description: J.str(j, 'description'),
      colour: J.str(j, 'colour'),
      vaccinationNotes: J.str(j, 'vaccination_notes'),
      healthNotes: J.str(j, 'health_notes'),
      dewormed: J.boolN(j, 'dewormed'),
      microchipped: J.boolN(j, 'microchipped'),
      images: J.list(j, 'images', Img.fromJson),
      attributes: attrs,
      viewsCount: J.integer(j, 'views_count'),
      contactUnlocked: J.boolean(contact, 'unlocked'),
      requiresMembership: J.boolean(contact, 'requires_membership', true),
      disclaimer: J.str(j, 'disclaimer'),
      status: J.str(j, 'status'),
      rejectionReason: J.strN(j, 'rejection_reason'),
      expiredReason: J.strN(j, 'expired_reason'),
      favouritesCount: J.integer(j, 'favourites_count'),
      enquiriesCount: J.integer(j, 'enquiries_count'),
      expiresAt: J.dt(j, 'expires_at'),
      moderation: J.list(j, 'moderation', ModerationEvent.fromJson),
      missingForSubmission: J.strings(j, 'missing_for_submission'),
    );
  }
}

/// Search filters. Immutable; `toQuery` maps to `GET /pets` params.
class PetFilter {
  const PetFilter({
    this.q = '',
    this.category,
    this.breed,
    this.minPrice,
    this.maxPrice,
    this.minAge,
    this.maxAge,
    this.gender,
    this.city = '',
    this.lat,
    this.lng,
    this.radiusKm,
    this.sellerType,
    this.verifiedSeller = false,
    this.listingType,
    this.vaccination,
    this.availability,
    this.listedWithinDays,
    this.featured = false,
    this.sort = 'newest',
  });

  final String q, city, sort;
  final String? category, breed, gender, sellerType, listingType, vaccination, availability;
  final int? minPrice, maxPrice, minAge, maxAge, radiusKm, listedWithinDays;
  final double? lat, lng;
  final bool verifiedSeller, featured;

  static const _unset = Object();

  PetFilter copyWith({
    String? q,
    Object? category = _unset,
    Object? breed = _unset,
    Object? minPrice = _unset,
    Object? maxPrice = _unset,
    Object? minAge = _unset,
    Object? maxAge = _unset,
    Object? gender = _unset,
    String? city,
    Object? lat = _unset,
    Object? lng = _unset,
    Object? radiusKm = _unset,
    Object? sellerType = _unset,
    bool? verifiedSeller,
    Object? listingType = _unset,
    Object? vaccination = _unset,
    Object? availability = _unset,
    Object? listedWithinDays = _unset,
    bool? featured,
    String? sort,
  }) => PetFilter(
    q: q ?? this.q,
    category: identical(category, _unset) ? this.category : category as String?,
    breed: identical(breed, _unset) ? this.breed : breed as String?,
    minPrice: identical(minPrice, _unset) ? this.minPrice : minPrice as int?,
    maxPrice: identical(maxPrice, _unset) ? this.maxPrice : maxPrice as int?,
    minAge: identical(minAge, _unset) ? this.minAge : minAge as int?,
    maxAge: identical(maxAge, _unset) ? this.maxAge : maxAge as int?,
    gender: identical(gender, _unset) ? this.gender : gender as String?,
    city: city ?? this.city,
    lat: identical(lat, _unset) ? this.lat : lat as double?,
    lng: identical(lng, _unset) ? this.lng : lng as double?,
    radiusKm: identical(radiusKm, _unset) ? this.radiusKm : radiusKm as int?,
    sellerType: identical(sellerType, _unset) ? this.sellerType : sellerType as String?,
    verifiedSeller: verifiedSeller ?? this.verifiedSeller,
    listingType: identical(listingType, _unset) ? this.listingType : listingType as String?,
    vaccination: identical(vaccination, _unset) ? this.vaccination : vaccination as String?,
    availability: identical(availability, _unset) ? this.availability : availability as String?,
    listedWithinDays: identical(listedWithinDays, _unset) ? this.listedWithinDays : listedWithinDays as int?,
    featured: featured ?? this.featured,
    sort: sort ?? this.sort,
  );

  /// Number of active advanced filters (excludes query text and sort) - shown on the filter button.
  int get activeCount => [
    category,
    breed,
    minPrice,
    maxPrice,
    minAge,
    maxAge,
    gender,
    sellerType,
    listingType,
    vaccination,
    availability,
    listedWithinDays,
    city.isEmpty ? null : city,
    radiusKm,
    verifiedSeller ? true : null,
    featured ? true : null,
  ].where((e) => e != null).length;

  Map<String, dynamic> toQuery() => {
    'q': q.trim(),
    'category': category,
    'breed': breed,
    'min_price': minPrice,
    'max_price': maxPrice,
    'min_age_months': minAge,
    'max_age_months': maxAge,
    'gender': gender,
    'city': city.trim(),
    'lat': lat,
    'lng': lng,
    'radius_km': radiusKm,
    'seller_type': sellerType,
    'verified_seller': verifiedSeller ? true : null,
    'listing_type': listingType,
    'vaccination': vaccination,
    'availability': availability,
    'listed_within_days': listedWithinDays,
    'featured': featured ? true : null,
    'sort': sort,
  };

  @override
  bool operator ==(Object other) => other is PetFilter && _key == other._key;
  @override
  int get hashCode => _key.hashCode;
  String get _key => toQuery().toString();
}

/// Writable listing fields (create / edit wizard).
class ListingDraft {
  ListingDraft({
    this.id,
    this.title = '',
    this.description = '',
    this.categoryId,
    this.breedId,
    this.listingType = 'sale',
    this.priceMinor = 0,
    this.ageMonths,
    this.gender = 'unknown',
    this.colour = '',
    this.vaccinationStatus = 'unspecified',
    this.vaccinationNotes = '',
    this.healthNotes = '',
    this.dewormed,
    this.microchipped,
    this.city = '',
    this.state = '',
    this.lat,
    this.lng,
    Map<String, String>? attributes,
  }) : attributes = attributes ?? {};

  String? id, categoryId, breedId;
  String title, description, listingType, gender, colour, vaccinationStatus, vaccinationNotes, healthNotes, city, state;
  int priceMinor;
  int? ageMonths;
  bool? dewormed, microchipped;
  double? lat, lng;
  Map<String, String> attributes;

  factory ListingDraft.fromListing(Listing l) => ListingDraft(
    id: l.id,
    title: l.title,
    description: l.description,
    categoryId: l.category?.id,
    breedId: l.breed?.id,
    listingType: l.listingType,
    priceMinor: l.priceMinor,
    ageMonths: l.ageMonths,
    gender: l.gender,
    colour: l.colour,
    vaccinationStatus: l.vaccinationStatus,
    vaccinationNotes: l.vaccinationNotes,
    healthNotes: l.healthNotes,
    dewormed: l.dewormed,
    microchipped: l.microchipped,
    city: l.city,
    state: l.state,
    attributes: Map.of(l.attributes),
  );

  Map<String, dynamic> toJson() => {
    'title': title.trim(),
    'description': description.trim(),
    'category_id': categoryId,
    'breed_id': breedId,
    'listing_type': listingType,
    'price_minor': listingType == 'adoption' ? 0 : priceMinor,
    'age_months': ageMonths,
    'gender': gender,
    'colour': colour.trim(),
    'vaccination_status': vaccinationStatus,
    'vaccination_notes': vaccinationNotes.trim(),
    'health_notes': healthNotes.trim(),
    'dewormed': dewormed,
    'microchipped': microchipped,
    'city': city.trim(),
    'state': state.trim(),
    'lat': lat,
    'lng': lng,
    'attributes': attributes,
  };
}

class ListingAnalytics {
  const ListingAnalytics({this.views = 0, this.favourites = 0, this.enquiries = 0, this.series = const []});
  final int views, favourites, enquiries;
  final List<MapEntry<DateTime, int>> series;
  factory ListingAnalytics.fromJson(Json j) => ListingAnalytics(
    views: J.integer(j, 'views_total'),
    favourites: J.integer(j, 'favourites_total'),
    enquiries: J.integer(j, 'enquiries_total'),
    series: J.list(
      j,
      'series',
      (e) => MapEntry(DateTime.tryParse(J.str(e, 'date')) ?? DateTime.now(), J.integer(e, 'views')),
    ),
  );
}
