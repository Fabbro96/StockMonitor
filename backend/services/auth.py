import asyncio
import logging
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from typing import Optional
import bcrypt
import jwt
from fastapi import Request, HTTPException, Depends, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.future import select
from sqlalchemy.ext.asyncio import AsyncSession

from backend.config import settings
from backend.database import get_db
from backend.models.user import User

logger = logging.getLogger(__name__)

security_bearer = HTTPBearer(auto_error=False)

ALGORITHM = "HS256"

# Pool dedicato per bcrypt (cost 12 = CPU-bound ~0.5-1.5s su ARM): evita che
# login paralleli saturino il default executor di asyncio (8 thread), che
# bloccherebbe anche il resto dell'app. Dimensione volutamente piccola (2).
_BCRYPT_EXECUTOR_MAX_WORKERS = 2
_bcrypt_executor = ThreadPoolExecutor(
    max_workers=_BCRYPT_EXECUTOR_MAX_WORKERS,
    thread_name_prefix="bcrypt",
)

def hash_password(password: str) -> str:
    salt = bcrypt.gensalt(rounds=12)
    return bcrypt.hashpw(password.encode("utf-8"), salt).decode("utf-8")

def verify_password(plain_password: str, hashed_password: str) -> bool:
    try:
        return bcrypt.checkpw(plain_password.encode("utf-8"), hashed_password.encode("utf-8"))
    except Exception as e:
        logger.error(f"Errore durante la verifica della password: {e}")
        return False

async def hash_password_async(password: str) -> str:
    """Esegue l'hashing bcrypt (CPU-bound, cost 12) nel pool dedicato,
    evitando di bloccare l'event loop o di saturare il default executor."""
    loop = asyncio.get_running_loop()
    return await loop.run_in_executor(_bcrypt_executor, hash_password, password)

async def verify_password_async(plain_password: str, hashed_password: str) -> bool:
    """Esegue la verifica bcrypt nel pool dedicato (off event loop)."""
    loop = asyncio.get_running_loop()
    return await loop.run_in_executor(_bcrypt_executor, verify_password, plain_password, hashed_password)

def shutdown_bcrypt_executor() -> None:
    """Shutdown best-effort del pool bcrypt (invocata dal lifespan in uscita)."""
    try:
        _bcrypt_executor.shutdown(wait=False, cancel_futures=True)
    except TypeError:  # Python < 3.9
        _bcrypt_executor.shutdown(wait=False)

def create_access_token(data: dict, expires_delta: Optional[timedelta] = None) -> str:
    to_encode = data.copy()
    if expires_delta:
        expire = datetime.now(timezone.utc) + expires_delta
    else:
        expire = datetime.now(timezone.utc) + timedelta(days=settings.ACCESS_TOKEN_EXPIRE_DAYS)
    
    to_encode.update({"exp": expire, "iat": datetime.now(timezone.utc)})
    encoded_jwt = jwt.encode(to_encode, settings.SECRET_KEY, algorithm=ALGORITHM)
    return encoded_jwt

def decode_access_token(token: str) -> Optional[dict]:
    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[ALGORITHM])
        return payload
    except jwt.ExpiredSignatureError:
        logger.warning("Token JWT scaduto")
        return None
    except jwt.InvalidTokenError as e:
        logger.warning(f"Token JWT non valido: {e}")
        return None

async def get_current_user(
    request: Request,
    auth_credentials: Optional[HTTPAuthorizationCredentials] = Depends(security_bearer),
    db: AsyncSession = Depends(get_db)
) -> User:
    token = None
    
    # 1. Check Bearer header
    if auth_credentials and auth_credentials.credentials:
        token = auth_credentials.credentials
        
    # 2. Check HttpOnly Cookie fallback
    if not token:
        token = request.cookies.get("access_token")
        
    if not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Sessione non valida o scaduta. Effettua il login.",
            headers={"WWW-Authenticate": "Bearer"},
        )
        
    payload = decode_access_token(token)
    if not payload or "sub" not in payload:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token di autenticazione non valido.",
            headers={"WWW-Authenticate": "Bearer"},
        )
        
    username = payload["sub"]
    result = await db.execute(select(User).where(User.username == username))
    user = result.scalars().first()
    
    if not user or not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Utente non trovato o disabilitato.",
            headers={"WWW-Authenticate": "Bearer"},
        )
        
    return user

async def require_admin(current_user: User = Depends(get_current_user)) -> User:
    if not current_user.is_admin:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Operazione riservata esclusivamente all'amministratore."
        )
    return current_user

