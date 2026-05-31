import logging
import os

from pymongo import MongoClient
from pymongo.database import Database

logger = logging.getLogger(__name__)

_client: MongoClient | None = None
_db: Database | None = None


def _mongo_uri() -> str:
    return (os.getenv("MONGO_URI") or "").strip()


def _mongo_database_name() -> str:
    return (os.getenv("MONGO_DATABASE") or "video_converter").strip()


def is_mongo_configured() -> bool:
    return bool(_mongo_uri())


def get_database() -> Database | None:
    global _client, _db

    if not is_mongo_configured():
        return None

    if _db is not None:
        return _db

    _client = MongoClient(
        _mongo_uri(),
        retryWrites=True,
        serverSelectionTimeoutMS=2000,
        connectTimeoutMS=2000,
        socketTimeoutMS=5000,
        maxPoolSize=20,
        minPoolSize=1,
    )
    _db = _client[_mongo_database_name()]
    logger.info(
        "Gateway MongoDB client initialized database=%s", _mongo_database_name()
    )
    return _db


def close_mongo_client() -> None:
    global _client, _db

    if _client is not None:
        _client.close()
        _client = None
        _db = None
