import { api } from './api.js?v=3.0.0';
import { formatCurrency, formatPercent, showLoading, hideLoading, showToast, getChartThemeColors, CHART_FONT_FAMILY, escapeHtml } from './app.js?v=3.0.0';

let chart = null;
let lineSeries = null;
let candleSeries = null;
let volumeSeries = null;
let resizeObserver = null;
let currentChartDays = parseInt(localStorage.getItem('dashboard_timeframe')) || 30;
let currentChartType = 'area';
let benchSeriesMap = {};
let activeBenchmark = 'none';
let performanceRawData = [];
let performanceRequestId = 0;
let benchmarkRequestId = 0;
let dashboardHasLoaded = false;

// Helper: bandiera mercato (IT→🇮🇹, EU→🇪🇺, resto→🇺🇸). Niente default USA per l'Europa.
const marketFlag = (market) => {
  const m = (market || '').toUpperCase();
  if (m === 'IT') return '🇮🇹';
  if (m === 'EU') return '🇪🇺';
  return '🇺🇸';
};

// Helper B1: estrae un array di punti {date, value} da un nodo benchmark che
// può essere array diretto oppure oggetto {name, flag, data:[...]} (shape API),
// mai crash su .map con rete stale/forme inattese.
const toPointArray = (node) => {
  if (Array.isArray(node)) return node;
  if (node && Array.isArray(node.data)) return node.data;
  return [];
};

const renderSkeletons = () => {
  const statGrid = document.querySelector('.stat-grid');
  if (statGrid) {
    const valEls = statGrid.querySelectorAll('.stat-value');
    valEls.forEach(el => {
      el.innerHTML = '<div class="skeleton skeleton-value"></div>';
    });
  }

  const tbody = document.getElementById('holdingsTableBody');
  if (tbody) {
    tbody.innerHTML = `
      <tr><td colspan="7"><div class="skeleton skeleton-row"></div></td></tr>
      <tr><td colspan="7"><div class="skeleton skeleton-row"></div></td></tr>
      <tr><td colspan="7"><div class="skeleton skeleton-row"></div></td></tr>
    `;
  }

  const heatmap = document.getElementById('marketHeatmap');
  if (heatmap) {
    heatmap.innerHTML = `
      <div class="skeleton skeleton-card"></div>
      <div class="skeleton skeleton-card"></div>
      <div class="skeleton skeleton-card"></div>
      <div class="skeleton skeleton-card"></div>
    `;
  }
};

const initChart = () => {
  const chartContainer = document.getElementById('portfolioChart');
  if (!chartContainer || typeof LightweightCharts === 'undefined') return;
  
  if (chart) {
    try { chart.remove(); } catch(e){}
  }

  const themeColors = getChartThemeColors();

  chart = LightweightCharts.createChart(chartContainer, {
    layout: {
      background: { type: 'solid', color: 'transparent' },
      textColor: themeColors.textColor,
      fontFamily: CHART_FONT_FAMILY,
      fontSize: 12
    },
    grid: {
      vertLines: { color: themeColors.gridColor },
      horzLines: { color: themeColors.gridColor },
    },
    rightPriceScale: {
      borderVisible: false,
      scaleMargins: { top: 0.1, bottom: 0.25 }
    },
    timeScale: {
      borderVisible: false,
      fixLeftEdge: true,
      fixRightEdge: true
    },
    crosshair: {
      vertLine: { color: themeColors.lineColor, width: 1, style: 3 },
      horzLine: { color: themeColors.lineColor, width: 1, style: 3 }
    }
  });

  lineSeries = chart.addAreaSeries({
    topColor: themeColors.topColor,
    bottomColor: themeColors.bottomColor,
    lineColor: themeColors.lineColor,
    lineWidth: 2,
    crosshairMarkerVisible: true,
  });

  candleSeries = chart.addCandlestickSeries({
    upColor: themeColors.upColor,
    downColor: themeColors.downColor,
    borderUpColor: themeColors.upColor,
    borderDownColor: themeColors.downColor,
    wickUpColor: themeColors.upColor,
    wickDownColor: themeColors.downColor,
    visible: false
  });

  volumeSeries = chart.addHistogramSeries({
    color: themeColors.volumeColor,
    priceFormat: { type: 'volume' },
    priceScaleId: ''
  });
  volumeSeries.priceScale().applyOptions({ scaleMargins: { top: 0.8, bottom: 0 } });

  // Benchmark series
  benchSeriesMap['^GSPC'] = chart.addLineSeries({
    color: themeColors.benchmarkSp,
    lineWidth: 2,
    priceLineVisible: false,
    lastValueVisible: true,
    crosshairMarkerVisible: false,
    visible: false
  });

  benchSeriesMap['FTSEMIB.MI'] = chart.addLineSeries({
    color: themeColors.benchmarkMib,
    lineWidth: 2,
    priceLineVisible: false,
    lastValueVisible: true,
    crosshairMarkerVisible: false,
    visible: false
  });

  if (window.ResizeObserver) {
    if (resizeObserver) {
      try { resizeObserver.disconnect(); } catch(e){}
    }
    resizeObserver = new ResizeObserver(entries => {
      for (const entry of entries) {
        const width = entry.contentRect.width;
        if (width > 0 && chart) {
          // Legge l'altezza PRIMA di applyOptions per evitare read-after-write layout thrash
          const height = chartContainer.clientHeight || 340;
          chart.applyOptions({ width, height });
        }
      }
    });
    resizeObserver.observe(chartContainer);
  }
};

