from fastapi import FastAPI
from app.routes.login import router as login_router
from app.routes.register import router as register_router
from app.routes.refresh_token import router as refresh_router

app = FastAPI(
    title="Auth Service",
    version="1.0.0"
)

app.include_router(login_router, prefix="/auth", tags=["Login"])
app.include_router(register_router, prefix="/auth", tags=["Register"])
app.include_router(refresh_router, prefix="/auth", tags=["Refresh Token"])


@app.get("/")
def root():
    return {
        "message": "Auth Service Running"
    }