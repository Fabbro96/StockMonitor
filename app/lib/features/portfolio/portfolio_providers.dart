import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api/portfolio_api.dart';
import '../../core/api/settings_api.dart';
import '../../core/models/portfolio.dart';
import '../../core/models/settings.dart';
import '../settings/settings_providers.dart';
import 'portfolio_tools_providers.dart';

/// Budget di default legacy quando le impostazioni non sono disponibili.
const double kDefaultPortfolioBudget = 10000;

/// Controller delle holdings del portafoglio (load + mutazioni).
///
/// Il data layer (`PortfolioApi`) coercizza le liste malformate a lista vuota
/// (`asMapList`), quindi un payload non-array produce empty state pulito e non
/// un crash; gli errori di rete finiscono in `AsyncError` e vengono notificati
/// dalla pagina con `ApiException.message`.
class PortfolioController extends AsyncNotifier<List<Holding>> {
  @override
  Future<List<Holding>> build() => ref.read(portfolioApiProvider).holdings();

  /// Ricarica la lista mantenendo i dati correnti durante il refresh.
  Future<void> reload() async {
    if (state.value == null) {
      state = const AsyncLoading<List<Holding>>();
    }
    state = await AsyncValue.guard<List<Holding>>(
      () => ref.read(portfolioApiProvider).holdings(),
    );
  }

  /// Aggiunge una holding (il backend fa merge di un ticker già presente).
  Future<Holding> add({
    required String ticker,
    required double quantity,
    required double avgPurchasePrice,
    DateTime? purchaseDate,
    String? notes,
  }) async {
    final Holding created = await ref
        .read(portfolioApiProvider)
        .addHolding(
          ticker: ticker,
          quantity: quantity,
          avgPurchasePrice: avgPurchasePrice,
          purchaseDate: purchaseDate,
          notes: notes,
        );
    await reload();
    return created;
  }

  /// Elimina una holding con aggiornamento ottimistico dello stato locale.
  Future<void> remove(int id) async {
    await ref.read(portfolioApiProvider).deleteHolding(id);
    final List<Holding>? current = state.value;
    if (current == null || !ref.mounted) return;
    state = AsyncData<List<Holding>>(<Holding>[
      for (final Holding item in current)
        if (item.id != id) item,
    ]);
  }

  /// Undo di una eliminazione: ripristina la posizione con i valori originali.
  Future<void> restore(Holding holding) async {
    await ref
        .read(portfolioApiProvider)
        .addHolding(
          ticker: holding.ticker,
          quantity: holding.quantity,
          avgPurchasePrice: holding.avgPurchasePrice,
          notes: holding.notes.isEmpty ? null : holding.notes,
        );
    await reload();
  }

  /// Salva in blocco le modifiche inline; ritorna il numero di posizioni
  /// aggiornate (fallback: numero di update inviati).
  Future<int> batchUpdate(
    List<({int id, double quantity, double avgPurchasePrice, String? notes})>
    updates,
  ) async {
    final Map<String, dynamic> result = await ref
        .read(portfolioApiProvider)
        .batchUpdateHoldings(updates);
    final int? updated = (result['updated_count'] as num?)?.toInt();
    await reload();
    return updated ?? updates.length;
  }

  /// Inizializza il portafoglio demo; ritorna il messaggio del backend.
  Future<String> seedDemo() async {
    final Map<String, dynamic> result = await ref
        .read(portfolioApiProvider)
        .seedDemo();
    await reload();
    return result['message']?.toString() ?? 'Demo inizializzata con successo!';
  }
}

/// Holdings del portafoglio.
final portfolioProvider =
    AsyncNotifierProvider<PortfolioController, List<Holding>>(
      PortfolioController.new,
    );

/// Riepilogo aggregato (`GET /portfolio/summary`).
final portfolioSummaryProvider = FutureProvider<PortfolioSummary>(
  (Ref ref) => ref.watch(portfolioApiProvider).summary(),
);

/// P&L realizzato (`GET /portfolio/realized-pnl`).
final realizedPnlProvider = FutureProvider<RealizedPnl>(
  (Ref ref) => ref.watch(portfolioApiProvider).realizedPnl(),
);

