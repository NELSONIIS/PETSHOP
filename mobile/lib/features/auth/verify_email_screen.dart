import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../state/auth.dart';
import '../../state/providers.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/buttons.dart';
import '../../ui/widgets/dialogs.dart';
import '../../ui/widgets/fields.dart';
import '../../ui/widgets/scaffolds.dart';
import '../../ui/widgets/states.dart';
import '../common.dart';

class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key, this.next});
  final String? next;
  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  final _form = GlobalKey<FormState>();
  final _code = TextEditingController();
  bool _busy = false, _resending = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _done() => context.go(widget.next ?? homeFor(ref.read(authProvider).user));

  Future<void> _verify() async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepoProvider).verifyEmail(_code.text);
      await ref.read(authProvider.notifier).refreshUser();
      if (!mounted) return;
      showSnack(context, 'Email verified');
      _done();
    } on AppException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.userMessage;
        });
      }
    }
  }

  Future<void> _resend() async {
    setState(() => _resending = true);
    try {
      await ref.read(authRepoProvider).resendVerification();
      if (mounted) showSnack(context, 'A new code has been sent');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = ref.watch(authProvider).user?.email ?? 'your email';
    return FormPage(
      title: 'Verify email',
      bottom: PButton('Verify', onPressed: _verify, loading: _busy),
      children: [
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Enter the 6-digit code', style: context.tt.headlineMedium),
              const SizedBox(height: 6),
              Text(
                'We sent a code to $email. It expires in 15 minutes.',
                style: context.tt.bodyMedium?.copyWith(color: context.pc.textMuted),
              ),
              const SizedBox(height: PSpace.xl),
              if (_error != null) ...[InfoBanner(_error!, tone: BannerTone.danger), const SizedBox(height: PSpace.md)],
              PTextField(
                label: 'Verification code',
                controller: _code,
                keyboard: TextInputType.number,
                maxLength: 6,
                validator: Validators.code6,
                formatters: [FilteringTextInputFormatter.digitsOnly],
                autofocus: true,
                onSubmitted: (_) => _verify(),
              ),
              const SizedBox(height: PSpace.md),
              Row(
                children: [
                  TextButton(
                    onPressed: _resending ? null : _resend,
                    child: Text(_resending ? 'Sending...' : 'Resend code'),
                  ),
                  const Spacer(),
                  TextButton(onPressed: _done, child: const Text('Skip for now')),
                ],
              ),
              gap8,
              Text(
                'You can browse without verifying, but contacting sellers and purchasing a plan require a verified email.',
                style: context.tt.bodySmall?.copyWith(color: context.pc.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
