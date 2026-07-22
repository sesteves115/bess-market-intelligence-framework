-- ============================================
-- STAGE 1 INTEGRATION | BESS OPPORTUNITY SCORING
-- Sources: module_a2_state_hourly_metrics, module_a_monthly_metrics,
--          module_b_metrics, module_b_cost_spread, module_c_summary,
--          module_d_industrial_load, module_d_storage_deployment,
--          module_d_reliability, module_d_regulatory_receptiveness,
--          module_e_residential_score, module_f_ci_score,
--          module_f_dc_score, market_structure_ref,
--          raw_dsire_incentive_scores
-- Final tables: integration_base, integration_scores,
--               integration_final_grid, integration_final_residential,
--               integration_final_ci
-- ============================================

-- STEP 1 | BASE TABLE
-- joins all module outputs at state level
-- placeholder NULLs for external data layers filled in subsequent steps

CREATE TABLE integration_base AS
WITH
a_monthly AS (
    SELECT
        state,
        MAX(renewable_share)            AS renewable_share,
        MAX(variable_renewable_share)   AS variable_renewable_share,
        MAX(fossil_share)               AS fossil_share
    FROM module_a_monthly_metrics
    GROUP BY state
),
b_gas AS (
    SELECT
        state,
        avg_cost_per_mwh                AS gas_avg_cost_per_mwh,
        cv_cost                         AS gas_cv_cost,
        high_null_flag                  AS gas_high_null_flag
    FROM module_b_metrics
    WHERE fuel_type_code_pudl = 'gas'
),
b_oil AS (
    SELECT
        state,
        avg_cost_per_mwh                AS oil_avg_cost_per_mwh,
        cv_cost                         AS oil_cv_cost
    FROM module_b_metrics
    WHERE fuel_type_code_pudl = 'oil'
)
SELECT
    h.state,
    h.cv_gen,
    h.cv_demand,
    h.avg_ramp_rate_mwh,
    h.max_ramp_rate_mwh,
    h.avg_demand_ramp_mwh,
    h.max_demand_ramp_mwh,
    h.avg_interchange_mwh,
    h.max_deficit_mwh,
    a.fossil_share,
    a.renewable_share,
    a.variable_renewable_share,
    g.gas_avg_cost_per_mwh,
    g.gas_cv_cost,
    g.gas_high_null_flag,
    o.oil_avg_cost_per_mwh,
    o.oil_cv_cost,
    s.gas_coal_spread,
    s.oil_coal_spread,
    c.hhi_concentration,
    c.dominant_fuel_type,
    c.dominant_fuel_pct,
    c.variable_re_growth_pct,
    c.late_fossil_pct,
    c.late_variable_re_pct,
    c.transition_status,
    c.concentration_class,
    NULL                                AS market_structure,
    NULL                                AS iso_rto,
    NULL                                AS industrial_load_score,
    NULL                                AS incentive_score
FROM module_a2_state_hourly_metrics h
JOIN a_monthly a                ON h.state = a.state
LEFT JOIN b_gas g               ON h.state = g.state
LEFT JOIN b_oil o               ON h.state = o.state
LEFT JOIN module_b_cost_spread s ON h.state = s.state
JOIN module_c_summary c         ON h.state = c.state
ORDER BY h.state;

-- STEP 2 | SCORING TABLE
-- NTILE(5) percentile ranking across 49 states per dimension
-- placeholder columns for external layers filled via UPDATE in subsequent steps

CREATE TABLE integration_scores AS
SELECT
    state,
    dominant_fuel_type,
    transition_status,
    concentration_class,
    gas_high_null_flag,
    cv_gen,
    cv_demand,
    avg_ramp_rate_mwh,
    gas_cv_cost,
    gas_avg_cost_per_mwh,
    oil_avg_cost_per_mwh,
    oil_coal_spread,
    gas_coal_spread,
    hhi_concentration,
    fossil_share,
    variable_re_growth_pct,
    late_fossil_pct,
    late_variable_re_pct,

    -- grid stress: high cv and ramp = high stress = high score
    ROUND((
        NTILE(5) OVER (ORDER BY cv_gen) +
        NTILE(5) OVER (ORDER BY cv_demand) +
        NTILE(5) OVER (ORDER BY avg_ramp_rate_mwh) +
        NTILE(5) OVER (ORDER BY avg_demand_ramp_mwh)
    ) / 4.0, 2)                             AS grid_stress_score,

    -- cost volatility: high gas cv = high score
    NTILE(5) OVER (ORDER BY gas_cv_cost)    AS cost_volatility_score,

    -- fossil dependency: high fossil share and concentration = high score
    ROUND((
        NTILE(5) OVER (ORDER BY fossil_share) +
        NTILE(5) OVER (ORDER BY hhi_concentration)
    ) / 2.0, 2)                             AS fossil_dependency_score,

    -- fossil backup dependency: high late fossil + renewable growth + gas cv
    ROUND((
        NTILE(5) OVER (ORDER BY late_fossil_pct) +
        NTILE(5) OVER (ORDER BY variable_re_growth_pct) +
        NTILE(5) OVER (ORDER BY gas_cv_cost)
    ) / 3.0, 2)                             AS fossil_backup_dependency_score,

    -- transition opportunity: high renewable growth and late RE share
    ROUND((
        NTILE(5) OVER (ORDER BY variable_re_growth_pct) +
        NTILE(5) OVER (ORDER BY late_variable_re_pct)
    ) / 2.0, 2)                             AS transition_opportunity_score,

    CAST(NULL AS DECIMAL(3,1))              AS market_structure_score,
    CAST(NULL AS DECIMAL(3,1))              AS industrial_load_score,
    CAST(NULL AS DECIMAL(3,1))              AS storage_deployment_score,
    CAST(NULL AS DECIMAL(3,1))              AS reliability_score,
    CAST(NULL AS DECIMAL(3,1))              AS regulatory_receptiveness_score,
    CAST(NULL AS DECIMAL(3,1))              AS incentive_score
