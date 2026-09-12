import { api } from './api.js?v=3.0.0';
import { formatCurrency, formatDateTime, showLoading, hideLoading, showToast, escapeHtml } from './app.js?v=3.0.0';

let currentPage = 1;
let currentFilters = { market: '', action: '', date: '', q: '' };
let adviceRequestId = 0;

// L14: mappa unica azione → classe badge, tollerante alle varianti (includes).
const getActionBadgeClass = (action) => {
  const act = String(action || '').toUpperCase();
  if (act.includes('ACCUMULO') || act.includes('BUY')) return 'badge-buy';
  if (act.includes('PROFITTO') || act.includes('SELL') || act.includes('ALLEGGERIMENTO')) return 'badge-sell';
  return 'badge-hold';
};

const renderAdviceCard = (advice) => {
  const isFollowed = Boolean(advice.followed);
  const isIT = advice.market === 'IT';
  const flag = isIT ? '🇮🇹' : '🇺🇸';

  const actionBadge = getActionBadgeClass(advice.action);
  let actionText = '🟡 MANTENIMENTO';
  const act = (advice.action || '').toUpperCase();
  if (act.includes('ACCUMULO') || act.includes('BUY')) {
    actionText = '🟢 ACCUMULO / BUY';
  } else if (act.includes('PROFITTO') || act.includes('SELL') || act.includes('ALLEGGERIMENTO')) {
    actionText = '🔴 PRESA PROFITTO / SELL';
  } else if (act.includes('PRUDENZA')) {
    actionText = '🛡️ PRUDENZA';
  }

  // Stocks analysis schematic list
  const stocks = Array.isArray(advice.stocks_analysis) ? advice.stocks_analysis : [];
  let stocksHtml = '';
  if (stocks.length > 0) {
    stocksHtml = `
      <div class="mt-4 pt-4 border-t border-border-color">
        <div class="flex justify-between items-center mb-3 flex-wrap gap-2">
          <h4 class="text-sm font-bold text-primary flex items-center gap-2">
            <span>📋 Consigli Strategici Prioritizzati (${stocks.length}) ${flag}</span>
          </h4>
          <span class="text-xs text-muted">Ordinati per rilevanza & priorità operativa</span>
        </div>
          <div class="table-container table-bordered">
            <table>
              <thead>
                <tr>
                  <th class="w-170">Ticker & Titolo</th>
                  <th class="text-center w-110">Azione</th>
                  <th class="text-center w-110">Priorità</th>
                  <th class="text-right w-120">Target</th>
                  <th>Motivo Sintetico & Catalizzatore</th>
                  <th class="text-center w-80">Dettagli</th>
                </tr>
              </thead>
            <tbody>
              ${stocks.map(s => {
                const sAct = (s.action || 'HOLD').toUpperCase();
                const sBadge = getActionBadgeClass(sAct);
                const sLabel = (sAct.includes('BUY') || sAct.includes('ACCUMULO')) ? '🟢 COMPRA' : ((sAct.includes('SELL') || sAct.includes('PROFITTO')) ? '🔴 VENDI' : '🟡 TIENI');
                
                const prio = (s.priority || 'MEDIA').toUpperCase();
                let prioBadge = 'prio-badge-medium';
                let prioLabel = '⚡ Media';
                if (prio.includes('ALTA') || prio.includes('HIGH')) {
                  prioBadge = 'prio-badge-high';
                  prioLabel = '🚨 Alta';
                } else if (prio.includes('OPPORTUN')) {
                  prioBadge = 'prio-badge-opportunity';
                  prioLabel = '💡 Opportunità';
                } else if (prio.includes('RISCH') || prio.includes('RISK')) {
                  prioBadge = 'prio-badge-risk';
                  prioLabel = '🛡️ Rischio';
                }

                return `
                  <tr>
                    <td>
                      <a href="#" class="stock-ticker-link font-bold font-mono text-sm" data-stock="${escapeHtml(s.ticker)}">${escapeHtml(s.ticker)}</a>
                      <div class="text-xs text-muted truncate max-w-150">${escapeHtml(s.name || '')}</div>
                    </td>
                    <td class="text-center">
                      <span class="badge ${sBadge} text-xs font-semibold">${sLabel}</span>
                    </td>
                    <td class="text-center">
                      <span class="badge ${prioBadge} text-xs font-semibold">${prioLabel}</span>
                    </td>
                    <td class="text-right font-mono font-bold text-primary">
                      ${s.target_price ? formatCurrency(s.target_price) : '--'}
                    </td>
                    <td class="text-sm text-secondary leading-relaxed">
                      ${escapeHtml(s.note || s.reasoning || '--')}
                    </td>
                    <td class="text-center">
                      <button type="button" class="btn btn-ghost btn-xs py-1 px-2 text-xs" data-stock="${escapeHtml(s.ticker)}" title="Apri Scheda Tecnica">🔍</button>
                    </td>
                  </tr>
                `;
              }).join('')}
            </tbody>
          </table>
        </div>
      </div>
    `;
  }

  const followBtnHtml = isFollowed
    ? `<button class="btn btn-sm btn-success" data-follow-id="${advice.id}">
         <span>✅ Letto</span>
         <span class="text-2xs opacity-80">(Segna come Non Letto)</span>
       </button>`
    : `<button class="btn btn-sm btn-ghost" data-follow-id="${advice.id}">
         <span>👁️ Segna come Letto</span>
       </button>`;

  return `
    <div class="card advice-card ${isIT ? 'advice-it' : 'advice-us'} mb-4" id="advice-${advice.id}">
      <!-- Top header -->
      <div class="flex justify-between items-start mb-4 flex-wrap gap-2">
        <div>
          <div class="flex items-center gap-3 mb-1 flex-wrap">
            <span class="text-xl">${flag}</span>
            <h3 class="text-xl font-bold">${escapeHtml(advice.title || (isIT ? 'Borsa Italiana (Piazza Affari)' : 'Wall Street'))}</h3>
            <span class="badge ${actionBadge}">${actionText}</span>
          </div>
          <div class="text-xs text-muted">Analisi elaborata: <strong>${formatDateTime(advice.timestamp)}</strong></div>
        </div>
        <div id="follow-container-${advice.id}">
          ${followBtnHtml}
        </div>
      </div>

      <!-- Overview Section -->
      ${advice.overview ? `
      <div class="mb-4">
        <h4 class="text-xs font-bold text-muted uppercase tracking-wider mb-1">🌐 Quadro & Scenario Generale</h4>
        <p class="text-primary leading-relaxed text-base">${escapeHtml(advice.overview)}</p>
      </div>` : ''}

      <!-- Strategy Section -->
      ${advice.strategy ? `
      <div class="callout mb-4">
        <h4 class="text-xs font-bold text-muted uppercase tracking-wider mb-1">🎯 Strategia Operativa & Piano d'Azione</h4>
        <p class="text-primary leading-relaxed text-base">${escapeHtml(advice.strategy)}</p>
      </div>` : ''}

      <!-- Stocks Breakdown -->
      ${stocksHtml}

      <!-- Risks Section -->
      ${advice.risks ? `
      <div class="callout-danger mt-4">
        <h4 class="text-xs font-bold mb-1 text-danger flex items-center gap-1">
          <span>⚠️ Punti di Attenzione & Rischi Chiave</span>
        </h4>
        <p class="text-xs text-secondary leading-relaxed mb-0">${escapeHtml(advice.risks)}</p>
      </div>` : ''}

      <!-- Footer Info -->
      <div class="flex gap-4 text-xs text-muted mt-4 pt-3 border-t flex-wrap items-center justify-between">
        <div class="flex gap-4 flex-wrap">
          ${advice.confidence ? `<div>Confidenza IA: <strong class="text-primary">${escapeHtml(advice.confidence)}</strong></div>` : ''}
          ${advice.timeframe ? `<div>Orizzonte: <strong class="text-primary">${escapeHtml(advice.timeframe)}</strong></div>` : ''}
        </div>
        <div class="text-xs text-muted">Archivio Ultimi 7 Giorni • Gemini 3.7 Flash</div>
      </div>
    </div>
  `;
};

