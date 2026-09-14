import 'package:flutter/material.dart';

import 'tokens.dart';

/// Tema chiaro dell'app, costruito dai token CSS del frontend.
final ThemeData lightTheme = buildAppTheme(AppTokens.light);

/// Tema scuro dell'app, costruito dai token CSS del frontend.
final ThemeData darkTheme = buildAppTheme(AppTokens.dark);

/// Costruisce un [ThemeData] completo a partire da un set di [AppTokens]:
/// colorScheme, textTheme (base 14px), temi di bottoni/input/dialog/tooltip,
/// scrollbar, data table e transizioni pagina.
ThemeData buildAppTheme(AppTokens t) {
  final ColorScheme colorScheme = ColorScheme(
    brightness: t.brightness,
    primary: t.primarySolid,
    onPrimary: t.onPrimarySolid,
    primaryContainer: t.primaryGlow,
    onPrimaryContainer: t.primary,
    secondary: t.primary,
    onSecondary: t.onPrimarySolid,
    secondaryContainer: t.primaryGlow,
    onSecondaryContainer: t.primary,
    tertiary: t.purple,
    onTertiary: t.onPrimarySolid,
    tertiaryContainer: t.purpleBg,
    onTertiaryContainer: t.purple,
    error: t.danger,
    onError: t.onPrimarySolid,
    errorContainer: t.dangerBg,
    onErrorContainer: t.danger,
    surface: t.surface,
    onSurface: t.textPrimary,
    surfaceDim: t.bg,
    surfaceBright: t.surface,
    surfaceContainerLowest: t.bg,
    surfaceContainerLow: t.bgSecondary,
    surfaceContainer: t.surfaceHover,
    surfaceContainerHigh: t.surfaceActive,
    surfaceContainerHighest: t.surfaceActive,
    onSurfaceVariant: t.textSecondary,
    outline: t.border,
    outlineVariant: t.borderSubtle,
    shadow: const Color(0xFF101828),
    scrim: t.scrim,
    inverseSurface: t.textPrimary,
    onInverseSurface: t.surface,
    inversePrimary: t.primary,
    surfaceTint: Colors.transparent,
  );

  final InputDecorationThemeData inputTheme = _inputDecorationTheme(t);

  return ThemeData(
    useMaterial3: true,
    brightness: t.brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: t.bg,
    canvasColor: t.bg,
    cardColor: t.surface,
    dividerColor: t.borderSubtle,
    disabledColor: t.textMuted,
    hintColor: t.textMuted,
    highlightColor: Colors.transparent,
    splashFactory: NoSplash.splashFactory,
    visualDensity: VisualDensity.standard,
    fontFamilyFallback: AppTokens.fontFallback,
    extensions: <ThemeExtension<dynamic>>[t],
    textTheme: _buildTextTheme(t),
    primaryTextTheme: _buildTextTheme(t),
    iconTheme: IconThemeData(color: t.textSecondary, size: 18),
    primaryIconTheme: IconThemeData(color: t.textSecondary, size: 18),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: t.primary,
      selectionColor: t.primaryGlow,
      selectionHandleColor: t.primary,
    ),
    dividerTheme: DividerThemeData(
      color: t.borderSubtle,
      thickness: 1,
      space: 1,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shadowColor: Colors.transparent,
      barrierColor: t.scrim,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.modal),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      titleTextStyle: AppText.modalTitleFor(t),
      contentTextStyle: AppText.bodyFor(t),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: t.surface,
      modalBackgroundColor: t.surface,
      modalBarrierColor: t.scrim,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      modalElevation: 0,
      shadowColor: Colors.transparent,
      showDragHandle: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.modal)),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(AppRadii.input),
        boxShadow: t.shadowMd,
      ),
      textStyle: TextStyle(
        color: t.textPrimary,
        fontSize: 12.2,
        fontWeight: FontWeight.w400,
        height: 1.4,
        fontFamilyFallback: AppTokens.fontFallback,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      constraints: const BoxConstraints(maxWidth: 230),
      waitDuration: const Duration(milliseconds: 350),
      showDuration: const Duration(seconds: 8),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll<double>(8),
      radius: const Radius.circular(4),
      crossAxisMargin: 0,
      minThumbLength: 32,
      trackVisibility: const WidgetStatePropertyAll<bool>(false),
      thumbColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
        return states.contains(WidgetState.hovered) || states.contains(WidgetState.dragged)
            ? t.textMuted
            : t.borderStrong;
      }),
    ),
    inputDecorationTheme: inputTheme,
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: _solidButtonStyle(t, t.primarySolid, t.primarySolidHover, t.onPrimarySolid),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: _solidButtonStyle(t, t.primarySolid, t.primarySolidHover, t.onPrimarySolid),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(style: _ghostButtonStyle(t)),
    textButtonTheme: TextButtonThemeData(style: _textButtonStyle(t)),
    iconButtonTheme: IconButtonThemeData(style: _iconButtonStyle(t)),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.small)),
      side: BorderSide(color: t.borderStrong, width: 1.5),
      fillColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
        if (states.contains(WidgetState.disabled)) return t.surfaceActive;
        return states.contains(WidgetState.selected) ? t.primarySolid : Colors.transparent;
      }),
      checkColor: WidgetStatePropertyAll<Color>(t.onPrimarySolid),
      overlayColor: WidgetStatePropertyAll<Color>(t.primaryGlow),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
        if (states.contains(WidgetState.disabled)) return t.textMuted;
        return states.contains(WidgetState.selected) ? t.primarySolid : t.borderStrong;
      }),
      overlayColor: WidgetStatePropertyAll<Color>(t.primaryGlow),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
        return states.contains(WidgetState.selected) ? t.onPrimarySolid : t.textMuted;
      }),
      trackColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
        return states.contains(WidgetState.selected) ? t.primarySolid : t.surfaceActive;
      }),
      trackOutlineColor: WidgetStatePropertyAll<Color>(t.border),
      overlayColor: WidgetStatePropertyAll<Color>(t.primaryGlow),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: t.primarySolid,
      linearTrackColor: t.surfaceActive,
      circularTrackColor: t.border,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: t.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.input),
        side: BorderSide(color: t.border),
      ),
      textStyle: AppText.bodyFor(t),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      textStyle: AppText.bodyFor(t),
      inputDecorationTheme: inputTheme,
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll<Color>(t.surface),
        surfaceTintColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
        elevation: const WidgetStatePropertyAll<double>(0),
        shape: WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.input),
            side: BorderSide(color: t.border),
          ),
        ),
      ),
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      scrimColor: t.scrim,
      elevation: 0,
      shadowColor: Colors.transparent,
      width: AppTokens.sidebarMobileWidth,
      shape: const RoundedRectangleBorder(),
    ),
    dataTableTheme: DataTableThemeData(
      headingRowColor: WidgetStatePropertyAll<Color>(t.surface),
      headingTextStyle: AppText.tableHeaderFor(t),
      headingRowHeight: 40,
      dataTextStyle: AppText.tableCellFor(t),
      dataRowMinHeight: 44,
      dataRowMaxHeight: 60,
      dividerThickness: 1,
      horizontalMargin: 12,
      columnSpacing: 18,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: t.textSecondary,
      textColor: t.textPrimary,
      selectedColor: t.primary,
      selectedTileColor: t.primaryGlow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.input)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: t.surface,
      contentTextStyle: AppText.bodyFor(t),
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.input),
        side: BorderSide(color: t.border),
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.fuchsia: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
      },
    ),
  );
}

