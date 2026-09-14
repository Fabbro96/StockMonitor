import '../../core/models/portfolio.dart';

/// Modifica inline (non ancora salvata) di una holding.
///
/// I calcoli ricalcano il legacy `handleInlineEdit`/`renderTable` di
/// `portfolio.js`: il valore live usa `current_price` (fallback prezzo di
/// carico), il controvalore è `quantità × prezzo live`, il P&L è
/// `controvalore − quantità × prezzo di carico`.
class HoldingEdit {
  /// Crea una modifica per [holding] con i valori correnti.
  const HoldingEdit({
    required this.holding,
    required this.quantity,
    required this.avgPrice,
  });

  /// Crea la vista "non modificata" a partire dalla holding server.
  factory HoldingEdit.fromHolding(Holding holding) => HoldingEdit(
    holding: holding,
    quantity: holding.quantity,
    avgPrice: holding.avgPurchasePrice,
  );

  /// Holding originale.
  final Holding holding;

  /// Quantità in bozza.
  final double quantity;

  /// Prezzo medio di carico in bozza.
  final double avgPrice;

  /// True se uno dei due valori differisce dal server (tolleranza legacy).
  bool get changed =>
      (quantity - holding.quantity).abs() > 1e-9 ||
      (avgPrice - holding.avgPurchasePrice).abs() > 1e-4;

  /// Prezzo live: quello di mercato, con fallback sul prezzo di carico.
  double get currentPrice =>
      holding.currentPrice > 0 ? holding.currentPrice : avgPrice;

  /// Controvalore live (`quantità × prezzo live`).
  double get totalValue => quantity * currentPrice;

  /// Capitale investito (`quantità × prezzo di carico`).
  double get invested => quantity * avgPrice;

  /// P&L netto non realizzato.
  double get pnlAbsolute => totalValue - invested;

  /// P&L percentuale (0 se il capitale investito è 0).
  double get pnlPercent => invested > 0 ? (pnlAbsolute / invested) * 100 : 0;

  /// Copia con quantità e/o prezzo aggiornati.
  HoldingEdit copyWith({double? quantity, double? avgPrice}) => HoldingEdit(
    holding: holding,
    quantity: quantity ?? this.quantity,
    avgPrice: avgPrice ?? this.avgPrice,
  );
}

/// Vista di [holding]: la modifica pendente se presente, altrimenti i valori
/// server.
HoldingEdit holdingEditOf(Holding holding, Map<int, HoldingEdit> edits) =>
    edits[holding.id] ?? HoldingEdit.fromHolding(holding);

/// Formatta una bozza numerica (interi senza decimali, altrimenti fino a 4).
///
/// Usata dai controller degli stepper inline e dal riepilogo delle variazioni.
String formatDraftNumber(double value, {int? decimals}) {
  if (decimals != null) return value.toStringAsFixed(decimals);
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value
      .toStringAsFixed(4)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}
