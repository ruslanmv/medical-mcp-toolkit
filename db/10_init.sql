-- =============================================================================
-- medical-ai-hospital: PostgreSQL Database Schema (PRODUCTION)
-- File: db/10_init.sql
--
-- Fixes:
--  - Replaces invalid UNIQUE table constraint on drug_interactions using
--    expressions (LEAST/GREATEST) with a proper UNIQUE EXPRESSION INDEX.
--  - Ensures schema and search_path are explicit.
-- =============================================================================

BEGIN;

-- Ensure schema exists and set search_path
CREATE SCHEMA IF NOT EXISTS public;
SET search_path TO public;

-- -----------------------------------------------------------------------------
-- Extensions
-- -----------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "pgcrypto";  -- gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS "citext";    -- case-insensitive text (emails/usernames)

-- -----------------------------------------------------------------------------
-- ENUM types (idempotent creation)
-- -----------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'sex') THEN
    CREATE TYPE sex AS ENUM ('male','female','intersex','other','unknown');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'acuity_level') THEN
    CREATE TYPE acuity_level AS ENUM ('EMERGENT','URGENT','ROUTINE');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'risk_level') THEN
    CREATE TYPE risk_level AS ENUM ('LOW','MODERATE','HIGH','CRITICAL');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'interaction_severity') THEN
    CREATE TYPE interaction_severity AS ENUM ('minor','moderate','major','contraindicated');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'pregnancy_category') THEN
    CREATE TYPE pregnancy_category AS ENUM ('A','B','C','D','X','Unknown');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'allergy_severity') THEN
    CREATE TYPE allergy_severity AS ENUM ('mild','moderate','severe');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'appointment_status') THEN
    CREATE TYPE appointment_status AS ENUM ('scheduled', 'completed', 'cancelled', 'no-show');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'patient_user_role') THEN
    CREATE TYPE patient_user_role AS ENUM ('OWNER','CAREGIVER','PROXY');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'encounter_type') THEN
    CREATE TYPE encounter_type AS ENUM ('in_person','telemed','chat');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'encounter_status') THEN
    CREATE TYPE encounter_status AS ENUM ('open','closed','cancelled');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'note_kind') THEN
    CREATE TYPE note_kind AS ENUM ('ai_summary','provider_note','patient_note','system');
  END IF;
END $$;

-- -----------------------------------------------------------------------------
-- Utility: automatic updated_at
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END $$;

-- =============================================================================
-- AUTH & WEBSITE MANAGEMENT
-- =============================================================================