const updateChartTheme = () => {
  if (!chart) return;
  const themeColors = getChartThemeColors();
  chart.applyOptions({
    layout: { textColor: themeColors.textColor },
    grid: {
      vertLines: { color: themeColors.gridColor },
      horzLines: { color: themeColors.gridColor }
    },
    crosshair: {
      vertLine: { color: themeColors.lineColor },
      horzLine: { color: themeColors.lineColor }
    }
  });
  lineSeries?.applyOptions({
    topColor: themeColors.topColor,
    bottomColor: themeColors.bottomColor,
    lineColor: themeColors.lineColor
  });
  candleSeries?.applyOptions({
    upColor: themeColors.upColor,
    downColor: themeColors.downColor,
    borderUpColor: themeColors.upColor,
    borderDownColor: themeColors.downColor,
    wickUpColor: themeColors.upColor,
    wickDownColor: themeColors.downColor
  });
  volumeSeries?.applyOptions({ color: themeColors.volumeColor });
  benchSeriesMap['^GSPC']?.applyOptions({ color: themeColors.benchmarkSp });
  benchSeriesMap['FTSEMIB.MI']?.applyOptions({ color: themeColors.benchmarkMib });
  if (performanceRawData.length > 0) applyChartData();
  // H4b: con un benchmark attivo il theme change non deve riportare
  // permanentemente alla vista assoluta in EUR appena ridisegnata.
  if (activeBenchmark !== 'none') refreshBenchmarks();
};

const applyChartData = () => {
  if (!chart || performanceRawData.length === 0) return;

  if (currentChartType === 'candles') {
    lineSeries.applyOptions({ visible: false });
    candleSeries.applyOptions({ visible: true });
    candleSeries.setData(performanceRawData.map(d => ({
      time: d.date,
      open: d.open || (d.value * 0.995),
      high: d.high || (d.value * 1.008),
      low: d.low || (d.value * 0.992),
      close: d.value
    })));
  } else {
    candleSeries.applyOptions({ visible: false });
    lineSeries.applyOptions({ visible: true });
    lineSeries.setData(performanceRawData.map(d => ({ time: d.date, value: d.value })));
  }

  const volumeColors = getChartThemeColors();
  volumeSeries.setData(performanceRawData.map((d, i) => ({
    time: d.date,
    value: d.volume || (d.value * 50),
    color: i > 0 && d.value >= performanceRawData[i-1].value ? volumeColors.volumeUp : volumeColors.volumeDown
  })));

  chart.timeScale().fitContent();
};

const updateMarketStatus = (statusData = null) => {
  const mibEl = document.getElementById('statusMib');
  const usEl = document.getElementById('statusUs');
  
  const itOpen = statusData?.IT === 'OPEN' || (new Date().getDay() >= 1 && new Date().getDay() <= 5 && new Date().getHours() >= 9 && new Date().getHours() < 18);
  const usOpen = statusData?.US === 'OPEN' || (new Date().getDay() >= 1 && new Date().getDay() <= 5 && new Date().getHours() >= 15 && new Date().getHours() < 22);

  if (mibEl) {
    mibEl.className = `status-dot ${itOpen ? 'open' : 'closed'}`;
    mibEl.title = itOpen ? 'Borsa Italiana: Aperta (09:00 - 17:30)' : 'Borsa Italiana: Chiusa (09:00 - 17:30)';
  }
  if (usEl) {
    usEl.className = `status-dot ${usOpen ? 'open' : 'closed'}`;
    usEl.title = usOpen ? 'Wall Street: Aperta (15:30 - 22:00)' : 'Wall Street: Chiusa (15:30 - 22:00)';
  }
};

