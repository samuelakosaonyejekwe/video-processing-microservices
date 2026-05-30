const databaseName =
    process.env.MONGO_DATABASE;

const mediaCollectionName =
    process.env.MONGO_MEDIA_COLLECTION;

const mediaFilenameIndexName =
    process.env.MONGO_MEDIA_FILENAME_INDEX_NAME;

const mediaUploadedAtIndexName =
    process.env.MONGO_MEDIA_UPLOADED_AT_INDEX_NAME;

const mediaStatusIndexName =
    process.env.MONGO_MEDIA_STATUS_INDEX_NAME;

const mediaUserIdIndexName =
    process.env.MONGO_MEDIA_USER_ID_INDEX_NAME;

const mediaFormatIndexName =
    process.env.MONGO_MEDIA_FORMAT_INDEX_NAME;

const mediaCreatedAtTTLIndexName =
    process.env.MONGO_MEDIA_CREATED_AT_TTL_INDEX_NAME;

const mediaFileHashIndexName =
    process.env.MONGO_MEDIA_FILE_HASH_INDEX_NAME;

const mediaTTLSeconds =
    Number(process.env.MEDIA_TTL_SECONDS);


if (
    !databaseName ||
    !mediaCollectionName ||
    !mediaTTLSeconds
) {
    throw new Error(
        "Required MongoDB environment variables are missing."
    );
}


db = db.getSiblingDB(
    databaseName
);


db.createCollection(
    mediaCollectionName
);


db[mediaCollectionName].createIndex(
    {
        filename: 1
    },
    {
        name: mediaFilenameIndexName
    }
);


db[mediaCollectionName].createIndex(
    {
        uploaded_at: -1
    },
    {
        name: mediaUploadedAtIndexName
    }
);


db[mediaCollectionName].createIndex(
    {
        status: 1
    },
    {
        name: mediaStatusIndexName
    }
);


db[mediaCollectionName].createIndex(
    {
        user_id: 1
    },
    {
        name: mediaUserIdIndexName
    }
);


db[mediaCollectionName].createIndex(
    {
        conversion_format: 1
    },
    {
        name: mediaFormatIndexName
    }
);


db[mediaCollectionName].createIndex(
    {
        createdAt: 1
    },
    {
        name: mediaCreatedAtTTLIndexName,
        expireAfterSeconds: mediaTTLSeconds
    }
);


db[mediaCollectionName].createIndex(
    {
        file_hash: 1
    },
    {
        unique: true,
        sparse: true,
        name: mediaFileHashIndexName
    }
);


print(
    "MongoDB media collection and indexes created successfully."
);