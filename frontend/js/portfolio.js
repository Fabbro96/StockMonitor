import { api } from './api.js?v=3.0.0';
import { formatCurrency, formatPercent, showLoading, hideLoading, showToast, getTheme, escapeHtml, openMarketEditor } from './app.js?v=3.0.0';

let portfolioData = [];
let summaryData = {};
let modifiedHoldings = new Map();
let currentAllocView = localStorage.getItem('portfolio_alloc_view') || 'stock'; // 'stock' or 'market'

// Helper: bandiera mercato (IT→🇮🇹, EU→🇪🇺, resto→🇺🇸). Niente default USA per l'Europa.
const marketFlag = (market) => {
  const m = (market || '').toUpperCase();
  if (m === 'IT') return '🇮🇹';
  if (m === 'EU') return '🇪🇺';
  return '🇺🇸';
};

const getPieColors = () => getTheme() === 'light'
  ? ['#2563eb', '#0f8a4d', '#d1242f', '#b45309', '#6d28d9', '#0e7490', '#be185d', '#4f46e5', '#0f766e']
  : ['#5b9dff', '#4cc38a', '#f26a76', '#e3a008', '#a78bfa', '#22d3ee', '#f472b6', '#818cf8', '#2dd4bf'];

const renderSkeletons = () => {
  const tbody = document.getElementById('portfolioTableBody');
  if (tbody) {
    tbody.innerHTML = `
      <tr><td colspan="9"><div class="skeleton skeleton-row"></div></td></tr>
      <tr><td colspan="9"><div class="skeleton skeleton-row"></div></td></tr>
      <tr><td colspan="9"><div class="skeleton skeleton-row"></div></td></tr>
    `;
  }
};

const drawPieChart = (data) => {
  const canvas = document.getElementById('allocationChart');
  if (!canvas) return;
  const ctx = canvas.getContext('2d');
  
  const dpr = window.devicePixelRatio || 1;
  const displayWidth = 190;
  const displayHeight = 190;

  if (canvas.width !== displayWidth * dpr || canvas.height !== displayHeight * dpr) {
    canvas.width = displayWidth * dpr;
    canvas.height = displayHeight * dpr;
    canvas.style.width = `${displayWidth}px`;
    canvas.style.height = `${displayHeight}px`;
  }
  
  ctx.save();
  ctx.scale(dpr, dpr);
  ctx.clearRect(0, 0, displayWidth, displayHeight);
  
  const centerX = displayWidth / 2;
  const centerY = displayHeight / 2;
  const outerRadius = Math.min(centerX, centerY) - 8;
  const innerRadius = outerRadius * 0.58;

  const colors = getPieColors();

  if (!data || data.length === 0) {
    ctx.fillStyle = getTheme() === 'light' ? 'rgba(37, 99, 235, 0.10)' : 'rgba(91, 157, 255, 0.14)';
    ctx.beginPath();
    ctx.arc(centerX, centerY, outerRadius, 0, 2 * Math.PI);
    ctx.fill();
    ctx.restore();
    const legend = document.getElementById('allocationLegend');
    if (legend) legend.innerHTML = '<div class="text-muted text-center text-xs">Nessun dato</div>';
    return;
  }

  const total = data.reduce((sum, item) => sum + (item.value || 0), 0);
  if (total <= 0) {
    ctx.restore();
    return;
  }

  let startAngle = -0.5 * Math.PI;

  data.forEach((item, i) => {
    const sliceAngle = (item.value / total) * 2 * Math.PI;
    ctx.fillStyle = colors[i % colors.length];
    ctx.beginPath();
    ctx.arc(centerX, centerY, outerRadius, startAngle, startAngle + sliceAngle);
    ctx.arc(centerX, centerY, innerRadius, startAngle + sliceAngle, startAngle, true);
    ctx.closePath();
    ctx.fill();
    startAngle += sliceAngle;
  });

  ctx.restore();

  const legend = document.getElementById('allocationLegend');
  if (legend) {
    legend.innerHTML = data.slice(0, 7).map((item, i) => `
      <div class="flex items-center justify-between">
        <div class="flex items-center gap-2">
          <div style="width:10px;height:10px;background-color:${colors[i % colors.length]};border-radius:3px;"></div>
          <span class="font-bold text-primary font-mono">${escapeHtml(item.label)}</span>
        </div>
        <span class="font-mono text-secondary">${formatPercent((item.value / total) * 100)}</span>
      </div>
    `).join('');
  }
};

const updateAllocationChart = () => {
  if (currentAllocView === 'market') {
    const allocMap = summaryData.market_allocation || {};
    const marketLabels = { 'IT': '🇮🇹 Italia', 'US': '🇺🇸 USA', 'EU': '🇪🇺 Europa' };
    const data = Object.entries(allocMap).map(([k, v]) => ({
      label: marketLabels[k] || k,
      value: v
    })).filter(d => d.value > 0);
    drawPieChart(data);
  } else {
    const data = portfolioData.map(item => ({
      label: item.ticker,
      value: item.total_value || ((item.current_price || item.avg_purchase_price) * item.quantity)
    })).filter(d => d.value > 0);
    drawPieChart(data);
  }
};

const updateSaveBar = () => {
  const saveBar = document.getElementById('saveBar');
  const countEl = document.getElementById('pendingChangesCount');
  if (!saveBar) return;
  
  const count = modifiedHoldings.size;
  if (count > 0) {
    saveBar.style.display = 'flex';
    countEl.textContent = `Hai ${count} posizion${count === 1 ? 'e modificata' : 'i modificate'}. Clicca "Salva Modifiche" per applicarle.`;
  } else {
    saveBar.style.display = 'none';
  }
};

