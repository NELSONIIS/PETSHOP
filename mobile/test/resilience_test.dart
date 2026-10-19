import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_backend.dart';
import 'helpers/pump.dart';

Handler offline() =>
    (o) => throw DioException(requestOptions: o, type: DioExceptionType.connectionError);

void main() {
  group('error + retry states', () {
    testWidgets('home shows an offline state and recovers on Try again', (t) async {
      useScreen(t, h: 900);
      final b = FakeBackend();
      b.on('GET', '/categories', ok([categoryJson()]));
      b.on('GET', '/sellers', okPaged([]));
      var online = false;
      b.on(
        'GET',
        '/pets',
        (o) => online
            ? okPaged([listingJson(title: 'Recovered Labrador')])
            : throw DioException(requestOptions: o, type: DioExceptionType.connectionError),
      );
      await t.pumpWidget(await buildApp(b));
      await settle(t);
      expect(find.text("You're offline"), findsWidgets);
      expect(find.textContaining('No internet connection'), findsWidgets);
      expect(find.text('Recovered Labrador'), findsNothing);
      online = true;
      await tapText(t, 'Try again');
      await settle(t, frames: 10);
      expect(find.text("You're offline"), findsNothing);
      expect(find.text('Recovered Labrador'), findsWidgets);
    });

    testWidgets('pet detail: server error shows reference id and retry works', (t) async {
      useScreen(t, h: 900);
      final b = FakeBackend();
      publicHome(b);
      var fail = true;
      b.on('GET', '/pets/*', (o) => fail ? err(500, 'internal_error', 'boom') : ok(listingJson()));
      b.on('GET', '/pets/*/similar', ok([]));
      b.on('POST', '/pets/*/view', noContent());
      await t.pumpWidget(await buildApp(b));
      await settle(t);
      await goTo(t, '/pet/slug-l-1');
      await settle(t, frames: 6);
      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.textContaining('Ref: req-test'), findsOneWidget);
      fail = false;
      await tapText(t, 'Try again');
      await settle(t, frames: 8);
      expect(find.text('Friendly Labrador puppy'), findsOneWidget);
    });

    testWidgets('pet not found shows an error state, not a crash', (t) async {
      useScreen(t);
      final b = FakeBackend();
      publicHome(b);
      b.on('GET', '/pets/*', err(404, 'not_found', 'Pet not found'));
      await t.pumpWidget(await buildApp(b));
      await settle(t);
      await goTo(t, '/pet/gone');
      await settle(t, frames: 6);
      expect(find.text('Pet not found'), findsOneWidget);
    });

    testWidgets('splash offline: keeps the session and retries bootstrap', (t) async {
      useScreen(t);
      final b = FakeBackend();
      publicHome(b);
      var online = false;
      b.on(
        'GET',
        '/me',
        (o) => online ? ok(userJson()) : throw DioException(requestOptions: o, type: DioExceptionType.connectionError),
      );
      b.on('GET', '/notifications/unread-count', ok({'count': 0}));
      b.on('GET', '/buyer/enquiries', okPaged([]));
      b.on('GET', '/buyer/recently-viewed', ok([]));
      final tokens = signedInTokens();
      await t.pumpWidget(await buildApp(b, tokens: tokens));
      await settle(t, frames: 10);
      expect(find.text("You're offline"), findsOneWidget);
      expect(await tokens.read(), isNotNull, reason: 'tokens survive a network failure');
      online = true;
      await tapText(t, 'Try again');
      await settle(t, frames: 10);
      expect(navLabel('Home'), findsOneWidget);
    });

    testWidgets('enquiries list: error then retry', (t) async {
      useScreen(t);
      final b = FakeBackend();
      publicHome(b);
      b.on('GET', '/me', ok(userJson()));
      b.on('GET', '/notifications/unread-count', ok({'count': 0}));
      b.on('GET', '/buyer/recently-viewed', ok([]));
      var fail = true;
      b.on(
        'GET',
        '/buyer/enquiries',
        (o) => fail
            ? err(503, 'maintenance', 'Back soon')
            : okPaged([
                {
                  'id': 'e-1',
                  'status': 'responded',
                  'listing': {'id': 'l-1', 'slug': 's', 'title': 'Lab pup'},
                  'counterparty': {'name': 'Paws'},
                  'last_message': 'Yes available',
                  'last_message_at': '2026-10-18T10:00:00Z',
                  'unread': 1,
                  'created_at': '2026-10-18T09:00:00Z',
                },
              ]),
      );
      await t.pumpWidget(await buildApp(b, tokens: signedInTokens()));
      await settle(t);
      await tapNav(t, 'Enquiries');
      await settle(t, frames: 6);
      expect(find.text('Back soon'), findsOneWidget);
      fail = false;
      await tapText(t, 'Try again');
      await settle(t, frames: 8);
      expect(find.text('Lab pup'), findsOneWidget);
      expect(find.text('Yes available'), findsOneWidget);
    });
  });

  group('pagination and preserved state', () {
    List<Map<String, dynamic>> page(int n) => [
      for (var i = 0; i < 12; i++) listingJson(id: 'p$n-$i', title: 'Pet $n-$i'),
    ];

    testWidgets('search loads page 2 when scrolling to the end (never everything at once)', (t) async {
      useScreen(t);
      final b = FakeBackend();
      b.on('GET', '/categories', ok([categoryJson()]));
      b.on('GET', '/pets', (o) {
        final p = o.queryParameters['page'] ?? 1;
        return ok(page(p as int), meta: {'page': p, 'per_page': 12, 'total': 24, 'total_pages': 2});
      });
      await t.pumpWidget(await buildApp(b));
      await settle(t);
      await tapNav(t, 'Search');
      await settle(t, frames: 8);
      expect(find.text('24 pets'), findsOneWidget);
      final pagesBefore = b.log.where((o) => o.path == '/pets' && o.queryParameters['page'] == 2).length;
      expect(pagesBefore, 0);
      await t.dragUntilVisible(
        find.text('Pet 2-0'),
        find.byType(CustomScrollView).last,
        const Offset(0, -400),
        maxIteration: 60,
      );
      await settle(t, frames: 5);
      expect(find.text('Pet 2-0'), findsOneWidget);
      expect(b.log.where((o) => o.path == '/pets' && o.queryParameters['page'] == 2).length, 1);
    });

    testWidgets('failed load-more offers a retry without losing loaded items', (t) async {
      useScreen(t);
      final b = FakeBackend();
      b.on('GET', '/categories', ok([categoryJson()]));
      var failPage2 = true;
      b.on('GET', '/pets', (o) {
        final p = o.queryParameters['page'] as int? ?? 1;
        if (p == 2 && failPage2) throw DioException(requestOptions: o, type: DioExceptionType.connectionError);
        return ok(page(p), meta: {'page': p, 'per_page': 12, 'total': 24, 'total_pages': 2});
      });
      await t.pumpWidget(await buildApp(b));
      await settle(t);
      await tapNav(t, 'Search');
      await settle(t, frames: 8);
      await t.dragUntilVisible(
        find.text('Retry loading more'),
        find.byType(CustomScrollView).last,
        const Offset(0, -400),
        maxIteration: 80,
      );
      final failedTries = b.log.where((o) => o.path == '/pets' && o.queryParameters['page'] == 2).length;
      expect(failedTries, 1);
      failPage2 = false;
      await tapText(t, 'Retry loading more');
      await settle(t, frames: 6);
      expect(find.text('Retry loading more'), findsNothing);
      expect(b.log.where((o) => o.path == '/pets' && o.queryParameters['page'] == 2).length, 2);
    });

    testWidgets('search query survives opening a listing and coming back', (t) async {
      useScreen(t);
      final b = FakeBackend();
      b.on('GET', '/categories', ok([categoryJson()]));
      b.on('GET', '/pets', okPaged([listingJson(title: 'Beagle puppy')]));
      b.on('GET', '/pets/*', ok(listingJson(title: 'Beagle puppy')));
      b.on('GET', '/pets/*/similar', ok([]));
      b.on('POST', '/pets/*/view', noContent());
      await t.pumpWidget(await buildApp(b));
      await settle(t);
      await tapNav(t, 'Search');
      await settle(t, frames: 6);
      await t.enterText(find.byType(TextField).first, 'beagle');
      await t.testTextInput.receiveAction(TextInputAction.search);
      await settle(t, frames: 8);
      expect(b.log.any((o) => o.path == '/pets' && o.queryParameters['q'] == 'beagle'), isTrue);
      final callsBefore = b.count('GET', '/pets');
      await tapText(t, 'Beagle puppy');
      await settle(t, frames: 8);
      expect(find.text('Seller contact is locked'), findsOneWidget);
      await t.pageBack();
      await settle(t, frames: 6);
      expect(find.text('beagle'), findsOneWidget);
      expect(find.text('Beagle puppy'), findsOneWidget);
      expect(b.count('GET', '/pets'), callsBefore, reason: 'results were not refetched on return');
    });

    testWidgets('Android back from another tab returns to Home before leaving the app', (t) async {
      useScreen(t);
      final b = FakeBackend();
      publicHome(b);
      await t.pumpWidget(await buildApp(b));
      await settle(t);
      await tapNav(t, 'Favourites');
      await settle(t, frames: 4);
      expect(find.text('Save pets you love'), findsOneWidget);
      await t.binding.handlePopRoute();
      await settle(t, frames: 6);
      expect(find.text('Featured pets'), findsOneWidget);
    });

    testWidgets('optimistic favourite reverts when the server call fails', (t) async {
      useScreen(t);
      final b = FakeBackend();
      publicHome(b);
      b.on('GET', '/me', ok(userJson()));
      b.on('GET', '/notifications/unread-count', ok({'count': 0}));
      b.on('GET', '/buyer/enquiries', okPaged([]));
      b.on('GET', '/buyer/recently-viewed', ok([]));
      b.on('POST', '/favourites', err(500, 'internal_error', 'nope'));
      await t.pumpWidget(await buildApp(b, tokens: signedInTokens()));
      await settle(t);
      await t.tap(find.byTooltip('Save to favourites').first);
      await settle(t, frames: 6);
      expect(find.byTooltip('Remove from favourites'), findsNothing);
      expect(find.textContaining('Could not update favourites'), findsOneWidget);
    });
  });
}
