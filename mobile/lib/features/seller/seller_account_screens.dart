import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../data/media_picker.dart';
import '../../data/repositories.dart';
import '../../models/billing.dart';
import '../../models/seller.dart';
import '../../state/auth.dart';
import '../../state/data.dart';
import '../../state/providers.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/badges.dart';
import '../../ui/widgets/buttons.dart';
import '../../ui/widgets/cards.dart';
import '../../ui/widgets/dialogs.dart';
import '../../ui/widgets/fields.dart';
import '../../ui/widgets/inputs.dart';
import '../../ui/widgets/net_image.dart';
import '../../ui/widgets/scaffolds.dart';
import '../../ui/widgets/states.dart';
import '../common.dart';
import '../enquiries/enquiries_screens.dart';

/// Seller registration steps 2-4: individual/business, business profile, contact + location.
/// Also used to edit the profile later (`edit: true`).
class SellerOnboardingScreen extends ConsumerStatefulWidget {
  const SellerOnboardingScreen({super.key, this.edit = false});
  final bool edit;
  @override
  ConsumerState<SellerOnboardingScreen> createState() => _SellerOnboardingScreenState();
}

class _SellerOnboardingScreenState extends ConsumerState<SellerOnboardingScreen> {
  final _formA = GlobalKey<FormState>();
  final _formB = GlobalKey<FormState>();
  final _display = TextEditingController();
  final _business = TextEditingController();
  final _gst = TextEditingController();
  final _bio = TextEditingController();
  final _city = TextEditingController();
  final _phone = TextEditingController();
  final _whatsapp = TextEditingController();
  final _email = TextEditingController();
  String _type = 'individual';
  String? _state;
  int _step = 0;
  bool _busy = false, _loaded = false;
  Map<String, String> _errs = {};

  @override
  void dispose() {
    for (final c in [_display, _business, _gst, _bio, _city, _phone, _whatsapp, _email]) {
      c.dispose();
    }
    super.dispose();
  }

  void _fill(SellerProfile p) {
    if (_loaded) return;
    _loaded = true;
    _type = p.sellerType;
    _display.text = p.displayName;
    _business.text = p.businessName ?? '';
    _gst.text = p.gstNumber ?? '';
    _bio.text = p.bio;
    _city.text = p.city;
    _state = indianStates.contains(p.state) ? p.state : null;
    _phone.text = p.contactPhone ?? '';
    _whatsapp.text = p.contactWhatsapp ?? '';
    _email.text = p.contactEmail ?? '';
  }

