from fastapi import APIRouter

from app.database.mongo_client import client

router = APIRouter()


@router.get("/health/mongodb")
def mongodb_health():

    client.admin.command("ping")

    return {"mongodb": "healthy"}
