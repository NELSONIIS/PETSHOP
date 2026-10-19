import 'package:flutter/material.dart';

import '../tokens.dart';

/// Search bar. With [onTap] it behaves as a launcher (read-only); otherwise it's an editable field.
class PSearchBar extends StatelessWidget {
  const PSearchBar({
    super.key,
    this.controller,
    this.hint = 'Search pets, breeds, cities',
    this.onTap,
    this.onSubmitted,
    this.onChanged,
    this.trailing,
    this.autofocus = false,
  });
  final TextEditingController? controller;
  final String hint;
  final VoidCallback? onTap;
  final ValueChanged<String>? onSubmitted, onChanged;
  final Widget? trailing;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final readOnly = onTap != null;
    return Semantics(
      textField: !readOnly,
      button: readOnly,
      label: hint,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: context.pc.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: context.pc.border),
        ),
        padding: const EdgeInsets.only(left: 14, right: 4),
        child: Row(
          children: [
            Icon(Icons.search, color: context.pc.textMuted, size: PIcon.lg),
            const SizedBox(width: 8),
            Expanded(
              child: readOnly
                  ? InkWell(
                      onTap: onTap,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          hint,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.tt.bodyMedium?.copyWith(color: context.pc.textMuted),
                        ),
                      ),
                    )
                  : TextField(
                      controller: controller,
                      autofocus: autofocus,
                      textInputAction: TextInputAction.search,
                      onSubmitted: onSubmitted,
                      onChanged: onChanged,
                      style: context.tt.bodyLarge,
                      decoration: InputDecoration(
                        hintText: hint,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        isDense: true,
                      ),
                    ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

class PFilterChip extends StatelessWidget {
  const PFilterChip({super.key, required this.label, required this.selected, required this.onTap, this.icon});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: FilterChip(
      label: Text(label),
      avatar: icon == null ? null : Icon(icon, size: 16),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      selectedColor: context.cs.primaryContainer,
      labelStyle: context.tt.labelMedium?.copyWith(
        color: selected ? context.cs.onPrimaryContainer : context.cs.onSurface,
      ),
      side: BorderSide(color: selected ? context.cs.primary : context.pc.border),
    ),
  );
}

/// Horizontally scrolling chip row.
class ChipRow extends StatelessWidget {
  const ChipRow({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.symmetric(horizontal: PSpace.gutter),
  });
  final List<Widget> children;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 48,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      children: [for (final c in children) Center(child: c)],
    ),
  );
}

/// Segmented selector for small enumerations.
class SegmentRow<T> extends StatelessWidget {
  const SegmentRow({super.key, required this.value, required this.options, required this.onChanged});
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 4,
    children: [
      for (final e in options.entries)
        PFilterChip(label: e.value, selected: e.key == value, onTap: () => onChanged(e.key)),
    ],
  );
}
