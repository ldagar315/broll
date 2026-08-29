import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:book_wheel/main.dart';

void main() {
  testWidgets('loads the library, continuously scrolls, and tracks focus', (
    tester,
  ) async {
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues({
      ReaderProgress.lastOpenedKey: 'adventures-of-sherlock-holmes',
      ReaderProgress.keyForId('adventures-of-sherlock-holmes'): 4,
    });

    await tester.pumpWidget(const BookWheelApp());
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(find.text('Broll'), findsOneWidget);
    expect(find.byKey(const ValueKey('theme-toggle-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('import-book-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('import-book-cta')), findsOneWidget);
    expect(find.text('Your library'), findsOneWidget);
    expect(find.text('The Lantern at Lake Merrow'), findsOneWidget);
    expect(find.text('Avery Finch'), findsOneWidget);
    expect(find.text('The Adventures of Sherlock Holmes'), findsOneWidget);
    expect(find.text('Pick up where you left off'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Sherlock');
    await tester.pump();
    expect(find.text('Search results'), findsOneWidget);
    expect(find.text('The Adventures of Sherlock Holmes'), findsOneWidget);
    expect(find.text('The Lantern at Lake Merrow'), findsNothing);

    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    await tester.tap(find.text('The Lantern at Lake Merrow'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('reader-scroll-view')), findsOneWidget);
    expect(find.byType(PageView), findsNothing);
    expect(find.byKey(const ValueKey('book-progress')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('chapter-navigation-button')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('reader-metadata')), findsOneWidget);
    expect(find.text('1 / 25'), findsOneWidget);
    expect(
      find.textContaining('Mara Vale arrived at Lake Merrow'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('reader-focus-0')), findsOneWidget);
    final initialCurrentOpacity = tester.widget<AnimatedOpacity>(
      find.byKey(const ValueKey('reader-focus-0')),
    );
    final initialNextOpacity = tester.widget<AnimatedOpacity>(
      find.byKey(const ValueKey('reader-focus-1')),
    );
    expect(initialCurrentOpacity.opacity, 1);
    expect(initialNextOpacity.opacity, 0.32);

    await tester.drag(
      find.byKey(const ValueKey('reader-scroll-view')),
      const Offset(0, -220),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final afterScrollOpacity = tester.widget<AnimatedOpacity>(
      find.byKey(const ValueKey('reader-focus-0')),
    );
    expect(afterScrollOpacity.opacity, lessThan(1));
    expect(
      find.textContaining('At the end of the pier stood a lighthouse'),
      findsOneWidget,
    );

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Pick up where you left off'), findsOneWidget);
  });

  testWidgets('toggles between light and dark themes', (tester) async {
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const BookWheelApp());
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));

    final homeContext = tester.element(find.widgetWithText(AppBar, 'Broll'));
    expect(Theme.of(homeContext).brightness, Brightness.light);

    await tester.tap(find.byKey(const ValueKey('theme-toggle-button')));
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).theme?.brightness,
      Brightness.dark,
    );
  });
}
