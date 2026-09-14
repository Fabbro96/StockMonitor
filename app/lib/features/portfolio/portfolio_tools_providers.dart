import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/portfolio_api.dart';
import '../../core/api_client.dart';
import '../../core/models/portfolio.dart';

/// Valore del filtro "Tutte" del Trade Ledger (`data-type="ALL"` legacy).
const String kAllTransactionsFilter = 'ALL';

/// Allocazioni target del Rebalancer (`GET /portfolio/rebalance/targets`).
final rebalanceTargetsProvider = FutureProvider<List<RebalanceTarget>>(
  (Ref ref) => ref.watch(portfolioApiProvider).rebalanceTargets(),
);

/// Piano di ribilanciamento corrente: `null` = nessun calcolo ancora eseguito.
final rebalancePreviewProvider =
    AsyncNotifierProvider<RebalancePreviewController, RebalancePreview?>(
      RebalancePreviewController.new,
    );

/// Controller del piano di ribilanciamento.
///
/// Il calcolo è on-demand (`POST /portfolio/rebalance/preview`): il risultato
/// resta visibile finché l'utente non ricalcola, come `#rebalanceResult`
/// legacy; un errore viene conservato nello stato e restituito al chiamante
/// per il toast (messaggio già leggibile da [ApiException.message]).
class RebalancePreviewController extends AsyncNotifier<RebalancePreview?> {
  @override
  RebalancePreview? build() => null;

  /// Calcola il piano con [extraCash] di liquidità aggiuntiva.
  ///
  /// Ritorna il messaggio d'errore oppure `null` in caso di successo.
  Future<String?> calculate(double extraCash) async {
    state = const AsyncLoading<RebalancePreview?>();
    final AsyncValue<RebalancePreview?> next =
        await AsyncValue.guard<RebalancePreview?>(
          () => ref.read(portfolioApiProvider).rebalancePreview(extraCash),
        );
    if (!ref.mounted) return null;
    state = next;
    if (!next.hasError) return null;
    final Object? error = next.error;
    return error is ApiException
        ? error.message
        : 'Errore durante il calcolo del piano';
  }
}

/// Dividendi stimati delle posizioni (`GET /portfolio/dividends`).
final dividendsProvider = FutureProvider<DividendsResult>(
  (Ref ref) => ref.watch(portfolioApiProvider).dividends(),
);

/// Transazioni del Trade Ledger filtrate per tipo (`ALL`/`BUY`/`SELL`/`DIVIDEND`).
///
/// Il backend accetta `?type=`; con [kAllTransactionsFilter] nessun filtro
/// viene inviato, come il legacy `getTransactions({})`.
///
/// `isAutoDispose: true` (in Riverpod 3 il default è `false`): ogni filtro
/// rilascia la cache quando la sezione smette di osservarlo, così cambiare
/// filtro — e tornarci — rifà sempre la richiesta come il legacy.
final transactionsProvider = FutureProvider.family<List<Transaction>, String>(
  (Ref ref, String type) => ref
      .watch(portfolioApiProvider)
      .transactions(type: type == kAllTransactionsFilter ? null : type),
  isAutoDispose: true,
);
