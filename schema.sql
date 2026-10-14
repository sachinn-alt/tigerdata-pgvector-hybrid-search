-- ============================================================================
-- Tiger Data: AI-Powered Vector Search with pgvector & pgvectorscale
-- Challenge: Implement AI-Powered Vector Search with pgvector
-- ============================================================================

-- 1. Enable pgvector and pgvectorscale extensions
CREATE EXTENSION IF NOT EXISTS vector CASCADE;
CREATE EXTENSION IF NOT EXISTS vectorscale CASCADE;

-- 2. Create the Knowledge & Incident Telemetry Table with Vector Embeddings
DROP TABLE IF EXISTS system_incident_embeddings CASCADE;

CREATE TABLE system_incident_embeddings (
    id          SERIAL,
    created_at  TIMESTAMPTZ NOT NULL,
    service     VARCHAR(64) NOT NULL,
    severity    VARCHAR(16) NOT NULL,
    summary     TEXT NOT NULL,
    content     TEXT NOT NULL,
    embedding   VECTOR(384) NOT NULL, -- 384-dimensional dense semantic embedding (all-MiniLM-L6-v2)
    PRIMARY KEY (id, created_at)
);

-- 3. Convert into a TimescaleDB Hypertable partitioned by created_at
-- Enables automatic temporal chunk skipping when filtering by time
SELECT create_hypertable(
    'system_incident_embeddings', 
    by_range('created_at'),
    if_not_exists => TRUE
);

-- 4. Create StreamingDiskANN Index (via pgvectorscale) for High-Recall Vector Search
-- Uses disk-optimized indexing to reduce RAM usage while preserving search throughput
CREATE INDEX IF NOT EXISTS idx_incident_embedding_diskann 
ON system_incident_embeddings USING diskann (embedding);

-- 5. Create Compound Index for Fast Metadata & Temporal Pruning
CREATE INDEX IF NOT EXISTS idx_incident_service_time 
ON system_incident_embeddings (service, created_at DESC);
