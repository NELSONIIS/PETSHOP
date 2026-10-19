import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/auth.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/brand.dart';
import '../../ui/widgets/states.dart';

/// Shows the brand while the session is restored; offers Retry when the network is down.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});
  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(authProvider.notifier).bootstrap());
  }

  @override
  Widget build(BuildContext context) {
    final err = ref.watch(authProvider).bootError;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: err != null
              ? ErrorState(error: err, onRetry: () => ref.read(authProvider.notifier).bootstrap())
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const PetoraLogo(size: 64),
                    const SizedBox(height: PSpace.xl),
                    SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: context.cs.primary),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
