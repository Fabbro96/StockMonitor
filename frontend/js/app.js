import { api } from './api.js?v=3.0.0';

export const formatCurrency = (val, currency = 'EUR') => {
  if (val === null || val === undefined || isNaN(val)) return '-';
  const curr = currency === 'USD' ? 'USD' : 'EUR';
  return new Intl.NumberFormat('it-IT', {
    style: 'currency',
    currency: curr,
    minimumFractionDigits: 2,
    maximumFractionDigits: 2
  }).format(val);
};

export const formatPercent = (val) => {
  if (val === null || val === undefined || isNaN(val)) return '-';
  const sign = val > 0 ? '+' : '';
  return `${sign}${val.toFixed(2)}%`;
};

const formatCompactNumber = (val) => {
  if (!val || isNaN(val)) return '-';
  return new Intl.NumberFormat('it-IT', {
    notation: 'compact',
    maximumFractionDigits: 2
  }).format(val);
};

export const formatDate = (dateString) => {
  if (!dateString) return '-';
  const date = new Date(dateString);
  if (isNaN(date.getTime())) return '-';
  return new Intl.DateTimeFormat('it-IT', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric'
  }).format(date);
};

export const formatDateTime = (dateString) => {
  if (!dateString) return '-';
  const date = new Date(dateString);
  if (isNaN(date.getTime())) return '-';
  return new Intl.DateTimeFormat('it-IT', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit'
  }).format(date);
};

// Escapes dynamic values before interpolation into innerHTML (XSS hardening).
export const escapeHtml = (value) => {
  if (value === null || value === undefined) return '';
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
};

export const showToast = (message, type = 'info', actionText = null, onAction = null) => {
  let container = document.querySelector('.toast-container');
  if (!container) {
    container = document.createElement('div');
    container.className = 'toast-container';
    document.body.appendChild(container);
  }

  const toast = document.createElement('div');
  toast.className = `toast toast-${type}`;
  
  let actionHtml = '';
  if (actionText && typeof onAction === 'function') {
    actionHtml = `<button class="btn btn-ghost btn-sm toast-action">${escapeHtml(actionText)}</button>`;
  }

  toast.innerHTML = `<span>${escapeHtml(message)}</span>${actionHtml}`;
  container.appendChild(toast);

  if (actionText && onAction) {
    toast.querySelector('.toast-action')?.addEventListener('click', () => {
      onAction();
      toast.remove();
    });
  }

  setTimeout(() => toast.classList.add('show'), 10);

  let autoTimer = null;
  let removeTimer = null;
  const dismiss = () => {
    clearTimeout(autoTimer);
    clearTimeout(removeTimer);
    toast.classList.remove('show');
    removeTimer = setTimeout(() => toast.remove(), 300);
  };

  autoTimer = setTimeout(dismiss, 4000);

  // L'hover sospende la chiusura; al mouseleave viene riprogrammata per non lasciare il toast appeso.
  toast.addEventListener('mouseenter', () => clearTimeout(autoTimer));
  toast.addEventListener('mouseleave', () => {
    clearTimeout(autoTimer);
    autoTimer = setTimeout(dismiss, 2500);
  });
};

export const showLoading = (elementId = null) => {
  if (elementId) {
    const el = document.getElementById(elementId);
    if (el) {
      let overlay = el.querySelector('.loader-overlay');
      if (!overlay) {
        overlay = document.createElement('div');
        overlay.className = 'loader-overlay';
        overlay.innerHTML = '<div class="spinner"></div>';
        el.style.position = 'relative';
        el.appendChild(overlay);
      }
      overlay.classList.add('active');
    }
  }
};

export const hideLoading = (elementId = null) => {
  if (elementId) {
    const el = document.getElementById(elementId);
    if (el) {
      const overlay = el.querySelector('.loader-overlay');
      if (overlay) overlay.classList.remove('active');
    }
  }
};

// ==========================================
// Theme Management (minimal light & dark)
// ==========================================
export const getTheme = () => {
  const saved = localStorage.getItem('app_theme');
  if (saved === 'light' || saved === 'dark') return saved;
  return window.matchMedia && window.matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark';
};

export const CHART_FONT_FAMILY = '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif';

export const getChartThemeColors = () => {
  const isLight = getTheme() === 'light';
  return {
    textColor: isLight ? '#5a6472' : '#a2a9b6',
    gridColor: isLight ? 'rgba(21, 24, 30, 0.07)' : 'rgba(232, 234, 238, 0.07)',
    lineColor: isLight ? '#2563eb' : '#5b9dff',
    topColor: isLight ? 'rgba(37, 99, 235, 0.16)' : 'rgba(91, 157, 255, 0.22)',
    bottomColor: isLight ? 'rgba(37, 99, 235, 0.01)' : 'rgba(91, 157, 255, 0.01)',
    upColor: isLight ? '#0f8a4d' : '#4cc38a',
    downColor: isLight ? '#d1242f' : '#f26a76',
    volumeColor: isLight ? 'rgba(90, 100, 114, 0.25)' : 'rgba(162, 169, 182, 0.22)',
    volumeUp: isLight ? 'rgba(15, 138, 77, 0.32)' : 'rgba(76, 195, 138, 0.32)',
    volumeDown: isLight ? 'rgba(209, 36, 47, 0.28)' : 'rgba(242, 106, 118, 0.3)',
    benchmarkSp: isLight ? '#0f8a4d' : '#4cc38a',
    benchmarkMib: isLight ? '#b45309' : '#e3a008'
  };
};

const updateThemeToggleButton = () => {
  const btn = document.getElementById('btnThemeToggle');
  if (!btn) return;
  const isLight = getTheme() === 'light';
  btn.innerHTML = isLight 
    ? '<span>☀️</span>' 
    : '<span>🌙</span>';
  btn.title = isLight ? 'Passa al tema scuro' : 'Passa al tema chiaro';
  btn.setAttribute('aria-label', btn.title);
};

const setTheme = (theme) => {
  localStorage.setItem('app_theme', theme);
  document.documentElement.setAttribute('data-theme', theme);
  updateThemeToggleButton();
  window.dispatchEvent(new CustomEvent('themeChanged', { detail: { theme } }));
};

const toggleTheme = () => {
  const current = getTheme();
  const next = current === 'light' ? 'dark' : 'light';
  setTheme(next);
};

const initTopBarControls = () => {
  const topbar = document.querySelector('.topbar');
  if (!topbar) return;

  // Controlli sulla destra della topbar
  let actionGroup = topbar.querySelector('.topbar-actions');
  
  if (!actionGroup) {
    actionGroup = document.createElement('div');
    actionGroup.className = 'topbar-actions';
    topbar.appendChild(actionGroup);
  }

  // 1. Bottone Ricerca Globale (Spotlight Ctrl+K)
  if (!document.getElementById('btnGlobalSearch')) {
    const searchBtn = document.createElement('button');
    searchBtn.className = 'topbar-search-btn';
    searchBtn.id = 'btnGlobalSearch';
    searchBtn.addEventListener('click', () => openCommandPalette());
    searchBtn.title = 'Cerca titoli o naviga (Ctrl+K)';
    searchBtn.innerHTML = `
      <span>🔍</span>
      <span class="search-text">Cerca...</span>
      <kbd class="kbd-badge">Ctrl K</kbd>
    `;
    const themeBtn = document.getElementById('btnThemeToggle');
    if (themeBtn && themeBtn.parentNode) {
      themeBtn.parentNode.insertBefore(searchBtn, themeBtn);
    } else {
      actionGroup.appendChild(searchBtn);
    }
  }

  // 2. Bottone Scorciatoie da Tastiera (?)
  if (!document.getElementById('btnShortcutsHelp')) {
    const helpBtn = document.createElement('button');
    helpBtn.className = 'topbar-help-btn';
    helpBtn.id = 'btnShortcutsHelp';
    helpBtn.addEventListener('click', () => openShortcutsHelp());
    helpBtn.title = 'Scorciatoie da tastiera (?)';
    helpBtn.setAttribute('aria-label', 'Scorciatoie da tastiera');
    helpBtn.innerHTML = `<span>?</span>`;
    const themeBtn = document.getElementById('btnThemeToggle');
    if (themeBtn && themeBtn.parentNode) {
      themeBtn.parentNode.insertBefore(helpBtn, themeBtn);
    } else {
      actionGroup.appendChild(helpBtn);
    }
  }

  // 3. Bottone Cambio Tema (presente in tutte le pagine)
  document.getElementById('btnThemeToggle')?.addEventListener('click', toggleTheme);
};

