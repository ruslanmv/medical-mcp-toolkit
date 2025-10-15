-- =============================================================================
-- medical-mcp-toolkit: PostgreSQL Seed Data (PRODUCTION)
-- File: db/20_seed.sql
-- =============================================================================
BEGIN;

-- =============================================================================
-- Seed Patients with realistic PII
-- =============================================================================
INSERT INTO patients (
  external_key, mrn, national_id,
  first_name, middle_name, last_name, suffix,
  date_of_birth, sex,
  email, phone,
  address_line1, address_line2, city, state, postal_code, country_code,
  pregnant, breastfeeding, insurance_id, risk_flags, meta
) VALUES
  (
    'demo-001', 'MRN-100001', NULL,
    'John', NULL, 'Doe', NULL,
    DATE '1980-05-20', 'male',
    'john.doe@example.com', '+1-555-0101',
    '123 Maple St', NULL, 'Springfield', 'IL', '62704', 'US',
    FALSE, FALSE, 'INS-ACME-123', ARRAY['HTN'], '{"note":"demo male"}'::jsonb
  ),
  (
    'demo-002', 'MRN-100002', NULL,
    'Mary', 'A.', 'Smith', NULL,
    DATE '1953-11-02', 'female',
    'mary.smith@example.com', '+1-555-0202',
    '456 Oak Ave', 'Apt 5', 'Cedar Grove', 'CA', '95001', 'US',
    FALSE, FALSE, 'INS-OMEGA-789', ARRAY['OA'], '{"note":"demo female"}'::jsonb
  )
ON CONFLICT (external_key) DO NOTHING;

-- Grab IDs for further inserts
DO $$
DECLARE
  p1 UUID; p2 UUID;
BEGIN
  SELECT id INTO p1 FROM patients WHERE external_key='demo-001';
  SELECT id INTO p2 FROM patients WHERE external_key='demo-002';

  -- Conditions
  INSERT INTO conditions (patient_id, name, code, code_system, onset_date)
  VALUES
    (p1,'Hypertension','I10','ICD-10', DATE '2015-01-01'),
    (p2,'Osteoarthritis',NULL,NULL, NULL)
  ON CONFLICT DO NOTHING;

  -- Allergies
  INSERT INTO allergies (patient_id, substance, reaction, severity, note)
  VALUES
    (p1,'penicillin','rash','mild','childhood rash')
  ON CONFLICT DO NOTHING;

  -- Medications
  INSERT INTO medications (patient_id, drug_name, dose, route, frequency, start_date, prn)
  VALUES
    (p1,'lisinopril','10 mg','oral','daily', DATE '2022-01-01', FALSE),
    (p2,'warfarin','5 mg','oral','daily', DATE '2021-06-01', FALSE)
  ON CONFLICT DO NOTHING;

  -- Vitals (recent samples)
  INSERT INTO vitals (
    patient_id, timestamp_utc, systolic_mmhg, diastolic_mmhg, heart_rate_bpm,
    resp_rate_min, temperature_c, spo2_percent, weight_kg, height_cm, bmi,
    serum_creatinine, egfr_ml_min_1_73m2
  )
  VALUES
    (p1, now() - INTERVAL '1 hour', 162, 98, 88, 18, 36.8, 97.0, 82, 178, 25.9, 1.0, 85.0),
    (p2, now() - INTERVAL '1 day', 128, 78, 72, 16, 36.7, 98.0, 64, 162, 24.4, 0.9, 90.0)
  ON CONFLICT DO NOTHING;
END $$;

-- =============================================================================
-- Seed Drug Monographs
-- NOTE: use 'reference_urls' (not 'references').
-- =============================================================================
INSERT INTO drugs (
  drug_name, brand_names, drug_class, mechanism, atc_codes,
  indications, contraindications, warnings, pregnancy_category, lactation,
  renal_adjustment, hepatic_adjustment,
  common_adverse_effects, serious_adverse_effects, reference_urls
)
VALUES
  (
    'ibuprofen', ARRAY['Advil','Motrin'], 'NSAID',
    'Non-selective COX inhibitor; analgesic and anti-inflammatory',
    ARRAY['M01AE01'],
    ARRAY['pain','fever','inflammation'],
    ARRAY['Active GI bleed'],
    ARRAY['Use caution in renal or hepatic impairment'],
    'C',
    'Compatible with breastfeeding; monitor infant for GI upset',
    'Avoid in severe renal impairment',
    'Use with caution',
    ARRAY['dyspepsia','nausea','headache'],
    ARRAY['GI bleeding','renal failure'],
    ARRAY['https://www.ncbi.nlm.nih.gov/books/NBK547742/']
  )
