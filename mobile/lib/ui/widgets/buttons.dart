import 'package:flutter/material.dart';

import '../tokens.dart';

enum PButtonKind { primary, secondary, outline, destructive, ghost, accent }

/// One button for the whole app. While [loading] it ignores taps (prevents duplicate submissions).
class PButton extends StatelessWidget {
  const PButton(
    this.label, {
    super.key,
    this.onPressed,
    this.kind = PButtonKind.primary,
    this.icon,
    this.loading = false,
    this.expand = true,
    this.small = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final PButtonKind kind;
  final IconData? icon;
  final bool loading, expand, small;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final pc = context.pc;
    final enabled = onPressed != null && !loading;
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
        else if (icon != null)
          Icon(icon, size: PIcon.md),
        if (loading || icon != null) const SizedBox(width: 8),
        Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
      ],
    );
    final size = Size(small ? 48 : 64, small ? 48 : 52);
    Widget b;
    switch (kind) {
      case PButtonKind.primary:
        b = FilledButton(
          onPressed: enabled ? onPressed : null,
          style: FilledButton.styleFrom(minimumSize: size),
          child: child,
        );
      case PButtonKind.accent:
        b = FilledButton(
          onPressed: enabled ? onPressed : null,
          style: FilledButton.styleFrom(minimumSize: size, backgroundColor: pc.accent, foregroundColor: Colors.white),
          child: child,
        );
      case PButtonKind.secondary:
        b = FilledButton(
          onPressed: enabled ? onPressed : null,
          style: FilledButton.styleFrom(
            minimumSize: size,
            backgroundColor: cs.primaryContainer,
            foregroundColor: cs.onPrimaryContainer,
          ),
          child: child,
        );
      case PButtonKind.destructive:
        b = FilledButton(
          onPressed: enabled ? onPressed : null,
          style: FilledButton.styleFrom(minimumSize: size, backgroundColor: cs.error, foregroundColor: cs.onError),
          child: child,
        );
      case PButtonKind.outline:
        b = OutlinedButton(
          onPressed: enabled ? onPressed : null,
          style: OutlinedButton.styleFrom(minimumSize: size),
          child: child,
        );
      case PButtonKind.ghost:
        b = TextButton(
          onPressed: enabled ? onPressed : null,
          style: TextButton.styleFrom(minimumSize: size),
          child: child,
        );
    }
    return expand ? SizedBox(width: double.infinity, child: b) : b;
  }
}
