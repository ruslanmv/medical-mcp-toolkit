# src/medical_mcp_toolkit/store/pg.py
from __future__ import annotations

from typing import Any, Optional
from uuid import UUID

try:
    import psycopg
    from psycopg import rows, errors
    from psycopg_pool import AsyncConnectionPool  # type: ignore
except Exception:  # pragma: no cover
    psycopg = None  # type: ignore
    rows = None  # type: ignore
    errors = None  # type: ignore
    AsyncConnectionPool = None  # type: ignore

from .config import get_db_dsn

_pool: Optional["AsyncConnectionPool"] = None


# -----------------------------------------------------------------------------
# Pool management
# -----------------------------------------------------------------------------
async def get_pool() -> "AsyncConnectionPool":
    """
    Get (or lazily create) a global async connection pool.
    """
    global _pool
    if _pool is None:
        dsn = get_db_dsn()
        if not dsn:
            raise RuntimeError("DATABASE_URL not configured")
        _pool = AsyncConnectionPool(dsn, min_size=1, max_size=10, open=True)  # type: ignore
    return _pool


async def close_pool() -> None:
    """
    Gracefully close the global pool (useful in tests/shutdown).
    """
    global _pool
    if _pool is not None:
        await _pool.close()  # type: ignore
        _pool = None


# -----------------------------------------------------------------------------
# Low-level helpers
# -----------------------------------------------------------------------------
async def fetchrow(sql: str, *args: Any) -> Optional[dict]:
    pool = await get_pool()
    async with pool.connection() as conn:  # type: ignore[union-attr]
        async with conn.cursor(row_factory=rows.dict_row) as cur:  # type: ignore
            await cur.execute(sql, args)
            return await cur.fetchone()


async def fetch(sql: str, *args: Any) -> list[dict]:
    pool = await get_pool()
    async with pool.connection() as conn:  # type: ignore[union-attr]
        async with conn.cursor(row_factory=rows.dict_row) as cur:  # type: ignore
            await cur.execute(sql, args)
            rows_ = await cur.fetchall()
            return list(rows_)


async def execute(sql: str, *args: Any) -> int:
    pool = await get_pool()
    async with pool.connection() as conn:  # type: ignore[union-attr]
        async with conn.cursor() as cur:  # type: ignore
            await cur.execute(sql, args)
            return cur.rowcount or 0


# -----------------------------------------------------------------------------
# Higher-level query helpers aligned with updated DB schema
# -----------------------------------------------------------------------------
# Users
async def get_user_by_email(email: str) -> Optional[dict]:
    return await fetchrow(
        """
        SELECT id, email, password_hash, password_algo, is_active, is_verified,
               display_name, phone, mfa_enabled, last_login_at, last_login_ip,
               created_at, updated_at
        FROM users
        WHERE email = %s
        """,
        email,
    )


# Patients
async def get_patient(patient_id: str | UUID) -> Optional[dict]:
    return await fetchrow(
        """
        SELECT *
        FROM patients
        WHERE id = %s
        """,
        str(patient_id),
    )


async def insert_patient(
    *,
    first_name: str,
    last_name: str,
    date_of_birth: str,  # ISO date
    sex: str = "unknown",
    external_key: Optional[str] = None,
    mrn: Optional[str] = None,
    email: Optional[str] = None,
    phone: Optional[str] = None,
) -> dict:
    return await fetchrow(
        """
        INSERT INTO patients (
            first_name, last_name, date_of_birth, sex,
            external_key, mrn, email, phone
        )
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
        RETURNING *
        """,
        first_name,
        last_name,
        date_of_birth,
        sex,
        external_key,
        mrn,
        email,
        phone,
    )


# Patient ↔ User linking (patient_users)
async def link_patient_user(
    *, patient_id: str | UUID, user_id: str | UUID, role: str = "OWNER"
) -> dict:
    """
    Insert (or no-op if already linked) a row in patient_users.
    Uses the UNIQUE (patient_id, user_id) constraint for idempotency.
    """
    return await fetchrow(
        """
        INSERT INTO patient_users (patient_id, user_id, role)
        VALUES (%s, %s, %s)
        ON CONFLICT (patient_id, user_id) DO UPDATE
            SET role = EXCLUDED.role
        RETURNING *
        """,
        str(patient_id),
        str(user_id),
        role,
    )


