import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../state/providers.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/buttons.dart';
import '../../ui/widgets/dialogs.dart';
import '../../ui/widgets/fields.dart';
import '../../ui/widgets/scaffolds.dart';
import '../../ui/widgets/states.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepoProvider).forgotPassword(_email.text);
      if (mounted) {
        context.pushReplacement('/reset?email=${Uri.encodeComponent(_email.text.trim())}');
      }
    } on AppException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.userMessage;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => FormPage(
    title: 'Forgot password',
    bottom: PButton('Send reset code', onPressed: _send, loading: _busy),
    children: [
      Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "We'll email you a code to reset your password.",
              style: context.tt.bodyMedium?.copyWith(color: context.pc.textMuted),
            ),
            gap16,
            if (_error != null) ...[InfoBanner(_error!, tone: BannerTone.danger), gap12],
            PTextField(
              label: 'Email',
              controller: _email,
              keyboard: TextInputType.emailAddress,
              validator: Validators.email,
              onSubmitted: (_) => _send(),
            ),
          ],
        ),
      ),
    ],
  );
}

class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key, this.email = ''});
  final String email;
  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _form = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.email);
  final _code = TextEditingController();
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_email, _code, _pw, _pw2]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _reset() async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepoProvider).resetPassword(_email.text, _code.text, _pw.text);
      if (!mounted) return;
      showSnack(context, 'Password updated. Please sign in.');
      context.go('/login');
    } on AppException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.fieldErrors.values.isNotEmpty ? e.fieldErrors.values.first : e.userMessage;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => FormPage(
    title: 'Reset password',
    bottom: PButton('Update password', onPressed: _reset, loading: _busy),
    children: [
      Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_error != null) ...[InfoBanner(_error!, tone: BannerTone.danger), gap12],
            PTextField(
              label: 'Email',
              controller: _email,
              keyboard: TextInputType.emailAddress,
              validator: Validators.email,
            ),
            gap16,
            PTextField(
              label: '6-digit code',
              controller: _code,
              keyboard: TextInputType.number,
              maxLength: 6,
              validator: Validators.code6,
            ),
            gap16,
            PTextField(
              label: 'New password',
              controller: _pw,
              obscure: true,
              validator: Validators.password,
              helper: 'At least 10 characters with a letter and a number',
            ),
            gap16,
            PTextField(
              label: 'Confirm new password',
              controller: _pw2,
              obscure: true,
              validator: (v) => v == _pw.text ? null : 'Passwords do not match',
            ),
          ],
        ),
      ),
    ],
  );
}
