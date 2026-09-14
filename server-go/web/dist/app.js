/* StockMon Go — vanilla JS, niente framework né CDN.
 * API: POST /api/auth/login · GET /api/dashboard/ · GET /api/watchlist/
 *      GET /api/stocks/{t}/candles?timeframe=TF
 * ETag/If-None-Match gestito qui (304 = riusa cache in memoria).
 * Servito via embed.FS dal Go: app.js/style.css con ?v=1 + Cache-Control
 * immutable lato server (vedi README-NAS-GO.md).
 */
"use strict";
const $ = (id) => document.getElementById(id);
const LS_KEY = "sm_token";
const REFRESH_MS = 300_000;   // auto-refresh 5 min (allineato a cache server 300s)
const VIS_STALE_MS = 60_000;  // visibilitychange: ricarica se dati più vecchi di 60s

let token = localStorage.getItem(LS_KEY) || "";
let lastLoad = 0;
const etags = new Map(); // url -> {etag, data}
const eur = new Intl.NumberFormat("it-IT", { style: "currency", currency: "EUR" });
const num2 = new Intl.NumberFormat("it-IT", { maximumFractionDigits: 2 });

/* ---------- HTTP con ETag ---------- */
async function api(path, opts = {}) {
  const cached = etags.get(path);
  const headers = { ...(opts.headers || {}) };
  if (token) headers.Authorization = "Bearer " + token;
  if (cached && !opts.noEtag) headers["If-None-Match"] = cached.etag;
  const res = await fetch(path, { ...opts, headers });
  if (res.status === 304 && cached) return { data: cached.data, stale: res.headers.get("X-Data-Stale") === "true", notModified: true };
  if (res.status === 401) { logout(true); throw new Error("unauthorized"); }
  if (!res.ok) {
    let msg = "HTTP " + res.status;
    try { const j = await res.json(); if (j.detail) msg = j.detail; } catch (_) {}
    throw new Error(msg);
  }
  const data = await res.json();
  const etag = res.headers.get("ETag");
  if (etag) etags.set(path, { etag, data });
  return { data, stale: res.headers.get("X-Data-Stale") === "true" };
}

/* ---------- Auth ---------- */
async function login(u, p) {
  const res = await fetch("/api/auth/login", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ username: u, password: p }),
  });
  if (!res.ok) {
    let msg = "Credenziali non corrette.";
    try { const j = await res.json(); if (j.detail) msg = j.detail; } catch (_) {}
    throw new Error(msg);
  }
  const j = await res.json();
  token = j.access_token || "";
  localStorage.setItem(LS_KEY, token);
  showApp();
  await loadAll();
}

function logout(expired) {
  token = "";
  localStorage.removeItem(LS_KEY);
  etags.clear();
  $("app").hidden = true;
  $("login").hidden = false;
  $("logout").hidden = true;
  if (expired) $("loginErr").textContent = "Sessione scaduta, rieffettua il login.";
}

function showApp() {
  $("login").hidden = true;
  $("app").hidden = false;
  $("logout").hidden = false;
  $("loginErr").textContent = "";
}

/* ---------- Dashboard ---------- */
function cls(v) { return v > 0 ? "up" : v < 0 ? "dn" : ""; }
function signed(v, fmt) {
  const s = (fmt || num2).format(v);
  return (v > 0 ? "+" : "") + s;
}

function renderDashboard(d) {
  const s = d.portfolio_summary || {};
  $("cVal").textContent = eur.format(s.total_value || 0);
  $("cInv").textContent = "investito " + eur.format(s.total_invested || 0);
  const pnl = $("cPnl");
  pnl.textContent = signed(s.total_pnl || 0, eur);
  pnl.className = "big " + cls(s.total_pnl || 0);
  $("cPnlP").textContent = signed(s.total_pnl_percent || 0) + " %";
  const day = $("cDay");
  day.textContent = signed(s.daily_pnl || 0, eur);
  day.className = "big " + cls(s.daily_pnl || 0);
  $("cDayP").textContent = signed(s.daily_pnl_percent || 0) + " % oggi";
  $("cPos").textContent = String(s.holdings_count ?? 0);
  $("cAlert").textContent = "alert attivi: " + (d.active_alerts_count ?? 0);

  const m = d.market_status || {};
  $("mkt").innerHTML = "IT <b>" + (m.IT || "?") + "</b> · US <b>" + (m.US || "?") + "</b>";

  const adv = d.recent_advices || [];
  $("adv").innerHTML = adv.length ? "" : "<li>Nessun consiglio recente.</li>";
  for (const a of adv.slice(0, 6)) {
    const li = document.createElement("li");
    const t = document.createElement("div");
    t.textContent = (a.ticker ? a.ticker + " — " : "") + (a.title || "Consiglio");
    const sm = document.createElement("small");
    sm.textContent = [a.market, a.action, a.confidence, a.timestamp].filter(Boolean).join(" · ");
    li.append(t, sm);
    $("adv").append(li);
  }
}

