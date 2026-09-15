import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'app_card.dart';
import 'app_delta.dart';

/// Card di statistica (KPI): micro-etichetta maiuscola, numero mono tabulare
/// in evidenza, variazione opzionale e nota di contesto.
///
/// - [label] è mostrata maiuscola con tracking;
/// - [value] usa il font mono tabular; [valueColor] serve per profit/loss;
/// - [valueWidget] sostituisce il valore quando serve composizione (es.
///   `€ (+x%)`);
/// - [delta] aggiunge la variazione firmata con freccia (mai solo colore);
/// - [tooltip] aggiunge l'icona info con tooltip;
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
    this.delta,
    this.deltaLabel,
    this.iconColor,
  });

  /// Etichetta dello stat (es. `Valore Portafoglio`).
  final String label;

  /// Valore testuale, tipicamente già formattato (es. `12.345,67 €`).
  final String? value;

  /// Valore personalizzato; ha precedenza su [value].
  final Widget? valueWidget;

  /// Icona Material opzionale prima dell'etichetta.
  final Widget? icon;

  /// Riga descrittiva sotto il valore.
  final String? description;

  /// Testo del tooltip informativo accanto all'etichetta.
  final String? tooltip;

  /// Colore del valore (default `textPrimary`).
  final Color? valueColor;

  /// True = taglia ridotta del valore.
  final bool smallValue;

  /// Widget a destra dell'etichetta.
  final Widget? trailing;

  /// Variazione firmata mostrata sotto il valore.
  final double? delta;

  /// Suffisso della variazione (es. `%`, `€`).
  final String? deltaLabel;

  /// Colore dell'icona (default `textMuted`).
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final bool compact = context.isCompact;
    final TextStyle valueStyle = smallValue ? AppText.statValueSm(context) : AppText.statValue(context);

    return AppCard(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 14,
        vertical: compact ? 11 : 13,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (icon != null) ...<Widget>[
                IconTheme.merge(
                  data: IconThemeData(
                    color: iconColor ?? t.textMuted,
                    size: compact ? AppSizes.iconXs : AppSizes.iconSm,
                  ),
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
                    child: Icon(Icons.info_outline, size: 12, color: t.textFaint),
                  ),
                ),
              if (trailing != null) ...<Widget>[
                const SizedBox(width: AppSpacing.s6),
                trailing!,
              ],
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: valueWidget ??
                Text(
                  value ?? '—',
                  style: valueStyle.copyWith(color: valueColor),
                  overflow: TextOverflow.ellipsis,
                ),
          ),
          if (delta != null || description != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: <Widget>[
                  if (delta != null) ...<Widget>[
                    Flexible(
                      fit: FlexFit.loose,
                      child: AppDelta(value: delta, suffix: deltaLabel, size: 12.5),
                    ),
                    if (description != null) const SizedBox(width: AppSpacing.s8),
                  ],
                  if (description != null)
                    Expanded(
                      child: Text(
                        description!,
                        style: AppText.statDesc(context),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
