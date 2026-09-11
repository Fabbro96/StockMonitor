# ---------------------------------------------------------------------------
# Rilevamento mercato/valuta dal suffisso del ticker (convenzioni Yahoo Finance).
# Fonte unica di verità per la classificazione iniziale degli stock: il
# risultato di Yahoo può ARRICCHIRE (nome, settore, valuta dei ticker senza
# suffisso) ma non deve mai declassare un suffisso noto a US.
# ---------------------------------------------------------------------------
EU_SUFFIXES = (".DE", ".PA", ".AS", ".MC", ".LS", ".BR", ".VI")


def detect_market_currency(ticker: str | None) -> tuple[str, str]:
    """Ritorna (market, currency) dedotti dal suffisso del ticker.

    - `.MI` -> (IT, EUR); `.DE/.PA/.AS/.MC/.LS/.BR/.VI` -> (EU, EUR)
    - `=X` -> (FX, USD); `=F` -> (COMMODITY, USD)
    - `-USD`/`-EUR`/`-GBP` -> (CRYPTO, <valuta>)
    - default SOLO per ticker senza suffisso noto -> (US, USD)
    """
    t = (ticker or "").strip().upper()
    if not t:
        return ("US", "USD")
    if t.endswith(".MI"):
        return ("IT", "EUR")
    if t.endswith(EU_SUFFIXES):
        return ("EU", "EUR")
    if t.endswith("=X"):
        return ("FX", "USD")
    if t.endswith("=F"):
        return ("COMMODITY", "USD")
    if t.endswith("-USD"):
        return ("CRYPTO", "USD")
    if t.endswith("-EUR"):
        return ("CRYPTO", "EUR")
    if t.endswith("-GBP"):
        return ("CRYPTO", "GBP")
    return ("US", "USD")


def calculate_pnl(current_price: float, avg_price: float, quantity: int) -> dict:
    if current_price is None or avg_price is None or quantity is None:
        return {"pnl_absolute": 0.0, "pnl_percent": 0.0}
        
    invested = avg_price * quantity
    current_value = current_price * quantity
    pnl_absolute = current_value - invested
    
    pnl_percent = 0.0
    if invested > 0:
        pnl_percent = (pnl_absolute / invested) * 100
        
    return {
        "pnl_absolute": round(pnl_absolute, 2),
        "pnl_percent": round(pnl_percent, 2)
    }
