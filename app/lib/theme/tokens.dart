import 'package:flutter/material.dart';

/// Palette per i grafici (light/dark) — parità con `getChartThemeColors()`
/// del frontend HTML e con la palette della donut di allocazione.
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
    required this.volume,
    required this.volumeUp,
    required this.volumeDown,
    required this.benchmarkSp,
    required this.benchmarkMib,
    required this.breakeven,
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

  /// Volume neutro.
  final Color volume;

  /// Volume su candela rialzista.
  final Color volumeUp;

  /// Volume su candela ribassista.
  final Color volumeDown;

  /// Benchmark S&P 500.
  final Color benchmarkSp;

  /// Benchmark FTSE MIB.
  final Color benchmarkMib;

  /// Linea prezzo medio di carico (sempre `#f59e0b`, tratteggiata).
  final Color breakeven;

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
      volume: Color.lerp(volume, other.volume, t)!,
      volumeUp: Color.lerp(volumeUp, other.volumeUp, t)!,
      volumeDown: Color.lerp(volumeDown, other.volumeDown, t)!,
      benchmarkSp: Color.lerp(benchmarkSp, other.benchmarkSp, t)!,
      benchmarkMib: Color.lerp(benchmarkMib, other.benchmarkMib, t)!,
      breakeven: Color.lerp(breakeven, other.breakeven, t)!,
      pie: <Color>[
        for (var i = 0; i < pie.length; i++)
          Color.lerp(pie[i], other.pie[i % other.pie.length], t)!,
      ],
    );
  }
}