const triggerSeedDemo = async () => {
  try {
    showLoading('portfolioContent');
    const res = await api.seedDemo();
    showToast(res.message || 'Demo inizializzata con successo!', 'success');
    loadPortfolio();
  } catch (e) {
    showToast(e.message || 'Errore nel caricamento della demo', 'error');
  } finally {
    hideLoading('portfolioContent');
  }
};

const renderTable = () => {
  const tbody = document.getElementById('portfolioTableBody');
  if (!tbody) return;
  
  if (portfolioData.length === 0) {
    tbody.innerHTML = `
      <tr>
        <td colspan="9" class="text-center text-muted py-8">
          Nessun titolo in portafoglio. 
          <div class="mt-3 flex justify-center gap-2">
            <button class="btn btn-primary" data-action="open-add-holding">➕ Aggiungi Holding</button>
            <button class="btn btn-ghost" id="btnEmptySeedDemo" data-action="seed-demo">🚀 Inizializza Demo</button>
          </div>
        </td>
      </tr>
    `;
    return;
  }

  tbody.innerHTML = portfolioData.map(item => {
    const isModified = modifiedHoldings.has(item.id);
    const mod = modifiedHoldings.get(item.id);
    
    const displayQty = mod ? mod.newQty : item.quantity;
    const displayPrice = mod ? mod.newPrice : item.avg_purchase_price;
    const currentPrice = item.current_price || displayPrice;
    
    const totalValue = displayQty * currentPrice;
    const invested = displayQty * displayPrice;
    const pnlAbs = totalValue - invested;
    const pnlPct = invested > 0 ? (pnlAbs / invested) * 100 : 0;
    const flag = marketFlag(item.market);

    return `
      <tr class="${isModified ? 'row-modified' : ''}" data-id="${item.id}">
        <td>
          <div class="flex items-center gap-2">
            <button class="btn btn-ghost btn-sm" data-action="edit-market" data-ticker="${escapeHtml(item.ticker)}" data-market="${escapeHtml(item.market || '')}" title="Modifica mercato" aria-label="Modifica mercato di ${escapeHtml(item.ticker)}">${flag}</button>
            <div>
              <a href="#" class="stock-ticker-link font-bold font-mono" data-stock="${escapeHtml(item.ticker)}">${escapeHtml(item.ticker)}</a>
              ${item.notes ? `<div class="text-2xs text-muted" title="${escapeHtml(item.notes)}">📝 ${escapeHtml(item.notes.substring(0, 20))}</div>` : ''}
            </div>
          </div>
        </td>
        <td class="text-secondary">${escapeHtml(item.name || item.ticker)}</td>
        
        <!-- Editable Quantity -->
        <td class="text-right">
          <div class="modern-stepper">
            <button type="button" class="stepper-btn dec" data-step="1" title="Diminuisci (−1, Shift: −10)" aria-label="Diminuisci quantità per ${escapeHtml(item.ticker)}">−</button>
            <input 
              type="number" 
              class="inline-input input-qty font-mono" 
              data-id="${item.id}" 
              value="${displayQty}" 
              step="1" 
              min="0"
              aria-label="Quantità per ${escapeHtml(item.ticker)}"
            >
            <button type="button" class="stepper-btn inc" data-step="1" title="Aumenta (+1, Shift: +10)" aria-label="Aumenta quantità per ${escapeHtml(item.ticker)}">+</button>
          </div>
        </td>

        <!-- Editable Purchase Price -->
        <td class="text-right">
          <div class="modern-stepper">
            <button type="button" class="stepper-btn dec" data-step="0.5" title="Diminuisci (−0.50, Shift: −5.00)" aria-label="Diminuisci prezzo di carico per ${escapeHtml(item.ticker)}">−</button>
            <input 
              type="number" 
              class="inline-input input-price font-mono" 
              data-id="${item.id}" 
              value="${displayPrice}" 
              step="any" 
              min="0"
              aria-label="Prezzo medio carico per ${escapeHtml(item.ticker)}"
            >
            <button type="button" class="stepper-btn inc" data-step="0.5" title="Aumenta (+0.50, Shift: +5.00)" aria-label="Aumenta prezzo di carico per ${escapeHtml(item.ticker)}">+</button>
          </div>
        </td>

        <td class="text-right font-mono font-bold">${formatCurrency(currentPrice, item.currency)}</td>
        <td class="text-right font-mono font-bold text-primary" id="val-${item.id}">${formatCurrency(totalValue, item.currency)}</td>
        <td class="text-right font-mono font-bold ${pnlAbs >= 0 ? 'text-profit' : 'text-loss'}" id="pnlabs-${item.id}">
          ${formatCurrency(pnlAbs, item.currency)}
        </td>
        <td class="text-right font-mono font-bold ${pnlPct >= 0 ? 'text-profit' : 'text-loss'}" id="pnlpct-${item.id}">
          ${formatPercent(pnlPct)}
        </td>
        <td class="text-center">
          <div class="flex justify-center gap-1">
            <button class="btn btn-ghost btn-sm text-loss" title="Elimina" aria-label="Elimina posizione ${escapeHtml(item.ticker)}" data-action="delete-holding" data-id="${item.id}">🗑️</button>
          </div>
        </td>
      </tr>
    `;
  }).join('');
};

