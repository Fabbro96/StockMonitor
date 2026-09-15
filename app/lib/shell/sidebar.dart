import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/session/auth_controller.dart';
import '../core/storage.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/app_button.dart';

/// Gruppi del "table of contents" della sidebar.
enum AppNavGroup {
  /// Sintesi: dove sta andando il patrimonio.
  sintesi,

  /// Registro: cosa possiedi e cosa farne.
  registro,
}

/// Voce di navigazione della sidebar, con il titolo usato anche dalla topbar.
class AppNavDestination {
  /// Crea una destinazione di navigazione.
  const AppNavDestination({
    required this.label,
    required this.path,
    required this.icon,
    required this.selectedIcon,
    required this.topbarTitle,
    this.group = AppNavGroup.sintesi,
  });

  /// Etichetta del link.
  final String label;

  /// Percorso go_router.
  final String path;

  /// Icona a riposo (Material outlined).
  final IconData icon;

  /// Icona quando la voce è attiva (Material filled).
  final IconData selectedIcon;

  /// Titolo di pagina mostrato nella topbar (testo semplice, senza emoji).
  final String topbarTitle;

  /// Gruppo di appartenenza (le voci di fondo non hanno gruppo).
  final AppNavGroup? group;
}

/// Destinazioni della sidebar nell'ordine del "table of contents".
const List<AppNavDestination> appNavDestinations = <AppNavDestination>[
  AppNavDestination(
    label: 'Dashboard',
    path: '/dashboard',
    icon: Icons.space_dashboard_outlined,
    selectedIcon: Icons.space_dashboard,
    topbarTitle: 'Dashboard',
  ),
  AppNavDestination(
    label: 'Mercati',
    path: '/watchlist',
    icon: Icons.travel_explore,
    selectedIcon: Icons.travel_explore,
    topbarTitle: 'Mercati',
  ),
  AppNavDestination(
    label: 'Portafoglio',
    path: '/portfolio',
    icon: Icons.account_balance_wallet_outlined,
    selectedIcon: Icons.account_balance_wallet,
    topbarTitle: 'Portafoglio',
    group: AppNavGroup.registro,
  ),
  AppNavDestination(
    label: 'Analisi',
    path: '/advice',
    icon: Icons.insights_outlined,
    selectedIcon: Icons.insights,
    topbarTitle: 'Analisi',
    group: AppNavGroup.registro,
  ),
];

/// Voce di fondo della sidebar (fuori dai gruppi): impostazioni.
///
/// È pubblica perché i consumatori che disegnano una navigazione alternativa
/// (es. barra inferiore su mobile) possano riusare la stessa destinazione
/// senza duplicare icona, percorso e titolo.
const AppNavDestination appSettingsDestination = AppNavDestination(
  label: 'Impostazioni',
  path: '/settings',
  icon: Icons.tune,
  selectedIcon: Icons.tune,
  topbarTitle: 'Impostazioni',
  group: null,
);

/// Percorso corrente letto dal router; fuori da go_router ricade su [Uri.base].
String appLocationOf(BuildContext context) {
  try {
    return GoRouterState.of(context).uri.path;
  } on GoError {
    return GoRouter.maybeOf(context)?.state.uri.path ?? Uri.base.path;
  }
}

/// Titolo di topbar per il percorso corrente (match per prefisso, così anche
/// le sotto-rotte restano associate alla sezione).
String appTopbarTitle(String location) {
  for (final AppNavDestination destination in <AppNavDestination>[
    ...appNavDestinations,
    appSettingsDestination,
  ]) {
    if (location == destination.path ||
        location.startsWith('${destination.path}/')) {
      return destination.topbarTitle;
    }
  }
  return 'Stock Monitor';
}

/// Controller dello stato compresso della sidebar desktop (persistito).
class SidebarCollapsedController extends Notifier<bool> {
  bool _loaded = false;

  @override
  bool build() => false;

  /// Carica la preferenza da [AppStorage] una sola volta.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    state = await ref.read(appStorageProvider).getSidebarCollapsed();
  }

  /// Alterna compressa/espansa e persiste.
  Future<void> toggle() async {
    state = !state;
    await ref.read(appStorageProvider).setSidebarCollapsed(state);
  }
}

/// True = sidebar desktop compressa.
final sidebarCollapsedProvider =
    NotifierProvider<SidebarCollapsedController, bool>(
      SidebarCollapsedController.new,
    );

/// Sidebar di navigazione: desktop 248px compressa a 64px, mobile (drawer)
/// 268px off-canvas.
///
/// Struttura da "table of contents": micro-etichette di gruppo (`SINTESI`,
/// `REGISTRO`), voci a 36px, Impostazioni in un blocco di fondo sopra la riga
/// utente. La voce attiva usa fondo `primaryGlow`, testo d'accento e una barra
/// da 2px clippata a sinistra (Stack, mai `Border` asimmetrico + radius).
class AppSidebar extends ConsumerStatefulWidget {
  /// Crea la sidebar.
  const AppSidebar({super.key, this.drawer = false, this.onNavigate});

