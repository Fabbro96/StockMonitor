import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api/advice_api.dart';
import '../../core/api/dashboard_api.dart';
import '../../core/api/portfolio_api.dart';
import '../../core/models/advice.dart';
import '../../core/models/dashboard.dart';
import '../../core/models/portfolio.dart';

/// Stato aggregato della dashboard: ogni sezione può mancare (mai caricata o
/// ultima chiamata fallita) senza buttare giù le altre.
@immutable
class DashboardState {
  /// Crea lo stato aggregato.
  const DashboardState({
    this.summary,
    this.holdings,
    this.heatmap,
    this.advices,
    this.marketStatus,
    this.failedSections = const <String>[],
    this.loadCount = 0,
    this.lastLoadSilent = false,
    this.lastUpdated,
  });

  /// Summary del portafoglio (stat cards), `null` finché mai caricato.
  final PortfolioSummary? summary;

  /// Righe del portafoglio per la tabella, `null` finché mai caricate.
  final List<Holding>? holdings;

  /// Titoli della heatmap, `null` finché mai caricata.
  final List<HeatmapItem>? heatmap;

  /// Ultime analisi macro, `null` finché mai caricate.
  final List<Advice>? advices;

  /// Stato dei mercati dal payload dashboard, `null` se mai caricato.
  final MarketStatusInfo? marketStatus;

  /// Nomi (ordine API) delle sezioni fallite nell'ultimo load.
  final List<String> failedSections;

  /// Contatore dei load completati: usato dalla pagina per non ripetere i toast.
  final int loadCount;

  /// True se l'ultimo load era il refresh silente (senza toast sugli errori).
  final bool lastLoadSilent;

  /// Ultimo aggiornamento riuscito (almeno una sezione).
  final DateTime? lastUpdated;
}

/// Carica e aggiorna i dati della dashboard con errori per-sezione.
///
/// Comportamento (parità `dashboard.js`):
/// - le 4 call primarie (`dashboard`, `portafoglio`, `heatmap`, `consigli`)
///   partono in parallelo; una sezione fallita mantiene il render precedente;
/// - i toast di errore sono a carico della pagina, solo per il load non
///   silente (vedi [DashboardState.lastLoadSilent]);
/// - [silentRefresh] non tocca risk metrics né chart (il refresh automatico
///   deve restare leggero); [reload] li invalida perché dati/posizioni sono
///   cambiati.
class DashboardController extends AsyncNotifier<DashboardState> {
  /// Etichette usate nel toast `Dati non aggiornati (...)`.
  static const List<String> _sectionLabels = <String>[
    'riepilogo',
    'portafoglio',
    'heatmap',
    'consigli',
  ];

  @override
  Future<DashboardState> build() => _load(previous: const DashboardState(), silent: false);

  /// Ricarica tutto (usata dopo seed demo o modifiche da scheda titolo):
  /// invalida anche metriche di rischio e grafico.
  Future<void> reload() async {
    ref.invalidate(dashboardRiskProvider);
    ref.invalidate(performanceSeriesProvider);
    ref.invalidate(benchmarksSeriesProvider);
    ref.invalidate(dashboardChartProvider);
    await _refresh(previous: state.value ?? const DashboardState(), silent: false);
  }

  /// Refresh leggero dell'auto-refresh: solo le 4 sezioni primarie, niente
  /// chart/risk, niente toast in caso di errore.
  Future<void> silentRefresh() =>
      _refresh(previous: state.value ?? const DashboardState(), silent: true);

  Future<void> _refresh({required DashboardState previous, required bool silent}) async {
    state = AsyncData(await _load(previous: previous, silent: silent));
  }