InputDecorationThemeData _inputDecorationTheme(AppTokens t) => InputDecorationThemeData(
      filled: true,
      fillColor: t.surface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      hintStyle: TextStyle(color: t.textMuted, fontSize: 14.4, fontWeight: FontWeight.w400),
      labelStyle: AppText.formLabelFor(t),
      floatingLabelStyle: TextStyle(color: t.primary, fontSize: 13.1, fontWeight: FontWeight.w600),
      errorStyle: TextStyle(color: t.danger, fontSize: 12.2, height: 1.3),
      prefixIconColor: t.textMuted,
      suffixIconColor: t.textMuted,
      border: _inputBorder(t.border),
      enabledBorder: _inputBorder(t.border),
      focusedBorder: _GlowOutlineInputBorder(
        borderSide: BorderSide(color: t.primary, width: 1),
        borderRadius: BorderRadius.circular(AppRadii.input),
        glowColor: t.primaryGlow,
      ),
      errorBorder: _inputBorder(t.dangerBorder),
      focusedErrorBorder: _GlowOutlineInputBorder(
        borderSide: BorderSide(color: t.danger, width: 1),
        borderRadius: BorderRadius.circular(AppRadii.input),
        glowColor: t.dangerBg,
      ),
      disabledBorder: _inputBorder(t.borderSubtle),
    );

