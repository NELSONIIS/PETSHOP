import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/auth.dart';
import '../../state/data.dart';
import '../search/listing_views.dart';
import '../shell/shells.dart';

class FavouritesScreen extends ConsumerWidget {
  const FavouritesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(authProvider.select((s) => s.isAuthed))) {
      return Scaffold(
        appBar: AppBar(title: const Text('Favourites')),
        body: const SignInPrompt(
          title: 'Save pets you love',
          message: 'Sign in to keep a shortlist of favourite pets and come back to them any time.',
          icon: Icons.favorite_border,
        ),
      );
    }
    final s = ref.watch(favouritesProvider);
    final n = ref.read(favouritesProvider.notifier);
    // Drop rows the user un-favourited (optimistic overrides) without refetching.
    final overrides = ref.watch(favouriteOverridesProvider);
    final visible = s.copyWith(items: s.items.where((l) => overrides[l.id] ?? true).toList());
    return Scaffold(
      appBar: AppBar(
        title: const Text('Favourites'),
        actions: [
          TextButton.icon(
            onPressed: () => context.push('/pets/recently-viewed'),
            icon: const Icon(Icons.history, size: 18),
            label: const Text('Recently viewed'),
          ),
        ],
      ),
      body: PagedListingGrid(
        state: visible,
        onRefresh: n.refresh,
        onLoadMore: n.loadMore,
        emptyIcon: Icons.favorite_border,
        emptyTitle: 'No favourites yet',
        emptyMessage: 'Tap the heart on any pet to save it here.',
        emptyActionLabel: 'Browse pets',
        emptyAction: () => context.go('/search'),
      ),
    );
  }
}
