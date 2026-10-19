import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/data.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/brand.dart';
import '../../ui/widgets/buttons.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pc = PageController();
  int _i = 0;

  static const _pages = [
    (Icons.pets, 'Find your new companion', 'Browse pets from sellers near you - always free, no account needed.'),
    (
      Icons.verified_user_outlined,
      'Know who you are buying from',
      'Sellers can be verified by our team. Look for the Verified seller badge and read the health disclosures.',
    ),
    (
      Icons.chat_bubble_outline,
      'Talk to sellers directly',
      'Unlock seller contact details with a membership and send enquiries inside the app.',
    ),
  ];

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  Future<void> _go(String route) async {
    await markOnboardingSeen(ref);
    if (mounted) context.go(route);
  }

  @override
  Widget build(BuildContext context) {
    final last = _i == _pages.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(PSpace.xl),
          child: Column(
            children: [
              const Align(alignment: Alignment.centerLeft, child: PetoraLogo(size: 32)),
              Expanded(
                child: PageView.builder(
                  controller: _pc,
                  itemCount: _pages.length,
                  onPageChanged: (i) => setState(() => _i = i),
                  itemBuilder: (_, i) {
                    final p = _pages[i];
                    return SingleChildScrollView(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(height: 48),
                          Container(
                            width: 140,
                            height: 140,
                            decoration: BoxDecoration(color: context.cs.primaryContainer, shape: BoxShape.circle),
                            child: Icon(p.$1, size: 64, color: context.cs.primary),
                          ),
                          const SizedBox(height: 32),
                          Text(p.$2, style: context.tt.headlineMedium, textAlign: TextAlign.center),
                          const SizedBox(height: 10),
                          Text(
                            p.$3,
                            style: context.tt.bodyLarge?.copyWith(color: context.pc.textMuted),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _pages.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.all(3),
                      width: i == _i ? 22 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _i ? context.cs.primary : context.pc.border,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: PSpace.xl),
              if (!last)
                PButton(
                  'Next',
                  onPressed: () => _pc.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
                )
              else ...[
                PButton('Create account', onPressed: () => _go('/register')),
                const SizedBox(height: 8),
                PButton('I already have an account', kind: PButtonKind.outline, onPressed: () => _go('/login')),
              ],
              PButton('Browse as guest', kind: PButtonKind.ghost, onPressed: () => _go('/')),
            ],
          ),
        ),
      ),
    );
  }
}
