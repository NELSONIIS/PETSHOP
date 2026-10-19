import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/json.dart';
import '../../core/format.dart';
import '../../models/common.dart';
import '../../state/auth.dart';
import '../../state/data.dart';
import '../../state/providers.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/badges.dart';
import '../../ui/widgets/buttons.dart';
import '../../ui/widgets/cards.dart';
import '../../ui/widgets/dialogs.dart';
import '../../ui/widgets/fields.dart';
import '../../ui/widgets/scaffolds.dart';
import '../../ui/widgets/states.dart';

import 'package:go_router/go_router.dart';

import '../common.dart';

const _fallbackFaq = [
  (
    'Is browsing really free?',
    'Yes. You can search and view pets, photos and seller profiles without paying. A membership is only needed to unlock seller contact details and send enquiries.',
  ),
  (
    'What does "Verified seller" mean?',
    'Our team reviewed the seller\'s identity or business documents. It is not a guarantee about any individual pet, and PETORA does not certify pets as healthy.',
  ),
  (
    'Does a membership guarantee a pet?',
    'No. A membership gives you access to contact details. Availability and any sale are between you and the seller.',
  ),
  (
    'How do I stay safe?',
    'Meet in person, ask for vaccination records, and never pay in full in advance. Report anything suspicious from the listing menu.',
  ),
  (
    'How do refunds work?',
    'See the refund policy shown at checkout. Refunds are reviewed by our team; they are not automatic.',
  ),
];

/// Help & support: FAQ, contact form, disputes.
class HelpScreen extends ConsumerWidget {
  const HelpScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final faq = ref.watch(_faqProvider).asData?.value ?? _fallbackFaq;
    final authed = ref.watch(authProvider.select((s) => s.isAuthed));
    return Scaffold(
      appBar: petoraAppBar(context, 'Help & support'),
      body: ListView(
        padding: const EdgeInsets.all(PSpace.gutter),
        children: [
          Text('Frequently asked questions', style: context.tt.titleMedium),
          gap8,
          for (final f in faq)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ExpansionTile(
                shape: const Border(),
                collapsedShape: const Border(),
                title: Text(f.$1, style: context.tt.titleSmall),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [Text(f.$2, style: context.tt.bodyMedium)],
              ),
            ),
          gap16,
          MenuTile(
            icon: Icons.mail_outline,
            title: 'Contact support',
            subtitle: 'We reply by email',
            onTap: () => _contact(context, ref),
          ),
          if (authed)
            MenuTile(
              icon: Icons.gavel_outlined,
              title: 'Disputes & appeals',
              subtitle: 'Payment issues, listing appeals, conduct',
              onTap: () => showPetoraSheet<void>(context, full: true, builder: (_) => const DisputesSheet()),
            ),
          MenuTile(
            icon: Icons.shield_outlined,
            title: 'Safety & responsible ownership',
            onTap: () => context.push('/legal/safety'),
          ),
        ],
      ),
    );
  }

  void _contact(BuildContext context, WidgetRef ref) =>
      showPetoraSheet<void>(context, builder: (_) => const _ContactForm());
}

final _faqProvider = FutureProvider.autoDispose<List<(String, String)>>((ref) async {
  try {
    final m = await ref.watch(catalogRepoProvider).content('faq');
    final items = J.list(m, 'items', (e) => (J.str(e, 'q', J.str(e, 'question')), J.str(e, 'a', J.str(e, 'answer'))));
    return items.where((e) => e.$1.isNotEmpty).toList().isEmpty ? _fallbackFaq : items;
  } catch (_) {
    return _fallbackFaq;
  }
});

class _ContactForm extends ConsumerStatefulWidget {
  const _ContactForm();
  @override
  ConsumerState<_ContactForm> createState() => _ContactFormState();
}

