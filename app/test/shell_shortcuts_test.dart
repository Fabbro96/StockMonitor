import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_monitor/core/api/dashboard_api.dart';
import 'package:stock_monitor/core/api_client.dart';
import 'package:stock_monitor/core/models/dashboard.dart';
import 'package:stock_monitor/shell/app_shell.dart';
import 'package:stock_monitor/shell/command_palette.dart';
import 'package:stock_monitor/shell/shortcuts_help.dart';
import 'package:stock_monitor/theme/tokens.dart';

/// Dashboard API finta: indici vuoti → il ticker tape non monta la marquee
/// (animazione infinita) e i test che montano [AppShell] restano stabili.
class _EmptyDashboardApi extends DashboardApi {
  _EmptyDashboardApi() : super(ApiClient());

  @override
  Future<List<IndexQuote>> indices() async => const <IndexQuote>[];
}

/// Harness minimale: un bottone apre palette/help sulla stessa radice.
class _Launcher extends StatelessWidget {
  const _Launcher();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextButton(
              onPressed: () => showAppCommandPalette(context),
              child: const Text('apri-palette'),
            ),
            TextButton(
              onPressed: () => showShortcutsHelp(context),
              child: const Text('apri-help'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Contenuto della shell con un bottone che apre un dialog.
class _DialogLauncher extends StatelessWidget {
  const _DialogLauncher();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (BuildContext dialogContext) =>
              const AlertDialog(content: Text('dialogo-aperto')),
        ),
        child: const Text('apri-dialog'),
      ),
    );
  }
}

/// Shell reale con il tape neutralizzato (indici vuoti).
Widget _shellApp({Widget? child}) {
  return ProviderScope(
    overrides: [dashboardApiProvider.overrideWithValue(_EmptyDashboardApi())],
    child: MaterialApp(home: AppShell(child: child ?? const SizedBox.shrink())),
  );
}

Future<void> _pressCtrlK(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
}

/// Barra accent della voce attiva della palette (unica `ColoredBox` primary).
Finder _activeBarFinder() => find.byWidgetPredicate(
  (Widget widget) =>
      widget is ColoredBox && widget.color == AppTokens.light.primary,
);

void main() {
  testWidgets('command palette: si apre, ignore/esc chiude', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: _Launcher())),
    );

    await tester.tap(find.text('apri-palette'));
    await tester.pumpAndSettle();

    expect(find.text('Stock Monitor Spotlight'), findsOneWidget);
    expect(find.textContaining('FTSEMIB.MI'), findsWidgets);
    expect(find.textContaining('NAVIGAZIONE'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('Stock Monitor Spotlight'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shortcuts help: si apre e si chiude con Esc', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: _Launcher())),
    );

    await tester.tap(find.text('apri-help'));
    await tester.pumpAndSettle();

    expect(find.text('⌨️ Scorciatoie da Tastiera'), findsOneWidget);
    expect(find.text('Apri Command Palette / Cerca'), findsOneWidget);
    expect(find.text('Ho capito'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('⌨️ Scorciatoie da Tastiera'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // F3.1
  testWidgets('F3.1: con un dialog aperto Ctrl+K non apre la palette', (
    tester,
  ) async {
    await tester.pumpWidget(_shellApp(child: const _DialogLauncher()));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('apri-dialog'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('dialogo-aperto'), findsOneWidget);

    await _pressCtrlK(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Stock Monitor Spotlight'), findsNothing);
    expect(find.text('dialogo-aperto'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // F3.2
  testWidgets('F3.2: con un TextField focusato / non apre la palette', (
    tester,
  ) async {
    final FocusNode fieldFocus = FocusNode();
    addTearDown(fieldFocus.dispose);

    await tester.pumpWidget(
      _shellApp(
        child: Center(
          child: SizedBox(width: 220, child: TextField(focusNode: fieldFocus)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(fieldFocus.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Stock Monitor Spotlight'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // F3.3
  testWidgets(
    'F3.3: Ctrl+K con shell attiva e nessun dialogo apre la palette',
    (tester) async {
      await tester.pumpWidget(_shellApp());
      await tester.pump();
      await tester.pump();

      await _pressCtrlK(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Stock Monitor Spotlight'), findsOneWidget);

      // chiusura pulita, senza pumpAndSettle (shell montata)
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('Stock Monitor Spotlight'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  // F6
  testWidgets('F6: il cambio query riporta la selezione sulla prima voce', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: _Launcher())),
    );
    await tester.tap(find.text('apri-palette'));
    await tester.pumpAndSettle();

    // Porta la selezione sulla terza voce (Portafoglio & Ledger).
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    final double dashboardY = tester.getTopLeft(find.text('Dashboard')).dy;
    final double portfolioY = tester
        .getTopLeft(find.text('Portafoglio & Ledger'))
        .dy;
    final double before = tester.getTopLeft(_activeBarFinder()).dy;
    expect(
      (before - portfolioY).abs(),
      lessThan((before - dashboardY).abs()),
      reason: 'selezione attesa su Portafoglio dopo due ArrowDown',
    );

    // Cambio query (1 carattere: solo match di navigazione): selezione a 0.
    await tester.enterText(find.byType(TextField), 'a');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    final double after = tester.getTopLeft(_activeBarFinder()).dy;
    expect(
      (after - dashboardY).abs(),
      lessThan((after - portfolioY).abs()),
      reason: 'la selezione deve tornare sulla prima voce',
    );
    expect(after, lessThan(before));
    expect(tester.takeException(), isNull);
  });
}
