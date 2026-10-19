import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../state/auth.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/brand.dart';
import '../../ui/widgets/buttons.dart';
import '../../ui/widgets/fields.dart';
import '../../ui/widgets/states.dart';
import '../common.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.from});
  final String? from;
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _pw = TextEditingController();
  final _otp = TextEditingController();
  bool _busy = false, _needOtp = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _pw.dispose();
    _otp.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final user = await ref.read(authProvider.notifier).login(_email.text, _pw.text);
      if (!mounted) return;
      final from = widget.from;
      context.go(from != null && from.startsWith('/') && !user.isStaff ? from : homeFor(user));
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (e.kind == ErrorKind.mfaRequired) {
          _needOtp = true;
          _error = e.message;
        } else {
          _error = e.userMessage;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final expired = ref.watch(authProvider.select((s) => s.sessionExpired));
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(PSpace.xl),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Form(
            key: _form,
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const PetoraLogo(size: 40),
                  const SizedBox(height: PSpace.xl),
                  Text('Welcome back', style: context.tt.headlineMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Sign in to your PETORA account',
                    style: context.tt.bodyMedium?.copyWith(color: context.pc.textMuted),
                  ),
                  const SizedBox(height: PSpace.xl),
                  if (expired) ...[
                    const InfoBanner('Your session expired. Please sign in again.', tone: BannerTone.warning),
                    const SizedBox(height: PSpace.md),
                  ],
                  if (_error != null) ...[
                    InfoBanner(_error!, tone: BannerTone.danger, icon: Icons.error_outline),
                    const SizedBox(height: PSpace.md),
                  ],
                  PTextField(
                    label: 'Email',
                    controller: _email,
                    keyboard: TextInputType.emailAddress,
                    validator: Validators.email,
                    autofillHints: const [AutofillHints.email],
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: PSpace.lg),
                  PTextField(
                    label: 'Password',
                    controller: _pw,
                    obscure: true,
                    validator: (v) => Validators.required(v, 'Password'),
                    autofillHints: const [AutofillHints.password],
                    textInputAction: _needOtp ? TextInputAction.next : TextInputAction.done,
                    onSubmitted: (_) => _needOtp ? null : _submit(),
                  ),
                  if (_needOtp) ...[
                    const SizedBox(height: PSpace.lg),
                    PTextField(
                      label: 'Authenticator code',
                      controller: _otp,
                      keyboard: TextInputType.number,
                      validator: Validators.code6,
                      maxLength: 6,
                      formatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                  ],
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(onPressed: () => context.push('/forgot'), child: const Text('Forgot password?')),
                  ),
                  const SizedBox(height: PSpace.sm),
                  PButton('Sign in', onPressed: _submit, loading: _busy),
                  const SizedBox(height: PSpace.md),
                  Center(
                    child: TextButton(
                      onPressed: () => context.pushReplacement(
                        '/register${widget.from != null ? '?from=${Uri.encodeComponent(widget.from!)}' : ''}',
                      ),
                      child: const Text('New to PETORA? Create an account'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
