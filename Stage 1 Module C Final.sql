-- ============================================
-- MODULE C | MARKET CONCENTRATION AND RENEWABLE TRANSITION
-- Sources: module_a_base, module_a_monthly_metrics
-- Final tables: module_c_concentration, module_c_renewable_trend,
--               module_c_summary, module_c_fuel_share
-- ============================================

-- HHI concentration index by state
-- sum of squared fuel shares: closer to 1 = highly concentrated, closer to 0 = diversified
CREATE TABLE module_c_concentration AS
SELECT
    state,
    ROUND(SUM(fuel_share * fuel_share), 4)      AS hhi_concentration,
    COUNT(fuel_type_code_pudl)                  AS fuel_type_count,
    MAX(fuel_share)                             AS dominant_fuel_share,
    MAX(CASE WHEN fuel_share = 
        (SELECT MAX(f2.fuel_share) 
         FROM module_a_monthly_metrics f2 
         WHERE f2.state = f1.state)
        THEN fuel_type_code_pudl END)           AS dominant_fuel_type
FROM module_a_monthly_metrics f1
GROUP BY state
ORDER BY hhi_concentration DESC;

-- renewable and fossil share trend comparing 2019-2021 vs 2022-2024
CREATE TABLE module_c_renewable_trend AS
WITH annual_gen AS (
    SELECT
        state,
        LEFT(period, 4)                         AS year,
        SUM(monthly_gen_mwh)                    AS total_gen_mwh,
        SUM(CASE WHEN fuel_type_code_pudl 
            IN ('solar','wind') 
            THEN monthly_gen_mwh ELSE 0 END)    AS variable_re_gen_mwh,
        SUM(CASE WHEN fuel_type_code_pudl 
            IN ('solar','wind','hydro') 
            THEN monthly_gen_mwh ELSE 0 END)    AS total_re_gen_mwh,
        SUM(CASE WHEN fuel_type_code_pudl 
            IN ('gas','coal','oil') 
            THEN monthly_gen_mwh ELSE 0 END)    AS fossil_gen_mwh
    FROM module_a_base
    GROUP BY state, year
),
annual_shares AS (
    SELECT
        state,
        year,
        ROUND(variable_re_gen_mwh / 
            NULLIF(total_gen_mwh, 0), 4)        AS variable_re_share,
        ROUND(total_re_gen_mwh / 
            NULLIF(total_gen_mwh, 0), 4)        AS total_re_share,
        ROUND(fossil_gen_mwh / 
            NULLIF(total_gen_mwh, 0), 4)        AS fossil_share
    FROM annual_gen
),
early_period AS (
    SELECT state,
        AVG(variable_re_share)                  AS early_variable_re_share,
        AVG(total_re_share)                     AS early_total_re_share,
        AVG(fossil_share)                       AS early_fossil_share
    FROM annual_shares
    WHERE year IN ('2019','2020','2021')
    GROUP BY state
),
late_period AS (
    SELECT state,
        AVG(variable_re_share)                  AS late_variable_re_share,
        AVG(total_re_share)                     AS late_total_re_share,
        AVG(fossil_share)                       AS late_fossil_share
    FROM annual_shares
    WHERE year IN ('2022','2023','2024')
    GROUP BY state
)
SELECT
    e.state,
    ROUND(e.early_variable_re_share, 4)         AS early_variable_re_share,
    ROUND(l.late_variable_re_share, 4)          AS late_variable_re_share,
    ROUND(l.late_variable_re_share - 
          e.early_variable_re_share, 4)         AS variable_re_growth,
    ROUND(e.early_total_re_share, 4)            AS early_total_re_share,
    ROUND(l.late_total_re_share, 4)             AS late_total_re_share,
    ROUND(l.late_total_re_share - 
          e.early_total_re_share, 4)            AS total_re_growth,
    ROUND(e.early_fossil_share, 4)              AS early_fossil_share,
    ROUND(l.late_fossil_share, 4)               AS late_fossil_share,
    ROUND(l.late_fossil_share - 
          e.early_fossil_share, 4)              AS fossil_share_change
FROM early_period e
JOIN late_period l ON e.state = l.state
ORDER BY variable_re_growth DESC;

-- summary table combining concentration and renewable trend
-- transition_status and concentration_class thresholds set relative to observed data distribution
CREATE TABLE module_c_summary AS
SELECT
    c.state,
    c.hhi_concentration,
    c.fuel_type_count,
    c.dominant_fuel_type,
    ROUND(c.dominant_fuel_share * 100, 1)           AS dominant_fuel_pct,
    ROUND(r.early_variable_re_share * 100, 1)       AS early_variable_re_pct,
    ROUND(r.late_variable_re_share * 100, 1)        AS late_variable_re_pct,
    ROUND(r.variable_re_growth * 100, 1)            AS variable_re_growth_pct,
    ROUND(r.early_total_re_share * 100, 1)          AS early_total_re_pct,
    ROUND(r.late_total_re_share * 100, 1)           AS late_total_re_pct,
    ROUND(r.total_re_growth * 100, 1)               AS total_re_growth_pct,
    ROUND(r.early_fossil_share * 100, 1)            AS early_fossil_pct,
    ROUND(r.late_fossil_share * 100, 1)             AS late_fossil_pct,
    ROUND(r.fossil_share_change * 100, 1)           AS fossil_change_pct,
    CASE
        WHEN r.variable_re_growth >= 0.05 
             AND r.fossil_share_change < 0      THEN 'rapid_transition'
        WHEN r.variable_re_growth >= 0.02 
             AND r.fossil_share_change < 0      THEN 'moderate_transition'
        WHEN r.variable_re_growth >= 0.02 
             AND r.fossil_share_change >= 0     THEN 'renewable_adding_not_replacing'
        WHEN r.variable_re_growth < 0.02 
             AND r.fossil_share_change < 0      THEN 'slow_transition'
        ELSE 'fossil_entrenched'
    END                                             AS transition_status,
    CASE
        WHEN c.hhi_concentration >= 0.7         THEN 'highly_concentrated'
        WHEN c.hhi_concentration >= 0.4         THEN 'moderately_concentrated'
        ELSE 'diversified'
    END                                             AS concentration_class
FROM module_c_concentration c
JOIN module_c_renewable_trend r ON c.state = r.state
ORDER BY r.variable_re_growth DESC;

-- fuel share by state and fuel type
CREATE TABLE module_c_fuel_share AS
SELECT
    state,
    fuel_type_code_pudl,
    ROUND(total_gen_mwh, 0)     AS total_fuel_gen_mwh,
    fuel_share
FROM module_a_monthly_metrics
ORDER BY state, fuel_type_code_pudl;