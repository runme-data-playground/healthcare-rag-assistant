"""
Vector retrieval from Bedrock Knowledge Base with optional metadata filtering.
"""

import logging
from typing import Optional

logger = logging.getLogger(__name__)


def retrieve_context(
    bedrock_agent_runtime,
    knowledge_base_id: str,
    query: str,
    max_results: int = 8,
    doc_scope: Optional[str] = None,
) -> list[dict]:
    """
    Retrieve top-k semantically relevant chunks from the Knowledge Base.

    Args:
        bedrock_agent_runtime: Boto3 Bedrock agent runtime client.
        knowledge_base_id:     Bedrock Knowledge Base ID.
        query:                 User's clinical query string.
        max_results:           Number of chunks to retrieve (1–20).
        doc_scope:             S3 prefix/document_type filter (None = all docs).

    Returns:
        List of chunk dicts with keys: text, score, source, page, document_type.
    """
    retrieval_config = {
        "vectorSearchConfiguration": {
            "numberOfResults":  max_results,
            "overrideSearchType": "HYBRID",
        }
    }

    if doc_scope:
        retrieval_config["vectorSearchConfiguration"]["filter"] = {
            "equals": {
                "key":   "document_type",
                "value": doc_scope,
            }
        }

    try:
        response = bedrock_agent_runtime.retrieve(
            knowledgeBaseId=knowledge_base_id,
            retrievalQuery={"text": query},
            retrievalConfiguration=retrieval_config,
        )
    except Exception as exc:
        logger.error(f"Knowledge Base retrieval failed: {exc}", exc_info=True)
        raise

    chunks = []
    for result in response.get("retrievalResults", []):
        content  = result.get("content", {})
        location = result.get("location", {}).get("s3Location", {})
        metadata = result.get("metadata", {})
        score    = result.get("score", 0.0)

        chunks.append({
            "text":          content.get("text", ""),
            "score":         round(score, 4),
            "source":        location.get("uri", "unknown"),
            "page":          metadata.get("page_number", "N/A"),
            "document_type": metadata.get("document_type", "general"),
            "section":       metadata.get("section_heading", ""),
        })

    chunks.sort(key=lambda c: c["score"], reverse=True)
    logger.info(f"Retrieved {len(chunks)} chunks (scope={doc_scope})")
    return chunks