OutlineInputBorder _inputBorder(Color color) => OutlineInputBorder(
      borderSide: BorderSide(color: color, width: 1),
      borderRadius: BorderRadius.circular(AppRadii.input),
    );

ButtonStyle _solidButtonStyle(AppTokens t, Color background, Color hover, Color foreground) {
  return ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
      if (states.contains(WidgetState.disabled)) return t.surfaceActive;
      if (states.contains(WidgetState.hovered) || states.contains(WidgetState.pressed)) return hover;
      return background;
    }),
    foregroundColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
      return states.contains(WidgetState.disabled) ? t.textMuted : foreground;
    }),
    overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
    side: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
      return BorderSide(color: states.contains(WidgetState.disabled) ? t.border : Colors.transparent);
    }),
    elevation: const WidgetStatePropertyAll<double>(0),
    shadowColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
    surfaceTintColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
    padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
      EdgeInsets.symmetric(horizontal: 14, vertical: 7),
    ),
    minimumSize: const WidgetStatePropertyAll<Size>(Size(0, 32)),
    maximumSize: const WidgetStatePropertyAll<Size>(Size(double.infinity, 44)),
    shape: WidgetStatePropertyAll<OutlinedBorder>(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.input)),
    ),
    textStyle: WidgetStatePropertyAll<TextStyle>(AppText.buttonFor()),
    mouseCursor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
      return states.contains(WidgetState.disabled) ? SystemMouseCursors.forbidden : SystemMouseCursors.click;
    }),
    animationDuration: AppMotion.fast,
    enableFeedback: false,
  );
}

ButtonStyle _ghostButtonStyle(AppTokens t) {
  return ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
      if (states.contains(WidgetState.disabled)) return t.surfaceActive;
      if (states.contains(WidgetState.hovered) || states.contains(WidgetState.pressed)) return t.surfaceHover;
      return t.surface;
    }),
    foregroundColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
      if (states.contains(WidgetState.disabled)) return t.textMuted;
      if (states.contains(WidgetState.hovered)) return t.primary;
      return t.textSecondary;
    }),
    overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
    side: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
      if (states.contains(WidgetState.hovered) && !states.contains(WidgetState.disabled)) {
        return BorderSide(color: t.primary);
      }
      return BorderSide(color: t.border);
    }),
    elevation: const WidgetStatePropertyAll<double>(0),
    shadowColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
    surfaceTintColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
    padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
      EdgeInsets.symmetric(horizontal: 14, vertical: 7),
    ),
    minimumSize: const WidgetStatePropertyAll<Size>(Size(0, 32)),
    maximumSize: const WidgetStatePropertyAll<Size>(Size(double.infinity, 44)),
    shape: WidgetStatePropertyAll<OutlinedBorder>(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.input)),
    ),
    textStyle: WidgetStatePropertyAll<TextStyle>(AppText.buttonFor()),
    mouseCursor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
      return states.contains(WidgetState.disabled) ? SystemMouseCursors.forbidden : SystemMouseCursors.click;
    }),
    animationDuration: AppMotion.fast,
    enableFeedback: false,
  );
}

ButtonStyle _textButtonStyle(AppTokens t) {
  return _ghostButtonStyle(t).copyWith(
    backgroundColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
    side: const WidgetStatePropertyAll<BorderSide>(BorderSide(color: Colors.transparent)),
    overlayColor: WidgetStatePropertyAll<Color>(t.primaryGlow),
  );
}

