import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../tokens.dart';
import 'buttons.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.actionLabel, this.onAction});
  final IconData icon;
  final String title;
  final String? message, actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(PSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: context.cs.primaryContainer, shape: BoxShape.circle),
              child: Icon(icon, size: 30, color: context.cs.primary),
            ),
            const SizedBox(height: PSpace.lg),
            Text(title, style: context.tt.titleMedium, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                style: context.tt.bodyMedium?.copyWith(color: context.pc.textMuted),
                textAlign: TextAlign.center,
              ),
            ],
            if (actionLabel != null) ...[
              const SizedBox(height: PSpace.lg),
              PButton(actionLabel!, onPressed: onAction, expand: false),
            ],
          ],
        ),
      ),
    );
  }
}

/// Friendly error with a Retry button. Network errors get their own icon/text.
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.error, this.onRetry, this.compact = false});
  final Object error;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final e = error is AppException ? error as AppException : null;
    final net = e?.isNetwork ?? false;
    final msg = e?.userMessage ?? 'Something went wrong. Please try again.';
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(PSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              net ? Icons.wifi_off_rounded : Icons.error_outline_rounded,
              size: compact ? 32 : 48,
              color: context.pc.textMuted,
            ),
            const SizedBox(height: PSpace.md),
            Text(
              net ? "You're offline" : 'Something went wrong',
              style: context.tt.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              msg,
              style: context.tt.bodyMedium?.copyWith(color: context.pc.textMuted),
              textAlign: TextAlign.center,
            ),
            if (e?.requestId != null) ...[
              const SizedBox(height: 4),
              Text('Ref: ${e!.requestId}', style: context.tt.bodySmall?.copyWith(color: context.pc.textMuted)),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: PSpace.lg),
              PButton('Try again', onPressed: onRetry, icon: Icons.refresh, expand: false, kind: PButtonKind.outline),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shimmer-style placeholder block.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.width, this.height = 14, this.radius = 8});
  final double? width;
  final double height, radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = context.pc.border;
    final hi = Color.lerp(base, context.cs.surface, 0.6)!;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          gradient: LinearGradient(
            colors: [base, hi, base],
            stops: [(_c.value - 0.3).clamp(0, 1), _c.value, (_c.value + 0.3).clamp(0, 1)],
          ),
        ),
      ),
    );
  }
}

class ListingCardSkeleton extends StatelessWidget {
  const ListingCardSkeleton({super.key});
  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          AspectRatio(
            aspectRatio: 4 / 3,
            child: Skeleton(radius: 0, height: double.infinity),
          ),
          Padding(
            padding: EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Skeleton(width: 80, height: 16),
                SizedBox(height: 8),
                Skeleton(height: 12),
                SizedBox(height: 6),
                Skeleton(width: 100, height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class GridSkeleton extends StatelessWidget {
  const GridSkeleton({super.key, this.count = 6});
  final int count;
  @override
  Widget build(BuildContext context) => GridView.builder(
    padding: const EdgeInsets.all(PSpace.gutter),
    physics: const NeverScrollableScrollPhysics(),
    shrinkWrap: true,
    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 240,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      mainAxisExtent: 238,
    ),
    itemCount: count,
    itemBuilder: (_, _) => const ListingCardSkeleton(),
  );
}

class ListSkeleton extends StatelessWidget {
  const ListSkeleton({super.key, this.count = 5, this.height = 72});
  final int count;
  final double height;
  @override
  Widget build(BuildContext context) => ListView.separated(
    padding: const EdgeInsets.all(PSpace.gutter),
    physics: const NeverScrollableScrollPhysics(),
    shrinkWrap: true,
    itemCount: count,
    separatorBuilder: (_, _) => const SizedBox(height: 10),
    itemBuilder: (_, _) => Skeleton(height: height, radius: PRadius.card),
  );
}

class LoadMoreFooter extends StatelessWidget {
  const LoadMoreFooter({super.key, required this.loading, required this.hasMore, required this.onLoadMore, this.error});
  final bool loading, hasMore;
  final VoidCallback onLoadMore;
  final Object? error;

  @override
  Widget build(BuildContext context) {
    if (!hasMore) return const SizedBox(height: 24);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: loading
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.4))
            : PButton(
                error != null ? 'Retry loading more' : 'Load more',
                onPressed: onLoadMore,
                kind: PButtonKind.outline,
                expand: false,
                small: true,
              ),
      ),
    );
  }
}

class TestModeBanner extends StatelessWidget {
  const TestModeBanner({super.key});
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: context.pc.warningBg,
      borderRadius: PRadius.fieldR,
      border: Border.all(color: context.pc.warning),
    ),
    child: Row(
      children: [
        Icon(Icons.science_outlined, size: PIcon.md, color: context.pc.warning),
        const SizedBox(width: 8),
        Expanded(
          child: Text('TEST MODE – no real charge', style: context.tt.labelMedium?.copyWith(color: context.pc.warning)),
        ),
      ],
    ),
  );
}

class InfoBanner extends StatelessWidget {
  const InfoBanner(this.message, {super.key, this.tone = BannerTone.info, this.icon, this.action});
  final String message;
  final BannerTone tone;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final pc = context.pc;
    final (bg, fg) = switch (tone) {
      BannerTone.info => (pc.infoBg, pc.info),
      BannerTone.warning => (pc.warningBg, pc.warning),
      BannerTone.danger => (pc.dangerBg, pc.danger),
      BannerTone.success => (pc.successBg, pc.success),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, borderRadius: PRadius.fieldR),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? Icons.info_outline, size: PIcon.md, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: context.tt.bodySmall?.copyWith(color: context.cs.onSurface, height: 1.4)),
          ),
          ?action,
        ],
      ),
    );
  }
}

enum BannerTone { info, warning, danger, success }

/// Renders AsyncValue with skeleton / error+retry / data.
class AsyncBody<T> extends StatelessWidget {
  const AsyncBody({super.key, required this.value, required this.data, this.onRetry, this.loading});
  final AsyncValue<T> value;
  final Widget Function(T) data;
  final VoidCallback? onRetry;
  final Widget? loading;

  @override
  Widget build(BuildContext context) {
    return value.when(
      skipLoadingOnReload: true,
      data: data,
      loading: () => loading ?? const ListSkeleton(),
      error: (e, _) => ErrorState(error: e, onRetry: onRetry),
    );
  }
}
