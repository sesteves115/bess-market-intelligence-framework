USE bess_project;

-- ============================================
-- MODULE A1 | GRID STRESS
-- Sources: out_eia923__monthly_generation_fuel_combined
--          out_eia__monthly_generators
--          out_eia930__hourly_operations
--          module_a_additional_ramps (loaded via ramp_rates_demand_interchange.py)
-- Final tables: module_a_base, module_a_monthly_metrics,
--               ba_state_mapping, module_a_hourly_final
-- ============================================

-- total generation by state, fuel type, and month
CREATE TABLE module_a_base AS
SELECT 
    g.state,
    c.fuel_type_code_pudl,
    DATE_FORMAT(c.report_date, '%Y-%m') AS period,
    SUM(c.net_generation_mwh) AS monthly_gen_mwh
FROM out_eia923__monthly_generation_fuel_combined c
JOIN out_eia__monthly_generators g
    ON c.plant_id_eia = g.plant_id_eia
    AND c.report_date = g.report_date
WHERE c.report_date >= '2019-01-01'
    AND g.state IS NOT NULL
GROUP BY g.state, c.fuel_type_code_pudl, period;

-- volume, variability, fuel shares, and capacity factors by state and fuel type
CREATE TABLE module_a_monthly_metrics AS
WITH volume AS (
    SELECT
        state,
        fuel_type_code_pudl,
        SUM(monthly_gen_mwh)    AS total_gen_mwh,
        AVG(monthly_gen_mwh)    AS avg_monthly_gen_mwh,
        MAX(monthly_gen_mwh)    AS max_monthly_gen_mwh,
        MIN(monthly_gen_mwh)    AS min_monthly_gen_mwh
    FROM module_a_base
    GROUP BY state, fuel_type_code_pudl
),
variability AS (
    SELECT
        state,
        fuel_type_code_pudl,
        STDDEV(monthly_gen_mwh)                         AS std_dev_gen_mwh,
        MAX(monthly_gen_mwh) - MIN(monthly_gen_mwh)     AS range_gen_mwh,
        CASE 
            WHEN AVG(monthly_gen_mwh) = 0 THEN NULL
            ELSE STDDEV(monthly_gen_mwh) / AVG(monthly_gen_mwh)
        END AS coefficient_of_variation
    FROM module_a_base
    GROUP BY state, fuel_type_code_pudl
),
state_total AS (
    SELECT
        state,
        SUM(total_gen_mwh) AS state_total_gen_mwh
    FROM volume
    GROUP BY state
),
share_numerators AS (
    SELECT
        v.state,
        v.fuel_type_code_pudl,
        v.total_gen_mwh,
        st.state_total_gen_mwh,
        v.total_gen_mwh / st.state_total_gen_mwh AS fuel_share,
        SUM(CASE WHEN v.fuel_type_code_pudl IN ('solar','wind','hydro') 
            THEN v.total_gen_mwh ELSE 0 END) 
            OVER (PARTITION BY v.state) AS renewable_gen,
        SUM(CASE WHEN v.fuel_type_code_pudl IN ('solar','wind') 
            THEN v.total_gen_mwh ELSE 0 END) 
            OVER (PARTITION BY v.state) AS variable_renewable_gen,
        SUM(CASE WHEN v.fuel_type_code_pudl IN ('gas','coal','oil') 
            THEN v.total_gen_mwh ELSE 0 END) 
            OVER (PARTITION BY v.state) AS fossil_gen
    FROM volume v
    JOIN state_total st ON v.state = st.state
),
shares AS (
    SELECT
        state,
        fuel_type_code_pudl,
        fuel_share,
        renewable_gen / state_total_gen_mwh          AS renewable_share,
        variable_renewable_gen / state_total_gen_mwh  AS variable_renewable_share,
        fossil_gen / state_total_gen_mwh              AS fossil_share
    FROM share_numerators
),
capacity AS (
    SELECT
        state,
        fuel_type_code_pudl,
        AVG(capacity_factor) AS avg_capacity_factor
    FROM out_eia__monthly_generators
    WHERE report_date >= '2019-01-01'
        AND state IS NOT NULL
    GROUP BY state, fuel_type_code_pudl
)
SELECT
    v.state,
    v.fuel_type_code_pudl,
    v.total_gen_mwh,
    v.avg_monthly_gen_mwh,
    v.max_monthly_gen_mwh,
    v.min_monthly_gen_mwh,
    var.std_dev_gen_mwh,
    var.range_gen_mwh,
    var.coefficient_of_variation,
    s.fuel_share,
    s.renewable_share,
    s.variable_renewable_share,
    s.fossil_share,
    c.avg_capacity_factor