const initTheme = () => {
  const saved = getTheme();
  document.documentElement.setAttribute('data-theme', saved);
  initTopBarControls();
  updateThemeToggleButton();
};

// ==========================================
// Global Marquee Ticker
// ==========================================
const initTickerMarquee = async () => {
  const mainContent = document.querySelector('.main-content');
  if (!mainContent) return;

  let tapeContainer = document.querySelector('.ticker-tape-container');
  if (!tapeContainer) {
    tapeContainer = document.createElement('div');
    tapeContainer.className = 'ticker-tape-container';
    tapeContainer.id = 'globalTickerTape';
    mainContent.insertBefore(tapeContainer, mainContent.firstChild);
  }

  try {
    const indices = await api.getIndices().catch(() => []);
    if (!indices || indices.length === 0) return;

    const renderItems = (items) => items.map(idx => {
      const isUp = idx.change_percent >= 0;
      const changeClass = isUp ? 'up' : 'down';
      const sign = isUp ? '+' : '';
      return `
        <div class="ticker-item" data-stock="${escapeHtml(idx.ticker)}">
          <span>${escapeHtml(idx.flag || '📊')}</span>
          <span class="ticker-name">${escapeHtml(idx.name)}</span>
          <span class="ticker-price">${escapeHtml(idx.price)}</span>
          <span class="ticker-change ${changeClass}">${sign}${escapeHtml(idx.change_percent)}%</span>
        </div>
      `;
    }).join('');

    tapeContainer.innerHTML = `
      <div class="ticker-tape-track">
        ${renderItems(indices)}
        ${renderItems(indices)}
      </div>
    `;
  } catch (e) {
    console.debug('Ticker marquee error:', e);
  }
};

// ==========================================
// Modern Number Steppers (+ / -)
// ==========================================
const initSteppers = () => {
  let activeTimer = null;
  let activeInterval = null;

  const performStep = (btn, isShift = false, isAlt = false) => {
    const stepper = btn.closest('.modern-stepper');
    if (!stepper) return;
    const input = stepper.querySelector('input[type="number"], .inline-input, .stepper-input');
    if (!input || input.disabled || input.readOnly) return;

    let step = parseFloat(btn.dataset.step);
    if (isNaN(step) || step <= 0) {
      step = parseFloat(input.step);
      if (isNaN(step) || step <= 0) {
        step = input.classList.contains('input-price') ? 0.5 : 1;
      }
    }

    if (isShift) step *= 10;
    else if (isAlt) step = Math.max(step / 10, 0.01);

    const isInc = btn.classList.contains('inc');
    const currentVal = parseFloat(input.value) || 0;
    let newVal = isInc ? currentVal + step : currentVal - step;

    if (input.min !== '' && !isNaN(parseFloat(input.min))) {
      newVal = Math.max(newVal, parseFloat(input.min));
    }
    if (input.max !== '' && !isNaN(parseFloat(input.max))) {
      newVal = Math.min(newVal, parseFloat(input.max));
    }

    // Determine precision to prevent floating point noise (e.g. 21.500000000000004)
    const stepDecimals = (step.toString().split('.')[1] || '').length;
    const valDecimals = Math.max(stepDecimals, input.classList.contains('input-price') ? 2 : 0);
    input.value = valDecimals > 0 ? parseFloat(newVal.toFixed(valDecimals)) : Math.round(newVal);

    input.dispatchEvent(new Event('input', { bubbles: true }));
    input.dispatchEvent(new Event('change', { bubbles: true }));
  };

  const stopRepeat = () => {
    if (activeTimer) clearTimeout(activeTimer);
    if (activeInterval) clearInterval(activeInterval);
    activeTimer = null;
    activeInterval = null;
  };

  document.addEventListener('mousedown', (e) => {
    const btn = e.target.closest('.stepper-btn');
    if (!btn || e.button !== 0) return;
    e.preventDefault();

    performStep(btn, e.shiftKey, e.altKey);

    stopRepeat();
    activeTimer = setTimeout(() => {
      activeInterval = setInterval(() => {
        performStep(btn, e.shiftKey, e.altKey);
      }, 75);
    }, 280);
  });

  document.addEventListener('mouseup', stopRepeat);
  document.addEventListener('mouseleave', stopRepeat);
  window.addEventListener('blur', stopRepeat);

  document.addEventListener('touchstart', (e) => {
    const btn = e.target.closest('.stepper-btn');
    if (!btn) return;
    performStep(btn);

    stopRepeat();
    activeTimer = setTimeout(() => {
      activeInterval = setInterval(() => {
        performStep(btn);
      }, 75);
    }, 280);
  }, { passive: true });

  document.addEventListener('touchend', stopRepeat, { passive: true });
  document.addEventListener('touchcancel', stopRepeat, { passive: true });
};

// ==========================================
// Global Stock Deep Dive Modal
// ==========================================
let modalChart = null;
let modalAreaSeries = null;
let modalCandleSeries = null;
let modalVolumeSeries = null;
let modalBreakevenLine = null;
let currentModalTicker = null;
let currentModalTimeframe = '1m';
let currentModalChartType = 'area'; // 'area' | 'candle'
let rawCandlesData = [];
let modalLoadGeneration = 0;

const disposeModalChart = () => {
  modalLoadGeneration++;
  if (modalChart) {
    try { modalChart.remove(); } catch (e) {}
  }
  modalChart = null;
  modalAreaSeries = null;
  modalCandleSeries = null;
  modalVolumeSeries = null;
  modalBreakevenLine = null;
};

