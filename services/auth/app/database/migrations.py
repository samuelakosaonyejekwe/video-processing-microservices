"""Schema bootstrap for the auth service.

Creates tables from the SQLAlchemy models using the configured engine. This is
the same metadata used by the application at runtime, so the schema (including
unique constraints on email and username) stays in sync with the ORM models.
"""

import logging

from app.database.connection import engine
from app.models.user_entity import Base

logger = logging.getLogger(__name__)


def create_users_table() -> None:
    Base.metadata.create_all(bind=engine)


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    create_users_table()
    logger.info("Users table created successfully.")
