import { api } from './api.js?v=3.0.0';
import { formatCurrency, formatPercent, showToast, escapeHtml, openMarketEditor } from './app.js?v=3.0.0';

let watchlistData = [];

// Converte in numero finito; null/undefined/'' -> null (così 0 resta un valore valido).
const toFiniteNumberOrNull = (value) => {
  if (value === null || value === undefined || value === '') return null;
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
};

const renderSkeletons = () => {
  const tbody = document.getElementById('watchlistTableBody');
  if (tbody) {
    tbody.innerHTML = `
      <tr><td colspan="9"><div class="skeleton skeleton-row"></div></td></tr>
      <tr><td colspan="9"><div class="skeleton skeleton-row"></div></td></tr>
      <tr><td colspan="9"><div class="skeleton skeleton-row"></div></td></tr>
    `;
  }
};

const renderWatchlist = () => {
  const tbody = document.getElementById('watchlistTableBody');
  const query = document.getElementById('watchlistSearch')?.value.trim().toUpperCase() || '';
  if (!tbody) return;

  const filtered = query
    ? watchlistData.filter(item => String(item.ticker || '').toUpperCase().includes(query) || String(item.name || '').toUpperCase().includes(query))
    : watchlistData;

  if (filtered.length === 0) {
    tbody.innerHTML = `
      <tr>
        <td colspan="9" class="text-center text-muted py-8">
          ${watchlistData.length === 0 ? 'Nessun titolo nel radar. Clicca su <strong>"➕ Aggiungi Titolo al Radar"</strong> per iniziare.' : 'Nessun risultato corrispondente al filtro.'}
        </td>
      </tr>
    `;
    return;
  }

  tbody.innerHTML = filtered.map(item => {
    const isUp = item.change_percent >= 0;
    const sign = isUp ? '+' : '';
    const flag = item.market === 'IT' ? '🇮🇹' : (item.market === 'EU' ? '🇪🇺' : '🇺🇸');
    const pctRaw = toFiniteNumberOrNull(item.fifty_two_week_pct);
    const pct = Math.max(0, Math.min(100, pctRaw !== null ? pctRaw : 50));

    // Numerici API: coercizione + guardie per non rompere il render con stringhe/null.
    // 0 è un valore valido (es. yield 0%), quindi si distingue solo null/undefined/''.
    const rsiNum = toFiniteNumberOrNull(item.rsi);
    const rsiText = rsiNum !== null ? rsiNum : '--';
    const peNum = toFiniteNumberOrNull(item.pe_ratio);
    const peText = peNum !== null ? peNum.toFixed(1) : '--';
    const dyNum = toFiniteNumberOrNull(item.dividend_yield);
    const dyText = dyNum !== null ? `${dyNum.toFixed(2)}%` : '--';

    // Alert Badge
    let alertHtml = '<span class="text-xs text-muted">Nessuno</span>';
    if (item.alert_triggered) {
      alertHtml = `<span class="badge badge-triggered" title="Alert Scattato! Prezzo oltre la soglia">🚨 Scattato!</span>`;
    } else if (item.alert_above || item.alert_below) {
      const aboveStr = item.alert_above ? `▲ > ${formatCurrency(item.alert_above, item.currency)}` : '';
      const belowStr = item.alert_below ? `▼ < ${formatCurrency(item.alert_below, item.currency)}` : '';
      const txt = [aboveStr, belowStr].filter(Boolean).join('<br>');
      alertHtml = `<span class="badge badge-alert" title="Alert Attivo">${txt}</span>`;
    }

    return `
      <tr id="wl-row-${item.id}">
        <td>
          <div class="flex items-center gap-2">
            <button class="btn btn-ghost btn-sm" data-action="edit-market" data-ticker="${escapeHtml(item.ticker)}" data-market="${escapeHtml(item.market || '')}" title="Modifica mercato" aria-label="Modifica mercato di ${escapeHtml(item.ticker)}">${flag}</button>
            <div>
              <a href="#" class="stock-ticker-link font-bold font-mono" data-stock="${escapeHtml(item.ticker)}">${escapeHtml(item.ticker)}</a>
              <div class="text-xs text-secondary">${escapeHtml(item.name || item.ticker)}</div>
              ${item.notes ? `<div class="text-2xs text-muted mt-0.5" title="${escapeHtml(item.notes)}">📝 ${escapeHtml(item.notes.substring(0, 26))}</div>` : ''}
            </div>
          </div>
        </td>
        <td class="text-right font-mono font-bold">${formatCurrency(item.current_price, item.currency)}</td>
        <td class="text-right font-mono font-bold ${isUp ? 'text-profit' : 'text-loss'}">
          ${sign}${formatCurrency(item.change_abs, item.currency)} (${formatPercent(item.change_percent)})
        </td>
        <td>
          <div class="range-bar-container">
            <div class="range-bar-track">
              <div class="range-bar-fill"></div>
              <div class="range-bar-pin" style="left: ${pct}%;"></div>
            </div>
            <div class="range-bar-labels">
              <span>${formatCurrency(item.fifty_two_week_low, item.currency)}</span>
              <span>${formatCurrency(item.fifty_two_week_high, item.currency)}</span>
            </div>
          </div>
        </td>
        <td class="text-center">
          <span class="badge ${escapeHtml(item.rsi_badge || 'badge-hold')}" title="RSI a 14 periodi">${rsiText} (${escapeHtml(item.rsi_status || 'Neutro')})</span>
        </td>
        <td class="text-center">
          <button class="btn btn-ghost btn-sm btn-alert" data-action="edit-alert" data-id="${item.id}" data-ticker="${escapeHtml(item.ticker)}" data-above="${escapeHtml(item.alert_above ?? '')}" data-below="${escapeHtml(item.alert_below ?? '')}" title="Modifica Alert">
            ${alertHtml}
          </button>
        </td>
        <td class="text-right font-mono text-xs">${peText}</td>
        <td class="text-right font-mono text-xs text-profit">${dyText}</td>
        <td class="text-center">
          <div class="flex justify-center gap-1.5 flex-wrap">
            <button class="btn btn-ghost btn-sm" data-action="open-stock" data-ticker="${escapeHtml(item.ticker)}" title="Apri Scheda Completa" aria-label="Analisi e scheda completa per ${escapeHtml(item.ticker)}">
              🔍
            </button>
            <button class="btn btn-ghost btn-sm" data-action="edit-alert" data-id="${item.id}" data-ticker="${escapeHtml(item.ticker)}" data-above="${escapeHtml(item.alert_above ?? '')}" data-below="${escapeHtml(item.alert_below ?? '')}" title="Imposta Alert Prezzo" aria-label="Imposta alert di prezzo per ${escapeHtml(item.ticker)}">
              🔔
            </button>
            <button class="btn btn-primary btn-sm" data-action="add-holding" data-ticker="${escapeHtml(item.ticker)}" title="Aggiungi alle Holding" aria-label="Aggiungi ${escapeHtml(item.ticker)} al portafoglio">
              💼
            </button>
            <button class="btn btn-ghost btn-sm text-loss" data-action="remove-watchlist" data-id="${item.id}" data-ticker="${escapeHtml(item.ticker)}" title="Rimuovi dal radar" aria-label="Rimuovi ${escapeHtml(item.ticker)} dalla watchlist">
              🗑️
            </button>
          </div>
        </td>
      </tr>
    `;
  }).join('');
};