/* ---------- Watchlist ---------- */
let tickers = [];
function renderWatchlist(list) {
  const tb = $("wl").querySelector("tbody");
  tb.innerHTML = "";
  tickers = (list || []).map((w) => w.ticker);
  $("wlCount").textContent = tickers.length + " titoli";
  const sel = $("ticker");
  const prev = sel.value;
  sel.innerHTML = "";
  for (const w of list || []) {
    const tr = document.createElement("tr");
    tr.dataset.ticker = w.ticker;
    const chg = w.change_percent || 0;
    tr.innerHTML =
      "<td><b></b><br><small class='muted'></small></td>" +
      "<td class='num'></td><td class='num " + cls(chg) + "'></td>" +
      "<td class='num'></td><td></td>";
    tr.children[0].querySelector("b").textContent = w.ticker;
    tr.children[0].querySelector("small").textContent = w.name || "";
    tr.children[1].textContent = num2.format(w.current_price || 0) + " " + (w.currency || "");
    tr.children[2].textContent = signed(chg) + " %";
    tr.children[3].textContent = w.rsi != null ? num2.format(w.rsi) : "—";
    tr.children[4].textContent = w.alert_triggered ? "🔔" : (w.alert_above || w.alert_below ? "⏰" : "—");
    tr.title = w.alert_triggered ? "Alert scattato" : w.ticker;
    tr.addEventListener("click", () => {
      sel.value = w.ticker;
      tb.querySelectorAll("tr").forEach((r) => r.classList.remove("sel"));
      tr.classList.add("sel");
      loadCandles();
    });
    tb.append(tr);
    const o = document.createElement("option");
    o.value = o.textContent = w.ticker;
    sel.append(o);
  }
  if (tickers.includes(prev)) sel.value = prev;
}

/* ---------- Candele (canvas nativo) ---------- */
function normTime(t) {
  if (typeof t === "number") return new Date(t * 1000);
  const d = new Date(typeof t === "string" && /^\d{4}-\d{2}-\d{2}$/.test(t) ? t + "T12:00:00" : t);
  return isNaN(d) ? null : d;
}

function drawCandles(candles) {
  const cv = $("chart");
  const dpr = window.devicePixelRatio || 1;
  const W = cv.clientWidth || cv.parentElement.clientWidth - 28;
  const H = 220;
  cv.width = W * dpr;
  cv.height = H * dpr;
  const ctx = cv.getContext("2d");
  ctx.scale(dpr, dpr);
  ctx.clearRect(0, 0, W, H);
  if (!candles.length) {
    ctx.fillStyle = "#9aa3b2";
    ctx.font = "13px system-ui";
    ctx.fillText("Nessun dato.", 12, 24);
    return;
  }
  let lo = Infinity, hi = -Infinity, vmax = 0;
  for (const c of candles) {
    lo = Math.min(lo, c.low); hi = Math.max(hi, c.high);
    vmax = Math.max(vmax, c.volume || 0);
  }
  if (!(hi > lo)) { hi = lo + 1; }
  const pad = (hi - lo) * 0.08 || 1;
  hi += pad; lo -= pad;
  const L = 8, R = 64, T = 8, B = 30, VB = 44; // VB = fascia volumi
  const pw = W - L - R, ph = H - T - B - VB;
  const y = (p) => T + (1 - (p - lo) / (hi - lo)) * ph;
  // griglia
  ctx.strokeStyle = "#262c36"; ctx.fillStyle = "#9aa3b2";
  ctx.font = "11px system-ui"; ctx.lineWidth = 1;
  for (let i = 0; i <= 3; i++) {
    const p = lo + ((hi - lo) * i) / 3;
    ctx.beginPath(); ctx.moveTo(L, y(p)); ctx.lineTo(L + pw, y(p)); ctx.stroke();
    ctx.fillText(num2.format(p), L + pw + 4, y(p) + 4);
  }
  const n = candles.length;
  const step = pw / n;
  const bw = Math.max(1, Math.min(14, step * 0.6));
  for (let i = 0; i < n; i++) {
    const c = candles[i];
    const x = L + step * i + step / 2;
    const up = c.close >= c.open;
    ctx.strokeStyle = ctx.fillStyle = up ? "#3fb950" : "#f85149";
    ctx.beginPath(); ctx.moveTo(x, y(c.high)); ctx.lineTo(x, y(c.low)); ctx.stroke();
    const yO = y(c.open), yC = y(c.close);
    ctx.fillRect(x - bw / 2, Math.min(yO, yC), bw, Math.max(1, Math.abs(yC - yO)));
    if (vmax > 0) {
      const vh = ((c.volume || 0) / vmax) * (VB - 6);
      ctx.globalAlpha = 0.35;
      ctx.fillRect(x - bw / 2, H - B - vh, bw, vh);
      ctx.globalAlpha = 1;
    }
  }
  // ultima chiusura
  const last = candles[n - 1].close;
  ctx.setLineDash([4, 3]);
  ctx.strokeStyle = "#58a6ff";
  ctx.beginPath(); ctx.moveTo(L, y(last)); ctx.lineTo(L + pw, y(last)); ctx.stroke();
  ctx.setLineDash([]);
  ctx.fillStyle = "#58a6ff";
  ctx.fillText(num2.format(last), L + pw + 4, y(last) + 4);
  // asse tempi: prima / media / ultima
  ctx.fillStyle = "#9aa3b2";
  const fmt = (c) => {
    const d = normTime(c.time);
    return d ? d.toLocaleDateString("it-IT", { day: "2-digit", month: "short" }) : String(c.time);
  };
  ctx.fillText(fmt(candles[0]), L, H - 8);
  const mid = fmt(candles[n >> 1]);
  ctx.fillText(mid, L + pw / 2 - 20, H - 8);
  const end = fmt(candles[n - 1]);
  ctx.fillText(end, L + pw - 34, H - 8);
}