const injectStockModalHTML = () => {
  if (document.getElementById('stockDeepDiveModal')) return;

  const modalEl = document.createElement('div');
  modalEl.className = 'modal-overlay';
  modalEl.id = 'stockDeepDiveModal';
  modalEl.setAttribute('role', 'dialog');
  modalEl.setAttribute('aria-modal', 'true');
  modalEl.setAttribute('aria-labelledby', 'smTicker');
  modalEl.innerHTML = `
    <div class="modal-content stock-modal-large">
      <div class="modal-header">
        <div class="flex items-center gap-3">
          <span class="text-2xl" id="smFlag">📈</span>
          <div>
            <div class="flex items-center gap-2 flex-wrap">
              <h2 class="modal-title" id="smTicker">--</h2>
              <span class="badge" id="smMarketBadge">--</span>
              <span id="smHeldBadge" class="badge badge-buy" style="display: none;">💼 In Portafoglio</span>
            </div>
            <div class="text-xs text-secondary" id="smName">--</div>
          </div>
        </div>
        <div class="flex items-center gap-3">
          <div class="text-right">
            <div class="text-xl font-bold font-mono" id="smPrice">-- €</div>
            <div class="text-xs font-mono font-bold" id="smChange">--</div>
          </div>
          <button class="modal-close" id="closeStockModal" aria-label="Chiudi finestra">×</button>
        </div>
      </div>

      <!-- Modal Tabs -->
      <div class="modal-tabs">
        <button class="modal-tab-btn active" data-tab="tab-chart">📈 Grafico & Dati</button>
        <button class="modal-tab-btn" data-tab="tab-technicals">⚡ Indicatori Tecnici</button>
        <button class="modal-tab-btn" data-tab="tab-fundamentals">📊 Fondamentali</button>
        <button class="modal-tab-btn" data-tab="tab-ai">🤖 Analisi AI Gemini</button>
      </div>

      <!-- Tab Content: Chart -->
      <div id="tab-chart" class="modal-tab-panel">
        <div class="flex justify-between items-center mb-3 flex-wrap gap-2">
          <div class="flex items-center gap-2 flex-wrap">
            <div class="timeframe-group" id="modalTimeframeGroup">
              <button class="timeframe-btn" data-tf="1d">1G</button>
              <button class="timeframe-btn" data-tf="1w">1S</button>
              <button class="timeframe-btn active" data-tf="1m">1M</button>
              <button class="timeframe-btn" data-tf="6m">6M</button>
              <button class="timeframe-btn" data-tf="1y">1A</button>
              <button class="timeframe-btn" data-tf="5y">5A</button>
            </div>
            <div class="flex gap-2" id="modalChartTypeGroup">
              <button class="chart-type-btn active" data-type="area">📈 Area</button>
              <button class="chart-type-btn" data-type="candle">📊 Candele</button>
            </div>
          </div>
          <div class="flex gap-2 flex-wrap">
            <button class="btn btn-ghost btn-sm" id="btnModalAddWatchlist">⭐ Salva in Watchlist</button>
            <button class="btn btn-primary btn-sm" id="btnModalAddHolding">➕ Aggiungi al Portafoglio</button>
          </div>
        </div>
        <div id="stockModalChart" class="modal-chart"></div>
        <div class="flex justify-between items-center text-xs text-muted mt-2 flex-wrap gap-2">
          <span id="smBreakevenLegend" style="display: none;">🟠 Linea Tratteggiata: Prezzo Medio Carico Portafoglio</span>
          <span>Volumi visualizzati in basso</span>
        </div>
      </div>

      <!-- Tab Content: Technicals -->
      <div id="tab-technicals" class="modal-tab-panel" style="display: none;">
        <div class="metric-grid mb-4">
          <div class="card card-subtle p-3">
            <div class="text-xs text-muted mb-1">RSI (14 Periodi)</div>
            <div class="text-2xl font-bold font-mono" id="smRsiVal">--</div>
            <span class="badge mt-2" id="smRsiBadge">Neutro</span>
          </div>
          <div class="card card-subtle p-3">
            <div class="text-xs text-muted mb-1">Media Mobile 20 (SMA 20)</div>
            <div class="text-xl font-bold font-mono" id="smSma20">--</div>
            <div class="text-xs text-secondary mt-1">Trend breve termine</div>
          </div>
          <div class="card card-subtle p-3">
            <div class="text-xs text-muted mb-1">Media Mobile 50 (SMA 50)</div>
            <div class="text-xl font-bold font-mono" id="smSma50">--</div>
            <div class="text-xs text-secondary mt-1">Trend medio termine</div>
          </div>
          <div class="card card-subtle p-3">
            <div class="text-xs text-muted mb-1">Configurazione Trend</div>
            <div class="text-lg font-bold text-primary mt-1" id="smTrend">--</div>
          </div>
        </div>

        <div class="card card-subtle p-4">
          <div class="text-xs font-bold text-muted uppercase mb-2">Range 52 Settimane</div>
          <div class="range-bar-container">
            <div class="range-bar-track">
              <div class="range-bar-fill"></div>
              <div class="range-bar-pin" id="sm52Pin" style="left: 50%;"></div>
            </div>
            <div class="range-bar-labels mt-1">
              <span>Min: <strong id="sm52Low">--</strong></span>
              <span id="sm52Pos">Posizione: 50%</span>
              <span>Max: <strong id="sm52High">--</strong></span>
            </div>
          </div>
        </div>
      </div>

      <!-- Tab Content: Fundamentals -->
      <div id="tab-fundamentals" class="modal-tab-panel" style="display: none;">
        <div class="metric-grid mb-4">
          <div class="card card-subtle p-3">
            <div class="text-xs text-muted">Capitalizzazione</div>
            <div class="text-lg font-bold font-mono mt-1" id="smMarketCap">--</div>
          </div>
          <div class="card card-subtle p-3">
            <div class="text-xs text-muted">P/E Ratio (Trailing)</div>
            <div class="text-lg font-bold font-mono mt-1" id="smPe">--</div>
          </div>
          <div class="card card-subtle p-3">
            <div class="text-xs text-muted">EPS (Utile per Azione)</div>
            <div class="text-lg font-bold font-mono mt-1" id="smEps">--</div>
          </div>
          <div class="card card-subtle p-3">
            <div class="text-xs text-muted">Beta (Volatilità)</div>
            <div class="text-lg font-bold font-mono mt-1" id="smBeta">--</div>
          </div>
          <div class="card card-subtle p-3">
            <div class="text-xs text-muted">Dividend Yield</div>
            <div class="text-lg font-bold font-mono text-profit mt-1" id="smDivYield">--%</div>
          </div>
          <div class="card card-subtle p-3">
            <div class="text-xs text-muted">Volume Medio</div>
            <div class="text-lg font-bold font-mono mt-1" id="smVolume">--</div>
          </div>
        </div>
        <div class="card card-subtle p-3 text-xs text-secondary leading-relaxed scrollbox-sm" id="smSummary">
          Nessuna descrizione disponibile per questa società.
        </div>
      </div>

      <!-- Tab Content: AI Analysis -->
      <div id="tab-ai" class="modal-tab-panel" style="display: none;">
        <div class="flex justify-between items-center mb-3 flex-wrap gap-2">
          <div class="text-sm font-bold text-primary flex items-center gap-1.5">
            <span>🧠 Analisi Istantanea Gemini 3.7 Flash</span>
          </div>
          <button class="btn btn-primary btn-sm" id="btnRunStockAi">⚡ Elabora Analisi Ora</button>
        </div>
        <div id="stockAiResultContainer" class="card card-subtle p-4 card-note">
          <div class="text-center text-muted py-6 text-sm">
            Clicca <strong>"Elabora Analisi Ora"</strong> per interrogare l'IA su fondamentali, indicatori tecnici, catalizzatori e posizione in portafoglio.
          </div>
        </div>
      </div>
    </div>
  `;
  document.body.appendChild(modalEl);

  // Listeners
  document.getElementById('closeStockModal').addEventListener('click', () => {
    disposeModalChart();
    modalEl.classList.remove('active');
  });

  modalEl.querySelectorAll('.modal-tab-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      modalEl.querySelectorAll('.modal-tab-btn').forEach(b => b.classList.remove('active'));
      modalEl.querySelectorAll('.modal-tab-panel').forEach(p => p.style.display = 'none');
      btn.classList.add('active');
      const targetPanel = document.getElementById(btn.dataset.tab);
      if (targetPanel) targetPanel.style.display = 'block';
    });
  });

  modalEl.querySelectorAll('.timeframe-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      modalEl.querySelectorAll('.timeframe-btn').forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      currentModalTimeframe = btn.dataset.tf;
      // Nuova generazione: invalida eventuali risposte in volo di timeframe precedenti.
      loadModalChart(currentModalTicker, currentModalTimeframe, ++modalLoadGeneration);
    });
  });

  // Chart type switcher
  const chartTypeGroup = document.getElementById('modalChartTypeGroup');
  if (chartTypeGroup) {
    chartTypeGroup.querySelectorAll('.chart-type-btn').forEach(btn => {
      btn.addEventListener('click', () => {
        chartTypeGroup.querySelectorAll('.chart-type-btn').forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
        currentModalChartType = btn.dataset.type;
        applyModalChartData();
      });
    });
  }

  document.getElementById('btnRunStockAi').addEventListener('click', runModalStockAi);

  document.getElementById('btnModalAddWatchlist').addEventListener('click', async () => {
    if (!currentModalTicker) return;
    try {
      const res = await api.addToWatchlist({ ticker: currentModalTicker });
      showToast(res.message || `${currentModalTicker} aggiunto alla Watchlist!`, 'success');
    } catch (e) {
      showToast(e.message || 'Errore salvataggio in Watchlist', 'error');
    }
  });

  document.getElementById('btnModalAddHolding').addEventListener('click', () => {
    disposeModalChart();
    modalEl.classList.remove('active');
    if (window.location.pathname.includes('portfolio.html')) {
      const tickerInput = document.getElementById('tickerInput');
      if (tickerInput) {
        tickerInput.value = currentModalTicker;
        document.getElementById('holdingModal')?.classList.add('active');
      }
    } else {
      window.location.href = `/static/portfolio.html?add=${encodeURIComponent(currentModalTicker)}`;
    }
  });
};

