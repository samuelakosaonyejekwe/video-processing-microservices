from fastapi import APIRouter

router = APIRouter(prefix="/health", tags=["Health"])


@router.get("/mongodb")
def mongodb_health():

    try:
        from app.database.mongo_client import client

        client.admin.command("ping")

        return {"mongodb": "healthy"}

    except Exception as exc:
        return {"mongodb": "unhealthy", "detail": str(exc)}


@router.get("/ready")
def readiness_check():

    return {"status": "ready"}


@router.get("/live")
def liveness_check():

    return {"status": "alive"}
