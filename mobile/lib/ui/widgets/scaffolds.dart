import 'package:flutter/material.dart';

import '../tokens.dart';
import 'brand.dart';

/// Standard app bar used by detail screens.
PreferredSizeWidget petoraAppBar(
  BuildContext context,
  String title, {
  List<Widget>? actions,
  bool logo = false,
  PreferredSizeWidget? bottom,
}) => AppBar(
  title: logo ? const PetoraLogo(size: 30) : Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
  actions: actions,
  bottom: bottom,
);

/// Scrollable form page with bottom-pinned action area that respects the keyboard and system insets.
class FormPage extends StatelessWidget {
  const FormPage({super.key, required this.title, required this.children, this.bottom, this.actions, this.padding});
  final String title;
  final List<Widget> children;
  final Widget? bottom;
  final List<Widget>? actions;
  final EdgeInsets? padding;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: petoraAppBar(context, title, actions: actions),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: padding ?? const EdgeInsets.all(PSpace.gutter),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: children,
            ),
          ),
          if (bottom != null)
            Container(
              padding: const EdgeInsets.fromLTRB(PSpace.gutter, 10, PSpace.gutter, 10),
              decoration: BoxDecoration(
                color: context.pc.surface,
                border: Border(top: BorderSide(color: context.pc.border)),
              ),
              child: bottom,
            ),
        ],
      ),
    ),
  );
}

const gap8 = SizedBox(height: 8);
const gap12 = SizedBox(height: 12);
const gap16 = SizedBox(height: 16);
const gap24 = SizedBox(height: 24);
