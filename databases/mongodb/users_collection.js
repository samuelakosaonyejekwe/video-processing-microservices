db = db.getSiblingDB("video_converter");

db.createCollection("users");

db.users.createIndex(
    {
        email: 1
    },
    {
        unique: true
    }
);

print("Users collection created.");