db = db.getSiblingDB("video_converter");

db.createCollection("media");

db.media.createIndex(
    {
        filename: 1
    }
);

db.media.createIndex(
    {
        uploaded_at: -1
    }
);

print("Media collection created.");