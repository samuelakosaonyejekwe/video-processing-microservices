from fastapi import FastAPI
from app.routes.auth_routes import router as auth_router
from app.routes.converter_routes import router as converter_router
from app.routes.health_routes import router as health_router
from app.middleware.logging_middleware import LoggingMiddleware

app = FastAPI(
    title="Gateway Service",
    version="1.0.0"
)

app.add_middleware(LoggingMiddleware)

app.include_router(auth_router, prefix="/auth", tags=["Auth"])
app.include_router(converter_router, prefix="/converter", tags=["Converter"])
app.include_router(health_router, prefix="/health", tags=["Health"])


@app.get("/")
def root():
    return {
        "message": "Gateway Service Running"
    }