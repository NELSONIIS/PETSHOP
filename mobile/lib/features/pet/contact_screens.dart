import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/errors.dart';
import '../../models/billing.dart';
import '../../models/engagement.dart';
import '../../state/auth.dart';
import '../../state/data.dart';
import '../../state/providers.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/buttons.dart';
import '../../ui/widgets/cards.dart';
import '../../ui/widgets/dialogs.dart';
import '../../ui/widgets/fields.dart';
import '../../ui/widgets/scaffolds.dart';
import '../../ui/widgets/states.dart';
import '../common.dart';
import '../shell/shells.dart';

/// One screen for the contact flow. The backend decides:
///  * 200 -> contact unlocked view,
///  * 402 membership_required -> subscription-required view with suggested plans,
///  * 403 verification_required -> prompt to verify email.
class ContactScreen extends ConsumerWidget {
  const ContactScreen({super.key, required this.listingId});
  final String listingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authed = ref.watch(authProvider.select((s) => s.isAuthed));
    if (!authed) {
      return Scaffold(
        appBar: petoraAppBar(context, 'Seller contact'),
        body: const SignInPrompt(
          title: 'Sign in to view contact',
          message: 'Seller contact details are available to signed-in members.',
        ),
      );
    }
    final v = ref.watch(contactProvider(listingId));
    return Scaffold(
      appBar: petoraAppBar(context, 'Seller contact'),
      body: v.when(
        loading: () => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [CircularProgressIndicator(), SizedBox(height: 12), Text('Checking your membership...')],
          ),
        ),
        error: (e, _) {
          if (e is AppException &&
              (e.kind == ErrorKind.membershipRequired || e.kind == ErrorKind.subscriptionRequired)) {
            return MembershipRequiredView(error: e, listingId: listingId);
          }
          if (e is AppException && e.kind == ErrorKind.verificationRequired) {
            return EmptyState(
              icon: Icons.mark_email_unread_outlined,
              title: 'Verify your email',
              message: 'Please verify your email address to see seller contact details.',
              actionLabel: 'Enter code',
              onAction: () => context.push('/verify-email'),
            );
          }
          return ErrorState(error: e, onRetry: () => ref.invalidate(contactProvider(listingId)));
        },
        data: (c) => _Unlocked(contact: c, listingId: listingId),
      ),
    );
  }
}

class _Unlocked extends StatelessWidget {
  const _Unlocked({required this.contact, required this.listingId});
  final ContactInfo contact;
  final String listingId;

  Future<void> _open(BuildContext context, Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication).catchError((_) => false);
    if (!ok && context.mounted) {
      showSnack(context, 'Could not open that app on this device.', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = contact;
    final wa = (c.whatsapp ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    return ListView(
      padding: const EdgeInsets.all(PSpace.gutter),
      children: [
        Container(
          padding: const EdgeInsets.all(PSpace.lg),
          decoration: BoxDecoration(color: context.pc.successBg, borderRadius: PRadius.cardR),
          child: Row(
            children: [
              Icon(Icons.lock_open_rounded, color: context.pc.success),
              const SizedBox(width: 10),
              Expanded(child: Text('Contact unlocked for ${c.sellerName}', style: context.tt.titleSmall)),
            ],
          ),
        ),
        gap12,
        Card(
          child: Column(
            children: [
              if ((c.phone ?? '').isNotEmpty)
                MenuTile(
                  icon: Icons.call_outlined,
                  title: c.phone!,
                  subtitle: 'Call',
                  onTap: () => _open(context, Uri(scheme: 'tel', path: c.phone)),
                ),
              if (wa.isNotEmpty)
                MenuTile(
                  icon: Icons.chat_outlined,
                  title: c.whatsapp!,
                  subtitle: 'WhatsApp',
                  onTap: () => _open(context, Uri.parse('https://wa.me/$wa')),
                ),
              if ((c.email ?? '').isNotEmpty)
                MenuTile(
                  icon: Icons.mail_outline,
                  title: c.email!,
                  subtitle: 'Email',
                  onTap: () => _open(context, Uri(scheme: 'mailto', path: c.email)),
                ),
              if ((c.phone ?? '').isEmpty && wa.isEmpty && (c.email ?? '').isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('This seller has not added direct contact details. Send an enquiry instead.'),
                ),
            ],
          ),
        ),
        if (c.remainingUnlocks != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${c.remainingUnlocks} contact unlock${c.remainingUnlocks == 1 ? '' : 's'} remaining on your plan',
              style: context.tt.bodySmall?.copyWith(color: context.pc.textMuted),
            ),
          ),
        gap16,
        PButton(
          'Send an enquiry',
          icon: Icons.chat_bubble_outline,
          onPressed: () => context.push('/pet/$listingId/enquire'),
        ),
        gap24,
        Text('Stay safe', style: context.tt.titleSmall),
        const SizedBox(height: 6),
        for (final t in const [
          'Meet in a public place or visit the seller\'s premises with someone you trust.',
          'Ask to see the pet\'s vaccination records and parents where relevant.',
          'Never pay a full amount in advance to someone you have not met.',
          'A membership does not guarantee a pet is available or that a sale will happen.',
        ])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.shield_outlined, size: 16, color: context.cs.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(t, style: context.tt.bodyMedium)),
              ],
            ),
          ),
      ],
    );
  }
}