ButtonStyle _iconButtonStyle(AppTokens t) {
  return ButtonStyle(
    foregroundColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
      if (states.contains(WidgetState.disabled)) return t.textMuted;
      if (states.contains(WidgetState.hovered)) return t.primary;
      return t.textSecondary;
    }),
    backgroundColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
    overlayColor: WidgetStatePropertyAll<Color>(t.primaryGlow),
    side: const WidgetStatePropertyAll<BorderSide>(BorderSide(color: Colors.transparent)),
    elevation: const WidgetStatePropertyAll<double>(0),
    padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(EdgeInsets.all(7)),
    minimumSize: const WidgetStatePropertyAll<Size>(Size(34, 34)),
    maximumSize: const WidgetStatePropertyAll<Size>(Size(34, 34)),
    shape: WidgetStatePropertyAll<OutlinedBorder>(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.input)),
    ),
    animationDuration: AppMotion.fast,
    enableFeedback: false,
  );
}

TextTheme _buildTextTheme(AppTokens t) {
  return TextTheme(
    displayLarge: TextStyle(color: t.textPrimary, fontSize: 34, fontWeight: FontWeight.w700, height: 1.2),
    displayMedium: TextStyle(color: t.textPrimary, fontSize: 28, fontWeight: FontWeight.w700, height: 1.2),
    displaySmall: TextStyle(color: t.textPrimary, fontSize: 24, fontWeight: FontWeight.w700, height: 1.25),
    headlineLarge: TextStyle(color: t.textPrimary, fontSize: 21, fontWeight: FontWeight.w700, height: 1.25),
    headlineMedium: TextStyle(color: t.textPrimary, fontSize: 19, fontWeight: FontWeight.w700, height: 1.3),
    headlineSmall: TextStyle(color: t.textPrimary, fontSize: 17, fontWeight: FontWeight.w700, height: 1.3),
    titleLarge: TextStyle(
      color: t.textPrimary,
      fontSize: 17.9,
      fontWeight: FontWeight.w700,
      height: 1.3,
      letterSpacing: -0.18,
    ),
    titleMedium: TextStyle(
      color: t.textPrimary,
      fontSize: 15.7,
      fontWeight: FontWeight.w600,
      height: 1.35,
      letterSpacing: -0.16,
    ),
    titleSmall: TextStyle(color: t.textSecondary, fontSize: 13.1, fontWeight: FontWeight.w600, height: 1.4),
    bodyLarge: TextStyle(color: t.textPrimary, fontSize: 15.2, fontWeight: FontWeight.w400, height: 1.5),
    bodyMedium: TextStyle(color: t.textPrimary, fontSize: 14, fontWeight: FontWeight.w400, height: 1.5),
    bodySmall: TextStyle(color: t.textSecondary, fontSize: 13.1, fontWeight: FontWeight.w400, height: 1.45),
    labelLarge: TextStyle(color: t.textPrimary, fontSize: 13.8, fontWeight: FontWeight.w600, height: 1.3),
    labelMedium: TextStyle(color: t.textSecondary, fontSize: 12.2, fontWeight: FontWeight.w600, height: 1.3),
    labelSmall: TextStyle(
      color: t.textSecondary,
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
      height: 1.3,
      letterSpacing: 0.58,
    ),
  );
}

/// Stili di testo "di prodotto" allineati al CSS del frontend
/// (`.page-title`, `.card-title`, `.stat-*`, tabelle, form, login).
///
/// Due livelli di API:
/// - i metodi `*For(AppTokens)` costruiscono lo stile dai soli token, con
///   flag `compact`/`tiny` per le taglie responsive;
/// - i metodi che prendono un [BuildContext] usano i token del tema attivo e
///   i breakpoint reali della finestra.
///
/// Il colore arriva dai token: sugli stessi stili si può poi applicare
/// `.copyWith(color: ...)` per profit/loss.
abstract final class AppText {
  /// Titolo di pagina in topbar (`1.12rem/700`, `1rem` sotto 640).
  static TextStyle pageTitle(BuildContext context) =>
      pageTitleFor(context.tokens, compact: context.isCompact);

