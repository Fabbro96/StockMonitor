import inspect
import logging
from datetime import datetime, timedelta, timezone
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, Response, status
from pydantic import BaseModel, Field
from sqlalchemy import case, delete as sa_delete, func, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.future import select
from sqlalchemy.ext.asyncio import AsyncSession

from backend.database import get_db
from backend.models.advice import Advice
from backend.models.portfolio import Holding, Transaction
from backend.models.settings import AlertRule, UserSettings
from backend.models.target_allocation import TargetAllocation
from backend.models.user import User
from backend.models.watchlist import WatchlistItem
from backend.services.auth import (
    verify_password_async,
    hash_password_async,
    create_access_token,
    get_current_user,
    require_admin
)

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/auth", tags=["auth"])

MAX_FAILED_ATTEMPTS = 5
LOCKOUT_MINUTES = 15

class LoginRequest(BaseModel):
    username: str = Field(..., min_length=1)
    password: str = Field(..., min_length=1)

class ChangePasswordRequest(BaseModel):
    current_password: str = Field(..., min_length=1)
    new_password: str = Field(..., min_length=8, description="La nuova password deve contenere almeno 8 caratteri")

class CreateUserRequest(BaseModel):
    username: str = Field(..., min_length=3, max_length=50)
    password: str = Field(..., min_length=8)
    is_admin: bool = False

class ResetUserPasswordRequest(BaseModel):
    new_password: str = Field(..., min_length=8)

class UserResponse(BaseModel):
    id: int
    username: str
    is_admin: bool
    is_active: bool
    created_at: datetime
    last_login: Optional[datetime] = None

    class Config:
        from_attributes = True

@router.post("/login")
async def login(
    login_data: LoginRequest,
    response: Response,
    db: AsyncSession = Depends(get_db)
):
    username = login_data.username.strip()
    result = await db.execute(select(User).where(User.username == username))
    user = result.scalars().first()

    now = datetime.now(timezone.utc)

    if not user:
        logger.warning(f"Tentativo di login fallito per utente inesistente: {username}")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Credenziali non corrette."
        )

    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Questo account è stato disabilitato dall'amministratore."
        )

    # Verifica blocco per troppi tentativi falliti
    if user.locked_until:
        locked_time = user.locked_until
        if locked_time.tzinfo is None:
            locked_time = locked_time.replace(tzinfo=timezone.utc)
            
        if locked_time > now:
            remaining = int((locked_time - now).total_seconds() / 60) + 1
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail=f"Account temporaneamente bloccato per sicurezza. Riprova tra {remaining} minuti."
            )
        else:
            user.locked_until = None
            user.failed_attempts = 0

    if not await verify_password_async(login_data.password, user.hashed_password):
        # M10: incremento ATOMICO lato DB (failed_attempts = failed_attempts + 1):
        # due login falliti in parallelo contano entrambi, niente check-then-write.
        # Il lockout scatta nello stesso UPDATE via CASE, quindi non c'è finestra
        # tra conteggio e blocco. Il valore letto è solo per il messaggio.
        increment = func.coalesce(User.failed_attempts, 0) + 1
        lock_until = now + timedelta(minutes=LOCKOUT_MINUTES)
        await db.execute(
            update(User)
            .where(User.id == user.id)
            .values(
                failed_attempts=increment,
                locked_until=case(
                    (increment >= MAX_FAILED_ATTEMPTS, lock_until),
                    else_=User.locked_until,
                ),
            )
        )
        await db.commit()
        failed_attempts = (
            await db.execute(select(User.failed_attempts).where(User.id == user.id))
        ).scalar() or 1
        # Risincronizza l'istanza ORM con i valori appena scritti.
        await db.refresh(user)

        if failed_attempts >= MAX_FAILED_ATTEMPTS:
            logger.warning(f"Account bloccato per troppi tentativi: {username}")
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Troppi tentativi falliti. Account bloccato per 15 minuti."
            )

        remaining_attempts = MAX_FAILED_ATTEMPTS - failed_attempts
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Password errata. {remaining_attempts} tentativi rimasti prima del blocco temporaneo."
        )

    # Login riuscito
    user.failed_attempts = 0
    user.locked_until = None
    user.last_login = now
    await db.commit()

    token = create_access_token(data={"sub": user.username})

    response.set_cookie(
        key="access_token",
        value=token,
        httponly=True,
        max_age=7 * 24 * 3600,
        samesite="lax",
        secure=False
    )

    return {
        "access_token": token,
        "token_type": "bearer",
        "username": user.username,
        "is_admin": user.is_admin
    }