const handleInlineEdit = (e) => {
  const input = e.target;
  const holdingId = parseInt(input.dataset.id);
  const row = input.closest('tr');
  
  const item = portfolioData.find(h => h.id === holdingId);
  if (!item) return;

  const qtyInput = row.querySelector('.input-qty');
  const priceInput = row.querySelector('.input-price');

  const newQty = parseFloat(qtyInput.value) || 0;
  const newPrice = parseFloat(priceInput.value) || 0;

  const isChanged = (newQty !== item.quantity) || (Math.abs(newPrice - item.avg_purchase_price) > 0.0001);

  if (isChanged) {
    modifiedHoldings.set(holdingId, {
      id: holdingId,
      ticker: item.ticker,
      originalQty: item.quantity,
      newQty: newQty,
      originalPrice: item.avg_purchase_price,
      newPrice: newPrice,
      notes: item.notes
    });
    row.classList.add('row-modified');
  } else {
    modifiedHoldings.delete(holdingId);
    row.classList.remove('row-modified');
  }

  const currentPrice = item.current_price || newPrice;
  const totalValue = newQty * currentPrice;
  const invested = newQty * newPrice;
  const pnlAbs = totalValue - invested;
  const pnlPct = invested > 0 ? (pnlAbs / invested) * 100 : 0;

  const valEl = document.getElementById(`val-${holdingId}`);
  const pnlAbsEl = document.getElementById(`pnlabs-${holdingId}`);
  const pnlPctEl = document.getElementById(`pnlpct-${holdingId}`);

  if (valEl) valEl.textContent = formatCurrency(totalValue, item.currency);
  if (pnlAbsEl) {
    pnlAbsEl.textContent = formatCurrency(pnlAbs, item.currency);
    pnlAbsEl.className = `text-right font-mono font-bold ${pnlAbs >= 0 ? 'text-profit' : 'text-loss'}`;
  }
  if (pnlPctEl) {
    pnlPctEl.textContent = formatPercent(pnlPct);
    pnlPctEl.className = `text-right font-mono font-bold ${pnlPct >= 0 ? 'text-profit' : 'text-loss'}`;
  }

  updateSaveBar();
};

const loadPortfolio = async () => {
  try {
    renderSkeletons();
    const [summaryResult, portfolioResult, settingsResult] = await Promise.all([
      api.getPortfolioSummary().catch(() => ({})),
      api.getPortfolio().catch(() => []),
      api.getSettings().catch(() => ({}))
    ]);
    summaryData = summaryResult;
    portfolioData = portfolioResult;
    const userSettings = settingsResult;

    document.getElementById('totalValue').textContent = formatCurrency(summaryData.total_value || 0);
    document.getElementById('totalInvested').textContent = formatCurrency(summaryData.total_invested || 0);
    document.getElementById('totalCount').textContent = summaryData.holdings_count || portfolioData.length;
    
    // Budget & Liquidity display
    const userBudget = userSettings.total_budget || userSettings.budget || 10000;
    const budgetDisplayEl = document.getElementById('userBudgetDisplay');
    if (budgetDisplayEl) {
      budgetDisplayEl.textContent = formatCurrency(userBudget);
    }
    const deployedPct = userBudget > 0 ? ((summaryData.total_value || 0) / userBudget) * 100 : 0;
    const deployedBadgeEl = document.getElementById('budgetDeployedBadge');
    if (deployedBadgeEl) {
      deployedBadgeEl.textContent = `Allocato: ${deployedPct.toFixed(1)}%`;
      deployedBadgeEl.style.color = deployedPct > 100 ? 'var(--danger-color)' : 'var(--primary-color)';
    }
    const remainingCash = Math.max(0, userBudget - (summaryData.total_value || 0));
    const remainingCashEl = document.getElementById('userRemainingCash');
    if (remainingCashEl) {
      remainingCashEl.textContent = formatCurrency(remainingCash);
    }

    const pnlEl = document.getElementById('totalPnL');
    const totPnL = summaryData.total_pnl || 0;
    const totPct = summaryData.total_pnl_percent || 0;
    pnlEl.textContent = `${formatCurrency(totPnL)} (${formatPercent(totPct)})`;
    pnlEl.className = `text-2xl font-bold font-mono mt-1 ${totPnL >= 0 ? 'text-profit' : 'text-loss'}`;

    const divEl = document.getElementById('totalDividends');
    if (divEl) {
      divEl.textContent = `${formatCurrency(summaryData.estimated_annual_dividends || 0)}/anno (${(summaryData.estimated_dividend_yield || 0).toFixed(2)}%)`;
    }

    modifiedHoldings.clear();
    updateSaveBar();
    renderTable();
    updateAllocationChart();
    loadRealizedPnL();
    loadTransactions();
    loadDividends();

  } catch (error) {
    showToast('Errore nel caricamento del portafoglio', 'error');
  }
};

const loadRealizedPnL = async () => {
  try {
    const res = await api.getRealizedPnL();
    const el = document.getElementById('totalRealizedPnL');
    if (el && res) {
      const net = res.net_realized_profit || 0;
      el.textContent = `${net >= 0 ? '+' : ''}${formatCurrency(net)}`;
      el.className = `text-2xl font-bold font-mono mt-1 ${net >= 0 ? 'text-profit' : 'text-loss'}`;
    }
  } catch (e) {
    console.error('Error loading realized PnL:', e);
  }
};

let currentTxFilter = 'ALL';

