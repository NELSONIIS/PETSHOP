import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/errors.dart';
import '../models/billing.dart';
import '../models/common.dart';
import '../models/engagement.dart';
import '../models/listing.dart';
import '../models/seller.dart';
import 'auth.dart';
import 'paged.dart';
import 'providers.dart';

// ---------- public catalogue ----------

final publicConfigProvider = FutureProvider<PublicConfig>((ref) => ref.watch(catalogRepoProvider).config());
final categoriesProvider = FutureProvider<List<Category>>((ref) => ref.watch(catalogRepoProvider).categories());

/// Chosen location (persisted locally; synced to the buyer profile when signed in).
class UserLocation {
  const UserLocation({this.city = '', this.state = '', this.lat, this.lng, this.radiusKm = 50});
  final String city, state;
  final double? lat, lng;
  final int radiusKm;
  bool get isSet => city.isNotEmpty || lat != null;
  bool get hasCoords => lat != null && lng != null;
}

class LocationNotifier extends Notifier<UserLocation> {
  @override
  UserLocation build() {
    final p = ref.watch(sharedPrefsProvider);
    return UserLocation(
      city: p.getString('loc_city') ?? '',
      state: p.getString('loc_state') ?? '',
      lat: p.getDouble('loc_lat'),
      lng: p.getDouble('loc_lng'),
      radiusKm: p.getInt('loc_radius') ?? 50,
    );
  }

  Future<void> set(UserLocation l) async {
    final p = ref.read(sharedPrefsProvider);
    await p.setString('loc_city', l.city);
    await p.setString('loc_state', l.state);
    l.lat == null ? await p.remove('loc_lat') : await p.setDouble('loc_lat', l.lat!);
    l.lng == null ? await p.remove('loc_lng') : await p.setDouble('loc_lng', l.lng!);
    await p.setInt('loc_radius', l.radiusKm);
    state = l;
    if (ref.read(authProvider).isAuthed && ref.read(authProvider).user!.isBuyer) {
      try {
        final repo = ref.read(buyerRepoProvider);
        final cur = await repo.profile();
        await repo.saveProfile(
          cur.copyWith(city: l.city, state: l.state, lat: l.lat, lng: l.lng, radiusKm: l.radiusKm),
        );
      } catch (_) {
        /* local preference is already saved */
      }
    }
  }
}

final locationProvider = NotifierProvider<LocationNotifier, UserLocation>(LocationNotifier.new);

// Home sections (small, bounded lists)
final homeFeaturedProvider = FutureProvider<List<Listing>>((ref) async {
  ref.watch(userIdProvider);
  return (await ref.watch(catalogRepoProvider).pets(const PetFilter(featured: true), perPage: 8)).items;
});
final homeRecentProvider = FutureProvider<List<Listing>>((ref) async {
  ref.watch(userIdProvider);
  return (await ref.watch(catalogRepoProvider).pets(const PetFilter(), perPage: 10)).items;
});
final homeNearbyProvider = FutureProvider<List<Listing>>((ref) async {
  ref.watch(userIdProvider);
  final loc = ref.watch(locationProvider);
  if (!loc.isSet) return const [];
  final f = loc.hasCoords
      ? PetFilter(lat: loc.lat, lng: loc.lng, radiusKm: loc.radiusKm, sort: 'nearest')
      : PetFilter(city: loc.city);
  return (await ref.watch(catalogRepoProvider).pets(f, perPage: 8)).items;
});
final verifiedSellersProvider = FutureProvider<List<SellerBadge>>(
  (ref) async => (await ref.watch(catalogRepoProvider).sellers(perPage: 10)).items,
);

// ---------- search (state survives navigating to a listing and back) ----------

class SearchFilterNotifier extends Notifier<PetFilter> {
  @override
  PetFilter build() => const PetFilter();
  void set(PetFilter f) => state = f;
  void reset() => state = const PetFilter();
}

final searchFilterProvider = NotifierProvider<SearchFilterNotifier, PetFilter>(SearchFilterNotifier.new);

class PetsNotifier extends PagedNotifier<Listing> {
  PetsNotifier(this.filter);
  final PetFilter filter;
  @override
  void deps() => ref.watch(userIdProvider);
  @override
  Future<Paged<Listing>> fetch(int page) => ref.read(catalogRepoProvider).pets(filter, page: page);
}

final petsProvider = NotifierProvider.autoDispose.family<PetsNotifier, PagedState<Listing>, PetFilter>(
  PetsNotifier.new,
);

class SellerPetsNotifier extends PagedNotifier<Listing> {
  SellerPetsNotifier(this.slug);
  final String slug;
  @override
  Future<Paged<Listing>> fetch(int page) => ref.read(catalogRepoProvider).sellerPets(slug, page: page);
}