const updateStats = () => {
  const countEl = document.getElementById('statWatchlistCount');
  const gainersEl = document.getElementById('statWatchlistGainers');
  const losersEl = document.getElementById('statWatchlistLosers');
  const alertsEl = document.getElementById('statWatchlistAlerts');

  const count = watchlistData.length;
  const gainers = watchlistData.filter(i => i.change_percent > 0).length;
  const losers = watchlistData.filter(i => i.change_percent < 0).length;
  const activeAlerts = watchlistData.filter(i => i.alert_above || i.alert_below || i.alert_triggered).length;

  if (countEl) countEl.textContent = count;
  if (gainersEl) gainersEl.textContent = gainers;
  if (losersEl) losersEl.textContent = losers;
  if (alertsEl) alertsEl.textContent = activeAlerts;
};

const loadWatchlist = async () => {
  try {
    renderSkeletons();
    watchlistData = await api.getWatchlist();
    updateStats();
    renderWatchlist();
  } catch (e) {
    showToast('Errore nel caricamento della Watchlist', 'error');
  }
};

const removeFromWatchlist = async (id, ticker) => {
  try {
    await api.removeFromWatchlist(id);
    const removedItem = watchlistData.find(w => w.id === id);
    showToast(`${ticker} rimosso dalla Watchlist`, 'info', 'Annulla', async () => {
      if (removedItem) {
        await api.addToWatchlist({
          ticker: removedItem.ticker,
          notes: removedItem.notes,
          alert_above: removedItem.alert_above,
          alert_below: removedItem.alert_below
        });
        loadWatchlist();
      }
    });
    loadWatchlist();
  } catch (e) {
    showToast(e.message || 'Errore durante la rimozione', 'error');
  }
};

// Edit Alert Modal
const openEditAlertModal = (id, ticker, above, below) => {
  document.getElementById('editAlertItemId').value = id;
  document.getElementById('editAlertTickerLabel').textContent = `Imposta soglie per ${ticker}`;
  document.getElementById('editAlertAbove').value = above !== null && above !== undefined ? above : '';
  document.getElementById('editAlertBelow').value = below !== null && below !== undefined ? below : '';
  document.getElementById('editAlertModal').classList.add('active');
};

const closeEditAlertModal = () => {
  document.getElementById('editAlertModal').classList.remove('active');
};

// Add Modal
const addModal = document.getElementById('addWatchlistModal');
const openAddModal = () => {
  document.getElementById('addWatchlistForm').reset();
  addModal.classList.add('active');
  document.getElementById('wlTickerInput').focus();
};
const closeAddModal = () => addModal.classList.remove('active');

