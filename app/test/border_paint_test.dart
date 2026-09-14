import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_monitor/features/portfolio/portfolio_screen.dart'
    show PortfolioSaveBar;
import 'package:stock_monitor/features/stock_detail/stock_detail_modal.dart'
    show StockDetailCallout;

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

  testWidgets('StockDetailCallout con accent non lancia eccezioni di paint', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const StockDetailCallout(
          background: Color(0x1A2563EB),
          borderColor: Color(0xFF2563EB),
          accentColor: Color(0xFFF59E0B),
          child: Text('💼 Posizione nel tuo Portafoglio'),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
