import io
import csv
import asyncio
import inspect
import logging
from datetime import datetime, date, timezone
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Response, Query
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from sqlalchemy.orm import selectinload
from sqlalchemy import or_, func, update as sa_update, delete as sa_delete
from sqlalchemy.exc import IntegrityError, OperationalError

from backend.database import get_db
from backend.models.portfolio import Holding, Transaction
from backend.models.stock import Stock
from backend.models.target_allocation import TargetAllocation
from backend.models.user import User
from backend.services.auth import get_current_user
from backend.services.market_data import MarketDataService
from backend.services.portfolio_service import build_portfolio_rows, build_portfolio_summary
from backend.services.analytics import (
    compute_risk_metrics,
    compute_benchmark_comparison,
    compute_rebalance_plan,
    BENCHMARKS,
)

router = APIRouter(prefix="/api/portfolio", tags=["portfolio"])

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Helper di concorrenza e affidabilità scritture
# ---------------------------------------------------------------------------
# Un asyncio.Lock per utente serializza le mutazioni di holdings/transactions
# in-process (deployment a singolo worker uvicorn). Il vincolo DB
# UNIQUE(user_id, stock_id) resta la difesa di ultima istanza.
_user_write_locks: dict[int, asyncio.Lock] = {}


def _get_user_lock(user_id: int) -> asyncio.Lock:
    """Ritorna (creandolo se serve) il lock di scrittura dell'utente."""
    lock = _user_write_locks.get(user_id)
    if lock is None:
        lock = asyncio.Lock()
        _user_write_locks[user_id] = lock
    return lock


async def _invalidate_user_caches(user_id: int) -> None:
    """
    Invalida le cache analytics dell'utente dopo una scrittura riuscita.
    Import lazy + guardia: la funzione è fornita da un'altra lane e la sua
    assenza (o un errore) non deve mai rompere una scrittura già committata.
    """
    try:
        from backend.services.analytics import invalidate_user_caches
        result = invalidate_user_caches(user_id)
        if inspect.isawaitable(result):
            await result
    except Exception as e:
        logger.debug(f"invalidate_user_caches non disponibile: {e}")


async def _commit_write(
    db: AsyncSession,
    conflict_detail: str = "Conflitto di integrità dei dati, riprova.",
) -> None:
    """
    Commit con mappatura degli errori DB in risposte HTTP pulite:
    OperationalError (DB occupato/locked) -> 503, IntegrityError -> 409.
    """
    try:
        await db.commit()
    except OperationalError as e:
        await db.rollback()
        logger.warning(f"Commit fallito (database occupato): {e}")
        raise HTTPException(status_code=503, detail="database temporaneamente occupato, riprova")
    except IntegrityError as e:
        await db.rollback()
        logger.warning(f"Commit fallito (vincolo di integrità): {e}")
        raise HTTPException(status_code=409, detail=conflict_detail)


def _can_access_holding(holding: Holding, current_user: User) -> bool:
    """
    Ownership STRICT: solo il proprietario può modificare/eliminare la holding.

    Righe legacy con user_id NULL (pre multi-utente): accesso riservato
    all'admin, stesso precedente di `_can_access_watchlist_item` in watchlist.py
    e `_can_access_alert_rule` in settings.py.
    """
    if holding.user_id is None:
        return bool(current_user.is_admin)
    return holding.user_id == current_user.id


def _can_access_transaction(tx: Transaction, current_user: User) -> bool:
    """Ownership STRICT sulla transazione; righe legacy NULL -> solo admin."""
    if tx.user_id is None:
        return bool(current_user.is_admin)
    return tx.user_id == current_user.id


async def _ensure_stocks(db: AsyncSession, specs: dict[str, dict]) -> dict[str, Stock]:
    """
    Ritorna {ticker: Stock} garantendo l'esistenza dei titoli in `specs`
    (ticker -> {"name", "market", "currency"}). Gestisce la race su UNIQUE
    stocks.ticker tra richieste concorrenti: su IntegrityError esegue rollback
    e re-select, senza rompere i flussi bulk di import/seed.
    """
    tickers = set(specs.keys())
    if not tickers:
        return {}

    async def _fetch() -> dict[str, Stock]:
        res = await db.execute(select(Stock).where(Stock.ticker.in_(tickers)))
        return {s.ticker: s for s in res.scalars().all()}

    def _add_missing(mapping: dict) -> bool:
        added = False
        for ticker, spec in specs.items():
            if ticker not in mapping:
                db.add(Stock(
                    ticker=ticker,
                    name=spec.get("name") or ticker,
                    market=spec.get("market"),
                    currency=spec.get("currency"),
                ))
                added = True
        return added

    stocks_map = await _fetch()
    if not _add_missing(stocks_map):
        return stocks_map
    try:
        await db.flush()
    except IntegrityError:
        # Un'altra sessione ha inserito uno degli stessi ticker: annulla i pending
        # e recupera le righe esistenti, ricreando solo quelle ancora mancanti.
        await db.rollback()
        stocks_map = await _fetch()
        if _add_missing(stocks_map):
            await db.flush()
    return await _fetch()

class HoldingCreate(BaseModel):
    ticker: Optional[str] = None
    stock_id: Optional[int] = None
    quantity: float = Field(..., gt=0, description="Quantità deve essere > 0")
    avg_purchase_price: float = Field(..., gt=0, description="Prezzo medio deve essere > 0")
    purchase_date: Optional[date] = None
    notes: Optional[str] = None

class HoldingUpdate(BaseModel):
    quantity: Optional[float] = Field(None, gt=0, description="Quantità deve essere > 0")
    avg_purchase_price: Optional[float] = Field(None, gt=0, description="Prezzo medio deve essere > 0")
    purchase_date: Optional[date] = None
    notes: Optional[str] = None

class HoldingBatchItem(BaseModel):
    id: int
    quantity: float = Field(..., gt=0, description="Quantità deve essere > 0")
    avg_purchase_price: float = Field(..., gt=0, description="Prezzo medio deve essere > 0")
    notes: Optional[str] = None

