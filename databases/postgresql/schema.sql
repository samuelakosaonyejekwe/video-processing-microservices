CREATE TABLE IF NOT EXISTS users (

    id SERIAL PRIMARY KEY,

    username VARCHAR(100) NOT NULL,

    email VARCHAR(255) UNIQUE NOT NULL,

    password VARCHAR(255) NOT NULL,

    role VARCHAR(50) NOT NULL DEFAULT 'user'
        CHECK (role IN ('user', 'admin')),

    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);


CREATE TABLE IF NOT EXISTS conversions (

    id SERIAL PRIMARY KEY,

    user_id INTEGER NOT NULL REFERENCES users(id),

    original_filename VARCHAR(255) NOT NULL,

    converted_filename VARCHAR(255),

    status VARCHAR(50) NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'queued', 'processing', 'completed', 'failed')),

    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);


-- Indexes to support common lookups (per-user history, status filtering).
CREATE INDEX IF NOT EXISTS idx_conversions_user_id ON conversions (user_id);

CREATE INDEX IF NOT EXISTS idx_conversions_status ON conversions (status);
