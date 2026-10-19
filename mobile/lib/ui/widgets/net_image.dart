import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../tokens.dart';

IconData categoryIcon(String? slugOrIcon) {
  switch ((slugOrIcon ?? '').toLowerCase()) {
    case 'dog':
    case 'dogs':
      return Icons.pets;
    case 'cat':
    case 'cats':
      return Icons.cruelty_free;
    case 'bird':
    case 'birds':
      return Icons.flutter_dash;
    case 'fish':
    case 'aquatic':
      return Icons.set_meal;
    case 'rabbit':
    case 'rabbits':
    case 'small-animals':
      return Icons.cruelty_free;
    case 'reptile':
    case 'reptiles':
      return Icons.bug_report_outlined;
  }
  return Icons.pets;
}

/// Cached network image with a tinted category-icon placeholder (no stock photos are bundled).
class PNetImage extends StatelessWidget {
  const PNetImage(this.url, {super.key, this.fit = BoxFit.cover, this.iconSlug, this.radius, this.memCacheWidth = 600});
  final String? url;
  final BoxFit fit;
  final String? iconSlug;
  final double? radius;
  final int? memCacheWidth;

  @override
  Widget build(BuildContext context) {
    final ph = Container(
      color: context.cs.primaryContainer.withValues(alpha: 0.6),
      alignment: Alignment.center,
      child: Icon(categoryIcon(iconSlug), color: context.cs.primary.withValues(alpha: 0.55), size: 36),
    );
    Widget w = (url == null || url!.isEmpty)
        ? ph
        : CachedNetworkImage(
            imageUrl: url!,
            fit: fit,
            memCacheWidth: memCacheWidth,
            fadeInDuration: const Duration(milliseconds: 150),
            placeholder: (_, _) => Container(color: context.pc.border),
            errorWidget: (_, _, _) => ph,
          );
    if (radius != null) {
      w = ClipRRect(borderRadius: BorderRadius.circular(radius!), child: w);
    }
    return w;
  }
}

class PAvatar extends StatelessWidget {
  const PAvatar({super.key, this.url, required this.name, this.size = 40});
  final String? url;
  final String name;
  final double size;
  @override
  Widget build(BuildContext context) {
    final initials = name.trim().isEmpty
        ? '?'
        : name.trim().split(RegExp(r'\s+')).take(2).map((e) => e[0].toUpperCase()).join();
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: (url != null && url!.isNotEmpty)
            ? CachedNetworkImage(
                imageUrl: url!,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => _fallback(context, initials),
              )
            : _fallback(context, initials),
      ),
    );
  }

  Widget _fallback(BuildContext context, String initials) => Container(
    color: context.cs.primaryContainer,
    alignment: Alignment.center,
    child: Text(
      initials,
      style: context.tt.labelLarge?.copyWith(color: context.cs.primary, fontSize: size * 0.36),
    ),
  );
}
