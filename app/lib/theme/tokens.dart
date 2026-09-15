import 'package:flutter/material.dart';

/// Palette per i grafici (light/dark).
///
/// Regole di linguaggio ("Registro"):
/// - il verde/rosso semantico descrive solo guadagno/perdita, mai la marca;
/// - le candele rialziste sono **vuote** (solo contorno) e le ribassiste
///   **piene**: la direzione resta leggibile anche senza colore (deuteranopia);
/// - i benchmark usano tratteggio e tinte distinte dalla serie principale;
/// - la donut alterna famiglie di tinta e livelli di luminosità per restare
///   distinguibile in scala di grigi.
@immutable
class AppChartPalette {
  /// Crea una palette grafici.
  const AppChartPalette({
    required this.text,
    required this.grid,
    required this.line,
    required this.top,
    required this.bottom,
    required this.up,
    required this.down,
    required this.neutral,
    required this.volume,
    required this.volumeUp,
    required this.volumeDown,
    required this.benchmarkSp,
    required this.benchmarkMib,
    required this.breakeven,
    required this.candleUpFill,
    required this.candleUpStroke,
    required this.candleDownFill,
    required this.candleDownStroke,
    required this.crosshair,
    required this.pie,
  });

  /// Testo di assi e legende.
  final Color text;

  /// Linee della griglia.
  final Color grid;

  /// Linea serie principale (area/linea).
  final Color line;

  /// Riempimento alto del gradiente area.
  final Color top;

  /// Riempimento basso del gradiente area.
  final Color bottom;

  /// Candela rialzista / variazione positiva.
  final Color up;

  /// Candela ribassista / variazione negativa.
  final Color down;

  /// Valore neutro (flat, zero, serie senza segno).
  final Color neutral;

  /// Volume neutro.
  final Color volume;

  /// Volume su candela rialzista.
  final Color volumeUp;

  /// Volume su candela ribassista.
  final Color volumeDown;

  /// Benchmark S&P 500 (linea tratteggiata).
  final Color benchmarkSp;

  /// Benchmark FTSE MIB (linea tratteggiata).
  final Color benchmarkMib;

  /// Linea prezzo medio di carico (tratteggiata).
  final Color breakeven;

  /// Corpo delle candele rialziste: tinta della superficie (candela vuota).
  final Color candleUpFill;

  /// Contorno delle candele rialziste.
  final Color candleUpStroke;

  /// Corpo delle candele ribassiste (candela piena).
  final Color candleDownFill;

  /// Contorno delle candele ribassiste.
  final Color candleDownStroke;

  /// Mirino/tooltip verticale sui grafici interattivi.
  final Color crosshair;

  /// Palette della donut di allocazione (9 colori, ordine stabile).
  final List<Color> pie;

  /// Interpolazione tra due palette (transizione tema).
  AppChartPalette lerp(AppChartPalette? other, double t) {
    if (other == null) return this;
    return AppChartPalette(
      text: Color.lerp(text, other.text, t)!,
      grid: Color.lerp(grid, other.grid, t)!,
      line: Color.lerp(line, other.line, t)!,
      top: Color.lerp(top, other.top, t)!,
      bottom: Color.lerp(bottom, other.bottom, t)!,
      up: Color.lerp(up, other.up, t)!,
      down: Color.lerp(down, other.down, t)!,
      neutral: Color.lerp(neutral, other.neutral, t)!,
      volume: Color.lerp(volume, other.volume, t)!,
      volumeUp: Color.lerp(volumeUp, other.volumeUp, t)!,
      volumeDown: Color.lerp(volumeDown, other.volumeDown, t)!,
      benchmarkSp: Color.lerp(benchmarkSp, other.benchmarkSp, t)!,
      benchmarkMib: Color.lerp(benchmarkMib, other.benchmarkMib, t)!,
      breakeven: Color.lerp(breakeven, other.breakeven, t)!,
      candleUpFill: Color.lerp(candleUpFill, other.candleUpFill, t)!,
      candleUpStroke: Color.lerp(candleUpStroke, other.candleUpStroke, t)!,
      candleDownFill: Color.lerp(candleDownFill, other.candleDownFill, t)!,
      candleDownStroke: Color.lerp(candleDownStroke, other.candleDownStroke, t)!,
      crosshair: Color.lerp(crosshair, other.crosshair, t)!,
      pie: <Color>[
        for (var i = 0; i < pie.length; i++)
          Color.lerp(pie[i], other.pie[i % other.pie.length], t)!,
      ],
    );
  }
}

