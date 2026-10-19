import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../models/engagement.dart';
import '../../state/auth.dart';
import '../../state/data.dart';
import '../../state/paged.dart';
import '../../state/providers.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/cards.dart';
import '../../ui/widgets/dialogs.dart';
import '../../ui/widgets/inputs.dart';
import '../../ui/widgets/states.dart';
import '../common.dart';
import '../search/browse_screens.dart';
import '../shell/shells.dart';

Widget _enquiryList(
  BuildContext context,
  PagedState<Enquiry> s, {
  required Future<void> Function() refresh,
  required VoidCallback more,
  required bool seller,
  required String emptyMsg,
}) {
  if (s.loading && s.items.isEmpty) return const ListSkeleton(height: 96);
  if (s.error != null && s.items.isEmpty) {
    return ErrorState(error: s.error!, onRetry: refresh);
  }
  if (s.items.isEmpty) {
    return EmptyState(icon: Icons.chat_bubble_outline, title: 'No enquiries yet', message: emptyMsg);
  }
  return RefreshIndicator(
    onRefresh: refresh,
    child: NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.extentAfter < 400 && s.loadMoreError == null) more();
        return false;
      },
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(PSpace.gutter),
        itemCount: s.items.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, i) => i == s.items.length
            ? LoadMoreFooter(loading: s.loadingMore, hasMore: s.hasMore, onLoadMore: more, error: s.loadMoreError)
            : EnquiryCard(
                enquiry: s.items[i],
                sellerView: seller,
                onTap: () => context.push(seller ? '/sell/enquiry/${s.items[i].id}' : '/enquiry/${s.items[i].id}'),
              ),
      ),
    ),
  );
}

/// Buyer Enquiries tab.
class BuyerEnquiriesScreen extends ConsumerStatefulWidget {
  const BuyerEnquiriesScreen({super.key});
  @override
  ConsumerState<BuyerEnquiriesScreen> createState() => _BuyerEnquiriesScreenState();
}

class _BuyerEnquiriesScreenState extends ConsumerState<BuyerEnquiriesScreen> {
  String? _status;
  @override
  Widget build(BuildContext context) {
    if (!ref.watch(authProvider.select((s) => s.isAuthed))) {
      return Scaffold(
        appBar: AppBar(title: const Text('Enquiries')),
        body: const SignInPrompt(
          title: 'Your conversations',
          message: 'Sign in to see your enquiries and seller replies.',
          icon: Icons.chat_bubble_outline,
        ),
      );
    }
    final s = ref.watch(buyerEnquiriesProvider(_status));
    final n = ref.read(buyerEnquiriesProvider(_status).notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('Enquiries')),
      body: Column(
        children: [
          ChipRow(
            children: [
              for (final e in const {
                null: 'All',
                'pending': 'Pending',
                'responded': 'Responded',
                'closed': 'Closed',
              }.entries)
                PFilterChip(label: e.value, selected: _status == e.key, onTap: () => setState(() => _status = e.key)),
            ],
          ),
          Expanded(
            child: _enquiryList(
              context,
              s,
              refresh: n.refresh,
              more: n.loadMore,
              seller: false,
              emptyMsg: 'When you send an enquiry about a pet, the conversation shows up here.',
            ),
          ),
        ],
      ),
    );
  }
}

/// Seller Enquiries tab (inbox).
class SellerInboxScreen extends ConsumerStatefulWidget {
  const SellerInboxScreen({super.key});
  @override
  ConsumerState<SellerInboxScreen> createState() => _SellerInboxScreenState();
}

class _SellerInboxScreenState extends ConsumerState<SellerInboxScreen> {
  bool _unread = false;
  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sellerEnquiriesProvider(_unread));
    final n = ref.read(sellerEnquiriesProvider(_unread).notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('Enquiries')),
      body: Column(
        children: [
          ChipRow(
            children: [
              PFilterChip(label: 'All', selected: !_unread, onTap: () => setState(() => _unread = false)),
              PFilterChip(label: 'Unread', selected: _unread, onTap: () => setState(() => _unread = true)),
            ],
          ),
          Expanded(
            child: _enquiryList(
              context,
              s,
              refresh: n.refresh,
              more: n.loadMore,
              seller: true,
              emptyMsg: 'Buyer enquiries about your pets appear here.',
            ),
          ),
        ],
      ),
    );
  }
}

/// Conversation thread for buyer or seller. Polls every 15 s while open (no websocket yet).
class EnquiryThreadScreen extends ConsumerStatefulWidget {
  const EnquiryThreadScreen({
    super.key,
    required this.id,
    required this.seller,
    this.pollInterval = const Duration(seconds: 15),
  });
  final String id;
  final bool seller;
  final Duration pollInterval;
  @override
  ConsumerState<EnquiryThreadScreen> createState() => _EnquiryThreadScreenState();
}

