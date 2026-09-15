import 'package:flutter/material.dart';

import '../../../core/formatters.dart';
import '../../../core/models/dashboard.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_delta.dart';
import '../../../widgets/app_error_panel.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/skeleton.dart';
import 'price_flash.dart';
import 'responsive_wrap.dart';

/// Griglia heatmap (`.heatmap-grid`): tile-bottone con ticker, nome, prezzo e
/// variazione firmata; sfondo, bordo e testo arrivano da
/// `AppTokens.heatmapTileBackground/Border/Foreground` (5 livelli di intensità).
///
/// La variazione usa [AppDelta] (freccia + segno + mono tabulare): la
/// direzione resta leggibile anche quando il colore non è percepito.
///
/// Stati: skeleton su primo load, pannello d'errore in errore senza dati,
/// empty `Nessun titolo attivo per la heatmap.` con bottone demo.
class HeatmapGrid extends StatelessWidget {
  /// Crea la griglia.
  const HeatmapGrid({
    super.key,
    required this.items,
    required this.loading,
    required this.failed,
    required this.onOpenStock,
    required this.onSeedDemo,
    this.onRetry,
  });

  /// Titoli della heatmap; `null` finché mai caricati.
  final List<HeatmapItem>? items;

  /// True durante il primo caricamento.
  final bool loading;

  /// True se la sezione è fallita senza dati precedenti.
  final bool failed;

  /// Tap su una tile (apre la scheda tecnica).
  final ValueChanged<String> onOpenStock;

  /// Tap su `Inizializza dati demo`.
  final VoidCallback onSeedDemo;

  /// Ritenta il caricamento della sezione.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final bool compact = context.isCompact;

    if (items == null && loading) {
      return ResponsiveWrap(
        minItemWidth: 140,
        mobileMinItemWidth: 150,
        gap: AppSpacing.s8,
        mobileGap: AppSpacing.s6,
        children: <Widget>[
          for (var i = 0; i < 4; i++)
            // ~altezza reale della tile con footer impilato su mobile.
            SkeletonCard(height: compact ? 92 : 84),
        ],
      );
    }

    if (items == null && failed) {
      return AppErrorPanel(
        message: 'Heatmap non disponibile.',
        onRetry: onRetry,
      );
    }

    final List<HeatmapItem> list = items ?? const <HeatmapItem>[];
    if (list.isEmpty) {
      return EmptyState(
        message: 'Nessun titolo attivo per la heatmap.',
        actions: <Widget>[
          AppButton(
            label: 'Inizializza dati demo',
            icon: const Icon(Icons.auto_awesome_outlined),
            size: AppButtonSize.sm,
            onPressed: onSeedDemo,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ResponsiveWrap(
          minItemWidth: 140,
          mobileMinItemWidth: 150,
          gap: AppSpacing.s8,
          mobileGap: AppSpacing.s6,
          children: <Widget>[
            for (final HeatmapItem item in list)
              _HeatmapTile(
                key: ValueKey<String>(item.ticker),
                item: item,
                onTap: () => onOpenStock(item.ticker),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.s12),
        const _IntensityLegend(),
      ],
    );
  }
}

/// Legenda dei cinque livelli di intensità della heatmap.
class _IntensityLegend extends StatelessWidget {
  const _IntensityLegend();

  /// Valori campione: due negativi, neutro, due positivi.
  static const List<(double, String)> _samples = <(double, String)>[
    (-5, '-5%'),
    (-2, '-2%'),
    (0, '0%'),
    (2, '+2%'),
    (5, '+5%'),
  ];

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.s10,
      runSpacing: AppSpacing.s6,
      children: <Widget>[
        Text('INTENSITÀ', style: AppText.micro(context).copyWith(color: t.textMuted)),
        for (final (double value, String label) in _samples)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 11,
                height: 11,
                decoration: BoxDecoration(
                  color: t.heatmapTileBackground(value),
                  border: Border.all(color: t.heatmapTileBorder(value)),
                  borderRadius: BorderRadius.circular(AppRadii.xs),
                ),
              ),
              const SizedBox(width: AppSpacing.s4),
              Text(label, style: AppText.mono(context, size: 11, weight: FontWeight.w500, color: t.textMuted)),
            ],
          ),
      ],
    );
  }
}

class _HeatmapTile extends StatefulWidget {
  const _HeatmapTile({super.key, required this.item, required this.onTap});

  final HeatmapItem item;
  final VoidCallback onTap;

  @override
  State<_HeatmapTile> createState() => _HeatmapTileState();
}

class _HeatmapTileState extends State<_HeatmapTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final bool compact = context.isCompact;
    final HeatmapItem item = widget.item;
    final double change = item.changePercent;
    final bool up = change >= 0;
    final Color foreground = t.heatmapTileForeground(change);
    final Color border = _hovered ? t.primary : t.heatmapTileBorder(change);

    final Widget price = PriceFlash(
      value: item.currentPrice,
      rising: up,
      child: Text(
        formatCurrency(item.currentPrice, currency: item.currency),
        style: AppText.mono(context, size: 12, weight: FontWeight.w700, color: foreground),
      ),
    );
    final Widget changeText = AppDelta(
      value: change,
      suffix: '%',
      size: 12,
      colorOverride: foreground,
    );

    // Prezzo e variazione su due righe: a larghezze minime (140px) il delta
    // non viene mai troncato, a differenza della disposizione affiancata.
    final Widget footer = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[price, changeText],
    );

    return Tooltip(
      message: 'Apri scheda tecnica di ${item.ticker}',
      child: AnimatedContainer(
        duration: AppMotion.effective(context, AppMotion.fast),
        curve: AppMotion.ease,
        constraints: BoxConstraints(minHeight: compact ? 74 : 84),
        padding: EdgeInsets.all(compact ? 8 : 10),
        decoration: BoxDecoration(
          color: t.heatmapTileBackground(change),
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(AppRadii.heatmap),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            onHover: (bool value) => setState(() => _hovered = value),
            borderRadius: BorderRadius.circular(AppRadii.heatmap),
            hoverColor: Colors.transparent,
            focusColor: t.primaryGlow,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  item.ticker,
                  style: AppText.mono(
                    context,
                    size: 13,
                    weight: FontWeight.w700,
                    color: foreground,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.s2),
                Text(
                  item.name.isEmpty ? item.ticker : item.name,
                  style: AppText.caption(context).copyWith(
                    // Stessa tinta AA-safe di ticker e prezzo: nessuna alpha
                    // ridotta che abbasserebbe il contrasto sotto soglia.
                    color: foreground,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.s6),
                footer,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