  /// [pageTitle] dai soli token.
  static TextStyle pageTitleFor(AppTokens t, {bool compact = false}) => TextStyle(
        color: t.textPrimary,
        fontSize: compact ? 16 : 17.9,
        fontWeight: FontWeight.w700,
        height: 1.3,
        letterSpacing: -0.18,
        fontFamilyFallback: AppTokens.fontFallback,
      );

  /// Titolo di card/sezione (`.card-title`, `.98rem/600`).
  static TextStyle cardTitle(BuildContext context) => cardTitleFor(context.tokens);

  /// [cardTitle] dai soli token.
  static TextStyle cardTitleFor(AppTokens t) => TextStyle(
        color: t.textPrimary,
        fontSize: 15.7,
        fontWeight: FontWeight.w600,
        height: 1.35,
        letterSpacing: -0.16,
        fontFamilyFallback: AppTokens.fontFallback,
      );

  /// Etichetta maiuscola di sezione (`.text-xs` + `uppercase`).
  static TextStyle sectionLabel(BuildContext context) => sectionLabelFor(context.tokens);

  /// [sectionLabel] dai soli token.
  static TextStyle sectionLabelFor(AppTokens t) => TextStyle(
        color: t.textSecondary,
        fontSize: 12.2,
        fontWeight: FontWeight.w600,
        height: 1.3,
        letterSpacing: 0.6,
        fontFamilyFallback: AppTokens.fontFallback,
      );

  /// Etichetta di uno stat (`.stat-label`, `.76rem`, maiuscola con tracking).
  static TextStyle statLabel(BuildContext context) =>
      statLabelFor(context.tokens, compact: context.isCompact);

  /// [statLabel] dai soli token.
  static TextStyle statLabelFor(AppTokens t, {bool compact = false}) => TextStyle(
        color: t.textSecondary,
        fontSize: compact ? 10.9 : 12.2,
        fontWeight: FontWeight.w600,
        height: 1.3,
        letterSpacing: 0.6,
        fontFamilyFallback: AppTokens.fontFallback,
      );

  /// Valore numerico di uno stat (mono, tabular, 1.55rem → 1.25rem → 1.1rem).
  static TextStyle statValue(BuildContext context) =>
      statValueFor(context.tokens, compact: context.isCompact, tiny: context.isTiny);

  /// [statValue] dai soli token.
  static TextStyle statValueFor(AppTokens t, {bool compact = false, bool tiny = false}) {
    final double size = tiny ? 17.6 : (compact ? 20 : 24.8);
    return TextStyle(
      color: t.textPrimary,
      fontSize: size,
      fontWeight: FontWeight.w700,
      height: 1.25,
      letterSpacing: size * -0.02,
      fontFamily: AppTokens.monoFontFamily,
      fontFamilyFallback: AppTokens.monoFontFallback,
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );
  }

  /// Variante ridotta del valore stat (`.stat-value-sm`, 1.25rem).
  static TextStyle statValueSm(BuildContext context) =>
      statValueSmFor(context.tokens, compact: context.isCompact);

  /// [statValueSm] dai soli token.
  static TextStyle statValueSmFor(AppTokens t, {bool compact = false}) => TextStyle(
        color: t.textPrimary,
        fontSize: compact ? 16.8 : 20,
        fontWeight: FontWeight.w700,
        height: 1.25,
        letterSpacing: -0.2,
        fontFamily: AppTokens.monoFontFamily,
        fontFamilyFallback: AppTokens.monoFontFallback,
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      );

  /// Descrizione sotto il valore di uno stat (`.stat-desc`, `.74rem` muted).
  static TextStyle statDesc(BuildContext context) =>
      statDescFor(context.tokens, compact: context.isCompact);

  /// [statDesc] dai soli token.
  static TextStyle statDescFor(AppTokens t, {bool compact = false}) => TextStyle(
        color: t.textMuted,
        fontSize: compact ? 10.9 : 11.8,
        fontWeight: FontWeight.w400,
        height: 1.35,
        fontFamilyFallback: AppTokens.fontFallback,
      );

  /// Testo di corpo base (14px, line-height 1.5).
  static TextStyle body(BuildContext context) => bodyFor(context.tokens);

