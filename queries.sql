-- ============================================================================
-- Hybrid Vector Search & Temporal Analytics Queries
-- ============================================================================

-- Query 1: Pure Semantic Similarity Search (Cosine Distance <=>)
-- Finds most conceptually relevant incidents regardless of when they occurred
WITH query_input AS (
    SELECT embedding FROM system_incident_embeddings WHERE summary LIKE 'Stripe webhook%' LIMIT 1
)
SELECT 
    id, 
    service, 
    severity, 
    summary, 
    ROUND((system_incident_embeddings.embedding <=> query_input.embedding)::numeric, 4) AS cosine_distance
FROM system_incident_embeddings, query_input
ORDER BY cosine_distance ASC
LIMIT 5;


-- Query 2: Hybrid Search (Semantic Meaning + Temporal Chunk Pruning)
-- Filters strictly to incidents in the last 7 days while ordering by semantic relevance
WITH query_input AS (
    SELECT embedding FROM system_incident_embeddings WHERE summary LIKE 'Stripe webhook%' LIMIT 1
)
SELECT 
    id, 
    service, 
    severity, 
    summary, 
    created_at, 
    ROUND((1 - (system_incident_embeddings.embedding <=> query_input.embedding))::numeric, 4) AS cosine_similarity
FROM system_incident_embeddings, query_input
WHERE created_at >= NOW() - INTERVAL '7 days'
  AND service = 'payment-api'
ORDER BY system_incident_embeddings.embedding <=> query_input.embedding ASC;


-- Query 3: Multi-Filter RAG Retrieval (Semantic + Severity + Time Window)
-- Ideal for context injection in incident triage agents
WITH query_input AS (
    SELECT embedding FROM system_incident_embeddings WHERE severity = 'CRITICAL' LIMIT 1
)
SELECT 
    id,
    created_at,
    service,
    severity,
    summary,
    content,
    ROUND((system_incident_embeddings.embedding <=> query_input.embedding)::numeric, 4) AS distance
FROM system_incident_embeddings, query_input
WHERE created_at >= NOW() - INTERVAL '30 days'
  AND severity IN ('CRITICAL', 'HIGH')
ORDER BY distance ASC
LIMIT 3;