const initModalChart = () => {
  const container = document.getElementById('stockModalChart');
  if (!container || typeof LightweightCharts === 'undefined') return;

  if (modalChart) {
    try { modalChart.remove(); } catch(e){}
  }
  // I riferimenti alle serie del chart rimosso non sono più validi: azzerali per evitare
  // removePriceLine/applyOptions su oggetti morti alla riapertura del modal.
  modalChart = null;
  modalAreaSeries = null;
  modalCandleSeries = null;
  modalVolumeSeries = null;
  modalBreakevenLine = null;
  // Nuovo ticker/chart: le serie del precedente non devono riapparire.
  rawCandlesData = [];

  const themeColors = getChartThemeColors();

  modalChart = LightweightCharts.createChart(container, {
    layout: {
      background: { type: 'solid', color: 'transparent' },
      textColor: themeColors.textColor,
      fontFamily: CHART_FONT_FAMILY,
      fontSize: 11
    },
    grid: {
      vertLines: { color: themeColors.gridColor },
      horzLines: { color: themeColors.gridColor },
    },
    rightPriceScale: {
      borderVisible: false,
      scaleMargins: { top: 0.1, bottom: 0.25 }
    },
    timeScale: { borderVisible: false }
  });

  modalAreaSeries = modalChart.addAreaSeries({
    topColor: themeColors.topColor,
    bottomColor: themeColors.bottomColor,
    lineColor: themeColors.lineColor,
    lineWidth: 2,
  });

  modalCandleSeries = modalChart.addCandlestickSeries({
    upColor: themeColors.upColor,
    downColor: themeColors.downColor,
    borderUpColor: themeColors.upColor,
    borderDownColor: themeColors.downColor,
    wickUpColor: themeColors.upColor,
    wickDownColor: themeColors.downColor,
    visible: false
  });

  modalVolumeSeries = modalChart.addHistogramSeries({
    color: themeColors.volumeColor,
    priceFormat: { type: 'volume' },
    priceScaleId: ''
  });
  modalVolumeSeries.priceScale().applyOptions({ scaleMargins: { top: 0.8, bottom: 0 } });
};

const applyModalChartData = () => {
  if (!modalChart || rawCandlesData.length === 0) return;

  if (currentModalChartType === 'candle') {
    modalAreaSeries.applyOptions({ visible: false });
    modalCandleSeries.applyOptions({ visible: true });
    modalCandleSeries.setData(rawCandlesData.map(c => ({
      time: c.time,
      open: c.open,
      high: c.high,
      low: c.low,
      close: c.close
    })));
  } else {
    modalCandleSeries.applyOptions({ visible: false });
    modalAreaSeries.applyOptions({ visible: true });
    modalAreaSeries.setData(rawCandlesData.map(c => ({ time: c.time, value: c.close })));
  }

  // Volume
  const colors = getChartThemeColors();
  modalVolumeSeries.setData(rawCandlesData.map(c => ({
    time: c.time,
    value: c.volume || 0,
    color: c.close >= c.open ? colors.volumeUp : colors.volumeDown
  })));

  modalChart.timeScale().fitContent();
};

const loadModalChart = async (ticker, timeframe = '1m', generation = modalLoadGeneration) => {
  if (!modalChart || !ticker) return;
  try {
    const data = await api.getStockCandles(ticker, timeframe);
    // Solo la risposta della generazione corrente scrive lo stato condiviso:
    // una risposta stale non deve rimpiazzare rawCandlesData, che theme change
    // e toggle area/candele riapplicano sul chart corrente.
    if (generation !== modalLoadGeneration || !modalChart) return;
    rawCandlesData = data;
    applyModalChartData();
  } catch (e) {
    console.error('Errore caricamento candele modale:', e);
  }
};

const runModalStockAi = async () => {
  if (!currentModalTicker) return;
  const ticker = currentModalTicker;
  const container = document.getElementById('stockAiResultContainer');
  const btn = document.getElementById('btnRunStockAi');
  
  btn.disabled = true;
  btn.textContent = 'Analisi in corso...';
  container.innerHTML = '<div class="flex justify-center items-center py-8"><div class="spinner"></div></div>';

  try {
    const result = await api.analyzeStockOnDemand(ticker);
    // Il modal può essere stato riaperto su un altro ticker durante l'analisi: scarta il risultato.
    if (ticker !== currentModalTicker) return;
    const actionBadgeClass = result.action === 'ACCUMULO' || result.action === 'BUY' ? 'badge-buy' : (result.action === 'PRESA_PROFITTO' || result.action === 'SELL' ? 'badge-sell' : 'badge-hold');

    let holdingBox = '';
    if (result.holding_context) {
      const hc = result.holding_context;
      holdingBox = `
        <div class="callout-accent p-2.5 mb-3">
          <div class="text-xs text-primary font-bold mb-1">💼 Posizione nel tuo Portafoglio</div>
          <div class="flex justify-between items-center text-xs font-mono flex-wrap gap-2">
            <span>Possiedi: <strong>${escapeHtml(hc.quantity)}</strong> azioni a carico <strong>${formatCurrency(hc.avg_purchase_price)}</strong></span>
            <span class="${hc.current_pnl_pct >= 0 ? 'text-profit' : 'text-loss'} font-bold">P&L: ${formatCurrency(hc.current_pnl_abs)} (${formatPercent(hc.current_pnl_pct)})</span>
          </div>
        </div>
      `;
    }

    // Coercizione numerica sicura: l'output LLM non è validato e finisce in innerHTML.
    const upsideRaw = Number(result.upside_potential_pct);
    const upsidePct = Number.isFinite(upsideRaw) ? upsideRaw : 0;

    container.innerHTML = `
      <div>
        <div class="flex justify-between items-center mb-3 flex-wrap gap-2">
          <span class="badge ${actionBadgeClass}">${escapeHtml(result.action_label || result.action)}</span>
          <div class="text-xs text-muted">Confidenza: <strong class="text-primary">${escapeHtml(result.confidence || 'MEDIA')}</strong> • Orizzonte: <strong class="text-primary">${escapeHtml(result.timeframe || 'Medio Termine')}</strong></div>
        </div>

        ${holdingBox}

        <div class="split-grid mb-3">
          <div class="callout p-2.5">
            <div class="text-xs text-muted">🎯 Target Price Stimato</div>
            <div class="text-lg font-bold text-primary font-mono">${formatCurrency(result.target_price)} <span class="text-xs text-profit">(+${upsidePct}%)</span></div>
          </div>
          <div class="callout p-2.5">
            <div class="text-xs text-muted">🛡️ Stop Loss Consigliato</div>
            <div class="text-lg font-bold text-danger font-mono">${result.stop_loss ? formatCurrency(result.stop_loss) : '--'}</div>
          </div>
        </div>

        <p class="text-sm text-primary leading-relaxed mb-3">${escapeHtml(result.summary || '')}</p>

        <div class="split-grid mb-3 text-xs">
          <div class="callout-success p-2.5">
            <strong class="text-profit block mb-1">🟢 Bull Case & Punti di Forza</strong>
            <span class="text-secondary leading-normal">${escapeHtml(result.bull_case || '--')}</span>
          </div>
          <div class="callout-danger p-2.5">
            <strong class="text-loss block mb-1">🔴 Bear Case & Rischi Chiave</strong>
            <span class="text-secondary leading-normal">${escapeHtml(result.bear_case || '--')}</span>
          </div>
        </div>

        <div class="callout p-2.5">
          <strong class="text-xs text-primary block mb-1">💡 Strategia Operativa Suggerita</strong>
          <span class="text-xs text-secondary leading-normal">${escapeHtml(result.operational_strategy || '--')}</span>
        </div>
      </div>
    `;
  } catch (e) {
    if (ticker !== currentModalTicker) return;
    container.innerHTML = `<div class="alert-error text-center py-4 text-xs">Impossibile completare l'analisi per ${escapeHtml(ticker)}: ${escapeHtml(e.message)}</div>`;
  } finally {
    btn.disabled = false;
    btn.textContent = '⚡ Rielabora Analisi';
  }
};