  /// [body] dai soli token.
  static TextStyle bodyFor(AppTokens t) => TextStyle(
        color: t.textPrimary,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.5,
        fontFamilyFallback: AppTokens.fontFallback,
      );

  /// Testo di corpo secondario (muted).
  static TextStyle bodySecondary(BuildContext context) =>
      bodyFor(context.tokens).copyWith(color: context.tokens.textSecondary);

  /// Testo compatto (`.text-sm`, `.82rem`).
  static TextStyle small(BuildContext context) => smallFor(context.tokens);

  /// [small] dai soli token.
  static TextStyle smallFor(AppTokens t) => TextStyle(
        color: t.textPrimary,
        fontSize: 13.1,
        fontWeight: FontWeight.w400,
        height: 1.45,
        fontFamilyFallback: AppTokens.fontFallback,
      );

  /// Testo minuto/attenuato (`.text-xs`, `.74rem` muted).
  static TextStyle caption(BuildContext context) => captionFor(context.tokens);

  /// [caption] dai soli token.
  static TextStyle captionFor(AppTokens t) => TextStyle(
        color: t.textMuted,
        fontSize: 11.8,
        fontWeight: FontWeight.w400,
        height: 1.4,
        fontFamilyFallback: AppTokens.fontFallback,
      );

  /// Etichetta di form (`.form-group label`, `.82rem/600` secondary).
  static TextStyle formLabel(BuildContext context) => formLabelFor(context.tokens);

  /// [formLabel] dai soli token.
  static TextStyle formLabelFor(AppTokens t) => TextStyle(
        color: t.textSecondary,
        fontSize: 13.1,
        fontWeight: FontWeight.w600,
        height: 1.3,
        fontFamilyFallback: AppTokens.fontFallback,
      );

  /// Intestazione di tabella (`th`, `.72rem/600` maiuscola con tracking).
  static TextStyle tableHeader(BuildContext context) => tableHeaderFor(context.tokens);

  /// [tableHeader] dai soli token.
  static TextStyle tableHeaderFor(AppTokens t) => TextStyle(
        color: t.textSecondary,
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        height: 1.3,
        letterSpacing: 0.58,
        fontFamilyFallback: AppTokens.fontFallback,
      );

  /// Cella di tabella (`td`, `.88rem`).
  static TextStyle tableCell(BuildContext context) => tableCellFor(context.tokens);

  /// [tableCell] dai soli token.
  static TextStyle tableCellFor(AppTokens t) => TextStyle(
        color: t.textPrimary,
        fontSize: 14.1,
        fontWeight: FontWeight.w400,
        height: 1.4,
        fontFamilyFallback: AppTokens.fontFallback,
      );

  /// Titolo di modale (`.modal-title`, `1.08rem/700`).
  static TextStyle modalTitle(BuildContext context) => modalTitleFor(context.tokens);

  /// [modalTitle] dai soli token.
  static TextStyle modalTitleFor(AppTokens t) => TextStyle(
        color: t.textPrimary,
        fontSize: 17.3,
        fontWeight: FontWeight.w700,
        height: 1.3,
        letterSpacing: -0.17,
        fontFamilyFallback: AppTokens.fontFallback,
      );

  /// Etichetta di bottone (`.btn`, `.86rem/600`).
  static TextStyle button(BuildContext context) => buttonFor();

  /// [button] dai soli token (il colore lo decide il ButtonStyle).
  static TextStyle buttonFor() => const TextStyle(
        fontSize: 13.8,
        fontWeight: FontWeight.w600,
        height: 1.3,
        fontFamilyFallback: AppTokens.fontFallback,
      );

  /// Link testuale (`.stock-ticker-link`, primary/600).
  static TextStyle link(BuildContext context) =>
      buttonFor().copyWith(color: context.tokens.primary);

  /// Voce di navigazione della sidebar (`.nav-link`, `.9rem/500`).
  static TextStyle navLabel(BuildContext context, {bool active = false}) {
    final AppTokens t = context.tokens;
    return TextStyle(
      color: active ? t.primary : t.textSecondary,
      fontSize: 14.4,
      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
      height: 1.3,
      fontFamilyFallback: AppTokens.fontFallback,
    );
  }

