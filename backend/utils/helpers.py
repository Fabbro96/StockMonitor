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
