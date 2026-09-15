import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_monitor/theme/app_theme.dart';
import 'package:stock_monitor/widgets/app_progress_bar.dart';

/// Regressione `AppProgressBar`: il fill determinato deve disegnarsi a piena
/// altezza e largo `value × barra` (prima era invisibile: mancavano
/// `heightFactor: 1` e `SizedBox.expand`).
Widget _host(Widget child) => MaterialApp(
  theme: lightTheme,
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets(
    'AppProgressBar determinata: fill a metà larghezza e a piena altezza',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(
          const SizedBox(
            width: 100,
            child: AppProgressBar(value: 0.5, height: 5),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      // La barra occupa i 100px del contenitore...
      expect(tester.getSize(find.byType(AppProgressBar)).width, 100);

      // ...e il fill è il 50% della larghezza per tutta l'altezza (5px).
      final Finder fill = find.descendant(
        of: find.byType(FractionallySizedBox),
        matching: find.byType(ColoredBox),
      );
      expect(fill, findsOneWidget);
      final Size fillSize = tester.getSize(fill);
      expect(fillSize.width, moreOrLessEquals(50, epsilon: 0.5));
      expect(fillSize.height, 5);
    },
  );

  testWidgets(
    'AppProgressBar: il segnaposto target compare solo se impostato',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(
          const SizedBox(
            width: 100,
            child: AppProgressBar(value: 0.5, target: 0.25),
          ),
        ),
      );
      await tester.pump();

      final Finder marker = find.descendant(
        of: find.byType(AppProgressBar),
        matching: find.byType(Align),
      );
      expect(marker, findsOneWidget);
      expect(tester.getSize(marker).height, 5);

      await tester.pumpWidget(
        _host(const SizedBox(width: 100, child: AppProgressBar(value: 0.5))),
      );
      await tester.pump();

      expect(
        find.descendant(
          of: find.byType(AppProgressBar),
          matching: find.byType(Align),
        ),
        findsNothing,
      );
    },
  );

  testWidgets('AppProgressBar con value null: barra indeterminata', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(const SizedBox(width: 100, child: AppProgressBar(value: null))),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byType(FractionallySizedBox), findsNothing);
  });
}
