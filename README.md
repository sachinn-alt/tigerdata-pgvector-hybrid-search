# AI-Powered Vector Search with pgvector & pgvectorscale in Tiger Cloud

> **MLH Global Hack Week Challenge:** Implement AI-Powered Vector Search with pgvector  
> **Sponsor / Technology:** Tiger Data & TimescaleDB  
> **Author:** SACHIN KUMAR SINGH (`sachin-alt`)  
> **Live Tiger Cloud Service:** [`cagg-analytics` (Service ID: `kiwbq9oup6`)](https://console.cloud.tigerdata.com/dashboard/services/kiwbq9oup6)

---

## 🎯 Project Overview

Modern AI-driven systems (Retrieval-Augmented Generation / RAG, observability assistants, fraud intelligence) frequently require searching both **semantic similarity** (what does this mean?) and **temporal relevance** (when did this happen?).

Traditionally, teams manage this by synchronizing an external vector database sidecar (e.g., Pinecone, Milvus) alongside their primary relational database. This introduces data sync lag, distributed consistency issues, and redundant infrastructure costs.

This project implements **AI-Powered Vector Search directly inside PostgreSQL on Tiger Cloud** using:
* **`pgvector` (0.8.7):** Dense vector storage and cosine distance calculations (`<=>`).
* **`pgvectorscale` (0.9.0):** Timescale's high-performance **StreamingDiskANN** index for disk-backed, memory-efficient vector recall.
* **TimescaleDB Hypertables:** Partitioning embeddings across time chunks to enable automatic **temporal chunk skipping** during hybrid similarity queries.

---

## ☁️ Tiger Cloud Service Details

* **Service Name:** `cagg-analytics`
* **Service ID:** `kiwbq9oup6`
* **Type:** TimescaleDB (PostgreSQL) with `pgvector` & `pgvectorscale`
* **Region:** `us-east-1`
* **Console URL:** [https://console.cloud.tigerdata.com/dashboard/services/kiwbq9oup6](https://console.cloud.tigerdata.com/dashboard/services/kiwbq9oup6)

---

## 🏗️ Architecture & Search Flow

```
                      +------------------------------------------+
                      |         User / AI Agent Query            |
                      |   "Payment checkout timeout errors"      |
                      +------------------------------------------+
                                           |
                                           v
                      +------------------------------------------+
                      |       Text-to-Embedding Model            |
                      |       (384-dimensional vector)           |
                      +------------------------------------------+
                                           |
                                           v
+-----------------------------------------------------------------------------------------+
|                               TIGER CLOUD (PostgreSQL)                                  |
|                                                                                         |
|   +---------------------------------------------------------------------------------+   |
|   |                 system_incident_embeddings (Hypertable)                         |   |
|   |         (id, created_at, service, severity, summary, content, embedding)        |   |
|   +---------------------------------------------------------------------------------+   |
|                        |                                        |                       |
|        [1. Temporal Chunk Pruning]               [2. StreamingDiskANN Vector Index]     |
|       Only scans recent 7-day chunks              Sub-millisecond cosine distance (<=>) |
|                        \                                        /                       |
|                         v                                      v                        |
|   +---------------------------------------------------------------------------------+   |
|   |                                  HYBRID RESULTS                                 |   |
|   |                Top-K matches ranked by semantic cosine similarity               |   |
|   +---------------------------------------------------------------------------------+   |
+-----------------------------------------------------------------------------------------+
```

---

## 🛠️ Step-by-Step Implementation

### 1. Database Schema (`schema.sql`)

```sql
-- Enable extensions
CREATE EXTENSION IF NOT EXISTS vector CASCADE;
CREATE EXTENSION IF NOT EXISTS vectorscale CASCADE;

-- Create table with 384-dimensional vector embeddings
CREATE TABLE system_incident_embeddings (
    id          SERIAL,
    created_at  TIMESTAMPTZ NOT NULL,
    service     VARCHAR(64) NOT NULL,
    severity    VARCHAR(16) NOT NULL,
    summary     TEXT NOT NULL,
    content     TEXT NOT NULL,
    embedding   VECTOR(384) NOT NULL,
    PRIMARY KEY (id, created_at)
);

-- Convert into TimescaleDB Hypertable partitioned by created_at
SELECT create_hypertable('system_incident_embeddings', by_range('created_at'));

-- Build StreamingDiskANN vector index via pgvectorscale
CREATE INDEX idx_incident_embedding_diskann 
ON system_incident_embeddings USING diskann (embedding);

-- Compound index for service and time pruning
CREATE INDEX idx_incident_service_time 
ON system_incident_embeddings (service, created_at DESC);
```

---

## 📊 Live Verification on Tiger Cloud (`kiwbq9oup6`)

### 1. Semantic Vector Similarity Query (`<=>`)

Searches the hypertable for incidents conceptually closest to payment gateway failures:

```sql
WITH query AS (
    SELECT embedding FROM system_incident_embeddings 
    WHERE summary LIKE 'Stripe webhook%' LIMIT 1
)
SELECT 
    id, service, severity, summary, 
    ROUND((system_incident_embeddings.embedding <=> query.embedding)::numeric, 4) AS cosine_distance
FROM system_incident_embeddings, query
ORDER BY cosine_distance ASC
LIMIT 4;
```

**Live Output from Tiger Cloud:**
```
 id |     service      | severity |                                summary                                 | cosine_distance 
----+------------------+----------+------------------------------------------------------------------------+-----------------
  1 | payment-api      | CRITICAL | Stripe webhook timeout causing transaction failure and double charging |          0.0000
  5 | search-indexer   | LOW      | Elasticsearch heap memory warning on node-03                           |          0.9366
  2 | auth-service     | HIGH     | OAuth2 token verification rate limit exceeded                          |          0.9794
  4 | database-cluster | CRITICAL | PostgreSQL connection pool saturation during automated nightly backup  |          1.0083
```

### 2. Hybrid Search (Semantic Meaning + Temporal Chunk Pruning)

Filters to the last 7 days (`created_at >= NOW() - INTERVAL '7 days'`) on `payment-api` while ranking by semantic similarity:

```sql
WITH query AS (
    SELECT embedding FROM system_incident_embeddings 
    WHERE summary LIKE 'Stripe webhook%' LIMIT 1
)
SELECT 
    id, service, severity, summary, created_at, 
    ROUND((1 - (system_incident_embeddings.embedding <=> query.embedding))::numeric, 4) AS cosine_similarity
FROM system_incident_embeddings, query
WHERE created_at >= NOW() - INTERVAL '7 days'
  AND service = 'payment-api'
ORDER BY system_incident_embeddings.embedding <=> query.embedding ASC;
```

**Live Output from Tiger Cloud:**
```
 id |   service   | severity |                                summary                                 |          created_at           | cosine_similarity 
----+-------------+----------+------------------------------------------------------------------------+-------------------------------+-------------------
  1 | payment-api | CRITICAL | Stripe webhook timeout causing transaction failure and double charging | 2026-10-14 12:58:50.650184+00 |            1.0000
  3 | payment-api | MEDIUM   | SSL handshake failure with Visa gateway endpoint                       | 2026-10-09 14:58:50.650184+00 |           -0.0203
```

---

## 💡 Key Architectural Advantages

1. **No External Sidecar Required:** Eliminates the operational complexity, network latency, and billing overhead of external vector databases (Pinecone, Weaviate).
2. **Temporal Chunk Exclusion:** TimescaleDB hypertables prune entire time chunks that fall outside the query window *before* calculating vector distances, dramatically accelerating search on large historical datasets.
3. **StreamingDiskANN Efficiency:** Delivers high query throughput and recall while keeping index storage primarily on disk, overcoming memory constraints common to in-memory HNSW indexes.
