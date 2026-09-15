import 'package:flutter/material.dart';

import 'tokens.dart';

/// Tema chiaro "carta" del linguaggio Registro.
final ThemeData lightTheme = buildAppTheme(AppTokens.light);

/// Tema scuro "carbone" del linguaggio Registro.
final ThemeData darkTheme = buildAppTheme(AppTokens.dark);

/// Costruisce un [ThemeData] completo a partire da un set di [AppTokens]:
/// colorScheme, textTheme, temi di bottoni/input/dialogo/menu/tooltip,
/// scrollbar, tabella e transizioni pagina.
ThemeData buildAppTheme(AppTokens t) {
  final ColorScheme colorScheme = ColorScheme(
    brightness: t.brightness,
    primary: t.primarySolid,
    onPrimary: t.onPrimarySolid,
    primaryContainer: t.primaryGlow,
    onPrimaryContainer: t.primary,
    secondary: t.cyan,
    onSecondary: t.isDark ? t.surfaceInverse : t.onPrimarySolid,
    secondaryContainer: t.primaryGlow,
    onSecondaryContainer: t.cyan,
    tertiary: t.purple,
    onTertiary: t.isDark ? t.surfaceInverse : t.onPrimarySolid,
    tertiaryContainer: t.purpleBg,
    onTertiaryContainer: t.purple,
    error: t.danger,
    onError: t.onDangerSolid,
    errorContainer: t.dangerBg,
    onErrorContainer: t.danger,
    surface: t.surface,
    onSurface: t.textPrimary,
    surfaceDim: t.bg,
    surfaceBright: t.surfaceRaised,
    surfaceContainerLowest: t.bg,
    surfaceContainerLow: t.bgSecondary,
    surfaceContainer: t.surfaceSunken,
    surfaceContainerHigh: t.surfaceHover,
    surfaceContainerHighest: t.surfaceActive,
    onSurfaceVariant: t.textSecondary,
    outline: t.border,
    outlineVariant: t.borderSubtle,
    shadow: t.surfaceInverse,
    scrim: t.scrim,
    inverseSurface: t.surfaceInverse,
    onInverseSurface: t.textInverse,
    inversePrimary: t.primarySolid,
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
    focusColor: t.focusRing,
    hoverColor: t.surfaceHover,
    highlightColor: Colors.transparent,
    splashFactory: NoSplash.splashFactory,
    visualDensity: VisualDensity.standard,
    fontFamilyFallback: AppTokens.fontFallback,
    extensions: <ThemeExtension<dynamic>>[t],
    textTheme: _buildTextTheme(t),
    primaryTextTheme: _buildTextTheme(t),
    iconTheme: IconThemeData(color: t.textSecondary, size: AppSizes.icon),
    primaryIconTheme: IconThemeData(color: t.textSecondary, size: AppSizes.icon),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: t.primary,
      selectionColor: t.selection,
      selectionHandleColor: t.primary,
    ),
    dividerTheme: DividerThemeData(
      color: t.borderSubtle,
      thickness: 1,
      space: 1,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: t.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shadowColor: Colors.black,
      barrierColor: t.scrim,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.sheet),
        side: BorderSide(color: t.border),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      titleTextStyle: AppText.modalTitleFor(t),
      contentTextStyle: AppText.bodyFor(t),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: t.surfaceRaised,
      modalBackgroundColor: t.surfaceRaised,
      modalBarrierColor: t.scrim,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      modalElevation: 8,
      shadowColor: Colors.black,
      showDragHandle: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.sheet)),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: t.surfaceInverse,
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      textStyle: TextStyle(
        color: t.textInverse,
        fontSize: 11.8,
        fontWeight: FontWeight.w500,
        height: 1.35,
        fontFamilyFallback: AppTokens.fontFallback,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      constraints: const BoxConstraints(maxWidth: 250),
      waitDuration: const Duration(milliseconds: 320),
      showDuration: const Duration(seconds: 8),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll<double>(7),
      radius: const Radius.circular(4),
      crossAxisMargin: 2,
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.xs)),
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
        if (states.contains(WidgetState.disabled)) return t.textFaint;
        return states.contains(WidgetState.selected) ? t.primarySolid : t.borderStrong;
      }),
      overlayColor: WidgetStatePropertyAll<Color>(t.primaryGlow),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
        return states.contains(WidgetState.selected) ? t.onPrimarySolid : t.textSecondary;
      }),
      trackColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
        if (states.contains(WidgetState.disabled)) return t.surfaceActive;
        return states.contains(WidgetState.selected) ? t.primarySolid : t.track;
      }),
      trackOutlineColor: WidgetStatePropertyAll<Color>(t.border),
      overlayColor: WidgetStatePropertyAll<Color>(t.primaryGlow),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: t.primarySolid,
      linearTrackColor: t.track,
      circularTrackColor: t.track,
      linearMinHeight: 4,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: t.surfaceSunken,
      selectedColor: t.primaryGlow,
      disabledColor: t.surfaceActive,
      labelStyle: AppText.smallFor(t).copyWith(fontWeight: FontWeight.w500),
      secondaryLabelStyle: AppText.smallFor(t).copyWith(color: t.primary, fontWeight: FontWeight.w600),
      side: BorderSide(color: t.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.tag)),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      showCheckmark: false,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: t.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shadowColor: Colors.black,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.control),
        side: BorderSide(color: t.border),
      ),
      textStyle: AppText.bodyFor(t),
      labelTextStyle: WidgetStatePropertyAll<TextStyle>(AppText.bodyFor(t)),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      textStyle: AppText.bodyFor(t),
      inputDecorationTheme: inputTheme,
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll<Color>(t.surfaceRaised),
        surfaceTintColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
        elevation: const WidgetStatePropertyAll<double>(6),
        shadowColor: const WidgetStatePropertyAll<Color>(Colors.black),
        shape: WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.control),
            side: BorderSide(color: t.border),
          ),
        ),
      ),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll<Color>(t.surfaceRaised),
        surfaceTintColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
        elevation: const WidgetStatePropertyAll<double>(6),
        shape: WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.control),
            side: BorderSide(color: t.border),
          ),
        ),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        textStyle: WidgetStatePropertyAll<TextStyle>(
          AppText.buttonFor().copyWith(fontSize: 13),
        ),
        backgroundColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
          if (states.contains(WidgetState.disabled)) return t.surfaceActive;
          return states.contains(WidgetState.selected) ? t.primaryGlow : t.surface;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
          if (states.contains(WidgetState.disabled)) return t.textMuted;
          return states.contains(WidgetState.selected) ? t.primary : t.textSecondary;
        }),
        side: WidgetStatePropertyAll<BorderSide>(BorderSide(color: t.border)),
        shape: WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.control)),
        ),
        elevation: const WidgetStatePropertyAll<double>(0),
        minimumSize: const WidgetStatePropertyAll<Size>(Size(0, AppSizes.control)),
        padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
          EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        ),
      ),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: t.primary,
      unselectedLabelColor: t.textSecondary,
      labelStyle: AppText.buttonFor().copyWith(fontSize: 13.5),
      unselectedLabelStyle: AppText.buttonFor().copyWith(fontSize: 13.5, fontWeight: FontWeight.w500),
      indicatorColor: t.primary,
      indicatorSize: TabBarIndicatorSize.tab,
      dividerColor: t.borderSubtle,
      overlayColor: WidgetStatePropertyAll<Color>(t.primaryGlow),
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
      headingRowColor: WidgetStatePropertyAll<Color>(t.surfaceSunken),
      headingTextStyle: AppText.tableHeaderFor(t),
      headingRowHeight: AppSizes.tableHeader,
      dataTextStyle: AppText.tableCellFor(t),
      dataRowMinHeight: AppSizes.rowCompact,
      dataRowMaxHeight: AppSizes.rowLoose,
      dividerThickness: 1,
      horizontalMargin: 12,
      columnSpacing: 20,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: t.textSecondary,
      textColor: t.textPrimary,
      selectedColor: t.primary,
      selectedTileColor: t.primaryGlow,
      minVerticalPadding: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.control)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: t.surfaceRaised,
      contentTextStyle: AppText.bodyFor(t),
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.panel),
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      hintStyle: AppText.bodyFor(t).copyWith(color: t.textMuted),
      labelStyle: AppText.formLabelFor(t),
      floatingLabelStyle: TextStyle(color: t.primary, fontSize: 12.5, fontWeight: FontWeight.w600),
      errorStyle: TextStyle(color: t.danger, fontSize: 12, height: 1.35),
      prefixIconColor: t.textMuted,
      suffixIconColor: t.textMuted,
      border: _inputBorder(t.border),
      enabledBorder: _inputBorder(t.border),
      focusedBorder: _RingOutlineInputBorder(
        borderSide: BorderSide(color: t.primary, width: 1),
        borderRadius: BorderRadius.circular(AppRadii.control),
        ringColor: t.focusRing,
      ),
      errorBorder: _inputBorder(t.dangerBorder),
      focusedErrorBorder: _RingOutlineInputBorder(
        borderSide: BorderSide(color: t.danger, width: 1),
        borderRadius: BorderRadius.circular(AppRadii.control),
        ringColor: t.dangerBg,
      ),
      disabledBorder: _inputBorder(t.borderSubtle),
    );

