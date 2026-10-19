import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/format.dart';
import '../../models/listing.dart';
import '../../state/auth.dart';
import '../../state/data.dart';
import '../../state/providers.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/badges.dart';
import '../../ui/widgets/buttons.dart';
import '../../ui/widgets/cards.dart';
import '../../ui/widgets/dialogs.dart';
import '../../ui/widgets/gallery.dart';
import '../../ui/widgets/net_image.dart';
import '../../ui/widgets/scaffolds.dart';
import '../../ui/widgets/states.dart';
import '../common.dart';
import '../search/browse_screens.dart';
import '../search/listing_views.dart';

class PetDetailScreen extends ConsumerStatefulWidget {
  const PetDetailScreen({super.key, required this.idOrSlug});
  final String idOrSlug;
  @override
  ConsumerState<PetDetailScreen> createState() => _PetDetailScreenState();
}

class _PetDetailScreenState extends ConsumerState<PetDetailScreen> {
  bool _viewRecorded = false;

  void _recordView(Listing l) {
    if (_viewRecorded) return;
    _viewRecorded = true;
    ref.read(catalogRepoProvider).recordView(l.id);
  }

  Future<void> _unlock(Listing l) async {
    if (!await ensureSignedIn(context, ref, reason: 'Sign in to unlock seller contact')) {
      return;
    }
    if (!mounted) return;
    // If a limited allowance would be consumed, confirm first (already-unlocked contacts are free).
    if (!l.contactUnlocked) {
      final sub = ref.read(subscriptionProvider).asData?.value;
      final left = sub?.entitlements.remainingUnlocks;
      if (sub != null && sub.active && left != null) {
        final ok = await confirmDialog(
          context,
          title: 'Use 1 contact unlock?',
          message:
              'You have $left unlock${left == 1 ? '' : 's'} left on your plan. Unlocking this seller uses one. You can view this contact again at any time without using another.',
          confirmLabel: 'Unlock',
        );
        if (!ok || !mounted) return;
      }
    }
    context.push('/pet/${l.id}/contact');
  }

  Future<void> _enquire(Listing l) async {
    if (!await ensureSignedIn(context, ref, reason: 'Sign in to send an enquiry')) {
      return;
    }
    if (mounted) context.push('/pet/${l.id}/enquire');
  }