  Future<DashboardState> _load({
    required DashboardState previous,
    required bool silent,
  }) async {
    final DashboardApi dashboardApi = ref.read(dashboardApiProvider);
    final PortfolioApi portfolioApi = ref.read(portfolioApiProvider);
    final AdviceApi adviceApi = ref.read(adviceApiProvider);

    final (_Section<DashboardData> summary, _Section<List<Holding>> holdings,
            _Section<List<HeatmapItem>> heatmap, _Section<List<Advice>> advices) =
        await (
      _guard(dashboardApi.dashboard()),
      _guard(portfolioApi.holdings()),
      _guard(dashboardApi.heatmap()),
      _guard(adviceApi.latest()),
    ).wait;

    final List<String> failed = <String>[
      if (summary.error != null) _sectionLabels[0],
      if (holdings.error != null) _sectionLabels[1],
      if (heatmap.error != null) _sectionLabels[2],
      if (advices.error != null) _sectionLabels[3],
    ];

    return DashboardState(
      summary: summary.value?.portfolioSummary ?? previous.summary,
      holdings: holdings.value ?? previous.holdings,
      heatmap: heatmap.value ?? previous.heatmap,
      advices: advices.value ?? previous.advices,
      marketStatus: summary.value?.marketStatus ?? previous.marketStatus,
      failedSections: failed,
      loadCount: previous.loadCount + 1,
      lastLoadSilent: silent,
      lastUpdated:
          failed.length == _sectionLabels.length ? previous.lastUpdated : DateTime.now(),
    );
  }
}

/// Dati della dashboard (stat cards, holdings, heatmap, consigli, mercati).
final dashboardProvider =
    AsyncNotifierProvider<DashboardController, DashboardState>(DashboardController.new);

/// Metriche di rischio a 180 giorni (caricate solo su load completo).
final dashboardRiskProvider = FutureProvider<RiskMetrics>(
  (Ref ref) => ref.watch(portfolioApiProvider).riskMetrics(180),
);

/// Timeframe del grafico andamento, con persistenza.
enum ChartTimeframe {
  /// 7 giorni (`7G`).
  d7(7, '7G'),

  /// 30 giorni (`30G`, default).
  d30(30, '30G'),

  /// 90 giorni (`90G`).
  d90(90, '90G'),

  /// 1 anno (`1A`).
  d365(365, '1A');

  const ChartTimeframe(this.days, this.label);

  /// Giorni passati all'endpoint performance.
  final int days;

  /// Etichetta del selettore.
  final String label;

  /// Converte i giorni salvati nell'enum, con fallback a [d30].
  static ChartTimeframe fromDays(int? days) => values.firstWhere(
        (ChartTimeframe timeframe) => timeframe.days == days,
        orElse: () => ChartTimeframe.d30,
      );
}

/// Benchmark del grafico (come i chip `.bench-chip` del frontend).
enum ChartBenchmark {
  /// [Solo Portafoglio] — vista assoluta in valuta.
  portfolio('Solo Portafoglio'),

  /// [🇺🇸 S&P 500].
  sp500('🇺🇸 S&P 500'),

  /// [🇮🇹 FTSE MIB].
  ftseMib('🇮🇹 FTSE MIB'),

  /// [Entrambi] i benchmark in vista crescita %.
  both('Entrambi');

  const ChartBenchmark(this.label);

  /// Etichetta del chip.
  final String label;
}

/// Persistenza feature-local del timeframe del grafico.
///
/// Usa `shared_preferences` direttamente perché `AppStorage` (interfaccia
/// congelata) non espone chiavi generiche: stessa chiave `dashboard_timeframe`
/// del vecchio `localStorage`, valore = giorni come stringa (`30`).
class DashboardTimeframeStore {
  /// Crea lo store.
  const DashboardTimeframeStore();

  static const String _key = 'dashboard_timeframe';

  /// Legge i giorni salvati; `null` se assenti o storage non disponibile.
  Future<int?> readDays() async {
    try {
      final SharedPreferencesAsync prefs = SharedPreferencesAsync();
      final String? raw = await prefs.getString(_key);
      return raw == null ? null : int.tryParse(raw);
    } catch (_) {
      return null;
    }
  }

  /// Scrive i giorni scelti; gli errori di storage non devono rompere la UI.
  Future<void> writeDays(int days) async {
    try {
      await SharedPreferencesAsync().setString(_key, '$days');
    } catch (_) {
      // Nessuna persistenza disponibile: la selezione resta valida in memoria.
    }
  }
}

/// Controller del timeframe con persistenza (default 30G).
class ChartTimeframeController extends Notifier<ChartTimeframe> {
  /// True quando l'utente ha scelto un timeframe (anche uguale al default).
  bool _userSelected = false;

  @override
  ChartTimeframe build() => ChartTimeframe.d30;