const renderHeatmap = (items) => {
  const container = document.getElementById('marketHeatmap');
  if (!container) return;

  if (!items || items.length === 0) {
    container.innerHTML = `
      <div class="text-muted text-xs py-6 text-center span-full">
        Nessun titolo attivo per la heatmap. 
        <button class="btn btn-primary btn-sm mt-2" id="btnHeatmapSeedDemo" data-action="seed-demo">🚀 Inizializza Dati Demo</button>
      </div>
    `;
    return;
  }

  container.innerHTML = items.map(item => {
    const chg = Number(item.change_percent) || 0;
    let tileClass = 'tile-neutral';
    if (chg >= 3.0) tileClass = 'tile-gain-high';
    else if (chg >= 1.0) tileClass = 'tile-gain-mid';
    else if (chg > 0.0) tileClass = 'tile-gain-low';
    else if (chg <= -3.0) tileClass = 'tile-loss-high';
    else if (chg <= -1.0) tileClass = 'tile-loss-mid';
    else if (chg < 0.0) tileClass = 'tile-loss-low';

    const isUp = chg >= 0;
    const sign = isUp ? '+' : '';
    const flag = marketFlag(item.market);

    return `
      <div class="heatmap-tile ${tileClass}" data-stock="${escapeHtml(item.ticker)}">
        <div class="flex justify-between items-center mb-1">
          <span class="font-bold text-primary font-mono text-sm">${escapeHtml(item.ticker)}</span>
          <span class="text-xs">${flag}</span>
        </div>
        <div class="text-xs text-secondary mb-1 tile-name">${escapeHtml(item.name || item.ticker)}</div>
        <div class="flex justify-between items-end">
          <span class="text-xs font-mono font-bold">${formatCurrency(item.current_price, item.currency)}</span>
          <span class="text-xs font-mono font-bold ${isUp ? 'text-profit' : 'text-loss'}">${sign}${chg.toFixed(2)}%</span>
        </div>
      </div>
    `;
  }).join('');
};

const triggerSeedDemo = async () => {
  try {
    showLoading('dashboardContent');
    const res = await api.seedDemo();
    showToast(res.message || 'Demo caricata con successo!', 'success');
    await loadDashboardData();
  } catch (e) {
    showToast(e.message || 'Errore nel caricamento della demo', 'error');
  } finally {
    hideLoading('dashboardContent');
  }
};

const loadPerformanceChart = async (days = 30, silent = false) => {
  if (!chart) return true;
  const requestId = ++performanceRequestId;
  try {
    const performance = await api.getPerformance(days);
    // M6: scarta la risposta se nel frattempo è partita una richiesta più recente
    // (click rapidi 7G→1A), così un dato vecchio non sovrascrive quello nuovo.
    if (requestId !== performanceRequestId) return true;
    if (performance && performance.data && performance.data.length > 0) {
      performanceRawData = performance.data;
      applyChartData();
      // H4b: il write assoluto appena fatto clobbererebbe la vista % del
      // benchmark attivo; la riapplica (token-guarded) dopo di esso.
      if (activeBenchmark !== 'none') refreshBenchmarks();
    }
    return true;
  } catch (e) {
    console.error('Errore storico performance:', e);
    if (requestId === performanceRequestId && !silent) {
      showToast('Impossibile aggiornare il grafico performance', 'error');
    }
    return false;
  }
};