const loadTransactions = async (type = currentTxFilter) => {
  currentTxFilter = type;
  const tbody = document.getElementById('transactionsTableBody');
  if (!tbody) return;

  try {
    const params = type !== 'ALL' ? { type } : {};
    const txs = await api.getTransactions(params);

    if (!txs || txs.length === 0) {
      tbody.innerHTML = `
        <tr>
          <td colspan="10" class="text-center text-muted py-6">
            Nessuna transazione registrata ${type !== 'ALL' ? `con filtro <strong>${escapeHtml(type)}</strong>` : ''}.
            <div class="mt-2">
              <button class="btn btn-primary btn-sm" data-action="open-tx-modal">➕ Registra la prima esecuzione</button>
            </div>
          </td>
        </tr>
      `;
      return;
    }

    tbody.innerHTML = txs.map(tx => {
      const isBuy = tx.type === 'BUY';
      const isSell = tx.type === 'SELL';
      const isDiv = tx.type === 'DIVIDEND';

      const typeBadge = isBuy 
        ? '<span class="badge badge-buy">🟢 BUY</span>'
        : (isSell ? '<span class="badge badge-sell">🔴 SELL</span>' : '<span class="badge badge-hold">💰 DIVIDENDO</span>');

      const dateStr = tx.transaction_date ? tx.transaction_date.substring(0, 10) : '--';
      
      let pnlHtml = '--';
      if (isSell && tx.realized_pnl !== null) {
        const pnl = tx.realized_pnl;
        pnlHtml = `<span class="${pnl >= 0 ? 'text-profit' : 'text-loss'} font-bold font-mono">${pnl >= 0 ? '+' : ''}${formatCurrency(pnl, tx.currency)}</span>`;
      } else if (isDiv && tx.realized_pnl !== null) {
        pnlHtml = `<span class="text-profit font-bold font-mono">+${formatCurrency(tx.realized_pnl, tx.currency)}</span>`;
      }

      return `
        <tr>
          <td class="font-mono text-xs text-muted">${escapeHtml(dateStr)}</td>
          <td>${typeBadge}</td>
          <td>
            <a href="#" class="stock-ticker-link font-bold font-mono" data-stock="${escapeHtml(tx.ticker)}">${escapeHtml(tx.ticker)}</a>
          </td>
          <td class="text-secondary text-xs">${escapeHtml(tx.name || tx.ticker)}</td>
          <td class="text-right font-mono">${isDiv ? '--' : tx.quantity}</td>
          <td class="text-right font-mono">${formatCurrency(tx.price, tx.currency)}</td>
          <td class="text-right font-mono text-muted text-xs">${tx.fee > 0 ? formatCurrency(tx.fee, 'EUR') : '0 €'}</td>
          <td class="text-right font-mono">${pnlHtml}</td>
          <td class="text-xs text-muted" title="${escapeHtml(tx.notes || '')}">${tx.notes ? escapeHtml(tx.notes.substring(0, 25)) : '--'}</td>
          <td class="text-center">
            <button class="btn btn-ghost btn-sm text-loss" title="Elimina transazione" aria-label="Elimina transazione #${tx.id}" data-action="delete-transaction" data-id="${tx.id}">🗑️</button>
          </td>
        </tr>
      `;
    }).join('');
  } catch (e) {
    tbody.innerHTML = `<tr><td colspan="10" class="text-center text-loss py-4">Errore nel caricamento del Trade Ledger</td></tr>`;
  }
};

window.deleteTransaction = async (id) => {
  if (!confirm(`Sei sicuro di voler eliminare la transazione #${id}?`)) return;
  try {
    await api.deleteTransaction(id);
    showToast('Transazione rimossa dal registro', 'info');
    loadTransactions();
    loadRealizedPnL();
  } catch (e) {
    showToast(e.message || 'Errore durante la cancellazione', 'error');
  }
};

window.deleteHolding = async (id) => {
  const item = portfolioData.find(h => h.id === id);
  const ticker = item ? item.ticker : 'questa holding';
  
  try {
    await api.deleteHolding(id);
    showToast(`${ticker} eliminata con successo`, 'info', 'Annulla', async () => {
      if (item) {
        await api.addHolding({
          ticker: item.ticker,
          quantity: item.quantity,
          avg_purchase_price: item.avg_purchase_price,
          notes: item.notes
        });
        loadPortfolio();
      }
    });
    loadPortfolio();
  } catch (e) {
    showToast('Errore durante l\'eliminazione', 'error');
  }
};

// ==========================================
// Smart Rebalancer
// ==========================================
const SCOPE_LABELS = { MARKET: 'Mercato', TICKERS: 'Ticker', CASH: 'Liquidità' };

const renderRebalanceTargets = (targets) => {
  const tbody = document.getElementById('targetsTableBody');
  if (!tbody) return;

  if (!targets || targets.length === 0) {
    tbody.innerHTML = '<tr><td colspan="4" class="text-center text-muted py-3 text-xs">Nessuna allocazione target definita.</td></tr>';
    return;
  }

  tbody.innerHTML = targets.map(t => `
    <tr data-target-id="${t.id}">
      <td class="font-bold text-primary">${escapeHtml(t.name)}</td>
      <td class="text-center">
        <span class="badge badge-hold">${escapeHtml(SCOPE_LABELS[t.scope_type] || t.scope_type || '')}</span>
        ${t.scope_value ? `<span class="text-xs text-muted font-mono">${escapeHtml(t.scope_value)}</span>` : ''}
      </td>
      <td class="text-right font-mono font-bold text-primary">${(Number(t.target_percent) || 0).toFixed(1)}%</td>
      <td class="text-center">
        <button class="btn btn-ghost btn-sm text-loss" data-action="delete-target" data-target-id="${t.id}" data-target-name="${escapeHtml(t.name)}" title="Elimina target" aria-label="Elimina target ${escapeHtml(t.name)}">🗑️</button>
      </td>
    </tr>
  `).join('');
};

const loadRebalanceTargets = async () => {
  const tbody = document.getElementById('targetsTableBody');
  if (!tbody) return;

  try {
    const targets = await api.getRebalanceTargets();
    renderRebalanceTargets(targets);
  } catch (e) {
    tbody.innerHTML = '<tr><td colspan="4" class="text-center text-loss py-3 text-xs">Errore nel caricamento delle allocazioni target.</td></tr>';
  }
};