const initWatchlist = () => {
  loadWatchlist();

  document.getElementById('btnOpenAddWatchlist')?.addEventListener('click', openAddModal);
  document.getElementById('closeAddWatchlistModal')?.addEventListener('click', closeAddModal);
  document.getElementById('cancelAddWatchlist')?.addEventListener('click', closeAddModal);

  document.getElementById('closeEditAlertModal')?.addEventListener('click', closeEditAlertModal);
  document.getElementById('cancelEditAlert')?.addEventListener('click', closeEditAlertModal);

  // Delegated row actions (avoids inline handlers with interpolated tickers)
  const tableBody = document.getElementById('watchlistTableBody');
  if (tableBody) {
    tableBody.addEventListener('click', (e) => {
      const btn = e.target.closest('[data-action]');
      if (!btn) return;
      const action = btn.dataset.action;
      const ticker = btn.dataset.ticker || '';

      if (action === 'open-stock') {
        if (window.openStockModal) window.openStockModal(ticker);
      } else if (action === 'add-holding') {
        window.location.href = `/static/portfolio.html?add=${encodeURIComponent(ticker)}`;
      } else if (action === 'remove-watchlist') {
        removeFromWatchlist(parseInt(btn.dataset.id, 10), ticker);
      } else if (action === 'edit-alert') {
        const id = parseInt(btn.dataset.id, 10);
        const above = btn.dataset.above !== '' ? parseFloat(btn.dataset.above) : null;
        const below = btn.dataset.below !== '' ? parseFloat(btn.dataset.below) : null;
        openEditAlertModal(id, ticker, above, below);
      } else if (action === 'edit-market') {
        openMarketEditor(ticker, btn.dataset.market, () => loadWatchlist());
      }
    });
  }

  let searchTimer = null;
  document.getElementById('watchlistSearch')?.addEventListener('input', () => {
    clearTimeout(searchTimer);
    searchTimer = setTimeout(renderWatchlist, 250);
  });

  // Form Edit Alert Submit
  document.getElementById('editAlertForm')?.addEventListener('submit', async (e) => {
    e.preventDefault();
    const id = parseInt(document.getElementById('editAlertItemId').value);
    const aboveVal = document.getElementById('editAlertAbove').value;
    const belowVal = document.getElementById('editAlertBelow').value;

    const data = {
      alert_above: aboveVal !== '' ? parseFloat(aboveVal) : null,
      alert_below: belowVal !== '' ? parseFloat(belowVal) : null
    };

    try {
      await api.updateWatchlistAlert(id, data);
      showToast('Alert aggiornato con successo!', 'success');
      closeEditAlertModal();
      loadWatchlist();
    } catch (err) {
      showToast(err.message || 'Errore durante il salvataggio dell\'alert', 'error');
    }
  });

  // Form Add Submit
  document.getElementById('addWatchlistForm')?.addEventListener('submit', async (e) => {
    e.preventDefault();
    const ticker = document.getElementById('wlTickerInput').value.trim().toUpperCase();
    const notes = document.getElementById('wlNotesInput').value.trim();
    const aboveVal = document.getElementById('wlAlertAboveInput').value;
    const belowVal = document.getElementById('wlAlertBelowInput').value;

    if (!ticker) return;

    try {
      const res = await api.addToWatchlist({
        ticker,
        notes: notes || null,
        alert_above: aboveVal !== '' ? parseFloat(aboveVal) : null,
        alert_below: belowVal !== '' ? parseFloat(belowVal) : null
      });
      showToast(res.message || `${ticker} aggiunto al Radar!`, 'success');
      closeAddModal();
      loadWatchlist();
    } catch (err) {
      showToast(err.message || 'Errore durante l\'aggiunta', 'error');
    }
  });

  // Autocomplete
  let timeout = null;
  let requestSeq = 0;
  const input = document.getElementById('wlTickerInput');
  const resultsDiv = document.getElementById('wlAutocompleteResults');

  if (input && resultsDiv) {
    input.addEventListener('input', (e) => {
      clearTimeout(timeout);
      const seq = ++requestSeq;
      const q = e.target.value.trim();
      if (q.length < 2) {
        resultsDiv.style.display = 'none';
        return;
      }
      timeout = setTimeout(async () => {
        try {
          const results = await api.searchStocks(q);
          if (seq !== requestSeq) return; // risposta obsoleta
          if (results && results.length > 0) {
            resultsDiv.innerHTML = results.map(r => `
              <div class="autocomplete-item" data-ticker="${escapeHtml(r.ticker)}">
                <strong class="text-primary font-mono">${escapeHtml(r.ticker)}</strong> — <span class="text-secondary">${escapeHtml(r.name)}</span>
              </div>
            `).join('');
            resultsDiv.style.display = 'block';
          } else {
            resultsDiv.style.display = 'none';
          }
        } catch (e) {
          if (seq !== requestSeq) return;
          resultsDiv.style.display = 'none';
        }
      }, 250);
    });

    resultsDiv.addEventListener('click', (e) => {
      const option = e.target.closest('.autocomplete-item[data-ticker]');
      if (!option) return;
      input.value = option.dataset.ticker;
      resultsDiv.style.display = 'none';
    });
  }
};

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', initWatchlist);
} else {
  initWatchlist();
}
