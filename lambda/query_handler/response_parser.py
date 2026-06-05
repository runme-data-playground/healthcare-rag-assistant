"""
Post-processing for Bedrock generation responses.
Enriches raw LLM output with structured citations and confidence scoring.
"""

import re
import logging

logger = logging.getLogger(__name__)

LOW_CONFIDENCE_PHRASES = [
    "not available in the current knowledge base",
    "no relevant information",
    "cannot find",
    "not present in the context",
    "unable to locate",
]


def parse_and_enrich_response(
    raw_response: str,
    chunks: list[dict],
    request_id: str,
) -> dict:
    """
    Parse raw LLM output and attach structured source citations.

    Args:
        raw_response: Raw text from Bedrock Claude.
        chunks:       Retrieved document chunks used to build the prompt.
        request_id:   Lambda request ID for audit correlation.

    Returns:
        Structured response dict with answer, sources, confidence, request_id.
    """
    answer     = raw_response.strip()
    confidence = _assess_confidence(answer, chunks)
    sources    = _extract_sources(chunks)

    return {
        "answer":     answer,
        "sources":    sources,
        "confidence": confidence,
        "request_id": request_id,
        "disclaimer": (
            "This response is generated from institutional reference documents and is intended "
            "to support — not replace — clinical judgment. Always verify against primary sources."
        ),
    }


def _assess_confidence(answer: str, chunks: list[dict]) -> str:
    answer_lower = answer.lower()

    if any(phrase in answer_lower for phrase in LOW_CONFIDENCE_PHRASES):
        return "low"

    if not chunks:
        return "low"

    top_score = chunks[0].get("score", 0.0) if chunks else 0.0

    if top_score >= 0.75 and len(chunks) >= 3:
        return "high"
    elif top_score >= 0.50:
        return "medium"
    else:
        return "low"


def _extract_sources(chunks: list[dict]) -> list[dict]:
    seen    = set()
    sources = []

    for chunk in chunks:
        raw_source = chunk.get("source", "")
        filename   = raw_source.split("/")[-1]

        if filename in seen:
            continue
        seen.add(filename)

        sources.append({
            "document":      filename,
            "s3_uri":        raw_source,
            "page":          chunk.get("page", "N/A"),
            "section":       chunk.get("section", ""),
            "document_type": chunk.get("document_type", "general"),
            "relevance":     chunk.get("score", 0.0),
        })

    return sources
