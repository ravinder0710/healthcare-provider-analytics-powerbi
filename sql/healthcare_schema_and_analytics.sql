-- ==============================================================================================
-- HEALTHCARE PROVIDER ANALYTICS & REVENUE CYCLE MANAGEMENT (RCM) - RELATIONAL DDL & ANALYTICS
-- Author: Ravinder Gupta (Data Analyst & BI Specialist)
-- System: UK NHS / Private Healthcare Provider Network (5,000 Patient Encounters)
-- Stack: SQL (PostgreSQL / MySQL Compatible) · Power BI · DAX
-- ==============================================================================================

-- ==============================================================================================
-- 1. DATABASE SCHEMA & DDL DEFINITIONS
-- ==============================================================================================

DROP TABLE IF EXISTS visits CASCADE;
DROP TABLE IF EXISTS patients CASCADE;
DROP TABLE IF EXISTS providers CASCADE;
DROP TABLE IF EXISTS procedures CASCADE;
DROP TABLE IF EXISTS departments CASCADE;
DROP TABLE IF EXISTS diagnoses CASCADE;
DROP TABLE IF EXISTS insurance CASCADE;
DROP TABLE IF EXISTS cities CASCADE;

-- 1.1 Geographic Dimension (Snowflaked with Patients)
CREATE TABLE cities (
    city_id INT PRIMARY KEY,
    city VARCHAR(100) NOT NULL,
    state VARCHAR(100) NOT NULL
);

-- 1.2 Clinical Department Master
CREATE TABLE departments (
    department_id INT PRIMARY KEY,
    department VARCHAR(100) NOT NULL
);

-- 1.3 Clinical Diagnoses Master
CREATE TABLE diagnoses (
    diagnosis_id INT PRIMARY KEY,
    diagnosis VARCHAR(100) NOT NULL
);

-- 1.4 Insurance Provider Master
CREATE TABLE insurance (
    insurance_id INT PRIMARY KEY,
    insurance_provider VARCHAR(100) NOT NULL
);

-- 1.5 Medical Procedures Master
CREATE TABLE procedures (
    procedure_id INT PRIMARY KEY,
    procedure_name VARCHAR(100) NOT NULL
);

-- 1.6 Healthcare Providers (Doctors & Specialists)
CREATE TABLE providers (
    provider_id INT PRIMARY KEY,
    provider_name VARCHAR(150) NOT NULL,
    gender VARCHAR(20),
    nationality VARCHAR(50),
    age INT,
    image_url VARCHAR(255)
);

-- 1.7 Patient Demographics Dimension
CREATE TABLE patients (
    patient_id INT PRIMARY KEY,
    patient_name VARCHAR(150) NOT NULL,
    gender VARCHAR(20),
    age INT,
    city_id INT REFERENCES cities(city_id),
    race VARCHAR(50)
);

-- 1.8 Fact Table: Patient Encounters & Billing Transactions
CREATE TABLE visits (
    visit_id SERIAL PRIMARY KEY,
    date_of_visit DATE NOT NULL,
    patient_id INT NOT NULL REFERENCES patients(patient_id),
    provider_id INT NOT NULL REFERENCES providers(provider_id),
    department_id INT NOT NULL REFERENCES departments(department_id),
    diagnosis_id INT NOT NULL REFERENCES diagnoses(diagnosis_id),
    procedure_id INT NOT NULL REFERENCES procedures(procedure_id),
    insurance_id INT NOT NULL REFERENCES insurance(insurance_id),
    service_type VARCHAR(50),               -- 'Emergency', 'Inpatient', 'Outpatient'
    treatment_cost NUMERIC(12,2) DEFAULT 0.00,
    medication_cost NUMERIC(12,2) DEFAULT 0.00,
    follow_up_visit_date DATE,
    patient_satisfaction_score INT,         -- Rating scale (1 to 10)
    referral_source VARCHAR(100),
    emergency_visit VARCHAR(10),            -- 'Yes' / 'No'
    payment_status VARCHAR(50),             -- 'Paid', 'Pending'
    discharge_date DATE,
    admitted_date DATE,
    room_type VARCHAR(50),                  -- 'ICU', 'General Ward', 'N/A'
    insurance_coverage NUMERIC(12,2) DEFAULT 0.00,
    daily_room_charges NUMERIC(12,2) DEFAULT 0.00
);