/// Design token dell'app, con gli stessi valori dei token CSS del frontend
/// (`style.css`): tema chiaro = default, tema scuro via `[data-theme="dark"]`.
///
/// È una [ThemeExtension]: le istanze pubbliche sono [AppTokens.light] e
/// [AppTokens.dark]; nei widget si accede con `context.tokens`.
///
/// I valori che non dipendono dal tema (raggi, spaziature, dimensioni shell)
/// vivono in [AppRadii], [AppSpacing], [AppBreakpoints] e come costanti su
/// questa classe.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  /// Crea un set di token completo.
  const AppTokens({
    required this.brightness,
    required this.bg,
    required this.bgSecondary,
    required this.surface,
    required this.surfaceHover,
    required this.surfaceActive,
    required this.border,
    required this.borderSubtle,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
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
    required this.scrim,
    required this.onPrimarySolid,
    required this.onSuccessSolid,
    required this.onWarningSolid,
    required this.shadowSm,
    required this.shadowMd,
    required this.shadowLg,
    required this.chart,
  });

  /// Chiaro o scuro: utile per scelte che non passano da `Theme.of`.
  final Brightness brightness;

  // --- Superfici e bordi -------------------------------------------------
  /// Sfondo pagina (`--bg-color`).
  final Color bg;

  /// Sfondo secondario, usato da footer/dettagli (`--bg-secondary`).
  final Color bgSecondary;

  /// Superficie di card, sidebar, topbar, input (`--surface-color`).
  final Color surface;

  /// Superficie hover di righe e controlli (`--surface-hover`).
  final Color surfaceHover;

  /// Superficie attiva/selezionata e stato disabilitato (`--surface-active`).
  final Color surfaceActive;

  /// Bordo standard (`--border-color`).
  final Color border;

  /// Bordo tenue per separatori interni (`--border-subtle`).
  final Color borderSubtle;

  /// Bordo marcato per hover e scrollbar (`--border-strong`).
  final Color borderStrong;

  // --- Testo -------------------------------------------------------------
  /// Testo principale (`--text-primary`).
  final Color textPrimary;

  /// Testo secondario (`--text-secondary`).
  final Color textSecondary;

  /// Testo attenuato, descrizioni e placeholder (`--text-muted`).
  final Color textMuted;

  // --- Accenti -----------------------------------------------------------
  /// Blu di accento per link, outline focus, nav attiva (`--primary-color`).
  final Color primary;

  /// Blu pieno dei bottoni primari (`--primary-solid`).
  final Color primarySolid;

  /// Blu pieno in hover (`--primary-solid-hover`).
  final Color primarySolidHover;

  /// Alone del focus ring (`--primary-glow`).
  final Color primaryGlow;

  /// Ciano per badge/mercati non italiani (`--cyan-color`).
  final Color cyan;

  /// Verde di successo, usato anche dai grafici (`--success-color`).
  final Color success;

  /// Verde per testo profit (`--success-text`).
  final Color successText;

  /// Sfondo tenue di successo (`--success-bg`).
  final Color successBg;

  /// Bordo tenue di successo (`--success-border`).
  final Color successBorder;

  /// Rosso di errore/loss (`--danger-color`).
  final Color danger;

  /// Sfondo tenue di errore (`--danger-bg`).
  final Color dangerBg;

  /// Bordo tenue di errore (`--danger-border`).
  final Color dangerBorder;

  /// Ambra di warning (`--warning-color`).
  final Color warning;

  /// Sfondo tenue di warning (`--warning-bg`).
  final Color warningBg;

  /// Bordo tenue di warning (`--warning-border`).
  final Color warningBorder;

  /// Viola per badge admin (`--purple-color`).
  final Color purple;

  /// Sfondo tenue viola (`--purple-bg`).
  final Color purpleBg;

  /// Velo di overlay di modali e drawer (`rgba(16,24,40,.45)` / `rgba(0,0,0,.6)`).
  final Color scrim;

  /// Testo su superficie primary piena (sempre bianco).
  final Color onPrimarySolid;

  /// Testo su superficie success piena (scuro nel tema scuro, per contrasto).
  final Color onSuccessSolid;

  /// Testo su superficie warning piena (scuro nel tema scuro, per contrasto).
  final Color onWarningSolid;

  // --- Ombre -------------------------------------------------------------
  /// Ombra piccola (`--shadow-sm`).
  final List<BoxShadow> shadowSm;

  /// Ombra media, usata da card in evidenza e toast (`--shadow-md`).
  final List<BoxShadow> shadowMd;

  /// Ombra grande, usata da drawer e modali (`--shadow-lg`).
  final List<BoxShadow> shadowLg;

  /// Palette dei grafici.
  final AppChartPalette chart;

  // --- Dimensioni shell (uguali nei due temi) ---------------------------
  /// Larghezza sidebar desktop (`--sidebar-width`).
  static const double sidebarWidth = 232;

  /// Larghezza sidebar desktop compressa.
  static const double sidebarCollapsedWidth = 62;

  /// Larghezza drawer mobile.
  static const double sidebarMobileWidth = 260;

  /// Altezza topbar desktop (`--topbar-height`).
  static const double topbarHeight = 60;

  /// Altezza topbar mobile (≤640px).
  static const double topbarHeightMobile = 56;

  /// Larghezza massima del contenuto pagina (`.content-wrapper`).
  static const double contentMaxWidth = 1400;

  /// Famiglia di fallback sans di sistema (`--font-family`).
  static const List<String> fontFallback = <String>[
    '-apple-system',
    'BlinkMacSystemFont',
    'Segoe UI',
    'Roboto',
    'Helvetica',
    'Arial',
    'sans-serif',
  ];

  /// Famiglia mono di sistema (`--font-mono`).
  static const String monoFontFamily = 'monospace';

  /// Fallback mono di sistema.
  static const List<String> monoFontFallback = <String>[
    'ui-monospace',
    'SFMono-Regular',
    'Menlo',
    'Monaco',
    'Consolas',
    'Liberation Mono',
    'monospace',
  ];

  /// Tema chiaro (default del sito).
  static const AppTokens light = AppTokens(
    brightness: Brightness.light,
    bg: Color(0xFFF5F6F8),
    bgSecondary: Color(0xFFEEF0F3),
    surface: Color(0xFFFFFFFF),
    surfaceHover: Color(0xFFF2F4F7),
    surfaceActive: Color(0xFFE7EAEF),
    border: Color(0xFFE0E4EA),
    borderSubtle: Color(0xFFEDF0F4),
    borderStrong: Color(0xFFCBD2DC),
    textPrimary: Color(0xFF15181E),
    textSecondary: Color(0xFF5A6472),
    textMuted: Color(0xFF667085),
    primary: Color(0xFF2563EB),
    primarySolid: Color(0xFF2563EB),
    primarySolidHover: Color(0xFF1D4ED8),
    primaryGlow: Color.fromRGBO(37, 99, 235, 0.12),
    cyan: Color(0xFF0E7490),
    success: Color(0xFF0F8A4D),
    successText: Color(0xFF056B3E),
    successBg: Color.fromRGBO(15, 138, 77, 0.09),
    successBorder: Color.fromRGBO(15, 138, 77, 0.24),
    danger: Color(0xFFD1242F),
    dangerBg: Color.fromRGBO(209, 36, 47, 0.08),
    dangerBorder: Color.fromRGBO(209, 36, 47, 0.22),
    warning: Color(0xFFB45309),
    warningBg: Color.fromRGBO(180, 83, 9, 0.09),
    warningBorder: Color.fromRGBO(180, 83, 9, 0.24),
    purple: Color(0xFF6D28D9),
    purpleBg: Color.fromRGBO(109, 40, 217, 0.09),
    scrim: Color.fromRGBO(16, 24, 40, 0.45),
    onPrimarySolid: Color(0xFFFFFFFF),
    onSuccessSolid: Color(0xFFFFFFFF),
    onWarningSolid: Color(0xFFFFFFFF),
    shadowSm: <BoxShadow>[
      BoxShadow(color: Color.fromRGBO(16, 24, 40, 0.05), offset: Offset(0, 1), blurRadius: 2),
    ],
    shadowMd: <BoxShadow>[
      BoxShadow(color: Color.fromRGBO(16, 24, 40, 0.09), offset: Offset(0, 4), blurRadius: 14),
    ],
    shadowLg: <BoxShadow>[
      BoxShadow(color: Color.fromRGBO(16, 24, 40, 0.16), offset: Offset(0, 14), blurRadius: 36),
    ],
    chart: AppChartPalette(
      text: Color(0xFF5A6472),
      grid: Color.fromRGBO(21, 24, 30, 0.07),
      line: Color(0xFF2563EB),
      top: Color.fromRGBO(37, 99, 235, 0.16),
      bottom: Color.fromRGBO(37, 99, 235, 0.01),
      up: Color(0xFF0F8A4D),
      down: Color(0xFFD1242F),
      volume: Color.fromRGBO(90, 100, 114, 0.25),
      volumeUp: Color.fromRGBO(15, 138, 77, 0.32),
      volumeDown: Color.fromRGBO(209, 36, 47, 0.28),
      benchmarkSp: Color(0xFF0F8A4D),
      benchmarkMib: Color(0xFFB45309),
      breakeven: Color(0xFFF59E0B),
      pie: <Color>[
        Color(0xFF2563EB),
        Color(0xFF0F8A4D),
        Color(0xFFD1242F),
        Color(0xFFB45309),
        Color(0xFF6D28D9),
        Color(0xFF0E7490),
        Color(0xFFBE185D),
        Color(0xFF4F46E5),
        Color(0xFF0F766E),
      ],
    ),
  );

  /// Tema scuro (`[data-theme="dark"]`).
  static const AppTokens dark = AppTokens(
    brightness: Brightness.dark,
    bg: Color(0xFF0F1115),
    bgSecondary: Color(0xFF13161C),
    surface: Color(0xFF161920),
    surfaceHover: Color(0xFF1E222B),
    surfaceActive: Color(0xFF262B36),
    border: Color(0xFF272C36),
    borderSubtle: Color(0xFF1E222B),
    borderStrong: Color(0xFF3A4150),
    textPrimary: Color(0xFFE8EAEE),
    textSecondary: Color(0xFFA2A9B6),
    textMuted: Color(0xFF8B93A1),
    primary: Color(0xFF5B9DFF),
    primarySolid: Color(0xFF2F6FE4),
    primarySolidHover: Color(0xFF4080F0),
    primaryGlow: Color.fromRGBO(91, 157, 255, 0.15),
    cyan: Color(0xFF22D3EE),
    success: Color(0xFF4CC38A),
    successText: Color(0xFF4CC38A),
    successBg: Color.fromRGBO(76, 195, 138, 0.1),
    successBorder: Color.fromRGBO(76, 195, 138, 0.26),
    danger: Color(0xFFF26A76),
    dangerBg: Color.fromRGBO(242, 106, 118, 0.1),
    dangerBorder: Color.fromRGBO(242, 106, 118, 0.26),
    warning: Color(0xFFE3A008),
    warningBg: Color.fromRGBO(227, 160, 8, 0.1),
    warningBorder: Color.fromRGBO(227, 160, 8, 0.26),
    purple: Color(0xFFA78BFA),
    purpleBg: Color.fromRGBO(167, 139, 250, 0.1),
    scrim: Color.fromRGBO(0, 0, 0, 0.6),
    onPrimarySolid: Color(0xFFFFFFFF),
    onSuccessSolid: Color(0xFF0B1F14),
    onWarningSolid: Color(0xFF241A03),
    shadowSm: <BoxShadow>[
      BoxShadow(color: Color.fromRGBO(0, 0, 0, 0.3), offset: Offset(0, 1), blurRadius: 2),
    ],
    shadowMd: <BoxShadow>[
      BoxShadow(color: Color.fromRGBO(0, 0, 0, 0.36), offset: Offset(0, 4), blurRadius: 14),
    ],
    shadowLg: <BoxShadow>[
      BoxShadow(color: Color.fromRGBO(0, 0, 0, 0.48), offset: Offset(0, 14), blurRadius: 36),
    ],
    chart: AppChartPalette(
      text: Color(0xFFA2A9B6),
      grid: Color.fromRGBO(232, 234, 238, 0.07),
      line: Color(0xFF5B9DFF),
      top: Color.fromRGBO(91, 157, 255, 0.22),
      bottom: Color.fromRGBO(91, 157, 255, 0.01),
      up: Color(0xFF4CC38A),
      down: Color(0xFFF26A76),
      volume: Color.fromRGBO(162, 169, 182, 0.22),
      volumeUp: Color.fromRGBO(76, 195, 138, 0.32),
      volumeDown: Color.fromRGBO(242, 106, 118, 0.3),
      benchmarkSp: Color(0xFF4CC38A),
      benchmarkMib: Color(0xFFE3A008),
      breakeven: Color(0xFFF59E0B),
      pie: <Color>[
        Color(0xFF5B9DFF),
        Color(0xFF4CC38A),
        Color(0xFFF26A76),
        Color(0xFFE3A008),
        Color(0xFFA78BFA),
        Color(0xFF22D3EE),
        Color(0xFFF472B6),
        Color(0xFF818CF8),
        Color(0xFF2DD4BF),
      ],
    ),
  );

  /// Sfondo di una tile heatmap in base alla variazione percentuale:
  /// neutro a 0/null, tinte crescenti per |variazione| ≥1% e ≥3%.
  Color heatmapTileBackground(double? changePercent) {
    final Color base = _heatmapBase(changePercent);
    if (base == surface) return base;
    return base.withValues(alpha: _heatmapAlpha(changePercent, background: true));
  }

  /// Bordo di una tile heatmap, coerente con [heatmapTileBackground].
  Color heatmapTileBorder(double? changePercent) {
    final Color base = _heatmapBase(changePercent);
    if (base == surface) return border;
    return base.withValues(alpha: _heatmapAlpha(changePercent, background: false));
  }

  Color _heatmapBase(double? changePercent) {
    if (changePercent == null || changePercent == 0) return surface;
    return changePercent > 0 ? success : danger;
  }

  double _heatmapAlpha(double? changePercent, {required bool background}) {
    final double magnitude = changePercent?.abs() ?? 0;
    final bool isDark = brightness == Brightness.dark;
    if (background) {
      if (magnitude >= 3) return isDark ? 0.22 : 0.20;
      if (magnitude >= 1) return isDark ? 0.14 : 0.12;
      return isDark ? 0.07 : 0.06;
    }
    if (magnitude >= 3) return isDark ? 0.50 : 0.45;
    if (magnitude >= 1) return isDark ? 0.34 : 0.30;
    return isDark ? 0.20 : 0.18;
  }

  @override
  AppTokens copyWith({
    Brightness? brightness,
    Color? bg,
    Color? bgSecondary,
    Color? surface,
    Color? surfaceHover,
    Color? surfaceActive,
    Color? border,
    Color? borderSubtle,
    Color? borderStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
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
    Color? scrim,
    Color? onPrimarySolid,
    Color? onSuccessSolid,
    Color? onWarningSolid,
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
      surfaceHover: surfaceHover ?? this.surfaceHover,
      surfaceActive: surfaceActive ?? this.surfaceActive,
      border: border ?? this.border,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      borderStrong: borderStrong ?? this.borderStrong,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
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
      scrim: scrim ?? this.scrim,
      onPrimarySolid: onPrimarySolid ?? this.onPrimarySolid,
      onSuccessSolid: onSuccessSolid ?? this.onSuccessSolid,
      onWarningSolid: onWarningSolid ?? this.onWarningSolid,
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
      surfaceHover: Color.lerp(surfaceHover, other.surfaceHover, t)!,
      surfaceActive: Color.lerp(surfaceActive, other.surfaceActive, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
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
      scrim: Color.lerp(scrim, other.scrim, t)!,
      onPrimarySolid: Color.lerp(onPrimarySolid, other.onPrimarySolid, t)!,
      onSuccessSolid: Color.lerp(onSuccessSolid, other.onSuccessSolid, t)!,
      onWarningSolid: Color.lerp(onWarningSolid, other.onWarningSolid, t)!,
      shadowSm: BoxShadow.lerpList(shadowSm, other.shadowSm, t)!,
      shadowMd: BoxShadow.lerpList(shadowMd, other.shadowMd, t)!,
      shadowLg: BoxShadow.lerpList(shadowLg, other.shadowLg, t)!,
      chart: chart.lerp(other.chart, t),
    );
  }
}