FROM volume v
JOIN variability var 
    ON v.state = var.state 
    AND v.fuel_type_code_pudl = var.fuel_type_code_pudl
JOIN shares s 
    ON v.state = s.state 
    AND v.fuel_type_code_pudl = s.fuel_type_code_pudl
LEFT JOIN capacity c 
    ON v.state = c.state 
    AND v.fuel_type_code_pudl = c.fuel_type_code_pudl
ORDER BY v.state, v.fuel_type_code_pudl;

-- BA to state reference table
CREATE TABLE ba_state_mapping AS
SELECT DISTINCT 
    balancing_authority_code_eia,
    state
FROM out_eia__monthly_generators
WHERE balancing_authority_code_eia IS NOT NULL
ORDER BY balancing_authority_code_eia;

-- hour-over-hour generation ramp rates by BA using LAG
-- intermediate table, dropped after module_a_hourly_final is built
CREATE TABLE module_a_ramp_rates AS
WITH hourly_with_lag AS (
    SELECT
        balancing_authority_code_eia,
        datetime_utc,
        net_generation_imputed_eia_mwh,
        LAG(net_generation_imputed_eia_mwh) OVER (
            PARTITION BY balancing_authority_code_eia 
            ORDER BY datetime_utc
        ) AS prev_hour_gen_mwh
    FROM out_eia930__hourly_operations
    WHERE datetime_utc >= '2019-01-01'
),
ramp AS (
    SELECT
        balancing_authority_code_eia,
        ABS(net_generation_imputed_eia_mwh - prev_hour_gen_mwh) AS hourly_ramp_mwh
    FROM hourly_with_lag
    WHERE prev_hour_gen_mwh IS NOT NULL
)
SELECT
    balancing_authority_code_eia,
    AVG(hourly_ramp_mwh)    AS avg_ramp_rate_mwh,
    MAX(hourly_ramp_mwh)    AS max_ramp_rate_mwh,
    STDDEV(hourly_ramp_mwh) AS std_dev_ramp_rate_mwh
FROM ramp
GROUP BY balancing_authority_code_eia;

-- run ramp_rates_demand_interchange.py before continuing
-- to load module_a_additional_ramps

