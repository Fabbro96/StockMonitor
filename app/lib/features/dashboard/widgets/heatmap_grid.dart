import 'package:flutter/material.dart';

import '../../../core/formatters.dart';
import '../../../core/models/dashboard.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/skeleton.dart';
import '../../../widgets/ticker_flag.dart';
import 'price_flash.dart';
import 'responsive_wrap.dart';

/// Griglia heatmap (`.heatmap-grid`): tile-bottone con ticker+bandiera,
/// nome, prezzo e variazione, sfondo/bordo con intensità da
/// `AppTokens.heatmapTileBackground/Border`.
///
/// Stati: skeleton su primo load, `Dati non disponibili.` in errore senza dati,
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
  });

  /// Titoli della heatmap; `null` finché mai caricati.
  final List<HeatmapItem>? items;

  /// True durante il primo caricamento.
  final bool loading;

  /// True se la sezione è fallita senza dati precedenti.
  final bool failed;

  /// Tap su una tile (apre la scheda tecnica).
  final ValueChanged<String> onOpenStock;

  /// Tap su `Inizializza Dati Demo`.
  final VoidCallback onSeedDemo;

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
            SkeletonCard(height: compact ? 88 : 80),
        ],
      );
    }

    if (items == null && failed) {
      return const EmptyState(message: 'Dati non disponibili.');
    }

    final List<HeatmapItem> list = items ?? const <HeatmapItem>[];
    if (list.isEmpty) {
      return EmptyState(
        message: 'Nessun titolo attivo per la heatmap.',
        actions: <Widget>[
          AppButton(
            label: '🚀 Inizializza Dati Demo',
            size: AppButtonSize.sm,
            onPressed: onSeedDemo,
          ),
        ],
      );
    }

    return ResponsiveWrap(
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
    final String sign = up ? '+' : '';
    final String flag = TickerFlags.forMarket(item.market);
    final Color border = _hovered ? t.primary : t.heatmapTileBorder(change);

    final Widget price = PriceFlash(
      value: item.currentPrice,
      rising: up,
      child: Text(
        formatCurrency(item.currentPrice, currency: item.currency),
        style: AppText.mono(context, size: 12, weight: FontWeight.w700),
      ),
    );
    final Widget changeText = Text(
      '$sign${change.toStringAsFixed(2)}%',
      style: AppText.mono(
        context,
        size: 12,
        weight: FontWeight.w700,
        color: up ? t.successText : t.danger,
      ),
    );

    final Widget footer = compact
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[price, changeText],
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Flexible(child: price),
              const SizedBox(width: AppSpacing.s6),
              Flexible(child: changeText),
            ],
          );

    return Tooltip(
      message: 'Apri scheda tecnica di ${item.ticker}',
      child: AnimatedContainer(
        duration: AppMotion.effective(context, AppMotion.fast),
        curve: AppMotion.ease,
        constraints: BoxConstraints(minHeight: compact ? 70 : 80),
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
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        item.ticker,
                        style: AppText.mono(
                          context,
                          size: 13.1,
                          weight: FontWeight.w700,
                          color: t.primary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(flag, style: const TextStyle(fontSize: 12.2, height: 1.2)),
                  ],
                ),
                const SizedBox(height: AppSpacing.s2),
                Text(
                  item.name.isEmpty ? item.ticker : item.name,
                  style: TextStyle(
                    color: t.textSecondary,
                    fontSize: 12.2,
                    fontWeight: FontWeight.w400,
                    fontFamilyFallback: AppTokens.fontFallback,
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
