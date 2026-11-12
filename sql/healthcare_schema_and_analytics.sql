-- ========================================================================================
-- HEALTHCARE PROVIDER ANALYTICS & REVENUE CYCLE MANAGEMENT (RCM)
-- Production SQL Schema, Views & Cohort Analytics Suite
-- Author: Ravinder Gupta (ravinder0710)
-- Target: NHS UK / Healthcare Enterprise Hospital Systems
-- Compatible with: PostgreSQL / MySQL / SQL Server / Snowflake
-- ========================================================================================

-- ----------------------------------------------------------------------------------------
-- 1. DATABASE SCHEMA & DDL DEFINITIONS (Star Schema)
-- ----------------------------------------------------------------------------------------

CREATE TABLE dim_departments (
    department_id INT PRIMARY KEY,
    department VARCHAR(100) NOT NULL
);

CREATE TABLE dim_diagnoses (
    diagnosis_id INT PRIMARY KEY,
    diagnosis VARCHAR(100) NOT NULL
);

CREATE TABLE dim_procedures (
    procedure_id INT PRIMARY KEY,
    procedure_name VARCHAR(100) NOT NULL
);

CREATE TABLE dim_insurance (
    insurance_id INT PRIMARY KEY,
    insurance_provider VARCHAR(100) NOT NULL
);

CREATE TABLE dim_cities (
    city_id INT PRIMARY KEY,
    city VARCHAR(100) NOT NULL,
    state VARCHAR(100) NOT NULL
);

CREATE TABLE dim_providers (
    provider_id INT PRIMARY KEY,
    provider_name VARCHAR(150) NOT NULL,
    gender VARCHAR(20),
    nationality VARCHAR(50),
    age INT,
    image_url VARCHAR(255)
);

CREATE TABLE dim_patients (
    patient_id INT PRIMARY KEY,
    patient_name VARCHAR(150) NOT NULL,
    gender VARCHAR(20),
    age INT,
    city_id INT,
    race VARCHAR(50),
    FOREIGN KEY (city_id) REFERENCES dim_cities(city_id)
);

CREATE TABLE fact_visits (
    visit_id INT PRIMARY KEY,
    date_of_visit DATE NOT NULL,
    patient_id INT NOT NULL,
    provider_id INT NOT NULL,
    department_id INT NOT NULL,
    diagnosis_id INT NOT NULL,
    procedure_id INT NOT NULL,
    insurance_id INT,
    service_type VARCHAR(50) NOT NULL, -- Outpatient, Inpatient, Emergency
    treatment_cost DECIMAL(12, 2) DEFAULT 0.00,
    medication_cost DECIMAL(12, 2) DEFAULT 0.00,
    follow_up_visit_date DATE,
    patient_satisfaction_score INT,
    referral_source VARCHAR(100),
    emergency_visit VARCHAR(10),
    payment_status VARCHAR(50),
    discharge_date DATE,
    admitted_date DATE,
    room_type VARCHAR(100),
    insurance_coverage DECIMAL(12, 2) DEFAULT 0.00,
    daily_room_charges DECIMAL(12, 2) DEFAULT 0.00,
    FOREIGN KEY (patient_id) REFERENCES dim_patients(patient_id),
    FOREIGN KEY (provider_id) REFERENCES dim_providers(provider_id),
    FOREIGN KEY (department_id) REFERENCES dim_departments(department_id),
    FOREIGN KEY (diagnosis_id) REFERENCES dim_diagnoses(diagnosis_id),
    FOREIGN KEY (procedure_id) REFERENCES dim_procedures(procedure_id),
    FOREIGN KEY (insurance_id) REFERENCES dim_insurance(insurance_id)
);

-- ----------------------------------------------------------------------------------------
-- 2. ENRICHED REPORTING VIEW (Denormalized Semantic Model)
-- ----------------------------------------------------------------------------------------