// H4: (ri)carica i benchmark per l'orizzonte corrente con token anti-race.
// Usato sia dai chip benchmark sia al cambio timeframe con benchmark attivo.
const refreshBenchmarks = async () => {
  const requestedBenchmark = activeBenchmark;
  const requestId = ++benchmarkRequestId;

  if (requestedBenchmark === 'none') {
    benchSeriesMap['^GSPC']?.applyOptions({ visible: false });
    benchSeriesMap['^GSPC']?.setData([]);
    benchSeriesMap['FTSEMIB.MI']?.applyOptions({ visible: false });
    benchSeriesMap['FTSEMIB.MI']?.setData([]);
    // Torna alla vista assoluta in EUR (linea/candele + volumi).
    applyChartData();
    return;
  }

  try {
    const benchData = await api.getBenchmarks(currentChartDays);
    // Scarta risposte obsolete: vale solo l'ultima richiesta e solo se il
    // benchmark selezionato non è cambiato nel frattempo.
    if (requestId !== benchmarkRequestId || requestedBenchmark !== activeBenchmark) return;

    const portfolioPoints = Array.isArray(benchData?.portfolio)
      ? benchData.portfolio.map(p => ({ time: p.date, value: p.growth_pct }))
      : [];

    if (portfolioPoints.length === 0) {
      // Nessun dato portfolio in %: fallback alla vista assoluta, senza crash.
      benchSeriesMap['^GSPC']?.applyOptions({ visible: false });
      benchSeriesMap['^GSPC']?.setData([]);
      benchSeriesMap['FTSEMIB.MI']?.applyOptions({ visible: false });
      benchSeriesMap['FTSEMIB.MI']?.setData([]);
      applyChartData();
      return;
    }

    // Confronto in crescita %: la linea principale è il portafoglio
    // normalizzato; candele e volumi non hanno senso sulla scala %.
    lineSeries?.applyOptions({ visible: true });
    lineSeries?.setData(portfolioPoints);
    candleSeries?.applyOptions({ visible: false });
    volumeSeries?.setData([]);

    if (requestedBenchmark === '^GSPC' || requestedBenchmark === 'both') {
      const spData = toPointArray(benchData?.benchmarks?.['^GSPC']);
      benchSeriesMap['^GSPC']?.applyOptions({ visible: true });
      benchSeriesMap['^GSPC']?.setData(spData.map(p => ({ time: p.date, value: p.growth_pct })));
    } else {
      benchSeriesMap['^GSPC']?.applyOptions({ visible: false });
      benchSeriesMap['^GSPC']?.setData([]);
    }

    if (requestedBenchmark === 'FTSEMIB.MI' || requestedBenchmark === 'both') {
      const mibData = toPointArray(benchData?.benchmarks?.['FTSEMIB.MI']);
      benchSeriesMap['FTSEMIB.MI']?.applyOptions({ visible: true });
      benchSeriesMap['FTSEMIB.MI']?.setData(mibData.map(p => ({ time: p.date, value: p.growth_pct })));
    } else {
      benchSeriesMap['FTSEMIB.MI']?.applyOptions({ visible: false });
      benchSeriesMap['FTSEMIB.MI']?.setData([]);
    }

    chart?.timeScale().fitContent();
  } catch (e) {
    console.error('Errore benchmark:', e);
    // Solo la richiesta corrente tocca il DOM: un errore stale non deve
    // sovrascrivere una vista benchmark più recente.
    if (requestId !== benchmarkRequestId || requestedBenchmark !== activeBenchmark) return;
    // Errore: niente overlay rotti, si torna alla vista assoluta.
    benchSeriesMap['^GSPC']?.applyOptions({ visible: false });
    benchSeriesMap['^GSPC']?.setData([]);
    benchSeriesMap['FTSEMIB.MI']?.applyOptions({ visible: false });
    benchSeriesMap['FTSEMIB.MI']?.setData([]);
    applyChartData();
  }
};

const loadRiskMetrics = async () => {
  const container = document.getElementById('riskMetricsRow');
  if (!container) return;

  try {
    const metrics = await api.getRiskMetrics(180);
    if (!metrics || Object.keys(metrics).length === 0) {
      container.innerHTML = '<div class="text-muted text-xs py-2 text-center span-full">Metriche calcolate dopo l\'inserimento di posizioni storiche.</div>';
      return;
    }

    // P0.4: l'API espone le chiavi con suffisso _pct; fallback ai vecchi nomi
    // e coercizione numerica per non stampare NaN su payload inattesi.
    const maxDrawdown = Number(metrics.max_drawdown_pct ?? metrics.max_drawdown ?? 0) || 0;
    const annualizedVolatility = Number(metrics.annualized_volatility_pct ?? metrics.annualized_volatility ?? 0) || 0;
    const sharpeRatio = Number(metrics.sharpe_ratio ?? 0) || 0;
    const weightedBetaRaw = Number(metrics.weighted_beta);
    const weightedBeta = Number.isFinite(weightedBetaRaw) ? weightedBetaRaw : 1.0;

    container.innerHTML = `
      <div class="stat-card card-subtle p-3">
        <div class="text-xs text-muted">Max Drawdown</div>
        <div class="text-lg font-bold font-mono text-loss mt-1">${formatPercent(maxDrawdown)}</div>
        <div class="text-2xs text-muted mt-0.5">Picco-minimo</div>
      </div>
      <div class="stat-card card-subtle p-3">
        <div class="text-xs text-muted">Volatilità Annua</div>
        <div class="text-lg font-bold font-mono text-primary mt-1">${annualizedVolatility.toFixed(1)}%</div>
        <div class="text-2xs text-muted mt-0.5">Deviazione std</div>
      </div>
      <div class="stat-card card-subtle p-3">
        <div class="text-xs text-muted">Sharpe Ratio</div>
        <div class="text-lg font-bold font-mono ${sharpeRatio >= 1 ? 'text-profit' : 'text-primary'} mt-1">${sharpeRatio.toFixed(2)}</div>
        <div class="text-2xs text-muted mt-0.5">Rendimento / Rischio</div>
      </div>
      <div class="stat-card card-subtle p-3">
        <div class="text-xs text-muted">Beta Pesato</div>
        <div class="text-lg font-bold font-mono text-primary mt-1">${weightedBeta.toFixed(2)}</div>
        <div class="text-2xs text-muted mt-0.5">Sensibilità mercato</div>
      </div>
    `;
  } catch (e) {
    console.error('Errore metriche rischio:', e);
    // M11: in errore non si azzerano le metriche già mostrate; si ripulisce
    // solo lo skeleton del primo caricamento.
    if (container.querySelector('.skeleton')) {
      container.innerHTML = '<div class="text-muted text-xs py-2 text-center span-full">Metriche non disponibili al momento.</div>';
    }
  }
};