const openStockModal = async (ticker) => {
  if (!ticker) return;
  injectStockModalHTML();
  
  currentModalTicker = ticker.trim().toUpperCase();
  const generation = ++modalLoadGeneration;
  const modal = document.getElementById('stockDeepDiveModal');
  modal.classList.add('active');

  modal.querySelectorAll('.modal-tab-btn').forEach((b, idx) => {
    if (idx === 0) b.classList.add('active');
    else b.classList.remove('active');
  });
  modal.querySelectorAll('.modal-tab-panel').forEach((p, idx) => {
    p.style.display = idx === 0 ? 'block' : 'none';
  });

  document.getElementById('smTicker').textContent = currentModalTicker;
  document.getElementById('smName').textContent = 'Caricamento dati...';
  document.getElementById('smPrice').textContent = '--';
  document.getElementById('smChange').textContent = '--';
  document.getElementById('smHeldBadge').style.display = 'none';
  document.getElementById('smBreakevenLegend').style.display = 'none';

  initModalChart();
  loadModalChart(currentModalTicker, currentModalTimeframe, generation);

  try {
    const [data, portfolio] = await Promise.all([
      api.getStockDetails(currentModalTicker).catch(() => ({})),
      api.getPortfolio().catch(() => [])
    ]);

    // Modal chiuso o riaperto nel frattempo: continuazione obsoleta, niente scritture.
    if (generation !== modalLoadGeneration) return;

    document.getElementById('smName').textContent = data.name || currentModalTicker;
    document.getElementById('smPrice').textContent = formatCurrency(data.current_price, data.currency);
    
    const changeEl = document.getElementById('smChange');
    const isUp = data.change_percent >= 0;
    changeEl.textContent = `${isUp ? '+' : ''}${data.change_abs} (${formatPercent(data.change_percent)})`;
    changeEl.className = `text-xs font-mono font-bold ${isUp ? 'text-profit' : 'text-loss'}`;

    const marketBadge = document.getElementById('smMarketBadge');
    marketBadge.textContent = data.market || 'US';
    marketBadge.className = `badge ${data.market === 'IT' ? 'badge-buy' : 'badge-cyan'}`;

    document.getElementById('smFlag').textContent = data.market === 'IT' ? '🇮🇹' : (data.market === 'EU' ? '🇪🇺' : '🇺🇸');

    // Check if in portfolio
    const held = portfolio.find(p => p.ticker === currentModalTicker);
    if (held) {
      document.getElementById('smHeldBadge').style.display = 'inline-flex';
      document.getElementById('smBreakevenLegend').style.display = 'inline';

      if (modalAreaSeries) {
        if (modalBreakevenLine) {
          modalAreaSeries.removePriceLine(modalBreakevenLine);
        }
        modalBreakevenLine = modalAreaSeries.createPriceLine({
          price: held.avg_purchase_price,
          color: '#f59e0b',
          lineWidth: 2,
          lineStyle: 2, // Dashed
          axisLabelVisible: true,
          title: `Carico ${formatCurrency(held.avg_purchase_price, held.currency)}`
        });
      }
    }

    const tech = data.technical || {};
    // 0 è un valore legittimo per RSI/Beta: usa ?? per non mostrare '--'.
    document.getElementById('smRsiVal').textContent = tech.rsi_14 ?? '--';
    const rsiBadge = document.getElementById('smRsiBadge');
    rsiBadge.textContent = tech.rsi_status || 'Neutro';
    rsiBadge.className = `badge ${tech.rsi_badge || 'badge-hold'}`;

    document.getElementById('smSma20').textContent = tech.sma_20 ? formatCurrency(tech.sma_20, data.currency) : '--';
    document.getElementById('smSma50').textContent = tech.sma_50 ? formatCurrency(tech.sma_50, data.currency) : '--';
    document.getElementById('smTrend').textContent = tech.trend || 'Neutro';

    document.getElementById('sm52Low').textContent = formatCurrency(data.fifty_two_week_low, data.currency);
    document.getElementById('sm52High').textContent = formatCurrency(data.fifty_two_week_high, data.currency);
    const pin = document.getElementById('sm52Pin');
    const raw52wPct = Number(data.fifty_two_week_pct);
    const pct = Math.max(0, Math.min(100, Number.isFinite(raw52wPct) ? raw52wPct : 50));
    pin.style.left = `${pct}%`;
    document.getElementById('sm52Pos').textContent = `Posizione: ${pct}%`;

    document.getElementById('smMarketCap').textContent = formatCompactNumber(data.market_cap);
    document.getElementById('smPe').textContent = data.pe_ratio || '--';
    document.getElementById('smEps').textContent = data.eps ? formatCurrency(data.eps, data.currency) : '--';
    document.getElementById('smBeta').textContent = data.beta ?? '--';
    document.getElementById('smDivYield').textContent = data.dividend_yield ? `${data.dividend_yield}%` : '--%';
    document.getElementById('smVolume').textContent = formatCompactNumber(data.avg_volume || data.volume);
    document.getElementById('smSummary').textContent = data.summary || 'Nessuna descrizione disponibile.';

  } catch (e) {
    console.error('Errore recupero dettagli titolo:', e);
  }
};

window.openStockModal = openStockModal;

