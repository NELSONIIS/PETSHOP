import 'package:flutter/material.dart';

import '../../core/errors.dart';
import '../tokens.dart';
import 'buttons.dart';

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool destructive = false,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: ctx.cs.error, foregroundColor: ctx.cs.onError)
              : null,
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return r ?? false;
}

Future<T?> showPetoraSheet<T>(
  BuildContext context, {
  required Widget Function(BuildContext) builder,
  bool full = false,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  constraints: full ? null : BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9),
  builder: (ctx) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
    child: builder(ctx),
  ),
);

void showSnack(
  BuildContext context,
  String message, {
  bool error = false,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(
            error ? Icons.error_outline : Icons.check_circle_outline,
            size: 18,
            color: error ? const Color(0xFFFFB4A9) : const Color(0xFF8FE0B4),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
      action: actionLabel == null ? null : SnackBarAction(label: actionLabel, onPressed: onAction ?? () {}),
    ),
  );
}

void showError(BuildContext context, Object error) => showSnack(
  context,
  error is AppException ? error.userMessage : 'Something went wrong. Please try again.',
  error: true,
);

/// Sheet body with a title and consistent padding.
class SheetScaffold extends StatelessWidget {
  const SheetScaffold({super.key, required this.title, required this.child, this.actions});
  final String title;
  final Widget child;
  final List<Widget>? actions;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(PSpace.gutter, 0, PSpace.gutter, PSpace.lg),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: context.tt.titleLarge),
        const SizedBox(height: PSpace.md),
        child,
        if (actions != null) ...[const SizedBox(height: PSpace.lg), ...actions!],
      ],
    ),
  );
}

/// Radio-style chooser in a sheet; returns the selected key or null.
Future<String?> pickOne(
  BuildContext context, {
  required String title,
  required Map<String, String> options,
  String? selected,
}) => showPetoraSheet<String>(
  context,
  builder: (ctx) => SheetScaffold(
    title: title,
    child: Column(
      children: [
        for (final e in options.entries)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(e.value),
            trailing: e.key == selected ? Icon(Icons.check, color: ctx.cs.primary) : null,
            onTap: () => Navigator.pop(ctx, e.key),
          ),
        const SizedBox(height: 4),
        PButton('Cancel', kind: PButtonKind.ghost, onPressed: () => Navigator.pop(ctx)),
      ],
    ),
  ),
);