/// Subscription-required screen: why contact is locked and which plans unlock it.
class MembershipRequiredView extends ConsumerWidget {
  const MembershipRequiredView({super.key, required this.error, this.listingId});
  final AppException error;
  final String? listingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggested = error.suggestedPlans.map(Plan.fromJson).toList();
    final plans = suggested.isNotEmpty ? AsyncValue.data(suggested) : ref.watch(plansProvider('buyer'));
    final back = listingId == null ? '' : '?return=${Uri.encodeComponent('/pet/$listingId/contact')}';
    return ListView(
      padding: const EdgeInsets.all(PSpace.gutter),
      children: [
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: context.cs.primaryContainer, shape: BoxShape.circle),
            child: Icon(Icons.lock_outline_rounded, size: 34, color: context.cs.primary),
          ),
        ),
        gap16,
        Text('A membership is needed', style: context.tt.headlineMedium, textAlign: TextAlign.center),
        const SizedBox(height: 6),
        Text(
          error.message.isNotEmpty ? error.message : 'Seller contact details are part of PETORA membership.',
          style: context.tt.bodyLarge?.copyWith(color: context.pc.textMuted),
          textAlign: TextAlign.center,
        ),
        gap16,
        plans.when(
          loading: () => const Skeleton(height: 160, radius: 14),
          error: (_, _) => const SizedBox.shrink(),
          data: (l) => Column(
            children: [
              for (final p in l.take(2))
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: PlanCard(
                    plan: p,
                    highlighted: p == l.first,
                    ctaLabel: 'Choose ${p.name}',
                    onSelect: () => context.push('/checkout/${p.id}$back'),
                  ),
                ),
            ],
          ),
        ),
        PButton('Compare all plans', kind: PButtonKind.outline, onPressed: () => context.push('/plans$back')),
        gap12,
        Text(
          'Browsing and searching stay free. A membership does not guarantee a pet is available or that a transaction will succeed.',
          style: context.tt.bodySmall?.copyWith(color: context.pc.textMuted),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// Enquiry form (#33).
class EnquiryFormScreen extends ConsumerStatefulWidget {
  const EnquiryFormScreen({super.key, required this.listingId});
  final String listingId;
  @override
  ConsumerState<EnquiryFormScreen> createState() => _EnquiryFormScreenState();
}

class _EnquiryFormScreenState extends ConsumerState<EnquiryFormScreen> {
  final _form = GlobalKey<FormState>();
  final _msg = TextEditingController(
    text: 'Hi, I am interested in this pet. Is it still available? Could you share more details about its health and vaccinations?',
  );
  bool _busy = false;
  String? _error;
  AppException? _membership;

  @override
  void dispose() {
    _msg.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final e = await ref.read(buyerRepoProvider).createEnquiry(widget.listingId, _msg.text);
      ref.invalidate(buyerEnquiriesProvider);
      if (mounted) {
        context.pushReplacement('/pet/${widget.listingId}/enquiry-sent?eid=${e.id}');
      }
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      if (e.kind == ErrorKind.membershipRequired || e.kind == ErrorKind.subscriptionRequired) {
        setState(() => _membership = e);
      } else if (e.kind == ErrorKind.conflict && e.extra?['enquiry_id'] != null) {
        final id = '${e.extra!['enquiry_id']}';
        final open = await confirmDialog(
          context,
          title: 'Already enquired',
          message: 'You already have a conversation with this seller about this pet. Open it to continue?',
          confirmLabel: 'Open conversation',
        );
        if (open && mounted) context.pushReplacement('/enquiry/$id');
      } else if (e.kind == ErrorKind.verificationRequired) {
        handleActionError(context, e);
      } else {
        setState(() => _error = e.fieldErrors.isNotEmpty ? e.fieldErrors.values.first : e.userMessage);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_membership != null) {
      return Scaffold(
        appBar: petoraAppBar(context, 'Send enquiry'),
        body: MembershipRequiredView(error: _membership!, listingId: widget.listingId),
      );
    }
    return FormPage(
      title: 'Send enquiry',
      bottom: PButton('Send enquiry', icon: Icons.send, onPressed: _send, loading: _busy),
      children: [
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your message goes to the seller inside PETORA. Your contact details are not shared unless you choose to.',
                style: context.tt.bodyMedium?.copyWith(color: context.pc.textMuted),
              ),
              gap16,
              if (_error != null) ...[InfoBanner(_error!, tone: BannerTone.danger), gap12],
              PTextField(
                label: 'Message',
                controller: _msg,
                maxLines: 6,
                minLines: 4,
                maxLength: 2000,
                validator: (v) => Validators.minLen(v, 5, 'Message'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Confirmation (#34).
class EnquirySentScreen extends StatelessWidget {
  const EnquirySentScreen({super.key, required this.listingId, this.enquiryId});
  final String listingId;
  final String? enquiryId;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(PSpace.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(color: context.pc.successBg, shape: BoxShape.circle),
              child: Icon(Icons.check_rounded, size: 52, color: context.pc.success),
            ),
            gap24,
            Text('Enquiry sent', style: context.tt.headlineMedium),
            const SizedBox(height: 8),
            Text(
              'The seller has been notified. Replies appear in your Enquiries tab.',
              textAlign: TextAlign.center,
              style: context.tt.bodyLarge?.copyWith(color: context.pc.textMuted),
            ),
            gap24,
            if (enquiryId != null) PButton('View enquiry', onPressed: () => context.go('/enquiry/$enquiryId')),
            gap8,
            PButton('Keep browsing', kind: PButtonKind.outline, onPressed: () => context.go('/')),
          ],
        ),
      ),
    ),
  );
}
