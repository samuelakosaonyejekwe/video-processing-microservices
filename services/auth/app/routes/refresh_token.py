from fastapi import APIRouter

router = APIRouter()


@router.post("/refresh")
def refresh_token():

    return {
        "access_token": "new-sample-jwt-token"
    }