class BatchUpdateRequest(BaseModel):
    holdings: List[HoldingBatchItem]

@router.get("/")
async def get_portfolio(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Lista posizioni dell'utente con prezzi live (fallback DB/cache mai bloccante)."""
    return await build_portfolio_rows(db, user_id=current_user.id)

@router.get("/summary")
async def get_summary(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    return await build_portfolio_summary(db, user_id=current_user.id)

@router.get("/risk-metrics")
async def get_risk_metrics(
    days: int = Query(180, ge=30, le=3650),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Metriche quantitative di rischio/performance del portafoglio dell'utente:
    Max Drawdown, Volatilità annualizzata, Sharpe Ratio, Beta pesato.
    """
    return await compute_risk_metrics(db, days=days, user_id=current_user.id)

@router.get("/benchmarks")
async def get_benchmark_comparison(
    days: int = Query(90, ge=7, le=1825),
    tickers: Optional[str] = Query(None, description="Comma-separated: ^GSPC,FTSEMIB.MI"),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Crescita % storica del portafoglio confrontata con gli indici di mercato
    (default: S&P 500 ^GSPC e FTSE MIB FTSEMIB.MI).
    """
    benchmark_list = None
    if tickers:
        benchmark_list = [t.strip().upper() for t in tickers.split(",") if t.strip()]
        for t in benchmark_list:
            BENCHMARKS.setdefault(t, {"name": t, "flag": "📊"})
    return await compute_benchmark_comparison(db, days=days, benchmark_tickers=benchmark_list, user_id=current_user.id)

# ---------------------------------------------------------------------------
# Rebalancer: Target Allocation CRUD + Preview ordini
# ---------------------------------------------------------------------------
class TargetAllocationCreate(BaseModel):
    name: str
    target_percent: float
    scope_type: str = "MARKET"   # MARKET | TICKERS | CASH
    scope_value: Optional[str] = ""

class RebalancePreviewRequest(BaseModel):
    extra_cash: float = 0.0

@router.get("/rebalance/targets")
async def list_targets(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    result = await db.execute(
        select(TargetAllocation)
        .where(TargetAllocation.user_id == current_user.id)
        .order_by(TargetAllocation.id)
    )
    targets = result.scalars().all()
    return [
        {
            "id": t.id,
            "name": t.name,
            "target_percent": t.target_percent,
            "scope_type": t.scope_type,
            "scope_value": t.scope_value or "",
        }
        for t in targets
    ]

@router.post("/rebalance/targets")
async def create_target(
    data: TargetAllocationCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    if not (0.0 <= data.target_percent <= 100.0):
        raise HTTPException(status_code=400, detail="target_percent deve essere tra 0 e 100.")
    scope_type = (data.scope_type or "MARKET").upper()
    if scope_type not in ("MARKET", "TICKERS", "CASH"):
        raise HTTPException(status_code=400, detail="scope_type deve essere MARKET, TICKERS o CASH.")
    if scope_type == "MARKET" and not data.scope_value:
        raise HTTPException(status_code=400, detail="Per scope MARKET indica scope_value (IT, US, EU).")

    # Check+insert atomici sotto il lock per-utente: due POST paralleli dello
    # stesso utente non possono entrambi superare il check e sfondare il 100%.
    lock = _get_user_lock(current_user.id)
    async with lock:
        # La somma delle allocazioni target dell'utente non può superare il 100%.
        existing_sum_res = await db.execute(
            select(func.coalesce(func.sum(TargetAllocation.target_percent), 0.0))
            .where(TargetAllocation.user_id == current_user.id)
        )
        existing_sum = float(existing_sum_res.scalar() or 0.0)
        if existing_sum + data.target_percent > 100.0 + 1e-6:
            raise HTTPException(
                status_code=400,
                detail=(
                    "La somma delle allocazioni target non può superare 100% "
                    f"(attuale {existing_sum:.2f}% + nuova {data.target_percent:.2f}%)."
                ),
            )

        target = TargetAllocation(
            user_id=current_user.id,
            name=data.name.strip(),
            target_percent=data.target_percent,
            scope_type=scope_type,
            scope_value=(data.scope_value or "").strip().upper(),
        )
        db.add(target)
        await _commit_write(db, conflict_detail="Conflitto nella creazione dell'allocazione target, riprova.")
        await db.refresh(target)
        response = {"id": target.id, "name": target.name, "target_percent": target.target_percent,
                    "scope_type": target.scope_type, "scope_value": target.scope_value or ""}
    return response

@router.delete("/rebalance/targets/{target_id}")
async def delete_target(
    target_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    target = await db.get(TargetAllocation, target_id)
    if not target or target.user_id != current_user.id:
        raise HTTPException(status_code=404, detail="Allocazione target non trovata.")
    await db.delete(target)
    await _commit_write(db, conflict_detail="Conflitto nella rimozione dell'allocazione target, riprova.")
    return {"status": "success"}

@router.post("/rebalance/preview")
async def rebalance_preview(
    data: RebalancePreviewRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Calcola il piano di ribilanciamento per il portafoglio dell'utente: delta per bucket e ordini buy/sell
    (quantità stimate) necessari per raggiungere le allocazioni target.
    """
    result = await db.execute(
        select(TargetAllocation)
        .where(TargetAllocation.user_id == current_user.id)
        .order_by(TargetAllocation.id)
    )
    targets = result.scalars().all()
    if not targets:
        raise HTTPException(status_code=400, detail="Nessuna allocazione target configurata.")

    target_dicts = [
        {"id": t.id, "name": t.name, "target_percent": t.target_percent,
         "scope_type": t.scope_type, "scope_value": t.scope_value or ""}
        for t in targets
    ]
    portfolio = await build_portfolio_rows(db, user_id=current_user.id)
    plan = compute_rebalance_plan(portfolio, target_dicts, extra_cash=data.extra_cash)
    plan["portfolio_empty"] = len(portfolio) == 0
    return plan


@router.post("/holdings")
async def add_holding(
    holding_data: HoldingCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Aggiunge (o fonde) una posizione per l'utente in modo serializzato e atomico:
    lock per-utente + UNIQUE(user_id, stock_id) impediscono righe duplicate.
    La Stock eventualmente auto-creata viene solo flushata e committata insieme
    alla holding: un errore non lascia Stock orfani.
    """
    ticker_norm = (holding_data.ticker or "").strip().upper() or None

    async def _resolve_stock_id() -> int:
        """Risolve stock_id da stock_id esplicito o da ticker (find or create)."""
        if holding_data.stock_id is not None:
            stock = await db.get(Stock, holding_data.stock_id)
            if not stock:
                raise HTTPException(status_code=400, detail=f"Stock id {holding_data.stock_id} inesistente.")
            return stock.id
        if not ticker_norm:
            raise HTTPException(status_code=400, detail="Specificare stock_id o ticker valido.")

        result = await db.execute(select(Stock).where(Stock.ticker == ticker_norm))
        stock = result.scalars().first()
        if not stock:
            # Auto-create stock (nome via Yahoo quando disponibile), senza commit:
            # flush + commit finale unico per evitare Stock orfani.
            info = await MarketDataService.resolve_stock_info(ticker_norm)
            name = info.get("name") or ticker_norm
            market, currency = MarketDataService.classify_new_stock(ticker_norm, info)
            stocks_map = await _ensure_stocks(db, {
                ticker_norm: {"name": name, "market": market, "currency": currency}
            })
            stock = stocks_map.get(ticker_norm)
            if stock is None:
                raise HTTPException(status_code=409, detail=f"Conflitto concorrente sulla creazione di {ticker_norm}.")
        return stock.id

    lock = _get_user_lock(current_user.id)
    async with lock:
        stock_id = await _resolve_stock_id()

        # Upsert sotto lock: la seconda richiesta concorrente ri-legge la riga
        # committata dalla prima e la fonde (mai una seconda riga).
        # Il retry su IntegrityError copre comunque la corsa a livello DB.
        for _attempt in range(3):
            existing_result = await db.execute(
                select(Holding)
                .where(Holding.stock_id == stock_id, Holding.user_id == current_user.id)
            )
            existing_holding = existing_result.scalars().first()
            if existing_holding:
                total_qty = existing_holding.quantity + holding_data.quantity
                if total_qty <= 0:
                    # Mai ricadere nella creazione di una seconda riga: la posizione
                    # risultante sarebbe nulla/negativa, quindi l'operazione è invalida.
                    raise HTTPException(
                        status_code=400,
                        detail=(
                            "Operazione rifiutata: la quantità totale della posizione "
                            "diventerebbe uguale o inferiore a zero."
                        ),
                    )
                new_avg = (
                    (existing_holding.quantity * existing_holding.avg_purchase_price) +
                    (holding_data.quantity * holding_data.avg_purchase_price)
                ) / total_qty
                existing_holding.quantity = round(total_qty, 4)
                existing_holding.avg_purchase_price = round(new_avg, 4)
                if holding_data.notes:
                    existing_holding.notes = f"{existing_holding.notes or ''}; {holding_data.notes}".strip("; ")
                try:
                    await db.commit()
                except IntegrityError:
                    await db.rollback()
                    stock_id = await _resolve_stock_id()
                    continue
                except OperationalError as e:
                    await db.rollback()
                    logger.warning(f"Commit fallito (database occupato): {e}")
                    raise HTTPException(status_code=503, detail="database temporaneamente occupato, riprova")
                await db.refresh(existing_holding)
                await _invalidate_user_caches(current_user.id)
                return existing_holding

            new_holding = Holding(
                user_id=current_user.id,
                stock_id=stock_id,
                quantity=holding_data.quantity,
                avg_purchase_price=holding_data.avg_purchase_price,
                purchase_date=holding_data.purchase_date or date.today(),
                notes=holding_data.notes
            )
            db.add(new_holding)
            try:
                await db.commit()
            except IntegrityError:
                # Un'altra richiesta ha inserito la stessa (user_id, stock_id):
                # rollback, ri-risolve lo stock (potrebbe essere stato creato da
                # noi in questa transazione) e fonde al giro successivo.
                await db.rollback()
                stock_id = await _resolve_stock_id()
                continue
            except OperationalError as e:
                await db.rollback()
                logger.warning(f"Commit fallito (database occupato): {e}")
                raise HTTPException(status_code=503, detail="database temporaneamente occupato, riprova")
            await db.refresh(new_holding)
            await _invalidate_user_caches(current_user.id)
            return new_holding

        raise HTTPException(status_code=409, detail="Conflitto concorrente sulla posizione, riprova.")

@router.put("/holdings/{holding_id}")
async def update_holding(
    holding_id: int,
    holding_update: HoldingUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    lock = _get_user_lock(current_user.id)
    async with lock:
        holding = await db.get(Holding, holding_id)
        if not holding or not _can_access_holding(holding, current_user):
            raise HTTPException(status_code=404, detail="Holding non trovata")

        update_data = holding_update.model_dump(exclude_unset=True)
        for key, value in update_data.items():
            if value is not None:
                setattr(holding, key, value)

        await _commit_write(db, conflict_detail="Conflitto nell'aggiornamento della holding, riprova.")
        await db.refresh(holding)
        await _invalidate_user_caches(current_user.id)
        return holding

@router.put("/batch")
async def batch_update_holdings(
    batch_data: BatchUpdateRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Aggiorna più posizioni dell'utente contemporaneamente con una singola transazione sicura.
    """
    if not batch_data.holdings:
        return {"status": "success", "updated_count": 0}

    lock = _get_user_lock(current_user.id)
    async with lock:
        holding_ids = [item.id for item in batch_data.holdings]
        # Una sola query per caricare tutte le holdings coinvolte (niente db.get in loop).
        # Le righe legacy user_id NULL sono visibili/aggiornabili solo dall'admin:
        # il filtro SQL evita di toccarle per i non-admin.
        access_filter = Holding.user_id == current_user.id
        if current_user.is_admin:
            access_filter = or_(access_filter, Holding.user_id.is_(None))
        result = await db.execute(
            select(Holding).where(Holding.id.in_(holding_ids), access_filter)
        )
        holdings_by_id = {
            h.id: h for h in result.scalars().all()
            if _can_access_holding(h, current_user)
        }

        updated_count = 0
        for item in batch_data.holdings:
            holding = holdings_by_id.get(item.id)
            if holding:
                holding.quantity = item.quantity
                holding.avg_purchase_price = item.avg_purchase_price
                if item.notes is not None:
                    holding.notes = item.notes
                updated_count += 1

        await _commit_write(db, conflict_detail="Conflitto nell'aggiornamento batch delle holdings, riprova.")
        if updated_count:
            await _invalidate_user_caches(current_user.id)
        return {"status": "success", "updated_count": updated_count}

@router.delete("/holdings/{holding_id}")
async def remove_holding(
    holding_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    lock = _get_user_lock(current_user.id)
    async with lock:
        holding = await db.get(Holding, holding_id)
        if not holding or not _can_access_holding(holding, current_user):
            raise HTTPException(status_code=404, detail="Holding non trovata")

        await db.delete(holding)
        await _commit_write(db, conflict_detail="Conflitto nella rimozione della holding, riprova.")
        await _invalidate_user_caches(current_user.id)
        return {"status": "success", "message": "Holding rimossa"}

@router.get("/export")
async def export_portfolio(
    format: str = Query("csv", pattern="^(csv|json)$"),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Esporta il portafoglio dell'utente corrente in formato CSV o JSON.
    """
    portfolio = await build_portfolio_rows(db, user_id=current_user.id)
    
    if format == "json":
        return portfolio

    # Format CSV
    output = io.StringIO()
    writer = csv.writer(output, delimiter=",")
    writer.writerow(["ticker", "name", "quantity", "avg_purchase_price", "current_price", "pnl_absolute", "pnl_percent", "purchase_date", "notes"])
    
    for item in portfolio:
        writer.writerow([
            item["ticker"],
            item["name"],
            item["quantity"],
            item["avg_purchase_price"],
            item["current_price"],
            item["pnl_absolute"],
            item["pnl_percent"],
            item.get("purchase_date", ""),
            item.get("notes", "")
        ])
        
    today_str = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    csv_content = output.getvalue()
    
    return Response(
        content=csv_content,
        media_type="text/csv",
        headers={"Content-Disposition": f"attachment; filename=portafoglio_{today_str}.csv"}
    )

@router.post("/import")
async def import_holdings(
    file: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Importa posizioni azionarie da un file CSV assegnandole all'utente autenticato.
    """
    content = await file.read()
    text = content.decode("utf-8-sig", errors="ignore")
    
    # Auto-detect separator
    sample = text[:1024]
    delimiter = ";" if sample.count(";") > sample.count(",") else ","
    
    reader = csv.DictReader(io.StringIO(text), delimiter=delimiter)
    
    imported = 0
    updated = 0
    errors = []
    parsed_rows = []
    
    for row_idx, row in enumerate(reader, start=1):
        # Normalize header keys to lowercase
        norm_row = {k.strip().lower(): (v or "").strip() for k, v in row.items() if k}
        
        # Ticker resolution
        ticker = norm_row.get("ticker") or norm_row.get("simbolo") or norm_row.get("azione") or norm_row.get("titolo")
        if not ticker:
            continue
        ticker = ticker.upper()
        
        # Quantity resolution
        qty_str = norm_row.get("quantity") or norm_row.get("quantita") or norm_row.get("quantità") or norm_row.get("qty") or "0"
        qty_str = qty_str.replace(",", ".")
        try:
            quantity = float(qty_str)
        except ValueError:
            errors.append(f"Riga {row_idx}: Quantità non valida '{qty_str}' per {ticker}")
            continue
            
        if quantity <= 0:
            errors.append(
                f"Riga {row_idx}: Quantità deve essere maggiore di zero per {ticker} (trovato {quantity})."
            )
            continue
            
        # Price resolution
        price_str = norm_row.get("avg_purchase_price") or norm_row.get("avg_price") or norm_row.get("prezzo") or norm_row.get("prezzo_acquisto") or norm_row.get("prezzo_medio") or "0"
        price_str = price_str.replace(",", ".").replace("€", "").replace("$", "").strip()
        try:
            avg_price = float(price_str)
        except ValueError:
            errors.append(f"Riga {row_idx}: Prezzo non valido '{price_str}' per {ticker}")
            continue

        if avg_price <= 0:
            errors.append(
                f"Riga {row_idx}: Prezzo medio di acquisto deve essere maggiore di zero per {ticker} (trovato {avg_price})."
            )
            continue

        # Notes resolution
        notes = norm_row.get("notes") or norm_row.get("note") or None
        
        # Purchase date resolution
        date_str = norm_row.get("purchase_date") or norm_row.get("data") or norm_row.get("data_acquisto")
        purchase_date = None
        if date_str:
            for fmt in ("%Y-%m-%d", "%d/%m/%Y", "%d-%m-%Y", "%Y/%m/%d"):
                try:
                    purchase_date = datetime.strptime(date_str, fmt).date()
                    break
                except ValueError:
                    pass

        parsed_rows.append({
            "ticker": ticker,
            "name": norm_row.get("name") or norm_row.get("nome") or ticker,
            "quantity": quantity,
            "avg_price": avg_price,
            "notes": notes,
            "purchase_date": purchase_date,
        })

    if not parsed_rows and text.strip():
        # File con contenuto ma zero righe valide (header sconosciuti, spazzatura):
        # non restare silenti, segnala in errors invece di 200 vuoto.
        errors.append(
            "Nessuna riga valida trovata nel file: attese colonne "
            "'ticker, quantity, avg_purchase_price' (separatore , o ;)."
        )

    lock = _get_user_lock(current_user.id)
    async with lock:
        if parsed_rows:
            # Prefetch: UNA query per gli stock esistenti e UNA per le holdings dell'utente
            # (creazione con gestione della race su UNIQUE stocks.ticker)
            specs = {
                r["ticker"]: {
                    "name": r["name"],
                    "market": MarketDataService.detect_market_currency(r["ticker"])[0],
                    "currency": MarketDataService.detect_market_currency(r["ticker"])[1],
                }
                for r in parsed_rows
            }
            stocks_by_ticker = await _ensure_stocks(db, specs)

            stock_ids = [s.id for s in stocks_by_ticker.values() if s.id is not None]
            holdings_result = await db.execute(
                select(Holding).where(Holding.stock_id.in_(stock_ids), Holding.user_id == current_user.id)
            )
            holdings_by_stock_id = {h.stock_id: h for h in holdings_result.scalars().all()}

            for r in parsed_rows:
                stock = stocks_by_ticker[r["ticker"]]
                holding = holdings_by_stock_id.get(stock.id)
                if holding:
                    holding.quantity = r["quantity"]
                    holding.avg_purchase_price = r["avg_price"]
                    if r["notes"]:
                        holding.notes = r["notes"]
                    if r["purchase_date"]:
                        holding.purchase_date = r["purchase_date"]
                    updated += 1
                else:
                    holding = Holding(
                        user_id=current_user.id,
                        stock_id=stock.id,
                        quantity=r["quantity"],
                        avg_purchase_price=r["avg_price"],
                        purchase_date=r["purchase_date"] or date.today(),
                        notes=r["notes"]
                    )
                    db.add(holding)
                    holdings_by_stock_id[stock.id] = holding
                    imported += 1

        # Un solo commit: se fallisce non restano né Stock né holdings parziali.
        await _commit_write(db, conflict_detail="Conflitto durante l'import del portafoglio, riprova.")
        await _invalidate_user_caches(current_user.id)
    return {
        "status": "success",
        "imported": imported,
        "updated": updated,
        "errors": errors
    }

@router.post("/seed-demo")
async def seed_demo_data(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Inizializza posizioni demo bilanciate (Italia + USA) per l'utente autenticato.
    """
    from backend.models.watchlist import WatchlistItem

    demo_holdings = [
        {"ticker": "ENEL.MI", "name": "Enel S.p.A.", "market": "IT", "currency": "EUR", "qty": 400, "price": 6.20, "notes": "Dividendo Core"},
        {"ticker": "ISP.MI", "name": "Intesa Sanpaolo", "market": "IT", "currency": "EUR", "qty": 800, "price": 3.15, "notes": "Settore Bancario"},
        {"ticker": "RACE.MI", "name": "Ferrari N.V.", "market": "IT", "currency": "EUR", "qty": 8, "price": 380.0, "notes": "Luxury Growth"},
        {"ticker": "AAPL", "name": "Apple Inc.", "market": "US", "currency": "USD", "qty": 15, "price": 195.0, "notes": "Big Tech"},
        {"ticker": "NVDA", "name": "NVIDIA Corporation", "market": "US", "currency": "USD", "qty": 20, "price": 118.0, "notes": "AI Leader"},
        {"ticker": "MSFT", "name": "Microsoft Corporation", "market": "US", "currency": "USD", "qty": 8, "price": 390.0, "notes": "Cloud & AI Enterprise"},
    ]

    demo_watchlist = [
        {"ticker": "LDO.MI", "name": "Leonardo S.p.A.", "market": "IT", "currency": "EUR", "alert_above": 26.0, "alert_below": 22.0, "notes": "Target breakout"},
        {"ticker": "G.MI", "name": "Assicurazioni Generali", "market": "IT", "currency": "EUR", "alert_above": 28.0, "alert_below": 24.5, "notes": "High yield"},
        {"ticker": "AMZN", "name": "Amazon.com Inc.", "market": "US", "currency": "USD", "alert_above": 220.0, "alert_below": 185.0, "notes": "AWS Cloud margin expansion"},
        {"ticker": "GOOGL", "name": "Alphabet Inc.", "market": "US", "currency": "USD", "alert_above": 190.0, "alert_below": 165.0, "notes": "Search AI & Waymo"},
    ]

    # Prefetch: UNA query per gli stock coinvolti (holdings + watchlist),
    # creazione con gestione della race su UNIQUE stocks.ticker.
    specs = {
        item["ticker"]: {"name": item["name"], "market": item["market"], "currency": item["currency"]}
        for item in demo_holdings + demo_watchlist
    }

    lock = _get_user_lock(current_user.id)
    async with lock:
        stocks_by_ticker = await _ensure_stocks(db, specs)

        stock_ids = [s.id for s in stocks_by_ticker.values() if s.id is not None]

        created_holdings = 0
        held_res = await db.execute(
            select(Holding.stock_id)
            .where(Holding.stock_id.in_(stock_ids), Holding.user_id == current_user.id)
        )
        held_stock_ids = {row[0] for row in held_res.all()}
        for item in demo_holdings:
            stock = stocks_by_ticker[item["ticker"]]
            if stock.id not in held_stock_ids:
                h = Holding(
                    user_id=current_user.id,
                    stock_id=stock.id,
                    quantity=item["qty"],
                    avg_purchase_price=item["price"],
                    purchase_date=date.today(),
                    notes=item["notes"]
                )
                db.add(h)
                held_stock_ids.add(stock.id)
                created_holdings += 1

        created_watchlist = 0
        wl_res = await db.execute(
            select(WatchlistItem.stock_id)
            .where(WatchlistItem.stock_id.in_(stock_ids), WatchlistItem.user_id == current_user.id)
        )
        wl_stock_ids = {row[0] for row in wl_res.all()}
        for item in demo_watchlist:
            stock = stocks_by_ticker[item["ticker"]]
            if stock.id not in wl_stock_ids:
                w = WatchlistItem(
                    user_id=current_user.id,
                    stock_id=stock.id,
                    notes=item["notes"],
                    alert_above=item.get("alert_above"),
                    alert_below=item.get("alert_below")
                )
                db.add(w)
                wl_stock_ids.add(stock.id)
                created_watchlist += 1

        await _commit_write(db, conflict_detail="Conflitto durante la creazione dei dati demo, riprova.")
        await _invalidate_user_caches(current_user.id)
    return {
        "status": "success",
        "message": f"Demo popolata con successo ({created_holdings} holding, {created_watchlist} watchlist).",
        "created_holdings": created_holdings,
        "created_watchlist": created_watchlist
    }


# ---------------------------------------------------------------------------
# Trade Ledger (Registro Transazioni, Storico Compravendite & P&L Realizzato)
# ---------------------------------------------------------------------------
class TransactionCreate(BaseModel):
    ticker: str
    type: str  # BUY, SELL, DIVIDEND
    quantity: float = Field(0.0, ge=0, description="Quantità deve essere >= 0")
    price: float = Field(0.0, ge=0, description="Prezzo deve essere >= 0")
    fee: float = Field(0.0, ge=0, description="Commissioni devono essere >= 0")
    transaction_date: Optional[datetime] = None
    notes: Optional[str] = ""


@router.get("/transactions")
async def list_transactions(
    type: Optional[str] = None,
    ticker: Optional[str] = None,
    limit: int = 100,
    skip: int = 0,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Restituisce lo storico completo delle transazioni registrate nel Trade Ledger dell'utente."""
    query = (
        select(Transaction)
        .join(Stock)
        .where(Transaction.user_id == current_user.id)
        .options(selectinload(Transaction.stock))
    )
    if type:
        query = query.where(Transaction.type == type.upper())
    if ticker:
        query = query.where(Stock.ticker == ticker.strip().upper())
    query = query.order_by(Transaction.transaction_date.desc()).offset(skip).limit(limit)

    result = await db.execute(query)
    txs = result.scalars().all()
    output = []
    for tx in txs:
        output.append({
            "id": tx.id,
            "stock_id": tx.stock_id,
            "ticker": tx.stock.ticker if tx.stock else "?",
            "name": tx.stock.name if tx.stock else "",
            "market": tx.stock.market if tx.stock else "US",
            "type": tx.type,
            "quantity": tx.quantity,
            "price": tx.price,
            "fee": tx.fee,
            "realized_pnl": tx.realized_pnl,
            "currency": tx.currency or (tx.stock.currency if tx.stock else "EUR"),
            "transaction_date": str(tx.transaction_date) if tx.transaction_date else str(tx.created_at),
            "notes": tx.notes or ""
        })
    return output


@router.post("/transactions")
async def create_transaction(
    tx_in: TransactionCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Registra una nuova transazione (BUY, SELL o DIVIDEND) per l'utente e aggiorna atomicamente il portafoglio.
    - BUY: incrementa o crea la posizione calcolando il nuovo prezzo medio di carico ponderato.
    - SELL: calcola il P&L realizzato, decrementa la posizione (o la rimuove se 0).
    - DIVIDEND: registra l'incasso cedolare.
    """
    t_type = (tx_in.type or "BUY").strip().upper()
    if t_type not in ("BUY", "SELL", "DIVIDEND"):
        raise HTTPException(status_code=400, detail="Il tipo transazione deve essere BUY, SELL o DIVIDEND.")

    ticker = tx_in.ticker.strip().upper()
    if not ticker:
        raise HTTPException(status_code=400, detail="Specificare un ticker valido.")

    lock = _get_user_lock(current_user.id)
    async with lock:
        # Risolve o crea Stock con solo flush: niente commit anticipato, così
        # un errore successivo non lascia una Stock orfana attiva.
        res = await db.execute(select(Stock).where(Stock.ticker == ticker))
        stock = res.scalars().first()
        if not stock:
            info = await MarketDataService.resolve_stock_info(ticker)
            market, currency = MarketDataService.classify_new_stock(ticker, info)
            stocks_map = await _ensure_stocks(db, {
                ticker: {"name": info.get("name", ticker), "market": market, "currency": currency}
            })
            stock = stocks_map.get(ticker)
            if stock is None:
                raise HTTPException(status_code=409, detail=f"Conflitto concorrente sulla creazione di {ticker}.")

        tx_date = tx_in.transaction_date or datetime.now(timezone.utc)
        realized_pnl = None
        holding = None

        if t_type == "BUY":
            if tx_in.quantity <= 0 or tx_in.price <= 0:
                raise HTTPException(status_code=400, detail="Quantità e prezzo devono essere maggiori di zero per un acquisto.")

            h_res = await db.execute(
                select(Holding)
                .where(Holding.stock_id == stock.id, Holding.user_id == current_user.id)
            )
            holding = h_res.scalars().first()
            if holding:
                new_qty = holding.quantity + tx_in.quantity
                new_avg = ((holding.quantity * holding.avg_purchase_price) + (tx_in.quantity * tx_in.price)) / new_qty
                holding.quantity = round(new_qty, 4)
                holding.avg_purchase_price = round(new_avg, 4)
                if tx_in.notes:
                    holding.notes = tx_in.notes
            else:
                holding = Holding(
                    user_id=current_user.id,
                    stock_id=stock.id,
                    quantity=tx_in.quantity,
                    avg_purchase_price=tx_in.price,
                    purchase_date=tx_date.date() if isinstance(tx_date, datetime) else tx_date,
                    notes=tx_in.notes
                )
                db.add(holding)
            realized_pnl = 0.0

        elif t_type == "SELL":
            if tx_in.quantity <= 0 or tx_in.price <= 0:
                raise HTTPException(status_code=400, detail="Quantità e prezzo devono essere maggiori di zero per una vendita.")

            h_res = await db.execute(
                select(Holding)
                .where(Holding.stock_id == stock.id, Holding.user_id == current_user.id)
            )
            holding = h_res.scalars().first()
            if not holding or holding.quantity + 1e-9 < tx_in.quantity:
                avail = holding.quantity if holding else 0
                raise HTTPException(
                    status_code=409,
                    detail=f"Quantità insufficiente in portafoglio: possiedi {avail} quote di {ticker}, impossibile venderne {tx_in.quantity}."
                )

            # P&L realizzato sul prezzo medio di carico letto PRIMA della vendita
            # (dentro il lock). = (Prezzo Vendita - Prezzo Medio) * Qty - Commissioni
            realized_pnl = round((tx_in.price - holding.avg_purchase_price) * tx_in.quantity - tx_in.fee, 2)

            # Decremento atomico con guardia quantity >= q: due SELL concorrenti
            # non possono andare entrambe a buon fine (rowcount 0 -> 409).
            upd = await db.execute(
                sa_update(Holding)
                .where(
                    Holding.id == holding.id,
                    Holding.user_id == current_user.id,
                    Holding.quantity >= tx_in.quantity,
                )
                .values(quantity=Holding.quantity - tx_in.quantity)
                .execution_options(synchronize_session=False)
            )
            if upd.rowcount != 1:
                await db.rollback()
                raise HTTPException(
                    status_code=409,
                    detail=f"Quantità insufficiente in portafoglio per {ticker}: la posizione è cambiata durante la vendita, riprova."
                )

            # Uso la quantità letta prima dell'UPDATE (l'ORM non è sincronizzato
            # di proposito) per decidere se la posizione va rimossa.
            if holding.quantity - tx_in.quantity <= 0.0001:
                await db.execute(
                    sa_delete(Holding).where(
                        Holding.id == holding.id,
                        Holding.user_id == current_user.id,
                    )
                )

        elif t_type == "DIVIDEND":
            if tx_in.price < 0:
                raise HTTPException(status_code=400, detail="L'importo del dividendo non può essere negativo.")
            total_div = (tx_in.price * tx_in.quantity) if tx_in.quantity > 0 else tx_in.price
            realized_pnl = round(total_div - tx_in.fee, 2)

        # Crea record transazione per questo utente (stessa transazione della holding)
        tx = Transaction(
            user_id=current_user.id,
            stock_id=stock.id,
            type=t_type,
            quantity=tx_in.quantity,
            price=tx_in.price,
            fee=tx_in.fee,
            realized_pnl=realized_pnl,
            currency=stock.currency or "EUR",
            transaction_date=tx_date,
            notes=tx_in.notes or ""
        )
        db.add(tx)
        await _commit_write(db, conflict_detail="Conflitto nella registrazione della transazione, riprova.")
        await db.refresh(tx)
        await _invalidate_user_caches(current_user.id)

    return {
        "status": "success",
        "transaction": {
            "id": tx.id,
            "ticker": ticker,
            "type": tx.type,
            "quantity": tx.quantity,
            "price": tx.price,
            "fee": tx.fee,
            "realized_pnl": tx.realized_pnl,
            "currency": tx.currency,
            "transaction_date": str(tx.transaction_date)
        }
    }


@router.delete("/transactions/{tx_id}")
async def delete_transaction(
    tx_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Elimina una riga dallo storico transazioni e ricalcola atomicamente la
    posizione dai movimenti residui (stesso lock per-utente, un solo commit).

    Semantica documentata: il modello non traccia i lotti venduti, quindi
    quantity = somma(BUY) - somma(SELL) e avg_purchase_price = media ponderata
    di TUTTI i BUY residui (non solo delle quote ancora in portafoglio).
    Se non restano quote la holding viene eliminata.
    """
    lock = _get_user_lock(current_user.id)
    async with lock:
        tx = await db.get(Transaction, tx_id)
        if not tx or not _can_access_transaction(tx, current_user):
            raise HTTPException(status_code=404, detail="Transazione non trovata.")

        # Access check già superato: per l'admin una riga legacy con user_id NULL
        # è trattata come propria (i dati storici pre multi-utente sono suoi),
        # quindi il recompute usa il suo id come proprietario effettivo.
        owner_id = tx.user_id if tx.user_id is not None else current_user.id
        stock_id = tx.stock_id

        await db.delete(tx)

        # Ricalcolo dai movimenti residui (la SELECT forza l'autoflush della DELETE).
        remaining_res = await db.execute(
            select(Transaction.type, Transaction.quantity, Transaction.price, Transaction.transaction_date)
            .where(
                Transaction.user_id == owner_id,
                Transaction.stock_id == stock_id,
                Transaction.type.in_(("BUY", "SELL")),
            )
            .order_by(Transaction.transaction_date, Transaction.id)
        )
        remaining = remaining_res.all()

        buy_qty = sum(float(r.quantity or 0.0) for r in remaining if r.type == "BUY")
        sell_qty = sum(float(r.quantity or 0.0) for r in remaining if r.type == "SELL")
        total_qty = buy_qty - sell_qty
        total_cost = sum(
            float(r.quantity or 0.0) * float(r.price or 0.0)
            for r in remaining if r.type == "BUY"
        )
        new_avg = (total_cost / buy_qty) if buy_qty > 0 else None

        h_res = await db.execute(
            select(Holding).where(Holding.user_id == owner_id, Holding.stock_id == stock_id)
        )
        holding = h_res.scalars().first()

        if total_qty <= 0.0001:
            # Nessuna quota residua: la posizione non esiste più.
            if holding:
                await db.delete(holding)
        elif holding:
            holding.quantity = round(total_qty, 4)
            if new_avg is not None:
                holding.avg_purchase_price = round(new_avg, 4)
        else:
            # Posizione ricreata dai movimenti residui (es. holding rimossa a mano).
            first_buy = next((r for r in remaining if r.type == "BUY"), None)
            purchase_day = (
                first_buy.transaction_date.date()
                if first_buy and isinstance(first_buy.transaction_date, datetime)
                else (first_buy.transaction_date if first_buy else None)
            )
            db.add(Holding(
                user_id=owner_id,
                stock_id=stock_id,
                quantity=round(total_qty, 4),
                avg_purchase_price=round(new_avg or 0.0, 4),
                purchase_date=purchase_day or date.today(),
            ))

        await _commit_write(db, conflict_detail="Conflitto nel ricalcolo della posizione, riprova.")
        await _invalidate_user_caches(current_user.id)

    return {"status": "success", "message": f"Transazione #{tx_id} rimossa."}


@router.get("/realized-pnl")
async def get_realized_pnl(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Riepilogo globale di P&L Realizzato, dividendi incassati e commissioni pagate per l'utente."""
    res = await db.execute(
        select(Transaction)
        .join(Stock)
        .where(Transaction.user_id == current_user.id)
        .options(selectinload(Transaction.stock))
    )
    txs = res.scalars().all()
    usd_to_eur = await MarketDataService.get_fx_rate("USD", "EUR")

    total_realized_capital_gains = 0.0
    total_dividends_collected = 0.0
    total_fees_paid = 0.0
    sell_fees_already_netted = 0.0
    wins = 0
    losses = 0

    for tx in txs:
        fx = usd_to_eur if (tx.currency == "USD") else 1.0
        fee_eur = tx.fee * fx
        total_fees_paid += fee_eur

        if tx.type == "SELL" and tx.realized_pnl is not None:
            pnl_eur = tx.realized_pnl * fx
            total_realized_capital_gains += pnl_eur
            # Convenzione: realized_pnl di una SELL è già al netto della fee
            # (vedi create_transaction), quindi la commissione di vendita è già
            # inclusa nel P&L capital gain e non va sottratta una seconda volta.
            # total_fees_paid resta il totale informativo lordo di tutte le fee.
            sell_fees_already_netted += fee_eur
            if pnl_eur >= 0:
                wins += 1
            else:
                losses += 1
        elif tx.type == "DIVIDEND":
            div_val = (tx.price * tx.quantity if tx.quantity > 0 else tx.price) * fx
            total_dividends_collected += div_val

    # Le fee su BUY e DIVIDEND non sono incluse altrove: si sottraggono dal
    # netto; le fee SELL sono già dentro total_realized_capital_gains.
    fees_not_yet_netted = total_fees_paid - sell_fees_already_netted
    net_realized_profit = (
        total_realized_capital_gains
        + total_dividends_collected
        - fees_not_yet_netted
    )
    win_rate = (wins / (wins + losses) * 100) if (wins + losses) > 0 else 0.0

    return {
        "total_realized_capital_gains": round(total_realized_capital_gains, 2),
        "total_dividends_collected": round(total_dividends_collected, 2),
        "total_fees_paid": round(total_fees_paid, 2),
        "net_realized_profit": round(net_realized_profit, 2),
        "trade_count": wins + losses,
        "win_trades": wins,
        "loss_trades": losses,
        "win_rate_percent": round(win_rate, 1),
        "transactions_count": len(txs)
    }


@router.get("/dividends")
async def get_dividends_calendar(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Calendario dividendi del portafoglio:
    Calcola il rendimento da dividendi, Yield on Cost (YoC) e flussi stimati per ogni holding dell'utente.
    """
    rows = await build_portfolio_rows(db, user_id=current_user.id)

    # Totali portafoglio derivati dalle righe già calcolate (nessun secondo build)
    total_value = round(sum(h.get("total_value_eur", h["total_value"]) for h in rows), 2)
    total_invested = round(sum(h.get("total_invested_eur", h["total_invested"]) for h in rows), 2)

    dividends_list = []
    total_projected_annual_eur = 0.0

    for h in rows:
        ticker = h["ticker"]
        div_yield = MarketDataService.get_stock_dividend_yield(ticker)
        current_price = h["current_price"]
        avg_buy_price = h["avg_purchase_price"]
        qty = h["quantity"]
        fx = h.get("fx_rate_to_eur", 1.0)

        # Calcolo dividendo annuo per azione
        annual_div_per_share = round(current_price * (div_yield / 100.0), 4) if div_yield > 0 else 0.0
        annual_income_native = round(annual_div_per_share * qty, 2)
        annual_income_eur = round(annual_income_native * fx, 2)
        total_projected_annual_eur += annual_income_eur

        # Yield on Cost: dividendo annuo diviso per prezzo medio di acquisto
        yield_on_cost = round((annual_div_per_share / avg_buy_price * 100.0), 2) if avg_buy_price > 0 else 0.0

        dividends_list.append({
            "ticker": ticker,
            "name": h["name"],
            "market": h["market"],
            "currency": h["currency"],
            "quantity": qty,
            "current_price": current_price,
            "avg_purchase_price": avg_buy_price,
            "dividend_yield_pct": div_yield,
            "yield_on_cost_pct": yield_on_cost,
            "annual_dividend_per_share": annual_div_per_share,
            "annual_income_eur": annual_income_eur,
            "monthly_income_eur": round(annual_income_eur / 12.0, 2)
        })

    # Ordina per reddito annuo stimato
    dividends_list.sort(key=lambda x: x["annual_income_eur"], reverse=True)

    return {
        "holdings": dividends_list,
        "total_annual_dividend_eur": round(total_projected_annual_eur, 2),
        "total_monthly_dividend_eur": round(total_projected_annual_eur / 12.0, 2),
        "portfolio_total_value": total_value,
        "portfolio_yield_on_cost": round(
            (total_projected_annual_eur / total_invested * 100.0), 2
        ) if total_invested > 0 else 0.0
    }


