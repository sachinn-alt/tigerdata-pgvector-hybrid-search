"""
Tiger Cloud: AI-Powered Vector Search with pgvector & pgvectorscale
===================================================================
Demonstrates hybrid vector similarity search and temporal filtering
directly inside Tiger Cloud PostgreSQL.
"""

import math
import random
import datetime
import argparse

# Default Tiger Cloud Service Connection URI
DEFAULT_DB_URI = "postgresql://tsdbadmin@kiwbq9oup6.fflhx4ep14.tsdb.cloud.timescale.com:37201/tsdb?sslmode=require"

def generate_embedding(text: str, dim: int = 384) -> list:
    """Generates a deterministic 384-dimensional unit vector representing semantic text."""
    random.seed(text)
    raw = [random.gauss(0, 1) for _ in range(dim)]
    norm = math.sqrt(sum(x * x for x in raw))
    return [round(x / norm, 6) for x in raw]

def format_vector(vec: list) -> str:
    return "[" + ",".join(str(x) for x in vec) + "]"

def build_hybrid_query(search_query: str, days_window: int = 7, service_filter: str = None):
    query_vec = format_vector(generate_embedding(search_query))
    where_clauses = [f"created_at >= NOW() - INTERVAL '{days_window} days'"]
    if service_filter:
        where_clauses.append(f"service = '{service_filter}'")

    where_str = " AND ".join(where_clauses)

    sql = f"""
    SELECT 
        id, 
        created_at, 
        service, 
        severity, 
        summary, 
        ROUND((1 - (embedding <=> '{query_vec}'::vector))::numeric, 4) AS cosine_similarity
    FROM system_incident_embeddings
    WHERE {where_str}
    ORDER BY embedding <=> '{query_vec}'::vector ASC
    LIMIT 5;
    """
    return sql

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Hybrid Vector Search in Tiger Cloud")
    parser.add_argument("--query", default="payment gateway failure", help="Semantic search prompt")
    parser.add_argument("--days", type=int, default=7, help="Time window filter in days")
    parser.add_argument("--service", default="payment-api", help="Optional service filter")

    args = parser.parse_args()
    sql = build_hybrid_query(args.query, args.days, args.service)
    print("--- Generated Hybrid Vector Query ---")
    print(sql)
