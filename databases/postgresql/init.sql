CREATE DATABASE video_converter_db;

CREATE USER video_user WITH PASSWORD 'password123';

GRANT ALL PRIVILEGES ON DATABASE video_converter_db TO video_user;