const handleAddTarget = async () => {
  const nameEl = document.getElementById('targetName');
  const pctEl = document.getElementById('targetPct');
  const scopeTypeEl = document.getElementById('targetScopeType');
  const scopeValueEl = document.getElementById('targetScopeValue');
  if (!nameEl || !pctEl || !scopeTypeEl || !scopeValueEl) return;

  const name = nameEl.value.trim();
  const targetPercent = parseFloat(pctEl.value);
  const scopeType = (scopeTypeEl.value || 'MARKET').toUpperCase();
  const scopeValue = scopeValueEl.value.trim().toUpperCase();

  if (!name) {
    showToast('Inserisci un nome per l\'allocazione target', 'error');
    return;
  }
  if (isNaN(targetPercent) || targetPercent < 0 || targetPercent > 100) {
    showToast('La percentuale target deve essere un numero tra 0 e 100', 'error');
    return;
  }
  if (scopeType !== 'CASH' && !scopeValue) {
    showToast(scopeType === 'MARKET' ? 'Per lo scope Mercato indica il valore (IT, US, EU)' : 'Per lo scope Ticker indica i simboli (es. AAPL,MSFT)', 'error');
    return;
  }

  const btn = document.getElementById('btnAddTarget');
  if (btn) btn.disabled = true;
  try {
    await api.addRebalanceTarget({
      name,
      target_percent: targetPercent,
      scope_type: scopeType,
      scope_value: scopeValue
    });
    nameEl.value = '';
    pctEl.value = '';
    scopeValueEl.value = '';
    showToast('Allocazione target aggiunta con successo', 'success');
    await loadRebalanceTargets();
  } catch (e) {
    showToast(e.message || 'Errore durante l\'aggiunta dell\'allocazione target', 'error');
  } finally {
    if (btn) btn.disabled = false;
  }
};

const renderRebalancePlan = (plan) => {
  const container = document.getElementById('rebalanceResult');
  if (!container) return;

  const orders = Array.isArray(plan?.orders) ? plan.orders : [];

  if (orders.length === 0) {
    container.className = 'text-xs text-muted py-4 text-center';
    container.innerHTML = plan?.portfolio_empty
      ? 'Portafoglio vuoto: aggiungi delle posizioni per generare un piano di ribilanciamento.'
      : 'Il portafoglio è già allineato alle allocazioni target: nessun ordine necessario.';
    return;
  }

  container.className = '';
  container.innerHTML = `
    <div class="flex justify-between items-center mb-2 flex-wrap gap-2">
      <span class="text-xs text-muted">Valore totale (incl. liquidità): <strong class="font-mono text-primary">${formatCurrency(plan.total_value || 0)}</strong></span>
      <span class="text-xs text-muted">BUY: <strong class="font-mono text-profit">${formatCurrency(plan.total_buy_value || 0)}</strong> • SELL: <strong class="font-mono text-loss">${formatCurrency(plan.total_sell_value || 0)}</strong></span>
    </div>
    <div class="table-container table-bordered">
      <table>
        <thead>
          <tr>
            <th class="text-center w-80">Lato</th>
            <th>Titolo</th>
            <th class="text-right">Quantità</th>
            <th class="text-right">Prezzo Stimato</th>
            <th class="text-right">Importo</th>
          </tr>
        </thead>
        <tbody>
          ${orders.map(o => {
            const isBuy = o.side === 'BUY';
            return `
              <tr>
                <td class="text-center">
                  <span class="badge ${isBuy ? 'badge-buy' : 'badge-sell'}">${isBuy ? '🟢 BUY' : '🔴 SELL'}</span>
                </td>
                <td>
                  <a href="#" class="stock-ticker-link font-bold font-mono" data-stock="${escapeHtml(o.ticker)}">${escapeHtml(o.ticker)}</a>
                  <div class="text-xs text-secondary">${escapeHtml(o.name || '')}${o.allocation_name ? ` • ${escapeHtml(o.allocation_name)}` : ''}</div>
                </td>
                <td class="text-right font-mono">${o.quantity}</td>
                <td class="text-right font-mono">${formatCurrency(o.estimated_price, o.currency)}</td>
                <td class="text-right font-mono font-bold ${isBuy ? 'text-profit' : 'text-loss'}">${formatCurrency(o.estimated_value, o.currency)}</td>
              </tr>
            `;
          }).join('')}
        </tbody>
      </table>
    </div>
  `;
};

const handleRebalancePreview = async () => {
  const container = document.getElementById('rebalanceResult');
  if (!container) return;

  const cashInput = document.getElementById('rebalanceCashInput');
  let extraCash = parseFloat(cashInput?.value);
  if (isNaN(extraCash) || extraCash < 0) extraCash = 0;

  const btn = document.getElementById('btnRebalancePreview');
  if (btn) {
    btn.disabled = true;
    btn.textContent = 'Calcolo...';
  }
  container.className = 'text-xs text-muted py-4 text-center';
  container.innerHTML = '<div class="flex justify-center items-center py-2"><div class="spinner"></div></div>';

  try {
    const plan = await api.rebalancePreview(extraCash);
    renderRebalancePlan(plan);
  } catch (e) {
    container.className = 'text-xs py-4 text-center';
    container.innerHTML = `<div class="text-loss">${escapeHtml(e.message || 'Errore durante il calcolo del piano')}</div>`;
    showToast(e.message || 'Errore durante il calcolo del piano di ribilanciamento', 'error');
  } finally {
    if (btn) {
      btn.disabled = false;
      btn.textContent = 'Calcola Ordini ➔';
    }
  }
};

