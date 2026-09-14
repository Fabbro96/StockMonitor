/// Mappatura ticker/mercato → emoji bandiera usata da watchlist, heatmap e
/// ticker tape (nel frontend la stessa logica era inline in `app.js`).
///
/// Regole:
/// - `market` `IT`/`US`/`EU` → 🇮🇹 🇺🇸 🇪🇺;
/// - `type` `FX`/`COMMODITY`/`CRYPTO` (o suffissi tipici `=F`, `-USD`) →
///   fallback 💱 🛢️ ₿;
/// - `^` (indici) e mercati sconosciuti → 🇺🇸 come il comportamento legacy,
///   con 🌐 per i suffissi esteri non riconosciuti.
abstract final class TickerFlags {
  /// Italia.
  static const String italy = '🇮🇹';

  /// Stati Uniti.
  static const String unitedStates = '🇺🇸';

  /// Europa.
  static const String europe = '🇪🇺';

  /// Valute (fallback).
  static const String forex = '💱';

  /// Commodity (fallback).
  static const String commodity = '🛢️';

  /// Cripto (fallback).
  static const String crypto = '₿';

  /// Mercato/sconosciuto (fallback).
  static const String world = '🌐';

  /// Bandiera dal solo mercato (`IT`/`US`/`EU`), altrimenti [world].
  static String forMarket(String? market) {
    return switch (market?.toUpperCase()) {
      'IT' => italy,
      'US' => unitedStates,
      'EU' => europe,
      _ => world,
    };
  }

  /// Bandiera per un titolo: usa `market`, poi `type`, poi il suffisso del
  /// ticker, con 🇺🇸 come default legacy.
  static String forTicker(String ticker, {String? market, String? type}) {
    final String? normalizedMarket = market?.toUpperCase();
    if (normalizedMarket == 'IT' || normalizedMarket == 'US' || normalizedMarket == 'EU') {
      return forMarket(normalizedMarket);
    }
    final String? normalizedType = type?.toUpperCase();
    switch (normalizedType) {
      case 'FX':
      case 'FOREX':
        return forex;
      case 'COMMODITY':
      case 'COMMODITIES':
        return commodity;
      case 'CRYPTO':
      case 'CRYPTOCURRENCY':
        return crypto;
    }
    final String upper = ticker.toUpperCase();
    if (upper.endsWith('.MI')) return italy;
    if (upper.endsWith('.DE') || upper.endsWith('.PA') || upper.endsWith('.AS')) return europe;
    if (upper.endsWith('=F')) return commodity;
    if (upper.endsWith('-USD') || upper.endsWith('-EUR')) return crypto;
    if (upper.startsWith('^')) return unitedStates;
    return market == null ? unitedStates : world;
  }
}

/// Scorciatoia top-level per [TickerFlags.forTicker].
String tickerFlag(String ticker, {String? market, String? type}) =>
    TickerFlags.forTicker(ticker, market: market, type: type);