class _EnquiryThreadScreenState extends ConsumerState<EnquiryThreadScreen> {
  final _msg = TextEditingController();
  final _scroll = ScrollController();
  Timer? _timer;
  bool _sending = false;

  ThreadKey get _key => (id: widget.id, seller: widget.seller);

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.pollInterval, (_) {
      if (mounted) ref.invalidate(enquiryDetailProvider(_key));
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _msg.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _msg.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      widget.seller
          ? await ref.read(sellerRepoProvider).sendMessage(widget.id, body)
          : await ref.read(buyerRepoProvider).sendMessage(widget.id, body);
      _msg.clear();
      ref.invalidate(enquiryDetailProvider(_key));
      _refreshLists();
    } catch (e) {
      if (mounted) handleActionError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _refreshLists() {
    if (widget.seller) {
      ref.invalidate(sellerEnquiriesProvider);
    } else {
      ref.invalidate(buyerEnquiriesProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = ref.watch(enquiryDetailProvider(_key));
    // The GET marks messages read; refresh list badges once.
    ref.listen(enquiryDetailProvider(_key), (prev, next) {
      if (prev == null && next.hasValue) _refreshLists();
    });
    final e = v.asData?.value;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              e?.listingTitle ?? 'Enquiry',
              style: context.tt.titleSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (e != null)
              Text(
                widget.seller ? 'From ${e.counterpartyName}' : e.counterpartyName,
                style: context.tt.bodySmall?.copyWith(color: context.pc.textMuted),
              ),
          ],
        ),
        actions: [
          if (e != null)
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (a) async {
                if (a == 'pet') {
                  context.push('/pet/${e.listingSlug.isNotEmpty ? e.listingSlug : e.listingId}');
                }
                if (a == 'report') {
                  showReportSheet(context, ref, targetType: 'enquiry', targetId: e.id);
                }
                if (a == 'close') {
                  final ok = await confirmDialog(
                    context,
                    title: 'Close this enquiry?',
                    message: 'The conversation will be marked closed.',
                    confirmLabel: 'Close',
                  );
                  if (!ok) return;
                  try {
                    widget.seller
                        ? await ref.read(sellerRepoProvider).closeEnquiry(e.id)
                        : await ref.read(buyerRepoProvider).closeEnquiry(e.id);
                    ref.invalidate(enquiryDetailProvider(_key));
                    _refreshLists();
                  } catch (err) {
                    if (context.mounted) showError(context, err);
                  }
                }
              },
              itemBuilder: (_) => [
                if (e.listingId.isNotEmpty) const PopupMenuItem(value: 'pet', child: Text('View pet')),
                if (e.status != 'closed') const PopupMenuItem(value: 'close', child: Text('Close enquiry')),
                const PopupMenuItem(value: 'report', child: Text('Report conversation')),
              ],
            ),
        ],
      ),
      body: v.when(
        skipLoadingOnReload: true,
        loading: () => const ListSkeleton(),
        error: (err, _) => ErrorState(error: err, onRetry: () => ref.invalidate(enquiryDetailProvider(_key))),
        data: (e) => Column(
          children: [
            if (e.status == 'closed')
              const Padding(
                padding: EdgeInsets.all(8),
                child: InfoBanner('This enquiry is closed.', tone: BannerTone.warning),
              ),
            Expanded(
              child: e.messages.isEmpty
                  ? const EmptyState(icon: Icons.chat_outlined, title: 'No messages yet')
                  : ListView.builder(
                      controller: _scroll,
                      reverse: true,
                      padding: const EdgeInsets.all(PSpace.gutter),
                      itemCount: e.messages.length,
                      itemBuilder: (_, i) => _Bubble(message: e.messages[e.messages.length - 1 - i]),
                    ),
            ),
            if (e.status != 'closed')
              SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(PSpace.gutter, 8, 8, 8),
                  decoration: BoxDecoration(
                    color: context.pc.surface,
                    border: Border(top: BorderSide(color: context.pc.border)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _msg,
                          minLines: 1,
                          maxLines: 4,
                          maxLength: 2000,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(hintText: 'Write a message', counterText: ''),
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton.filled(
                        tooltip: 'Send message',
                        onPressed: _sending ? null : _send,
                        icon: _sending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.send),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});
  final Message message;
  @override
  Widget build(BuildContext context) {
    final mine = message.mine;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: mine ? context.cs.primary : context.cs.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(mine ? 14 : 4),
            bottomRight: Radius.circular(mine ? 4 : 14),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                message.body,
                style: context.tt.bodyMedium?.copyWith(color: mine ? context.cs.onPrimary : context.cs.onSurface),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              timeAgo(message.createdAt),
              style: context.tt.labelSmall?.copyWith(
                color: (mine ? context.cs.onPrimary : context.pc.textMuted).withValues(alpha: 0.75),
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