FROM integration_base;

-- STEP 3 | UPDATE EXTERNAL DIMENSION SCORES
-- market structure score from market_structure_ref
SET SQL_SAFE_UPDATES = 0;

UPDATE integration_scores s
JOIN market_structure_ref m ON s.state = m.state
SET s.market_structure_score = CASE
    WHEN m.iso_rto = 'ERCOT'                                       THEN 5
    WHEN m.market_structure = 'deregulated' 
         AND m.iso_rto != 'non_ISO'                                THEN 5
    WHEN m.market_structure = 'restricted' 
         AND m.iso_rto != 'non_ISO'                                THEN 4
    WHEN m.market_structure = 'regulated' 
         AND m.iso_rto != 'non_ISO'                                THEN 3
    WHEN m.market_structure = 'restricted' 
         AND m.iso_rto = 'non_ISO'                                 THEN 3
    WHEN m.market_structure = 'regulated' 
         AND m.iso_rto = 'non_ISO'                                 THEN 2
    ELSE 2
END;

-- industrial load score from module_d_industrial_load
UPDATE integration_scores s
JOIN (
    SELECT state,
        NTILE(5) OVER (ORDER BY industrial_pct) AS score
    FROM module_d_industrial_load
) t ON s.state = t.state
SET s.industrial_load_score = t.score;

-- storage deployment score | states with no storage get score of 1
UPDATE integration_scores s
LEFT JOIN (
    SELECT state,
        NTILE(5) OVER (ORDER BY total_discharge_mw) AS score
    FROM module_d_storage_deployment
) t ON s.state = t.state
SET s.storage_deployment_score = COALESCE(t.score, 1);

-- reliability score | higher SAIDI = worse reliability = higher BESS need
UPDATE integration_scores s
JOIN (
    SELECT state,
        NTILE(5) OVER (ORDER BY saidi_weighted_avg) AS score
    FROM module_d_reliability
) t ON s.state = t.state
SET s.reliability_score = t.score;

-- regulatory receptiveness score | higher EE savings = more active regulatory environment
UPDATE integration_scores s
JOIN (
    SELECT state,
        NTILE(5) OVER (ORDER BY ee_savings_mwh) AS score
    FROM module_d_regulatory_receptiveness
) t ON s.state = t.state
SET s.regulatory_receptiveness_score = t.score;

-- incentive score from DSIRE manual build
UPDATE integration_scores s
JOIN raw_dsire_incentive_scores d ON s.state = d.state
SET s.incentive_score = d.incentive_score;

SET SQL_SAFE_UPDATES = 1;

-- STEP 4 | FINAL GRID SCALE TABLE
-- 11 dimensions, equal weight, fixed divisor

DROP TABLE IF EXISTS integration_final_grid;

CREATE TABLE integration_final_grid AS
SELECT
    i.state,
    i.dominant_fuel_type,
    i.transition_status,
    i.concentration_class,
    i.gas_high_null_flag,
    ROUND(i.grid_stress_score, 2)                    AS grid_stress_score,
    ROUND(i.cost_volatility_score, 2)                AS cost_volatility_score,
    ROUND(i.fossil_dependency_score, 2)              AS fossil_dependency_score,
    ROUND(i.fossil_backup_dependency_score, 2)       AS fossil_backup_dependency_score,
    ROUND(i.transition_opportunity_score, 2)         AS transition_opportunity_score,
    ROUND(i.market_structure_score, 2)               AS market_structure_score,
    ROUND(i.industrial_load_score, 2)                AS industrial_load_score,
    ROUND(i.storage_deployment_score, 2)             AS storage_deployment_score,
    ROUND(i.reliability_score, 2)                    AS reliability_score,
    ROUND(i.regulatory_receptiveness_score, 2)       AS regulatory_receptiveness_score,
    ROUND(i.incentive_score, 2)                      AS incentive_score,
    ROUND((
        COALESCE(i.grid_stress_score, 0) +
        COALESCE(i.cost_volatility_score, 0) +
        COALESCE(i.fossil_dependency_score, 0) +
        COALESCE(i.fossil_backup_dependency_score, 0) +
        COALESCE(i.transition_opportunity_score, 0) +
        COALESCE(i.market_structure_score, 0) +
        COALESCE(i.industrial_load_score, 0) +
        COALESCE(i.storage_deployment_score, 0) +
        COALESCE(i.reliability_score, 0) +
        COALESCE(i.regulatory_receptiveness_score, 0) +
        COALESCE(i.incentive_score, 0)
    ) / 11.0, 2)                                     AS composite_score,
    RANK() OVER (ORDER BY (
        COALESCE(i.grid_stress_score, 0) +
        COALESCE(i.cost_volatility_score, 0) +
        COALESCE(i.fossil_dependency_score, 0) +
        COALESCE(i.fossil_backup_dependency_score, 0) +
        COALESCE(i.transition_opportunity_score, 0) +
        COALESCE(i.market_structure_score, 0) +
        COALESCE(i.industrial_load_score, 0) +
        COALESCE(i.storage_deployment_score, 0) +
        COALESCE(i.reliability_score, 0) +
        COALESCE(i.regulatory_receptiveness_score, 0) +
        COALESCE(i.incentive_score, 0)
    ) / 11.0 DESC)                                   AS opportunity_rank
