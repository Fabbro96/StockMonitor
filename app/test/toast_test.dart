import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_monitor/theme/app_theme.dart';
import 'package:stock_monitor/widgets/toast.dart';

/// Harness minimale: Overlay disponibile (MaterialApp + Navigator) e un
/// bottone che lancia il toast reale dal [BuildContext] sotto l'overlay.
Widget _harness(void Function(BuildContext context) onPressed) {
  return MaterialApp(
    theme: lightTheme,
    home: Scaffold(
      body: Builder(
        builder: (BuildContext context) {
          return Center(
            child: TextButton(
              onPressed: () => onPressed(context),
              child: const Text('mostra'),
            ),
          );
        },
      ),
    ),
  );
}

void main() {
  testWidgets('showAppToast dipinge senza eccezioni e mostra il testo', (tester) async {
    await tester.pumpWidget(
      _harness(
        (BuildContext context) => showAppToast(
          context,
          message: 'Titolo rimosso',
          type: AppToastType.success,
        ),
      ),
    );

    await tester.tap(find.text('mostra'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    expect(find.text('Titolo rimosso'), findsOneWidget);
    // Il bug del bordo non uniforme + borderRadius si manifesta al paint:
    // qui non deve esserci nessuna eccezione.
    expect(tester.takeException(), isNull);

    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.takeException(), isNull);

    // Chiusura pulita senza timer pendenti.
    await tester.tap(find.byTooltip('Chiudi notifica'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Titolo rimosso'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('showAppToast con azione: callback eseguita e chiusura', (tester) async {
    bool tapped = false;
    await tester.pumpWidget(
      _harness(
        (BuildContext context) => showAppToast(
          context,
          message: 'Elemento rimosso',
          type: AppToastType.error,
          actionLabel: 'Annulla',
          onAction: () => tapped = true,
        ),
      ),
    );

    await tester.tap(find.text('mostra'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    expect(find.text('Elemento rimosso'), findsOneWidget);
    expect(find.text('Annulla'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Annulla'));
    expect(tapped, isTrue);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Elemento rimosso'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
