import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_button.dart';

/// Mostra un form modale del Portafoglio: dialog centrato da 640px in su,
/// bottom sheet agganciato in basso sotto (pattern Registro per i form lunghi
/// su mobile).
///
/// Il contenuto decide la propria impaginazione con [PortfolioModalShell];
/// entrambe le strade restituiscono lo stesso risultato al chiamante.
Future<T?> showPortfolioModal<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  if (context.isCompact) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext sheetContext) => Padding(
        // Il campo attivo resta visibile sopra la tastiera.
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: builder(sheetContext),
      ),
    );
  }
  return showDialog<T>(
    context: context,
    barrierColor: context.tokens.scrim,
    builder: (BuildContext _) => builder(context),
  );
}

/// Guscio di un form del Portafoglio: intestazione con titolo e chiusura,
/// corpo scrollabile, barra azioni a destra.
///
/// - ≥640px: [Dialog] centrato (raggio 10, bordo 1px), larghezza massima
///   [maxWidth];
/// - <640px: superficie a tutta larghezza agganciata in basso, con
///   maniglietta di trascinamento e rispetto della safe area.
class PortfolioModalShell extends StatelessWidget {
  /// Crea il guscio del form.
  const PortfolioModalShell({
    super.key,
    required this.title,
    required this.child,
    this.actions = const <Widget>[],
    this.onClose,
    this.maxWidth = 480,
  });

  /// Titolo del form.
  final String title;

  /// Corpo del form (scrollabile).
  final Widget child;

  /// Azioni della barra inferiore (di norma `Annulla` + conferma).
  final List<Widget> actions;

  /// Callback di chiusura; `null` nasconde la X.
  final VoidCallback? onClose;

  /// Larghezza massima in modalità dialog.
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final bool sheet = context.isCompact;
    final double maxHeight =
        MediaQuery.sizeOf(context).height * (sheet ? 0.94 : 0.85);
    final double safeBottom = sheet
        ? MediaQuery.paddingOf(context).bottom
        : 0;

    final Widget header = Row(
      children: <Widget>[
        Expanded(
          child: Text(
            title,
            style: AppText.modalTitle(context),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (onClose != null)
          AppIconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Chiudi',
            semanticLabel: 'Chiudi',
            onPressed: onClose,
          ),
      ],
    );

    final Widget body = Flexible(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.s18,
          AppSpacing.s4,
          AppSpacing.s18,
          AppSpacing.s18,
        ),
        child: child,
      ),
    );

    final Widget footer = actions.isEmpty
        ? const SizedBox.shrink()
        : Container(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.s18,
              AppSpacing.s12,
              AppSpacing.s18,
              AppSpacing.s14 + safeBottom,
            ),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: t.borderSubtle)),
            ),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: AppSpacing.s8,
              runSpacing: AppSpacing.s8,
              children: actions,
            ),
          );

    final Widget content = ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: sheet ? double.infinity : maxWidth,
        maxHeight: maxHeight,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (sheet) ...<Widget>[
            const SizedBox(height: AppSpacing.s8),
            Container(
              width: 36,
              height: 3,
              decoration: BoxDecoration(
                color: t.borderStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: AppSpacing.s6),
          ],
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.s18,
              sheet ? AppSpacing.s6 : AppSpacing.s18,
              AppSpacing.s18,
              0,
            ),
            child: header,
          ),
          body,
          footer,
        ],
      ),
    );

    if (!sheet) {
      return Dialog(
        backgroundColor: t.surface,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.sheet),
          side: BorderSide(color: t.border),
        ),
        child: content,
      );
    }

    return Material(
      color: t.surfaceRaised,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.sheet)),
      ),
      child: content,
    );
  }
}
