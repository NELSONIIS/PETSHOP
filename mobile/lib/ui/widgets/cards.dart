import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../models/billing.dart';
import '../../models/engagement.dart';
import '../../models/listing.dart';
import '../tokens.dart';
import 'badges.dart';
import 'buttons.dart';
import 'net_image.dart';

/// Grid/list card for a listing (4:3 cover, price, chips, verified badge, favourite heart).
class ListingCard extends StatelessWidget {
  const ListingCard({super.key, required this.listing, required this.onTap, this.onFavourite, this.showStatus = false});
  final Listing listing;
  final VoidCallback onTap;
  final VoidCallback? onFavourite;
  final bool showStatus;

  @override
  Widget build(BuildContext context) {
    final l = listing;
    final unavailable = l.availability == 'sold' || l.availability == 'unavailable';
    return Semantics(
      button: true,
      label: '${l.title}, ${l.isAdoption ? 'free adoption' : formatMoney(l.priceMinor)}, ${l.location}',
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 4 / 3,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    PNetImage(l.cover?.best, iconSlug: l.category?.slug),
                    if (unavailable)
                      Container(
                        color: Colors.black45,
                        alignment: Alignment.center,
                        child: Text(
                          titleCase(l.availability),
                          style: context.tt.titleSmall?.copyWith(color: Colors.white),
                        ),
                      ),
                    if (l.featured)
                      Positioned(
                        left: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(color: context.pc.accent, borderRadius: PRadius.chipR),
                          child: Text('Featured', style: context.tt.labelSmall?.copyWith(color: Colors.white)),
                        ),
                      ),
                    if (onFavourite != null)
                      Positioned(
                        right: 2,
                        top: 2,
                        child: IconButton(
                          tooltip: l.isFavourite ? 'Remove from favourites' : 'Save to favourites',
                          onPressed: onFavourite,
                          style: IconButton.styleFrom(backgroundColor: Colors.white70, minimumSize: const Size(40, 40)),
                          icon: Icon(
                            l.isFavourite ? Icons.favorite : Icons.favorite_border,
                            size: 20,
                            color: l.isFavourite ? context.pc.accent : Colors.black87,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PriceLabel(minor: l.priceMinor, currency: l.currency, adoption: l.isAdoption),
                    const SizedBox(height: 2),
                    Text(l.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.titleSmall),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        MiniChip(formatAge(l.ageMonths)),
                        if (l.gender != 'unknown') MiniChip(genderLabel(l.gender)),
                        if (showStatus && l.status.isNotEmpty) StatusBadge.status(l.status),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.place_outlined, size: 13, color: context.pc.textMuted),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Text(
                            l.distanceKm != null ? '${l.city} · ${l.distanceKm!.toStringAsFixed(0)} km' : l.location,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.tt.bodySmall?.copyWith(color: context.pc.textMuted),
                          ),
                        ),
                        if (l.seller.verified) const VerifiedBadge(compact: true),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Height of a [ListingCard] for a given tile width and text scale: 4:3 cover + text block that grows with
/// the user's font size (so large accessibility text never overflows).
double listingCardHeight(double tileWidth, double textScale) {
  final s = textScale.clamp(0.8, 3.0);
  final wrapSlack = (tileWidth / s) < 100 ? 20 * s : 0; // chips may wrap onto a second line
  return tileWidth * 0.75 + 42 + 72 * s + wrapSlack;
}

double textScaleOf(BuildContext context) => MediaQuery.textScalerOf(context).scale(14) / 14;

/// Fixed-count grid whose row height follows the real tile width and the text scale.
SliverGridDelegate listingGridDelegate(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  final cols = ((width - 32) / 190).floor().clamp(2, 6);
  const gap = 12.0;
  final tile = (width - 32 - gap * (cols - 1)) / cols;
  return SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: cols,
    mainAxisSpacing: gap,
    crossAxisSpacing: gap,
    mainAxisExtent: listingCardHeight(tile, textScaleOf(context)),
  );
}

class CategoryTile extends StatelessWidget {
  const CategoryTile({super.key, required this.category, required this.onTap, this.selected = false});
  final Category category;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: category.name,
      child: InkWell(
        onTap: onTap,
        borderRadius: PRadius.cardR,
        child: Container(
          width: 76,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: selected ? context.cs.primary : context.cs.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  categoryIcon(category.slug),
                  color: selected ? context.cs.onPrimary : context.cs.primary,
                  size: 26,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                category.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.tt.labelMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.actionLabel, this.onAction, this.padding});
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry? padding;
  @override
  Widget build(BuildContext context) => Padding(
    padding: padding ?? const EdgeInsets.fromLTRB(PSpace.gutter, 18, PSpace.gutter, 6),
    child: Row(
      children: [
        Expanded(
          child: Semantics(header: true, child: Text(title, style: context.tt.titleMedium)),
        ),
        if (actionLabel != null) TextButton(onPressed: onAction, child: Text(actionLabel!)),
      ],
    ),
  );
}

class PlanCard extends StatelessWidget {
  const PlanCard({
    super.key,
    required this.plan,
    required this.onSelect,
    this.highlighted = false,
    this.ctaLabel = 'Choose plan',
    this.busy = false,
    this.current = false,
  });
  final Plan plan;
  final VoidCallback? onSelect;
  final bool highlighted, busy, current;
  final String ctaLabel;

  @override
  Widget build(BuildContext context) {
    final e = plan.entitlements;
    final bullets = <String>[
      if (plan.audience == 'buyer')
        e.contactUnlocks == null ? 'Unlimited seller contact unlocks' : '${e.contactUnlocks} seller contact unlocks',
      if (plan.audience == 'buyer' && e.enquiries != null) '${e.enquiries} enquiries',
      if (plan.audience == 'seller') e.listingLimit == null ? 'Unlimited listings' : 'Up to ${e.listingLimit} listings',
      if (plan.audience == 'seller' && e.analytics) 'Listing analytics',
      if (plan.audience == 'seller' && (e.featuredSlots ?? 0) > 0) '${e.featuredSlots} featured slots',
      ...plan.features,
    ];
    return Container(
      decoration: BoxDecoration(
        color: context.pc.surface,
        borderRadius: PRadius.cardR,
        border: Border.all(color: highlighted ? context.cs.primary : context.pc.border, width: highlighted ? 2 : 1),
      ),
      padding: const EdgeInsets.all(PSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(plan.name, style: context.tt.titleMedium)),
              if (current) const StatusBadge('Current', tone: Tone.brand),
              if (highlighted && !current) const StatusBadge('Popular', tone: Tone.brand),
            ],
          ),
          if (plan.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(plan.description, style: context.tt.bodySmall?.copyWith(color: context.pc.textMuted)),
            ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (plan.hasPromo) ...[
                PriceLabel(minor: plan.priceMinor, currency: plan.currency, size: 14, strike: true),
                const SizedBox(width: 8),
              ],
              PriceLabel(minor: plan.effectivePriceMinor, currency: plan.currency, size: 26),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  '/ ${plan.periodLabel}',
                  style: context.tt.bodySmall?.copyWith(color: context.pc.textMuted),
                ),
              ),
            ],
          ),
          if (plan.taxRateBps > 0)
            Text(
              '+ ${(plan.taxRateBps / 100).toStringAsFixed(plan.taxRateBps % 100 == 0 ? 0 : 1)}% tax · pay ${formatMoney(plan.totalMinor, currency: plan.currency)}',
              style: context.tt.bodySmall?.copyWith(color: context.pc.textMuted),
            ),
          const SizedBox(height: 10),
          for (final b in bullets)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_circle, size: 16, color: context.cs.primary),
                  const SizedBox(width: 8),
                  Expanded(child: Text(b, style: context.tt.bodyMedium)),
                ],
              ),
            ),
          const SizedBox(height: 12),
          PButton(
            ctaLabel,
            onPressed: onSelect,
            loading: busy,
            kind: highlighted ? PButtonKind.primary : PButtonKind.secondary,
          ),
        ],
      ),
    );
  }
}