-- Optimized Performance Indexes
CREATE INDEX idx_visits_patient ON visits(patient_id);
CREATE INDEX idx_visits_provider ON visits(provider_id);
CREATE INDEX idx_visits_department ON visits(department_id);
CREATE INDEX idx_visits_date ON visits(date_of_visit);
CREATE INDEX idx_visits_service_type ON visits(service_type);


-- ==============================================================================================
-- 2. ENTERPRISE REVENUE CYCLE ANALYTICAL VIEWS (MATCHING POWER BI DAX)
-- ==============================================================================================

-- 2.1 Executive Financial & Volume KPI Cockpit
CREATE OR REPLACE VIEW vw_healthcare_executive_kpis AS
WITH visit_metrics AS (
    SELECT 
        v.visit_id,
        v.treatment_cost,
        v.medication_cost,
        v.insurance_coverage,
        COALESCE((v.discharge_date - v.admitted_date), 0) AS length_of_stay,
        (COALESCE((v.discharge_date - v.admitted_date), 0) * v.daily_room_charges) AS room_charges,
        (v.medication_cost + v.treatment_cost + (COALESCE((v.discharge_date - v.admitted_date), 0) * v.daily_room_charges)) AS total_billing
    FROM visits v
)
SELECT 
    COUNT(visit_id) AS total_visits,
    COUNT(DISTINCT v.patient_id) AS total_patients,
    SUM(vm.total_billing) AS total_billing_amount,
    SUM(vm.treatment_cost) AS total_treatment_cost,
    SUM(vm.medication_cost) AS total_medication_cost,
    SUM(vm.room_charges) AS total_room_charges,
    SUM(vm.insurance_coverage) AS total_insurance_coverage,
    SUM(vm.total_billing - vm.insurance_coverage) AS total_out_of_pocket,
    
    -- Average Per Visit Unit Economics
    ROUND(AVG(vm.total_billing), 2) AS avg_billing_per_visit,
    ROUND(AVG(vm.treatment_cost), 2) AS avg_treatment_per_visit,
    ROUND(AVG(vm.medication_cost), 2) AS avg_medication_per_visit,
    ROUND(AVG(vm.room_charges), 2) AS avg_room_charges_per_visit,
    ROUND(AVG(vm.insurance_coverage), 2) AS avg_insurance_coverage_per_visit,
    ROUND(AVG(vm.total_billing - vm.insurance_coverage), 2) AS avg_out_of_pocket_per_visit
FROM visits v
JOIN visit_metrics vm ON v.visit_id = vm.visit_id;


-- 2.2 Departmental Billing Contribution & % Grand Total
CREATE OR REPLACE VIEW vw_department_billing_contribution AS
WITH dept_totals AS (
    SELECT 
        d.department,
        COUNT(v.visit_id) AS total_visits,
        SUM(v.medication_cost + v.treatment_cost + (COALESCE((v.discharge_date - v.admitted_date), 0) * v.daily_room_charges)) AS total_billing_amount
    FROM visits v
    JOIN departments d ON v.department_id = d.department_id
    GROUP BY d.department
),
overall_total AS (
    SELECT SUM(total_billing_amount) AS grand_total FROM dept_totals
)
SELECT 
    dt.department,
    dt.total_visits,
    dt.total_billing_amount,
    ROUND((dt.total_billing_amount / ot.grand_total) * 100, 2) AS pct_department_share,
    DENSE_RANK() OVER (ORDER BY dt.total_billing_amount DESC) AS revenue_rank
FROM dept_totals dt
CROSS JOIN overall_total ot;


-- 2.3 Procedure Revenue & Share Analysis
CREATE OR REPLACE VIEW vw_procedure_revenue_analysis AS
WITH proc_totals AS (
    SELECT 
        p.procedure_name,
        COUNT(v.visit_id) AS total_procedures,
        SUM(v.medication_cost + v.treatment_cost + (COALESCE((v.discharge_date - v.admitted_date), 0) * v.daily_room_charges)) AS total_billing_amount
    FROM visits v
    JOIN procedures p ON v.procedure_id = p.procedure_id
    GROUP BY p.procedure_name
),
overall_total AS (
    SELECT SUM(total_billing_amount) AS grand_total FROM proc_totals
)
SELECT 
    pt.procedure_name,
    pt.total_procedures,
    pt.total_billing_amount,
    ROUND((pt.total_billing_amount / ot.grand_total) * 100, 2) AS pct_procedure_share