// Editor mercato di un titolo (lo Stock è globale: la correzione vale per tutti).
export const openMarketEditor = (ticker, currentMarket = 'US', onSaved = null) => {
  const normalizedTicker = (ticker || '').toUpperCase();
  if (!normalizedTicker) return;
  const current = (currentMarket || 'US').toUpperCase();

  document.getElementById('marketEditorModal')?.remove();

  const options = [
    { value: 'IT', label: '🇮🇹 IT — Borsa Italiana' },
    { value: 'US', label: '🇺🇸 US — Wall Street' },
    { value: 'EU', label: '🇪🇺 EU — Europa' }
  ];

  const modalEl = document.createElement('div');
  modalEl.className = 'modal-overlay';
  modalEl.id = 'marketEditorModal';
  modalEl.setAttribute('role', 'dialog');
  modalEl.setAttribute('aria-modal', 'true');
  modalEl.setAttribute('aria-labelledby', 'marketEditorTitle');
  modalEl.innerHTML = `
    <div class="modal-content">
      <div class="modal-header">
        <h2 class="modal-title" id="marketEditorTitle">🏛️ Mercato di ${escapeHtml(normalizedTicker)}</h2>
        <button class="modal-close" id="closeMarketEditor" aria-label="Chiudi finestra">×</button>
      </div>
      <div class="form-group">
        <label for="marketEditorSelect">Borsa di quotazione</label>
        <select id="marketEditorSelect">
          ${options.map(o => `<option value="${o.value}"${o.value === current ? ' selected' : ''}>${o.label}</option>`).join('')}
        </select>
        <div class="text-xs text-muted mt-2">La correzione vale per tutti gli utenti: il mercato è una proprietà del titolo, non della posizione.</div>
      </div>
      <div class="flex justify-end gap-2 mt-4">
        <button class="btn btn-ghost" id="cancelMarketEditor">Annulla</button>
        <button class="btn btn-primary" id="saveMarketEditor">💾 Salva</button>
      </div>
    </div>
  `;
  document.body.appendChild(modalEl);

  const close = () => modalEl.remove();
  document.getElementById('closeMarketEditor').addEventListener('click', close);
  document.getElementById('cancelMarketEditor').addEventListener('click', close);
  modalEl.addEventListener('click', (e) => { if (e.target === modalEl) close(); });

  document.getElementById('saveMarketEditor').addEventListener('click', async () => {
    const select = document.getElementById('marketEditorSelect');
    const market = select ? select.value : current;
    const saveBtn = document.getElementById('saveMarketEditor');
    saveBtn.disabled = true;
    try {
      const updated = await api.updateStockMarket(normalizedTicker, market);
      showToast(`Mercato di ${normalizedTicker} impostato a ${updated.market || market}`, 'success');
      close();
      if (typeof onSaved === 'function') onSaved(updated);
    } catch (err) {
      showToast(err.message || 'Errore durante il salvataggio del mercato', 'error');
      saveBtn.disabled = false;
    }
  });

  modalEl.classList.add('active');
};

const initSidebar = () => {
  const currentPath = window.location.pathname;
  const links = document.querySelectorAll('.nav-link');
  
  links.forEach(link => {
    const href = link.getAttribute('href');
    if (currentPath.endsWith(href) || (currentPath === '/' && href === '/static/index.html')) {
      link.classList.add('active');
    } else {
      link.classList.remove('active');
    }
  });

  // Mobile drawer backdrop
  let backdrop = document.getElementById('sidebarBackdrop');
  if (!backdrop) {
    backdrop = document.createElement('div');
    backdrop.className = 'sidebar-backdrop';
    backdrop.id = 'sidebarBackdrop';
    document.body.appendChild(backdrop);
  }

  const toggle = document.querySelector('.mobile-toggle');
  const sidebar = document.querySelector('.sidebar');
  
  if (toggle && sidebar && backdrop) {
    toggle.addEventListener('click', () => {
      sidebar.classList.toggle('open');
      backdrop.classList.toggle('active');
    });

    backdrop.addEventListener('click', () => {
      sidebar.classList.remove('open');
      backdrop.classList.remove('active');
    });

    // Close on navigation link click
    links.forEach(link => {
      link.addEventListener('click', () => {
        sidebar.classList.remove('open');
        backdrop.classList.remove('active');
      });
    });
  }

  // Sidebar collapse toggle (desktop)
  const collapseBtn = document.getElementById('btnSidebarCollapse');
  if (collapseBtn && sidebar) {
    const syncCollapseButton = (collapsed) => {
      collapseBtn.textContent = collapsed ? '»' : '«';
      collapseBtn.title = collapsed ? 'Espandi menu' : 'Comprimi menu';
      collapseBtn.setAttribute('aria-label', collapseBtn.title);
    };
    if (localStorage.getItem('sidebar_collapsed') === '1') {
      sidebar.classList.add('collapsed');
      syncCollapseButton(true);
    }
    collapseBtn.addEventListener('click', () => {
      const collapsed = sidebar.classList.toggle('collapsed');
      syncCollapseButton(collapsed);
      localStorage.setItem('sidebar_collapsed', collapsed ? '1' : '0');
    });
  }

  // Add User Footer to Sidebar
  if (sidebar && !sidebar.querySelector('.sidebar-footer')) {
    const username = localStorage.getItem('auth_username') || 'Utente';
    const footer = document.createElement('div');
    footer.className = 'sidebar-footer';
    footer.innerHTML = `
      <div class="sidebar-user">
        <span>👤</span>
        <span class="sidebar-username">${escapeHtml(username)}</span>
      </div>
      <button id="btnLogout" class="icon-btn" title="Disconnetti" aria-label="Disconnetti">🚪</button>
    `;
    sidebar.appendChild(footer);

    const btnLogout = footer.querySelector('#btnLogout');
    if (btnLogout) {
      btnLogout.addEventListener('click', async () => {
        if (confirm('Sei sicuro di voler effettuare il logout?')) {
          await api.logout();
        }
      });
    }
  }
};

const checkAuth = async () => {
  if (window.location.pathname.includes('login.html')) return;

  try {
    const me = await api.getMe();
    if (me && me.username) {
      localStorage.setItem('auth_username', me.username);
      const usernameEl = document.querySelector('.sidebar-username');
      if (usernameEl) usernameEl.textContent = me.username;
    }
  } catch (e) {
    // Redirect handled by api.js
  }
};

// ==========================================
// Live Price Flash Micro-Interaction
// ==========================================
const flashPriceTimeouts = new WeakMap();

const flashPriceChange = (el, isUp) => {
  if (!el) return;
  const cls = isUp ? 'flash-up' : 'flash-down';
  const prevTimer = flashPriceTimeouts.get(el);
  if (prevTimer) clearTimeout(prevTimer);
  el.classList.remove('flash-up', 'flash-down');
  void el.offsetWidth; // Trigger reflow per riavviare l'animazione
  el.classList.add(cls);
  flashPriceTimeouts.set(el, setTimeout(() => {
    el.classList.remove(cls);
    flashPriceTimeouts.delete(el);
  }, 850));
};
window.flashPriceChange = flashPriceChange;

// ==========================================
// Command Palette & Keyboard Shortcuts System
// ==========================================
const COMMAND_NAV_ITEMS = [
  { type: 'nav', icon: '🏠', title: 'Dashboard', desc: 'Panoramica patrimonio, indici globali e heatmap', url: '/static/index.html', shortcut: 'D' },
  { type: 'nav', icon: '⭐', title: 'Watchlist & Radar', desc: 'Monitoraggio titoli osservati e alert prezzi', url: '/static/watchlist.html', shortcut: 'W' },
  { type: 'nav', icon: '💼', title: 'Portafoglio & Ledger', desc: 'Holdings, trade ledger, dividendi e ribilanciamento', url: '/static/portfolio.html', shortcut: 'P' },
  { type: 'nav', icon: '🧠', title: 'Consigli IA & Sentiment', desc: 'Report di intelligence e raccomandazioni operative', url: '/static/advice.html', shortcut: 'C' },
  { type: 'nav', icon: '⚙️', title: 'Impostazioni & Alert', desc: 'Configurazione budget, notifiche Telegram e profilo', url: '/static/settings.html', shortcut: 'S' },
  { type: 'action', icon: '🌓', title: 'Alterna Tema (Dark/Light)', desc: 'Passa al tema chiaro o scuro', action: () => toggleTheme(), shortcut: 'T' },
  { type: 'action', icon: '❓', title: 'Scorciatoie Tastiera', desc: 'Visualizza tutte le scorciatoie disponibili', action: () => openShortcutsHelp(), shortcut: '?' }
];

