import 'package:flutter/material.dart';

import 'badges.dart';

/// Tag compatto di mercato/strumento (sostituisce le emoji bandiera nel
/// linguaggio Registro): codice mono maiuscolo, tag squadrato, tinta per
/// famiglia di mercato.
///
/// Esempi: `IT`, `US`, `EU`, `FX`, `CMDTY`, `CRYPTO`, `IDX`.
class AppMarketTag extends StatelessWidget {
  /// Crea un tag di mercato da un codice già risolto.
  const AppMarketTag({
    super.key,
    required this.code,
    this.tone = BadgeTone.neutral,
    this.tooltip,
  });

  /// Tag dal ticker/mercato/tipo: mercato esplicito, poi tipo, poi suffisso
  /// del ticker (`IT`, `US`, `EU`, `FX`, `CMDTY`, `CRYPTO`, `IDX`).
  factory AppMarketTag.forTicker(String ticker, {String? market, String? type, String? tooltip}) {
    final (String code, BadgeTone tone) = resolve(ticker, market: market, type: type);
    return AppMarketTag(code: code, tone: tone, tooltip: tooltip);
  }

  /// Codice mostrato (es. `IT`, `US`, `FX`).
  final String code;

  /// Tinta del tag.
  final BadgeTone tone;

  /// Tooltip opzionale (es. nome esteso del mercato).
  final String? tooltip;

  /// Risolve il tag per un ticker: mercato esplicito, poi tipo, poi suffisso.
  static (String, BadgeTone) resolve(String ticker, {String? market, String? type}) {
    final String? normalizedMarket = market?.toUpperCase();
    switch (normalizedMarket) {
      case 'IT':
        return ('IT', BadgeTone.primary);
      case 'US':
        return ('US', BadgeTone.neutral);
      case 'EU':
        return ('EU', BadgeTone.cyan);
    }
    switch (type?.toUpperCase()) {
      case 'FX':
      case 'FOREX':
        return ('FX', BadgeTone.purple);
      case 'COMMODITY':
      case 'COMMODITIES':
        return ('CMDTY', BadgeTone.warning);
      case 'CRYPTO':
      case 'CRYPTOCURRENCY':
        return ('CRYPTO', BadgeTone.success);
    }
    final String upper = ticker.toUpperCase();
    if (upper.endsWith('.MI')) return ('IT', BadgeTone.primary);
    if (upper.endsWith('.DE') || upper.endsWith('.PA') || upper.endsWith('.AS')) {
      return ('EU', BadgeTone.cyan);
    }
    if (upper.endsWith('=F')) return ('CMDTY', BadgeTone.warning);
    if (upper.endsWith('-USD') || upper.endsWith('-EUR')) return ('CRYPTO', BadgeTone.success);
    if (upper.startsWith('^')) return ('IDX', BadgeTone.neutral);
    return ('US', BadgeTone.neutral);
  }

  @override
  Widget build(BuildContext context) => AppBadge(label: code, tone: tone, tooltip: tooltip);
}