async function loadCandles() {
  const t = $("ticker").value;
  if (!t) return;
  const tf = $("tf").value || "1m";
  $("chartInfo").textContent = t + " · " + tf + " · carico…";
  try {
    const { data, stale } = await api("/api/stocks/" + encodeURIComponent(t) + "/candles?timeframe=" + encodeURIComponent(tf));
    const candles = Array.isArray(data) ? data : data.candles || [];
    drawCandles(candles);
    $("stale").hidden = !stale;
    $("stale").classList.toggle("on", !!stale);
    const last = candles[candles.length - 1];
    $("chartInfo").textContent = t + " · " + tf + " · " + candles.length + " punti" +
      (last ? " · ult. " + num2.format(last.close) : "") + (stale ? " · dati DB (upstream non disponibile)" : "");
  } catch (e) {
    if (String(e.message).includes("unauthorized")) return;
    $("chartInfo").textContent = "Errore grafico: " + e.message;
  }
}

/* ---------- Load all ---------- */
async function loadAll() {
  if (!token) return;
  $("status").textContent = "Aggiornamento…";
  try {
    const [{ data: dash }, { data: wl }] = await Promise.all([
      api("/api/dashboard/"),
      api("/api/watchlist/"),
    ]);
    renderDashboard(dash);
    renderWatchlist(wl);
    lastLoad = Date.now();
    const d = new Date(lastLoad);
    $("status").textContent = "Aggiornato alle " + d.toLocaleTimeString("it-IT") + " · prossimo auto-refresh tra 5 min";
    await loadCandles();
  } catch (e) {
    if (String(e.message).includes("unauthorized")) return;
    $("status").textContent = "Errore: " + e.message;
  }
}

/* ---------- Eventi ---------- */
$("loginForm").addEventListener("submit", async (e) => {
  e.preventDefault();
  $("loginErr").textContent = "";
  try {
    await login($("user").value.trim(), $("pass").value);
    $("pass").value = "";
  } catch (err) {
    $("loginErr").textContent = err.message;
  }
});
$("logout").addEventListener("click", () => logout(false));
$("refresh").addEventListener("click", loadAll);
$("tf").addEventListener("change", loadCandles);
$("ticker").addEventListener("change", loadCandles);
window.addEventListener("resize", () => { if (tickers.length) loadCandles(); });

setInterval(() => { if (token && !document.hidden) loadAll(); }, REFRESH_MS);
document.addEventListener("visibilitychange", () => {
  if (!document.hidden && token && Date.now() - lastLoad > VIS_STALE_MS) loadAll();
});

/* ---------- Boot: ripristina sessione ---------- */
(async () => {
  if (!token) return;
  try {
    await api("/api/auth/me", { noEtag: true });
    showApp();
    await loadAll();
  } catch (_) {
    logout(true);
  }
})();
