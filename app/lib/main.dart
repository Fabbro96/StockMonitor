import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/session/session_epoch.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _SessionScopedApp());
}

/// Root dell'app: ricrea il `ProviderScope` a ogni bump di [sessionEpoch].
///
/// La chiave diversa (`session-<n>`) smonta lo scope precedente e ne monta uno
/// nuovo, azzerando **tutte** le cache dei provider non autoDispose (dashboard,
/// portfolio, watchlist, impostazioni, ...): è il comportamento voluto, perché
/// dopo login/logout/cambio server/sessione scaduta non deve restare visibile
/// alcun dato del backend o dell'utente precedente. Il nuovo `AuthController`
/// rifà il bootstrap leggendo token e server dallo storage.
class _SessionScopedApp extends StatelessWidget {
  const _SessionScopedApp();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: sessionEpoch,
      builder: (BuildContext context, Widget? child) => ProviderScope(
        key: ValueKey<String>('session-${sessionEpoch.value}'),
        child: const StockMonitorApp(),
      ),
    );
  }
}