  /// Titolo del logo in sidebar (`.app-title`, `1.02rem/700`).
  static TextStyle appTitle(BuildContext context) {
    final AppTokens t = context.tokens;
    return TextStyle(
      color: t.textPrimary,
      fontSize: 16.3,
      fontWeight: FontWeight.w700,
      height: 1.3,
      letterSpacing: -0.16,
      fontFamilyFallback: AppTokens.fontFallback,
    );
  }

  /// Testo di un toast (`.toast`, `.86rem/500`).
  static TextStyle toast(BuildContext context) {
    final AppTokens t = context.tokens;
    return TextStyle(
      color: t.textPrimary,
      fontSize: 13.8,
      fontWeight: FontWeight.w500,
      height: 1.4,
      fontFamilyFallback: AppTokens.fontFallback,
    );
  }

  /// Titolo della login (`.login-title`, `1.35rem/700`).
  static TextStyle loginTitle(BuildContext context) {
    final AppTokens t = context.tokens;
    return TextStyle(
      color: t.textPrimary,
      fontSize: 21.6,
      fontWeight: FontWeight.w700,
      height: 1.3,
      letterSpacing: -0.2,
      fontFamilyFallback: AppTokens.fontFallback,
    );
  }

  /// Sottotitolo della login (`.login-subtitle`, `.88rem` secondary).
  static TextStyle loginSubtitle(BuildContext context) {
    final AppTokens t = context.tokens;
    return TextStyle(
      color: t.textSecondary,
      fontSize: 14.1,
      fontWeight: FontWeight.w400,
      height: 1.45,
      fontFamilyFallback: AppTokens.fontFallback,
    );
  }

  /// Nota di sicurezza sotto la login (`.security-badge`, `.74rem` muted).
  static TextStyle securityBadge(BuildContext context) {
    final AppTokens t = context.tokens;
    return TextStyle(
      color: t.textMuted,
      fontSize: 11.8,
      fontWeight: FontWeight.w500,
      height: 1.4,
      fontFamilyFallback: AppTokens.fontFallback,
    );
  }

  /// Numero mono a taglia configurabile (default 14, tabular).
  static TextStyle mono(BuildContext context, {double size = 14, FontWeight weight = FontWeight.w600, Color? color}) {
    return TextStyle(
      color: color ?? context.tokens.textPrimary,
      fontSize: size,
      fontWeight: weight,
      height: 1.4,
      fontFamily: AppTokens.monoFontFamily,
      fontFamilyFallback: AppTokens.monoFontFallback,
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );
  }
}

/// [OutlineInputBorder] con alone di focus (`box-shadow: 0 0 0 3px var(--primary-glow)`).
class _GlowOutlineInputBorder extends OutlineInputBorder {
  const _GlowOutlineInputBorder({
    super.borderSide,
    super.borderRadius,
    super.gapPadding,
    required this.glowColor,
  });

  /// Colore dell'alone (di norma `--primary-glow`).
  final Color glowColor;

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    double? gapStart,
    double gapExtent = 0.0,
    double gapPercentage = 0.0,
    TextDirection? textDirection,
  }) {
    // Anello pieno di 3px attorno al bordo, come il box-shadow del CSS.
    final RRect rrect = borderRadius.resolve(textDirection).toRRect(rect).inflate(2);
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = glowColor,
    );
    super.paint(
      canvas,
      rect,
      gapStart: gapStart,
      gapExtent: gapExtent,
      gapPercentage: gapPercentage,
      textDirection: textDirection,
    );
  }

  @override
  _GlowOutlineInputBorder copyWith({
    BorderSide? borderSide,
    BorderRadius? borderRadius,
    double? gapPadding,
  }) {
    return _GlowOutlineInputBorder(
      borderSide: borderSide ?? this.borderSide,
      borderRadius: borderRadius ?? this.borderRadius,
      gapPadding: gapPadding ?? this.gapPadding,
      glowColor: glowColor,
    );
  }

  @override
  _GlowOutlineInputBorder scale(double t) {
    return _GlowOutlineInputBorder(
      borderSide: borderSide.scale(t),
      borderRadius: borderRadius * t,
      gapPadding: gapPadding * t,
      glowColor: glowColor,
    );
  }
}