async def get_patient_user_by_pair(
    *, patient_id: str | UUID, user_id: str | UUID
) -> Optional[dict]:
    """
    Select via the unique pair (patient_id, user_id). The table now has a UUID PK (id),
    but the pair remains unique for lookups.
    """
    return await fetchrow(
        """
        SELECT *
        FROM patient_users
        WHERE patient_id = %s AND user_id = %s
        """,
        str(patient_id),
        str(user_id),
    )


# Vitals (updated columns)
async def insert_vitals(
    *,
    patient_id: str | UUID,
    timestamp_utc: str,  # ISO datetime
    systolic_mmhg: Optional[int] = None,
    diastolic_mmhg: Optional[int] = None,
    heart_rate_bpm: Optional[int] = None,
    resp_rate_min: Optional[int] = None,
    temperature_c: Optional[float] = None,
    spo2_percent: Optional[float] = None,
    weight_kg: Optional[float] = None,
    height_cm: Optional[float] = None,
    bmi: Optional[float] = None,
    serum_creatinine: Optional[float] = None,
    egfr_ml_min_1_73m2: Optional[float] = None,
) -> dict:
    return await fetchrow(
        """
        INSERT INTO vitals (
            patient_id, timestamp_utc,
            systolic_mmhg, diastolic_mmhg, heart_rate_bpm, resp_rate_min,
            temperature_c, spo2_percent, weight_kg, height_cm, bmi,
            serum_creatinine, egfr_ml_min_1_73m2
        )
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        RETURNING *
        """,
        str(patient_id),
        timestamp_utc,
        systolic_mmhg,
        diastolic_mmhg,
        heart_rate_bpm,
        resp_rate_min,
        temperature_c,
        spo2_percent,
        weight_kg,
        height_cm,
        bmi,
        serum_creatinine,
        egfr_ml_min_1_73m2,
    )


async def get_latest_vitals(patient_id: str | UUID) -> Optional[dict]:
    return await fetchrow(
        """
        SELECT *
        FROM v_latest_vitals
        WHERE patient_id = %s
        """,
        str(patient_id),
    )


# Drugs (rename references -> reference_urls)
async def upsert_drug(
    *,
    drug_name: str,
    drug_class: Optional[str] = None,
    mechanism: Optional[str] = None,
    pregnancy_category: Optional[str] = None,
    lactation: Optional[str] = None,
    renal_adjustment: Optional[str] = None,
    hepatic_adjustment: Optional[str] = None,
    indications: Optional[list[str]] = None,
    contraindications: Optional[list[str]] = None,
    warnings: Optional[list[str]] = None,
    common_adverse_effects: Optional[list[str]] = None,
    serious_adverse_effects: Optional[list[str]] = None,
    brand_names: Optional[list[str]] = None,
    atc_codes: Optional[list[str]] = None,
    reference_urls: Optional[list[str]] = None,
) -> dict:
    """
    Upsert by unique key drug_name.
    """
    return await fetchrow(
        """
        INSERT INTO drugs (
          drug_name, drug_class, mechanism, pregnancy_category, lactation,
          renal_adjustment, hepatic_adjustment, indications, contraindications, warnings,
          common_adverse_effects, serious_adverse_effects, brand_names, atc_codes, reference_urls
        )
        VALUES (
          %s, %s, %s, %s, %s,
          %s, %s, %s, %s, %s,
          %s, %s, %s, %s, %s
        )
        ON CONFLICT (drug_name) DO UPDATE SET
          drug_class = EXCLUDED.drug_class,
          mechanism = EXCLUDED.mechanism,
          pregnancy_category = EXCLUDED.pregnancy_category,
          lactation = EXCLUDED.lactation,
          renal_adjustment = EXCLUDED.renal_adjustment,
          hepatic_adjustment = EXCLUDED.hepatic_adjustment,
          indications = EXCLUDED.indications,
          contraindications = EXCLUDED.contraindications,
          warnings = EXCLUDED.warnings,
          common_adverse_effects = EXCLUDED.common_adverse_effects,
          serious_adverse_effects = EXCLUDED.serious_adverse_effects,
          brand_names = EXCLUDED.brand_names,
          atc_codes = EXCLUDED.atc_codes,
          reference_urls = EXCLUDED.reference_urls,
          updated_at = now()
        RETURNING *
        """,
        drug_name,
        drug_class,
        mechanism,
        pregnancy_category,
        lactation,
        renal_adjustment,
        hepatic_adjustment,
        indications or [],
        contraindications or [],
        warnings or [],
        common_adverse_effects or [],
        serious_adverse_effects or [],
        brand_names or [],
        atc_codes or [],
        reference_urls or [],
    )


