import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/session/auth_controller.dart';
import '../core/storage.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/app_button.dart';

/// Voce di navigazione della sidebar, con il titolo usato anche dalla topbar.
class AppNavDestination {
  /// Crea una destinazione di navigazione.
  const AppNavDestination({
    required this.label,
    required this.path,
    required this.icon,
    required this.selectedIcon,
    required this.topbarTitle,
  });

  /// Etichetta del link (parità con la sidebar attuale).
  final String label;

  /// Percorso go_router.
  final String path;

  /// Icona a riposo.
  final IconData icon;

  /// Icona quando la voce è attiva.
  final IconData selectedIcon;

  /// Titolo di pagina mostrato nella topbar (con emoji, parità copy).
  final String topbarTitle;
}

/// Destinazioni della sidebar nell'ordine dell'app attuale.
const List<AppNavDestination> appNavDestinations = <AppNavDestination>[
  AppNavDestination(
    label: 'Dashboard',
    path: '/dashboard',
    icon: Icons.dashboard_outlined,
    selectedIcon: Icons.dashboard,
    topbarTitle: 'Dashboard',
  ),
  AppNavDestination(
    label: 'Watchlist',
    path: '/watchlist',
    icon: Icons.star_outline,
    selectedIcon: Icons.star,
    topbarTitle: '⭐ Watchlist & Radar Mercati',
  ),
  AppNavDestination(
    label: 'Portafoglio',
    path: '/portfolio',
    icon: Icons.work_outline,
    selectedIcon: Icons.work,
    topbarTitle: '💼 Gestione Portafoglio',
  ),
  AppNavDestination(
    label: 'Consigli',
    path: '/advice',
    icon: Icons.psychology_outlined,
    selectedIcon: Icons.psychology,
    topbarTitle: '🧠 Analisi & Consigli IA',
  ),
  AppNavDestination(
    label: 'Impostazioni',
    path: '/settings',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
    topbarTitle: 'Impostazioni',
  ),
];

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
  for (final AppNavDestination destination in appNavDestinations) {
    if (location == destination.path || location.startsWith('${destination.path}/')) {
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

/// True = sidebar desktop compressa (62px).
final sidebarCollapsedProvider =
    NotifierProvider<SidebarCollapsedController, bool>(SidebarCollapsedController.new);

/// Sidebar di navigazione: desktop 232px compressa a 62px, mobile (drawer)
/// 260px off-canvas. In modalità [drawer] le etichette sono sempre visibili.
///
/// Voci attive = alone `primaryGlow` + testo `primary` + `aria-current="page"`
/// equivalente (`selected` semantics). Le voci compresse mantengono un nome
/// accessibile (tooltip + semantics), come il clipping CSS del vecchio frontend.
class AppSidebar extends ConsumerStatefulWidget {
  /// Crea la sidebar.
  const AppSidebar({super.key, this.drawer = false, this.onNavigate});

  /// True = variante drawer mobile (larghezza 260, nessun collapse).
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
    final bool collapsed = !widget.drawer && ref.watch(sidebarCollapsedProvider);
    final double width = widget.drawer
        ? AppTokens.sidebarMobileWidth
        : (collapsed ? AppTokens.sidebarCollapsedWidth : AppTokens.sidebarWidth);
    final String location = appLocationOf(context);
    final String username =
        ref.watch(authControllerProvider).value?.user?.username ?? 'Utente';

    return AnimatedContainer(
      duration: AppMotion.effective(context, AppMotion.drawer),
      curve: AppMotion.easeInOut,
      width: width,
      decoration: BoxDecoration(
        color: t.surface,
        border: widget.drawer ? null : Border(right: BorderSide(color: t.border)),
      ),
      child: Column(
        children: <Widget>[
          _SidebarHeader(
            collapsed: collapsed,
            onToggleCollapsed:
                widget.drawer ? null : () => ref.read(sidebarCollapsedProvider.notifier).toggle(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              children: <Widget>[
                for (final AppNavDestination destination in appNavDestinations)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: _NavItem(
                      destination: destination,
                      active: _isActive(location, destination),
                      collapsed: collapsed,
                      onTap: () {
                        context.go(destination.path);
                        widget.onNavigate?.call();
                      },
                    ),
                  ),
              ],
            ),
          ),
          _SidebarFooter(
            username: username,
            collapsed: collapsed,
            onLogout: _confirmLogout,
          ),        ],
      ),
    );
  }

  bool _isActive(String location, AppNavDestination destination) {
    return location == destination.path || location.startsWith('${destination.path}/');
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

class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader({required this.collapsed, this.onToggleCollapsed});

  final bool collapsed;
  final VoidCallback? onToggleCollapsed;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Container(
      height: AppTokens.topbarHeight,
      padding: collapsed
          ? EdgeInsets.zero
          : const EdgeInsets.only(left: 16, right: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      child: Row(
        mainAxisAlignment: collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
        children: <Widget>[
          if (!collapsed) ...<Widget>[
            const Text('📈', style: TextStyle(fontSize: 16.8)),
            const SizedBox(width: AppSpacing.s8),
            Expanded(
              child: Text(
                'Stock Monitor',
                style: AppText.appTitle(context),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          if (onToggleCollapsed != null)
            AppIconButton(
              icon: Icon(collapsed ? Icons.chevron_right : Icons.chevron_left),
              tooltip: collapsed ? 'Espandi menu' : 'Comprimi menu',
              semanticLabel: collapsed ? 'Espandi menu' : 'Comprimi menu',
              bordered: false,
              onPressed: onToggleCollapsed,
            ),
        ],
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
      padding: widget.collapsed
          ? const EdgeInsets.symmetric(vertical: 10)
          : const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: active ? t.primaryGlow : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadii.input),
      ),
      child: Row(
        mainAxisAlignment:
            widget.collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
        children: <Widget>[
          Icon(
            active ? widget.destination.selectedIcon : widget.destination.icon,
            size: 18,
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

    item = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        onHover: (bool value) => setState(() => _hovered = value),
        borderRadius: BorderRadius.circular(AppRadii.input),
        hoverColor: t.surfaceHover,
        focusColor: t.primaryGlow,
        child: item,
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
    required this.onLogout,
  });

  final String username;
  final bool collapsed;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Container(
      padding: collapsed
          ? const EdgeInsets.symmetric(vertical: 12)
          : const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.border)),
      ),
      child: Row(
        mainAxisAlignment:
            collapsed ? MainAxisAlignment.center : MainAxisAlignment.spaceBetween,
        children: <Widget>[
          if (collapsed) ...<Widget>[
            Tooltip(
              message: username,
              child: Icon(Icons.person_outline, size: 16, color: t.textSecondary),
            ),
            const SizedBox(width: AppSpacing.s4),
          ] else ...<Widget>[
            Icon(Icons.person_outline, size: 16, color: t.textSecondary),
            const SizedBox(width: AppSpacing.s8),
            Expanded(
              child: Text(
                username,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 13.4,
                  fontWeight: FontWeight.w600,
                  fontFamilyFallback: AppTokens.fontFallback,
                ),
              ),
            ),
          ],
          AppIconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Disconnetti',
            semanticLabel: 'Disconnetti',
            bordered: false,
            danger: true,
            onPressed: () => onLogout(),
          ),
        ],
      ),
    );
  }
}