ON CONFLICT (drug_name) DO NOTHING;

INSERT INTO drugs (
  drug_name, brand_names, drug_class, mechanism, atc_codes,
  indications, contraindications, warnings, pregnancy_category, lactation,
  renal_adjustment, hepatic_adjustment,
  common_adverse_effects, serious_adverse_effects, reference_urls
)
VALUES
  (
    'warfarin', ARRAY['Coumadin'], 'Vitamin K antagonist anticoagulant',
    'Inhibits vitamin K epoxide reductase complex 1',
    ARRAY['B01AA03'],
    ARRAY['thromboembolism prevention'],
    ARRAY['Pregnancy (X)','Hemorrhagic tendencies'],
    ARRAY['Many drug-drug and diet interactions'],
    'X',
    'Use with caution; monitor infant',
    'No adjustment; monitor INR closely',
    'Use with caution',
    ARRAY['bleeding','bruising'],
    ARRAY['major bleeding'],
    ARRAY['https://www.ncbi.nlm.nih.gov/books/NBK470313/']
  )
ON CONFLICT (drug_name) DO NOTHING;

INSERT INTO drugs (
  drug_name, brand_names, drug_class, mechanism, atc_codes,
  indications, contraindications, warnings, pregnancy_category, lactation,
  renal_adjustment, hepatic_adjustment,
  common_adverse_effects, serious_adverse_effects, reference_urls
)
VALUES
  (
    'lisinopril', ARRAY['Prinivil','Zestril'], 'ACE inhibitor',
    'Inhibits ACE; reduces angiotensin II',
    ARRAY['C09AA03'],
    ARRAY['hypertension','heart failure'],
    ARRAY['History of angioedema related to previous ACE inhibitor treatment'],
    ARRAY['Hyperkalemia risk, renal dysfunction'],
    'D',
    'Use with caution',
    'Adjust dose based on renal function',
    'No adjustment',
    ARRAY['cough','dizziness'],
    ARRAY['angioedema','renal failure'],
    ARRAY['https://www.ncbi.nlm.nih.gov/books/NBK482230/']
  )
ON CONFLICT (drug_name) DO NOTHING;

-- =============================================================================
-- Seed Drug Interactions
-- NOTE: use 'reference_urls' (not 'references').
-- =============================================================================
DO $$
DECLARE
  ibu UUID; warf UUID; lisi UUID;
BEGIN
  SELECT id INTO ibu  FROM drugs WHERE drug_name='ibuprofen';
  SELECT id INTO warf FROM drugs WHERE drug_name='warfarin';
  SELECT id INTO lisi FROM drugs WHERE drug_name='lisinopril';

  -- Ibuprofen <-> Warfarin
  INSERT INTO drug_interactions (
    primary_drug_id, interacting_drug_id, severity, mechanism, clinical_effect, management, reference_urls
  )
  VALUES (
    LEAST(ibu, warf), GREATEST(ibu, warf), 'major',
    'Additive anticoagulant/platelet inhibition → bleeding risk',
    'Increased INR/bleeding risk',
    'Avoid combination; if necessary, close INR monitoring',
    ARRAY['https://reference.medscape.com/drug-interactionchecker']
  )
  ON CONFLICT DO NOTHING;

  -- Ibuprofen <-> Lisinopril
  INSERT INTO drug_interactions (
    primary_drug_id, interacting_drug_id, severity, mechanism, clinical_effect, management, reference_urls
  )
  VALUES (
    LEAST(ibu, lisi), GREATEST(ibu, lisi), 'moderate',
    'NSAIDs may reduce antihypertensive effect and impair renal function',
    'Attenuated BP control; risk of AKI',
    'Monitor BP and renal function; use lowest effective NSAID dose',
    ARRAY['https://reference.medscape.com/drug-interactionchecker']
  )
  ON CONFLICT DO NOTHING;
END $$;

COMMIT;
