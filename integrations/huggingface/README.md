# Medical AI Hospital Portal — HuggingFace Spaces

This directory contains the complete HuggingFace Spaces deployment of the Medical AI Hospital Portal.

## Architecture

- **Frontend**: Next.js 14 React portal (from medical-ai-hospital)
- **Backend**: FastAPI gateway with LangGraph agent
- **AI**: HuggingFace Inference API (Mistral-7B-Instruct default)
- **Database**: SQLite (lightweight, no external services)
- **Infrastructure**: Docker + nginx + supervisord

## Key Changes from Original

| Component | Original | HF Version |
|-----------|----------|------------|
| AI Backend | WatsonX via MCP | LangGraph + HF Inference |
| Database | PostgreSQL | SQLite |
| Deployment | Docker Compose (4 services) | Single Docker container |
| LLM | IBM watsonx models | Mistral-7B-Instruct |

## Medical Tools (12 total)

All 12 tools from medical-mcp-toolkit ported as direct Python functions:

1. `getPatient` - Patient demographics
2. `getPatientVitals` - Vital signs
3. `getPatientMedicalProfile` - Conditions, allergies, medications
4. `calcClinicalScores` - BMI, BSA, CrCl, eGFR
5. `getDrugInfo` - Drug monographs
6. `getDrugInteractions` - Drug-drug interactions
7. `getDrugContraindications` - Patient-specific contraindications
8. `getDrugAlternatives` - Therapeutic alternatives
9. `triageSymptoms` - Acuity triage (rule-based)
10. `searchMedicalKB` - Knowledge base search
11. `scheduleAppointment` - Appointment booking
12. `getPatient360` - Unified patient view

## Deployment

The portal is deployed at: https://ruslanmv-medical-ai-hospital.hf.space

To deploy your own:
1. Create a Docker Space on HuggingFace
2. Set `HF_TOKEN` as a Space secret
3. Push this directory as the Space root