final sellerPetsProvider = NotifierProvider.autoDispose.family<SellerPetsNotifier, PagedState<Listing>, String>(
  SellerPetsNotifier.new,
);

final petDetailProvider = FutureProvider.autoDispose.family<Listing, String>((ref, id) {
  ref.watch(userIdProvider);
  return ref.watch(catalogRepoProvider).pet(id);
});
final similarProvider = FutureProvider.autoDispose.family<List<Listing>, String>(
  (ref, id) => ref.watch(catalogRepoProvider).similar(id),
);
final sellerPublicProvider = FutureProvider.autoDispose.family<SellerBadge, String>(
  (ref, slug) => ref.watch(catalogRepoProvider).seller(slug),
);
final plansProvider = FutureProvider.autoDispose.family<List<Plan>, String>(
  (ref, audience) => ref.watch(catalogRepoProvider).plans(audience),
);
final legalProvider = FutureProvider.autoDispose.family<({String title, String body}), String>(
  (ref, slug) => ref.watch(catalogRepoProvider).legal(slug),
);

// ---------- favourites (optimistic) ----------

class FavouriteOverrides extends Notifier<Map<String, bool>> {
  @override
  Map<String, bool> build() {
    ref.watch(userIdProvider);
    return {};
  }

  bool isFav(Listing l) => state[l.id] ?? l.isFavourite;

  /// Returns false (and reverts) when the call fails.
  Future<bool> toggle(Listing l) async {
    final now = !isFav(l);
    state = {...state, l.id: now};
    try {
      final repo = ref.read(buyerRepoProvider);
      now ? await repo.addFavourite(l.id) : await repo.removeFavourite(l.id);
      ref.invalidate(favouritesProvider);
      return true;
    } catch (_) {
      state = {...state, l.id: !now};
      return false;
    }
  }
}

final favouriteOverridesProvider = NotifierProvider<FavouriteOverrides, Map<String, bool>>(FavouriteOverrides.new);

class FavouritesNotifier extends PagedNotifier<Listing> {
  @override
  void deps() => ref.watch(userIdProvider);
  @override
  Future<Paged<Listing>> fetch(int page) => ref.read(buyerRepoProvider).favourites(page: page);
}

final favouritesProvider = NotifierProvider<FavouritesNotifier, PagedState<Listing>>(FavouritesNotifier.new);
final recentlyViewedProvider = FutureProvider.autoDispose<List<Listing>>(
  (ref) => ref.watch(buyerRepoProvider).recentlyViewed(),
);

// ---------- buyer ----------

final buyerDashboardProvider = FutureProvider.autoDispose<BuyerDashboard>(
  (ref) => ref.watch(buyerRepoProvider).dashboard(),
);
final buyerProfileProvider = FutureProvider.autoDispose<BuyerProfile>((ref) => ref.watch(buyerRepoProvider).profile());

class BuyerEnquiriesNotifier extends PagedNotifier<Enquiry> {
  BuyerEnquiriesNotifier(this.status);
  final String? status;
  @override
  void deps() => ref.watch(userIdProvider);
  @override
  Future<Paged<Enquiry>> fetch(int page) => ref.read(buyerRepoProvider).enquiries(status: status, page: page);
}

final buyerEnquiriesProvider = NotifierProvider.family<BuyerEnquiriesNotifier, PagedState<Enquiry>, String?>(
  BuyerEnquiriesNotifier.new,
);

// Enquiry thread: parameter says which side is reading.
typedef ThreadKey = ({String id, bool seller});
final enquiryDetailProvider = FutureProvider.autoDispose.family<Enquiry, ThreadKey>(
  (ref, k) => k.seller ? ref.watch(sellerRepoProvider).enquiry(k.id) : ref.watch(buyerRepoProvider).enquiry(k.id),
);

// ---------- billing ----------

final subscriptionProvider = FutureProvider.autoDispose<SubscriptionStatus>((ref) {
  ref.watch(userIdProvider);
  return ref.watch(billingRepoProvider).current();
});

class PaymentsNotifier extends PagedNotifier<Payment> {
  @override
  Future<Paged<Payment>> fetch(int page) => ref.read(billingRepoProvider).payments(page: page);
}

final paymentsProvider = NotifierProvider.autoDispose<PaymentsNotifier, PagedState<Payment>>(PaymentsNotifier.new);

class InvoicesNotifier extends PagedNotifier<Invoice> {
  @override
  Future<Paged<Invoice>> fetch(int page) => ref.read(billingRepoProvider).invoices(page: page);
}

