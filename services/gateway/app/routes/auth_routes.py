from fastapi import APIRouter

router = APIRouter()


@router.post("/login")
def login():
    return {
        "message": "Login route"
    }


@router.post("/register")
def register():
    return {
        "message": "Register route"
    }