@router.post("/logout")
async def logout(response: Response):
    response.delete_cookie(key="access_token", path="/")
    return {"status": "success", "message": "Disconnesso con successo"}

@router.get("/me", response_model=UserResponse)
async def get_me(current_user: User = Depends(get_current_user)):
    return current_user

@router.post("/change-password")
async def change_password(
    data: ChangePasswordRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    if not await verify_password_async(data.current_password, current_user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="La password attuale non è corretta."
        )

    if len(data.new_password) < 8:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="La nuova password deve contenere almeno 8 caratteri."
        )

    current_user.hashed_password = await hash_password_async(data.new_password)
    await db.commit()
    return {"status": "success", "message": "Password modificata con successo"}

# ==========================================
# GESTIONE UTENTI (RISERVATA AGLI AMMINISTRATORI)
# ==========================================

@router.get("/users", response_model=List[UserResponse])
async def list_users(
    admin_user: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db)
):
    """Restituisce la lista di tutti gli utenti (solo per admin)."""
    result = await db.execute(select(User).order_by(User.id))
    return result.scalars().all()

@router.post("/users", response_model=UserResponse)
async def create_user(
    data: CreateUserRequest,
    admin_user: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db)
):
    """Crea un nuovo utente (solo per admin)."""
    username = data.username.strip()
    
    # Check if username already exists
    existing = await db.execute(select(User).where(User.username == username))
    if existing.scalars().first():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"L'utente '{username}' esiste già."
        )

    new_user = User(
        username=username,
        hashed_password=await hash_password_async(data.password),
        is_admin=data.is_admin,
        is_active=True
    )
    db.add(new_user)
    try:
        await db.commit()
        await db.refresh(new_user)
    except IntegrityError:
        # H8: race su UNIQUE(users.username) tra il check e l'INSERT.
        # Ri-seleziona e restituisci lo stesso 400 del controllo preventivo.
        await db.rollback()
        existing = await db.execute(select(User).where(User.username == username))
        if existing.scalars().first():
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"L'utente '{username}' esiste già."
            )
        raise
    return new_user

@router.delete("/users/{user_id}")
async def delete_user(
    user_id: int,
    admin_user: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db)
):
    """Elimina un utente (solo per admin, non è consentito eliminare se stessi)."""
    if admin_user.id == user_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Non puoi eliminare il tuo stesso account amministratore."
        )

    user = await db.get(User, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="Utente non trovato")

    # Le FK aggiunte via ALTER TABLE non hanno ON DELETE CASCADE sul DB esistente:
    # eliminiamo esplicitamente i dati dell'utente prima di rimuovere l'account.
    # ORDINE: prima le tabelle dipendenti (TargetAllocation inclusa, altrimenti
    # PRAGMA foreign_keys=ON fa fallire il db.delete(user) con IntegrityError).
    username = user.username
    await db.execute(sa_delete(TargetAllocation).where(TargetAllocation.user_id == user_id))
    await db.execute(sa_delete(Holding).where(Holding.user_id == user_id))
    await db.execute(sa_delete(Transaction).where(Transaction.user_id == user_id))
    await db.execute(sa_delete(WatchlistItem).where(WatchlistItem.user_id == user_id))
    await db.execute(sa_delete(UserSettings).where(UserSettings.user_id == user_id))
    await db.execute(sa_delete(AlertRule).where(AlertRule.user_id == user_id))
    await db.execute(sa_delete(Advice).where(Advice.user_id == user_id))
    await db.delete(user)
    await db.commit()

    # Invalida le cache per-utente (serie/risk). Import lazy con guardia:
    # `analytics.invalidate_user_caches` è aggiunta dalla lane BE-3.
    try:
        from backend.services.analytics import invalidate_user_caches
        result = invalidate_user_caches(user_id)
        if inspect.isawaitable(result):
            await result
    except Exception as e:
        logger.warning(f"Invalidazione cache per l'utente {user_id} non riuscita: {e}")

    return {"status": "success", "message": f"Utente '{username}' eliminato"}

@router.put("/users/{user_id}/reset-password")
async def admin_reset_password(
    user_id: int,
    data: ResetUserPasswordRequest,
    admin_user: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db)
):
    """Reimposta la password di un utente (solo per admin)."""
    user = await db.get(User, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="Utente non trovato")

    user.hashed_password = await hash_password_async(data.new_password)
    user.failed_attempts = 0
    user.locked_until = None
    await db.commit()
    return {"status": "success", "message": f"Password reimpostata per l'utente '{user.username}'"}