OutlineInputBorder _inputBorder(Color color) => OutlineInputBorder(
      borderSide: BorderSide(color: color, width: 1),
      borderRadius: BorderRadius.circular(AppRadii.control),
    );

/// Stile "rule": bordo 1px, nessuna ombra, hover con fondo tenue.
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
      EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    ),
    minimumSize: const WidgetStatePropertyAll<Size>(Size(0, AppSizes.control)),
    maximumSize: const WidgetStatePropertyAll<Size>(Size(double.infinity, AppSizes.controlLg)),
    shape: WidgetStatePropertyAll<OutlinedBorder>(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.control)),
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
      if (states.contains(WidgetState.disabled)) return Colors.transparent;
      if (states.contains(WidgetState.hovered) || states.contains(WidgetState.pressed)) return t.surfaceHover;
      return Colors.transparent;
    }),
    foregroundColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
      if (states.contains(WidgetState.disabled)) return t.textMuted;
      if (states.contains(WidgetState.hovered)) return t.primary;
      return t.textPrimary;
    }),
    overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
    side: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
      if (states.contains(WidgetState.disabled)) return BorderSide(color: t.borderSubtle);
      final bool hot = states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.focused) ||
          states.contains(WidgetState.pressed);
      return BorderSide(color: hot ? t.primary : t.border);
    }),
    elevation: const WidgetStatePropertyAll<double>(0),
    shadowColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
    surfaceTintColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
    padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
      EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    ),
    minimumSize: const WidgetStatePropertyAll<Size>(Size(0, AppSizes.control)),
    maximumSize: const WidgetStatePropertyAll<Size>(Size(double.infinity, AppSizes.controlLg)),
    shape: WidgetStatePropertyAll<OutlinedBorder>(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.control)),
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
    padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(EdgeInsets.all(6)),
    minimumSize: const WidgetStatePropertyAll<Size>(Size(32, 32)),
    maximumSize: const WidgetStatePropertyAll<Size>(Size(32, 32)),
    shape: WidgetStatePropertyAll<OutlinedBorder>(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.control)),
    ),
    animationDuration: AppMotion.fast,
    enableFeedback: false,
  );
}