/// Raggi ricorrenti (`--radius-*`), uguali nei due temi.
abstract final class AppRadii {
  /// Controlli piccoli (stepper button, icone interne).
  static const double small = 4;

  /// Input, bottoni, dropdown, tooltip (`--radius-input`).
  static const double input = 6;

  /// Tile heatmap.
  static const double heatmap = 8;

  /// Card, tabelle, modali desktop (`--radius-card`).
  static const double card = 10;

  /// Modali in bottom-sheet su mobile.
  static const double modal = 12;

  /// Pill e badge (`--radius-pill`).
  static const double pill = 999;

  /// Alias di compatibilità con il token CSS `--radius-input`.
  static const double radiusInput = input;

  /// Alias di compatibilità con il token CSS `--radius-card`.
  static const double radiusCard = card;

  /// Alias di compatibilità con il token CSS `--radius-pill`.
  static const double radiusPill = pill;
}

/// Spaziature del design system (scala dal CSS: 4, 6, 8, 10, 12, 14, 16, 18, 22…).
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

  /// 22 — padding pagina desktop (`.content-wrapper`).
  static const double s22 = 22;

  /// 24 — margini di sezione ampi.
  static const double s24 = 24;

  /// 32 — padding dei box in evidenza (login).
  static const double s32 = 32;

  /// Padding orizzontale pagina ai tre breakpoint (22 / 18 / 12).
  static double pagePadding(double width) {
    if (width < AppBreakpoints.compact) return 12;
    if (width < AppBreakpoints.narrow) return 18;
    return 22;
  }

  /// Padding interno delle card ai tre breakpoint (18 / 18 / 14).
  static double cardPadding(double width) => width < AppBreakpoints.compact ? 14 : 18;
}

