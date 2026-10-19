import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../models/billing.dart';
import '../../state/auth.dart';
import '../../state/data.dart';
import '../../state/providers.dart';
import '../../state/theme_mode.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/badges.dart';
import '../../ui/widgets/buttons.dart';
import '../../ui/widgets/cards.dart';
import '../../ui/widgets/dialogs.dart';
import '../../ui/widgets/fields.dart';
import '../../ui/widgets/net_image.dart';
import '../../ui/widgets/scaffolds.dart';
import '../../ui/widgets/states.dart';
import '../shell/shells.dart';

/// Profile tab for buyers (guests see sign-in prompt). Sellers use a variant in features/seller.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    if (!auth.isAuthed) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profile')),
        body: ListView(
          children: [
            const SizedBox(height: 40),
            const SignInPrompt(
              title: 'Welcome to PETORA',
              message: 'Sign in to manage favourites, enquiries and your membership.',
              icon: Icons.person_outline,
            ),
            const Divider(height: 32),
            const _AppearanceTile(),
            MenuTile(icon: Icons.help_outline, title: 'Help & support', onTap: () => context.push('/help')),
            MenuTile(icon: Icons.policy_outlined, title: 'Privacy policy', onTap: () => context.push('/legal/privacy')),
            MenuTile(icon: Icons.gavel_outlined, title: 'Terms of service', onTap: () => context.push('/legal/terms')),
          ],
        ),
      );
    }
    final u = auth.user!;
    final sub = ref.watch(subscriptionProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(PSpace.gutter),
            child: Row(
              children: [
                PAvatar(url: u.avatarUrl, name: u.name, size: 56),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(u.name, style: context.tt.titleMedium),
                      Text(u.email, style: context.tt.bodySmall?.copyWith(color: context.pc.textMuted)),
                      const SizedBox(height: 4),
                      u.emailVerified
                          ? const StatusBadge('Email verified', tone: Tone.success, icon: Icons.check)
                          : const StatusBadge('Email not verified', tone: Tone.warning),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (!u.emailVerified)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: PSpace.gutter),
              child: InfoBanner(
                'Verify your email to unlock contacts and send enquiries.',
                tone: BannerTone.warning,
                action: TextButton(onPressed: () => context.push('/verify-email'), child: const Text('Verify')),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(PSpace.gutter),
            child: _MembershipTile(sub: sub),
          ),
          MenuTile(icon: Icons.person_outline, title: 'Edit profile', onTap: () => context.push('/profile/edit')),
          MenuTile(
            icon: Icons.place_outlined,
            title: 'Location',
            subtitle: ref.watch(locationProvider).city.isEmpty ? 'Not set' : ref.watch(locationProvider).city,
            onTap: () => context.push('/setup/location'),
          ),
          MenuTile(icon: Icons.notifications_none, title: 'Notifications', onTap: () => context.push('/notifications')),
          MenuTile(
            icon: Icons.receipt_long_outlined,
            title: 'Billing & invoices',
            onTap: () => context.push('/billing'),
          ),
          MenuTile(icon: Icons.history, title: 'Recently viewed', onTap: () => context.push('/pets/recently-viewed')),
          const Divider(),
          const _AppearanceTile(),
          MenuTile(icon: Icons.lock_outline, title: 'Security', onTap: () => context.push('/profile/security')),
          MenuTile(icon: Icons.privacy_tip_outlined, title: 'Privacy', onTap: () => context.push('/profile/privacy')),
          MenuTile(icon: Icons.help_outline, title: 'Help & support', onTap: () => context.push('/help')),
          MenuTile(
            icon: Icons.logout,
            title: 'Sign out',
            onTap: () async {
              final ok = await confirmDialog(
                context,
                title: 'Sign out?',
                message: 'You can sign back in at any time.',
                confirmLabel: 'Sign out',
              );
              if (ok) await ref.read(authProvider.notifier).logout();
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _MembershipTile extends StatelessWidget {
  const _MembershipTile({required this.sub});
  final AsyncValue<SubscriptionStatus> sub;
  @override
  Widget build(BuildContext context) {
    final s = sub.asData?.value;
    final active = s?.active ?? false;
    return Material(
      color: active ? context.cs.primaryContainer : context.pc.bgWarm,
      borderRadius: PRadius.cardR,
      child: InkWell(
        borderRadius: PRadius.cardR,
        onTap: () => context.push('/membership'),
        child: Padding(
          padding: const EdgeInsets.all(PSpace.lg),
          child: Row(
            children: [
              Icon(Icons.workspace_premium_outlined, color: context.cs.primary, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(active ? s!.subscription!.planName : 'No membership', style: context.tt.titleSmall),
                    Text(
                      active
                          ? 'Active until ${formatDate(s!.subscription!.periodEnd)}${s.entitlements.remainingUnlocks != null ? ' · ${s.entitlements.remainingUnlocks} unlocks left' : ''}'
                          : (sub.isLoading ? 'Checking...' : 'Unlock seller contacts with a plan'),
                      style: context.tt.bodySmall?.copyWith(color: context.pc.textMuted),
                    ),
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

class _AppearanceTile extends ConsumerWidget {
  const _AppearanceTile();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return MenuTile(
      icon: Icons.brightness_6_outlined,
      title: 'Appearance',
      subtitle: {ThemeMode.light: 'Light', ThemeMode.dark: 'Dark', ThemeMode.system: 'Follow system'}[mode],
      onTap: () async {
        final k = await pickOne(
          context,
          title: 'Appearance',
          options: const {'light': 'Light', 'dark': 'Dark', 'system': 'Follow system'},
          selected: mode.name,
        );
        if (k != null) {
          ref.read(themeModeProvider.notifier).set(ThemeMode.values.firstWhere((m) => m.name == k));
        }
      },
    );
  }
}

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});
  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: ref.read(authProvider).user?.name);
  late final _phone = TextEditingController(text: ref.read(authProvider).user?.phone ?? '');
  bool _busy = false;
  Map<String, String> _errs = {};

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _errs = {};
    });
    try {
      final u = await ref.read(authRepoProvider).updateMe(name: _name.text.trim(), phone: _phone.text.trim());
      ref.read(authProvider.notifier).setUser(u);
      if (mounted) {
        showSnack(context, 'Profile updated');
        context.pop();
      }
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errs = e.fieldErrors;
      });
      if (e.fieldErrors.isEmpty) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => FormPage(
    title: 'Edit profile',
    bottom: PButton('Save changes', onPressed: _save, loading: _busy),
    children: [
      Form(
        key: _form,
        child: Column(
          children: [
            PTextField(
              label: 'Full name',
              controller: _name,
              validator: (v) => Validators.minLen(v, 2, 'Name'),
              errorText: _errs['name'],
            ),
            gap16,
            PTextField(
              label: 'Phone',
              controller: _phone,
              keyboard: TextInputType.phone,
              validator: (v) => Validators.phone(v, optional: true),
              errorText: _errs['phone'],
            ),
            gap16,
            PTextField(
              label: 'Email',
              initialValue: ref.read(authProvider).user?.email,
              enabled: false,
              helper: 'Contact support to change your email address',
            ),
          ],
        ),
      ),
    ],
  );
}

class SecurityScreen extends ConsumerStatefulWidget {
  const SecurityScreen({super.key});
  @override
  ConsumerState<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends ConsumerState<SecurityScreen> {
  final _form = GlobalKey<FormState>();
  final _cur = TextEditingController();
  final _new = TextEditingController();
  bool _busy = false;
  String? _curErr;

  @override
  void dispose() {
    _cur.dispose();
    _new.dispose();
    super.dispose();
  }

  Future<void> _change() async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _curErr = null;
    });
    try {
      await ref.read(authRepoProvider).changePassword(_cur.text, _new.text);
      _cur.clear();
      _new.clear();
      ref.invalidate(sessionsProvider);
      if (mounted) {
        showSnack(context, 'Password changed. Other devices were signed out.');
      }
    } on AppException catch (e) {
      if (mounted) {
        if (e.fieldErrors.containsKey('current_password')) {
          setState(() => _curErr = e.fieldErrors['current_password']);
        } else {
          showError(context, e);
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessions = ref.watch(sessionsProvider);
    return Scaffold(
      appBar: petoraAppBar(context, 'Security'),
      body: ListView(
        padding: const EdgeInsets.all(PSpace.gutter),
        children: [
          Text('Change password', style: context.tt.titleMedium),
          gap12,
          Form(
            key: _form,
            child: Column(
              children: [
                PTextField(
                  label: 'Current password',
                  controller: _cur,
                  obscure: true,
                  validator: (v) => Validators.required(v, 'Current password'),
                  errorText: _curErr,
                ),
                gap12,
                PTextField(
                  label: 'New password',
                  controller: _new,
                  obscure: true,
                  validator: Validators.password,
                  helper: 'At least 10 characters with a letter and a number',
                ),
                gap12,
                PButton('Update password', onPressed: _change, loading: _busy),
              ],
            ),
          ),
          gap24,
          Text('Signed-in devices', style: context.tt.titleMedium),
          gap8,
          sessions.when(
            loading: () => const ListSkeleton(count: 2, height: 64),
            error: (e, _) => ErrorState(error: e, compact: true, onRetry: () => ref.invalidate(sessionsProvider)),
            data: (list) => Column(
              children: [
                for (final s in list)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Icon(s.client == 'mobile' ? Icons.phone_android : Icons.language),
                      title: Text(
                        s.current
                            ? 'This device'
                            : (s.userAgent.isEmpty
                                  ? (s.client == 'mobile' ? 'PETORA app' : 'Web browser')
                                  : s.userAgent),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text('Last active ${timeAgo(s.lastUsedAt)}'),
                      trailing: s.current
                          ? const StatusBadge('Current', tone: Tone.brand)
                          : TextButton(
                              onPressed: () async {
                                try {
                                  await ref.read(authRepoProvider).revokeSession(s.id);
                                  ref.invalidate(sessionsProvider);
                                } catch (e) {
                                  if (context.mounted) showError(context, e);
                                }
                              },
                              child: const Text('Sign out'),
                            ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PrivacyScreen extends ConsumerWidget {
  const PrivacyScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final profile = ref.watch(buyerProfileProvider);
    return Scaffold(
      appBar: petoraAppBar(context, 'Privacy'),
      body: ListView(
        children: [
          if (user?.isBuyer ?? false)
            profile.when(
              loading: () => const ListSkeleton(count: 3, height: 56),
              error: (e, _) => ErrorState(error: e, compact: true, onRetry: () => ref.invalidate(buyerProfileProvider)),
              data: (p) {
                Future<void> save(p2) async {
                  try {
                    await ref.read(buyerRepoProvider).saveProfile(p2);
                    ref.invalidate(buyerProfileProvider);
                  } catch (e) {
                    if (context.mounted) showError(context, e);
                  }
                }

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Notifications', style: context.tt.titleMedium),
                      ),
                    ),
                    SwitchListTile(
                      title: const Text('Email'),
                      subtitle: const Text('Replies and account updates'),
                      value: p.notifyEmail,
                      onChanged: (v) => save(p.copyWith(notifyEmail: v)),
                    ),
                    SwitchListTile(
                      title: const Text('SMS'),
                      subtitle: const Text('Only if an SMS provider is enabled'),
                      value: p.notifySms,
                      onChanged: (v) => save(p.copyWith(notifySms: v)),
                    ),
                    SwitchListTile(
                      title: const Text('Push'),
                      subtitle: const Text('Saved preference; push delivery is not yet enabled'),
                      value: p.notifyPush,
                      onChanged: (v) => save(p.copyWith(notifyPush: v)),
                    ),
                  ],
                );
              },
            ),
          const Divider(),
          MenuTile(icon: Icons.policy_outlined, title: 'Privacy policy', onTap: () => context.push('/legal/privacy')),
          MenuTile(icon: Icons.gavel_outlined, title: 'Terms of service', onTap: () => context.push('/legal/terms')),
          MenuTile(
            icon: Icons.shield_outlined,
            title: 'Safety & responsible ownership',
            onTap: () => context.push('/legal/safety'),
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Seller contact details are only shared with members who unlock them. Your phone number and email are never shown to other users on your profile.',
            ),
          ),
          const Divider(),
          MenuTile(
            icon: Icons.delete_outline,
            title: 'Delete my account',
            subtitle: 'Permanently remove your personal data',
            danger: true,
            onTap: () => context.push('/profile/delete'),
          ),
        ],
      ),
    );
  }
}

class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});
  @override
  ConsumerState<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _form = GlobalKey<FormState>();
  final _pw = TextEditingController();
  bool _busy = false;
  String? _err;

  @override
  void dispose() {
    _pw.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    final ok = await confirmDialog(
      context,
      title: 'Delete account permanently?',
      message: 'This cannot be undone. Your profile, favourites and notifications are erased; invoices are kept as required by tax law without personal details.',
      confirmLabel: 'Delete my account',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await ref.read(authRepoProvider).deleteAccount(_pw.text);
      await ref.read(authProvider.notifier).logout();
      if (mounted) context.go('/');
    } on AppException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _err = e.fieldErrors['password'] ?? e.userMessage;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => FormPage(
    title: 'Delete account',
    bottom: PButton('Delete my account', kind: PButtonKind.destructive, onPressed: _delete, loading: _busy),
    children: [
      Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const InfoBanner(
              'Deleting your account signs you out everywhere and erases your personal data. Sellers: your listings are removed.',
              tone: BannerTone.danger,
              icon: Icons.warning_amber_rounded,
            ),
            gap16,
            if (_err != null) ...[InfoBanner(_err!, tone: BannerTone.danger), gap12],
            PTextField(
              label: 'Confirm with your password',
              controller: _pw,
              obscure: true,
              validator: (v) => Validators.required(v, 'Password'),
            ),
          ],
        ),
      ),
    ],
  );
}

/// Legal pages (terms, privacy, refund policy, safety...) rendered from simple markdown.
class LegalScreen extends ConsumerWidget {
  const LegalScreen({super.key, required this.slug});
  final String slug;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = ref.watch(legalProvider(slug));
    return Scaffold(
      appBar: petoraAppBar(context, titleCase(slug.replaceAll('-', '_'))),
      body: AsyncBody<({String title, String body})>(
        value: v,
        onRetry: () => ref.invalidate(legalProvider(slug)),
        data: (p) => ListView(
          padding: const EdgeInsets.all(PSpace.gutter),
          children: [
            Text(p.title, style: context.tt.headlineMedium),
            gap12,
            ...SimpleMarkdown.build(context, p.body),
          ],
        ),
      ),
    );
  }
}

/// Tiny markdown subset: #/##/### headings, "-"/"*" bullets, paragraphs.
class SimpleMarkdown {
  static List<Widget> build(BuildContext context, String md) {
    final out = <Widget>[];
    for (final raw in md.split('\n')) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        out.add(const SizedBox(height: 8));
      } else if (line.startsWith('### ')) {
        out.add(
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(line.substring(4), style: context.tt.titleSmall),
          ),
        );
      } else if (line.startsWith('## ')) {
        out.add(
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(line.substring(3), style: context.tt.titleMedium),
          ),
        );
      } else if (line.startsWith('# ')) {
        out.add(
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(line.substring(2), style: context.tt.titleLarge),
          ),
        );
      } else if (line.startsWith('- ') || line.startsWith('* ')) {
        out.add(
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('•  '),
                Expanded(child: Text(line.substring(2), style: context.tt.bodyMedium)),
              ],
            ),
          ),
        );
      } else {
        out.add(Text(line.replaceAll('**', ''), style: context.tt.bodyMedium));
      }
    }
    return out;
  }
}

class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return Scaffold(
      appBar: petoraAppBar(context, 'Appearance'),
      body: RadioGroup<ThemeMode>(
        groupValue: mode,
        onChanged: (m) {
          if (m != null) ref.read(themeModeProvider.notifier).set(m);
        },
        child: ListView(
          children: const [
            RadioListTile<ThemeMode>(title: Text('Light'), subtitle: Text('Default'), value: ThemeMode.light),
            RadioListTile<ThemeMode>(title: Text('Dark'), value: ThemeMode.dark),
            RadioListTile<ThemeMode>(title: Text('Follow system'), value: ThemeMode.system),
          ],
        ),
      ),
    );
  }
}