TextTheme _buildTextTheme(AppTokens t) {
  return TextTheme(
    displayLarge: TextStyle(color: t.textPrimary, fontSize: 34, fontWeight: FontWeight.w700, height: 1.15, letterSpacing: -0.4),
    displayMedium: TextStyle(color: t.textPrimary, fontSize: 30, fontWeight: FontWeight.w700, height: 1.15, letterSpacing: -0.35),
    displaySmall: TextStyle(color: t.textPrimary, fontSize: 26, fontWeight: FontWeight.w700, height: 1.2, letterSpacing: -0.3),
    headlineLarge: TextStyle(color: t.textPrimary, fontSize: 22, fontWeight: FontWeight.w700, height: 1.25, letterSpacing: -0.25),
    headlineMedium: TextStyle(color: t.textPrimary, fontSize: 20, fontWeight: FontWeight.w700, height: 1.3, letterSpacing: -0.2),
    headlineSmall: TextStyle(color: t.textPrimary, fontSize: 18, fontWeight: FontWeight.w600, height: 1.3, letterSpacing: -0.15),
    titleLarge: TextStyle(color: t.textPrimary, fontSize: 17, fontWeight: FontWeight.w600, height: 1.3, letterSpacing: -0.15),
    titleMedium: TextStyle(color: t.textPrimary, fontSize: 15, fontWeight: FontWeight.w600, height: 1.35, letterSpacing: -0.1),
    titleSmall: TextStyle(color: t.textSecondary, fontSize: 13, fontWeight: FontWeight.w600, height: 1.4),
    bodyLarge: TextStyle(color: t.textPrimary, fontSize: 15, fontWeight: FontWeight.w400, height: 1.5),
    bodyMedium: TextStyle(color: t.textPrimary, fontSize: 14, fontWeight: FontWeight.w400, height: 1.5),
    bodySmall: TextStyle(color: t.textSecondary, fontSize: 12.5, fontWeight: FontWeight.w400, height: 1.45),
    labelLarge: TextStyle(color: t.textPrimary, fontSize: 13, fontWeight: FontWeight.w600, height: 1.3),
    labelMedium: TextStyle(color: t.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w600, height: 1.3, letterSpacing: 0.4),
    labelSmall: TextStyle(color: t.textSecondary, fontSize: 11, fontWeight: FontWeight.w600, height: 1.3, letterSpacing: 0.8),
  );
}