const loadAdvice = async (page = 1, append = false) => {
  const requestId = ++adviceRequestId;
  const loadMoreBtn = document.getElementById('btnLoadMore');
  if (append && loadMoreBtn) loadMoreBtn.disabled = true;
  try {
    if (!append) showLoading('adviceContent');

    const params = { page, limit: 10, days: 7, ...currentFilters };
    const response = await api.getAdvice(params);

    // M2: scarta le risposte fuori ordine (filtri/debounce/load-more
    // concorrenti) prima di qualsiasi scrittura sul DOM.
    if (requestId !== adviceRequestId) return;

    const adviceList = Array.isArray(response) ? response : (response.data || []);

    if (page === 1) {
      if (currentFilters.date) {
        document.getElementById('marketSummaryText').textContent = `Analisi storiche registrate per la giornata del ${currentFilters.date}.`;
      } else {
        document.getElementById('marketSummaryText').textContent = "Visualizzazione dei report strategici generati nell'ultima settimana, suddivisi per Borsa Italiana (Piazza Affari) e Borsa Americana (Wall Street).";
      }
    }

    const listEl = document.getElementById('adviceList');
    if (!append) listEl.innerHTML = '';

    let filtered = adviceList;
    if (currentFilters.q) {
      const query = currentFilters.q.toUpperCase();
      filtered = filtered.filter(adv => {
        const titleMatch = (adv.title || '').toUpperCase().includes(query);
        const overviewMatch = (adv.overview || '').toUpperCase().includes(query);
        const strategyMatch = (adv.strategy || '').toUpperCase().includes(query);
        const stocksMatch = (adv.stocks_analysis || []).some(s => 
          (s.ticker || '').toUpperCase().includes(query) || (s.name || '').toUpperCase().includes(query)
        );
        return titleMatch || overviewMatch || strategyMatch || stocksMatch;
      });
    }

    if (filtered.length === 0 && !append) {
      listEl.innerHTML = '<div class="card text-center text-muted py-8">Nessuna analisi strategica trovata per i criteri selezionati. Usa il pulsante "Genera Analisi Macro Ora" o seleziona un\'altra data.</div>';
      if (loadMoreBtn) loadMoreBtn.style.display = 'none';
      return;
    }

    listEl.insertAdjacentHTML('beforeend', filtered.map(renderAdviceCard).join(''));
    if (loadMoreBtn) loadMoreBtn.style.display = adviceList.length === 10 ? 'block' : 'none';

  } catch (error) {
    if (requestId === adviceRequestId) {
      showToast('Errore nel caricamento dei consigli', 'error');
    }
  } finally {
    // Solo la richiesta più recente gestisce spinner e stato del bottone.
    if (requestId === adviceRequestId) {
      hideLoading('adviceContent');
      if (loadMoreBtn) loadMoreBtn.disabled = false;
    }
  }
};

