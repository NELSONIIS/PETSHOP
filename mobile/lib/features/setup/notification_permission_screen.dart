import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/auth.dart';
import '../../state/providers.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/buttons.dart';
import '../common.dart';

/// Explains why notifications are useful and records the preference on the buyer profile.
/// NOTE: OS-level push registration (FCM) is not integrated - the backend has no push gateway yet -
/// so this stores the preference only; in-app notifications are always available.
class NotificationPermissionScreen extends ConsumerStatefulWidget {
  const NotificationPermissionScreen({super.key});
  @override
  ConsumerState<NotificationPermissionScreen> createState() => _NotificationPermissionScreenState();
}

class _NotificationPermissionScreenState extends ConsumerState<NotificationPermissionScreen> {
  bool _busy = false;

  Future<void> _choose(bool allow) async {
    setState(() => _busy = true);
    try {
      final user = ref.read(authProvider).user;
      if (user != null && user.isBuyer) {
        final repo = ref.read(buyerRepoProvider);
        final p = await repo.profile();
        await repo.saveProfile(p.copyWith(notifyPush: allow));
      }
    } catch (_) {
      /* preference can be changed later in Privacy settings */
    }
    if (mounted) context.go(homeFor(ref.read(authProvider).user));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(PSpace.xl),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(color: context.cs.primaryContainer, shape: BoxShape.circle),
                child: Icon(Icons.notifications_active_outlined, size: 56, color: context.cs.primary),
              ),
              const SizedBox(height: 28),
              Text('Stay in the loop', style: context.tt.headlineMedium, textAlign: TextAlign.center),
              const SizedBox(height: 10),
              Text(
                'Get told when a seller replies to your enquiry or when a pet you saved changes. You can change this any time in Privacy settings.',
                style: context.tt.bodyLarge?.copyWith(color: context.pc.textMuted),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              PButton('Turn on notifications', loading: _busy, onPressed: () => _choose(true)),
              PButton('Not now', kind: PButtonKind.ghost, onPressed: _busy ? null : () => _choose(false)),
            ],
          ),
        ),
      ),
    );
  }
}