class EnquiryCard extends StatelessWidget {
  const EnquiryCard({super.key, required this.enquiry, required this.onTap, this.sellerView = false});
  final Enquiry enquiry;
  final VoidCallback onTap;
  final bool sellerView;
  @override
  Widget build(BuildContext context) {
    final e = enquiry;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 64, height: 64, child: PNetImage(e.cover?.small, radius: 10)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            e.listingTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.tt.titleSmall,
                          ),
                        ),
                        Text(
                          timeAgo(e.lastMessageAt),
                          style: context.tt.bodySmall?.copyWith(color: context.pc.textMuted),
                        ),
                      ],
                    ),
                    Text(
                      sellerView ? 'From ${e.counterpartyName}' : e.counterpartyName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.tt.bodySmall?.copyWith(color: context.pc.textMuted),
                    ),
                    const SizedBox(height: 4),
                    Text(e.lastMessage, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.tt.bodyMedium),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        StatusBadge.status(e.status),
                        const Spacer(),
                        if (e.unread > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: context.pc.accent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text('${e.unread}', style: context.tt.labelSmall?.copyWith(color: Colors.white)),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.bold = false});
  final String label, value;
  final bool bold;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: Text(label, style: context.tt.bodyMedium?.copyWith(color: context.pc.textMuted)),
        ),
        Expanded(
          flex: 6,
          child: Text(value, textAlign: TextAlign.end, style: bold ? context.tt.titleSmall : context.tt.bodyMedium),
        ),
      ],
    ),
  );
}

class MenuTile extends StatelessWidget {
  const MenuTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
    this.danger = false,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool danger;
  @override
  Widget build(BuildContext context) {
    final c = danger ? context.cs.error : context.cs.onSurface;
    return ListTile(
      onTap: onTap,
      minTileHeight: 52,
      leading: Icon(icon, color: danger ? c : context.cs.primary, size: PIcon.lg),
      title: Text(
        title,
        style: context.tt.bodyLarge?.copyWith(color: c, fontWeight: FontWeight.w500),
      ),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, style: context.tt.bodySmall?.copyWith(color: context.pc.textMuted)),
      trailing: trailing ?? (onTap == null ? null : Icon(Icons.chevron_right, color: context.pc.textMuted)),
    );
  }
}