window.toggleFollow = async (id) => {
  try {
    const res = await api.followAdvice(id);
    showToast(res.followed ? 'Segnato come letto' : 'Segnato come non letto', 'success');
    
    const container = document.getElementById(`follow-container-${id}`);
    if (container) {
      const isFollowed = Boolean(res.followed);
      container.innerHTML = isFollowed
        ? `<button class="btn btn-sm btn-success" data-follow-id="${id}">
             <span>✅ Letto</span>
             <span class="text-2xs opacity-80">(Segna come Non Letto)</span>
           </button>`
        : `<button class="btn btn-sm btn-ghost" data-follow-id="${id}">
             <span>👁️ Segna come Letto</span>
           </button>`;
    }
  } catch(e) {
    showToast('Errore durante l\'aggiornamento dello stato', 'error');
  }
};

const checkMarketStatus = async () => {
  try {
    const data = await api.getDashboard();
    const marketStatus = data.market_status || {};
    const itStatus = marketStatus.IT === 'OPEN';
    const usStatus = marketStatus.US === 'OPEN';

    const badgeIT = document.getElementById('marketStatusIT');
    const badgeUS = document.getElementById('marketStatusUS');

    if (badgeIT) {
      if (itStatus) {
        badgeIT.className = 'badge badge-buy text-2xs';
        badgeIT.textContent = '🟢 Aperta (09:00-17:30)';
      } else {
        badgeIT.className = 'badge badge-sell text-2xs';
        badgeIT.textContent = '🔴 Chiusa (09:00-17:30)';
      }
    }

    if (badgeUS) {
      if (usStatus) {
        badgeUS.className = 'badge badge-buy text-2xs';
        badgeUS.textContent = '🟢 Aperta (15:30-22:00)';
      } else {
        badgeUS.className = 'badge badge-sell text-2xs';
        badgeUS.textContent = '🔴 Chiusa (15:30-22:00)';
      }
    }
  } catch(e) {
    console.error('Errore recupero stato mercati', e);
  }
};

