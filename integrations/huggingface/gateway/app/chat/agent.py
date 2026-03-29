# gateway/app/chat/agent.py — LangGraph medical agent with HuggingFace LLM
from __future__ import annotations

import json
import logging
from typing import Any, Dict, List, Optional, TypedDict

from langgraph.graph import StateGraph, END

from ..config import settings
from ..medical_tools.tools import TOOL_REGISTRY, triage_symptoms

log = logging.getLogger("gateway.agent")

_hf_client = None


def _get_hf_client():
    global _hf_client
    if _hf_client is None:
        from huggingface_hub import InferenceClient
        _hf_client = InferenceClient(token=settings.hf_token or None)
    return _hf_client


class AgentState(TypedDict):
    user_message: str
    args: Dict[str, Any]
    intent: str
    tool_name: str
    tool_result: Optional[Dict[str, Any]]
    llm_response: str
    final_response: Dict[str, Any]


MEDICAL_SYSTEM_PROMPT = """You are a medical AI assistant at a hospital portal. You help patients with:
- Symptom triage and initial assessment
- Drug information and interaction checks
- General health questions and guidance

You are professional, empathetic, and always remind patients to consult healthcare professionals.
Based on the tool results provided, give a clear, helpful response to the patient.
IMPORTANT: Always include a disclaimer that this is AI-assisted and not a substitute for professional medical advice."""


def classify_intent(state: AgentState) -> AgentState:
    msg = (state.get("user_message") or "").lower()
    args = state.get("args") or {}
    if args.get("symptoms") or args.get("age") or args.get("sex"):
        state["intent"], state["tool_name"] = "triage", "triageSymptoms"
        return state
    if any(kw in msg for kw in ["symptom", "pain", "ache", "fever", "cough", "breath", "dizzy", "nausea", "triage", "emergency", "urgent", "chest"]):
        state["intent"], state["tool_name"] = "triage", "triageSymptoms"
    elif any(kw in msg for kw in ["drug", "medication", "medicine", "pill", "dose"]):
        if any(kw in msg for kw in ["interact", "combination", "together"]):
            state["intent"], state["tool_name"] = "drug_interaction", "getDrugInteractions"
        elif any(kw in msg for kw in ["alternative", "substitute"]):
            state["intent"], state["tool_name"] = "drug_alternatives", "getDrugAlternatives"
        else:
            state["intent"], state["tool_name"] = "drug_info", "getDrugInfo"
    elif any(kw in msg for kw in ["bmi", "weight", "height", "calculate", "creatinine"]):
        state["intent"], state["tool_name"] = "clinical_calc", "calcClinicalScores"
    elif any(kw in msg for kw in ["appointment", "schedule", "book"]):
        state["intent"], state["tool_name"] = "scheduling", "scheduleAppointment"
    else:
        state["intent"], state["tool_name"] = "general", "searchMedicalKB"
    return state


KNOWN_DRUGS = ["ibuprofen", "warfarin", "lisinopril", "aspirin", "acetaminophen", "losartan", "amlodipine"]


def _extract_drug_name(text: str) -> Optional[str]:
    for drug in KNOWN_DRUGS:
        if drug in text.lower():
            return drug
    return None


def execute_tool(state: AgentState) -> AgentState:
    tool_name = state.get("tool_name", "triageSymptoms")
    msg = state.get("user_message", "")
    args = state.get("args") or {}
    try:
        tool_fn = TOOL_REGISTRY.get(tool_name)
        if not tool_fn:
            state["tool_result"] = {"error": f"Unknown tool: {tool_name}"}
            return state
        if tool_name == "triageSymptoms":
            state["tool_result"] = tool_fn(age=args.get("age", 0), sex=args.get("sex", "unknown"), symptoms=args.get("symptoms", []), query=msg)
        elif tool_name == "getDrugInfo":
            state["tool_result"] = tool_fn(_extract_drug_name(msg) or args.get("name", msg))
        elif tool_name == "getDrugInteractions":
            found = [d for d in KNOWN_DRUGS if d in msg.lower()]
            state["tool_result"] = tool_fn(found if found else [msg])
        elif tool_name == "getDrugAlternatives":
            state["tool_result"] = tool_fn(_extract_drug_name(msg) or msg)
        elif tool_name == "searchMedicalKB":
            state["tool_result"] = tool_fn(query=msg)
        else:
            state["tool_result"] = tool_fn(**args) if args else tool_fn()
    except Exception as e:
        log.exception("Tool execution failed: %s", tool_name)
        state["tool_result"] = {"error": str(e)}
    return state


def generate_response(state: AgentState) -> AgentState:
    tool_result = state.get("tool_result", {})
    user_message = state.get("user_message", "")
    try:
        client = _get_hf_client()
        prompt = f"Tool results: {json.dumps(tool_result, default=str)}\n\nPatient's message: {user_message}\n\nProvide a clear, empathetic response."
        response = client.chat_completion(
            model=settings.hf_model_id,
            messages=[{"role": "system", "content": MEDICAL_SYSTEM_PROMPT}, {"role": "user", "content": prompt}],
            max_tokens=512, temperature=0.3,
        )
        state["llm_response"] = response.choices[0].message.content
    except Exception as e:
        log.warning("LLM call failed: %s", e)
        state["llm_response"] = json.dumps(tool_result, indent=2, default=str)
    state["final_response"] = {"ok": True, "tool": state.get("tool_name", ""), "result": tool_result, "message": state.get("llm_response", ""), "intent": state.get("intent", "general")}
    return state


def _build_graph():
    graph = StateGraph(AgentState)
    graph.add_node("classify", classify_intent)
    graph.add_node("execute_tool", execute_tool)
    graph.add_node("generate_response", generate_response)
    graph.set_entry_point("classify")
    graph.add_edge("classify", "execute_tool")
    graph.add_edge("execute_tool", "generate_response")
    graph.add_edge("generate_response", END)
    return graph.compile()


_agent = None


def get_agent():
    global _agent
    if _agent is None:
        _agent = _build_graph()
    return _agent


async def run_agent(message: str, args: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    agent = get_agent()
    initial_state: AgentState = {
        "user_message": message or "", "args": args or {},
        "intent": "", "tool_name": "", "tool_result": None,
        "llm_response": "", "final_response": {},
    }
    result = await agent.ainvoke(initial_state)
    return result.get("final_response", {"ok": False, "error": "Agent failed"})