final invoicesProvider = NotifierProvider.autoDispose<InvoicesNotifier, PagedState<Invoice>>(InvoicesNotifier.new);
final invoiceProvider = FutureProvider.autoDispose.family<Invoice, String>(
  (ref, id) => ref.watch(billingRepoProvider).invoice(id),
);

// ---------- notifications ----------

class NotificationsNotifier extends PagedNotifier<Notice> {
  @override
  Future<Paged<Notice>> fetch(int page) => ref.read(accountRepoProvider).notifications(page: page);
}

final notificationsProvider = NotifierProvider.autoDispose<NotificationsNotifier, PagedState<Notice>>(
  NotificationsNotifier.new,
);
final unreadCountProvider = FutureProvider.autoDispose<int>((ref) async {
  if (!ref.watch(authProvider).isAuthed) return 0;
  try {
    return await ref.watch(accountRepoProvider).unreadCount();
  } on AppException {
    return 0;
  }
});
final disputesProvider = FutureProvider.autoDispose<List<Dispute>>((ref) => ref.watch(accountRepoProvider).disputes());
final sessionsProvider = FutureProvider.autoDispose<List<SessionInfo>>((ref) => ref.watch(authRepoProvider).sessions());

// ---------- seller ----------

final sellerDashboardProvider = FutureProvider.autoDispose<SellerDashboard>(
  (ref) => ref.watch(sellerRepoProvider).dashboard(),
);
final sellerProfileProvider = FutureProvider.autoDispose<SellerProfile>(
  (ref) => ref.watch(sellerRepoProvider).profile(),
);
final verificationProvider = FutureProvider.autoDispose<VerificationStatus>(
  (ref) => ref.watch(sellerRepoProvider).verification(),
);
final sellerDocsProvider = FutureProvider.autoDispose<List<SellerDoc>>(
  (ref) => ref.watch(sellerRepoProvider).documents(),
);
final sellerListingProvider = FutureProvider.autoDispose.family<Listing, String>(
  (ref, id) => ref.watch(sellerRepoProvider).listing(id),
);
final listingAnalyticsProvider = FutureProvider.autoDispose.family<ListingAnalytics, String>(
  (ref, id) => ref.watch(sellerRepoProvider).analytics(id),
);

class SellerListingsNotifier extends PagedNotifier<Listing> {
  SellerListingsNotifier(this.status);
  final String? status;
  @override
  Future<Paged<Listing>> fetch(int page) => ref.read(sellerRepoProvider).listings(status: status, page: page);
}

final sellerListingsProvider = NotifierProvider.family<SellerListingsNotifier, PagedState<Listing>, String?>(
  SellerListingsNotifier.new,
);

class SellerEnquiriesNotifier extends PagedNotifier<Enquiry> {
  SellerEnquiriesNotifier(this.unreadOnly);
  final bool unreadOnly;
  @override
  Future<Paged<Enquiry>> fetch(int page) => ref.read(sellerRepoProvider).enquiries(unread: unreadOnly, page: page);
}

final sellerEnquiriesProvider = NotifierProvider.family<SellerEnquiriesNotifier, PagedState<Enquiry>, bool>(
  SellerEnquiriesNotifier.new,
);

// ---------- onboarding flag ----------

final onboardingSeenProvider = Provider<bool>(
  (ref) => ref.watch(sharedPrefsProvider).getBool('onboarding_seen') ?? false,
);

Future<void> markOnboardingSeen(WidgetRef ref) => ref.read(sharedPrefsProvider).setBool('onboarding_seen', true);

// Tab-bar badge helpers
final buyerUnreadProvider = Provider<int>(
  (ref) => ref.watch(buyerEnquiriesProvider(null)).items.fold(0, (a, e) => a + e.unread),
);
final sellerUnreadProvider = Provider<int>(
  (ref) => ref.watch(sellerEnquiriesProvider(false)).items.fold(0, (a, e) => a + e.unread),
);

typedef SharedPrefs = SharedPreferences;

class SellersNotifier extends PagedNotifier<SellerBadge> {
  @override
  Future<Paged<SellerBadge>> fetch(int page) => ref.read(catalogRepoProvider).sellers(page: page);
}

final sellersProvider = NotifierProvider.autoDispose<SellersNotifier, PagedState<SellerBadge>>(SellersNotifier.new);

/// Seller contact for a listing. Calls the authorised, idempotent unlock endpoint; throws
/// membership_required when the backend denies access. Never cached beyond the screen's lifetime.
final contactProvider = FutureProvider.autoDispose.family<ContactInfo, String>(
  (ref, listingId) => ref.watch(buyerRepoProvider).unlockContact(listingId),
);
