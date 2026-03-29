-- SQLite schema for Medical AI Hospital (adapted from PostgreSQL)

CREATE TABLE IF NOT EXISTS users (
    id           TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
    email        TEXT NOT NULL UNIQUE COLLATE NOCASE,
    password_hash TEXT NOT NULL,
    password_algo TEXT NOT NULL DEFAULT 'argon2id',
    display_name TEXT,
    phone        TEXT,
    is_active    INTEGER NOT NULL DEFAULT 1,
    is_verified  INTEGER NOT NULL DEFAULT 0,
    created_at   TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at   TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS auth_sessions (
    id                 TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
    user_id            TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    session_token_hash TEXT NOT NULL UNIQUE,
    ip_address         TEXT,
    user_agent         TEXT,
    expires_at         TEXT,
    revoked_at         TEXT,
    created_at         TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_sessions_token ON auth_sessions(session_token_hash);
CREATE INDEX IF NOT EXISTS idx_sessions_user ON auth_sessions(user_id);

CREATE TABLE IF NOT EXISTS password_resets (
    id           TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
    user_id      TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash   TEXT NOT NULL UNIQUE,
    requested_at TEXT NOT NULL DEFAULT (datetime('now')),
    expires_at   TEXT NOT NULL,
    used_at      TEXT
);

CREATE TABLE IF NOT EXISTS patients (
    id             TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
    mrn            TEXT UNIQUE,
    first_name     TEXT NOT NULL,
    middle_name    TEXT,
    last_name      TEXT NOT NULL,
    suffix         TEXT,
    date_of_birth  TEXT NOT NULL,
    sex            TEXT DEFAULT 'unknown',
    email          TEXT,
    phone          TEXT,
    address_line1  TEXT,
    address_line2  TEXT,
    city           TEXT,
    state          TEXT,
    postal_code    TEXT,
    country_code   TEXT DEFAULT 'US',
    pregnant       INTEGER,
    breastfeeding  INTEGER,
    insurance_id   TEXT,
    risk_flags     TEXT,
    meta           TEXT,
    created_at     TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at     TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS patient_users (
    patient_id TEXT NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    user_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role       TEXT NOT NULL DEFAULT 'OWNER',
    linked_at  TEXT NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (patient_id, user_id)
);

CREATE TABLE IF NOT EXISTS vitals (
    id               TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
    patient_id       TEXT NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    timestamp        TEXT NOT NULL DEFAULT (datetime('now')),
    systolic_mmhg    INTEGER,
    diastolic_mmhg   INTEGER,
    heart_rate_bpm   INTEGER,
    resp_rate_min    INTEGER,
    temperature_c    REAL,
    spo2_percent     REAL,
    weight_kg        REAL,
    height_cm        REAL,
    bmi              REAL,
    egfr             REAL,
    created_at       TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_vitals_patient ON vitals(patient_id, timestamp);

CREATE TABLE IF NOT EXISTS conditions (
    id          TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
    patient_id  TEXT NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    name        TEXT NOT NULL,
    icd_code    TEXT,
    onset_date  TEXT,
    status      TEXT DEFAULT 'active',
    created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS allergies (
    id          TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
    patient_id  TEXT NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    substance   TEXT NOT NULL,
    reaction    TEXT,
    severity    TEXT DEFAULT 'mild',
    note        TEXT,
    created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS medications (
    id          TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
    patient_id  TEXT NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    drug_name   TEXT NOT NULL,
    dose        TEXT,
    route       TEXT,
    frequency   TEXT,
    start_date  TEXT,
    end_date    TEXT,
    is_prn      INTEGER DEFAULT 0,
    created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS encounters (
    id              TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
    patient_id      TEXT NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    encounter_type  TEXT DEFAULT 'chat',
    status          TEXT DEFAULT 'open',
    chief_complaint TEXT,
    started_at      TEXT NOT NULL DEFAULT (datetime('now')),
    ended_at        TEXT
);

CREATE TABLE IF NOT EXISTS encounter_notes (
    id              TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
    encounter_id    TEXT NOT NULL REFERENCES encounters(id) ON DELETE CASCADE,
    author_user_id  TEXT,
    kind            TEXT DEFAULT 'patient_note',
    content         TEXT,
    data            TEXT DEFAULT '{}',
    created_at      TEXT NOT NULL DEFAULT (datetime('now'))
);