-- Roles (flexible text PK so we can seed codes like 'admin','patient','clinician','staff')
CREATE TABLE IF NOT EXISTS roles (
  code        TEXT PRIMARY KEY,
  description TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Users (website accounts)
CREATE TABLE IF NOT EXISTS users (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email              CITEXT NOT NULL UNIQUE,
  password_hash      TEXT   NOT NULL,  -- store PHC string (e.g., argon2id)
  password_algo      TEXT   NOT NULL DEFAULT 'argon2id',
  is_active          BOOLEAN NOT NULL DEFAULT TRUE,
  is_verified        BOOLEAN NOT NULL DEFAULT FALSE,
  display_name       TEXT,
  phone              TEXT,
  mfa_enabled        BOOLEAN NOT NULL DEFAULT FALSE,
  mfa_secret         TEXT,             -- if using TOTP; store encrypted
  last_login_at      TIMESTAMPTZ,
  last_login_ip      INET,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS users_is_active_idx   ON users (is_active);
CREATE INDEX IF NOT EXISTS users_created_at_idx  ON users (created_at DESC);

DROP TRIGGER IF EXISTS trg_users_updated_at ON users;
CREATE TRIGGER trg_users_updated_at
BEFORE UPDATE ON users
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- User ↔ Roles (many-to-many)
CREATE TABLE IF NOT EXISTS user_roles (
  user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role_code  TEXT NOT NULL REFERENCES roles(code) ON DELETE RESTRICT,
  granted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, role_code)
);

-- User settings/preferences (per-user JSON)
CREATE TABLE IF NOT EXISTS user_settings (
  user_id     UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  preferences JSONB NOT NULL DEFAULT '{}',
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
DROP TRIGGER IF EXISTS trg_user_settings_updated_at ON user_settings;
CREATE TRIGGER trg_user_settings_updated_at
BEFORE UPDATE ON user_settings
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Auth sessions (token stored hashed)
CREATE TABLE IF NOT EXISTS auth_sessions (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id            UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  session_token_hash TEXT NOT NULL UNIQUE, -- store hash only
  ip_address         INET,
  user_agent         TEXT,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at         TIMESTAMPTZ NOT NULL,
  revoked_at         TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS auth_sessions_user_idx
  ON auth_sessions (user_id, expires_at DESC);
CREATE INDEX IF NOT EXISTS auth_sessions_active_idx
  ON auth_sessions (expires_at)
  WHERE revoked_at IS NULL;

-- Password reset tokens (hash only)
CREATE TABLE IF NOT EXISTS password_resets (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash     TEXT NOT NULL UNIQUE, -- store hash only
  requested_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at     TIMESTAMPTZ NOT NULL,
  used_at        TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS password_resets_user_idx
  ON password_resets (user_id, expires_at DESC);

-- =============================================================================
-- PATIENTS & CLINICAL DATA
-- =============================================================================

-- Patients (PII + identifiers)
CREATE TABLE IF NOT EXISTS patients (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  -- Primary identifiers
  external_key     TEXT UNIQUE,               -- e.g., "demo-001" or upstream ID
  mrn              TEXT UNIQUE,               -- Medical Record Number (hospital scope)
  national_id      TEXT,                      -- e.g., SSN/NI/curp (if applicable)

  -- Personal information
  first_name       TEXT NOT NULL,
  middle_name      TEXT,
  last_name        TEXT NOT NULL,
  suffix           TEXT,
  date_of_birth    DATE NOT NULL,
  sex              sex NOT NULL DEFAULT 'unknown',

  -- Contact
  email            CITEXT,                    -- optional (may differ from account email)
  phone            TEXT,

  -- Address
  address_line1    TEXT,
  address_line2    TEXT,
  city             TEXT,
  state            TEXT,
  postal_code      TEXT,
  country_code     CHAR(2),

  -- Clinical flags
  pregnant         BOOLEAN NOT NULL DEFAULT FALSE,
  breastfeeding    BOOLEAN NOT NULL DEFAULT FALSE,
  insurance_id     TEXT,

  -- Optional structured metadata
  risk_flags       TEXT[] NOT NULL DEFAULT '{}',
  meta             JSONB  NOT NULL DEFAULT '{}',

  -- Audit
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS patients_last_name_idx ON patients (last_name);
CREATE INDEX IF NOT EXISTS patients_dob_idx       ON patients (date_of_birth);
CREATE INDEX IF NOT EXISTS patients_email_idx     ON patients (email) WHERE email IS NOT NULL;
CREATE INDEX IF NOT EXISTS patients_insurance_idx ON patients (insurance_id) WHERE insurance_id IS NOT NULL;

DROP TRIGGER IF EXISTS trg_patients_updated_at ON patients;
CREATE TRIGGER trg_patients_updated_at
BEFORE UPDATE ON patients
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Relationship: Users ↔ Patients (owner/caregiver/proxy)
CREATE TABLE IF NOT EXISTS patient_users (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id  UUID NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
  user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role        patient_user_role NOT NULL DEFAULT 'OWNER',
  linked_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (patient_id, user_id)
);
CREATE INDEX IF NOT EXISTS patient_users_role_idx ON patient_users (role);

-- Vitals (high-volume table)
CREATE TABLE IF NOT EXISTS vitals (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id           UUID NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
  timestamp_utc        TIMESTAMPTZ NOT NULL,
  systolic_mmhg        INT,
  diastolic_mmhg       INT,
  heart_rate_bpm       INT,
  resp_rate_min        INT,
  temperature_c        NUMERIC(4,1),
  spo2_percent         NUMERIC(5,2),
  weight_kg            NUMERIC(6,2),
  height_cm            NUMERIC(6,2),
  bmi                  NUMERIC(6,2),
  serum_creatinine     NUMERIC(6,3),
  egfr_ml_min_1_73m2   NUMERIC(6,2),
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS vitals_patient_time_idx ON vitals (patient_id, timestamp_utc DESC);

DROP TRIGGER IF EXISTS trg_vitals_updated_at ON vitals;
CREATE TRIGGER trg_vitals_updated_at
BEFORE UPDATE ON vitals
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Conditions
CREATE TABLE IF NOT EXISTS conditions (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id    UUID NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
  name          TEXT NOT NULL,
  code          TEXT,
  code_system   TEXT,
  onset_date    DATE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS conditions_patient_idx ON conditions (patient_id);

DROP TRIGGER IF EXISTS trg_conditions_updated_at ON conditions;
CREATE TRIGGER trg_conditions_updated_at
BEFORE UPDATE ON conditions
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Allergies
CREATE TABLE IF NOT EXISTS allergies (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id    UUID NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
  substance     TEXT NOT NULL,
  reaction      TEXT,
  severity      allergy_severity,
  note          TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS allergies_patient_idx ON allergies (patient_id);

DROP TRIGGER IF EXISTS trg_allergies_updated_at ON allergies;
CREATE TRIGGER trg_allergies_updated_at
BEFORE UPDATE ON allergies
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Medications
CREATE TABLE IF NOT EXISTS medications (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id    UUID NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
  drug_name     TEXT NOT NULL,
  dose          TEXT,
  route         TEXT,
  frequency     TEXT,
  start_date    DATE,
  end_date      DATE,
  prn           BOOLEAN,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS medications_patient_idx ON medications (patient_id);

DROP TRIGGER IF EXISTS trg_medications_updated_at ON medications;
CREATE TRIGGER trg_medications_updated_at
BEFORE UPDATE ON medications
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Drug Monographs (arrays for compact storage)
-- NOTE: renamed 'references' -> 'reference_urls' to avoid reserved keyword clash
CREATE TABLE IF NOT EXISTS drugs (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  drug_name               TEXT UNIQUE NOT NULL,
  drug_class              TEXT,
  mechanism               TEXT,
  pregnancy_category      pregnancy_category,
  lactation               TEXT,
  renal_adjustment        TEXT,
  hepatic_adjustment      TEXT,
  indications             TEXT[] NOT NULL DEFAULT '{}',
  contraindications       TEXT[] NOT NULL DEFAULT '{}',
  warnings                TEXT[] NOT NULL DEFAULT '{}',
  common_adverse_effects  TEXT[] NOT NULL DEFAULT '{}',
  serious_adverse_effects TEXT[] NOT NULL DEFAULT '{}',
  brand_names             TEXT[] NOT NULL DEFAULT '{}',
  atc_codes               TEXT[] NOT NULL DEFAULT '{}',
  reference_urls          TEXT[] NOT NULL DEFAULT '{}',
  created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);
DROP TRIGGER IF EXISTS trg_drugs_updated_at ON drugs;
CREATE TRIGGER trg_drugs_updated_at
BEFORE UPDATE ON drugs
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Drug Interactions (pairwise unique index with LEAST/GREATEST)
CREATE TABLE IF NOT EXISTS drug_interactions (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  primary_drug_id     UUID NOT NULL REFERENCES drugs(id) ON DELETE CASCADE,
  interacting_drug_id UUID NOT NULL REFERENCES drugs(id) ON DELETE CASCADE,
  severity            interaction_severity NOT NULL,
  mechanism           TEXT,
  clinical_effect     TEXT,
  management          TEXT,
  reference_urls      TEXT[] NOT NULL DEFAULT '{}',
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ✅ Correct, idempotent UNIQUE EXPRESSION INDEX (not a table constraint)
CREATE UNIQUE INDEX IF NOT EXISTS ux_drug_interactions_pair
  ON drug_interactions (
    LEAST(primary_drug_id, interacting_drug_id),
    GREATEST(primary_drug_id, interacting_drug_id)
  );

DROP TRIGGER IF EXISTS trg_drug_interactions_updated_at ON drug_interactions;
CREATE TRIGGER trg_drug_interactions_updated_at
BEFORE UPDATE ON drug_interactions
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Appointments
CREATE TABLE IF NOT EXISTS appointments (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id       UUID NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
  scheduled_start  TIMESTAMPTZ NOT NULL,
  scheduled_end    TIMESTAMPTZ NOT NULL,
  specialty        TEXT NOT NULL,
  provider         TEXT,
  location         TEXT,
  status           appointment_status NOT NULL DEFAULT 'scheduled',
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_appt_time CHECK (scheduled_end >= scheduled_start)
);
CREATE INDEX IF NOT EXISTS appt_patient_time_idx ON appointments (patient_id, scheduled_start DESC);

DROP TRIGGER IF EXISTS trg_appointments_updated_at ON appointments;
CREATE TRIGGER trg_appointments_updated_at
BEFORE UPDATE ON appointments
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Longitudinal Encounters (clinical consults/visits)
CREATE TABLE IF NOT EXISTS encounters (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id       UUID NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
  encounter_type   encounter_type NOT NULL DEFAULT 'chat',
  status           encounter_status NOT NULL DEFAULT 'open',
  started_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  ended_at         TIMESTAMPTZ,
  chief_complaint  TEXT,
  provisional_dx   TEXT,
  final_dx         TEXT,
  disposition      TEXT,
  created_by_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_encounter_time CHECK (ended_at IS NULL OR ended_at >= started_at)
);
CREATE INDEX IF NOT EXISTS encounters_patient_time_idx ON encounters (patient_id, started_at DESC);

DROP TRIGGER IF EXISTS trg_encounters_updated_at ON encounters;
CREATE TRIGGER trg_encounters_updated_at
BEFORE UPDATE ON encounters
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Encounter Notes (AI/provider/patient notes + structured data)
CREATE TABLE IF NOT EXISTS encounter_notes (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  encounter_id     UUID NOT NULL REFERENCES encounters(id) ON DELETE CASCADE,
  author_user_id   UUID REFERENCES users(id) ON DELETE SET NULL,
  kind             note_kind NOT NULL DEFAULT 'provider_note',
  content          TEXT,     -- unstructured note content
  data             JSONB NOT NULL DEFAULT '{}',  -- structured payload (e.g., AI results)
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS encounter_notes_enc_idx ON encounter_notes (encounter_id, created_at DESC);

DROP TRIGGER IF EXISTS trg_encounter_notes_updated_at ON encounter_notes;
CREATE TRIGGER trg_encounter_notes_updated_at
BEFORE UPDATE ON encounter_notes
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Patient Documents (metadata; actual bytes in object storage)
CREATE TABLE IF NOT EXISTS documents (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id          UUID NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
  encounter_id        UUID REFERENCES encounters(id) ON DELETE SET NULL,
  file_name           TEXT NOT NULL,
  content_type        TEXT,
  storage_url         TEXT NOT NULL,      -- e.g., s3://... or https://...
  size_bytes          BIGINT,
  sha256_hex          TEXT,               -- integrity check (optional)
  uploaded_by_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS documents_patient_time_idx ON documents (patient_id, created_at DESC);
CREATE INDEX IF NOT EXISTS documents_encounter_idx    ON documents (encounter_id);

-- Tool Audit (for MCP calls)
CREATE TABLE IF NOT EXISTS tool_audit (
  id            BIGSERIAL PRIMARY KEY,
  occurred_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  tool_name     TEXT NOT NULL,
  request_json  JSONB NOT NULL,
  response_json JSONB
);
CREATE INDEX IF NOT EXISTS tool_audit_tool_idx ON tool_audit (tool_name, occurred_at DESC);

-- =============================================================================
-- Views
-- =============================================================================

-- Latest vitals per patient
CREATE OR REPLACE VIEW v_latest_vitals AS
SELECT DISTINCT ON (v.patient_id)
  v.*
FROM vitals v
ORDER BY v.patient_id, v.timestamp_utc DESC;

-- Patient profile: PII + clinical snapshot
CREATE OR REPLACE VIEW v_patient_profile AS
SELECT
  p.id AS patient_id,
  p.external_key,
  p.mrn,
  p.national_id,
  p.first_name,
  p.middle_name,
  p.last_name,
  p.suffix,
  p.date_of_birth,
  p.sex,
  p.email,
  p.phone,
  p.address_line1,
  p.address_line2,
  p.city,
  p.state,
  p.postal_code,
  p.country_code,
  p.pregnant,
  p.breastfeeding,
  p.insurance_id,
  p.risk_flags,
  (SELECT jsonb_agg(jsonb_build_object('name', c.name, 'code', c.code, 'code_system', c.code_system, 'onset_date', c.onset_date))
     FROM conditions c WHERE c.patient_id = p.id) AS conditions,
  (SELECT jsonb_agg(jsonb_build_object('substance', a.substance, 'reaction', a.reaction, 'severity', a.severity, 'note', a.note))
     FROM allergies a WHERE a.patient_id = p.id) AS allergies,
  (SELECT jsonb_agg(jsonb_build_object('drug_name', m.drug_name, 'dose', m.dose, 'route', m.route, 'frequency', m.frequency, 'start_date', m.start_date, 'end_date', m.end_date, 'prn', m.prn))
     FROM medications m WHERE m.patient_id = p.id) AS medications,
  (SELECT row_to_json(v) FROM v_latest_vitals v WHERE v.patient_id = p.id) AS latest_vitals,
  p.meta,
  p.created_at,
  p.updated_at
FROM patients p;

COMMIT;
