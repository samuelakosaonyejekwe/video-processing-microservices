from fastapi import FastAPI
from app.queue.consumer import start_consumer

app = FastAPI(
    title="Notification Service",
    version="1.0.0"
)


@app.get("/")
def root():

    return {
        "message": "Notification Service Running"
    }


@app.get("/health")
def health():

    return {
        "status": "healthy"
    }