// F1: pulisce gli skeleton del primo load. Se una call primaria è fallita non
// si mostrano stati "vuoti" finti (0,00 € / "Nessun titolo...") ma l'indisponibilità.
const clearSkeletons = (failed = {}) => {
  const unavailable = 'Dati non disponibili';

  const statTotal = document.getElementById('statTotalValue');
  if (statTotal && statTotal.querySelector('.skeleton')) statTotal.textContent = failed.dash ? unavailable : '0,00 €';
  
  const dailyEl = document.getElementById('statDailyPnL');
  if (dailyEl && dailyEl.querySelector('.skeleton')) dailyEl.textContent = failed.dash ? unavailable : '0,00 € (+0.00%)';
  
  const totalEl = document.getElementById('statTotalPnL');
  if (totalEl && totalEl.querySelector('.skeleton')) totalEl.textContent = failed.dash ? unavailable : '0,00 € (+0.00%)';
  
  const divEl = document.getElementById('statDividends');
  if (divEl && divEl.querySelector('.skeleton')) divEl.textContent = failed.dash ? unavailable : '0,00 €/anno';
  
  const tgEl = document.getElementById('statTopGainer');
  if (tgEl && tgEl.querySelector('.skeleton')) tgEl.textContent = '--';

  const riskRow = document.getElementById('riskMetricsRow');
  if (riskRow && riskRow.querySelector('.skeleton')) {
    riskRow.innerHTML = '<div class="text-muted text-xs py-2 text-center span-full">Metriche calcolate dopo l\'inserimento di posizioni nel portafoglio.</div>';
  }

  const recentAdv = document.getElementById('recentAdviceList');
  if (recentAdv && recentAdv.textContent.includes('Caricamento')) {
    recentAdv.innerHTML = failed.advice
      ? '<div class="text-center text-muted py-4 text-xs">Dati non disponibili.</div>'
      : '<div class="text-center text-muted py-4 text-xs">Nessuna analisi recente.</div>';
  }

  const heatmap = document.getElementById('marketHeatmap');
  if (heatmap && (heatmap.querySelector('.skeleton') || heatmap.textContent.includes('Caricamento'))) {
    if (failed.heatmap) {
      heatmap.innerHTML = '<div class="text-muted text-xs py-6 text-center span-full">Dati non disponibili.</div>';
    } else {
      renderHeatmap([]);
    }
  }

  const tbody = document.getElementById('holdingsTableBody');
  if (tbody && (tbody.querySelector('.skeleton') || tbody.textContent.includes('Caricamento'))) {
    if (failed.portfolio) {
      tbody.innerHTML = `
        <tr>
          <td colspan="7" class="text-center text-muted py-6">Dati non disponibili.</td>
        </tr>
      `;
    } else {
      tbody.innerHTML = `
        <tr>
          <td colspan="7" class="text-center text-muted py-6">
            Nessun titolo nel portafoglio.
            <div class="mt-2 flex justify-center gap-2">
              <a href="/static/portfolio.html" class="btn btn-primary btn-sm">➕ Aggiungi Holding</a>
              <button class="btn btn-ghost btn-sm" id="btnTableSeedDemoFallback" data-action="seed-demo">🚀 Prova Demo</button>
            </div>
          </td>
        </tr>
      `;
    }
  }
};

