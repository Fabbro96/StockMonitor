import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Wrapper del contenuto di pagina (`.content-wrapper`): larghezza massima
/// 1400 centrata, padding 22/18/12 ai breakpoint (più 28px in basso su
/// mobile) e, di default, scroll verticale.
///
/// Le pagine della shell lo usano come primo figlio del proprio layout:
/// ```dart
/// PageContent(child: Column(children: [...sezioni...]));
/// ```
class PageContent extends StatelessWidget {
  /// Avvolge [child] con il wrapper di pagina.
  const PageContent({
    super.key,
    required this.child,
    this.scrollable = true,
    this.maxWidth = AppTokens.contentMaxWidth,
    this.padding,
  });

  /// Contenuto della pagina.
  final Widget child;

  /// True = scroll verticale (default).
  final bool scrollable;

  /// Larghezza massima del contenuto.
  final double maxWidth;

  /// Padding esplicito; default responsive da [AppSpacing.pagePadding].
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final bool compact = context.isCompact;
    final double pagePadding = AppSpacing.pagePadding(context.windowWidth);
    final EdgeInsetsGeometry effectivePadding = padding ??
        EdgeInsets.fromLTRB(
          pagePadding,
          pagePadding,
          pagePadding,
          compact ? 28 : pagePadding,
        );

    final Widget content = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(padding: effectivePadding, child: child),
      ),
    );

    if (!scrollable) return content;
    return SingleChildScrollView(child: content);
  }
}