  Future<void> _save() async {
    if (_busy || !(_formB.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _errs = {};
    });
    try {
      await ref.read(sellerRepoProvider).saveProfile({
        'display_name': _display.text.trim(),
        'seller_type': _type,
        'business_name': _type == 'business' ? _business.text.trim() : '',
        'gst_number': _type == 'business' ? _gst.text.trim() : '',
        'bio': _bio.text.trim(),
        'city': _city.text.trim(),
        'state': _state ?? '',
        'contact_phone': _phone.text.trim(),
        'contact_whatsapp': _whatsapp.text.trim(),
        'contact_email': _email.text.trim(),
      });
      ref.invalidate(sellerProfileProvider);
      ref.invalidate(sellerDashboardProvider);
      ref.invalidate(verificationProvider);
      if (!mounted) return;
      if (widget.edit) {
        showSnack(context, 'Profile saved');
        context.pop();
      } else {
        context.go('/sell/verification?setup=1');
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
  Widget build(BuildContext context) {
    final profile = ref.watch(sellerProfileProvider);
    return profile.when(
      loading: () => Scaffold(appBar: petoraAppBar(context, 'Seller profile'), body: const ListSkeleton()),
      error: (e, _) => Scaffold(
        appBar: petoraAppBar(context, 'Seller profile'),
        body: ErrorState(error: e, onRetry: () => ref.invalidate(sellerProfileProvider)),
      ),
      data: (p) {
        _fill(p);
        return FormPage(
          title: widget.edit ? 'Business profile' : 'Set up your seller profile',
          actions: widget.edit ? null : [TextButton(onPressed: () => context.go('/sell'), child: const Text('Later'))],
          bottom: Row(
            children: [
              if (_step > 0)
                Expanded(
                  child: PButton('Back', kind: PButtonKind.outline, onPressed: () => setState(() => _step = 0)),
                ),
              if (_step > 0) const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: _step == 0
                    ? PButton(
                        'Continue',
                        onPressed: () {
                          if (_formA.currentState?.validate() ?? false) {
                            setState(() => _step = 1);
                          }
                        },
                      )
                    : PButton('Save profile', onPressed: _save, loading: _busy),
              ),
            ],
          ),
          children: [
            LinearProgressIndicator(value: (_step + 1) / 2, minHeight: 4, borderRadius: BorderRadius.circular(2)),
            const SizedBox(height: 6),
            Text('Step ${_step + 1} of 2', style: context.tt.bodySmall?.copyWith(color: context.pc.textMuted)),
            gap16,
            if (_step == 0)
              Form(
                key: _formA,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Who are you selling as?', style: context.tt.titleMedium),
                    gap8,
                    SegmentRow<String>(
                      value: _type,
                      options: const {'individual': 'Individual', 'business': 'Business / breeder / shop'},
                      onChanged: (v) => setState(() => _type = v),
                    ),
                    gap16,
                    PTextField(
                      label: _type == 'business' ? 'Public name' : 'Display name',
                      controller: _display,
                      validator: (v) => Validators.minLen(v, 2, 'Name'),
                      errorText: _errs['display_name'],
                    ),
                    if (_type == 'business') ...[
                      gap16,
                      PTextField(
                        label: 'Registered business name',
                        controller: _business,
                        validator: (v) => Validators.required(v, 'Business name'),
                        errorText: _errs['business_name'],
                      ),
                      gap16,
                      PTextField(label: 'GST number (optional)', controller: _gst, errorText: _errs['gst_number']),
                    ],
                    gap16,
                    PTextField(
                      label: 'About you (optional)',
                      controller: _bio,
                      maxLines: 4,
                      minLines: 3,
                      maxLength: 600,
                      errorText: _errs['bio'],
                    ),
                  ],
                ),
              )
            else
              Form(
                key: _formB,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Where are you based?', style: context.tt.titleMedium),
                    gap8,
                    PTextField(
                      label: 'City',
                      controller: _city,
                      validator: (v) => Validators.minLen(v, 2, 'City'),
                      errorText: _errs['city'],
                    ),
                    gap12,
                    PDropdown<String>(
                      label: 'State',
                      value: _state,
                      items: {for (final s in indianStates) s: s},
                      onChanged: (v) => setState(() => _state = v),
                      validator: (v) => v == null ? 'Select a state' : null,
                    ),
                    gap24,
                    Text('Contact details', style: context.tt.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      'Shown only to members who unlock your contact - never on your public profile.',
                      style: context.tt.bodySmall?.copyWith(color: context.pc.textMuted),
                    ),
                    gap12,
                    PTextField(
                      label: 'Phone',
                      controller: _phone,
                      keyboard: TextInputType.phone,
                      validator: Validators.phone,
                      errorText: _errs['contact_phone'],
                    ),
                    gap12,
                    PTextField(
                      label: 'WhatsApp (optional)',
                      controller: _whatsapp,
                      keyboard: TextInputType.phone,
                      validator: (v) => Validators.phone(v, optional: true),
                      errorText: _errs['contact_whatsapp'],
                    ),
                    gap12,
                    PTextField(
                      label: 'Contact email (optional)',
                      controller: _email,
                      keyboard: TextInputType.emailAddress,
                      validator: (v) => (v ?? '').trim().isEmpty ? null : Validators.email(v),
                      errorText: _errs['contact_email'],
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Verification status + document upload + submit. Payment never counts as verification.
class VerificationScreen extends ConsumerStatefulWidget {
  const VerificationScreen({super.key, this.setup = false});
  final bool setup;
  @override
  ConsumerState<VerificationScreen> createState() => _VerificationScreenState();
}

class _UploadJob {
  _UploadJob(this.file, this.kind);
  final UploadFile file;
  final String kind;
  double progress = 0;
  bool failed = false;
  String? error;
  final cancel = CancelToken();
}

class _VerificationScreenState extends ConsumerState<VerificationScreen> {
  String _kind = 'identity';
  final _jobs = <_UploadJob>[];
  bool _submitting = false;

  static const kinds = {
    'identity': 'Identity (Aadhaar, PAN, passport...)',
    'address_proof': 'Address proof',
    'business_registration': 'Business registration',
    'trade_licence': 'Trade licence',
    'breeder_registration': 'Breeder registration',
    'other': 'Other supporting document',
  };

  Future<void> _pick() async {
    final f = await ref.read(mediaPickerProvider).pickDocument();
    if (f == null) return;
    if (f.size > 10 * 1024 * 1024) {
      if (mounted) {
        showSnack(context, 'That file is larger than 10 MB.', error: true);
      }
      return;
    }
    final job = _UploadJob(f, _kind);
    setState(() => _jobs.add(job));
    _upload(job);
  }

  Future<void> _upload(_UploadJob j) async {
    setState(() {
      j.failed = false;
      j.error = null;
      j.progress = 0;
    });
    try {
      await ref
          .read(sellerRepoProvider)
          .uploadDocument(
            j.file,
            j.kind,
            onProgress: (s, t) {
              if (t > 0 && mounted) setState(() => j.progress = s / t);
            },
            cancel: j.cancel,
          );
      ref.invalidate(verificationProvider);
      ref.invalidate(sellerDocsProvider);
      if (mounted) setState(() => _jobs.remove(j));
    } on AppException catch (e) {
      if (mounted) {
        if (e.code == 'cancelled') {
          setState(() => _jobs.remove(j));
        } else {
          setState(() {
            j.failed = true;
            j.error = e.fieldErrors.values.isNotEmpty ? e.fieldErrors.values.first : e.userMessage;
          });
        }
      }
    }
  }

  Future<void> _submit(VerificationStatus v) async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      final profile = ref.read(sellerProfileProvider).asData?.value;
      await ref.read(sellerRepoProvider).submitVerification(jurisdictionState: profile?.state ?? '');
      ref.invalidate(verificationProvider);
      ref.invalidate(sellerDashboardProvider);
      ref.invalidate(sellerProfileProvider);
      if (mounted) showSnack(context, 'Submitted for review');
    } on AppException catch (e) {
      if (mounted) {
        if (e.fieldErrors.isNotEmpty) {
          showSnack(context, e.fieldErrors.values.join('\n'), error: true);
        } else {
          handleActionError(context, e);
        }
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = ref.watch(verificationProvider);
    return Scaffold(
      appBar: petoraAppBar(
        context,
        'Verification',
        actions: [if (widget.setup) TextButton(onPressed: () => context.go('/sell'), child: const Text('Later'))],
      ),
      body: AsyncBody<VerificationStatus>(
        value: v,
        onRetry: () => ref.invalidate(verificationProvider),
        data: (s) {
          final canEdit = s.status == 'unsubmitted' || s.status == 'rejected';
          return RefreshIndicator(
            onRefresh: () async => ref.refresh(verificationProvider.future),
            child: ListView(
              padding: const EdgeInsets.all(PSpace.gutter),
              children: [
                _StatusCard(status: s),
                gap12,
                const InfoBanner(
                  'Verification is a review of your identity or business documents by our team. Buying a plan does not verify you, and a Verified badge is never a guarantee about an individual pet.',
                  icon: Icons.verified_user_outlined,
                ),
                if (s.requirements.isNotEmpty && canEdit) ...[
                  gap16,
                  Text('Still needed', style: context.tt.titleSmall),
                  for (final r in s.requirements)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          Icon(Icons.radio_button_unchecked, size: 16, color: context.pc.warning),
                          const SizedBox(width: 8),
                          Expanded(child: Text(r)),
                        ],
                      ),
                    ),
                ],
                gap24,
                Text('Documents', style: context.tt.titleMedium),
                const SizedBox(height: 2),
                Text(
                  'PDF, JPG or PNG up to 10 MB. Stored privately and visible only to our verification team.',
                  style: context.tt.bodySmall?.copyWith(color: context.pc.textMuted),
                ),
                gap8,
                for (final d in s.documents)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const Icon(Icons.description_outlined),
                      title: Text(d.originalName, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${titleCase(d.kind)} · ${(d.sizeBytes / 1024).round()} KB'),
                      trailing: canEdit
                          ? IconButton(
                              tooltip: 'Delete document',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () async {
                                final ok = await confirmDialog(
                                  context,
                                  title: 'Delete document?',
                                  message: d.originalName,
                                  confirmLabel: 'Delete',
                                  destructive: true,
                                );
                                if (!ok) return;
                                try {
                                  await ref.read(sellerRepoProvider).deleteDocument(d.id);
                                  ref.invalidate(verificationProvider);
                                } catch (e) {
                                  if (context.mounted) showError(context, e);
                                }
                              },
                            )
                          : null,
                    ),
                  ),
                for (final j in _jobs)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: j.failed
                          ? Icon(Icons.error_outline, color: context.cs.error)
                          : const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
                      title: Text(j.file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: j.failed
                          ? Text(j.error ?? 'Upload failed', style: TextStyle(color: context.cs.error))
                          : LinearProgressIndicator(value: j.progress == 0 ? null : j.progress),
                      trailing: j.failed
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextButton(onPressed: () => _upload(j), child: const Text('Retry')),
                                IconButton(
                                  tooltip: 'Dismiss',
                                  icon: const Icon(Icons.close),
                                  onPressed: () => setState(() => _jobs.remove(j)),
                                ),
                              ],
                            )
                          : IconButton(
                              tooltip: 'Cancel upload',
                              icon: const Icon(Icons.close),
                              onPressed: () => j.cancel.cancel(),
                            ),
                    ),
                  ),
                if (canEdit) ...[
                  gap8,
                  PDropdown<String>(
                    label: 'Document type',
                    value: _kind,
                    items: kinds,
                    onChanged: (k) => setState(() => _kind = k ?? _kind),
                  ),
                  gap8,
                  PButton('Upload document', icon: Icons.upload_file, kind: PButtonKind.outline, onPressed: _pick),
                  gap16,
                  PButton(
                    'Submit for verification',
                    onPressed: _jobs.isNotEmpty || s.documents.isEmpty ? null : () => _submit(s),
                    loading: _submitting,
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status});
  final VerificationStatus status;
  @override
  Widget build(BuildContext context) {
    final (icon, title, msg, tone) = switch (status.status) {
      'approved' => (
        Icons.verified,
        'Verified seller',
        'Your documents were approved${status.reviewedAt != null ? ' on ${formatDate(status.reviewedAt)}' : ''}.',
        Tone.success,
      ),
      'pending' => (
        Icons.hourglass_top,
        'Under review',
        'We are reviewing your documents. This usually takes 1-2 working days.',
        Tone.warning,
      ),
      'rejected' => (
        Icons.error_outline,
        'Needs attention',
        status.reason ?? 'Your verification was not approved. Update your documents and resubmit.',
        Tone.danger,
      ),
      'suspended' => (Icons.block, 'Suspended', status.reason ?? 'Contact support for details.', Tone.danger),
      _ => (
        Icons.badge_outlined,
        'Not submitted',
        'Upload your documents and submit them to earn the Verified seller badge.',
        Tone.neutral,
      ),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(PSpace.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              size: 30,
              color: switch (tone) {
                Tone.success => context.pc.success,
                Tone.warning => context.pc.warning,
                Tone.danger => context.pc.danger,
                _ => context.pc.textMuted,
              },
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: context.tt.titleMedium),
                  const SizedBox(height: 2),
                  Text(msg, style: context.tt.bodyMedium?.copyWith(color: context.pc.textMuted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Seller dashboard (tab 0).
class SellerDashboardScreen extends ConsumerWidget {
  const SellerDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = ref.watch(sellerDashboardProvider);
    final user = ref.watch(authProvider).user;
    return Scaffold(
      appBar: AppBar(
        title: Text('Hi, ${(user?.name ?? '').split(' ').first}'),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            onPressed: () => context.push('/notifications'),
            icon: Badge(
              isLabelVisible: (ref.watch(unreadCountProvider).asData?.value ?? 0) > 0,
              child: const Icon(Icons.notifications_none),
            ),
          ),
        ],
      ),
      body: AsyncBody<SellerDashboard>(
        value: v,
        onRetry: () => ref.invalidate(sellerDashboardProvider),
        loading: const ListSkeleton(height: 110),
        data: (d) {
          final sub = d.subscription;
          final c = d.counts;
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(sellerEnquiriesProvider);
              return ref.refresh(sellerDashboardProvider.future);
            },
            child: ListView(
              padding: const EdgeInsets.all(PSpace.gutter),
              children: [
                if (!(user?.emailVerified ?? true)) ...[
                  InfoBanner(
                    'Verify your email to submit listings.',
                    tone: BannerTone.warning,
                    action: TextButton(onPressed: () => context.push('/verify-email'), child: const Text('Verify')),
                  ),
                  gap12,
                ],
                _VerificationCard(status: d.verificationStatus),
                gap12,
                _SubscriptionCard(status: sub),
                gap16,
                Row(
                  children: [
                    Expanded(
                      child: _Stat(label: 'Views (30d)', value: '${d.views30d}', icon: Icons.visibility_outlined),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _Stat(label: 'Enquiries', value: '${d.enquiriesTotal}', icon: Icons.chat_bubble_outline),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _Stat(
                        label: 'Unread',
                        value: '${d.unreadEnquiries}',
                        icon: Icons.mark_chat_unread_outlined,
                        highlight: d.unreadEnquiries > 0,
                      ),
                    ),
                  ],
                ),
                const SectionHeader('Your listings', padding: EdgeInsets.fromLTRB(0, 20, 0, 6)),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final e in const {
                      'approved': 'Active',
                      'pending': 'Pending',
                      'draft': 'Drafts',
                      'rejected': 'Rejected',
                      'sold': 'Sold / unavailable',
                      'expired': 'Expired',
                      'suspended': 'Suspended',
                    }.entries)
                      if ((c[e.key] ?? 0) > 0 || e.key == 'approved' || e.key == 'draft')
                        ActionChip(
                          label: Text('${e.value} · ${c[e.key] ?? 0}'),
                          onPressed: () => context.go('/sell/listings?tab=${e.key}'),
                        ),
                  ],
                ),
                if (d.recent.isNotEmpty) ...[
                  SectionHeader(
                    'Recent enquiries',
                    padding: const EdgeInsets.fromLTRB(0, 20, 0, 6),
                    actionLabel: 'Inbox',
                    onAction: () => context.go('/sell/enquiries'),
                  ),
                  for (final e in d.recent.take(3))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: EnquiryCard(
                        enquiry: e,
                        sellerView: true,
                        onTap: () => context.push('/sell/enquiry/${e.id}'),
                      ),
                    ),
                ],
                const SizedBox(height: 80),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.icon, this.highlight = false});
  final String label, value;
  final IconData icon;
  final bool highlight;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: highlight ? context.pc.accent : context.cs.primary),
          const SizedBox(height: 6),
          Text(value, style: context.tt.headlineMedium?.copyWith(color: highlight ? context.pc.accent : null)),
          Text(
            label,
            style: context.tt.bodySmall?.copyWith(color: context.pc.textMuted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    ),
  );
}

class _VerificationCard extends StatelessWidget {
  const _VerificationCard({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) {
    final approved = status == 'approved';
    final (label, tone) = switch (status) {
      'approved' => ('Verified seller', Tone.success),
      'pending' => ('Verification under review', Tone.warning),
      'rejected' => ('Verification needs attention', Tone.danger),
      'suspended' => ('Seller account suspended', Tone.danger),
      _ => ('Get verified', Tone.neutral),
    };
    return Card(
      child: ListTile(
        onTap: () => context.push('/sell/verification'),
        leading: Icon(
          approved ? Icons.verified : Icons.verified_user_outlined,
          color: approved ? context.pc.secondary : context.pc.textMuted,
        ),
        title: Text(label, style: context.tt.titleSmall),
        subtitle: Text(
          approved ? 'Buyers see the Verified seller badge.' : 'Submit documents to earn the Verified seller badge.',
        ),
        trailing: StatusBadge(titleCase(status == 'unsubmitted' ? 'Not submitted' : status), tone: tone),
      ),
    );
  }
}

class _SubscriptionCard extends StatelessWidget {
  const _SubscriptionCard({required this.status});
  final SubscriptionStatus status;
  @override
  Widget build(BuildContext context) {
    final s = status.subscription;
    final e = status.entitlements;
    return Card(
      child: InkWell(
        borderRadius: PRadius.cardR,
        onTap: () => context.push(status.active ? '/membership' : '/plans'),
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
                    Text(status.active ? s!.planName : 'No active plan', style: context.tt.titleSmall),
                    Text(
                      status.active
                          ? '${e.listingsUsed} of ${e.listingLimit ?? '∞'} listings · ${status.inGrace ? 'grace period ends' : 'renews'} ${formatDate(status.inGrace ? s!.graceEnds : s!.periodEnd)}'
                          : 'Subscribe to publish listings',
                      style: context.tt.bodySmall?.copyWith(color: context.pc.textMuted),
                    ),
                  ],
                ),
              ),
              if (status.active && (s!.canRenew || status.inGrace))
                const StatusBadge('Renew', tone: Tone.warning)
              else
                Icon(Icons.chevron_right, color: context.pc.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Seller profile tab (tab 3).
class SellerProfileTab extends ConsumerWidget {
  const SellerProfileTab({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final u = ref.watch(authProvider).user;
    final p = ref.watch(sellerProfileProvider).asData?.value;
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(PSpace.gutter),
            child: Row(
              children: [
                PAvatar(url: p?.logoUrl, name: p?.displayName ?? u?.name ?? '', size: 56),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p?.displayName ?? u?.name ?? '', style: context.tt.titleMedium),
                      Text(u?.email ?? '', style: context.tt.bodySmall?.copyWith(color: context.pc.textMuted)),
                      const SizedBox(height: 4),
                      if (p?.verified ?? false)
                        const VerifiedBadge()
                      else
                        StatusBadge(
                          titleCase(
                            p?.verificationStatus == 'unsubmitted'
                                ? 'Not verified'
                                : (p?.verificationStatus ?? 'unsubmitted'),
                          ),
                          tone: Tone.neutral,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          MenuTile(
            icon: Icons.storefront_outlined,
            title: 'Business profile',
            onTap: () => context.push('/sell/profile/edit'),
          ),
          MenuTile(
            icon: Icons.verified_user_outlined,
            title: 'Verification & documents',
            onTap: () => context.push('/sell/verification'),
          ),
          MenuTile(
            icon: Icons.workspace_premium_outlined,
            title: 'Subscription',
            onTap: () => context.push('/membership'),
          ),
          MenuTile(
            icon: Icons.receipt_long_outlined,
            title: 'Payments & invoices',
            onTap: () => context.push('/billing'),
          ),
          MenuTile(icon: Icons.notifications_none, title: 'Notifications', onTap: () => context.push('/notifications')),
          if (p != null && p.slug.isNotEmpty)
            MenuTile(icon: Icons.public, title: 'View my public profile', onTap: () => context.push('/s/${p.slug}')),
          const Divider(),
          MenuTile(
            icon: Icons.brightness_6_outlined,
            title: 'Appearance',
            onTap: () => context.push('/profile/appearance'),
          ),
          MenuTile(icon: Icons.lock_outline, title: 'Security', onTap: () => context.push('/profile/security')),
          MenuTile(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy & data',
            onTap: () => context.push('/profile/privacy'),
          ),
          MenuTile(icon: Icons.help_outline, title: 'Support & disputes', onTap: () => context.push('/help')),
          MenuTile(
            icon: Icons.gavel_outlined,
            title: 'Seller policy',
            onTap: () => context.push('/legal/seller-policy'),
          ),
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

// Re-exports so seller screens can share the thread widgets.
typedef SellerThread = EnquiryThreadScreen;
typedef SellerInbox = SellerInboxScreen;
