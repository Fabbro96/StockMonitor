/* StockMon Go — vanilla JS, timeframe fisso 1m. */
"use strict";
const $=(id)=>document.getElementById(id);
const LS_KEY="sm_token";
const REFRESH_MS=300_000;
const VIS_STALE_MS=60_000;
const TF="1m";
let token=localStorage.getItem(LS_KEY)||"";
let lastLoad=0;
const etags=new Map();
const eur=new Intl.NumberFormat("it-IT",{style:"currency",currency:"EUR"});
const num2=new Intl.NumberFormat("it-IT",{maximumFractionDigits:2});
async function api(path,opts={}){
  const c=etags.get(path);
  const h={...(opts.headers||{})};
  if(token)h.Authorization="Bearer "+token;
  if(c&&!opts.noEtag)h["If-None-Match"]=c.etag;
  const r=await fetch(path,{...opts,headers:h});
  if(r.status===304&&c)return{data:c.data,stale:r.headers.get("X-Data-Stale")==="true",notModified:true};
  if(r.status===401){logout(true);throw new Error("unauthorized");}
  if(!r.ok){let m="HTTP "+r.status;try{const j=await r.json();if(j.detail)m=j.detail;}catch(_){}throw new Error(m);}
  const d=await r.json();
  const e=r.headers.get("ETag");
  if(e)etags.set(path,{etag:e,data:d});
  return{data:d,stale:r.headers.get("X-Data-Stale")==="true"};
}
async function login(u,p){
  const r=await fetch("/api/auth/login",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({username:u,password:p})});
  if(!r.ok){let m="Credenziali non corrette.";try{const j=await r.json();if(j.detail)m=j.detail;}catch(_){}throw new Error(m);}
  const j=await r.json();
  token=j.access_token||"";
  localStorage.setItem(LS_KEY,token);
  showApp();
  await loadAll();
}
function logout(x){
  token="";
  localStorage.removeItem(LS_KEY);
  etags.clear();
  $("app").hidden=true;
  $("login").hidden=false;
  $("logout").hidden=true;
  if(x)$("loginErr").textContent="Sessione scaduta, rieffettua il login.";
}
function showApp(){$("login").hidden=true;$("app").hidden=false;$("logout").hidden=false;$("loginErr").textContent="";}
const cls=(v)=>v>0?"up":v<0?"dn":"";
const signed=(v,f)=>((v>0?"+":"")+(f||num2).format(v));
function renderDashboard(d){
  const s=d.portfolio_summary||{};
  $("cVal").textContent=eur.format(s.total_value||0);
  $("cInv").textContent="investito "+eur.format(s.total_invested||0);
  const p=$("cPnl");
  p.textContent=signed(s.total_pnl||0,eur);
  p.className="big "+cls(s.total_pnl||0);
  $("cPnlP").textContent=signed(s.total_pnl_percent||0)+" %";
  const g=$("cDay");
  g.textContent=signed(s.daily_pnl||0,eur);
  g.className="big "+cls(s.daily_pnl||0);
  $("cDayP").textContent=signed(s.daily_pnl_percent||0)+" % oggi";
  $("cPos").textContent=String(s.holdings_count??0);
  $("cAlert").textContent="alert: "+(d.active_alerts_count??0);
  const m=d.market_status||{};
  $("mkt").textContent="IT "+(m.IT||"?")+" · US "+(m.US||"?");
  const a=d.recent_advices||[];
  const ul=$("adv");
  ul.innerHTML=a.length?"":"<li>Nessun consiglio.</li>";
  for(const x of a.slice(0,5)){
    const li=document.createElement("li");
    li.textContent=(x.ticker?x.ticker+" — ":"")+(x.title||"Consiglio");
    ul.append(li);
  }
}
let tickers=[];
function renderWatchlist(list){
  const tb=$("wl").querySelector("tbody");
  tb.innerHTML="";
  tickers=(list||[]).map((w)=>w.ticker);
  $("wlCount").textContent=tickers.length+" titoli";
  const sel=$("ticker");
  const prev=sel.value;
  sel.innerHTML="";
  for(const w of list||[]){
    const tr=document.createElement("tr");
    const chg=w.change_percent||0;
    tr.innerHTML="<td><b></b><br><small class='muted'></small></td><td class='num'></td><td class='num "+cls(chg)+"'></td><td class='num'></td><td></td>";
    tr.children[0].querySelector("b").textContent=w.ticker;
    tr.children[0].querySelector("small").textContent=w.name||"";
    tr.children[1].textContent=num2.format(w.current_price||0)+" "+(w.currency||"");
    tr.children[2].textContent=signed(chg)+" %";
    tr.children[3].textContent=w.rsi!=null?num2.format(w.rsi):"—";
    tr.children[4].textContent=w.alert_triggered?"🔔":(w.alert_above||w.alert_below?"⏰":"—");
    tr.addEventListener("click",()=>{sel.value=w.ticker;tb.querySelectorAll("tr").forEach((r)=>r.classList.remove("sel"));tr.classList.add("sel");loadCandles();});
    tb.append(tr);
    const o=document.createElement("option");
    o.value=o.textContent=w.ticker;
    sel.append(o);
  }
  if(tickers.includes(prev))sel.value=prev;
}
function drawCandles(cs){
  const cv=$("chart");
  const dpr=window.devicePixelRatio||1;
  const W=cv.clientWidth||cv.parentElement.clientWidth-28;
  const H=220;
  cv.width=W*dpr;
  cv.height=H*dpr;
  const x2=cv.getContext("2d");
  x2.scale(dpr,dpr);
  x2.clearRect(0,0,W,H);
  if(!cs.length){x2.fillStyle="#9aa3b2";x2.font="13px system-ui";x2.fillText("Nessun dato.",12,24);return;}
  let lo=Infinity,hi=-Infinity;
  for(const c of cs){lo=Math.min(lo,c.low);hi=Math.max(hi,c.high);}
  if(!(hi>lo))hi=lo+1;
  const pd=(hi-lo)*0.08||1;
  hi+=pd;lo-=pd;
  const L=8,R=64,T=8,B=26;
  const pw=W-L-R,ph=H-T-B;
  const y=(p)=>T+(1-(p-lo)/(hi-lo))*ph;
  x2.strokeStyle="#262c36";x2.fillStyle="#9aa3b2";x2.font="11px system-ui";x2.lineWidth=1;
  for(let i=0;i<=3;i++){const p=lo+((hi-lo)*i)/3;x2.beginPath();x2.moveTo(L,y(p));x2.lineTo(L+pw,y(p));x2.stroke();x2.fillText(num2.format(p),L+pw+4,y(p)+4);}
  const n=cs.length,step=pw/n,bw=Math.max(1,Math.min(14,step*0.6));
  for(let i=0;i<n;i++){
    const c=cs[i],px=L+step*i+step/2,up=c.close>=c.open;
    x2.strokeStyle=x2.fillStyle=up?"#3fb950":"#f85149";
    x2.beginPath();x2.moveTo(px,y(c.high));x2.lineTo(px,y(c.low));x2.stroke();
    const yO=y(c.open),yC=y(c.close);
    x2.fillRect(px-bw/2,Math.min(yO,yC),bw,Math.max(1,Math.abs(yC-yO)));
  }
  const last=cs[n-1].close;
  x2.setLineDash([4,3]);x2.strokeStyle="#58a6ff";
  x2.beginPath();x2.moveTo(L,y(last));x2.lineTo(L+pw,y(last));x2.stroke();x2.setLineDash([]);
  x2.fillStyle="#58a6ff";x2.fillText(num2.format(last),L+pw+4,y(last)+4);
  x2.fillStyle="#9aa3b2";
  const f=(c)=>{const d=new Date(typeof c.time==="number"?c.time*1000:c.time);return isNaN(d)?String(c.time):d.toLocaleDateString("it-IT",{day:"2-digit",month:"short"});};
  x2.fillText(f(cs[0]),L,H-8);
  x2.fillText(f(cs[n-1]),L+pw-34,H-8);
}
async function loadCandles(){
  const t=$("ticker").value;
  if(!t)return;
  $("chartInfo").textContent=t+" · 1m · carico…";
  try{
    const{data,stale}=await api("/api/stocks/"+encodeURIComponent(t)+"/candles?timeframe="+TF);
    const cs=Array.isArray(data)?data:data.candles||[];
    drawCandles(cs);
    $("stale").hidden=!stale;
    const l=cs[cs.length-1];
    $("chartInfo").textContent=t+" · 1m · "+cs.length+" punti"+(l?" · ult. "+num2.format(l.close):"")+(stale?" · cache DB":"");
  }catch(e){if(String(e.message).includes("unauthorized"))return;$("chartInfo").textContent="Errore grafico: "+e.message;}
}
async function loadAll(){
  if(!token)return;
  $("status").textContent="Aggiornamento…";
  try{
    const[{data:d},{data:w}]=await Promise.all([api("/api/dashboard/"),api("/api/watchlist/")]);
    renderDashboard(d);
    renderWatchlist(w);
    lastLoad=Date.now();
    $("status").textContent="Aggiornato alle "+new Date(lastLoad).toLocaleTimeString("it-IT");
    await loadCandles();
  }catch(e){if(String(e.message).includes("unauthorized"))return;$("status").textContent="Errore: "+e.message;}
}
$("loginForm").addEventListener("submit",async(e)=>{e.preventDefault();$("loginErr").textContent="";try{await login($("user").value.trim(),$("pass").value);$("pass").value="";}catch(err){$("loginErr").textContent=err.message;}});
$("logout").addEventListener("click",()=>logout(false));
$("refresh").addEventListener("click",loadAll);
$("ticker").addEventListener("change",loadCandles);
setInterval(()=>{if(token&&!document.hidden)loadAll();},REFRESH_MS);
document.addEventListener("visibilitychange",()=>{if(!document.hidden&&token&&Date.now()-lastLoad>VIS_STALE_MS)loadAll();});
(async()=>{if(!token)return;try{await api("/api/auth/me",{noEtag:true});showApp();await loadAll();}catch(_){logout(true);}})();