/// Stili di testo "di prodotto" del linguaggio Registro.
///
/// Gerarchia: micro-etichette MAIUSCOLE con tracking (11px), testo di corpo
/// 13–14px, titoli 15–18px, numeri in mono tabulare con il valore come
/// elemento più grande della card.
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
  /// Titolo di pagina in topbar (18px/700, 16px sotto 640).
  static TextStyle pageTitle(BuildContext context) =>
      pageTitleFor(context.tokens, compact: context.isCompact);

  /// [pageTitle] dai soli token.
  static TextStyle pageTitleFor(AppTokens t, {bool compact = false}) => TextStyle(
        color: t.textPrimary,
        fontSize: compact ? 16 : 18,
        fontWeight: FontWeight.w700,
        height: 1.25,
        letterSpacing: -0.15,
        fontFamilyFallback: AppTokens.fontFallback,
      );

  /// Numero in evidenza (display, 30px/700).
  static TextStyle display(BuildContext context) => displayFor(context.tokens);

  /// [display] dai soli token.
  static TextStyle displayFor(AppTokens t) => TextStyle(
        color: t.textPrimary,
        fontSize: 30,
        fontWeight: FontWeight.w700,
        height: 1.15,
        letterSpacing: -0.35,
        fontFamilyFallback: AppTokens.fontFallback,
      );

  /// Titolo di card/sezione (15px/650).
  static TextStyle cardTitle(BuildContext context) => cardTitleFor(context.tokens);

  /// [cardTitle] dai soli token.
  static TextStyle cardTitleFor(AppTokens t) => TextStyle(
        color: t.textPrimary,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        height: 1.35,
        letterSpacing: -0.1,
        fontFamilyFallback: AppTokens.fontFallback,
      );

  /// Etichetta micro maiuscola (11px/600, tracking 0.09em).
  static TextStyle micro(BuildContext context) => microFor(context.tokens);

  /// [micro] dai soli token.
  static TextStyle microFor(AppTokens t) => TextStyle(
        color: t.textSecondary,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        height: 1.3,
        letterSpacing: 0.9,
        fontFamilyFallback: AppTokens.fontFallback,
      );

  /// Etichetta maiuscola di sezione (alias storico di [micro]).
  static TextStyle sectionLabel(BuildContext context) => sectionLabelFor(context.tokens);

  /// [sectionLabel] dai soli token.
  static TextStyle sectionLabelFor(AppTokens t) => microFor(t);

  /// Etichetta di uno stat (11px maiuscola con tracking).
  static TextStyle statLabel(BuildContext context) =>
      statLabelFor(context.tokens, compact: context.isCompact);

  /// [statLabel] dai soli token.
  static TextStyle statLabelFor(AppTokens t, {bool compact = false}) => microFor(t).copyWith(
        fontSize: compact ? 10.5 : 11,
        color: t.textMuted,
      );

  /// Valore numerico di uno stat (mono tabular, 26 → 22 → 19).
  static TextStyle statValue(BuildContext context) =>
      statValueFor(context.tokens, compact: context.isCompact, tiny: context.isTiny);

  /// [statValue] dai soli token.
  static TextStyle statValueFor(AppTokens t, {bool compact = false, bool tiny = false}) {
    final double size = tiny ? 19 : (compact ? 22 : 26);
    return TextStyle(
      color: t.textPrimary,
      fontSize: size,
      fontWeight: FontWeight.w600,
      height: 1.15,
      letterSpacing: size * -0.015,
      fontFamily: AppTokens.monoFontFamily,
      fontFamilyFallback: AppTokens.monoFontFallback,
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );
  }

  /// Variante ridotta del valore stat (19px).
  static TextStyle statValueSm(BuildContext context) =>
      statValueSmFor(context.tokens, compact: context.isCompact);

  /// [statValueSm] dai soli token.
  static TextStyle statValueSmFor(AppTokens t, {bool compact = false}) => TextStyle(
        color: t.textPrimary,
        fontSize: compact ? 17 : 19,
        fontWeight: FontWeight.w600,
        height: 1.2,
        letterSpacing: -0.15,
        fontFamily: AppTokens.monoFontFamily,
        fontFamilyFallback: AppTokens.monoFontFallback,
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      );

  /// Descrizione sotto il valore di uno stat (12px muted).
  static TextStyle statDesc(BuildContext context) =>
      statDescFor(context.tokens, compact: context.isCompact);

  /// [statDesc] dai soli token.
  static TextStyle statDescFor(AppTokens t, {bool compact = false}) => TextStyle(
        color: t.textMuted,
        fontSize: compact ? 11 : 12,
        fontWeight: FontWeight.w400,
        height: 1.4,
        fontFamilyFallback: AppTokens.fontFallback,
      );

  /// Variazione numerica (mono tabulare, 13px/600).
  static TextStyle delta(BuildContext context) => deltaFor(context.tokens);

  /// [delta] dai soli token.
  static TextStyle deltaFor(AppTokens t) => TextStyle(
        color: t.textPrimary,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        height: 1.25,
        fontFamily: AppTokens.monoFontFamily,
        fontFamilyFallback: AppTokens.monoFontFallback,
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
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

  /// Testo compatto (13px).
  static TextStyle small(BuildContext context) => smallFor(context.tokens);

  /// [small] dai soli token.
  static TextStyle smallFor(AppTokens t) => TextStyle(
        color: t.textPrimary,
        fontSize: 13,
        fontWeight: FontWeight.w400,
        height: 1.5,
        fontFamilyFallback: AppTokens.fontFallback,
      );

  /// Testo minuto/attenuato (12px muted).
  static TextStyle caption(BuildContext context) => captionFor(context.tokens);

  /// [caption] dai soli token.
  static TextStyle captionFor(AppTokens t) => TextStyle(
        color: t.textMuted,
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.45,
        fontFamilyFallback: AppTokens.fontFallback,
      );

  /// Etichetta di form (12.5px/600 secondary).
  static TextStyle formLabel(BuildContext context) => formLabelFor(context.tokens);

  /// [formLabel] dai soli token.
  static TextStyle formLabelFor(AppTokens t) => TextStyle(
        color: t.textSecondary,
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        height: 1.3,
        fontFamilyFallback: AppTokens.fontFallback,
      );

  /// Intestazione di tabella (11px/600 maiuscola con tracking).
  static TextStyle tableHeader(BuildContext context) => tableHeaderFor(context.tokens);

  /// [tableHeader] dai soli token.
  static TextStyle tableHeaderFor(AppTokens t) => microFor(t);

  /// Cella di tabella (13px).
  static TextStyle tableCell(BuildContext context) => tableCellFor(context.tokens);

  /// [tableCell] dai soli token.
  static TextStyle tableCellFor(AppTokens t) => TextStyle(
        color: t.textPrimary,
        fontSize: 13,
        fontWeight: FontWeight.w400,
        height: 1.4,
        fontFamilyFallback: AppTokens.fontFallback,
      );

  /// Cella numerica di tabella (mono tabulare).
  static TextStyle tableCellNum(BuildContext context) =>
      tableCellFor(context.tokens).copyWith(
        fontFamily: AppTokens.monoFontFamily,
        fontFamilyFallback: AppTokens.monoFontFallback,
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
        fontWeight: FontWeight.w500,
      );

  /// Titolo di modale (17px/700).
  static TextStyle modalTitle(BuildContext context) => modalTitleFor(context.tokens);

  /// [modalTitle] dai soli token.
  static TextStyle modalTitleFor(AppTokens t) => TextStyle(
        color: t.textPrimary,
        fontSize: 17,
        fontWeight: FontWeight.w700,
        height: 1.3,
        letterSpacing: -0.15,
        fontFamilyFallback: AppTokens.fontFallback,
      );

  /// Etichetta di bottone (13px/600).
  static TextStyle button(BuildContext context) => buttonFor();

  /// [button] dai soli token (il colore lo decide il ButtonStyle).
  static TextStyle buttonFor() => const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        height: 1.25,
        letterSpacing: 0.1,
        fontFamilyFallback: AppTokens.fontFallback,
      );

  /// Link testuale (accento/600).
  static TextStyle link(BuildContext context) =>
      buttonFor().copyWith(color: context.tokens.primary);

  /// Voce di navigazione della sidebar (13.5px).
  static TextStyle navLabel(BuildContext context, {bool active = false}) {
    final AppTokens t = context.tokens;
    return TextStyle(
      color: active ? t.primary : t.textSecondary,
      fontSize: 13.5,
      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
      height: 1.3,
      fontFamilyFallback: AppTokens.fontFallback,
    );
  }

  /// Titolo del logo in sidebar (15px/700).
  static TextStyle appTitle(BuildContext context) {
    final AppTokens t = context.tokens;
    return TextStyle(
      color: t.textPrimary,
      fontSize: 15,
      fontWeight: FontWeight.w700,
      height: 1.3,
      letterSpacing: 0.4,
      fontFamilyFallback: AppTokens.fontFallback,
    );
  }

  /// Testo di un toast (13px/500).
  static TextStyle toast(BuildContext context) {
    final AppTokens t = context.tokens;
    return TextStyle(
      color: t.textPrimary,
      fontSize: 13,
      fontWeight: FontWeight.w500,
      height: 1.45,
      fontFamilyFallback: AppTokens.fontFallback,
    );
  }

  /// Titolo della login (24px/700).
  static TextStyle loginTitle(BuildContext context) {
    final AppTokens t = context.tokens;
    return TextStyle(
      color: t.textPrimary,
      fontSize: 24,
      fontWeight: FontWeight.w700,
      height: 1.25,
      letterSpacing: -0.3,
      fontFamilyFallback: AppTokens.fontFallback,
    );
  }

  /// Sottotitolo della login (14px secondary).
  static TextStyle loginSubtitle(BuildContext context) {
    final AppTokens t = context.tokens;
    return TextStyle(
      color: t.textSecondary,
      fontSize: 14,
      fontWeight: FontWeight.w400,
      height: 1.5,
      fontFamilyFallback: AppTokens.fontFallback,
    );
  }

  /// Nota di sicurezza sotto la login (11.5px muted).
  static TextStyle securityBadge(BuildContext context) {
    final AppTokens t = context.tokens;
    return TextStyle(
      color: t.textMuted,
      fontSize: 11.5,
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
      height: 1.35,
      fontFamily: AppTokens.monoFontFamily,
      fontFamilyFallback: AppTokens.monoFontFallback,
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );
  }
}

