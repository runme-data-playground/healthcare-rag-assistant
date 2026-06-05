"""
Clinical prompt construction for Bedrock generation.
Assembles retrieved chunks into a structured, safety-conscious prompt.
"""

SYSTEM_PROMPT = """You are a clinical decision support assistant for healthcare professionals.

RULES:
1. Answer ONLY using the provided context documents. Do not use outside knowledge.
2. If the answer is not present in the context, explicitly state: "This information is not available in the current knowledge base."
3. Never fabricate drug doses, lab values, diagnostic criteria, or clinical guidelines.
4. Always include the source document reference for every claim you make.
5. If the query involves a specific patient, remind the user that this tool provides general clinical reference information, not individualized medical advice.
6. Format responses clearly with sections where appropriate.
7. Flag any information that appears outdated or potentially superseded.

You are supporting trained clinicians — use appropriate medical terminology."""


def build_clinical_prompt(query: str, chunks: list[dict], user_role: str) -> str:
    """
    Build the full prompt for Bedrock Claude generation.

    Args:
        query:     The user's clinical question.
        chunks:    Retrieved document chunks from OpenSearch.
        user_role: User's Cognito group (for role-appropriate framing).

    Returns:
        Formatted prompt string ready for Bedrock invocation.
    """
    context_blocks = _format_context_blocks(chunks)
    role_note      = _role_note(user_role)

    prompt = f"""{SYSTEM_PROMPT}

{role_note}

---
REFERENCE DOCUMENTS ({len(chunks)} retrieved):

{context_blocks}
---

CLINICAL QUERY: {query}

Please provide a clear, evidence-based response citing the relevant source documents above."""

    return prompt


def _format_context_blocks(chunks: list[dict]) -> str:
    blocks = []
    for i, chunk in enumerate(chunks, 1):
        source   = chunk.get("source", "unknown").split("/")[-1]
        page     = chunk.get("page", "N/A")
        section  = chunk.get("section", "")
        score    = chunk.get("score", 0.0)
        text     = chunk.get("text", "").strip()

        header = f"[Document {i}] {source}"
        if section:
            header += f" — {section}"
        header += f" (page {page}, relevance: {score:.2f})"

        blocks.append(f"{header}\n{text}")

    return "\n\n".join(blocks)


def _role_note(user_role: str) -> str:
    notes = {
        "Physicians":  "User role: Physician — full clinical knowledge base access.",
        "Pharmacists": "User role: Pharmacist — drug formulary and medication reference scope.",
        "Nurses":      "User role: Nurse — clinical protocols and care pathway scope.",
        "Admins":      "User role: Administrator — compliance and policy document scope.",
    }
    return notes.get(user_role, "User role: Clinical staff.")
