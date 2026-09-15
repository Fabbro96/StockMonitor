import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_monitor/features/portfolio/portfolio_screen.dart'
    show PortfolioSaveBar;
import 'package:stock_monitor/widgets/app_callout.dart';

/// Widget test di paint per i bordi accent dei miei file: un [Border]
/// asimmetrico combinato con `borderRadius` lancia
/// `A borderRadius can only be given on borders with uniform colors` a ogni
/// paint. Il fix usa la striscia clippata su [Stack] (come `AppCard.accent` e
/// `widgets/toast.dart`).
Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets(
    'PortfolioSaveBar con una modifica pendente non lancia eccezioni di paint',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(PortfolioSaveBar(count: 1, onCancel: () {}, onSave: () {})),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('AppCallout con accent non lancia eccezioni di paint', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const AppCallout(
          tone: AppCalloutTone.info,
          accent: true,
          icon: Icon(Icons.work_outline),
          title: 'Posizione in portafoglio',
          body: 'Righe di registro e badge.',
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