CREATE OR REPLACE VIEW vw_healthcare_clinical_financial_summary AS
SELECT 
    v.visit_id,
    v.date_of_visit,
    p.patient_id,
    p.patient_name,
    p.gender AS patient_gender,
    p.age AS patient_age,
    p.race AS patient_race,
    c.city AS patient_city,
    c.state AS patient_state,
    pr.provider_id,
    pr.provider_name,
    d.department,
    dg.diagnosis,
    pc.procedure_name,
    ins.insurance_provider,
    v.service_type,
    v.emergency_visit,
    v.payment_status,
    v.patient_satisfaction_score,
    v.admitted_date,
    v.discharge_date,
    -- Length of stay calculation
    COALESCE(DATEDIFF(day, v.admitted_date, v.discharge_date), 0) AS length_of_stay_days,
    v.room_type,
    v.daily_room_charges,
    -- Financial Aggregations
    COALESCE(v.treatment_cost, 0) AS treatment_cost,
    COALESCE(v.medication_cost, 0) AS medication_cost,
    (COALESCE(v.daily_room_charges, 0) * COALESCE(DATEDIFF(day, v.admitted_date, v.discharge_date), 0)) AS total_room_charges,
    (COALESCE(v.treatment_cost, 0) + COALESCE(v.medication_cost, 0) + 
     (COALESCE(v.daily_room_charges, 0) * COALESCE(DATEDIFF(day, v.admitted_date, v.discharge_date), 0))) AS total_billing_amount,
    COALESCE(v.insurance_coverage, 0) AS insurance_coverage,
    ((COALESCE(v.treatment_cost, 0) + COALESCE(v.medication_cost, 0) + 
     (COALESCE(v.daily_room_charges, 0) * COALESCE(DATEDIFF(day, v.admitted_date, v.discharge_date), 0))) - 
     COALESCE(v.insurance_coverage, 0)) AS out_of_pocket_expense
FROM fact_visits v
JOIN dim_patients p ON v.patient_id = p.patient_id
JOIN dim_cities c ON p.city_id = c.city_id
JOIN dim_providers pr ON v.provider_id = pr.provider_id
JOIN dim_departments d ON v.department_id = d.department_id
JOIN dim_diagnoses dg ON v.diagnosis_id = dg.diagnosis_id
JOIN dim_procedures pc ON v.procedure_id = pc.procedure_id
LEFT JOIN dim_insurance ins ON v.insurance_id = ins.insurance_id;

-- ----------------------------------------------------------------------------------------
-- 3. EXECUTIVE KPI AUDIT QUERY (Matches Power BI Top Cards Exactly)
-- ----------------------------------------------------------------------------------------

SELECT 
    COUNT(visit_id) AS total_visits,
    COUNT(DISTINCT patient_id) AS distinct_patients,
    SUM(total_billing_amount) AS total_gross_billing_gbp,
    ROUND(AVG(total_billing_amount), 2) AS avg_billing_per_visit_gbp,
    SUM(medication_cost) AS total_medication_cost_gbp,
    ROUND(AVG(medication_cost), 2) AS avg_medication_per_visit_gbp,
    SUM(treatment_cost) AS total_treatment_cost_gbp,
    ROUND(AVG(treatment_cost), 2) AS avg_treatment_per_visit_gbp,
    SUM(total_room_charges) AS total_room_charges_gbp,
    ROUND(AVG(total_room_charges), 2) AS avg_room_charge_per_visit_gbp,
    SUM(insurance_coverage) AS total_insurance_covered_gbp,
    ROUND(AVG(insurance_coverage), 2) AS avg_insurance_covered_per_visit_gbp,
    SUM(out_of_pocket_expense) AS total_out_of_pocket_gbp,
    ROUND(AVG(out_of_pocket_expense), 2) AS avg_out_of_pocket_per_visit_gbp,
    ROUND(AVG(patient_satisfaction_score), 2) AS avg_patient_satisfaction
FROM vw_healthcare_clinical_financial_summary;

