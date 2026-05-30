import os

from pymongo import MongoClient

mongo_uri = os.getenv("MONGO_URI")

mongo_database = os.getenv("MONGO_DATABASE")

client = MongoClient(
    mongo_uri,
    retryWrites=True,
    serverSelectionTimeoutMS=10000,
    connectTimeoutMS=10000,
    socketTimeoutMS=10000,
    maxPoolSize=50,
    minPoolSize=5,
)

db = client[mongo_database]