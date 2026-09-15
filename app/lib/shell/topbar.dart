import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../theme/theme_controller.dart';
import '../widgets/app_button.dart';
import '../widgets/badges.dart';
import 'command_palette.dart';
import 'shortcuts_help.dart';

/// Azioni contestuali mostrate nella topbar a destra del titolo.
///
/// Ogni pagina rivendica la proprietà delle proprie azioni passando il proprio
/// `State` come `owner`:
///
/// ```dart
/// class _MyPageState extends ConsumerState<MyPage> {
///   late final TopbarActionsController _topbar;
///
///   @override
///   void initState() {
///     super.initState();
///     _topbar = ref.read(topbarActionsProvider.notifier);
///     // set() va fuori dalle life-cycle: post-frame callback.
///     WidgetsBinding.instance.addPostFrameCallback((_) {
///       if (!mounted) return;
///       _topbar.set(this, [AppButton(label: 'Esporta CSV', onPressed: ...)]);
///     });
///   }
///
///   @override
///   void dispose() {
///     // Campo catturato, NON `ref` (unmounted → unsafe).
///     _topbar.clear(this);
///     super.dispose();
///   }
/// }
/// ```
///
/// Regole:
/// - `set` va chiamato fuori dalle life-cycle (post-frame callback) con il
///   notifier catturato in un campo: dentro `build`/`initState`/
///   `didChangeDependencies` Riverpod lancia "Tried to modify a provider while
///   the widget tree was building".
/// - `clear` è pensato per il `dispose`, sempre col notifier catturato: usare
///   `ref` dopo lo smontaggio lancia "Using ref when a widget is about to or
///   has been unmounted is unsafe". Il controller differisce la modifica di
///   stato a un microtask (vedi [clear]) per non urtare il vincolo di Riverpod
///   durante la finalizzazione dell'albero.
/// - `clear(owner)` azzera solo se [owner] è ancora il proprietario corrente:
///   durante una transizione la pagina uscente può essere smontata dopo
///   l'entrante e non deve cancellarne le azioni.
class TopbarActionsController extends Notifier<List<Widget>> {
  Object? _owner;

  @override
  List<Widget> build() => const <Widget>[];

  /// Sostituisce le azioni correnti e ne rivendica la proprietà per [owner].
  void set(Object owner, List<Widget> actions) {
    _owner = owner;
    state = List<Widget>.unmodifiable(actions);
  }

  /// Azzera le azioni solo se [owner] è ancora il proprietario corrente.
  ///
  /// La modifica dello stato è differita a un microtask: `clear` viene
  /// chiamato da `dispose`, dove Riverpod vieta di modificare i provider
  /// ("Tried to modify a provider while the widget tree was building").
  /// L'ownership viene ri-verificata al momento dell'esecuzione, così il clear
  /// della pagina uscente non può cancellare le azioni di una pagina entrante
  /// che ha già rivendicato la proprietà nel frattempo.
  void clear(Object owner) {
    if (!identical(_owner, owner)) return;
    scheduleMicrotask(() {
      if (!ref.mounted || !identical(_owner, owner)) return;
      _owner = null;
      state = const <Widget>[];
    });
  }
}

/// Azioni della topbar per la pagina corrente.
final topbarActionsProvider =
    NotifierProvider<TopbarActionsController, List<Widget>>(
      TopbarActionsController.new,
    );

/// Barra superiore sticky: titolo pagina in chiaro (senza emoji), azioni
/// contestuali, ricerca globale a forma di campo (`Cerca...` + `Ctrl K`) e
/// azioni icona: aiuto `?` e toggle tema.
///
/// Desktop: alta 64px; mobile (<640px): 56px e ricerca a sola icona.
class AppTopbar extends ConsumerWidget {
  /// Crea la topbar.
  const AppTopbar({
    super.key,
    required this.title,
    this.onMenuTap,
    this.onOpenSearch,
    this.actions = const <Widget>[],
  });

  /// Titolo della pagina corrente.
  final String title;

  /// Callback del bottone hamburger; presente solo sotto 900px.
  final VoidCallback? onMenuTap;

