import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/session/auth_controller.dart';
import 'features/advice/advice_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/login/login_screen.dart';
import 'features/portfolio/portfolio_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/watchlist/watchlist_screen.dart';
import 'shell/app_shell.dart';
import 'theme/app_theme.dart';
import 'theme/tokens.dart';
import 'widgets/app_button.dart';
import 'widgets/empty_state.dart';
import 'widgets/skeleton.dart';

/// Router dell'app (hash URL strategy di default: nessun `usePathUrlStrategy`).
///
/// Guardia auth:
/// - bootstrap non completato → `/splash`;
/// - non loggato → `/login` (con `?expired=1` se la sessione è scaduta);
/// - loggato su `/login` o `/splash` → `/dashboard`.
final routerProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _AuthRefreshNotifier(ref);
  final router = GoRouter(
    initialLocation: '/splash',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider).value;
      final initialized = auth?.initialized ?? false;
      final location = state.uri.path;

      if (!initialized) {
        return location == '/splash' ? null : '/splash';
      }
      if (!(auth?.isLoggedIn ?? false)) {
        if (location == '/login') return null;
        return (auth?.sessionExpired ?? false) ? '/login?expired=1' : '/login';
      }
      if (location == '/login' || location == '/splash') {
        return '/dashboard';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const _SplashScreen(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/watchlist',
            builder: (context, state) => const WatchlistScreen(),
          ),
          GoRoute(
            path: '/portfolio',
            builder: (context, state) => const PortfolioScreen(),
          ),
          GoRoute(
            path: '/advice',
            builder: (context, state) => const AdviceScreen(),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsScreen(),
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => const _RouterErrorScreen(),
  );
  ref.onDispose(refreshNotifier.dispose);
  ref.onDispose(router.dispose);
  return router;
});

/// Bridge `ChangeNotifier` tra Riverpod e `GoRouter.refreshListenable`.
class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(Ref ref) {
    ref.listen<AsyncValue<AuthState>>(
      authControllerProvider,
      (previous, next) => notifyListeners(),
    );
  }
}

/// Schermata di attesa durante il bootstrap della sessione: marchio in
/// tassello inchiostro su fondo pagina, nome in maiuscolo tracciato e spinner.
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Scaffold(
      backgroundColor: t.bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: t.surfaceInverse,
                borderRadius: BorderRadius.circular(AppRadii.panel),
              ),
              child: Icon(
                Icons.candlestick_chart,
                size: 25,
                color: t.textInverse,
              ),
            ),
            const SizedBox(height: AppSpacing.s14),
            Text(
              'STOCK MONITOR',
              style: AppText.appTitle(context).copyWith(letterSpacing: 1.2),
            ),
            const SizedBox(height: AppSpacing.s24),
            const AppSpinner(size: 22),
          ],
        ),
      ),
    );
  }
}

/// Fallback per location sconosciute (es. hash URL scritto a mano).
class _RouterErrorScreen extends StatelessWidget {
  const _RouterErrorScreen();

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Scaffold(
      backgroundColor: t.bg,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: EmptyState(
            icon: const Icon(Icons.explore_off_outlined),
            title: 'Pagina non trovata.',
            message:
                'Il link che hai aperto non esiste o è stato spostato. '
                'Torna alla dashboard per riprendere.',
            actions: <Widget>[
              AppButton(
                label: 'Torna alla dashboard',
                variant: AppButtonVariant.ghost,
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.go('/dashboard'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
