-- =============================================================================
-- medical-ai-hospital: PostgreSQL Seed Data (PRODUCTION)
-- File: db/20_seed.sql
--
-- FIX: Changed ON CONFLICT for drug_interactions to target the unique index's
--      expressions instead of a named constraint.
-- =============================================================================
BEGIN;

-- -----------------------------------------------------------------------------
-- Seed Roles
-- -----------------------------------------------------------------------------
INSERT INTO roles (code, description) VALUES
  ('admin',     'Platform administrator'),
  ('clinician', 'Licensed clinician'),
  ('staff',     'Operational or front-desk staff'),
  ('patient',   'Patient end-user')
ON CONFLICT (code) DO NOTHING;

-- -----------------------------------------------------------------------------
-- Seed Users (demo accounts)
-- NOTE: password_hash values are placeholders. Replace in real deployments.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_admin_id   UUID;
  v_patient_uid UUID;
  v_p1         UUID;
  v_p2         UUID;
  v_enc        UUID;
  v_ibu        UUID;
  v_war        UUID;
  v_lis        UUID;
BEGIN
  -- Admin user
  INSERT INTO users (email, password_hash, password_algo, is_active, is_verified, display_name, phone)
  VALUES ('admin@example.com',
          '$argon2id$v=19$m=65536,t=3,p=4$c29tZXNhbHQ$POm8pP9bT9pY1i8B3y5z0A',
          'argon2id', TRUE, TRUE, 'Admin User', NULL)
  ON CONFLICT (email) DO UPDATE SET email = EXCLUDED.email
  RETURNING id INTO v_admin_id;

  -- Patient user
  INSERT INTO users (email, password_hash, password_algo, is_active, is_verified, display_name, phone)
  VALUES ('demo.user@example.com',
          '$argon2id$v=19$m=65536,t=3,p=4$c29tZXNhbHQ$POm8pP9bT9pY1i8B3y5z0A',
          'argon2id', TRUE, TRUE, 'Demo User', '+1-555-000-1111')
  ON CONFLICT (email) DO UPDATE SET email = EXCLUDED.email
  RETURNING id INTO v_patient_uid;

  -- Role grants
  INSERT INTO user_roles (user_id, role_code) VALUES (v_admin_id, 'admin')
  ON CONFLICT DO NOTHING;

  INSERT INTO user_roles (user_id, role_code) VALUES (v_patient_uid, 'patient')
  ON CONFLICT DO NOTHING;

  -- Per-user settings
  INSERT INTO user_settings (user_id, preferences) VALUES (v_admin_id, '{"theme":"dark"}')
  ON CONFLICT (user_id) DO NOTHING;

  INSERT INTO user_settings (user_id, preferences) VALUES (v_patient_uid, '{"theme":"light"}')
  ON CONFLICT (user_id) DO NOTHING;

  -- ---------------------------------------------------------------------------
  -- Seed Patients (linked to user via patient_users)
  -- ---------------------------------------------------------------------------
  INSERT INTO patients (
    external_key, mrn, national_id,
    first_name, middle_name, last_name, suffix,
    date_of_birth, sex, email, phone,
    address_line1, city, state, postal_code, country_code,
    pregnant, breastfeeding, insurance_id, risk_flags, meta
  ) VALUES
    ('demo-001', 'MRN001', NULL,
     'John', NULL, 'Doe', NULL,
     DATE '1980-08-08', 'male', 'john.doe@example.com', '+1-555-100-2000',
     '123 Main St', 'Metropolis', 'NY', '10001', 'US',
     FALSE, FALSE, 'INS-12345', ARRAY['htn'], '{"preferred_pharmacy":"Acme Pharmacy"}'::jsonb),

    ('demo-002', 'MRN002', NULL,
     'Mary', 'A', 'Smith', NULL,
     DATE '1953-05-12', 'female', 'mary.smith@example.com', '+1-555-200-3000',
     '456 Oak Ave', 'Gotham', 'CA', '94016', 'US',
     FALSE, FALSE, 'INS-98765', ARRAY['oa'], '{"mobility":"reduced"}'::jsonb)
  ON CONFLICT (external_key) DO NOTHING;

  SELECT id INTO v_p1 FROM patients WHERE external_key = 'demo-001';
  SELECT id INTO v_p2 FROM patients WHERE external_key = 'demo-002';

  -- Link patient user to patient record
  INSERT INTO patient_users (patient_id, user_id, role)
  VALUES (v_p1, v_patient_uid, 'OWNER') ON CONFLICT (patient_id, user_id) DO NOTHING;

  -- Clinical data for Patient 1
  INSERT INTO conditions (patient_id, name, code, code_system, onset_date) VALUES
    (v_p1, 'Hypertension', 'I10', 'ICD-10', DATE '2015-01-01');
  INSERT INTO allergies (patient_id, substance, reaction, severity, note) VALUES
    (v_p1, 'penicillin', 'rash', 'mild', 'childhood reaction');
  INSERT INTO medications (patient_id, drug_name, dose, route, frequency, start_date, prn) VALUES
    (v_p1, 'lisinopril', '10 mg', 'oral', 'daily', DATE '2020-01-01', FALSE);
  INSERT INTO vitals (patient_id, timestamp_utc, systolic_mmhg, diastolic_mmhg, heart_rate_bpm, resp_rate_min, temperature_c, spo2_percent, weight_kg, height_cm, bmi)
  VALUES
    (v_p1, now() - INTERVAL '1 hour', 162, 98, 88, 18, 36.8, 97.0, 82, 178, 25.9);

  -- Clinical data for Patient 2
  INSERT INTO conditions (patient_id, name, code, code_system, onset_date) VALUES
    (v_p2, 'Osteoarthritis', NULL, NULL, NULL);
  INSERT INTO medications (patient_id, drug_name, dose, route, frequency, start_date, prn) VALUES
    (v_p2, 'warfarin',   '5 mg',  'oral', 'daily', DATE '2018-01-01', FALSE);
  INSERT INTO vitals (patient_id, timestamp_utc, systolic_mmhg, diastolic_mmhg, heart_rate_bpm, resp_rate_min, temperature_c, spo2_percent, weight_kg, height_cm, bmi)
  VALUES
    (v_p2, now() - INTERVAL '1 day',  128, 78, 72, 16, 36.7, 98.0, 64, 162, 24.4);


  -- Encounters & notes (demo)
  INSERT INTO encounters (patient_id, encounter_type, status, chief_complaint)
  VALUES (v_p1, 'chat', 'open', 'Chest pain and sweating for 2 hours')
  RETURNING id INTO v_enc;

  INSERT INTO encounter_notes (encounter_id, author_user_id, kind, content, data)
  VALUES
    (v_enc, v_patient_uid, 'patient_note',
     'Chest pain and diaphoresis started 2 hours ago after climbing stairs.',
     '{"duration":"2 hours"}'::jsonb),
    (v_enc, v_admin_id,   'ai_summary',
     'AI suggests urgent evaluation for possible ACS.',
     '{"acuity":"urgent","next_steps":["ECG","troponin","aspirin"]}'::jsonb);

  -- -----------------------------------------------------------------------------
  -- Seed Drugs & Interactions (aligned with schema: reference_urls)
  -- -----------------------------------------------------------------------------
  INSERT INTO drugs (drug_name, brand_names, drug_class, mechanism, atc_codes, indications,
                     contraindications, warnings, pregnancy_category, lactation, renal_adjustment,
                     hepatic_adjustment, common_adverse_effects, serious_adverse_effects, reference_urls)
  VALUES
    ('ibuprofen', ARRAY['Advil','Motrin'], 'NSAID',
     'Non-selective COX inhibitor; analgesic and anti-inflammatory',
     ARRAY['M01AE01'], ARRAY['pain','fever','inflammation'], ARRAY['Active GI bleed'],
     ARRAY['Use caution in renal or hepatic impairment'],
     'C', 'Compatible with breastfeeding; monitor infant for GI upset',
     'Avoid in severe renal impairment', 'Use with caution',
     ARRAY['dyspepsia','nausea','headache'], ARRAY['GI bleeding','renal failure'],
     ARRAY['https://www.ncbi.nlm.nih.gov/books/NBK547742/'])
  ON CONFLICT (drug_name) DO NOTHING;

  INSERT INTO drugs (drug_name, brand_names, drug_class, mechanism, atc_codes, indications,
                     contraindications, warnings, pregnancy_category, lactation, renal_adjustment,
                     hepatic_adjustment, common_adverse_effects, serious_adverse_effects, reference_urls)
  VALUES
    ('warfarin', ARRAY['Coumadin'], 'Vitamin K antagonist anticoagulant',
     'Inhibits vitamin K epoxide reductase complex 1',
     ARRAY['B01AA03'], ARRAY['thromboembolism prevention'],
     ARRAY['Pregnancy (X)','Hemorrhagic tendencies'],
     ARRAY['Many drug-drug and diet interactions'],
     'X', 'Use with caution; monitor infant',
     'No adjustment; monitor INR closely', 'Use with caution',
     ARRAY['bleeding','bruising'], ARRAY['major bleeding'],
     ARRAY['https://www.ncbi.nlm.nih.gov/books/NBK470313/'])
  ON CONFLICT (drug_name) DO NOTHING;

  INSERT INTO drugs (drug_name, brand_names, drug_class, mechanism, atc_codes, indications,
                     contraindications, warnings, pregnancy_category, lactation, renal_adjustment,
                     hepatic_adjustment, common_adverse_effects, serious_adverse_effects, reference_urls)
  VALUES
    ('lisinopril', ARRAY['Prinivil','Zestril'], 'ACE inhibitor',
     'Inhibits ACE; reduces angiotensin II',
     ARRAY['C09AA03'], ARRAY['hypertension','heart failure'],
     ARRAY['History of angioedema related to previous ACE inhibitor treatment'],
     ARRAY['Hyperkalemia risk, renal dysfunction'],
     'D', 'Use with caution',
     'Adjust dose based on renal function', 'No adjustment',
     ARRAY['cough','dizziness'], ARRAY['angioedema','renal failure'],
     ARRAY['https://www.ncbi.nlm.nih.gov/books/NBK482230/'])
  ON CONFLICT (drug_name) DO NOTHING;

  SELECT id INTO v_ibu FROM drugs WHERE drug_name='ibuprofen';
  SELECT id INTO v_war FROM drugs WHERE drug_name='warfarin';
  SELECT id INTO v_lis FROM drugs WHERE drug_name='lisinopril';

  -- Interaction: ibuprofen ↔ warfarin (major)
  INSERT INTO drug_interactions (primary_drug_id, interacting_drug_id, severity, mechanism, clinical_effect, management, reference_urls)
  VALUES (LEAST(v_ibu, v_war), GREATEST(v_ibu, v_war), 'major',
          'Additive anticoagulant/platelet inhibition → bleeding risk',
          'Increased INR/bleeding risk',
          'Avoid combination; if necessary, close INR monitoring',
          ARRAY['https://reference.medscape.com/drug-interactionchecker'])
  ON CONFLICT (LEAST(primary_drug_id, interacting_drug_id), GREATEST(primary_drug_id, interacting_drug_id)) DO NOTHING;

  -- Interaction: ibuprofen ↔ lisinopril (moderate)
  INSERT INTO drug_interactions (primary_drug_id, interacting_drug_id, severity, mechanism, clinical_effect, management, reference_urls)
  VALUES (LEAST(v_ibu, v_lis), GREATEST(v_ibu, v_lis), 'moderate',
          'NSAIDs may reduce antihypertensive effect and impair renal function',
          'Attenuated BP control; risk of AKI',
          'Monitor BP and renal function; use lowest effective NSAID dose',
          ARRAY['https://reference.medscape.com/drug-interactionchecker'])
  ON CONFLICT (LEAST(primary_drug_id, interacting_drug_id), GREATEST(primary_drug_id, interacting_drug_id)) DO NOTHING;

END $$;

COMMIT;