/// Breakpoint del layout, allineati al CSS.
abstract final class AppBreakpoints {
  /// ≤1024: le griglie principali passano a una colonna.
  static const double narrow = 1024;

  /// ≤900: la sidebar diventa drawer off-canvas.
  static const double drawer = 900;

  /// ≤640: topbar 56, stat-grid a 2 colonne, modali a bottom-sheet.
  static const double compact = 640;

  /// ≤420: stat-value ridotto.
  static const double tiny = 420;
}

/// Durate e curve delle transizioni (`--transition: .15s ease`).
abstract final class AppMotion {
  /// 150ms — hover/colore dei controlli.
  static const Duration fast = Duration(milliseconds: 150);

  /// 200ms — transizioni di superficie.
  static const Duration medium = Duration(milliseconds: 200);

  /// 220ms — apertura drawer/sidebar.
  static const Duration drawer = Duration(milliseconds: 220);

  /// 180ms — ingresso/uscita toast e modali.
  static const Duration overlay = Duration(milliseconds: 180);

  /// Curva standard (`ease`).
  static const Curve ease = Curves.ease;

  /// Curva per movimenti in/out (`ease-in-out`).
  static const Curve easeInOut = Curves.easeInOut;

  /// Azzera la durata quando `prefers-reduced-motion` è attivo.
  static Duration effective(BuildContext context, Duration duration) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
}

/// Accesso ai token dal [BuildContext]: `context.tokens`.
extension AppTokensContext on BuildContext {
  /// Token del tema corrente (fallback: tema chiaro).
  AppTokens get tokens =>
      Theme.of(this).extension<AppTokens>() ?? AppTokens.light;
}

/// Helper responsive sul [BuildContext], con gli stessi breakpoint del CSS.
extension AppLayoutContext on BuildContext {
  /// Larghezza finestra corrente.
  double get windowWidth => MediaQuery.sizeOf(this).width;

  /// True sotto 1024px (griglie principali a una colonna).
  bool get isNarrow => windowWidth < AppBreakpoints.narrow;

  /// True sotto 900px (sidebar a drawer).
  bool get isDrawerLayout => windowWidth < AppBreakpoints.drawer;

  /// True sotto 640px (layout compatta, topbar bassa).
  bool get isCompact => windowWidth < AppBreakpoints.compact;

  /// True sotto 420px (tipografia dei valori ridotta).
  bool get isTiny => windowWidth < AppBreakpoints.tiny;
}
