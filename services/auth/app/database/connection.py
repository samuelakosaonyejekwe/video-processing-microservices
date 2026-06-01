import os

from sqlalchemy import URL, create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import QueuePool

from app.config import (
    POSTGRES_DB,
    POSTGRES_HOST,
    POSTGRES_PASSWORD,
    POSTGRES_PORT,
    POSTGRES_SSL_MODE,
    POSTGRES_USER,
)

DATABASE_POOL_SIZE = int(os.getenv("DATABASE_POOL_SIZE", "10") or "10")
DATABASE_MAX_OVERFLOW = int(os.getenv("DATABASE_MAX_OVERFLOW", "20") or "20")
DATABASE_POOL_TIMEOUT = int(os.getenv("DATABASE_POOL_TIMEOUT", "30") or "30")
DATABASE_POOL_RECYCLE = int(os.getenv("DATABASE_POOL_RECYCLE", "1800") or "1800")

# Build the URL as a SQLAlchemy URL object rather than a plain string so the
# password is never embedded in a module-level string and is masked (***) in
# the object's repr / logs.
DATABASE_URL = URL.create(
    "postgresql",
    username=POSTGRES_USER,
    password=POSTGRES_PASSWORD,
    host=POSTGRES_HOST,
    port=int(POSTGRES_PORT) if str(POSTGRES_PORT).strip() else None,
    database=POSTGRES_DB,
    query={"sslmode": POSTGRES_SSL_MODE} if POSTGRES_SSL_MODE else {},
)

engine = create_engine(
    DATABASE_URL,
    poolclass=QueuePool,
    pool_size=DATABASE_POOL_SIZE,
    max_overflow=DATABASE_MAX_OVERFLOW,
    pool_timeout=DATABASE_POOL_TIMEOUT,
    pool_recycle=DATABASE_POOL_RECYCLE,
    pool_pre_ping=True,
)

SessionLocal = sessionmaker(
    autocommit=False,
    autoflush=False,
    bind=engine,
)
