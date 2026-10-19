import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/errors.dart';
import '../models/common.dart';
import '../state/auth.dart';
import '../ui/tokens.dart';
import '../ui/widgets/buttons.dart';
import '../ui/widgets/dialogs.dart';

String homeFor(User? u) {
  if (u == null) return '/';
  if (u.isSeller) return '/sell';
  if (u.isStaff) return '/staff';
  return '/';
}

/// Returns true if signed in; otherwise offers sign in / register and returns false.
Future<bool> ensureSignedIn(BuildContext context, WidgetRef ref, {String reason = 'Sign in to continue'}) async {
  if (ref.read(authProvider).isAuthed) return true;
  final from = GoRouterState.of(context).uri.toString();
  await showPetoraSheet<void>(
    context,
    builder: (ctx) => SheetScaffold(
      title: reason,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Browsing is always free. You need a free account to save pets, unlock seller contacts and send enquiries.',
            style: ctx.tt.bodyMedium?.copyWith(color: ctx.pc.textMuted),
          ),
          const SizedBox(height: PSpace.lg),
          PButton(
            'Sign in',
            onPressed: () {
              Navigator.pop(ctx);
              context.push('/login?from=${Uri.encodeComponent(from)}');
            },
          ),
          const SizedBox(height: 8),
          PButton(
            'Create account',
            kind: PButtonKind.outline,
            onPressed: () {
              Navigator.pop(ctx);
              context.push('/register?from=${Uri.encodeComponent(from)}');
            },
          ),
        ],
      ),
    ),
  );
  return false;
}

/// Common handling for failed user actions (verification needed, session, etc.).
void handleActionError(BuildContext context, Object e) {
  if (e is AppException && e.kind == ErrorKind.verificationRequired) {
    showPetoraSheet<void>(
      context,
      builder: (ctx) => SheetScaffold(
        title: 'Verify your email',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'For everyone\'s safety, please verify your email address before continuing.',
              style: ctx.tt.bodyMedium,
            ),
            const SizedBox(height: PSpace.lg),
            PButton(
              'Enter verification code',
              onPressed: () {
                Navigator.pop(ctx);
                context.push('/verify-email');
              },
            ),
          ],
        ),
      ),
    );
    return;
  }
  showError(context, e);
}

/// Applies server-side field errors (validation_failed) to a map the form can display.
Map<String, String> fieldErrorsOf(Object e) => e is AppException ? e.fieldErrors : const {};

String? fieldError(Map<String, String> errs, String field) => errs[field];

extension WidgetRefHelpers on WidgetRef {
  bool get isAuthed => read(authProvider).isAuthed;
  User? get currentUser => read(authProvider).user;
}