const loadDashboardData = async (isSilentRefresh = false) => {
  try {
    if (!isSilentRefresh && !dashboardHasLoaded) {
      renderSkeletons();
    }
    
    // M11: niente fallback vuoti che mascherano le outage. Ogni call traccia
    // esito e dato; in caso di errore si mantiene quanto già renderizzato.
    const settle = (promise) => promise.then(
      data => ({ ok: true, data }),
      error => ({ ok: false, error })
    );

    const [dashRes, portfolioRes, heatmapRes, adviceRes] = await Promise.all([
      settle(api.getDashboard()),
      // getDashboard restituisce solo il summary aggregato (niente righe holdings):
      // la tabella qui sotto richiede la lista completa, quindi la call resta necessaria.
      settle(api.getPortfolio()),
      settle(api.getHeatmap()),
      settle(api.getLatestAdvice())
    ]);

    const dashFailed = !dashRes.ok;
    const heatmapFailed = !heatmapRes.ok;
    const dashData = dashRes.ok ? dashRes.data : null;
    const summary = (dashData && dashData.portfolio_summary) ? dashData.portfolio_summary : {};
    const portfolio = (portfolioRes.ok && Array.isArray(portfolioRes.data)) ? portfolioRes.data : null;
    const heatmap = (heatmapRes.ok && Array.isArray(heatmapRes.data)) ? heatmapRes.data : null;
    const advice = (adviceRes.ok && Array.isArray(adviceRes.data)) ? adviceRes.data : null;

    // 1. Stat Cards (M11: se il summary fallisce non si azzera nulla)
    if (!dashFailed) {
      const totalValEl = document.getElementById('statTotalValue');
      if (totalValEl) totalValEl.textContent = formatCurrency(summary.total_value || 0);

      const dailyEl = document.getElementById('statDailyPnL');
      if (dailyEl) {
        const dPnL = summary.daily_pnl || 0;
        const dPct = summary.daily_pnl_percent || 0;
        dailyEl.textContent = `${formatCurrency(dPnL)} (${formatPercent(dPct)})`;
        dailyEl.className = `stat-value font-mono ${dPnL >= 0 ? 'text-profit' : 'text-loss'}`;
      }

      const totalEl = document.getElementById('statTotalPnL');
      if (totalEl) {
        const tPnL = summary.total_pnl || 0;
        const tPct = summary.total_pnl_percent || 0;
        totalEl.textContent = `${formatCurrency(tPnL)} (${formatPercent(tPct)})`;
        totalEl.className = `stat-value font-mono ${tPnL >= 0 ? 'text-profit' : 'text-loss'}`;
      }

      // Dividends
      const divEl = document.getElementById('statDividends');
      if (divEl) divEl.textContent = `${formatCurrency(summary.estimated_annual_dividends || 0)}/anno`;
      const divYieldEl = document.getElementById('statDividendYield');
      if (divYieldEl) divYieldEl.textContent = `Yield Stimato: ${(Number(summary.estimated_dividend_yield) || 0).toFixed(2)}%`;

      if (isSilentRefresh && window.flashPriceChange) {
        if (totalValEl) window.flashPriceChange(totalValEl, (summary.daily_pnl || 0) >= 0);
        if (dailyEl) window.flashPriceChange(dailyEl, (summary.daily_pnl || 0) >= 0);
        if (totalEl) window.flashPriceChange(totalEl, (summary.total_pnl || 0) >= 0);
      }

      // Top Gainer
      const tgEl = document.getElementById('statTopGainer');
      const tgDescEl = document.getElementById('statTopGainerDesc');
      if (tgEl && summary.top_gainer) {
        tgEl.textContent = `${summary.top_gainer.ticker} (${formatPercent(summary.top_gainer.pnl_percent)})`;
        if (tgDescEl) tgDescEl.textContent = `P&L Netto: ${formatCurrency(summary.top_gainer.pnl_absolute)}`;
      } else if (tgEl) {
        tgEl.textContent = '--';
        if (tgDescEl) tgDescEl.textContent = 'Nessuna posizione in utile';
      }
    }

    // 2. Chart & Risk (solo su load manuale/cambio timeframe: il refresh
    //    automatico silente li salta per non pesare sul server ogni ciclo)
    if (!isSilentRefresh) {
      await loadPerformanceChart(currentChartDays);
      loadRiskMetrics().catch(err => console.debug('Risk error:', err));
    }

    // 3. Heatmap (mantiene quella precedente se la call è fallita)
    if (heatmap !== null) renderHeatmap(heatmap);

    // 4. Holdings Table
    const tbody = document.getElementById('holdingsTableBody');
    if (tbody && portfolio !== null) {
      if (portfolio.length === 0) {
        tbody.innerHTML = `
          <tr>
            <td colspan="7" class="text-center text-muted py-6">
              Nessun titolo nel portafoglio. 
              <div class="mt-2 flex justify-center gap-2">
                <a href="/static/portfolio.html" class="btn btn-primary btn-sm">➕ Aggiungi Holding</a>
                <button class="btn btn-ghost btn-sm" id="btnTableSeedDemo" data-action="seed-demo">🚀 Prova Demo</button>
              </div>
            </td>
          </tr>
        `;
      } else {
        tbody.innerHTML = portfolio.slice(0, 6).map(item => {
          const pnl = item.pnl_absolute ?? 0;
          const pnlPct = item.pnl_percent ?? 0;
          const curPrice = item.current_price ?? item.avg_purchase_price ?? 0;
          const totalVal = item.total_value ?? (item.quantity * curPrice);
          const flag = marketFlag(item.market);

          return `
            <tr>
              <td>
                <div class="flex items-center gap-2">
                  <span>${flag}</span>
                  <div>
                    <a href="#" class="stock-ticker-link font-bold font-mono" data-stock="${escapeHtml(item.ticker)}">${escapeHtml(item.ticker)}</a>
                    <div class="text-xs text-secondary">${escapeHtml(item.name || item.ticker)}</div>
                  </div>
                </div>
              </td>
              <td class="text-right font-mono font-bold">${item.quantity}</td>
              <td class="text-right font-mono font-bold">${formatCurrency(curPrice, item.currency)}</td>
              <td class="text-right font-mono font-bold text-primary">${formatCurrency(totalVal, item.currency)}</td>
              <td class="text-right font-mono font-bold ${pnl >= 0 ? 'text-profit' : 'text-loss'}">
                ${formatCurrency(pnl, item.currency)}
              </td>
              <td class="text-right font-mono font-bold ${pnlPct >= 0 ? 'text-profit' : 'text-loss'}">
                ${formatPercent(pnlPct)}
              </td>
              <td class="text-center">
                <button class="btn btn-ghost btn-sm" data-stock="${escapeHtml(item.ticker)}" title="Apri scheda completa">
                  🔍
                </button>
              </td>
            </tr>
          `;
        }).join('');
      }
    }

    // 5. Recent Advice
    const adviceList = document.getElementById('recentAdviceList');
    if (adviceList && advice !== null) {
      if (advice.length === 0) {
        adviceList.innerHTML = '<div class="text-center text-muted py-6 text-xs">Nessuna analisi recente. Generane una nella sezione Consigli.</div>';
      } else {
        adviceList.innerHTML = advice.slice(0, 2).map(adv => {
          const isIT = adv.market === 'IT';
          const flag = isIT ? '🇮🇹' : '🇺🇸';
          const action = (adv.action || 'HOLD').toUpperCase();
          let badgeClass = 'badge-hold';
          if (action.includes('ACCUMULO') || action.includes('BUY')) badgeClass = 'badge-buy';
          else if (action.includes('PROFITTO') || action.includes('SELL')) badgeClass = 'badge-sell';

          return `
            <div class="card card-subtle p-3">
              <div class="flex justify-between items-center mb-1.5">
                <span class="font-bold text-primary flex items-center gap-1.5 text-sm">
                  <span>${flag}</span>
                  <span>${escapeHtml(adv.title || (isIT ? 'Borsa Italiana' : 'Wall Street'))}</span>
                </span>
                <span class="badge ${badgeClass}">${escapeHtml(action)}</span>
              </div>
              <p class="text-xs text-secondary leading-relaxed clamp-2">
                ${escapeHtml(adv.overview || adv.strategy || 'Nessuna descrizione disponibile.')}
              </p>
            </div>
          `;
        }).join('');
      }
    }

    // 6. Market status (dal summary; se fallito si mantiene quello precedente)
    if (dashData) {
      if (dashData.market_status) updateMarketStatus(dashData.market_status);
      else updateMarketStatus();
    }

    // M11/F1: le outage delle call primarie vengono segnalate solo sul load non
    // silente; i dati già mostrati restano intatti (skeleton ripuliti). Sul primo
    // load le sezioni fallite mostrano "Dati non disponibili" senza stati vuoti finti.
    if (!isSilentRefresh && (!dashRes.ok || !portfolioRes.ok || !heatmapRes.ok || !adviceRes.ok)) {
      const failedNames = [];
      if (dashFailed) failedNames.push('riepilogo');
      if (!portfolioRes.ok) failedNames.push('portafoglio');
      if (heatmapFailed) failedNames.push('heatmap');
      if (!adviceRes.ok) failedNames.push('consigli');
      clearSkeletons({ dash: dashFailed, portfolio: !portfolioRes.ok, heatmap: heatmapFailed, advice: !adviceRes.ok });
      showToast(`Dati non aggiornati (${failedNames.join(', ')}). Riprova più tardi.`, 'error');
    }

    dashboardHasLoaded = true;

  } catch (error) {
    clearSkeletons();
    if (!isSilentRefresh) {
      showToast('Errore nel caricamento della dashboard', 'error');
    }
    console.error('Errore dashboard:', error);
  }
};