  void _share(Listing l) {
    final url = '${ref.read(appConfigProvider).webBaseUrl}/pets/${l.slug.isNotEmpty ? l.slug : l.id}';
    final price = l.isAdoption ? 'Free adoption' : formatMoney(l.priceMinor, currency: l.currency);
    Share.share('${l.title} - $price in ${l.city} on PETORA\n$url', subject: l.title);
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(petDetailProvider(widget.idOrSlug));
    final user = ref.watch(authProvider).user;
    final isSeller = user?.isSeller ?? false;
    return detail.when(
      loading: () => Scaffold(appBar: petoraAppBar(context, ''), body: const ListSkeleton(count: 4, height: 120)),
      error: (e, _) => Scaffold(
        appBar: petoraAppBar(context, 'Pet'),
        body: ErrorState(error: e, onRetry: () => ref.invalidate(petDetailProvider(widget.idOrSlug))),
      ),
      data: (l) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _recordView(l));
        final fav = ref.watch(favouriteOverridesProvider.select((m) => m[l.id] ?? l.isFavourite));
        final unavailable = l.availability == 'sold' || l.availability == 'unavailable';
        return Scaffold(
          appBar: AppBar(
            actions: [
              IconButton(
                tooltip: fav ? 'Remove from favourites' : 'Save to favourites',
                icon: Icon(fav ? Icons.favorite : Icons.favorite_border, color: fav ? context.pc.accent : null),
                onPressed: () async {
                  if (!await ensureSignedIn(context, ref, reason: 'Sign in to save pets')) {
                    return;
                  }
                  final ok = await ref.read(favouriteOverridesProvider.notifier).toggle(l);
                  if (!ok && context.mounted) {
                    showSnack(context, 'Could not update favourites.', error: true);
                  }
                },
              ),
              IconButton(tooltip: 'Share', icon: const Icon(Icons.share_outlined), onPressed: () => _share(l)),
              PopupMenuButton<String>(
                tooltip: 'More',
                onSelected: (v) async {
                  if (v == 'report') {
                    if (!await ensureSignedIn(context, ref, reason: 'Sign in to report')) {
                      return;
                    }
                    if (context.mounted) {
                      showReportSheet(context, ref, targetType: 'listing', targetId: l.id);
                    }
                  }
                },
                itemBuilder: (_) => const [PopupMenuItem(value: 'report', child: Text('Report this listing'))],
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: () async => ref.refresh(petDetailProvider(widget.idOrSlug).future),
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                ImageGallery(
                  images: l.images.isNotEmpty
                      ? l.images
                      : [
                          if (l.cover != null)
                            Img(medium: l.cover!.medium, large: l.cover!.large, thumb: l.cover!.thumb),
                        ],
                  iconSlug: l.category?.slug,
                ),
                Padding(
                  padding: const EdgeInsets.all(PSpace.gutter),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: PriceLabel(
                              minor: l.priceMinor,
                              currency: l.currency,
                              adoption: l.isAdoption,
                              size: 24,
                            ),
                          ),
                          StatusBadge.status(l.availability),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(l.title, style: context.tt.titleLarge),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          MiniChip(formatAge(l.ageMonths), icon: Icons.cake_outlined),
                          if (l.gender != 'unknown') MiniChip(genderLabel(l.gender), icon: Icons.wc),
                          if (l.breed != null) MiniChip(l.breed!.name, icon: Icons.pets),
                          if (l.category != null) MiniChip(l.category!.name),
                          if (l.colour.isNotEmpty) MiniChip(l.colour, icon: Icons.palette_outlined),
                          if (l.isAdoption) const MiniChip('Adoption', icon: Icons.volunteer_activism_outlined),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(Icons.place_outlined, size: 16, color: context.pc.textMuted),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              l.location,
                              style: context.tt.bodyMedium?.copyWith(color: context.pc.textMuted),
                            ),
                          ),
                          Text(
                            '${l.viewsCount} views',
                            style: context.tt.bodySmall?.copyWith(color: context.pc.textMuted),
                          ),
                        ],
                      ),
                      if (unavailable) ...[
                        const SizedBox(height: 12),
                        InfoBanner(
                          'This pet is ${l.availability == 'sold' ? 'no longer available' : 'currently unavailable'}.',
                          tone: BannerTone.warning,
                        ),
                      ],
                      const SizedBox(height: PSpace.xl),
                      _HealthSection(listing: l),
                      if (l.description.isNotEmpty) ...[
                        const SizedBox(height: PSpace.xl),
                        Text('About', style: context.tt.titleMedium),
                        const SizedBox(height: 6),
                        Text(l.description, style: context.tt.bodyLarge),
                      ],
                      if (l.attributes.isNotEmpty) ...[
                        const SizedBox(height: PSpace.xl),
                        Text('Details', style: context.tt.titleMedium),
                        const SizedBox(height: 4),
                        for (final e in l.attributes.entries) InfoRow(titleCase(e.key), e.value),
                      ],
                      const SizedBox(height: PSpace.xl),
                      _SellerCard(listing: l),
                      const SizedBox(height: PSpace.lg),
                      if (!isSeller) _ContactPanel(listing: l, onUnlock: () => _unlock(l)),
                      if (l.disclaimer.isNotEmpty) ...[
                        const SizedBox(height: PSpace.lg),
                        InfoBanner(l.disclaimer, icon: Icons.health_and_safety_outlined),
                      ],
                    ],
                  ),
                ),
                _Similar(id: l.id),
                const SizedBox(height: 100),
              ],
            ),
          ),
          bottomNavigationBar: (isSeller || unavailable)
              ? null
              : SafeArea(
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(PSpace.gutter, 10, PSpace.gutter, 10),
                    decoration: BoxDecoration(
                      color: context.pc.surface,
                      border: Border(top: BorderSide(color: context.pc.border)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: PButton(
                            l.contactUnlocked ? 'View contact' : 'Unlock contact',
                            icon: l.contactUnlocked ? Icons.lock_open : Icons.lock_outline,
                            kind: PButtonKind.accent,
                            onPressed: () => _unlock(l),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: PButton(
                            'Enquire',
                            icon: Icons.chat_bubble_outline,
                            kind: PButtonKind.outline,
                            onPressed: () => _enquire(l),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }
}

class _HealthSection extends StatelessWidget {
  const _HealthSection({required this.listing});
  final Listing listing;
  @override
  Widget build(BuildContext context) {
    final l = listing;
    String yn(bool? v) => v == null ? 'Not stated' : (v ? 'Yes' : 'No');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(PSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.vaccines_outlined, size: PIcon.md, color: context.cs.primary),
                const SizedBox(width: 8),
                Expanded(child: Text('Health & vaccination', style: context.tt.titleMedium)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Declared by the seller. PETORA has not verified these details.',
              style: context.tt.bodySmall?.copyWith(color: context.pc.textMuted),
            ),
            const SizedBox(height: 8),
            InfoRow(
              'Vaccinations',
              {'complete': 'Complete', 'partial': 'Partial', 'none': 'None'}[l.vaccinationStatus] ?? 'Not disclosed',
            ),
            InfoRow('Dewormed', yn(l.dewormed)),
            InfoRow('Microchipped', yn(l.microchipped)),
            if (l.vaccinationNotes.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(l.vaccinationNotes, style: context.tt.bodyMedium),
            ],
            if (l.healthNotes.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(l.healthNotes, style: context.tt.bodyMedium),
            ],
            const SizedBox(height: 6),
            Text(
              'We recommend a vet check before you commit to any pet.',
              style: context.tt.bodySmall?.copyWith(color: context.pc.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _SellerCard extends StatelessWidget {
  const _SellerCard({required this.listing});
  final Listing listing;
  @override
  Widget build(BuildContext context) {
    final s = listing.sellerProfile ?? listing.seller;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: s.slug.isEmpty ? null : () => context.push('/s/${s.slug}'),
        child: Padding(
          padding: const EdgeInsets.all(PSpace.md),
          child: Row(
            children: [
              PAvatar(url: s.logoUrl, name: s.displayName, size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.displayName, style: context.tt.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(
                      s.location,
                      style: context.tt.bodySmall?.copyWith(color: context.pc.textMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    s.verified ? const VerifiedBadge() : const StatusBadge('Seller not verified', tone: Tone.neutral),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: context.pc.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Locked / unlocked contact summary. Contact data is NEVER present here - it only comes from the
/// authorised unlock endpoint on the contact screen.
class _ContactPanel extends StatelessWidget {
  const _ContactPanel({required this.listing, required this.onUnlock});
  final Listing listing;
  final VoidCallback onUnlock;
  @override
  Widget build(BuildContext context) {
    final unlocked = listing.contactUnlocked;
    return Container(
      padding: const EdgeInsets.all(PSpace.lg),
      decoration: BoxDecoration(
        color: unlocked ? context.pc.successBg : context.cs.primaryContainer.withValues(alpha: 0.5),
        borderRadius: PRadius.cardR,
        border: Border.all(color: unlocked ? context.pc.success : context.cs.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(
            unlocked ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
            color: unlocked ? context.pc.success : context.cs.primary,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(unlocked ? 'Seller contact unlocked' : 'Seller contact is locked', style: context.tt.titleSmall),
                const SizedBox(height: 2),
                Text(
                  unlocked
                      ? 'Tap to see phone, WhatsApp and email.'
                      : '+91 ••••• •••••  ·  ••••@••••.com\nUnlock with a PETORA membership.',
                  style: context.tt.bodySmall?.copyWith(color: context.pc.textMuted),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onUnlock, child: Text(unlocked ? 'View' : 'Unlock')),
        ],
      ),
    );
  }
}

class _Similar extends ConsumerWidget {
  const _Similar({required this.id});
  final String id;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = ref.watch(similarProvider(id));
    return v.maybeWhen(
      data: (l) => l.isEmpty
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader('Similar pets'),
                ListingStrip(items: l),
              ],
            ),
      orElse: () => const SizedBox.shrink(),
    );
  }
}
