db = db.getSiblingDB("video_converter");

db.createUser({
    user: process.env.MONGO_USERNAME || "admin",
    pwd: process.env.MONGO_PASSWORD || "changeme",
    roles: [
        {
            role: "readWrite",
            db: "video_converter"
        }
    ]
});

print("MongoDB database initialized.");