FROM integration_scores i
ORDER BY opportunity_rank;

-- STEP 5 | FINAL RESIDENTIAL TABLE
-- 7 dimensions including residential_access_score and wholesale_complexity_score
-- business model pathway based on actual switching rates not regulatory classification

DROP TABLE IF EXISTS integration_final_residential;

CREATE TABLE integration_final_residential AS
SELECT
    e.state,
    e.residential_customers,
    e.avg_retail_price_per_mwh,
    e.avg_mwh_per_customer,
    ROUND(e.residential_price_score, 2)              AS residential_price_score,
    ROUND(e.residential_market_size_score, 2)        AS residential_market_size_score,
    ROUND(e.residential_consumption_score, 2)        AS residential_consumption_score,
    ROUND(e.reliability_score, 2)                    AS reliability_score,
    ROUND(e.market_structure_score, 2)               AS market_structure_score,
    ROUND(e.residential_access_score, 2)             AS residential_access_score,
    ROUND(e.wholesale_complexity_score, 2)           AS wholesale_complexity_score,
    ROUND(e.residential_composite_score, 2)          AS residential_composite_score,
    RANK() OVER (ORDER BY e.residential_composite_score DESC) AS opportunity_rank,
    CASE
        WHEN e.residential_access_score >= 4 
             AND e.wholesale_complexity_score >= 3 THEN 'Direct Retail Model'
        WHEN e.residential_access_score >= 3 
             AND e.wholesale_complexity_score >= 3 THEN 'Direct Retail — Limited Access'
        WHEN e.residential_access_score = 2         THEN 'C&I Access Only — Partnership for Residential'
        ELSE                                              'Utility Partnership Only'
    END                                              AS business_model
FROM module_e_residential_score e
JOIN integration_scores i ON e.state = i.state
ORDER BY opportunity_rank;

-- STEP 6 | FINAL C&I TABLE
-- 6 dimensions with 4 business model pathways including data center pipeline

DROP TABLE IF EXISTS integration_final_ci;

CREATE TABLE integration_final_ci AS
SELECT
    c.state,
    c.ci_customers,
    c.commercial_customers,
    c.industrial_customers,
    c.avg_ci_price_per_mwh,
    c.avg_mwh_per_ci_customer,
    ROUND(c.ci_price_score, 2)          AS ci_price_score,
    ROUND(c.ci_market_size_score, 2)    AS ci_market_size_score,
    ROUND(c.ci_consumption_score, 2)    AS ci_consumption_score,
    ROUND(c.reliability_score, 2)       AS reliability_score,
    ROUND(c.ci_access_score, 2)         AS ci_access_score,
    ROUND(c.dc_opportunity_score, 2)    AS dc_opportunity_score,
    ROUND(c.ci_composite_score, 2)      AS ci_composite_score,
    RANK() OVER (ORDER BY c.ci_composite_score DESC) AS opportunity_rank,
    CASE
        WHEN c.dc_opportunity_score >= 4
             AND c.ci_access_score >= 3
             THEN 'Direct C&I + Data Center Partnership'
        WHEN c.dc_opportunity_score >= 4
             AND c.ci_access_score < 3
             THEN 'Data Center Partnership'
        WHEN c.dc_opportunity_score < 4
             AND c.ci_access_score >= 3
             THEN 'Direct C&I Model'
        WHEN c.dc_opportunity_score < 4
             AND c.ci_access_score < 3
             AND d.dc_growth_flag = 'High'
             THEN 'Utility Partnership — Data Center Pipeline'
        ELSE 'Utility Partnership Only'
    END                                 AS business_model,
    d.dc_growth_flag
FROM module_f_ci_score c
JOIN module_f_dc_score d ON c.state = d.state
ORDER BY opportunity_rank;