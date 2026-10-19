import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/auth.dart';
import '../../state/data.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/brand.dart';
import '../../ui/widgets/buttons.dart';

/// Buyer navigation: Home · Search · Favourites · Enquiries · Profile. Each branch keeps its own
/// navigator stack and scroll position (StatefulShellRoute).
class BuyerShell extends ConsumerWidget {
  const BuyerShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(authProvider.select((s) => s.isAuthed)) ? ref.watch(buyerUnreadProvider) : 0;
    return PopScope(
      canPop: shell.currentIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) shell.goBranch(0);
      },
      child: Scaffold(
        body: shell,
        bottomNavigationBar: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
          destinations: [
            const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
            const NavigationDestination(icon: Icon(Icons.search), selectedIcon: Icon(Icons.search), label: 'Search'),
            const NavigationDestination(
              icon: Icon(Icons.favorite_border),
              selectedIcon: Icon(Icons.favorite),
              label: 'Favourites',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: unread > 0,
                label: Text('$unread'),
                child: const Icon(Icons.chat_bubble_outline),
              ),
              selectedIcon: Badge(
                isLabelVisible: unread > 0,
                label: Text('$unread'),
                child: const Icon(Icons.chat_bubble),
              ),
              label: 'Enquiries',
            ),
            const NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}

/// Seller navigation: Dashboard · Listings · Enquiries · Profile, with a prominent Add-pet action.
class SellerShell extends ConsumerWidget {
  const SellerShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(sellerUnreadProvider);
    return PopScope(
      canPop: shell.currentIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) shell.goBranch(0);
      },
      child: Scaffold(
        body: shell,
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        floatingActionButton: shell.currentIndex == 3
            ? null
            : FloatingActionButton.extended(
                onPressed: () => context.push('/sell/listing/new'),
                icon: const Icon(Icons.add),
                label: const Text('Add pet'),
                tooltip: 'Add a new pet listing',
              ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard),
              label: 'Dashboard',
            ),
            const NavigationDestination(
              icon: Icon(Icons.pets_outlined),
              selectedIcon: Icon(Icons.pets),
              label: 'Listings',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: unread > 0,
                label: Text('$unread'),
                child: const Icon(Icons.chat_bubble_outline),
              ),
              selectedIcon: Badge(
                isLabelVisible: unread > 0,
                label: Text('$unread'),
                child: const Icon(Icons.chat_bubble),
              ),
              label: 'Enquiries',
            ),
            const NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}

/// Staff accounts use the web admin portal; the app only offers a polite redirect and logout.
class StaffScreen extends ConsumerWidget {
  const StaffScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(PSpace.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const PetoraLogo(size: 56),
              const SizedBox(height: 24),
              Text('Use the web admin portal', style: context.tt.headlineMedium, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                'Administration is available at petora.in/admin in your browser. The mobile app is for buyers and sellers.',
                style: context.tt.bodyLarge?.copyWith(color: context.pc.textMuted),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              PButton('Sign out', kind: PButtonKind.outline, onPressed: () => ref.read(authProvider.notifier).logout()),
            ],
          ),
        ),
      ),
    );
  }
}

/// Guests see a prompt on tabs that need an account.
class SignInPrompt extends StatelessWidget {
  const SignInPrompt({super.key, required this.title, required this.message, this.icon = Icons.lock_outline});
  final String title, message;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(PSpace.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: context.cs.primaryContainer, shape: BoxShape.circle),
            child: Icon(icon, size: 30, color: context.cs.primary),
          ),
          const SizedBox(height: 16),
          Text(title, style: context.tt.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(
            message,
            style: context.tt.bodyMedium?.copyWith(color: context.pc.textMuted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          PButton('Sign in', onPressed: () => context.push('/login'), expand: false),
          TextButton(onPressed: () => context.push('/register'), child: const Text('Create a free account')),
        ],
      ),
    ),
  );
}
