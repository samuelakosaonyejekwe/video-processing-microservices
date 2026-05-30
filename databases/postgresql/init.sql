-- =========================================================
-- PostgreSQL Initialization Script
-- Production-Grade Secure Version
-- File: databases/postgresql/init.sql
-- =========================================================

-- Create Application Database
CREATE DATABASE video_converter_db;

-- =========================================================
-- Create Application User Securely
-- Credentials injected from environment variables
-- =========================================================

DO
$$
BEGIN
   IF NOT EXISTS (
      SELECT
      FROM pg_catalog.pg_roles
      WHERE rolname = current_setting('app.postgres_user', true)
   ) THEN

      EXECUTE format(
         'CREATE USER %I WITH PASSWORD %L',
         current_setting('app.postgres_user'),
         current_setting('app.postgres_password')
      );

   END IF;
END
$$;

-- =========================================================
-- Grant Database Privileges
-- =========================================================

GRANT ALL PRIVILEGES
ON DATABASE video_converter_db
TO CURRENT_SETTING('app.postgres_user');