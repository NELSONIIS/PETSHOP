import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../tokens.dart';

enum Tone { neutral, success, warning, danger, info, brand }

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.label, {super.key, this.tone = Tone.neutral, this.icon});
  final String label;
  final Tone tone;
  final IconData? icon;

  static Tone toneFor(String status) {
    switch (status) {
      case 'approved':
      case 'active':
      case 'succeeded':
      case 'responded':
      case 'resolved':
      case 'available':
        return Tone.success;
      case 'pending':
      case 'grace':
      case 'reserved':
      case 'viewed':
      case 'under_review':
      case 'open':
      case 'created':
        return Tone.warning;
      case 'rejected':
      case 'failed':
      case 'suspended':
      case 'reported':
      case 'cancelled':
        return Tone.danger;
      case 'draft':
      case 'closed':
      case 'expired':
      case 'sold':
      case 'unavailable':
        return Tone.neutral;
    }
    return Tone.info;
  }

  factory StatusBadge.status(String status) => StatusBadge(titleCase(status), tone: toneFor(status));

  @override
  Widget build(BuildContext context) {
    final pc = context.pc;
    final (bg, fg) = switch (tone) {
      Tone.success => (pc.successBg, pc.success),
      Tone.warning => (pc.warningBg, pc.warning),
      Tone.danger => (pc.dangerBg, pc.danger),
      Tone.info => (pc.infoBg, pc.info),
      Tone.brand => (context.cs.primaryContainer, context.cs.primary),
      Tone.neutral => (context.cs.surfaceContainerHighest, pc.textMuted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: PRadius.chipR),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: fg), const SizedBox(width: 3)],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.tt.labelSmall?.copyWith(color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Verified seller" - shown ONLY when the backend says an admin approved the seller's documents.
class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key, this.compact = false});
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final c = context.pc.secondary;
    return Semantics(
      label: 'Verified seller',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified, size: compact ? 14 : 16, color: c),
          if (!compact) ...[
            const SizedBox(width: 3),
            Text('Verified seller', style: context.tt.labelSmall?.copyWith(color: c)),
          ],
        ],
      ),
    );
  }
}

class PriceLabel extends StatelessWidget {
  const PriceLabel({
    super.key,
    required this.minor,
    this.currency = 'INR',
    this.adoption = false,
    this.size = 16,
    this.strike = false,
  });
  final int minor;
  final String currency;
  final bool adoption, strike;
  final double size;

  @override
  Widget build(BuildContext context) {
    final free = adoption || minor == 0;
    final text = adoption ? 'Free adoption' : (minor == 0 ? 'Free' : formatMoney(minor, currency: currency));
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: PType.price.copyWith(
        fontSize: size,
        color: strike ? context.pc.textMuted : (free ? context.pc.success : context.cs.onSurface),
        decoration: strike ? TextDecoration.lineThrough : null,
      ),
    );
  }
}

class MiniChip extends StatelessWidget {
  const MiniChip(this.label, {super.key, this.icon});
  final String label;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(color: context.cs.surfaceContainerHighest, borderRadius: PRadius.chipR),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 12, color: context.pc.textMuted), const SizedBox(width: 3)],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.tt.labelSmall?.copyWith(color: context.pc.textMuted, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    ),
  );
}
