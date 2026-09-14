import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'app_card.dart';

/// Card di statistica (`.stat-card` + `.stat-value`, `.stat-label`, `.stat-desc`).
///
/// - [label] è mostrata maiuscola con tracking;
/// - [value] usa il font mono tabular; [valueColor] serve per profit/loss;
/// - [valueWidget] sostituisce il valore quando serve composizione (es. `€ (+x%)`);
/// - [tooltip] aggiunge l'icona info con tooltip come `i.info-badge`;
/// - [trailing] è contenuto extra a destra dell'etichetta (es. badge).
class StatCard extends StatelessWidget {
  /// Crea una stat card.
  const StatCard({
    super.key,
    required this.label,
    this.value,
    this.valueWidget,
    this.icon,
    this.description,
    this.tooltip,
    this.valueColor,
    this.smallValue = false,
    this.trailing,
  });

  /// Etichetta dello stat (es. `Valore Portafoglio`).
  final String label;

  /// Valore testuale, tipicamente già formattato (es. `12.345,67 €`).
  final String? value;

  /// Valore personalizzato; ha precedenza su [value].
  final Widget? valueWidget;

  /// Icona/emoji opzionale prima dell'etichetta.
  final Widget? icon;

  /// Riga descrittiva sotto il valore (`.stat-desc`).
  final String? description;

  /// Testo del tooltip informativo accanto all'etichetta.
  final String? tooltip;

  /// Colore del valore (default `textPrimary`).
  final Color? valueColor;

  /// True = taglia ridotta del valore (`.stat-value-sm`).
  final bool smallValue;

  /// Widget a destra dell'etichetta.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final bool compact = context.isCompact;
    final TextStyle valueStyle = smallValue ? AppText.statValueSm(context) : AppText.statValue(context);

    return AppCard(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 16,
        vertical: compact ? 12 : 15,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (icon != null) ...<Widget>[
                IconTheme.merge(
                  data: IconThemeData(color: t.textSecondary, size: compact ? 12 : 13),
                  child: icon!,
                ),
                const SizedBox(width: AppSpacing.s6),
              ],
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: AppText.statLabel(context),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (tooltip != null)
                Tooltip(
                  message: tooltip!,
                  child: Padding(
                    padding: const EdgeInsets.only(left: AppSpacing.s6),
                    child: Icon(Icons.info_outline, size: 13, color: t.textMuted),
                  ),
                ),
              if (trailing != null) ...<Widget>[
                const SizedBox(width: AppSpacing.s6),
                trailing!,
              ],
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: valueWidget ??
                Text(
                  value ?? '—',
                  style: valueStyle.copyWith(color: valueColor),
                  overflow: TextOverflow.ellipsis,
                ),
          ),
          if (description != null)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(description!, style: AppText.statDesc(context)),
            ),
        ],
      ),
    );
  }
}