// ==========================================
// Dividendi (markup caricato in parallelo: guardie null ovunque)
// ==========================================
const renderDividends = (data) => {
  const tbody = document.getElementById('dividendsTableBody');
  const emptyEl = document.getElementById('dividendsEmpty');
  const holdings = Array.isArray(data?.holdings) ? data.holdings : [];

  const totalAnnualEl = document.getElementById('divTotalAnnual');
  if (totalAnnualEl) totalAnnualEl.textContent = formatCurrency(data?.total_annual_dividend_eur || 0);
  const totalMonthlyEl = document.getElementById('divTotalMonthly');
  if (totalMonthlyEl) totalMonthlyEl.textContent = formatCurrency(data?.total_monthly_dividend_eur || 0);
  const yocEl = document.getElementById('divYieldOnCost');
  if (yocEl) yocEl.textContent = `${(Number(data?.portfolio_yield_on_cost) || 0).toFixed(2)}%`;

  if (emptyEl) emptyEl.hidden = holdings.length > 0;
  if (!tbody) return;

  if (holdings.length === 0) {
    tbody.innerHTML = emptyEl
      ? ''
      : '<tr><td colspan="8" class="text-center text-muted py-4">Nessun dividendo stimato per le posizioni attuali.</td></tr>';
    return;
  }

  tbody.innerHTML = holdings.map(h => {
    const flag = marketFlag(h.market);
    return `
      <tr>
        <td>
          <div class="flex items-center gap-2">
            <span>${flag}</span>
            <a href="#" class="stock-ticker-link font-bold font-mono" data-stock="${escapeHtml(h.ticker)}">${escapeHtml(h.ticker)}</a>
          </div>
        </td>
        <td class="text-secondary">${escapeHtml(h.name || h.ticker)}</td>
        <td class="text-right font-mono">${h.quantity ?? 0}</td>
        <td class="text-right font-mono">${formatCurrency(h.annual_dividend_per_share || 0, h.currency)}</td>
        <td class="text-right font-mono">${(Number(h.dividend_yield_pct) || 0).toFixed(2)}%</td>
        <td class="text-right font-mono font-bold text-profit">${(Number(h.yield_on_cost_pct) || 0).toFixed(2)}%</td>
        <td class="text-right font-mono font-bold text-profit">${formatCurrency(h.annual_income_eur || 0)}</td>
        <td class="text-right font-mono text-secondary">${formatCurrency(h.monthly_income_eur || 0)}</td>
      </tr>
    `;
  }).join('');
};

const loadDividends = async () => {
  const card = document.getElementById('dividendsCard');
  const tbody = document.getElementById('dividendsTableBody');
  if (!card && !tbody) return; // markup Dividendi non ancora presente

  const emptyEl = document.getElementById('dividendsEmpty');
  const btn = document.getElementById('btnRefreshDividends');
  if (btn) btn.disabled = true;
  try {
    const data = await api.getDividends();
    renderDividends(data);
  } catch (e) {
    if (tbody) {
      tbody.innerHTML = '<tr><td colspan="8" class="text-center text-loss py-4">Errore nel caricamento dei dividendi</td></tr>';
    }
    if (emptyEl) emptyEl.hidden = true;
    showToast(e.message || 'Errore nel caricamento dei dividendi', 'error');
  } finally {
    if (btn) btn.disabled = false;
  }
};

// Modals
const holdingModal = document.getElementById('holdingModal');
const confirmSaveModal = document.getElementById('confirmSaveModal');
const importModal = document.getElementById('importModal');
const txModal = document.getElementById('txModal');

const openAddModal = (defaultTicker = '') => {
  document.getElementById('holdingForm').reset();
  document.getElementById('holdingId').value = '';
  document.getElementById('modalTitle').textContent = 'Aggiungi Titolo al Portafoglio';
  if (defaultTicker) {
    document.getElementById('tickerInput').value = defaultTicker;
  }
  holdingModal.classList.add('active');
};

window.openTxModal = (ticker = '') => {
  if (!txModal) return;
  document.getElementById('txForm')?.reset();
  if (ticker) {
    const input = document.getElementById('txTickerInput');
    if (input) input.value = ticker;
  }
  const dateInput = document.getElementById('txDateInput');
  if (dateInput) {
    dateInput.value = new Date().toISOString().substring(0, 10);
  }
  txModal.classList.add('active');
};

const closeHoldingModal = () => holdingModal?.classList.remove('active');
const closeConfirmModal = () => confirmSaveModal?.classList.remove('active');
const closeImportModal = () => importModal?.classList.remove('active');
const closeTxModal = () => txModal?.classList.remove('active');

// Autocomplete riutilizzabile (ricerca ticker con debounce)
const setupAutocomplete = (inputEl, resultsEl, onSelect) => {
  if (!inputEl || !resultsEl) return;
  let timeout = null;

  inputEl.addEventListener('input', (e) => {
    clearTimeout(timeout);
    const q = e.target.value.trim();
    if (q.length < 2) {
      resultsEl.style.display = 'none';
      return;
    }
    timeout = setTimeout(async () => {
      try {
        const results = await api.searchStocks(q);
        if (results && results.length > 0) {
          resultsEl.innerHTML = results.map(r => `
            <div class="autocomplete-item" data-ticker="${escapeHtml(r.ticker)}">
              <strong class="text-primary font-mono">${escapeHtml(r.ticker)}</strong> — <span class="text-secondary">${escapeHtml(r.name)}</span>
            </div>
          `).join('');
          resultsEl.style.display = 'block';
        } else {
          resultsEl.style.display = 'none';
        }
      } catch (e) {
        resultsEl.style.display = 'none';
      }
    }, 250);
  });

  resultsEl.addEventListener('click', (e) => {
    const option = e.target.closest('.autocomplete-item[data-ticker]');
    if (!option) return;
    if (onSelect) onSelect(option.dataset.ticker);
    else inputEl.value = option.dataset.ticker;
    resultsEl.style.display = 'none';
  });
};