/// Budget effettivo delle impostazioni: preferisce `total_budget`, poi
/// `budget`, poi il default legacy 10000.
double budgetFromSettings(UserSettings settings) {
  final double budget = settings.totalBudget > 0
      ? settings.totalBudget
      : settings.budget;
  return budget > 0 ? budget : kDefaultPortfolioBudget;
}

/// Budget totale derivato da [settingsProvider].
///
/// Deriva dallo stato settings (aggiornato anche dal PUT "Salva
/// Impostazioni"), così dopo un salvataggio il card Budget del portafoglio si
/// aggiorna senza reload manuali. Se lo stato settings è in errore si tenta
/// una GET diretta e, in ultima istanza, si usa il default legacy (10000).
///
/// Nota: si osserva solo `settingsProvider.future` (mai stato + future
/// insieme: in Riverpod 3.4.3 la combinazione non completa mai).
final portfolioBudgetProvider = FutureProvider<double>((Ref ref) async {
  try {
    final UserSettings settings = await ref.watch(settingsProvider.future);
    return budgetFromSettings(settings);
  } catch (_) {
    try {
      final UserSettings fallback = await ref
          .read(settingsApiProvider)
          .getSettings();
      return budgetFromSettings(fallback);
    } catch (_) {
      return kDefaultPortfolioBudget;
    }
  }
});

/// Ricarica holdings + aggregati dopo una mutazione (add/delete/save/import).
///
/// Invalida anche il calendario dividendi (`dividendsProvider`, sezione tools):
/// dipende dalle holdings e senza invalidazione resterebbe vecchio.
Future<void> reloadPortfolio(WidgetRef ref) async {
  ref.invalidate(portfolioSummaryProvider);
  ref.invalidate(realizedPnlProvider);
  ref.invalidate(dividendsProvider);
  await ref.read(portfolioProvider.notifier).reload();
}

/// Vista della donut di allocazione (`portfolio_alloc_view` legacy).
enum AllocationView {
  /// Allocazione per singolo titolo (default).
  stock,

  /// Allocazione per mercato.
  market,
}

/// Persistenza feature-local della vista allocazione.
///
/// Usa `shared_preferences` direttamente (come il timeframe dashboard) perché
/// `AppStorage` non espone chiavi generiche; stessa chiave `portfolio_alloc_view`
/// del vecchio `localStorage` (`stock` default / `market`).
class PortfolioAllocViewStore {
  /// Crea lo store.
  const PortfolioAllocViewStore();

  static const String _key = 'portfolio_alloc_view';

  /// Legge la vista salvata; `null` se assente o storage non disponibile.
  Future<AllocationView?> read() async {
    try {
      final String? raw = await SharedPreferencesAsync().getString(_key);
      return switch (raw) {
        'market' => AllocationView.market,
        'stock' => AllocationView.stock,
        _ => null,
      };
    } catch (_) {
      return null;
    }
  }

  /// Scrive la vista scelta; gli errori di storage non rompono la UI.
  Future<void> write(AllocationView view) async {
    try {
      await SharedPreferencesAsync().setString(
        _key,
        view == AllocationView.market ? 'market' : 'stock',
      );
    } catch (_) {
      // Nessuna persistenza disponibile: la selezione resta in memoria.
    }
  }
}

/// Controller della vista allocazione con persistenza (default `Titoli`).
class AllocationViewController extends Notifier<AllocationView> {
  bool _userSelected = false;

  @override
  AllocationView build() => AllocationView.stock;

  /// Carica la preferenza salvata (da chiamare una volta all'apertura pagina).
  Future<void> load() async {
    final AllocationView? stored = await const PortfolioAllocViewStore().read();
    if (_userSelected || stored == null) return;
    state = stored;
  }

  /// Seleziona la vista e la persiste.
  Future<void> select(AllocationView view) async {
    _userSelected = true;
    if (state == view) return;
    state = view;
    await const PortfolioAllocViewStore().write(view);
  }
}

/// Vista corrente della donut di allocazione.
final allocationViewProvider =
    NotifierProvider<AllocationViewController, AllocationView>(
      AllocationViewController.new,
    );