  /// True = variante drawer mobile (larghezza 268, nessun collapse).
  final bool drawer;

  /// Callback chiamata dopo la navigazione (chiude il drawer su mobile).
  final VoidCallback? onNavigate;

  @override
  ConsumerState<AppSidebar> createState() => _AppSidebarState();
}

class _AppSidebarState extends ConsumerState<AppSidebar> {
  @override
  void initState() {
    super.initState();
    if (!widget.drawer) {
      WidgetsBinding.instance.addPostFrameCallback((Duration _) {
        ref.read(sidebarCollapsedProvider.notifier).load();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final bool collapsed =
        !widget.drawer && ref.watch(sidebarCollapsedProvider);
    final double width = widget.drawer
        ? AppTokens.sidebarMobileWidth
        : (collapsed
              ? AppTokens.sidebarCollapsedWidth
              : AppTokens.sidebarWidth);
    final String location = appLocationOf(context);
    final String username =
        ref.watch(authControllerProvider).value?.user?.username ?? 'Utente';

    return AnimatedContainer(
      duration: AppMotion.effective(context, AppMotion.drawer),
      curve: AppMotion.easeInOut,
      width: width,
      decoration: BoxDecoration(
        color: t.surface,
        border: widget.drawer
            ? null
            : Border(right: BorderSide(color: t.border)),
      ),
      child: Column(
        children: <Widget>[
          _SidebarHeader(
            collapsed: collapsed,
            onToggleCollapsed: widget.drawer
                ? null
                : () => ref.read(sidebarCollapsedProvider.notifier).toggle(),
          ),
          Expanded(
            // La larghezza animata può passare per misure intermedie: le voci
            // si adattano alla larghezza reale, non solo allo stato del
            // provider, così l'animazione 64↔248 non produce overflow.
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final bool tight = collapsed || constraints.maxWidth < 120;
                return ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 10,
                  ),
                  children: <Widget>[
                    for (final AppNavGroup group
                        in AppNavGroup.values) ...<Widget>[
                      _GroupLabel(group: group, collapsed: tight),
                      for (final AppNavDestination destination
                          in appNavDestinations)
                        if (destination.group == group)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: _NavItem(
                              destination: destination,
                              active: _isActive(location, destination),
                              collapsed: tight,
                              onTap: () {
                                context.go(destination.path);
                                widget.onNavigate?.call();
                              },
                            ),
                          ),
                    ],
                  ],
                );
              },
            ),
          ),
          _SidebarFooter(
            username: username,
            collapsed: collapsed,
            settingsActive: _isActive(location, appSettingsDestination),
            onSettings: () {
              context.go(appSettingsDestination.path);
              widget.onNavigate?.call();
            },
            onLogout: _confirmLogout,
          ),
        ],
      ),
    );
  }

  bool _isActive(String location, AppNavDestination destination) {
    return location == destination.path ||
        location.startsWith('${destination.path}/');
  }

  Future<void> _confirmLogout() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          content: const Text('Sei sicuro di voler effettuare il logout?'),
          actions: <Widget>[
            AppButton(
              label: 'Annulla',
              variant: AppButtonVariant.ghost,
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            AppButton(
              label: 'Disconnetti',
              variant: AppButtonVariant.primary,
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        );
      },
    );
    if (confirmed ?? false) {
      await ref.read(authControllerProvider.notifier).logout();
    }
  }
}

/// Micro-etichetta di gruppo (o riga sottile in modalità compressa).
class _GroupLabel extends StatelessWidget {
  const _GroupLabel({required this.group, required this.collapsed});

  final AppNavGroup group;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    if (collapsed) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Container(height: AppSizes.rule, color: t.borderSubtle),
      );
    }
    final String label = switch (group) {
      AppNavGroup.sintesi => 'Sintesi',
      AppNavGroup.registro => 'Registro',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 6),
      child: Text(
        label.toUpperCase(),
        style: AppText.microFor(t).copyWith(color: t.textFaint),
      ),
    );
  }
}

/// Marchio dell'app: tassello con icona, usato anche dal drawer.
class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: t.surfaceInverse,
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      child: Icon(
        Icons.candlestick_chart,
        size: size * 0.6,
        color: t.textInverse,
      ),
    );
  }
}

