import 'package:flutter/material.dart';

import '../../../core/models/dashboard.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/badges.dart';

/// True se il mercato è aperto secondo l'orologio locale (fallback quando il
/// backend non fornisce lo stato): Italia 9-18, USA 15-22, lun-ven.
///
/// È la stessa euristica del vecchio `updateMarketStatus` (dashboard.js).
bool marketOpenByLocalClock(String market, DateTime now) {
  final bool weekday = now.weekday >= DateTime.monday && now.weekday <= DateTime.friday;
  final int hour = now.hour;
  if (market.toUpperCase() == 'IT') {
    return weekday && hour >= 9 && hour < 18;
  }
  return weekday && hour >= 15 && hour < 22;
}

/// Indicatore compatto dello stato dei mercati: due pallini con label
/// `Borsa Italiana` e `Wall Street` (label nascoste sotto 640px come
/// `.status-label` del CSS), tooltip con gli orari.
///
/// [status] arriva dal payload dashboard: se manca (o non è `OPEN`) si usa
/// [marketOpenByLocalClock], come il frontend. [now] è iniettabile nei test.
class MarketStatusView extends StatelessWidget {
  /// Crea l'indicatore.
  const MarketStatusView({super.key, this.status, this.now});

  /// Stato dei mercati dal backend; `null` = fallback locale.
  final MarketStatusInfo? status;

  /// Istante di riferimento per il fallback (default `DateTime.now()`).
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final DateTime reference = now ?? DateTime.now();
    final bool itOpen = status?.it == 'OPEN' || marketOpenByLocalClock('IT', reference);
    final bool usOpen = status?.us == 'OPEN' || marketOpenByLocalClock('US', reference);
    final bool compact = context.isCompact;

    return Semantics(
      container: true,
      liveRegion: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _StatusIndicator(
            open: itOpen,
            label: 'Borsa Italiana',
            tooltip: itOpen
                ? 'Borsa Italiana: Aperta (09:00 - 17:30)'
                : 'Borsa Italiana: Chiusa (09:00 - 17:30)',
            showLabel: !compact,
          ),
          SizedBox(width: compact ? AppSpacing.s8 : AppSpacing.s14),
          _StatusIndicator(
            open: usOpen,
            label: 'Wall Street',
            tooltip: usOpen
                ? 'Wall Street: Aperta (15:30 - 22:00)'
                : 'Wall Street: Chiusa (15:30 - 22:00)',
            showLabel: !compact,
          ),
        ],
      ),
    );
  }
}

class _StatusIndicator extends StatelessWidget {
  const _StatusIndicator({
    required this.open,
    required this.label,
    required this.tooltip,
    required this.showLabel,
  });

  final bool open;
  final String label;
  final String tooltip;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final Widget indicator = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        AppStatusDot(open: open, statusLabel: label),
        if (showLabel) ...<Widget>[
          const SizedBox(width: AppSpacing.s6),
          Text(
            label,
            style: TextStyle(
              color: t.textSecondary,
              fontSize: 13.1,
              fontWeight: FontWeight.w400,
              fontFamilyFallback: AppTokens.fontFallback,
            ),
          ),
        ],
      ],
    );

    return Tooltip(message: tooltip, child: indicator);
  }
}
