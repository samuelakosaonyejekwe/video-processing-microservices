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
-- Grant Database Privileges (Least Privilege)
-- The app needs to connect, use the public schema, run DML on its
-- tables, and use sequences for serial primary keys. It does NOT need
-- ownership/DDL/ALL ON DATABASE.
-- =========================================================

DO
$$
DECLARE
   app_user text := current_setting('app.postgres_user');
BEGIN
   -- Connect on the application database only.
   EXECUTE format('GRANT CONNECT ON DATABASE video_converter_db TO %I', app_user);

   -- Schema usage (required to reference any object in public).
   EXECUTE format('GRANT USAGE ON SCHEMA public TO %I', app_user);

   -- DML on all existing tables.
   EXECUTE format(
      'GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO %I',
      app_user
   );

   -- Sequence usage for serial / identity primary keys.
   EXECUTE format(
      'GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA public TO %I',
      app_user
   );

   -- Ensure future tables/sequences created in public are covered too.
   EXECUTE format(
      'ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO %I',
      app_user
   );
   EXECUTE format(
      'ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO %I',
      app_user
   );
END
$$;