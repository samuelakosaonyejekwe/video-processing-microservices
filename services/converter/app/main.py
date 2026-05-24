from fastapi import FastAPI, UploadFile, File
from app.ffmpeg.convert import convert_video_to_audio
from app.queue.producer import publish_conversion_job

app = FastAPI(
    title="Converter Service",
    version="1.0.0"
)


@app.get("/")
def root():

    return {
        "message": "Converter Service Running"
    }


@app.post("/convert")
async def convert(file: UploadFile = File(...)):

    file_location = f"uploads/{file.filename}"

    with open(file_location, "wb") as buffer:
        buffer.write(await file.read())

    publish_conversion_job(file.filename)

    return {
        "message": "Conversion job queued",
        "filename": file.filename
    }