class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader({required this.collapsed, this.onToggleCollapsed});

  final bool collapsed;
  final VoidCallback? onToggleCollapsed;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Container(
      height: AppTokens.topbarHeight,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          // Sotto 120px (compressa o frame intermedio dell'animazione) resta
          // solo il comando di espansione: niente overflow.
          final bool tight = collapsed || constraints.maxWidth < 120;
          return Padding(
            padding: tight
                ? EdgeInsets.zero
                : const EdgeInsets.only(left: 14, right: 6),
            child: Row(
              mainAxisAlignment: tight
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: <Widget>[
                if (!tight) ...<Widget>[
                  const _BrandMark(size: 28),
                  const SizedBox(width: AppSpacing.s10),
                  Expanded(
                    child: Text(
                      'STOCK MONITOR',
                      style: AppText.appTitle(context)
                          .copyWith(letterSpacing: 1.1),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                if (onToggleCollapsed != null)
                  AppIconButton(
                    icon: Icon(
                      tight ? Icons.chevron_right : Icons.chevron_left,
                    ),
                    tooltip: tight ? 'Espandi menu' : 'Comprimi menu',
                    semanticLabel: tight ? 'Espandi menu' : 'Comprimi menu',
                    size: 28,
                    iconSize: AppSizes.icon,
                    onPressed: onToggleCollapsed,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.destination,
    required this.active,
    required this.collapsed,
    required this.onTap,
  });

  final AppNavDestination destination;
  final bool active;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final bool active = widget.active;

    Widget item = Container(
      height: widget.collapsed ? 40 : 36,
      padding: widget.collapsed
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: active
            ? t.primaryGlow
            : (_hovered ? t.surfaceHover : Colors.transparent),
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      child: Row(
        mainAxisAlignment: widget.collapsed
            ? MainAxisAlignment.center
            : MainAxisAlignment.start,
        children: <Widget>[
          Icon(
            active ? widget.destination.selectedIcon : widget.destination.icon,
            size: AppSizes.icon,
            color: active
                ? t.primary
                : (_hovered ? t.textPrimary : t.textSecondary),
          ),
          if (!widget.collapsed) ...<Widget>[
            const SizedBox(width: AppSpacing.s10),
            Expanded(
              child: Text(
                widget.destination.label,
                style: AppText.navLabel(context, active: active),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );

    item = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: <Widget>[
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              onHover: (bool value) => setState(() => _hovered = value),
              borderRadius: BorderRadius.circular(AppRadii.control),
              hoverColor: Colors.transparent,
              focusColor: t.primaryGlow,
              child: item,
            ),
          ),
          if (active)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: AppSizes.accentStrip,
              child: ColoredBox(color: t.primary),
            ),
        ],
      ),
    );

    if (widget.collapsed) {
      item = Tooltip(message: widget.destination.label, child: item);
    }

    return Semantics(
      button: true,
      selected: active,
      label: widget.collapsed ? widget.destination.label : null,
      child: item,
    );
  }
}

class _SidebarFooter extends StatelessWidget {
  const _SidebarFooter({
    required this.username,
    required this.collapsed,
    required this.settingsActive,
    required this.onSettings,
    required this.onLogout,
  });

  final String username;
  final bool collapsed;
  final bool settingsActive;
  final VoidCallback onSettings;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.border)),
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool tight = collapsed || constraints.maxWidth < 140;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _NavItem(
                destination: appSettingsDestination,
                active: settingsActive,
                collapsed: tight,
                onTap: onSettings,
              ),
              const SizedBox(height: AppSpacing.s8),
              Container(height: AppSizes.rule, color: t.borderSubtle),
              const SizedBox(height: AppSpacing.s8),
              if (tight)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Tooltip(
                      message: username,
                      child: _UserTile(username: username, size: 28),
                    ),
                    const SizedBox(height: AppSpacing.s2),
                    AppIconButton(
                      icon: const Icon(Icons.logout),
                      tooltip: 'Disconnetti',
                      semanticLabel: 'Disconnetti',
                      size: 28,
                      iconSize: AppSizes.icon,
                      danger: true,
                      onPressed: onLogout,
                    ),
                  ],
                )
              else
                Row(
                  children: <Widget>[
                    _UserTile(username: username, size: 28),
                    const SizedBox(width: AppSpacing.s10),
                    Expanded(
                      child: Text(
                        username,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.smallFor(t)
                            .copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    AppIconButton(
                      icon: const Icon(Icons.logout),
                      tooltip: 'Disconnetti',
                      semanticLabel: 'Disconnetti',
                      danger: true,
                      onPressed: onLogout,
                    ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Tassello quadrato con l'iniziale dell'utente.
class _UserTile extends StatelessWidget {
  const _UserTile({required this.username, required this.size});

  final String username;
  final double size;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final String initial = username.trim().isEmpty
        ? '?'
        : username.trim()[0].toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: t.primaryGlow,
        border: Border.all(color: t.primary.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(AppRadii.tag),
      ),
      child: Text(
        initial,
        style: AppText.mono(
          context,
          size: 12.5,
          weight: FontWeight.w700,
          color: t.primary,
        ),
      ),
    );
  }
}
