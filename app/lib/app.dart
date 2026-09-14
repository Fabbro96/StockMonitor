import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';

/// Root dell'applicazione: tema, localizzazioni e router.
class StockMonitorApp extends ConsumerWidget {
  const StockMonitorApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Ripristina una volta la preferenza tema persistita.
    ref.watch(_themeBootstrapProvider);

    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeControllerProvider);

    return MaterialApp.router(
      title: 'Stock Monitor',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: themeMode,
      locale: const Locale('it', 'IT'),
      supportedLocales: const [Locale('it', 'IT')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}

/// Bootstrap del [ThemeController]: legge la preferenza salvata una sola volta.
final _themeBootstrapProvider = Provider<void>((ref) {
  unawaited(ref.read(themeControllerProvider.notifier).load());
});