const runSingleStockAnalysis = async () => {
  const input = document.getElementById('aiSingleTicker');
  const ticker = input.value.trim().toUpperCase();
  if (!ticker) {
    showToast('Inserisci un ticker valido da analizzare', 'error');
    return;
  }

  const resContainer = document.getElementById('singleStockAiResult');
  const btn = document.getElementById('btnAnalyzeSingle');

  btn.disabled = true;
  btn.textContent = 'Analisi in corso...';
  resContainer.style.display = 'block';
  resContainer.innerHTML = '<div class="flex justify-center items-center py-6"><div class="spinner"></div></div>';

  try {
    const result = await api.analyzeStockOnDemand(ticker);
    const actionBadgeClass = getActionBadgeClass(result.action);

    // Coercizione numerica sicura: l'output LLM non è validato e finisce in innerHTML.
    const upsideRaw = Number(result.upside_potential_pct);
    const upsidePct = Number.isFinite(upsideRaw) ? upsideRaw : 0;

    resContainer.innerHTML = `
      <div class="card callout-accent p-4">
        <div class="flex justify-between items-center mb-3 flex-wrap gap-2">
          <div class="flex items-center gap-2 flex-wrap">
            <span class="text-xl font-bold font-mono text-primary">${escapeHtml(result.ticker)}</span>
            <span class="text-sm text-secondary">${escapeHtml(result.name)}</span>
            <span class="badge ${actionBadgeClass}">${escapeHtml(result.action_label || result.action)}</span>
          </div>
          <div class="text-xs text-muted">
            Confidenza: <strong class="text-primary">${escapeHtml(result.confidence)}</strong> • Orizzonte: <strong class="text-primary">${escapeHtml(result.timeframe)}</strong>
          </div>
        </div>

        <div class="split-grid mb-3">
          <div class="callout p-2">
            <div class="text-xs text-muted">🎯 Target Price Stimato</div>
            <div class="text-lg font-bold text-primary font-mono">${formatCurrency(result.target_price)} <span class="text-xs text-profit">(+${escapeHtml(upsidePct)}%)</span></div>
          </div>
          <div class="callout p-2">
            <div class="text-xs text-muted">🛡️ Stop Loss Prudenziale</div>
            <div class="text-lg font-bold text-danger font-mono">${result.stop_loss ? formatCurrency(result.stop_loss) : '--'}</div>
          </div>
        </div>

        <p class="text-sm text-primary leading-relaxed mb-3">${escapeHtml(result.summary || '')}</p>

        <div class="split-grid mb-3 text-xs">
          <div class="callout-success p-2.5">
            <strong class="text-profit block mb-1">🟢 Bull Case & Catalizzatori</strong>
            <span class="text-secondary leading-normal">${escapeHtml(result.bull_case || '--')}</span>
          </div>
          <div class="callout-danger p-2.5">
            <strong class="text-loss block mb-1">🔴 Bear Case & Rischi</strong>
            <span class="text-secondary leading-normal">${escapeHtml(result.bear_case || '--')}</span>
          </div>
        </div>

        <div class="flex justify-between items-center flex-wrap gap-2 pt-2 border-t">
          <div class="text-xs text-secondary">💡 <strong>Strategia:</strong> ${escapeHtml(result.operational_strategy || '--')}</div>
          <button class="btn btn-ghost btn-sm" data-stock="${escapeHtml(result.ticker)}">Apri Scheda Completa ➔</button>
        </div>
      </div>
    `;
  } catch (e) {
    resContainer.innerHTML = `<div class="alert-error text-center py-4 text-xs">Errore analisi: ${escapeHtml(e.message)}</div>`;
  } finally {
    btn.disabled = false;
    btn.textContent = 'Analizza Titolo con IA ➔';
  }
};