/// Design token dell'app per il linguaggio "Registro".
///
/// È una [ThemeExtension]: le istanze pubbliche sono [AppTokens.light]
/// ("carta": pagina calda, superfici bianche, inchiostro) e [AppTokens.dark]
/// ("carbone": nero caldo, testo carta). Nei widget si accede con
/// `context.tokens`.
///
/// I valori che non dipendono dal tema (raggi, spaziature, misure, breakpoint)
/// vivono in [AppRadii], [AppSpacing], [AppSizes] e [AppBreakpoints].
///
/// Regole di linguaggio:
/// - i bordi da 1px ("rule") definiscono la struttura, le ombre solo i livelli
///   flottanti (menu, dialoghi, toast, palette);
/// - l'accento (`primary`, indaco-inchiostro) è riservato all'interazione; il
///   verde/rosso semantico solo ai dati di guadagno/perdita;
/// - nessun testo muted su `surfaceActive`: per quegli sfondi usare
///   `textSecondary` (contrasto AA verificato).
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  /// Crea un set di token completo.
  const AppTokens({
    required this.brightness,
    required this.bg,
    required this.bgSecondary,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceSunken,
    required this.surfaceHover,
    required this.surfaceActive,
    required this.surfaceInverse,
    required this.border,
    required this.borderSubtle,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textFaint,
    required this.textInverse,
    required this.primary,
    required this.primarySolid,
    required this.primarySolidHover,
    required this.primaryGlow,
    required this.cyan,
    required this.success,
    required this.successText,
    required this.successBg,
    required this.successBorder,
    required this.danger,
    required this.dangerBg,
    required this.dangerBorder,
    required this.warning,
    required this.warningBg,
    required this.warningBorder,
    required this.purple,
    required this.purpleBg,
    required this.track,
    required this.selection,
    required this.focusRing,
    required this.scrim,
    required this.onPrimarySolid,
    required this.onSuccessSolid,
    required this.onWarningSolid,
    required this.onDangerSolid,
    required this.shadowSm,
    required this.shadowMd,
    required this.shadowLg,
    required this.chart,
  });

  /// Chiaro o scuro: utile per scelte che non passano da `Theme.of`.
  final Brightness brightness;

  // --- Superfici e bordi -------------------------------------------------
  /// Sfondo pagina.
  final Color bg;

  /// Sfondo secondario (footer, zone di appoggio).
  final Color bgSecondary;

  /// Superficie dei pannelli (card, sidebar, topbar, input).
  final Color surface;

  /// Superficie flottante (menu, palette, dialoghi sopra `surface`).
  final Color surfaceRaised;

  /// Superficie incassata (well, testata tabella, blocchi interni).
  final Color surfaceSunken;

  /// Superficie hover di righe e controlli.
  final Color surfaceHover;

  /// Superficie attiva/selezionata e stato disabilitato.
  final Color surfaceActive;

  /// Superficie invertita (tooltip, chip scuri).
  final Color surfaceInverse;

  /// Bordo standard da 1px ("rule").
  final Color border;

  /// Bordo tenue per separatori interni.
  final Color borderSubtle;

  /// Bordo marcato per hover e scrollbar.
  final Color borderStrong;

  // --- Testo -------------------------------------------------------------
  /// Testo principale (inchiostro).
  final Color textPrimary;

  /// Testo secondario.
  final Color textSecondary;

  /// Testo attenuato, descrizioni e placeholder (AA su `bg`/`surface`).
  final Color textMuted;

  /// Testo debole: solo decorativo, disabilitato o placeholder grandi.
  final Color textFaint;

  /// Testo su `surfaceInverse`.
  final Color textInverse;

  // --- Accenti -----------------------------------------------------------
  /// Accento di interazione: link, nav attiva, focus, outline input.
  final Color primary;

  /// Fondo pieno dei bottoni primari.
  final Color primarySolid;

  /// Fondo pieno in hover (più profondo).
  final Color primarySolidHover;

  /// Alone tenue dell'accento (badge, selezione riga, stati attivi).
  final Color primaryGlow;

  /// Ciano informativo (mercati non italiani, dati ausiliari).
  final Color cyan;

  /// Verde di guadagno, usato anche dai grafici.
  final Color success;

  /// Verde per testo profit.
  final Color successText;

  /// Sfondo tenue di guadagno.
  final Color successBg;

  /// Bordo tenue di guadagno.
  final Color successBorder;

  /// Rosso di perdita/errore.
  final Color danger;

  /// Sfondo tenue di perdita.
  final Color dangerBg;

  /// Bordo tenue di perdita.
  final Color dangerBorder;

  /// Ambra di warning.
  final Color warning;

  /// Sfondo tenue di warning.
  final Color warningBg;

  /// Bordo tenue di warning.
  final Color warningBorder;

  /// Viola per badge admin e serie ausiliarie.
  final Color purple;

  /// Sfondo tenue viola.
  final Color purpleBg;

  // --- Stati funzionali --------------------------------------------------
  /// Track di progress bar e skeleton.
  final Color track;

  /// Selezione del testo.
  final Color selection;

  /// Anello di focus visibile (2px) per tastiera.
  final Color focusRing;

  /// Velo di overlay di modali e drawer.
  final Color scrim;

  /// Testo su superficie primary piena.
  final Color onPrimarySolid;

  /// Testo su superficie success piena.
  final Color onSuccessSolid;

  /// Testo su superficie warning piena.
  final Color onWarningSolid;

  /// Testo su superficie danger piena.
  final Color onDangerSolid;

  // --- Ombre -------------------------------------------------------------
  /// Ombra minima: pannelli sollevati (menu ancorati, card evidenziate).
  final List<BoxShadow> shadowSm;

  /// Ombra media: popover, toast, bottom sheet.
  final List<BoxShadow> shadowMd;

  /// Ombra ampia: dialoghi e palette.
  final List<BoxShadow> shadowLg;

  /// Palette dei grafici.
  final AppChartPalette chart;

  // --- Dimensioni shell (uguali nei due temi) ---------------------------
  /// Larghezza sidebar desktop.
  static const double sidebarWidth = 248;

  /// Larghezza sidebar desktop compressa.
  static const double sidebarCollapsedWidth = 64;

  /// Larghezza drawer mobile.
  static const double sidebarMobileWidth = 268;

  /// Altezza topbar desktop.
  static const double topbarHeight = 64;

  /// Altezza topbar mobile (≤640px).
  static const double topbarHeightMobile = 56;

  /// Larghezza massima del contenuto pagina.
  static const double contentMaxWidth = 1440;

  /// Famiglia di fallback sans di sistema: nessun font bundlato.
  static const List<String> fontFallback = <String>[
    '-apple-system',
    'BlinkMacSystemFont',
    'Segoe UI Variable Text',
    'Segoe UI',
    'Roboto',
    'Noto Sans',
    'Cantarell',
    'Liberation Sans',
    'Helvetica Neue',
    'Arial',
    'sans-serif',
  ];

  /// Famiglia mono di sistema per i numeri tabulari.
  static const String monoFontFamily = 'monospace';

  /// Fallback mono di sistema.
  static const List<String> monoFontFallback = <String>[
    'ui-monospace',
    'SFMono-Regular',
    'JetBrains Mono',
    'Menlo',
    'Consolas',
    'Roboto Mono',
    'Liberation Mono',
    'DejaVu Sans Mono',
    'monospace',
  ];

  /// Tema chiaro "carta" (default).
  static const AppTokens light = AppTokens(
    brightness: Brightness.light,
    bg: Color(0xFFF4F1EA),
    bgSecondary: Color(0xFFEDEAE1),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFFFFFFF),
    surfaceSunken: Color(0xFFF7F5F0),
    surfaceHover: Color(0xFFF4F1EA),
    surfaceActive: Color(0xFFEDE9DE),
    surfaceInverse: Color(0xFF1A1814),
    border: Color(0xFFDFDACD),
    borderSubtle: Color(0xFFEAE6DC),
    borderStrong: Color(0xFFC6C0AF),
    textPrimary: Color(0xFF1A1814),
    textSecondary: Color(0xFF514D45),
    textMuted: Color(0xFF67635A),
    textFaint: Color(0xFF8A857A),
    textInverse: Color(0xFFF7F5F0),
    primary: Color(0xFF2B3F9E),
    primarySolid: Color(0xFF2B3F9E),
    primarySolidHover: Color(0xFF21327F),
    primaryGlow: Color.fromRGBO(43, 63, 158, 0.12),
    cyan: Color(0xFF0F6D82),
    success: Color(0xFF0E6B4F),
    successText: Color(0xFF0B5C43),
    successBg: Color.fromRGBO(14, 107, 79, 0.09),
    successBorder: Color.fromRGBO(14, 107, 79, 0.28),
    danger: Color(0xFFA62B1F),
    dangerBg: Color.fromRGBO(166, 43, 31, 0.08),
    dangerBorder: Color.fromRGBO(166, 43, 31, 0.26),
    warning: Color(0xFF8A5300),
    warningBg: Color.fromRGBO(138, 83, 0, 0.09),
    warningBorder: Color.fromRGBO(138, 83, 0, 0.28),
    purple: Color(0xFF5B21B6),
    purpleBg: Color.fromRGBO(91, 33, 182, 0.09),
    track: Color(0xFFE4DFD2),
    selection: Color.fromRGBO(43, 63, 158, 0.16),
    focusRing: Color.fromRGBO(43, 63, 158, 0.45),
    scrim: Color.fromRGBO(26, 24, 20, 0.48),
    onPrimarySolid: Color(0xFFFFFFFF),
    onSuccessSolid: Color(0xFFFFFFFF),
    onWarningSolid: Color(0xFFFFFFFF),
    onDangerSolid: Color(0xFFFFFFFF),
    shadowSm: <BoxShadow>[
      BoxShadow(color: Color.fromRGBO(26, 24, 20, 0.06), offset: Offset(0, 1), blurRadius: 2),
    ],
    shadowMd: <BoxShadow>[
      BoxShadow(
        color: Color.fromRGBO(26, 24, 20, 0.10),
        offset: Offset(0, 6),
        blurRadius: 18,
        spreadRadius: -4,
      ),
    ],
    shadowLg: <BoxShadow>[
      BoxShadow(
        color: Color.fromRGBO(26, 24, 20, 0.18),
        offset: Offset(0, 18),
        blurRadius: 48,
        spreadRadius: -12,
      ),
    ],
    chart: AppChartPalette(
      text: Color(0xFF67635A),
      grid: Color.fromRGBO(26, 24, 20, 0.08),
      line: Color(0xFF2B3F9E),
      top: Color.fromRGBO(43, 63, 158, 0.20),
      bottom: Color.fromRGBO(43, 63, 158, 0.02),
      up: Color(0xFF0E6B4F),
      down: Color(0xFFA62B1F),
      neutral: Color(0xFF8A857A),
      volume: Color.fromRGBO(103, 99, 90, 0.28),
      volumeUp: Color.fromRGBO(14, 107, 79, 0.30),
      volumeDown: Color.fromRGBO(166, 43, 31, 0.28),
      benchmarkSp: Color(0xFF0E6C9E),
      benchmarkMib: Color(0xFF8A5300),
      breakeven: Color(0xFFB45309),
      candleUpFill: Color(0xFFFFFFFF),
      candleUpStroke: Color(0xFF0E6B4F),
      candleDownFill: Color(0xFFA62B1F),
      candleDownStroke: Color(0xFFA62B1F),
      crosshair: Color.fromRGBO(43, 63, 158, 0.45),
      pie: <Color>[
        Color(0xFF2B3F9E),
        Color(0xFF0E6B4F),
        Color(0xFFA62B1F),
        Color(0xFF8A5300),
        Color(0xFF5B21B6),
        Color(0xFF0F6D82),
        Color(0xFFA21D5E),
        Color(0xFF4D7C0F),
        Color(0xFF6B7280),
      ],
    ),
  );

  /// Tema scuro "carbone".
  static const AppTokens dark = AppTokens(
    brightness: Brightness.dark,
    bg: Color(0xFF131211),
    bgSecondary: Color(0xFF171614),
    surface: Color(0xFF1B1A17),
    surfaceRaised: Color(0xFF232220),
    surfaceSunken: Color(0xFF151412),
    surfaceHover: Color(0xFF242220),
    surfaceActive: Color(0xFF2D2B27),
    surfaceInverse: Color(0xFFEFECE5),
    border: Color(0xFF332F29),
    borderSubtle: Color(0xFF262420),
    borderStrong: Color(0xFF4C483F),
    textPrimary: Color(0xFFEFECE5),
    textSecondary: Color(0xFFB6B0A2),
    textMuted: Color(0xFF9A9487),
    textFaint: Color(0xFF6E6960),
    textInverse: Color(0xFF131211),
    primary: Color(0xFFA3B6FF),
    primarySolid: Color(0xFF3D55C8),
    primarySolidHover: Color(0xFF4A63D8),
    primaryGlow: Color.fromRGBO(163, 182, 255, 0.14),
    cyan: Color(0xFF4FD3E8),
    success: Color(0xFF5ACF9B),
    successText: Color(0xFF6FD7A8),
    successBg: Color.fromRGBO(90, 207, 155, 0.12),
    successBorder: Color.fromRGBO(90, 207, 155, 0.30),
    danger: Color(0xFFF08B7E),
    dangerBg: Color.fromRGBO(240, 139, 126, 0.12),
    dangerBorder: Color.fromRGBO(240, 139, 126, 0.30),
    warning: Color(0xFFE4B15C),
    warningBg: Color.fromRGBO(228, 177, 92, 0.12),
    warningBorder: Color.fromRGBO(228, 177, 92, 0.30),
    purple: Color(0xFFB79BFF),
    purpleBg: Color.fromRGBO(183, 155, 255, 0.12),
    track: Color(0xFF35322B),
    selection: Color.fromRGBO(163, 182, 255, 0.20),
    focusRing: Color.fromRGBO(163, 182, 255, 0.50),
    scrim: Color.fromRGBO(0, 0, 0, 0.64),
    onPrimarySolid: Color(0xFFF2F3FF),
    onSuccessSolid: Color(0xFF0B1F16),
    onWarningSolid: Color(0xFF241A03),
    onDangerSolid: Color(0xFF2A0A07),
    shadowSm: <BoxShadow>[
      BoxShadow(color: Color.fromRGBO(0, 0, 0, 0.32), offset: Offset(0, 1), blurRadius: 2),
    ],
    shadowMd: <BoxShadow>[
      BoxShadow(
        color: Color.fromRGBO(0, 0, 0, 0.44),
        offset: Offset(0, 6),
        blurRadius: 18,
        spreadRadius: -4,
      ),
    ],
    shadowLg: <BoxShadow>[
      BoxShadow(
        color: Color.fromRGBO(0, 0, 0, 0.58),
        offset: Offset(0, 18),
        blurRadius: 48,
        spreadRadius: -12,
      ),
    ],
    chart: AppChartPalette(
      text: Color(0xFF9A9487),
      grid: Color.fromRGBO(239, 236, 229, 0.08),
      line: Color(0xFFA3B6FF),
      top: Color.fromRGBO(163, 182, 255, 0.20),
      bottom: Color.fromRGBO(163, 182, 255, 0.02),
      up: Color(0xFF5ACF9B),
      down: Color(0xFFF08B7E),
      neutral: Color(0xFF6E6960),
      volume: Color.fromRGBO(154, 148, 135, 0.26),
      volumeUp: Color.fromRGBO(90, 207, 155, 0.30),
      volumeDown: Color.fromRGBO(240, 139, 126, 0.28),
      benchmarkSp: Color(0xFF6FC3E8),
      benchmarkMib: Color(0xFFE4B15C),
      breakeven: Color(0xFFE8B45C),
      candleUpFill: Color(0xFF1B1A17),
      candleUpStroke: Color(0xFF5ACF9B),
      candleDownFill: Color(0xFFF08B7E),
      candleDownStroke: Color(0xFFF08B7E),
      crosshair: Color.fromRGBO(163, 182, 255, 0.45),
      pie: <Color>[
        Color(0xFFA3B6FF),
        Color(0xFF5ACF9B),
        Color(0xFFF08B7E),
        Color(0xFFE4B15C),
        Color(0xFFB79BFF),
        Color(0xFF4FD3E8),
        Color(0xFFF584B6),
        Color(0xFFA3C46B),
        Color(0xFF98A0AE),
      ],
    ),
  );

  /// True nel tema scuro.
  bool get isDark => brightness == Brightness.dark;

  // --- Helper semantici (guadagno/perdita) -------------------------------

  /// Testo di una variazione: verde se positiva, rosso se negativa, muted a 0.
  Color deltaText(double? change) {
    if (change == null || change == 0) return textMuted;
    return change > 0 ? successText : danger;
  }

  /// Fondo tenue di una variazione (badge, pill, tile).
  Color deltaSurface(double? change) {
    if (change == null || change == 0) return surfaceHover;
    return change > 0 ? successBg : dangerBg;
  }

  /// Bordo tenue di una variazione.
  Color deltaBorder(double? change) {
    if (change == null || change == 0) return border;
    return change > 0 ? successBorder : dangerBorder;
  }

  // --- Heatmap ------------------------------------------------------------

  /// Sfondo di una tile heatmap in base alla variazione percentuale.
  ///
  /// Cinque livelli: neutro a 0/null, poi |Δ| <1,5%, <3%, <5% e ≥5%.
  Color heatmapTileBackground(double? changePercent) {
    final Color base = _heatmapBase(changePercent);
    if (base == surface) return surfaceSunken;
    return base.withValues(alpha: _heatmapAlpha(changePercent, background: true));
  }

  /// Bordo di una tile heatmap, coerente con [heatmapTileBackground].
  Color heatmapTileBorder(double? changePercent) {
    final Color base = _heatmapBase(changePercent);
    if (base == surface) return border;
    return base.withValues(alpha: _heatmapAlpha(changePercent, background: false));
  }

  /// Testo leggibile sopra [heatmapTileBackground] (contrasto AA verificato).
  Color heatmapTileForeground(double? changePercent) {
    final Color background = Color.alphaBlend(
      _heatmapBase(changePercent) == surface
          ? surfaceSunken
          : _heatmapBase(changePercent)
              .withValues(alpha: _heatmapAlpha(changePercent, background: true)),
      surface,
    );
    // Sceglie il polo con contrasto migliore: inchiostro o carta/inverso.
    final Color dark = isDark ? surfaceInverse : textPrimary;
    final Color light = isDark ? textPrimary : surfaceInverse;
    return _contrast(background, dark) >= _contrast(background, light) ? dark : light;
  }

  Color _heatmapBase(double? changePercent) {
    if (changePercent == null || changePercent == 0) return surface;
    return changePercent > 0 ? success : danger;
  }

  double _heatmapAlpha(double? changePercent, {required bool background}) {
    final double magnitude = changePercent?.abs() ?? 0;
    if (background) {
      if (magnitude >= 5) return isDark ? 0.34 : 0.28;
      if (magnitude >= 3) return isDark ? 0.26 : 0.20;
      if (magnitude >= 1.5) return isDark ? 0.18 : 0.14;
      return isDark ? 0.11 : 0.09;
    }
    if (magnitude >= 5) return isDark ? 0.62 : 0.56;
    if (magnitude >= 3) return isDark ? 0.50 : 0.44;
    if (magnitude >= 1.5) return isDark ? 0.38 : 0.32;
    return isDark ? 0.26 : 0.22;
  }

  /// Rapporto di contrasto WCAG tra due colori opachi.
  static double _contrast(Color a, Color b) {
    final double la = a.computeLuminance();
    final double lb = b.computeLuminance();
    final double hi = la > lb ? la : lb;
    final double lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  @override
  AppTokens copyWith({
    Brightness? brightness,
    Color? bg,
    Color? bgSecondary,
    Color? surface,
    Color? surfaceRaised,
    Color? surfaceSunken,
    Color? surfaceHover,
    Color? surfaceActive,
    Color? surfaceInverse,
    Color? border,
    Color? borderSubtle,
    Color? borderStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? textFaint,
    Color? textInverse,
    Color? primary,
    Color? primarySolid,
    Color? primarySolidHover,
    Color? primaryGlow,
    Color? cyan,
    Color? success,
    Color? successText,
    Color? successBg,
    Color? successBorder,
    Color? danger,
    Color? dangerBg,
    Color? dangerBorder,
    Color? warning,
    Color? warningBg,
    Color? warningBorder,
    Color? purple,
    Color? purpleBg,
    Color? track,
    Color? selection,
    Color? focusRing,
    Color? scrim,
    Color? onPrimarySolid,
    Color? onSuccessSolid,
    Color? onWarningSolid,
    Color? onDangerSolid,
    List<BoxShadow>? shadowSm,
    List<BoxShadow>? shadowMd,
    List<BoxShadow>? shadowLg,
    AppChartPalette? chart,
  }) {
    return AppTokens(
      brightness: brightness ?? this.brightness,
      bg: bg ?? this.bg,
      bgSecondary: bgSecondary ?? this.bgSecondary,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      surfaceSunken: surfaceSunken ?? this.surfaceSunken,
      surfaceHover: surfaceHover ?? this.surfaceHover,
      surfaceActive: surfaceActive ?? this.surfaceActive,
      surfaceInverse: surfaceInverse ?? this.surfaceInverse,
      border: border ?? this.border,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      borderStrong: borderStrong ?? this.borderStrong,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      textFaint: textFaint ?? this.textFaint,
      textInverse: textInverse ?? this.textInverse,
      primary: primary ?? this.primary,
      primarySolid: primarySolid ?? this.primarySolid,
      primarySolidHover: primarySolidHover ?? this.primarySolidHover,
      primaryGlow: primaryGlow ?? this.primaryGlow,
      cyan: cyan ?? this.cyan,
      success: success ?? this.success,
      successText: successText ?? this.successText,
      successBg: successBg ?? this.successBg,
      successBorder: successBorder ?? this.successBorder,
      danger: danger ?? this.danger,
      dangerBg: dangerBg ?? this.dangerBg,
      dangerBorder: dangerBorder ?? this.dangerBorder,
      warning: warning ?? this.warning,
      warningBg: warningBg ?? this.warningBg,
      warningBorder: warningBorder ?? this.warningBorder,
      purple: purple ?? this.purple,
      purpleBg: purpleBg ?? this.purpleBg,
      track: track ?? this.track,
      selection: selection ?? this.selection,
      focusRing: focusRing ?? this.focusRing,
      scrim: scrim ?? this.scrim,
      onPrimarySolid: onPrimarySolid ?? this.onPrimarySolid,
      onSuccessSolid: onSuccessSolid ?? this.onSuccessSolid,
      onWarningSolid: onWarningSolid ?? this.onWarningSolid,
      onDangerSolid: onDangerSolid ?? this.onDangerSolid,
      shadowSm: shadowSm ?? this.shadowSm,
      shadowMd: shadowMd ?? this.shadowMd,
      shadowLg: shadowLg ?? this.shadowLg,
      chart: chart ?? this.chart,
    );
  }

  @override
  AppTokens lerp(covariant AppTokens? other, double t) {
    if (other == null) return this;
    return AppTokens(
      brightness: t < 0.5 ? brightness : other.brightness,
      bg: Color.lerp(bg, other.bg, t)!,
      bgSecondary: Color.lerp(bgSecondary, other.bgSecondary, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      surfaceSunken: Color.lerp(surfaceSunken, other.surfaceSunken, t)!,
      surfaceHover: Color.lerp(surfaceHover, other.surfaceHover, t)!,
      surfaceActive: Color.lerp(surfaceActive, other.surfaceActive, t)!,
      surfaceInverse: Color.lerp(surfaceInverse, other.surfaceInverse, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textFaint: Color.lerp(textFaint, other.textFaint, t)!,
      textInverse: Color.lerp(textInverse, other.textInverse, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primarySolid: Color.lerp(primarySolid, other.primarySolid, t)!,
      primarySolidHover: Color.lerp(primarySolidHover, other.primarySolidHover, t)!,
      primaryGlow: Color.lerp(primaryGlow, other.primaryGlow, t)!,
      cyan: Color.lerp(cyan, other.cyan, t)!,
      success: Color.lerp(success, other.success, t)!,
      successText: Color.lerp(successText, other.successText, t)!,
      successBg: Color.lerp(successBg, other.successBg, t)!,
      successBorder: Color.lerp(successBorder, other.successBorder, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerBg: Color.lerp(dangerBg, other.dangerBg, t)!,
      dangerBorder: Color.lerp(dangerBorder, other.dangerBorder, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningBg: Color.lerp(warningBg, other.warningBg, t)!,
      warningBorder: Color.lerp(warningBorder, other.warningBorder, t)!,
      purple: Color.lerp(purple, other.purple, t)!,
      purpleBg: Color.lerp(purpleBg, other.purpleBg, t)!,
      track: Color.lerp(track, other.track, t)!,
      selection: Color.lerp(selection, other.selection, t)!,
      focusRing: Color.lerp(focusRing, other.focusRing, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
      onPrimarySolid: Color.lerp(onPrimarySolid, other.onPrimarySolid, t)!,
      onSuccessSolid: Color.lerp(onSuccessSolid, other.onSuccessSolid, t)!,
      onWarningSolid: Color.lerp(onWarningSolid, other.onWarningSolid, t)!,
      onDangerSolid: Color.lerp(onDangerSolid, other.onDangerSolid, t)!,
      shadowSm: BoxShadow.lerpList(shadowSm, other.shadowSm, t)!,
      shadowMd: BoxShadow.lerpList(shadowMd, other.shadowMd, t)!,
      shadowLg: BoxShadow.lerpList(shadowLg, other.shadowLg, t)!,
      chart: chart.lerp(other.chart, t),
    );
  }
}

/// Raggi del linguaggio "Registro": geometria squadrata, niente pill se non
/// per i contatori.
abstract final class AppRadii {
  /// 2 — badge, tag, tasti tastiera.
  static const double xs = 2;

  /// 3 — chip e tile.
  static const double tag = 3;

  /// 4 — controlli: bottoni, input, select, stepper.
  static const double control = 4;

  /// 6 — pannelli: card, tabelle, modali desktop.
  static const double panel = 6;

  /// 10 — bottom sheet e dialoghi flottanti.
  static const double sheet = 10;

  /// 999 — pill e contatori.
  static const double pill = 999;

  // --- Alias storici (valori allineati al nuovo linguaggio) --------------

  /// Controlli piccoli (icone interne, kbd): alias di [xs].
  static const double small = xs;

  /// Input, bottoni, dropdown: alias di [control].
  static const double input = control;

  /// Card, tabelle, modali desktop: alias di [panel].
  static const double card = panel;

  /// Bottom sheet mobili: alias di [sheet].
  static const double modal = sheet;

  /// Tile della heatmap: alias di [tag].
  static const double heatmap = tag;

  /// Alias di compatibilità con il vecchio token CSS `--radius-input`.
  static const double radiusInput = control;

  /// Alias di compatibilità con il vecchio token CSS `--radius-card`.
  static const double radiusCard = panel;

  /// Alias di compatibilità con il vecchio token CSS `--radius-pill`.
  static const double radiusPill = pill;
}

/// Spaziature del design system: scala base 2, passi principali 4/8/12.
abstract final class AppSpacing {
  /// 2 — micro aggiustamenti (margin icone).
  static const double s2 = 2;

  /// 4 — gap minimo tra elementi affiancati.
  static const double s4 = 4;

  /// 6 — gap di bottoni e badge.
  static const double s6 = 6;

  /// 8 — gap standard di toolbar e griglie fitte.
  static const double s8 = 8;

  /// 10 — gap griglie di card.
  static const double s10 = 10;

  /// 12 — gap griglie principali (`.stat-grid`).
  static const double s12 = 12;

  /// 14 — gap tra card di sezione.
  static const double s14 = 14;

  /// 16 — padding di blocchi e modali.
  static const double s16 = 16;

  /// 18 — padding card desktop.
  static const double s18 = 18;

  /// 20 — margini tra blocchi di form.
  static const double s20 = 20;

  /// 22 — padding storico di pagina.
  static const double s22 = 22;

  /// 24 — padding pagina desktop e margini di sezione ampi.
  static const double s24 = 24;

  /// 32 — padding dei box in evidenza (login).
  static const double s32 = 32;

  /// Padding orizzontale pagina ai tre breakpoint (24 / 18 / 12).
  static double pagePadding(double width) {
    if (width < AppBreakpoints.compact) return 12;
    if (width < AppBreakpoints.narrow) return 18;
    return 24;
  }

  /// Padding interno delle card ai tre breakpoint (16 / 16 / 12).
  static double cardPadding(double width) => width < AppBreakpoints.compact ? 12 : 16;
}

/// Misure dei controlli (indipendenti dal tema), per una densità coerente.
abstract final class AppSizes {
  /// Altezza bottone `xs` (azioni in riga tabella).
  static const double controlXs = 24;

  /// Altezza bottone `sm` e campo compatto.
  static const double controlSm = 28;

  /// Altezza standard di bottoni, input, select.
  static const double control = 34;

  /// Altezza bottone `lg` e campi in evidenza.
  static const double controlLg = 42;

  /// Riga tabella compatta.
  static const double rowCompact = 40;

  /// Riga tabella standard.
  static const double row = 48;

  /// Riga tabella ariosa (dettagli, form).
  static const double rowLoose = 56;

  /// Altezza della testata di tabella.
  static const double tableHeader = 36;

  /// Lato del bottone icona della topbar.
  static const double iconButton = 32;

  /// Lato del bottone icona in tabella.
  static const double iconButtonSm = 26;

  /// Area interattiva minima consigliata per le azioni di riga (32px).
  static const double touchTarget = 32;

  /// Icona piccola (badge, chip).
  static const double iconXs = 12;

  /// Icona compatta (bottoni sm, hint).
  static const double iconSm = 14;

  /// Icona standard (nav, bottoni md, celle).
  static const double icon = 16;

  /// Icona di sezione.
  static const double iconLg = 18;

  /// Icona grande (empty state, KPI).
  static const double iconXl = 22;

  /// Altezza di un tag/badge.
  static const double tag = 20;

  /// Altezza di un tasto tastiera.
  static const double kbd = 18;

  /// Spessore del bordo strutturale.
  static const double rule = 1;

  /// Spessore della striscia accent (card, toast).
  static const double accentStrip = 2;
}

/// Breakpoint del layout (invariati rispetto alla shell).
abstract final class AppBreakpoints {
  /// ≤1024: le griglie principali passano a una colonna.
  static const double narrow = 1024;

  /// ≤900: la sidebar diventa drawer off-canvas.
  static const double drawer = 900;

  /// ≤640: topbar 56, stat-grid a 2 colonne, modali a bottom-sheet.
  static const double compact = 640;

  /// ≤420: valori numerici ridotti.
  static const double tiny = 420;

  /// ≥1440: larghezza massima del contenuto raggiunta.
  static const double wide = 1440;
}

/// Durate e curve delle transizioni.
///
/// Principio: movimenti brevi e decisi. Le superfici cambiano in 120–200ms; i
/// contenuti entrano in 180–320ms con curva in uscita (`easeOutCubic`).
/// Le rivelazioni orchestrate usano [staggered] per dare un ordine di lettura.
abstract final class AppMotion {
  /// 120ms — hover/colore dei controlli.
  static const Duration fast = Duration(milliseconds: 120);

  /// 180ms — transizioni di superficie e ingressi compatti.
  static const Duration medium = Duration(milliseconds: 180);

  /// 200ms — ingresso/uscita toast, menu e popover.
  static const Duration overlay = Duration(milliseconds: 200);

  /// 240ms — apertura drawer/sidebar.
  static const Duration drawer = Duration(milliseconds: 240);

  /// 320ms — rivelazione di blocchi e grafici al primo caricamento.
  static const Duration reveal = Duration(milliseconds: 320);

  /// Passo base della rivelazione orchestrata.
  static const Duration staggerStep = Duration(milliseconds: 36);

  /// Curva standard dei cambi di stato (`easeOutCubic`).
  static const Curve ease = Curves.easeOutCubic;

  /// Curva per movimenti in/out (`ease-in-out`).
  static const Curve easeInOut = Curves.easeInOut;

  /// Curva di ingresso (elementi che appaiono).
  static const Curve enter = Curves.easeOutCubic;

  /// Curva di uscita (elementi che scompaiono).
  static const Curve exit = Curves.easeInCubic;

  /// Ritardo progressivo per liste/griglie che entrano in sequenza.
  ///
  /// `index` è la posizione dell'elemento; il ritardo si ferma a 6 passi
  /// (216ms) per non penalizzare le liste lunghe.
  static Duration staggered(int index, {int maxSteps = 6}) =>
      Duration(milliseconds: staggerStep.inMilliseconds * (index < 0 ? 0 : (index > maxSteps ? maxSteps : index)));

  /// Azzera la durata quando `prefers-reduced-motion` è attivo.
  static Duration effective(BuildContext context, Duration duration) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
}

/// Accesso ai token dal [BuildContext]: `context.tokens`.
extension AppTokensContext on BuildContext {
  /// Token del tema corrente (fallback: tema chiaro).
  AppTokens get tokens => Theme.of(this).extension<AppTokens>() ?? AppTokens.light;
}

/// Helper responsive sul [BuildContext], con gli stessi breakpoint del layout.
extension AppLayoutContext on BuildContext {
  /// Larghezza finestra corrente.
  double get windowWidth => MediaQuery.sizeOf(this).width;

  /// True sotto 1024px (griglie principali a una colonna).
  bool get isNarrow => windowWidth < AppBreakpoints.narrow;

  /// True sotto 900px (sidebar a drawer).
  bool get isDrawerLayout => windowWidth < AppBreakpoints.drawer;

  /// True sotto 640px (layout compatto, topbar bassa).
  bool get isCompact => windowWidth < AppBreakpoints.compact;

  /// True sotto 420px (tipografia dei valori ridotta).
  bool get isTiny => windowWidth < AppBreakpoints.tiny;
}