-- ----------------------------------------------------------------------------------------
-- 4. DEPARTMENT REVENUE CONTRIBUTION & SHARE (%)
-- ----------------------------------------------------------------------------------------

SELECT 
    department,
    COUNT(visit_id) AS visit_count,
    SUM(total_billing_amount) AS department_billing_gbp,
    ROUND(SUM(total_billing_amount) * 100.0 / SUM(SUM(total_billing_amount)) OVER(), 2) AS revenue_share_pct,
    ROUND(AVG(patient_satisfaction_score), 2) AS avg_satisfaction_score
FROM vw_healthcare_clinical_financial_summary
GROUP BY department
ORDER BY department_billing_gbp DESC;

-- ----------------------------------------------------------------------------------------
-- 5. PROCEDURE UTILIZATION & REVENUE IMPACT
-- ----------------------------------------------------------------------------------------

SELECT 
    procedure_name,
    COUNT(visit_id) AS procedure_volume,
    SUM(total_billing_amount) AS procedure_billing_gbp,
    ROUND(SUM(total_billing_amount) * 100.0 / SUM(SUM(total_billing_amount)) OVER(), 2) AS procedure_revenue_share_pct,
    ROUND(AVG(treatment_cost), 2) AS avg_procedure_cost_gbp
FROM vw_healthcare_clinical_financial_summary
GROUP BY procedure_name
ORDER BY procedure_billing_gbp DESC;

-- ----------------------------------------------------------------------------------------
-- 6. DIAGNOSIS BY SERVICE TYPE 100% STACKED REVENUE SHARE
-- ----------------------------------------------------------------------------------------

SELECT 
    diagnosis,
    ROUND(SUM(CASE WHEN service_type = 'Emergency' THEN total_billing_amount ELSE 0 END) * 100.0 / SUM(total_billing_amount), 2) AS emergency_pct,
    ROUND(SUM(CASE WHEN service_type = 'Inpatient' THEN total_billing_amount ELSE 0 END) * 100.0 / SUM(total_billing_amount), 2) AS inpatient_pct,
    ROUND(SUM(CASE WHEN service_type = 'Outpatient' THEN total_billing_amount ELSE 0 END) * 100.0 / SUM(total_billing_amount), 2) AS outpatient_pct,
    SUM(total_billing_amount) AS total_diagnosis_billing_gbp
FROM vw_healthcare_clinical_financial_summary
GROUP BY diagnosis
ORDER BY total_diagnosis_billing_gbp DESC;

-- ----------------------------------------------------------------------------------------
-- 7. GEOGRAPHIC CONCENTRATION (Top Cities by Billing Volume)
-- ----------------------------------------------------------------------------------------

SELECT 
    patient_city,
    patient_state,
    COUNT(visit_id) AS total_visits,
    SUM(total_billing_amount) AS city_billing_gbp,
    ROUND(SUM(total_billing_amount) * 100.0 / SUM(SUM(total_billing_amount)) OVER(), 2) AS national_share_pct
FROM vw_healthcare_clinical_financial_summary
GROUP BY patient_city, patient_state
ORDER BY city_billing_gbp DESC
LIMIT 10;

-- ----------------------------------------------------------------------------------------
-- 8. PROVIDER PRODUCTIVITY & REVENUE RANKING (Window Function)
-- ----------------------------------------------------------------------------------------

SELECT 
    provider_name,
    COUNT(visit_id) AS patient_encounters,
    SUM(total_billing_amount) AS provider_revenue_gbp,
    ROUND(AVG(patient_satisfaction_score), 2) AS avg_satisfaction,
    DENSE_RANK() OVER(ORDER BY SUM(total_billing_amount) DESC) AS revenue_rank,
    ROUND(AVG(length_of_stay_days), 1) AS avg_patient_length_of_stay
FROM vw_healthcare_clinical_financial_summary
GROUP BY provider_name
ORDER BY provider_revenue_gbp DESC;
