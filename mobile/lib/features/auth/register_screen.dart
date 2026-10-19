import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../state/auth.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/buttons.dart';
import '../../ui/widgets/fields.dart';
import '../../ui/widgets/inputs.dart';
import '../../ui/widgets/states.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key, this.initialRole = 'buyer', this.from});
  final String initialRole;
  final String? from;
  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _pw = TextEditingController();
  late String _role = widget.initialRole == 'seller' ? 'seller' : 'buyer';
  bool _terms = false, _busy = false;
  String? _error, _termsError;
  Map<String, String> _fieldErrors = {};

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _pw]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final ok = _form.currentState?.validate() ?? false;
    setState(() => _termsError = _terms ? null : 'Please accept the Terms and Privacy Policy');
    if (!ok || !_terms) return;
    setState(() {
      _busy = true;
      _error = null;
      _fieldErrors = {};
    });
    try {
      await ref
          .read(authProvider.notifier)
          .register(name: _name.text, email: _email.text, phone: _phone.text, password: _pw.text, role: _role);
      if (!mounted) return;
      final next = _role == 'seller' ? '/sell/onboarding' : (widget.from ?? '/setup/location');
      context.go('/verify-email?next=${Uri.encodeComponent(next)}');
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _fieldErrors = e.fieldErrors;
        _error = e.fieldErrors.isEmpty ? e.userMessage : null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
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
                  Text('I want to', style: context.tt.labelMedium?.copyWith(color: context.pc.textMuted)),
                  const SizedBox(height: 6),
                  SegmentRow<String>(
                    value: _role,
                    options: const {'buyer': 'Find a pet', 'seller': 'Sell / rehome pets'},
                    onChanged: (v) => setState(() => _role = v),
                  ),
                  const SizedBox(height: PSpace.lg),
                  if (_error != null) ...[
                    InfoBanner(_error!, tone: BannerTone.danger),
                    const SizedBox(height: PSpace.md),
                  ],
                  PTextField(
                    label: 'Full name',
                    controller: _name,
                    validator: (v) => Validators.minLen(v, 2, 'Name'),
                    autofillHints: const [AutofillHints.name],
                    textInputAction: TextInputAction.next,
                    errorText: _fieldErrors['name'],
                  ),
                  const SizedBox(height: PSpace.lg),
                  PTextField(
                    label: 'Email',
                    controller: _email,
                    keyboard: TextInputType.emailAddress,
                    validator: Validators.email,
                    autofillHints: const [AutofillHints.email],
                    textInputAction: TextInputAction.next,
                    errorText: _fieldErrors['email'],
                  ),
                  const SizedBox(height: PSpace.lg),
                  PTextField(
                    label: _role == 'seller' ? 'Phone' : 'Phone (optional)',
                    controller: _phone,
                    keyboard: TextInputType.phone,
                    validator: (v) => Validators.phone(v, optional: _role != 'seller'),
                    autofillHints: const [AutofillHints.telephoneNumber],
                    textInputAction: TextInputAction.next,
                    errorText: _fieldErrors['phone'],
                  ),
                  const SizedBox(height: PSpace.lg),
                  PTextField(
                    label: 'Password',
                    controller: _pw,
                    obscure: true,
                    validator: Validators.password,
                    autofillHints: const [AutofillHints.newPassword],
                    helper: 'At least 10 characters with a letter and a number',
                    errorText: _fieldErrors['password'],
                  ),
                  const SizedBox(height: PSpace.md),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _terms,
                    onChanged: (v) => setState(() => _terms = v ?? false),
                    title: Text.rich(
                      TextSpan(
                        style: context.tt.bodySmall,
                        children: [
                          const TextSpan(text: 'I agree to the '),
                          TextSpan(
                            text: 'Terms of Service',
                            style: TextStyle(color: context.cs.primary, fontWeight: FontWeight.w600),
                            recognizer: TapGestureRecognizer()..onTap = () => context.push('/legal/terms'),
                          ),
                          const TextSpan(text: ' and '),
                          TextSpan(
                            text: 'Privacy Policy',
                            style: TextStyle(color: context.cs.primary, fontWeight: FontWeight.w600),
                            recognizer: TapGestureRecognizer()..onTap = () => context.push('/legal/privacy'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_termsError != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 8),
                      child: Text(_termsError!, style: context.tt.bodySmall?.copyWith(color: context.cs.error)),
                    ),
                  const SizedBox(height: PSpace.md),
                  PButton('Create account', onPressed: _submit, loading: _busy),
                  const SizedBox(height: PSpace.sm),
                  Center(
                    child: TextButton(
                      onPressed: () => context.pushReplacement('/login'),
                      child: const Text('Already have an account? Sign in'),
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
