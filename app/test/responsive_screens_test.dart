import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_monitor/features/login/login_screen.dart';
import 'package:stock_monitor/shell/app_shell.dart';
import 'package:stock_monitor/theme/app_theme.dart';

/// Smoke test responsive permanente: le schermate senza dipendenze di rete
/// (login) e la shell non devono andare in overflow ai due estremi
/// 380px (mobile) e 1200px (desktop), in tema chiaro e scuro.
///
/// Le chiamate API reali falliscono subito nel test binding (HTTP mockato):
/// gli stati di errore/loading vengono comunque impaginati e verificati.
Future<void> _pump(
  WidgetTester tester,
  Widget screen,
  Size size,
  ThemeData theme,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: theme,
        home: Scaffold(body: screen),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  for (final ({String name, Size size, ThemeData theme}) variant in <({
    String name,
    Size size,
    ThemeData theme,
  })>[
    (name: 'login 380 light', size: const Size(380, 800), theme: lightTheme),
    (name: 'login 1200 dark', size: const Size(1200, 900), theme: darkTheme),
  ]) {
    testWidgets('responsive ${variant.name}', (WidgetTester tester) async {
      await _pump(tester, const LoginScreen(), variant.size, variant.theme);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final ({String name, Size size, ThemeData theme}) variant in <({
    String name,
    Size size,
    ThemeData theme,
  })>[
    (name: 'shell 380 light', size: const Size(380, 800), theme: lightTheme),
    (name: 'shell 1200 dark', size: const Size(1200, 900), theme: darkTheme),
  ]) {
    testWidgets('responsive ${variant.name}', (WidgetTester tester) async {
      await _pump(
        tester,
        const AppShell(child: SizedBox.expand()),
        variant.size,
        variant.theme,
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
