import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/tokens.dart';
import 'command_palette.dart';
import 'shortcuts_help.dart';
import 'sidebar.dart';
import 'ticker_tape.dart';
import 'topbar.dart';

/// Shell dell'app autenticata: sidebar + topbar + ticker tape + contenuto.
///
/// - ≥900px: sidebar fissa 232px (collassabile a 62px, stato persistito) e
///   topbar a 60px;
/// - <900px: sidebar come drawer off-canvas da 260px con backdrop, topbar con
///   bottone hamburger e, sotto 640px, altezza 56px.
///
/// Il titolo della topbar è derivato dalla rotta corrente; le azioni
/// contestuali arrivano da [topbarActionsProvider]. La shell intercetta anche
/// le scorciatoie globali: `Ctrl/Cmd+K` e `/` aprono la command palette, `?`
/// apre la guida; `/` e `?` non scattano mentre si digita in un campo di testo
/// e nessuna scorciatoia scatta con un dialog/modale già aperto.
class AppShell extends ConsumerWidget {
  /// Crea la shell attorno a [child].
  const AppShell({super.key, required this.child});

  /// Contenuto della pagina corrente.
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppTokens t = context.tokens;
    final bool drawerLayout = context.isDrawerLayout;
    final String title = appTopbarTitle(appLocationOf(context));
    final List<Widget> actions = ref.watch(topbarActionsProvider);

    final Widget shell;
    if (!drawerLayout) {
      shell = Scaffold(
        backgroundColor: t.bg,
        body: SafeArea(
          bottom: false,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const AppSidebar(),
              Expanded(
                child: Column(
                  children: <Widget>[
                    AppTopbar(title: title, actions: actions),
                    const TickerTape(),
                    Expanded(child: child),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      shell = Scaffold(
        backgroundColor: t.bg,
        drawer: Drawer(
          child: AppSidebar(
            drawer: true,
            onNavigate: () => Navigator.of(context).pop(),
          ),
        ),
        body: SafeArea(
          bottom: false,
          child: Builder(
            builder: (BuildContext scaffoldContext) {
              return Column(
                children: <Widget>[
                  AppTopbar(
                    title: title,
                    actions: actions,
                    onMenuTap: () => Scaffold.of(scaffoldContext).openDrawer(),
                  ),
                  const TickerTape(),
                  Expanded(child: child),
                ],
              );
            },
          ),
        ),
      );
    }

    return _ShellShortcutScope(child: shell);
  }
}

/// Scorciatoie globali della shell (`Ctrl/Cmd+K`, `/`, `?`).
///
/// Un [Focus] radice con autofocus riceve i key event che risalgono dalla
/// gerarchia; i binding di [CallbackShortcuts] li intercettano solo se nessun
/// dialog/modale è aperto e, per `/` e `?`, solo se il focus non è in un
/// campo di testo. `Ctrl/Cmd+K` resta attivo anche mentre si digita, come nel
/// frontend HTML.
class _ShellShortcutScope extends StatelessWidget {
  const _ShellShortcutScope({required this.child});

  final Widget child;

  bool _isTextInputFocused() {
    final BuildContext? focusContext =
        FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return false;
    if (focusContext.widget is EditableText) return true;
    return focusContext.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  bool _isOverlayRouteOpen(BuildContext context) {
    final ModalRoute<dynamic>? route = ModalRoute.of(context);
    return route != null && !route.isCurrent;
  }

  void _openPalette(BuildContext context, {bool typingGuard = false}) {
    if (_isOverlayRouteOpen(context)) return;
    if (typingGuard && _isTextInputFocused()) return;
    unawaited(showAppCommandPalette(context));
  }

  void _openShortcuts(BuildContext context) {
    if (_isOverlayRouteOpen(context) || _isTextInputFocused()) return;
    unawaited(showShortcutsHelp(context));
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
            _openPalette(context),
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
            _openPalette(context),
        const SingleActivator(LogicalKeyboardKey.slash): () =>
            _openPalette(context, typingGuard: true),
        const SingleActivator(LogicalKeyboardKey.question): () =>
            _openShortcuts(context),
        const SingleActivator(LogicalKeyboardKey.slash, shift: true): () =>
            _openShortcuts(context),
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}
