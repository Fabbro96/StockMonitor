import 'package:flutter_test/flutter_test.dart';
import 'package:stock_monitor/core/models/portfolio.dart';
import 'package:stock_monitor/features/portfolio/portfolio_edits.dart';

/// Holding di test (campi API minimi + default lato model).
Holding _holding({
  int id = 1,
  double quantity = 10,
  double avgPrice = 100,
  double currentPrice = 120,
}) {
  return Holding.fromJson(<String, dynamic>{
    'id': id,
    'stock_id': id,
    'ticker': 'AAPL',
    'name': 'Apple Inc.',
    'market': 'US',
    'currency': 'USD',
    'quantity': quantity,
    'avg_purchase_price': avgPrice,
    'current_price': currentPrice,
  });
}

void main() {
  group('HoldingEdit', () {
    test('changed è false a valori invariati', () {
      final Holding holding = _holding();
      expect(HoldingEdit.fromHolding(holding).changed, isFalse);
    });

    test('changed rileva quantità e prezzo oltre la tolleranza legacy', () {
      final Holding holding = _holding();
      final HoldingEdit baseline = HoldingEdit.fromHolding(holding);

      expect(baseline.copyWith(quantity: 11).changed, isTrue);
      expect(baseline.copyWith(avgPrice: 100.001).changed, isTrue);
      // Differenza entro 1e-4: considerata invariata (come handleInlineEdit).
      expect(baseline.copyWith(avgPrice: 100.00005).changed, isFalse);
    });

    test('currentPrice usa il prezzo live e ricade sul carico', () {
      expect(HoldingEdit.fromHolding(_holding()).currentPrice, 120);
      expect(
        HoldingEdit.fromHolding(_holding(currentPrice: 0)).currentPrice,
        100,
      );
      // Il fallback usa il prezzo di carico della bozza, non quello server.
      expect(
        HoldingEdit.fromHolding(_holding(currentPrice: 0))
            .copyWith(avgPrice: 90)
            .currentPrice,
        90,
      );
    });

    test('controvalore, investito e P&L usano i valori in bozza', () {
      final HoldingEdit edit = HoldingEdit.fromHolding(_holding())
          .copyWith(quantity: 11, avgPrice: 100);

      expect(edit.totalValue, 1320); // 11 × 120 (prezzo live)
      expect(edit.invested, 1100); // 11 × 100
      expect(edit.pnlAbsolute, 220);
      expect(edit.pnlPercent, closeTo(20, 1e-9));
    });

    test('P&L % è 0 quando il capitale investito è 0', () {
      final HoldingEdit edit = HoldingEdit.fromHolding(_holding())
          .copyWith(quantity: 0);
      expect(edit.invested, 0);
      expect(edit.pnlPercent, 0);
    });

    test('copyWith aggiorna solo i campi passati', () {
      final HoldingEdit baseline = HoldingEdit.fromHolding(_holding());
      final HoldingEdit next = baseline.copyWith(quantity: 5);
      expect(next.quantity, 5);
      expect(next.avgPrice, baseline.avgPrice);
      expect(next.holding, same(baseline.holding));
    });

    test('holdingEditOf preferisce la bozza pendente', () {
      final Holding holding = _holding();
      final HoldingEdit draft = HoldingEdit.fromHolding(holding)
          .copyWith(quantity: 3);
      expect(
        holdingEditOf(holding, <int, HoldingEdit>{holding.id: draft}).quantity,
        3,
      );
      expect(
        holdingEditOf(holding, const <int, HoldingEdit>{}).quantity,
        holding.quantity,
      );
    });
  });

  group('formatDraftNumber', () {
    test('interi senza decimali, decimali senza zeri finali', () {
      expect(formatDraftNumber(100), '100');
      expect(formatDraftNumber(24.5), '24.5');
      expect(formatDraftNumber(0), '0');
      expect(formatDraftNumber(1.23456), '1.2346');
    });

    test('decimals forza il numero di cifre', () {
      expect(formatDraftNumber(24.5, decimals: 2), '24.50');
      expect(formatDraftNumber(100, decimals: 2), '100.00');
    });
  });
}