/// [OutlineInputBorder] con anello di focus visibile (2px attorno al bordo).
class _RingOutlineInputBorder extends OutlineInputBorder {
  const _RingOutlineInputBorder({
    super.borderSide,
    super.borderRadius,
    super.gapPadding,
    required this.ringColor,
  });

  /// Colore dell'anello (`focusRing`).
  final Color ringColor;

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    double? gapStart,
    double gapExtent = 0.0,
    double gapPercentage = 0.0,
    TextDirection? textDirection,
  }) {
    // Anello pieno di 3px attorno al bordo (2px visibili + 1px di raccordo).
    final RRect rrect = borderRadius.resolve(textDirection).toRRect(rect).inflate(2);
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = ringColor,
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
  _RingOutlineInputBorder copyWith({
    BorderSide? borderSide,
    BorderRadius? borderRadius,
    double? gapPadding,
  }) {
    return _RingOutlineInputBorder(
      borderSide: borderSide ?? this.borderSide,
      borderRadius: borderRadius ?? this.borderRadius,
      gapPadding: gapPadding ?? this.gapPadding,
      ringColor: ringColor,
    );
  }

  @override
  _RingOutlineInputBorder scale(double t) {
    return _RingOutlineInputBorder(
      borderSide: borderSide.scale(t),
      borderRadius: borderRadius * t,
      gapPadding: gapPadding * t,
      ringColor: ringColor,
    );
  }
}