class _ContactFormState extends ConsumerState<_ContactForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: ref.read(authProvider).user?.name ?? '');
  late final _email = TextEditingController(text: ref.read(authProvider).user?.email ?? '');
  final _subject = TextEditingController();
  final _msg = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _email, _subject, _msg]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(catalogRepoProvider)
          .supportContact(
            name: _name.text.trim(),
            email: _email.text.trim(),
            subject: _subject.text.trim(),
            message: _msg.text.trim(),
          );
      if (mounted) {
        Navigator.pop(context);
        showSnack(context, 'Message sent. We will reply by email.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) => SheetScaffold(
    title: 'Contact support',
    child: Form(
      key: _form,
      child: Column(
        children: [
          PTextField(label: 'Name', controller: _name, validator: (v) => Validators.minLen(v, 2, 'Name')),
          gap12,
          PTextField(
            label: 'Email',
            controller: _email,
            keyboard: TextInputType.emailAddress,
            validator: Validators.email,
          ),
          gap12,
          PTextField(label: 'Subject', controller: _subject),
          gap12,
          PTextField(
            label: 'Message',
            controller: _msg,
            maxLines: 5,
            minLines: 3,
            maxLength: 2000,
            validator: (v) => Validators.minLen(v, 10, 'Message'),
          ),
          gap8,
          PButton('Send message', onPressed: _send, loading: _busy),
        ],
      ),
    ),
  );
}

class DisputesSheet extends ConsumerStatefulWidget {
  const DisputesSheet({super.key});
  @override
  ConsumerState<DisputesSheet> createState() => _DisputesSheetState();
}

class _DisputesSheetState extends ConsumerState<DisputesSheet> {
  final _form = GlobalKey<FormState>();
  final _subject = TextEditingController();
  final _msg = TextEditingController();
  String _kind = 'payment';
  bool _busy = false, _creating = false;

  @override
  void dispose() {
    _subject.dispose();
    _msg.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(accountRepoProvider)
          .openDispute(kind: _kind, subject: _subject.text.trim(), message: _msg.text.trim());
      ref.invalidate(disputesProvider);
      _subject.clear();
      _msg.clear();
      if (mounted) {
        setState(() {
          _busy = false;
          _creating = false;
        });
        showSnack(context, 'Dispute opened. We will update you here.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        handleActionError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(disputesProvider);
    return SheetScaffold(
      title: 'Disputes & appeals',
      child: _creating
          ? Form(
              key: _form,
              child: Column(
                children: [
                  PDropdown<String>(
                    label: 'Type',
                    value: _kind,
                    items: const {
                      'payment': 'Payment issue',
                      'listing_appeal': 'Listing appeal',
                      'conduct': 'Conduct complaint',
                      'other': 'Other',
                    },
                    onChanged: (v) => setState(() => _kind = v ?? _kind),
                  ),
                  gap12,
                  PTextField(
                    label: 'Subject',
                    controller: _subject,
                    validator: (v) => Validators.minLen(v, 4, 'Subject'),
                  ),
                  gap12,
                  PTextField(
                    label: 'What happened?',
                    controller: _msg,
                    maxLines: 5,
                    minLines: 3,
                    maxLength: 2000,
                    validator: (v) => Validators.minLen(v, 10, 'Description'),
                  ),
                  gap8,
                  PButton('Submit dispute', onPressed: _submit, loading: _busy),
                  PButton('Cancel', kind: PButtonKind.ghost, onPressed: () => setState(() => _creating = false)),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PButton('Open a new dispute', icon: Icons.add, onPressed: () => setState(() => _creating = true)),
                gap12,
                list.when(
                  loading: () => const ListSkeleton(count: 2, height: 64),
                  error: (e, _) => ErrorState(error: e, compact: true, onRetry: () => ref.invalidate(disputesProvider)),
                  data: (l) => l.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'You have no disputes.',
                            style: context.tt.bodyMedium?.copyWith(color: context.pc.textMuted),
                          ),
                        )
                      : Column(
                          children: [
                            for (final Dispute d in l)
                              Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  title: Text(d.subject),
                                  subtitle: Text(
                                    '${titleCase(d.kind)} · ${formatDate(d.createdAt)}${d.resolution != null ? '\n${d.resolution}' : ''}',
                                  ),
                                  isThreeLine: d.resolution != null,
                                  trailing: StatusBadge.status(d.status),
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
