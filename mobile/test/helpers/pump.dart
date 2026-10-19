import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:petora/router.dart';

GoRouter routerOf(WidgetTester t) =>
    ProviderScope.containerOf(t.element(find.byType(MaterialApp))).read(routerProvider);

Future<void> goTo(WidgetTester t, String path) async {
  routerOf(t).go(path);
  await t.pump();
}

Finder navLabel(String label) => find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

Future<void> tapNav(WidgetTester t, String label) async {
  await t.tap(navLabel(label));
  await t.pump();
}

Future<void> tapText(WidgetTester t, String text, {bool last = false}) async {
  final f = last ? find.text(text).last : find.text(text).first;
  await t.ensureVisible(f);
  await t.tap(f, warnIfMissed: false);
  await t.pump();
}

Future<void> enter(WidgetTester t, String label, String text) async {
  // PTextField renders the label above a TextFormField - find the field that follows the label text.
  final field = find
      .descendant(
        of: find.ancestor(of: find.text(label), matching: find.byType(Column)).first,
        matching: find.byType(TextFormField),
      )
      .first;
  await t.ensureVisible(field);
  await t.enterText(field, text);
  await t.pump();
}

/// Taps a button (Filled/Outlined/Text) by its label - avoids hitting an app bar title with the same text.
Future<void> tapButton(WidgetTester t, String label) async {
  final f = find
      .byWidgetPredicate((w) => (w is FilledButton || w is OutlinedButton || w is TextButton) && _hasLabel(w, label))
      .first;
  await t.ensureVisible(f);
  await t.tap(f, warnIfMissed: false);
  await t.pump();
}

bool _hasLabel(Widget w, String label) {
  final child = w is FilledButton ? w.child : (w is OutlinedButton ? w.child : (w as TextButton).child);
  var found = false;
  void visit(Widget? x) {
    if (x is Text && x.data == label) found = true;
    if (x is Row) {
      x.children.forEach(visit);
    }
    if (x is Flexible) visit(x.child);
  }

  visit(child);
  return found;
}
