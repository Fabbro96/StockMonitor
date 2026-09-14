import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_monitor/theme/app_theme.dart';
import 'package:stock_monitor/widgets/badges.dart';
import 'package:stock_monitor/widgets/range_bar.dart';

/// Regressione P4: i widget del DS con testo dinamico devono saper shrinkare
/// ed ellissare quando il contenitore è stretto (celle tabella, card a 380px).
/// Senza i `Flexible` interni questi casi lanciano RenderFlex overflow.
Widget _host(Widget child) => MaterialApp(
  theme: lightTheme,
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('AppBadge con label lunga ellissa senza overflow', (WidgetTester tester) async {
    await tester.pumpWidget(
      _host(
        const SizedBox(
          width: 120,
          child: AppBadge(
            label: '58,4 · Neutro con descrizione molto lunga',
            tooltip: 'RSI a 14 periodi',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('AppBadge mantiene le label multilinea', (WidgetTester tester) async {
    await tester.pumpWidget(
      _host(
        const SizedBox(
          width: 160,
          child: AppBadge(label: '▲ > 40,00 €\n▼ < 20,00 €', tone: BadgeTone.warning),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('▲ > 40,00 €\n▼ < 20,00 €'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AppPill con label lunga ellissa senza overflow', (WidgetTester tester) async {
    await tester.pumpWidget(
      _host(
        const SizedBox(
          width: 110,
          child: AppPill(label: 'Solo Portafoglio con descrizione lunga'),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('RangeBar con label lunghe ellissa senza overflow', (WidgetTester tester) async {
    await tester.pumpWidget(
      _host(
        const SizedBox(
          width: 120,
          child: RangeBar(
            positionPercent: 40,
            lowLabel: '1.234,56 USD',
            highLabel: '9.876,54 USD',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
