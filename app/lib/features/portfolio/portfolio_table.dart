import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/skeleton.dart';

/// Tabella del linguaggio Registro per le sezioni del Portafoglio.
///
/// Struttura: testata da 36px su `surfaceSunken`, righe da 40px
/// (`AppSizes.rowCompact`) separate da una regola da 1px, hover di riga e
/// striscia warning a sinistra quando la riga è una bozza non salvata. Sotto
/// [minWidth] la tabella scorre in orizzontale invece di comprimere le
/// colonne.
class PortfolioTable extends StatelessWidget {
  /// Crea il contenitore della tabella.
  const PortfolioTable({super.key, required this.minWidth, required this.child});

  /// Larghezza minima prima dello scroll orizzontale.
  final double minWidth;

  /// Contenuto della tabella (testata + righe), di norma una [Column].
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.control),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          if (constraints.maxWidth < minWidth) {
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(width: minWidth, child: child),
            );
          }
          return child;
        },
      ),
    );
  }
}

/// Testata di tabella: 36px su `surfaceSunken`, micro etichette maiuscole.
class PortfolioTableHeader extends StatelessWidget {
  /// Crea la testata.
  const PortfolioTableHeader({super.key, required this.cells});

  /// Celle della testata, già dimensionate dal chiamante (Expanded/SizedBox).
  final List<Widget> cells;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Container(
      height: AppSizes.tableHeader,
      color: t.surfaceSunken,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s10),
      // Il gap tra le celle evita che le etichette lunghe si tocchino.
      child: Row(spacing: AppSpacing.s10, children: cells),
    );
  }
}

/// Etichetta di colonna allineata come le celle sottostanti.
class PortfolioHeaderLabel extends StatelessWidget {
  /// Crea l'etichetta di colonna.
  const PortfolioHeaderLabel(
    this.label, {
    super.key,
    this.alignment = Alignment.centerLeft,
  });

  /// Testo mostrato maiuscolo.
  final String label;

  /// Allineamento nella cella.
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Text(
        label.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: _textAlignFor(alignment),
        style: AppText.tableHeader(context),
      ),
    );
  }
}

/// Cella di corpo allineata.
class PortfolioCell extends StatelessWidget {
  /// Crea la cella.
  const PortfolioCell({
    super.key,
    required this.child,
    this.alignment = Alignment.centerLeft,
  });

  /// Contenuto della cella.
  final Widget child;

  /// Allineamento del contenuto.
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Align(alignment: alignment, child: child);
  }
}

/// Riga di tabella a 40px: hover, regola inferiore e striscia warning per le
/// modifiche in bozza.
class PortfolioTableRow extends StatefulWidget {
  /// Crea la riga.
  const PortfolioTableRow({
    super.key,
    required this.cells,
    this.highlighted = false,
  });

  /// Celle, già dimensionate dal chiamante (Expanded/SizedBox).
  final List<Widget> cells;

  /// True = riga con bozza pendente (fondo warning + striscia sinistra).
  final bool highlighted;

  @override
  State<PortfolioTableRow> createState() => _PortfolioTableRowState();
}

class _PortfolioTableRowState extends State<PortfolioTableRow> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final bool hover = _hovered || _focused;
    return RowHoverScope(
      hovered: hover,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Focus(
          canRequestFocus: false,
          onFocusChange: (bool value) => setState(() => _focused = value),
          child: AnimatedContainer(
            duration: AppMotion.effective(context, AppMotion.fast),
            curve: AppMotion.ease,
            height: AppSizes.rowCompact,
            decoration: BoxDecoration(
              color: widget.highlighted
                  ? t.warningBg
                  : (hover ? t.surfaceHover : Colors.transparent),
              border: Border(bottom: BorderSide(color: t.borderSubtle)),
            ),
            child: Stack(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s10,
                  ),
                  child: Row(spacing: AppSpacing.s10, children: widget.cells),
                ),
                // Striscia warning sinistra: un Border asimmetrico non è
                // compatibile con il fondo animato della riga.
                if (widget.highlighted)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: 3,
                    child: ColoredBox(color: t.warning),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Azioni di riga rivelate con hover o focus da tastiera.
///
/// Legge l'hover della riga ([RowHoverScope]) e diventa visibile anche quando
/// una delle sue azioni riceve il focus, così resta raggiungibile da tastiera.
class PortfolioActionsReveal extends StatefulWidget {
  /// Crea il contenitore delle azioni.
  const PortfolioActionsReveal({super.key, required this.child});

  /// Azioni della riga.
  final Widget child;

  @override
  State<PortfolioActionsReveal> createState() => _PortfolioActionsRevealState();
}

class _PortfolioActionsRevealState extends State<PortfolioActionsReveal> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final bool rowHovered = RowHoverScope.of(context);
    return Focus(
      canRequestFocus: false,
      onFocusChange: (bool value) => setState(() => _focused = value),
      child: AnimatedOpacity(
        duration: AppMotion.effective(context, AppMotion.fast),
        curve: AppMotion.ease,
        opacity: (rowHovered || _focused) ? 1 : 0,
        child: widget.child,
      ),
    );
  }
}

/// Hover della riga condiviso con le sue celle (azioni rivelate).
class RowHoverScope extends InheritedWidget {
  /// Crea lo scope di hover.
  const RowHoverScope({
    super.key,
    required this.hovered,
    required super.child,
  });

  /// True quando il puntatore o il focus sono sulla riga.
  final bool hovered;

  /// Hover della riga corrente (false fuori da una [PortfolioTableRow]).
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RowHoverScope>()?.hovered ??
      false;

  @override
  bool updateShouldNotify(RowHoverScope oldWidget) =>
      oldWidget.hovered != hovered;
}

/// Placeholder di caricamento di una tabella (righe da 40px).
class PortfolioTableSkeleton extends StatelessWidget {
  /// Crea lo skeleton.
  const PortfolioTableSkeleton({super.key, this.rows = 3});

  /// Numero di righe mostrate.
  final int rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        for (int i = 0; i < rows; i++)
          const SkeletonRow(height: AppSizes.rowCompact),
      ],
    );
  }
}

/// Allineamento testuale coerente con [Alignment].
TextAlign _textAlignFor(Alignment alignment) {
  if (alignment == Alignment.centerRight) return TextAlign.right;
  if (alignment == Alignment.center) return TextAlign.center;
  return TextAlign.left;
}