  /// Carica la preferenza salvata. Da chiamare una volta all'apertura pagina.
  ///
  /// Il valore letto viene applicato solo se l'utente non ha già scelto un
  /// timeframe nei primi frame (race tra il tap e la lettura asincrona delle
  /// preferenze: la scelta dell'utente vince sempre).
  Future<void> load() async {
    final int? days = await const DashboardTimeframeStore().readDays();
    if (_userSelected) return;
    state = ChartTimeframe.fromDays(days);
  }

  /// Seleziona il timeframe e lo persiste.
  Future<void> select(ChartTimeframe timeframe) async {
    _userSelected = true;
    if (state == timeframe) return;
    state = timeframe;
    await const DashboardTimeframeStore().writeDays(timeframe.days);
  }
}

/// Timeframe corrente del grafico andamento.
final chartTimeframeProvider =
    NotifierProvider<ChartTimeframeController, ChartTimeframe>(ChartTimeframeController.new);

/// Controller del benchmark selezionato (non persistito, come il frontend).
class ChartBenchmarkController extends Notifier<ChartBenchmark> {
  @override
  ChartBenchmark build() => ChartBenchmark.portfolio;

  /// Seleziona il benchmark.
  void select(ChartBenchmark benchmark) => state = benchmark;
}

/// Benchmark corrente del grafico.
final chartBenchmarkProvider =
    NotifierProvider<ChartBenchmarkController, ChartBenchmark>(ChartBenchmarkController.new);

/// Serie del grafico andamento già pronte per il rendering.
@immutable
class DashboardChartData {
  /// Crea i dati del grafico.
  const DashboardChartData({required this.performance, this.benchmarks});

  /// Serie assoluta del portafoglio (`{date,value}`).
  final PerformanceSeries performance;

  /// Portafoglio normalizzato + benchmark (presente solo con un benchmark attivo).
  final BenchmarksResult? benchmarks;
}

/// Serie performance del portafoglio per un orizzonte, cache per `days`.
///
/// Separata dal benchmark: cambiare chip benchmark non rifà la call
/// `/dashboard/performance` (era un refetch inutile a ogni cambio chip).
final performanceSeriesProvider =
    FutureProvider.family<PerformanceSeries, int>((Ref ref, int days) {
  return ref.watch(dashboardApiProvider).performance(days);
});

/// Portafoglio normalizzato + benchmark per un orizzonte, cache per `days`.
///
/// In errore restituisce `null` invece di propagarlo: il grafico resta sulla
/// vista assoluta (performance) e [PortfolioChart] mostra la nota discreta
/// `Benchmark non disponibili`. Il risultato viene invalidato da
/// [DashboardController.reload] per ritentare al prossimo load completo.
final benchmarksSeriesProvider =
    FutureProvider.family<BenchmarksResult?, int>((Ref ref, int days) async {
  try {
    return await ref.watch(portfolioApiProvider).benchmarks(days);
  } catch (_) {
    return null;
  }
});

/// Carica il grafico per timeframe e benchmark correnti.
///
/// Con `Solo Portafoglio` usa solo la performance (cachata); con un benchmark
/// attende anche i dati normalizzati (cachati o `null` in errore). I cambi di
/// timeframe/benchmark rifanno partire questo provider, ma le due call di rete
/// restano separate e cachate per `days`.
final dashboardChartProvider = FutureProvider<DashboardChartData>((Ref ref) async {
  final ChartTimeframe timeframe = ref.watch(chartTimeframeProvider);
  final ChartBenchmark benchmark = ref.watch(chartBenchmarkProvider);

  final PerformanceSeries performance =
      await ref.watch(performanceSeriesProvider(timeframe.days).future);
  if (benchmark == ChartBenchmark.portfolio) {
    return DashboardChartData(performance: performance);
  }

  final BenchmarksResult? benchmarks =
      await ref.watch(benchmarksSeriesProvider(timeframe.days).future);
  return DashboardChartData(performance: performance, benchmarks: benchmarks);
});

class _Section<T> {
  const _Section({this.value, this.error});

  final T? value;
  final Object? error;
}

Future<_Section<T>> _guard<T>(Future<T> future) async {
  try {
    return _Section<T>(value: await future);
  } catch (error) {
    return _Section<T>(error: error);
  }
}
