-- Canonical lab_results keys: fasting_blood_sugar, triglyceride,
-- total_cholesterol, alt, and uacr. Legacy aliases remain synchronized by
-- both clients for compatibility with older deployed app versions.

-- Historical date-only staff rows receive midnight UTC; new writes retain
-- their full test_date precision.
UPDATE public.lab_results
SET test_date = lab_date::timestamp AT TIME ZONE 'UTC'
WHERE test_date IS NULL
  AND lab_date IS NOT NULL;

-- Prefer canonical values when both columns are populated, then backfill the
-- alias. Each assignment reads the pre-update row values in PostgreSQL.
UPDATE public.lab_results
SET
  fasting_blood_sugar = COALESCE(fasting_blood_sugar, fbs),
  fbs = COALESCE(fasting_blood_sugar, fbs),
  total_cholesterol = COALESCE(total_cholesterol, cholesterol),
  cholesterol = COALESCE(total_cholesterol, cholesterol),
  triglyceride = COALESCE(triglyceride, triglycerides),
  triglycerides = COALESCE(triglyceride, triglycerides),
  alt = COALESCE(alt, sgpt),
  sgpt = COALESCE(alt, sgpt),
  uacr = COALESCE(uacr, urine_microalbumin),
  urine_microalbumin = COALESCE(uacr, urine_microalbumin)
WHERE fasting_blood_sugar IS DISTINCT FROM fbs
   OR total_cholesterol IS DISTINCT FROM cholesterol
   OR triglyceride IS DISTINCT FROM triglycerides
   OR alt IS DISTINCT FROM sgpt
   OR uacr IS DISTINCT FROM urine_microalbumin;