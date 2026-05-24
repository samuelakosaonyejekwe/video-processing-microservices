CREATE TABLE users (

    id SERIAL PRIMARY KEY,

    username VARCHAR(100) NOT NULL,

    email VARCHAR(255) UNIQUE NOT NULL,

    password VARCHAR(255) NOT NULL,

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);


CREATE TABLE conversions (

    id SERIAL PRIMARY KEY,

    user_id INTEGER REFERENCES users(id),

    original_filename VARCHAR(255),

    converted_filename VARCHAR(255),

    status VARCHAR(50),

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);