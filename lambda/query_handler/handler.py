"""
Healthcare RAG Assistant — Query Handler Lambda
Orchestrates retrieval from Bedrock Knowledge Base and generation via Claude.
"""

import json
import logging
import os
import hashlib
from typing import Any

import boto3
from retrieval import retrieve_context
from prompt_builder import build_clinical_prompt
from response_parser import parse_and_enrich_response

logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

bedrock_agent_runtime = boto3.client("bedrock-agent-runtime")
bedrock_runtime = boto3.client("bedrock-runtime")
xray = boto3.client("xray")

KNOWLEDGE_BASE_ID = os.environ["KNOWLEDGE_BASE_ID"]
BEDROCK_MODEL_ID  = os.environ["BEDROCK_MODEL_ID"]
GUARDRAIL_ID      = os.environ.get("GUARDRAIL_ID", "")
ENVIRONMENT       = os.environ.get("ENVIRONMENT", "dev")

ROLE_DOCUMENT_SCOPE = {
    "Physicians":   None,                    # full access
    "Pharmacists":  "drug-formulary",
    "Nurses":       "protocols",
    "Admins":       "compliance",
}


def lambda_handler(event: dict, context: Any) -> dict:
    try:
        body        = json.loads(event.get("body", "{}"))
        query       = body.get("query", "").strip()
        max_results = min(int(body.get("max_results", 8)), 20)

        if not query or len(query) < 3:
            return _response(400, {"error": "Query must be at least 3 characters."})

        claims  = event.get("requestContext", {}).get("authorizer", {}).get("claims", {})
        groups  = claims.get("cognito:groups", "").split(",")
        user_id = claims.get("sub", "anonymous")

        primary_group = groups[0] if groups else "ReadOnly"
        doc_scope     = ROLE_DOCUMENT_SCOPE.get(primary_group)

        query_hash = hashlib.sha256(query.encode()).hexdigest()[:16]
        logger.info(json.dumps({
            "event":       "query_received",
            "query_hash":  query_hash,
            "group":       primary_group,
            "doc_scope":   doc_scope,
            "environment": ENVIRONMENT,
        }))

        chunks = retrieve_context(
            bedrock_agent_runtime=bedrock_agent_runtime,
            knowledge_base_id=KNOWLEDGE_BASE_ID,
            query=query,
            max_results=max_results,
            doc_scope=doc_scope,
        )

        if not chunks:
            return _response(200, {
                "answer":      "No relevant clinical documents were found for your query.",
                "sources":     [],
                "confidence":  "low",
                "request_id":  context.aws_request_id,
            })

        prompt = build_clinical_prompt(query=query, chunks=chunks, user_role=primary_group)

        model_response = _invoke_bedrock(prompt)

        result = parse_and_enrich_response(
            raw_response=model_response,
            chunks=chunks,
            request_id=context.aws_request_id,
        )

        logger.info(json.dumps({
            "event":       "query_completed",
            "query_hash":  query_hash,
            "chunks_used": len(chunks),
            "confidence":  result.get("confidence"),
        }))

        return _response(200, result)

    except Exception as exc:
        logger.error(f"Unhandled error: {exc}", exc_info=True)
        return _response(500, {"error": "An internal error occurred. Please try again."})


def _invoke_bedrock(prompt: str) -> str:
    request_body = {
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens":        2048,
        "temperature":       0.1,
        "messages": [{"role": "user", "content": prompt}],
    }

    kwargs = {
        "modelId":     BEDROCK_MODEL_ID,
        "contentType": "application/json",
        "accept":      "application/json",
        "body":        json.dumps(request_body),
    }

    if GUARDRAIL_ID:
        kwargs["guardrailIdentifier"] = GUARDRAIL_ID
        kwargs["guardrailVersion"]    = "DRAFT"

    resp = bedrock_runtime.invoke_model(**kwargs)
    body = json.loads(resp["body"].read())
    return body["content"][0]["text"]


def _response(status_code: int, body: dict) -> dict:
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type":                "application/json",
            "X-Content-Type-Options":      "nosniff",
            "Strict-Transport-Security":   "max-age=31536000; includeSubDomains",
            "Cache-Control":               "no-store",
        },
        "body": json.dumps(body),
    }