const DEFAULT_POPULAR_STOCKS = [
  { ticker: 'FTSEMIB.MI', name: 'FTSE MIB', market: 'IT', icon: '🇮🇹' },
  { ticker: '^GSPC', name: 'S&P 500', market: 'US', icon: '🇺🇸' },
  { ticker: '^IXIC', name: 'NASDAQ', market: 'US', icon: '🇺🇸' },
  { ticker: 'BTC-USD', name: 'Bitcoin', market: 'CRYPTO', icon: '🪙' },
  { ticker: 'GC=F', name: 'Oro (Futures)', market: 'COMMODITY', icon: '🥇' },
  { ticker: 'RACE.MI', name: 'Ferrari N.V.', market: 'IT', icon: '🏎️' },
  { ticker: 'ENEL.MI', name: 'Enel S.p.A.', market: 'IT', icon: '⚡' },
  { ticker: 'AAPL', name: 'Apple Inc.', market: 'US', icon: '🍏' },
  { ticker: 'NVDA', name: 'NVIDIA Corp.', market: 'US', icon: '🟢' }
];

let activePaletteIndex = 0;
let paletteCurrentItems = [];
let paletteItemElements = [];
let paletteSearchDebounce = null;
let paletteSearchAbortController = null;

const injectCommandPaletteHTML = () => {
  if (document.getElementById('commandPaletteBackdrop')) return;

  const html = `
    <div class="cmd-palette-backdrop" id="commandPaletteBackdrop" role="dialog" aria-modal="true" aria-label="Command Palette">
      <div class="cmd-palette-card">
        <div class="cmd-palette-header">
          <span class="cmd-palette-search-icon">🔍</span>
          <input type="text" class="cmd-palette-input" id="cmdPaletteInput" placeholder="Cerca titolo, ticker o naviga (es. AAPL, RACE, Portafoglio)..." autocomplete="off" spellcheck="false" />
          <kbd class="kbd-badge cursor-pointer">esc</kbd>
        </div>
        <div class="cmd-palette-body" id="cmdPaletteResults">
          <!-- Popolato dinamicamente -->
        </div>
        <div class="cmd-palette-footer">
          <div class="cmd-hints">
            <span class="cmd-hint-item"><kbd class="kbd-badge">↑↓</kbd> Naviga</span>
            <span class="cmd-hint-item"><kbd class="kbd-badge">↵</kbd> Seleziona</span>
            <span class="cmd-hint-item"><kbd class="kbd-badge">esc</kbd> Chiudi</span>
          </div>
          <div class="text-xs text-muted font-mono">Stock Monitor Spotlight</div>
        </div>
      </div>
    </div>

    <div class="modal-overlay" id="shortcutsHelpModal" role="dialog" aria-modal="true" aria-labelledby="shortcutsHelpTitle">
      <div class="modal-content">
        <div class="modal-header">
          <h3 class="modal-title" id="shortcutsHelpTitle">⌨️ Scorciatoie da Tastiera</h3>
          <button class="modal-close" aria-label="Chiudi">&times;</button>
        </div>
        <p class="text-xs text-secondary mb-3">Naviga e gestisci il tuo portafoglio ad alta velocità con questi comandi globali:</p>
        <div class="shortcuts-grid">
          <div class="shortcut-row">
            <span class="shortcut-action">Apri Command Palette / Cerca</span>
            <div class="shortcut-keys"><kbd class="kbd-badge">Ctrl</kbd> + <kbd class="kbd-badge">K</kbd> / <kbd class="kbd-badge">/</kbd></div>
          </div>
          <div class="shortcut-row">
            <span class="shortcut-action">Apri questa Guida</span>
            <div class="shortcut-keys"><kbd class="kbd-badge">?</kbd></div>
          </div>
          <div class="shortcut-row">
            <span class="shortcut-action">Chiudi Finestre e Modal</span>
            <div class="shortcut-keys"><kbd class="kbd-badge">Esc</kbd></div>
          </div>
        </div>
        <div class="flex justify-end mt-3">
          <button class="btn btn-primary">Ho capito</button>
        </div>
      </div>
    </div>
  `;

  document.body.insertAdjacentHTML('beforeend', html);

  const backdrop = document.getElementById('commandPaletteBackdrop');
  backdrop.addEventListener('click', (e) => {
    if (e.target === backdrop) closeCommandPalette();
  });

  // Badge "esc": chiude la palette
  backdrop.querySelector('.cmd-palette-header .kbd-badge')?.addEventListener('click', closeCommandPalette);

  // Guida scorciatoie: overlay, pulsante di chiusura e "Ho capito"
  const shortcutsModal = document.getElementById('shortcutsHelpModal');
  if (shortcutsModal) {
    shortcutsModal.addEventListener('click', (e) => {
      if (e.target === shortcutsModal) closeShortcutsHelp();
    });
    shortcutsModal.querySelector('.modal-close')?.addEventListener('click', closeShortcutsHelp);
    shortcutsModal.querySelector('.modal-content .btn-primary')?.addEventListener('click', closeShortcutsHelp);
  }

  // Delegated click sui risultati (bound una sola volta)
  const results = document.getElementById('cmdPaletteResults');
  if (results) {
    results.addEventListener('click', (e) => {
      const itemEl = e.target.closest('.cmd-palette-item');
      if (!itemEl) return;
      const idx = parseInt(itemEl.dataset.idx, 10);
      if (!isNaN(idx) && paletteCurrentItems[idx]) {
        executePaletteItem(paletteCurrentItems[idx]);
      }
    });
  }

  const input = document.getElementById('cmdPaletteInput');
  input.addEventListener('input', (e) => {
    const q = e.target.value.trim();
    clearTimeout(paletteSearchDebounce);
    paletteSearchDebounce = setTimeout(() => {
      renderCommandPaletteResults(q);
    }, 300);
  });

  input.addEventListener('keydown', (e) => {
    if (e.key === 'ArrowDown') {
      e.preventDefault();
      if (paletteCurrentItems.length > 0) {
        activePaletteIndex = (activePaletteIndex + 1) % paletteCurrentItems.length;
        updatePaletteSelection();
      }
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      if (paletteCurrentItems.length > 0) {
        activePaletteIndex = (activePaletteIndex - 1 + paletteCurrentItems.length) % paletteCurrentItems.length;
        updatePaletteSelection();
      }
    } else if (e.key === 'Enter') {
      e.preventDefault();
      if (paletteCurrentItems.length > 0 && paletteCurrentItems[activePaletteIndex]) {
        executePaletteItem(paletteCurrentItems[activePaletteIndex]);
      }
    }
  });
};

const executePaletteItem = (item) => {
  closeCommandPalette();
  if (item.type === 'stock') {
    if (window.openStockModal) {
      window.openStockModal(item.ticker);
    }
  } else if (item.type === 'nav') {
    if (item.url) window.location.href = item.url;
  } else if (item.type === 'action') {
    if (typeof item.action === 'function') item.action();
  }
};

const updatePaletteSelection = () => {
  paletteItemElements.forEach((el, idx) => {
    if (idx === activePaletteIndex) {
      el.classList.add('active');
      el.scrollIntoView({ block: 'nearest' });
    } else {
      el.classList.remove('active');
    }
  });
};