async def get_drug_by_name(drug_name: str) -> Optional[dict]:
    return await fetchrow(
        """
        SELECT *
        FROM drugs
        WHERE drug_name = %s
        """,
        drug_name,
    )


# Drug interactions (pairwise unique via expression index)
async def upsert_drug_interaction(
    *,
    drug_id_a: str | UUID,
    drug_id_b: str | UUID,
    severity: str,
    mechanism: Optional[str] = None,
    clinical_effect: Optional[str] = None,
    management: Optional[str] = None,
    reference_urls: Optional[list[str]] = None,
) -> dict:
    """
    Because the DB uses a UNIQUE EXPRESSION INDEX with LEAST/GREATEST,
    we cannot use ON CONFLICT directly (it only supports columns/constraints).
    Strategy: canonicalize the pair (a, b) -> (low, high), try INSERT; if unique
    violation occurs, UPDATE the existing row using the same canonical pair.
    """
    a = str(drug_id_a)
    b = str(drug_id_b)
    low, high = (a, b) if a <= b else (b, a)

    pool = await get_pool()
    async with pool.connection() as conn:  # type: ignore[union-attr]
        async with conn.cursor(row_factory=rows.dict_row) as cur:  # type: ignore
            try:
                await cur.execute(
                    """
                    INSERT INTO drug_interactions (
                        primary_drug_id, interacting_drug_id, severity,
                        mechanism, clinical_effect, management, reference_urls
                    )
                    VALUES (%s, %s, %s, %s, %s, %s, %s)
                    RETURNING *
                    """,
                    (low, high, severity, mechanism, clinical_effect, management, reference_urls or []),
                )
                inserted = await cur.fetchone()
                return inserted  # type: ignore[return-value]
            except errors.UniqueViolation:  # type: ignore[attr-defined]
                # Row exists in either order; update the matched pair
                await cur.execute(
                    """
                    UPDATE drug_interactions
                    SET severity = %s,
                        mechanism = %s,
                        clinical_effect = %s,
                        management = %s,
                        reference_urls = %s,
                        updated_at = now()
                    WHERE LEAST(primary_drug_id, interacting_drug_id) = %s
                      AND GREATEST(primary_drug_id, interacting_drug_id) = %s
                    RETURNING *
                    """,
                    (
                        severity,
                        mechanism,
                        clinical_effect,
                        management,
                        reference_urls or [],
                        low,
                        high,
                    ),
                )
                updated = await cur.fetchone()
                return updated  # type: ignore[return-value]


# Appointments (specialty is NOT NULL in schema)
async def create_appointment(
    *,
    patient_id: str | UUID,
    scheduled_start_iso: str,
    scheduled_end_iso: str,
    specialty: str,
    provider: Optional[str] = None,
    location: Optional[str] = None,
    status: str = "scheduled",
) -> dict:
    return await fetchrow(
        """
        INSERT INTO appointments (
            patient_id, scheduled_start, scheduled_end,
            specialty, provider, location, status
        )
        VALUES (%s, %s, %s, %s, %s, %s, %s)
        RETURNING *
        """,
        str(patient_id),
        scheduled_start_iso,
        scheduled_end_iso,
        specialty,
        provider,
        location,
        status,
    )


# Patient profile view
async def get_patient_profile(patient_id: str | UUID) -> Optional[dict]:
    return await fetchrow(
        """
        SELECT *
        FROM v_patient_profile
        WHERE patient_id = %s
        """,
        str(patient_id),
    )


__all__ = [
    "get_pool",
    "close_pool",
    "fetchrow",
    "fetch",
    "execute",
    # helpers
    "get_user_by_email",
    "get_patient",
    "insert_patient",
    "link_patient_user",
    "get_patient_user_by_pair",
    "insert_vitals",
    "get_latest_vitals",
    "upsert_drug",
    "get_drug_by_name",
    "upsert_drug_interaction",
    "create_appointment",
    "get_patient_profile",
]