const initAdvice = () => {
  loadAdvice(1);
  checkMarketStatus();

  // Delegated "follow" action (avoids inline handlers with interpolated ids)
  const listEl = document.getElementById('adviceList');
  listEl?.addEventListener('click', (e) => {
    const btn = e.target.closest('[data-follow-id]');
    if (!btn) return;
    const id = parseInt(btn.dataset.followId, 10);
    if (!isNaN(id) && window.toggleFollow) window.toggleFollow(id);
  });

  document.getElementById('btnAnalyzeSingle')?.addEventListener('click', runSingleStockAnalysis);
  document.getElementById('aiSingleTicker')?.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') runSingleStockAnalysis();
  });

  document.getElementById('btnLoadMore')?.addEventListener('click', () => {
    currentPage++;
    loadAdvice(currentPage, true);
  });

  const toDateInputValue = (d) => {
    const year = d.getFullYear();
    const month = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
  };

  const toDisplayDate = (dateStr) => {
    if (!dateStr) return '';
    const parts = dateStr.split('-');
    if (parts.length === 3) return `${parts[2]}/${parts[1]}/${parts[0]}`;
    return dateStr;
  };

  const dayButtons = {
    today: document.getElementById('btnFilterToday'),
    yesterday: document.getElementById('btnFilterYesterday'),
    pick: document.getElementById('btnFilterPickDay'),
  };

  const setDayButtonState = (activeType, customLabel = null) => {
    Object.values(dayButtons).forEach(btn => btn?.classList.remove('active'));
    if (activeType && dayButtons[activeType]) {
      dayButtons[activeType].classList.add('active');
    }
    if (dayButtons.pick) {
      dayButtons.pick.innerHTML = customLabel ? `📅 ${escapeHtml(customLabel)}` : 'Scegli giorno 📅';
    }
  };

  let debounceTimer;
  const applyFilters = () => {
    currentPage = 1;
    currentFilters.date = document.getElementById('filterDate').value;
    currentFilters.market = document.getElementById('filterMarket').value;
    currentFilters.action = document.getElementById('filterAction').value;
    currentFilters.q = document.getElementById('filterSearch').value;
    loadAdvice(1);
  };

  // Date Filter: Oggi
  dayButtons.today?.addEventListener('click', () => {
    const today = new Date();
    const dateStr = toDateInputValue(today);
    document.getElementById('filterDate').value = dateStr;
    setDayButtonState('today');
    applyFilters();
  });

  // Date Filter: Ieri
  dayButtons.yesterday?.addEventListener('click', () => {
    const yesterday = new Date();
    yesterday.setDate(yesterday.getDate() - 1);
    const dateStr = toDateInputValue(yesterday);
    document.getElementById('filterDate').value = dateStr;
    setDayButtonState('yesterday');
    applyFilters();
  });

  // Date Filter: Scegli giorno modal
  const datePickerModal = document.getElementById('datePickerModal');
  const customDatePickerInput = document.getElementById('customDatePickerInput');

  const openDatePicker = () => {
    const curVal = document.getElementById('filterDate').value || toDateInputValue(new Date());
    if (customDatePickerInput) customDatePickerInput.value = curVal;
    datePickerModal?.classList.add('active');
  };

  const closeDatePicker = () => {
    datePickerModal?.classList.remove('active');
  };

  dayButtons.pick?.addEventListener('click', openDatePicker);
  document.getElementById('closeDatePickerModal')?.addEventListener('click', closeDatePicker);
  document.getElementById('cancelDatePickerModal')?.addEventListener('click', closeDatePicker);

  document.getElementById('applyDatePickerModal')?.addEventListener('click', () => {
    const selectedDate = customDatePickerInput?.value;
    if (!selectedDate) {
      showToast('Seleziona una data valida', 'error');
      return;
    }
    document.getElementById('filterDate').value = selectedDate;
    setDayButtonState('pick', toDisplayDate(selectedDate));
    closeDatePicker();
    applyFilters();
  });

  // Close modal on escape or background click
  window.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && datePickerModal?.classList.contains('active')) {
      closeDatePicker();
    }
  });

  datePickerModal?.addEventListener('click', (e) => {
    if (e.target === datePickerModal) closeDatePicker();
  });

  document.getElementById('filterMarket')?.addEventListener('change', applyFilters);
  document.getElementById('filterAction')?.addEventListener('change', applyFilters);
  document.getElementById('filterSearch')?.addEventListener('input', () => {
    clearTimeout(debounceTimer);
    debounceTimer = setTimeout(applyFilters, 500);
  });

  document.getElementById('btnResetFilters')?.addEventListener('click', () => {
    document.getElementById('filterDate').value = '';
    setDayButtonState(null);
    document.getElementById('filterMarket').value = '';
    document.getElementById('filterAction').value = '';
    document.getElementById('filterSearch').value = '';
    currentFilters = { market: '', action: '', date: '', q: '' };
    currentPage = 1;
    loadAdvice(1);
  });

  const btnGenerate = document.getElementById('btnGenerate');
  btnGenerate?.addEventListener('click', async () => {
    if (btnGenerate.disabled) return; // L2: evita doppi click su ?force=true
    btnGenerate.disabled = true;
    try {
      showLoading('adviceContent');
      await api.generateAdvice(true);
      showToast('Analisi per Borsa Italiana e Americana generata con successo!', 'success');
      await loadAdvice(1);
    } catch(e) {
      showToast(e.message || 'Errore durante la generazione dell\'analisi', 'error');
    } finally {
      btnGenerate.disabled = false;
      hideLoading('adviceContent');
    }
  });
};

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', initAdvice);
} else {
  initAdvice();
}
