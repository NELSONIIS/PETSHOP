import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens.dart';

/// Text field with a label above it, inline validation and optional password toggle.
class PTextField extends StatefulWidget {
  const PTextField({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.validator,
    this.obscure = false,
    this.keyboard,
    this.maxLines = 1,
    this.maxLength,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.autofillHints,
    this.prefix,
    this.suffix,
    this.errorText,
    this.formatters,
    this.enabled = true,
    this.autofocus = false,
    this.minLines,
    this.initialValue,
    this.helper,
  });

  final String label;
  final TextEditingController? controller;
  final String? hint, errorText, initialValue, helper;
  final String? Function(String?)? validator;
  final bool obscure, enabled, autofocus;
  final TextInputType? keyboard;
  final int maxLines;
  final int? maxLength, minLines;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged, onSubmitted;
  final Iterable<String>? autofillHints;
  final Widget? prefix, suffix;
  final List<TextInputFormatter>? formatters;

  @override
  State<PTextField> createState() => _PTextFieldState();
}

class _PTextFieldState extends State<PTextField> {
  late bool _hidden = widget.obscure;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(widget.label, style: context.tt.labelMedium?.copyWith(color: context.pc.textMuted)),
        ),
        TextFormField(
          controller: widget.controller,
          initialValue: widget.controller == null ? widget.initialValue : null,
          validator: widget.validator,
          obscureText: _hidden,
          keyboardType: widget.keyboard,
          maxLines: widget.obscure ? 1 : widget.maxLines,
          minLines: widget.minLines,
          maxLength: widget.maxLength,
          textInputAction: widget.textInputAction,
          onChanged: widget.onChanged,
          onFieldSubmitted: widget.onSubmitted,
          autofillHints: widget.autofillHints,
          inputFormatters: widget.formatters,
          enabled: widget.enabled,
          autofocus: widget.autofocus,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          decoration: InputDecoration(
            hintText: widget.hint,
            errorText: widget.errorText,
            helperText: widget.helper,
            prefixIcon: widget.prefix,
            counterText: '',
            suffixIcon: widget.obscure
                ? IconButton(
                    tooltip: _hidden ? 'Show password' : 'Hide password',
                    icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: PIcon.md),
                    onPressed: () => setState(() => _hidden = !_hidden),
                  )
                : widget.suffix,
          ),
        ),
      ],
    );
  }
}

class PDropdown<T> extends StatelessWidget {
  const PDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.validator,
    this.hint,
  });
  final String label;
  final T? value;
  final Map<T, String> items;
  final ValueChanged<T?>? onChanged;
  final String? Function(T?)? validator;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(label, style: context.tt.labelMedium?.copyWith(color: context.pc.textMuted)),
        ),
        DropdownButtonFormField<T>(
          initialValue: items.containsKey(value) ? value : null,
          isExpanded: true,
          validator: validator,
          hint: hint == null ? null : Text(hint!),
          items: [
            for (final e in items.entries)
              DropdownMenuItem(
                value: e.key,
                child: Text(e.value, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: onChanged,
          autovalidateMode: AutovalidateMode.onUserInteraction,
        ),
      ],
    );
  }
}

/// Shared validators.
class Validators {
  Validators._();
  static String? required(String? v, [String name = 'This field']) =>
      (v == null || v.trim().isEmpty) ? '$name is required' : null;
  static String? email(String? v) {
    if (v == null || v.trim().isEmpty) return 'Email is required';
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$').hasMatch(v.trim()) ? null : 'Enter a valid email address';
  }

  static String? phone(String? v, {bool optional = false}) {
    final s = (v ?? '').replaceAll(' ', '');
    if (s.isEmpty) return optional ? null : 'Phone number is required';
    return RegExp(r'^\+?[0-9]{10,15}$').hasMatch(s) ? null : 'Enter 10-15 digits';
  }

  static String? password(String? v) {
    if (v == null || v.isEmpty) return 'Password is required';
    if (v.length < 10) return 'Use at least 10 characters';
    if (!RegExp(r'[A-Za-z]').hasMatch(v) || !RegExp(r'\d').hasMatch(v)) {
      return 'Include a letter and a number';
    }
    return null;
  }

  static String? code6(String? v) => RegExp(r'^\d{6}$').hasMatch((v ?? '').trim()) ? null : 'Enter the 6-digit code';
  static String? minLen(String? v, int n, String name) =>
      (v ?? '').trim().length < n ? '$name must be at least $n characters' : null;
}
