-- Runs once when the Postgres container is first created.
-- The pgvector/pgvector:pg16 image includes the vector extension binary;
-- this script enables it in the policyhub database.
CREATE EXTENSION IF NOT EXISTS vector;
-- Migration 017 also runs CREATE EXTENSION IF NOT EXISTS vector,
-- so this is belt-and-suspenders for cases where the container
-- is created before migrations run.