const renderCommandPaletteResults = async (query = '') => {
  const container = document.getElementById('cmdPaletteResults');
  if (!container) return;

  // Annulla la ricerca precedente ancora in volo
  if (paletteSearchAbortController) {
    paletteSearchAbortController.abort();
    paletteSearchAbortController = null;
  }

  const q = query.toLowerCase();
  paletteCurrentItems = [];
  activePaletteIndex = 0;

  // 1. Filtra elementi di navigazione
  const matchedNav = COMMAND_NAV_ITEMS.filter(item => 
    !q || 
    item.title.toLowerCase().includes(q) || 
    item.desc.toLowerCase().includes(q) || 
    (item.shortcut && item.shortcut.toLowerCase() === q)
  );

  let stockResults = [];
  if (q.length >= 2) {
    // Filtro istantaneo locale sui titoli predefiniti/noti
    const localMatches = DEFAULT_POPULAR_STOCKS.filter(s => 
      s.ticker.toLowerCase().includes(q) || 
      (s.name && s.name.toLowerCase().includes(q))
    );
    paletteSearchAbortController = new AbortController();
    const controller = paletteSearchAbortController;
    try {
      const remote = await api.searchStocks(query, { signal: controller.signal });
      if (controller.signal.aborted) return;
      const combined = [...localMatches];
      for (const r of remote) {
        if (!combined.some(c => c.ticker === r.ticker)) combined.push(r);
      }
      stockResults = combined;
    } catch (e) {
      if (e && e.name === 'AbortError') return;
      stockResults = localMatches;
    }
  } else if (!q) {
    stockResults = DEFAULT_POPULAR_STOCKS;
  }

  let html = '';

  if (matchedNav.length > 0) {
    html += `<div class="cmd-palette-category">⚡ Navigazione & Azioni Rapide</div>`;
    matchedNav.forEach(item => {
      const idx = paletteCurrentItems.length;
      paletteCurrentItems.push(item);
      html += `
        <div class="cmd-palette-item ${idx === 0 ? 'active' : ''}" data-idx="${idx}">
          <div class="cmd-item-left">
            <span class="cmd-item-icon">${item.icon}</span>
            <div>
              <div class="cmd-item-title">${item.title}</div>
              <div class="cmd-item-desc">${item.desc}</div>
            </div>
          </div>
          <div class="cmd-item-right">
            ${item.shortcut ? `<kbd class="kbd-badge">${item.shortcut}</kbd>` : ''}
          </div>
        </div>
      `;
    });
  }

  if (stockResults.length > 0) {
    const headerTitle = q ? '📈 Titoli Corrispondenti' : '⭐ Titoli & Indici Chiave';
    html += `<div class="cmd-palette-category">${headerTitle}</div>`;
    stockResults.slice(0, 8).forEach(s => {
      const idx = paletteCurrentItems.length;
      const isIT = (s.market === 'IT' || (s.ticker || '').endsWith('.MI'));
      const flag = s.icon || (isIT ? '🇮🇹' : '🇺🇸');
      const stockItem = { type: 'stock', ticker: s.ticker, name: s.name, market: s.market };
      paletteCurrentItems.push(stockItem);

      html += `
        <div class="cmd-palette-item ${idx === 0 ? 'active' : ''}" data-idx="${idx}">
          <div class="cmd-item-left">
            <span class="cmd-item-icon">${escapeHtml(flag)}</span>
            <div>
              <div class="cmd-item-title font-mono">${escapeHtml(s.ticker)} <span class="text-xs text-secondary font-normal">— ${escapeHtml(s.name || '')}</span></div>
              <div class="cmd-item-desc">Apri analisi fondamentale, RSI, grafici e scheda titolo</div>
            </div>
          </div>
          <div class="cmd-item-right">
            <span class="badge ${isIT ? 'badge-primary' : 'badge-hold'} text-xs">${escapeHtml(s.market || (isIT ? 'IT' : 'US'))}</span>
            <span class="text-muted text-xs">↵</span>
          </div>
        </div>
      `;
    });
  }

  if (paletteCurrentItems.length === 0) {
    html = `<div class="text-muted text-xs py-8 text-center">Nessun risultato trovato per "${escapeHtml(query)}". Premi <kbd class="kbd-badge">esc</kbd> per chiudere.</div>`;
  }

  container.innerHTML = html;
  paletteItemElements = Array.from(container.querySelectorAll('.cmd-palette-item'));
};

const openCommandPalette = () => {
  injectCommandPaletteHTML();
  const backdrop = document.getElementById('commandPaletteBackdrop');
  const input = document.getElementById('cmdPaletteInput');
  if (!backdrop || !input) return;
  backdrop.classList.add('active');
  input.value = '';
  renderCommandPaletteResults('');
  setTimeout(() => input.focus(), 60);
};

const closeCommandPalette = () => {
  const backdrop = document.getElementById('commandPaletteBackdrop');
  if (backdrop) backdrop.classList.remove('active');
  // Annulla ricerca/debounce pendenti: non devono scrivere nella DOM nascosta.
  if (paletteSearchAbortController) {
    paletteSearchAbortController.abort();
    paletteSearchAbortController = null;
  }
  clearTimeout(paletteSearchDebounce);
  paletteSearchDebounce = null;
};

const openShortcutsHelp = () => {
  closeCommandPalette();
  injectCommandPaletteHTML();
  const modal = document.getElementById('shortcutsHelpModal');
  if (modal) modal.classList.add('active');
};

const closeShortcutsHelp = () => {
  const modal = document.getElementById('shortcutsHelpModal');
  if (modal) modal.classList.remove('active');
};

const initGlobalKeyboardShortcuts = () => {
  window.addEventListener('keydown', (e) => {
    const activeTag = document.activeElement ? document.activeElement.tagName.toLowerCase() : '';
    const isInput = activeTag === 'input' || activeTag === 'textarea' || document.activeElement?.isContentEditable;

    // Ctrl+K o Cmd+K
    if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k') {
      e.preventDefault();
      openCommandPalette();
      return;
    }

    // '/' quando non si sta digitando in un campo
    if (e.key === '/' && !isInput) {
      e.preventDefault();
      openCommandPalette();
      return;
    }

    // Escape chiude tutto
    if (e.key === 'Escape') {
      closeCommandPalette();
      closeShortcutsHelp();
      const sidebar = document.querySelector('.sidebar');
      if (sidebar && sidebar.classList.contains('open')) {
        sidebar.classList.remove('open');
        document.getElementById('sidebarBackdrop')?.classList.remove('active');
      }
      if (document.getElementById('stockDeepDiveModal')?.classList.contains('active')) {
        disposeModalChart();
      }
      document.querySelectorAll('.modal-overlay.active').forEach(m => m.classList.remove('active'));
      document.querySelectorAll('.autocomplete-dropdown, #autocompleteResults, #wlAutocompleteResults').forEach(drop => {
        drop.style.display = 'none';
      });
      return;
    }

    // '?' apre la guida scorciatoie
    if (e.key === '?' && !isInput) {
      e.preventDefault();
      openShortcutsHelp();
      return;
    }
  });
};

const initApp = () => {
  initTheme();
  initSidebar();
  checkAuth();
  initTickerMarquee();
  injectStockModalHTML();
  initSteppers();
  injectCommandPaletteHTML();
  initGlobalKeyboardShortcuts();

  // Listen for theme changes to update modal chart
  window.addEventListener('themeChanged', () => {
    if (modalChart) {
      const colors = getChartThemeColors();
      modalChart.applyOptions({
        layout: { textColor: colors.textColor },
        grid: {
          vertLines: { color: colors.gridColor },
          horzLines: { color: colors.gridColor }
        }
      });
      modalAreaSeries?.applyOptions({
        topColor: colors.topColor,
        bottomColor: colors.bottomColor,
        lineColor: colors.lineColor
      });
      modalCandleSeries?.applyOptions({
        upColor: colors.upColor,
        downColor: colors.downColor,
        borderUpColor: colors.upColor,
        borderDownColor: colors.downColor,
        wickUpColor: colors.upColor,
        wickDownColor: colors.downColor
      });
      modalVolumeSeries?.applyOptions({ color: colors.volumeColor });
      if (rawCandlesData.length > 0) applyModalChartData();
    }
  });

  // Attach global click listener for stock tickers: agisce solo su elementi con data-stock.
  // I link senza data-stock (es. "Tutti ➔") devono navigare normalmente.
  document.addEventListener('click', (e) => {
    const target = e.target.closest('[data-stock]');
    if (!target) return;
    const ticker = target.dataset.stock;
    if (ticker) {
      e.preventDefault();
      openStockModal(ticker);
    }
  });
};

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', initApp);
} else {
  initApp();
}

