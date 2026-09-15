import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_monitor/theme/app_theme.dart';
import 'package:stock_monitor/widgets/app_button.dart';
import 'package:stock_monitor/widgets/app_callout.dart';
import 'package:stock_monitor/widgets/app_confirm_dialog.dart';
import 'package:stock_monitor/widgets/app_error_panel.dart';

/// Test dei widget condivisi nati dalla passata di coerenza: pannello
/// d'errore, callout tonale, dialog di conferma e area sensibile dei bottoni
/// icona.
Widget _host(Widget child) => MaterialApp(
  theme: lightTheme,
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('AppErrorPanel', () {
    testWidgets('mostra il messaggio e la Riprova chiama onRetry', (
      WidgetTester tester,
    ) async {
      var retries = 0;
      await tester.pumpWidget(
        _host(
          AppErrorPanel(
            message: 'Errore di rete.',
            onRetry: () => retries++,
          ),
        ),
      );

      expect(find.text('Errore di rete.'), findsOneWidget);
      await tester.tap(find.text('Riprova'));
      expect(retries, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('senza onRetry non mostra il bottone', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(const AppErrorPanel(message: 'Errore di rete.')),
      );

      expect(find.text('Riprova'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('il messaggio è annunciato come live region', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(const AppErrorPanel(message: 'Errore di rete.')),
      );

      final SemanticsNode node = tester.getSemantics(
        find.text('Errore di rete.'),
      );
      expect(node.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
      handle.dispose();
    });
  });

  group('AppCallout', () {
    testWidgets('messaggio con icona e azione', (WidgetTester tester) async {
      var acted = 0;
      await tester.pumpWidget(
        _host(
          AppCallout(
            tone: AppCalloutTone.warning,
            icon: const Icon(Icons.warning_amber),
            body: 'Chiave in scadenza.',
            actions: <Widget>[
              AppButton(
                label: 'Rinnova',
                variant: AppButtonVariant.ghost,
                size: AppButtonSize.sm,
                onPressed: () => acted++,
              ),
            ],
          ),
        ),
      );

      expect(find.text('Chiave in scadenza.'), findsOneWidget);
      await tester.tap(find.text('Rinnova'));
      expect(acted, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('titolo e corpo convivono con l\'accent', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const AppCallout(
            accent: true,
            icon: Icon(Icons.work_outline),
            title: 'Posizione in portafoglio',
            body: 'Righe di registro.',
          ),
        ),
      );

      expect(find.text('Posizione in portafoglio'), findsOneWidget);
      expect(find.text('Righe di registro.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('AppConfirmDialog', () {
    /// Apre il dialog di conferma e riporta l'esito in [onResult].
    Future<void> showConfirm(
      WidgetTester tester, {
      required ValueChanged<bool?> onResult,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: lightTheme,
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) => TextButton(
                onPressed: () async {
                  onResult(
                    await showAppConfirm(
                      context,
                      title: 'Elimina transazione',
                      message: 'Sei sicuro?',
                      confirmLabel: 'Elimina',
                      destructive: true,
                    ),
                  );
                },
                child: const Text('apri'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('apri'));
      await tester.pumpAndSettle();
    }

    testWidgets('la conferma distruttiva è rossa e chiude con true', (
      WidgetTester tester,
    ) async {
      bool? result;
      await showConfirm(tester, onResult: (bool? value) => result = value);

      final AppButton confirm = tester.widget<AppButton>(
        find.widgetWithText(AppButton, 'Elimina'),
      );
      expect(confirm.variant, AppButtonVariant.danger);

      await tester.tap(find.widgetWithText(AppButton, 'Elimina'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Annulla chiude con false', (WidgetTester tester) async {
      bool? result;
      await showConfirm(tester, onResult: (bool? value) => result = value);

      await tester.tap(find.widgetWithText(AppButton, 'Annulla'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
      expect(find.text('Sei sicuro?'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('AppIconButton.minTargetSize', () {
    testWidgets('allarga l\'area sensibile senza ingrandire il bottone', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(
          AppIconButton(
            icon: const Icon(Icons.close),
            size: 26,
            minTargetSize: 32,
            tooltip: 'Chiudi',
            onPressed: () {},
          ),
        ),
      );

      expect(tester.getSize(find.byTooltip('Chiudi')), const Size(32, 32));
      final Finder visual = find.descendant(
        of: find.byTooltip('Chiudi'),
        matching: find.byType(AnimatedContainer),
      );
      expect(tester.getSize(visual), const Size(26, 26));
      expect(tester.takeException(), isNull);
    });
  });
}