-- hourly variability, ramp rates, demand and interchange ramps by BA
-- null_count flags BAs with incomplete data
CREATE TABLE module_a_hourly_final AS
SELECT
    h.balancing_authority_code_eia,
    AVG(h.net_generation_imputed_eia_mwh)                                           AS avg_hourly_gen_mwh,
    STDDEV(h.net_generation_imputed_eia_mwh)                                        AS std_dev_gen_mwh,
    MAX(h.net_generation_imputed_eia_mwh)                                           AS max_hourly_gen_mwh,
    MIN(h.net_generation_imputed_eia_mwh)                                           AS min_hourly_gen_mwh,
    MAX(h.net_generation_imputed_eia_mwh) - MIN(h.net_generation_imputed_eia_mwh)   AS range_gen_mwh,
    CASE 
        WHEN AVG(h.net_generation_imputed_eia_mwh) = 0 THEN NULL
        ELSE STDDEV(h.net_generation_imputed_eia_mwh) / AVG(h.net_generation_imputed_eia_mwh)
    END                                                                             AS cv_gen,
    AVG(h.demand_imputed_pudl_mwh)                                                  AS avg_hourly_demand_mwh,
    STDDEV(h.demand_imputed_pudl_mwh)                                               AS std_dev_demand_mwh,
    MAX(h.demand_imputed_pudl_mwh)                                                  AS max_hourly_demand_mwh,
    MIN(h.demand_imputed_pudl_mwh)                                                  AS min_hourly_demand_mwh,
    CASE 
        WHEN AVG(h.demand_imputed_pudl_mwh) = 0 THEN NULL
        ELSE STDDEV(h.demand_imputed_pudl_mwh) / AVG(h.demand_imputed_pudl_mwh)
    END                                                                             AS cv_demand,
    AVG(h.net_generation_imputed_eia_mwh - h.demand_imputed_pudl_mwh)              AS avg_gap_mwh,
    STDDEV(h.net_generation_imputed_eia_mwh - h.demand_imputed_pudl_mwh)           AS std_dev_gap_mwh,
    MAX(h.net_generation_imputed_eia_mwh - h.demand_imputed_pudl_mwh)              AS max_surplus_mwh,
    MIN(h.net_generation_imputed_eia_mwh - h.demand_imputed_pudl_mwh)              AS max_deficit_mwh,
    CASE
        WHEN AVG(h.demand_imputed_pudl_mwh) = 0 THEN NULL
        ELSE STDDEV(h.net_generation_imputed_eia_mwh - h.demand_imputed_pudl_mwh) 
             / AVG(h.demand_imputed_pudl_mwh)
    END                                                                             AS cv_gap,
    AVG(h.interchange_adjusted_mwh)                                                 AS avg_interchange_mwh,
    STDDEV(h.interchange_adjusted_mwh)                                              AS std_dev_interchange_mwh,
    MAX(h.interchange_adjusted_mwh)                                                 AS max_interchange_mwh,
    MIN(h.interchange_adjusted_mwh)                                                 AS min_interchange_mwh,
    CASE
        WHEN AVG(h.interchange_adjusted_mwh) = 0 THEN NULL
        ELSE STDDEV(h.interchange_adjusted_mwh) / AVG(h.interchange_adjusted_mwh)
    END                                                                             AS cv_interchange,
    r.avg_ramp_rate_mwh,
    r.max_ramp_rate_mwh,
    r.std_dev_ramp_rate_mwh,
    a.avg_demand_ramp_mwh,
    a.max_demand_ramp_mwh,
    a.std_dev_demand_ramp_mwh,
    a.avg_interchange_ramp_mwh,
    a.max_interchange_ramp_mwh,
    a.std_dev_interchange_ramp_mwh,
    (CASE WHEN AVG(h.net_generation_imputed_eia_mwh) IS NULL THEN 1 ELSE 0 END +
     CASE WHEN AVG(h.demand_imputed_pudl_mwh) IS NULL THEN 1 ELSE 0 END +
     CASE WHEN AVG(h.net_generation_imputed_eia_mwh - h.demand_imputed_pudl_mwh) IS NULL THEN 1 ELSE 0 END +
     CASE WHEN r.avg_ramp_rate_mwh IS NULL THEN 1 ELSE 0 END +
     CASE WHEN a.avg_demand_ramp_mwh IS NULL THEN 1 ELSE 0 END) AS null_count
FROM out_eia930__hourly_operations h
LEFT JOIN module_a_ramp_rates r
    ON h.balancing_authority_code_eia = r.balancing_authority_code_eia
LEFT JOIN module_a_additional_ramps a
    ON h.balancing_authority_code_eia = a.balancing_authority_code_eia
WHERE h.datetime_utc >= '2019-01-01'
GROUP BY
    h.balancing_authority_code_eia,
    r.avg_ramp_rate_mwh, r.max_ramp_rate_mwh, r.std_dev_ramp_rate_mwh,
    a.avg_demand_ramp_mwh, a.max_demand_ramp_mwh, a.std_dev_demand_ramp_mwh,
    a.avg_interchange_ramp_mwh, a.max_interchange_ramp_mwh, a.std_dev_interchange_ramp_mwh
ORDER BY null_count ASC;

DROP TABLE module_a_ramp_rates;
DROP TABLE module_a_additional_ramps;