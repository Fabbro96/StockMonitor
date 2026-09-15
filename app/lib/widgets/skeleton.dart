import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Wrapper "pulse": opacità 1 → 0.5 in 1.4s. Con `prefers-reduced-motion`
/// resta statico.
class SkeletonPulse extends StatefulWidget {
  /// Crea l'animazione pulse attorno a [child].
  const SkeletonPulse({super.key, required this.child});

  /// Contenuto da animare (di norma un blocco `track`).
  final Widget child;

  @override
  State<SkeletonPulse> createState() => _SkeletonPulseState();
}

class _SkeletonPulseState extends State<SkeletonPulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  late final Animation<double> _opacity = Tween<double>(begin: 1, end: 0.5).animate(
    CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    return FadeTransition(opacity: _opacity, child: widget.child);
  }
}

/// Blocco skeleton (colore `track`, raggio 4 di default).
class SkeletonBox extends StatelessWidget {
  /// Crea un blocco skeleton.
  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.radius = AppRadii.control,
    this.margin,
  });

  /// Larghezza (null = intrinseca).
  final double? width;

  /// Altezza.
  final double? height;

  /// Raggio degli angoli.
  final double radius;

  /// Margine esterno.
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return SkeletonPulse(
      child: Container(
        width: width,
        height: height,
        margin: margin,
        decoration: BoxDecoration(
          color: context.tokens.track,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}

/// Riga di testo skeleton (h12, raggio 3).
class SkeletonLine extends StatelessWidget {
  /// Crea una riga di testo skeleton.
  const SkeletonLine({super.key, this.width, this.height = 12, this.margin});

  /// Larghezza (null = intrinseca).
  final double? width;

  /// Altezza della riga.
  final double height;

  /// Margine esterno.
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return SkeletonBox(width: width, height: height, radius: AppRadii.tag, margin: margin);
  }
}

/// Placeholder di un valore stat (110×26).
class SkeletonValue extends StatelessWidget {
  /// Crea il placeholder del valore.
  const SkeletonValue({super.key});

  @override
  Widget build(BuildContext context) {
    return const SkeletonBox(width: 110, height: 26, margin: EdgeInsets.only(top: 6));
  }
}

/// Placeholder di una riga tabella (h40, mb8).
class SkeletonRow extends StatelessWidget {
  /// Crea il placeholder di riga.
  const SkeletonRow({super.key, this.height = AppSizes.rowCompact});

  /// Altezza della riga.
  final double height;

  @override
  Widget build(BuildContext context) {
    return SkeletonBox(
      width: double.infinity,
      height: height,
      margin: const EdgeInsets.only(bottom: AppSpacing.s8),
    );
  }
}

/// Placeholder di uno stat (h72, raggio pannello).
class SkeletonStat extends StatelessWidget {
  /// Crea il placeholder di stat card.
  const SkeletonStat({super.key});

  @override
  Widget build(BuildContext context) {
    return const SkeletonBox(width: double.infinity, height: 72, radius: AppRadii.card);
  }
}

/// Placeholder di una card (min-h 88).
class SkeletonCard extends StatelessWidget {
  /// Crea il placeholder di card.
  const SkeletonCard({super.key, this.height = 88});

  /// Altezza della card.
  final double height;

  @override
  Widget build(BuildContext context) {
    return SkeletonBox(width: double.infinity, height: height, radius: AppRadii.card);
  }
}

/// Placeholder di un grafico (h240, raggio pannello).
class SkeletonChart extends StatelessWidget {
  /// Crea il placeholder di grafico.
  const SkeletonChart({super.key, this.height = 240});

  /// Altezza del blocco.
  final double height;

  @override
  Widget build(BuildContext context) {
    return SkeletonBox(width: double.infinity, height: height, radius: AppRadii.card);
  }
}

/// Spinner: track `track`, arco d'accento.
class AppSpinner extends StatelessWidget {
  /// Crea lo spinner.
  const AppSpinner({super.key, this.size = 24, this.strokeWidth = 2});

  /// Diametro.
  final double size;

  /// Spessore dell'arco.
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: strokeWidth,
        color: context.tokens.primarySolid,
        backgroundColor: context.tokens.track,
      ),
    );
  }
}

/// Overlay di caricamento: superficie all'85% + spinner, sopra il contenuto,
/// senza rimuoverlo dal layout.
class AppLoaderOverlay extends StatelessWidget {
  /// Avvolge [child] con l'overlay quando [loading] è true.
  const AppLoaderOverlay({
    super.key,
    required this.loading,
    required this.child,
    this.borderRadius,
  });

  /// True = overlay visibile.
  final bool loading;

  /// Contenuto sotto l'overlay.
  final Widget child;

  /// Raggio di ritaglio dell'overlay (es. raggio pannello).
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    Widget overlay = ColoredBox(
      color: context.tokens.surface.withValues(alpha: 0.85),
      child: const Center(child: AppSpinner()),
    );
    if (borderRadius != null) {
      overlay = ClipRRect(borderRadius: borderRadius!, child: overlay);
    }

    return Stack(
      children: <Widget>[
        child,
        if (loading) Positioned.fill(child: overlay),
      ],
    );
  }
}
