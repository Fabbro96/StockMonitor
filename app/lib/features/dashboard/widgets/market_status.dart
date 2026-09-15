import 'package:flutter/material.dart';

import '../../../core/models/dashboard.dart';
import '../../../theme/app_theme.dart';
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

/// Orari di sessione di fallback (usati quando il payload non li espone).
const String _fallbackItHours = '09:00 - 17:30';
const String _fallbackUsHours = '15:30 - 22:00';

/// Indicatore compatto dello stato delle sessioni: pallino di stato
/// ([AppStatusDot]) + nome mercato + orari di sessione in mono tabulare.
///
/// Niente emoji: la direzione è data dal pallino e dal testo del tooltip.
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
          _SessionIndicator(
            open: itOpen,
            label: 'Borsa Italiana',
            hours: _hoursOf(status, 'IT', fallback: _fallbackItHours),
            showLabel: !compact,
          ),
          SizedBox(width: compact ? AppSpacing.s8 : AppSpacing.s14),
          _SessionIndicator(
            open: usOpen,
            label: 'Wall Street',
            hours: _hoursOf(status, 'US', fallback: _fallbackUsHours),
            showLabel: !compact,
          ),
        ],
      ),
    );
  }

  String _hoursOf(MarketStatusInfo? status, String market, {required String fallback}) {
    final String? hours = status?.details[market]?.hours;
    return (hours == null || hours.isEmpty) ? fallback : hours;
  }
}

class _SessionIndicator extends StatelessWidget {
  const _SessionIndicator({
    required this.open,
    required this.label,
    required this.hours,
    required this.showLabel,
  });

  final bool open;
  final String label;
  final String hours;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final String state = open ? 'aperta' : 'chiusa';
    final Widget indicator = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        AppStatusDot(open: open, statusLabel: '$label $state'),
        const SizedBox(width: AppSpacing.s6),
        if (showLabel) ...<Widget>[
          Text(
            label,
            style: TextStyle(
              color: t.textSecondary,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              fontFamilyFallback: AppTokens.fontFallback,
            ),
          ),
          const SizedBox(width: AppSpacing.s6),
        ],
        Text(
          hours,
          style: AppText.mono(context, size: 11.5, weight: FontWeight.w500, color: t.textMuted),
        ),
      ],
    );

    return Tooltip(message: '$label: $state ($hours)', child: indicator);
  }
}