const initDashboard = () => {
  initChart();
  loadDashboardData();

  // Empty-state seed buttons are re-rendered on every load: ONE delegated
  // listener on the stable container instead of re-binding per render.
  const dashboardContent = document.getElementById('dashboardContent');
  if (dashboardContent) {
    dashboardContent.addEventListener('click', (e) => {
      if (e.target.closest('[data-action="seed-demo"]')) {
        triggerSeedDemo();
      }
    });
  }

  // Listen for theme change
  window.addEventListener('themeChanged', () => {
    updateChartTheme();
  });

  // Timeframe selector with persistence
  const tfGroup = document.getElementById('dashboardTimeframeGroup');
  if (tfGroup) {
    tfGroup.querySelectorAll('.timeframe-btn').forEach(btn => {
      const d = parseInt(btn.dataset.days);
      if (d === currentChartDays) {
        tfGroup.querySelectorAll('.timeframe-btn').forEach(b => {
          b.classList.remove('active');
          b.setAttribute('aria-pressed', 'false');
        });
        btn.classList.add('active');
        btn.setAttribute('aria-pressed', 'true');
      }

      btn.addEventListener('click', () => {
        tfGroup.querySelectorAll('.timeframe-btn').forEach(b => {
          b.classList.remove('active');
          b.setAttribute('aria-pressed', 'false');
        });
        btn.classList.add('active');
        btn.setAttribute('aria-pressed', 'true');
        currentChartDays = parseInt(btn.dataset.days) || 30;
        localStorage.setItem('dashboard_timeframe', currentChartDays);
        loadPerformanceChart(currentChartDays);
        // H4b: il benchmark attivo va riallineato al nuovo orizzonte temporale.
        if (activeBenchmark !== 'none') refreshBenchmarks();
      });
    });
  }

  // Chart type switcher
  const chartTypeGroup = document.getElementById('chartTypeGroup');
  if (chartTypeGroup) {
    chartTypeGroup.querySelectorAll('.chart-type-btn').forEach(btn => {
      btn.addEventListener('click', () => {
        chartTypeGroup.querySelectorAll('.chart-type-btn').forEach(b => {
          b.classList.remove('active');
          b.setAttribute('aria-pressed', 'false');
        });
        btn.classList.add('active');
        btn.setAttribute('aria-pressed', 'true');
        currentChartType = btn.dataset.type;
        applyChartData();
        // Con un benchmark attivo applyChartData riporta la vista assoluta:
        // riapplica subito la vista % per mantenere coerente il confronto.
        if (activeBenchmark !== 'none') refreshBenchmarks();
      });
    });
  }

  // Benchmark switcher
  const benchChips = document.getElementById('benchmarkChips');
  if (benchChips) {
    benchChips.querySelectorAll('.bench-chip').forEach(chip => {
      chip.addEventListener('click', () => {
        benchChips.querySelectorAll('.bench-chip').forEach(c => {
          c.classList.remove('active');
          c.setAttribute('aria-pressed', 'false');
        });
        chip.classList.add('active');
        chip.setAttribute('aria-pressed', 'true');
        activeBenchmark = chip.dataset.bench;
        refreshBenchmarks();
      });
    });
  }

  // Auto-refresh ogni 180s (solo dati leggeri: il ciclo silente salta
  // performance e risk-metrics, restano su load manuale/cambio timeframe)
  let refreshTimer = null;
  let refreshing = false;
  refreshTimer = setInterval(async () => {
    if (document.hidden || refreshing) return;
    refreshing = true;
    try {
      await loadDashboardData(true);
    } finally {
      refreshing = false;
    }
  }, 180000);

  // Cleanup su pagehide: stop polling, ResizeObserver e chart.
  // Skip se la pagina entra in bfcache (persisted): verrà ripristinata intatta.
  const teardown = (event) => {
    if (event && event.persisted) return;
    if (refreshTimer) {
      clearInterval(refreshTimer);
      refreshTimer = null;
    }
    if (resizeObserver) {
      try { resizeObserver.disconnect(); } catch (err) {}
      resizeObserver = null;
    }
    if (chart) {
      try { chart.remove(); } catch (err) {}
      chart = null;
    }
  };
  window.addEventListener('pagehide', teardown);
};

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', initDashboard);
} else {
  initDashboard();
}
