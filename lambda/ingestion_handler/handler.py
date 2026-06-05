"""
Healthcare RAG Assistant — Ingestion Handler Lambda
Triggers Bedrock Knowledge Base sync when new documents arrive in S3
or on a scheduled EventBridge rule.
"""

import json
import logging
import os
from typing import Any

import boto3

logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

bedrock_agent = boto3.client("bedrock-agent")

KNOWLEDGE_BASE_ID = os.environ["KNOWLEDGE_BASE_ID"]


def lambda_handler(event: dict, context: Any) -> dict:
    """
    Entry point — handles both EventBridge scheduled triggers
    and S3 event notifications via EventBridge.
    """
    logger.info(json.dumps({"event": "ingestion_triggered", "source": event.get("source")}))

    knowledge_base_id = event.get("knowledge_base_id", KNOWLEDGE_BASE_ID)
    data_source_id    = event.get("data_source_id")

    if not data_source_id:
        data_source_id = _get_data_source_id(knowledge_base_id)

    if not data_source_id:
        logger.error("No data source ID found for knowledge base.")
        return {"status": "error", "message": "data_source_id not found"}

    try:
        response = bedrock_agent.start_ingestion_job(
            knowledgeBaseId=knowledge_base_id,
            dataSourceId=data_source_id,
        )

        job_id  = response["ingestionJob"]["ingestionJobId"]
        status  = response["ingestionJob"]["status"]

        logger.info(json.dumps({
            "event":              "ingestion_job_started",
            "ingestion_job_id":   job_id,
            "status":             status,
            "knowledge_base_id":  knowledge_base_id,
            "data_source_id":     data_source_id,
        }))

        return {
            "status":           "started",
            "ingestion_job_id": job_id,
            "knowledge_base_id": knowledge_base_id,
        }

    except bedrock_agent.exceptions.ConflictException:
        logger.warning("Ingestion job already in progress — skipping.")
        return {"status": "skipped", "reason": "job already running"}

    except Exception as exc:
        logger.error(f"Failed to start ingestion job: {exc}", exc_info=True)
        raise


def _get_data_source_id(knowledge_base_id: str) -> str | None:
    try:
        response = bedrock_agent.list_data_sources(knowledgeBaseId=knowledge_base_id)
        sources  = response.get("dataSourceSummaries", [])
        return sources[0]["dataSourceId"] if sources else None
    except Exception as exc:
        logger.error(f"Failed to list data sources: {exc}", exc_info=True)
        return None