  /// Callback di apertura ricerca; se `null` usa [showAppCommandPalette].
  final VoidCallback? onOpenSearch;

  /// Azioni contestuali (di norma da [topbarActionsProvider]).
  final List<Widget> actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppTokens t = context.tokens;
    final bool compact = context.isCompact;
    final bool drawerLayout = context.isDrawerLayout;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: compact ? AppTokens.topbarHeightMobile : AppTokens.topbarHeight,
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 20, vertical: 8),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      child: Row(
        children: <Widget>[
          if (drawerLayout && onMenuTap != null) ...<Widget>[
            AppIconButton(
              icon: const Icon(Icons.menu),
              tooltip: 'Apri menu',
              semanticLabel: 'Apri menu',
              onPressed: onMenuTap,
            ),
            const SizedBox(width: AppSpacing.s12),
          ],
          Expanded(
            child: Text(
              title,
              style: AppText.pageTitle(context),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          for (final Widget action in actions) ...<Widget>[
            action,
            const SizedBox(width: AppSpacing.s8),
          ],
          const SizedBox(width: AppSpacing.s4),
          _SearchButton(
            compact: compact,
            onPressed: () {
              final VoidCallback? callback = onOpenSearch;
              if (callback != null) {
                callback();
              } else {
                unawaited(showAppCommandPalette(context));
              }
            },
          ),
          const SizedBox(width: AppSpacing.s6),
          AppIconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'Scorciatoie da tastiera (?)',
            semanticLabel: 'Scorciatoie da tastiera',
            onPressed: () => unawaited(showShortcutsHelp(context)),
          ),
          const SizedBox(width: AppSpacing.s6),
          AppIconButton(
            icon: Icon(
              isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            ),
            tooltip: isDark ? 'Passa al tema chiaro' : 'Passa al tema scuro',
            semanticLabel: isDark
                ? 'Passa al tema chiaro'
                : 'Passa al tema scuro',
            onPressed: () =>
                ref.read(themeControllerProvider.notifier).toggle(),
          ),
        ],
      ),
    );
  }
}

/// Ricerca globale: a riposo è un campo con bordo (aspetto `.input`), non un
/// bottone pieno. Sotto 640px resta la sola icona.
class _SearchButton extends StatefulWidget {
  const _SearchButton({required this.compact, required this.onPressed});

  final bool compact;
  final VoidCallback onPressed;

  @override
  State<_SearchButton> createState() => _SearchButtonState();
}

class _SearchButtonState extends State<_SearchButton> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final bool highlight = _hovered || _focused;
    final Color border = _focused ? t.primary : (highlight ? t.borderStrong : t.border);
    final Color foreground = highlight ? t.textPrimary : t.textSecondary;

    return Tooltip(
      message: 'Cerca titoli o naviga (Ctrl+K)',
      child: AnimatedContainer(
        duration: AppMotion.effective(context, AppMotion.fast),
        curve: AppMotion.ease,
        height: widget.compact ? AppSizes.iconButton : AppSizes.control,
        width: widget.compact ? AppSizes.iconButton : null,
        padding: widget.compact
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: _hovered ? t.surfaceHover : t.surface,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(AppRadii.control),
          boxShadow: _focused
              ? <BoxShadow>[
                  BoxShadow(color: t.focusRing, blurRadius: 0, spreadRadius: 2),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onPressed,
            onHover: (bool value) => setState(() => _hovered = value),
            onFocusChange: (bool value) => setState(() => _focused = value),
            borderRadius: BorderRadius.circular(AppRadii.control),
            hoverColor: Colors.transparent,
            focusColor: Colors.transparent,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(Icons.search, size: AppSizes.iconSm, color: foreground),
                if (!widget.compact) ...<Widget>[
                  const SizedBox(width: AppSpacing.s8),
                  Text(
                    'Cerca...',
                    style: AppText.smallFor(t).copyWith(color: foreground),
                  ),
                  const SizedBox(width: AppSpacing.s10),
                  const AppKbd('Ctrl K'),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