const initPortfolio = () => {
  loadPortfolio();
  loadRebalanceTargets();

  // Smart Rebalancer: aggiunta target + piano ordini
  document.getElementById('btnAddTarget')?.addEventListener('click', handleAddTarget);
  document.getElementById('btnRebalancePreview')?.addEventListener('click', handleRebalancePreview);

  const targetsBody = document.getElementById('targetsTableBody');
  if (targetsBody) {
    targetsBody.addEventListener('click', async (e) => {
      const btn = e.target.closest('[data-action="delete-target"]');
      if (!btn) return;
      const id = parseInt(btn.dataset.targetId, 10);
      if (isNaN(id)) return;
      const targetName = btn.dataset.targetName || 'questa allocazione';
      if (!confirm(`Eliminare l'allocazione target "${targetName}"?`)) return;
      try {
        await api.deleteRebalanceTarget(id);
        showToast('Allocazione target rimossa', 'info');
        await loadRebalanceTargets();
      } catch (err) {
        showToast(err.message || 'Errore durante la rimozione dell\'allocazione target', 'error');
      }
    });
  }

  // Dividendi: refresh manuale
  document.getElementById('btnRefreshDividends')?.addEventListener('click', loadDividends);

  // Azioni delegate su tabelle (evita handler inline con id interpolati)
  document.getElementById('portfolioTableBody')?.addEventListener('click', (e) => {
    const addHoldingBtn = e.target.closest('[data-action="open-add-holding"]');
    if (addHoldingBtn) {
      openAddModal();
      return;
    }
    const seedBtn = e.target.closest('[data-action="seed-demo"]');
    if (seedBtn) {
      triggerSeedDemo();
      return;
    }
    const btn = e.target.closest('[data-action="delete-holding"]');
    if (btn) {
      const id = parseInt(btn.dataset.id, 10);
      if (!isNaN(id) && window.deleteHolding) window.deleteHolding(id);
      return;
    }
    const marketBtn = e.target.closest('[data-action="edit-market"]');
    if (marketBtn) {
      openMarketEditor(marketBtn.dataset.ticker, marketBtn.dataset.market, () => loadPortfolio());
    }
  });

  // Inline edit delegato (qty/prezzo): un solo listener, niente riattacco per render
  document.getElementById('portfolioTableBody')?.addEventListener('input', (e) => {
    if (!e.target.closest('.input-qty, .input-price')) return;
    handleInlineEdit(e);
  });

  document.getElementById('transactionsTableBody')?.addEventListener('click', (e) => {
    const openTxBtn = e.target.closest('[data-action="open-tx-modal"]');
    if (openTxBtn) {
      window.openTxModal();
      return;
    }
    const btn = e.target.closest('[data-action="delete-transaction"]');
    if (!btn) return;
    const id = parseInt(btn.dataset.id, 10);
    if (!isNaN(id) && window.deleteTransaction) window.deleteTransaction(id);
  });

  // Listen for theme changes to redraw canvas chart
  window.addEventListener('themeChanged', () => {
    updateAllocationChart();
  });

  // Check URL query params for ?add=TICKER
  const params = new URLSearchParams(window.location.search);
  const addTicker = params.get('add');
  if (addTicker) {
    openAddModal(addTicker.toUpperCase());
  }

  // Allocation toggle with persistence
  const allocGroup = document.getElementById('allocTypeGroup');
  if (allocGroup) {
    allocGroup.querySelectorAll('.timeframe-btn').forEach(btn => {
      if (btn.dataset.type === currentAllocView) {
        allocGroup.querySelectorAll('.timeframe-btn').forEach(b => {
          b.classList.remove('active');
          b.setAttribute('aria-pressed', 'false');
        });
        btn.classList.add('active');
        btn.setAttribute('aria-pressed', 'true');
      }

      btn.addEventListener('click', () => {
        allocGroup.querySelectorAll('.timeframe-btn').forEach(b => {
          b.classList.remove('active');
          b.setAttribute('aria-pressed', 'false');
        });
        btn.classList.add('active');
        btn.setAttribute('aria-pressed', 'true');
        currentAllocView = btn.dataset.type;
        localStorage.setItem('portfolio_alloc_view', currentAllocView);
        updateAllocationChart();
      });
    });
  }

  document.getElementById('btnAddHolding')?.addEventListener('click', () => openAddModal());
  document.getElementById('closeModal')?.addEventListener('click', closeHoldingModal);
  document.getElementById('cancelModal')?.addEventListener('click', closeHoldingModal);

  document.getElementById('closeConfirmModal')?.addEventListener('click', closeConfirmModal);
  document.getElementById('cancelConfirmModal')?.addEventListener('click', closeConfirmModal);

  document.getElementById('closeImportModal')?.addEventListener('click', closeImportModal);
  document.getElementById('cancelImportModal')?.addEventListener('click', closeImportModal);

  // Cancel Pending Changes
  document.getElementById('btnCancelChanges')?.addEventListener('click', () => {
    if (confirm('Vuoi annullare tutte le modifiche non salvate?')) {
      modifiedHoldings.clear();
      updateSaveBar();
      renderTable();
      showToast('Modifiche annullate', 'info');
    }
  });

  // Open Confirm Save Modal
  document.getElementById('btnSaveChanges')?.addEventListener('click', () => {
    if (modifiedHoldings.size === 0) return;

    const listEl = document.getElementById('confirmChangesList');
    listEl.innerHTML = Array.from(modifiedHoldings.values()).map(m => `
      <div class="change-item">
        <div>
          <span class="font-bold text-primary font-mono">${escapeHtml(m.ticker)}</span>
        </div>
        <div class="text-right font-mono text-xs">
          <div>Q.tà: <span class="text-muted line-through">${m.originalQty}</span> ➔ <strong class="text-profit">${m.newQty}</strong></div>
          <div>Prz: <span class="text-muted line-through">${formatCurrency(m.originalPrice)}</span> ➔ <strong class="text-profit">${formatCurrency(m.newPrice)}</strong></div>
        </div>
      </div>
    `).join('');

    confirmSaveModal.classList.add('active');
  });

  // Execute Batch Save
  document.getElementById('btnExecuteSave')?.addEventListener('click', async () => {
    const btn = document.getElementById('btnExecuteSave');
    btn.disabled = true;
    btn.textContent = 'Salvataggio in corso...';

    const updates = Array.from(modifiedHoldings.values()).map(m => ({
      id: m.id,
      quantity: m.newQty,
      avg_purchase_price: m.newPrice,
      notes: m.notes
    }));

    try {
      const res = await api.batchUpdateHoldings(updates);
      showToast(`Salvate ${res.updated_count || updates.length} posizioni con successo!`, 'success');
      closeConfirmModal();
      loadPortfolio();
    } catch (err) {
      showToast(err.message || 'Errore durante il salvataggio delle modifiche', 'error');
    } finally {
      btn.disabled = false;
      btn.textContent = '✅ Sì, Conferma e Salva';
    }
  });

  // Add Single Holding
  document.getElementById('holdingForm')?.addEventListener('submit', async (e) => {
    e.preventDefault();
    const data = {
      ticker: document.getElementById('tickerInput').value.trim().toUpperCase(),
      quantity: parseFloat(document.getElementById('qtyInput').value),
      avg_purchase_price: parseFloat(document.getElementById('priceInput').value),
      purchase_date: document.getElementById('dateInput').value || null,
      notes: document.getElementById('notesInput').value || null
    };

    try {
      await api.addHolding(data);
      showToast(`${data.ticker} salvata nel portafoglio!`, 'success');
      closeHoldingModal();
      loadPortfolio();
    } catch (err) {
      showToast(err.message || 'Errore durante il salvataggio', 'error');
    }
  });

  // Autocomplete
  const tickerInput = document.getElementById('tickerInput');
  setupAutocomplete(tickerInput, document.getElementById('autocompleteResults'), (ticker) => {
    if (tickerInput) tickerInput.value = ticker;
  });

  // Export CSV
  document.getElementById('btnExport')?.addEventListener('click', async () => {
    try {
      const token = localStorage.getItem('auth_token');
      const res = await fetch('/api/portfolio/export?format=csv', {
        headers: token ? { 'Authorization': `Bearer ${token}` } : {}
      });
      if (!res.ok) throw new Error('Errore durante l\'esportazione');

      const blob = await res.blob();
      const url = window.URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      const today = new Date().toISOString().split('T')[0];
      a.download = `portafoglio_${today}.csv`;
      document.body.appendChild(a);
      a.click();
      a.remove();
      window.URL.revokeObjectURL(url);

      showToast('Portafoglio esportato in CSV!', 'success');
    } catch (err) {
      showToast(err.message || 'Errore durante l\'esportazione CSV', 'error');
    }
  });

  // Import CSV
  document.getElementById('btnImport')?.addEventListener('click', () => {
    document.getElementById('csvFileInput').value = '';
    importModal.classList.add('active');
  });

  document.getElementById('btnSubmitImport')?.addEventListener('click', async () => {
    const fileInput = document.getElementById('csvFileInput');
    if (fileInput.files.length === 0) {
      showToast('Seleziona un file CSV da caricare', 'error');
      return;
    }

    const btn = document.getElementById('btnSubmitImport');
    btn.disabled = true;
    btn.textContent = 'Importazione in corso...';

    try {
      const result = await api.importPortfolio(fileInput.files[0]);
      closeImportModal();
      const importErrors = result?.errors || [];
      if (importErrors.length > 0) {
        const first = String(importErrors[0] || '').slice(0, 160);
        showToast(`Importazione con errori (${importErrors.length}): ${first}`, 'error');
      } else {
        showToast(`Importate: ${result.imported || 0} nuove, Aggiornate: ${result.updated || 0}`, 'success');
      }
      loadPortfolio();
    } catch (err) {
      showToast(err.message || 'Errore durante l\'importazione del file CSV', 'error');
    } finally {
      btn.disabled = false;
      btn.textContent = 'Carica e Importa';
    }
  });

  // Trade Ledger Modal & Filter Handlers
  document.getElementById('btnOpenTxModal')?.addEventListener('click', () => window.openTxModal());
  document.getElementById('closeTxModal')?.addEventListener('click', closeTxModal);
  document.getElementById('cancelTxModal')?.addEventListener('click', closeTxModal);

  document.querySelectorAll('.tx-filter-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('.tx-filter-btn').forEach(b => {
        b.classList.remove('active');
        b.setAttribute('aria-pressed', 'false');
      });
      btn.classList.add('active');
      btn.setAttribute('aria-pressed', 'true');
      loadTransactions(btn.dataset.type);
    });
  });

  // Tx Autocomplete
  const txTickerInput = document.getElementById('txTickerInput');
  setupAutocomplete(txTickerInput, document.getElementById('txAutocompleteResults'), (ticker) => {
    if (txTickerInput) txTickerInput.value = ticker;
  });

  // Submit Transaction Form
  document.getElementById('txForm')?.addEventListener('submit', async (e) => {
    e.preventDefault();
    const ticker = document.getElementById('txTickerInput').value.trim().toUpperCase();
    const type = document.getElementById('txTypeSelect').value;
    const quantity = parseFloat(document.getElementById('txQtyInput').value) || 0;
    const price = parseFloat(document.getElementById('txPriceInput').value) || 0;
    const fee = parseFloat(document.getElementById('txFeeInput').value) || 0;
    const dateVal = document.getElementById('txDateInput').value;
    const notes = document.getElementById('txNotesInput').value.trim();

    if (!ticker) {
      showToast('Inserisci un ticker valido', 'error');
      return;
    }

    const data = {
      ticker,
      type,
      quantity,
      price,
      fee,
      transaction_date: dateVal ? new Date(dateVal).toISOString() : null,
      notes
    };

    const submitBtn = document.getElementById('btnSubmitTx');
    if (submitBtn) {
      submitBtn.disabled = true;
      submitBtn.textContent = 'Registrazione...';
    }

    try {
      await api.createTransaction(data);
      showToast(`Transazione ${type} per ${ticker} registrata con successo!`, 'success');
      closeTxModal();
      loadPortfolio();
    } catch (err) {
      showToast(err.message || 'Errore durante la registrazione della transazione', 'error');
    } finally {
      if (submitBtn) {
        submitBtn.disabled = false;
        submitBtn.textContent = 'Registra Transazione';
      }
    }
  });
};

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', initPortfolio);
} else {
  initPortfolio();
}