FROM proc_totals pt
CROSS JOIN overall_total ot
ORDER BY pt.total_billing_amount DESC;


-- 2.4 Diagnosis by Service Type Split (Emergency, Inpatient, Outpatient)
CREATE OR REPLACE VIEW vw_diagnosis_service_type_matrix AS
SELECT 
    dg.diagnosis,
    COUNT(CASE WHEN v.service_type = 'Emergency' THEN 1 END) AS emergency_visits,
    ROUND(SUM(CASE WHEN v.service_type = 'Emergency' THEN (v.medication_cost + v.treatment_cost + (COALESCE((v.discharge_date - v.admitted_date), 0) * v.daily_room_charges)) ELSE 0 END), 2) AS emergency_billing,
    
    COUNT(CASE WHEN v.service_type = 'Inpatient' THEN 1 END) AS inpatient_visits,
    ROUND(SUM(CASE WHEN v.service_type = 'Inpatient' THEN (v.medication_cost + v.treatment_cost + (COALESCE((v.discharge_date - v.admitted_date), 0) * v.daily_room_charges)) ELSE 0 END), 2) AS inpatient_billing,
    
    COUNT(CASE WHEN v.service_type = 'Outpatient' THEN 1 END) AS outpatient_visits,
    ROUND(SUM(CASE WHEN v.service_type = 'Outpatient' THEN (v.medication_cost + v.treatment_cost + (COALESCE((v.discharge_date - v.admitted_date), 0) * v.daily_room_charges)) ELSE 0 END), 2) AS outpatient_billing,

    ROUND(SUM(v.medication_cost + v.treatment_cost + (COALESCE((v.discharge_date - v.admitted_date), 0) * v.daily_room_charges)), 2) AS total_diagnosis_billing
FROM visits v
JOIN diagnoses dg ON v.diagnosis_id = dg.diagnosis_id
GROUP BY dg.diagnosis;


-- 2.5 Provider Clinical Scorecard & Patient Satisfaction
CREATE OR REPLACE VIEW vw_provider_performance_scorecard AS
SELECT 
    pr.provider_id,
    pr.provider_name,
    pr.nationality,
    COUNT(v.visit_id) AS total_patient_encounters,
    ROUND(AVG(v.patient_satisfaction_score), 2) AS avg_satisfaction_score,
    ROUND(SUM(v.medication_cost + v.treatment_cost + (COALESCE((v.discharge_date - v.admitted_date), 0) * v.daily_room_charges)), 2) AS total_generated_revenue,
    ROUND(AVG(COALESCE((v.discharge_date - v.admitted_date), 0)), 1) AS avg_inpatient_los_days
FROM visits v
JOIN providers pr ON v.provider_id = pr.provider_id
GROUP BY pr.provider_id, pr.provider_name, pr.nationality
ORDER BY total_generated_revenue DESC;


-- 2.6 Geographic Distribution by City & State (UK Regional Insights)
CREATE OR REPLACE VIEW vw_geographic_revenue_distribution AS
SELECT 
    c.state,
    c.city,
    COUNT(v.visit_id) AS total_visits,
    COUNT(DISTINCT v.patient_id) AS total_patients,
    ROUND(SUM(v.medication_cost + v.treatment_cost + (COALESCE((v.discharge_date - v.admitted_date), 0) * v.daily_room_charges)), 2) AS total_billing_amount,
    ROUND(AVG(v.medication_cost + v.treatment_cost + (COALESCE((v.discharge_date - v.admitted_date), 0) * v.daily_room_charges)), 2) AS avg_billing_per_visit
FROM visits v
JOIN patients p ON v.patient_id = p.patient_id
JOIN cities c ON p.city_id = c.city_id
GROUP BY c.state, c.city
ORDER BY total_billing_amount DESC;
