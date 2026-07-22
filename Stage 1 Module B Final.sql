-- ============================================
-- MODULE B | FUEL COST DYNAMICS
-- Sources: out_eia923__monthly_fuel_receipts_costs
-- Final tables: module_b_base, module_b_cost_per_mwh,
--               module_b_metrics, module_b_cost_spread
-- ============================================

-- volume-weighted average cost per MMBtu by state, fuel type, and month
-- SUM(total_fuel_cost) / SUM(fuel_consumed_mmbtu) corrects distortion
-- from low-volume extreme-price records (Virginia gas October 2021 case)
CREATE TABLE module_b_base AS
SELECT
    state,
    fuel_type_code_pudl,
    DATE_FORMAT(report_date, '%Y-%m')               AS period,
    SUM(total_fuel_cost) / 
        NULLIF(SUM(fuel_consumed_mmbtu), 0)         AS avg_cost_per_mmbtu,
    MIN(fuel_cost_per_mmbtu)                        AS min_cost_per_mmbtu,
    MAX(fuel_cost_per_mmbtu)                        AS max_cost_per_mmbtu,
    SUM(fuel_consumed_mmbtu)                        AS total_fuel_consumed_mmbtu,
    SUM(total_fuel_cost)                            AS total_fuel_cost,
    COUNT(*)                                        AS record_count,
    SUM(CASE WHEN fuel_cost_per_mmbtu IS NULL 
             THEN 1 ELSE 0 END)                     AS null_cost_count
FROM out_eia923__monthly_fuel_receipts_costs
WHERE report_date >= '2019-01-01'
    AND state IS NOT NULL
GROUP BY state, fuel_type_code_pudl, period
ORDER BY state, fuel_type_code_pudl, period;

-- cost per MWh using benchmark heat rates by fuel type
-- gas: 7.0 mmbtu/mwh, coal: 10.5, oil: 11.0
CREATE TABLE module_b_cost_per_mwh AS
SELECT
    state,
    fuel_type_code_pudl,
    period,
    avg_cost_per_mmbtu,
    min_cost_per_mmbtu,
    max_cost_per_mmbtu,
    total_fuel_consumed_mmbtu,
    total_fuel_cost,
    record_count,
    null_cost_count,
    ROUND(null_cost_count * 100.0 / record_count, 1) AS null_pct,
    CASE
        WHEN fuel_type_code_pudl = 'gas'  THEN 7.0
        WHEN fuel_type_code_pudl = 'coal' THEN 10.5
        WHEN fuel_type_code_pudl = 'oil'  THEN 11.0
        ELSE NULL
    END AS benchmark_heat_rate,
    CASE
        WHEN fuel_type_code_pudl = 'gas'  THEN avg_cost_per_mmbtu * 7.0
        WHEN fuel_type_code_pudl = 'coal' THEN avg_cost_per_mmbtu * 10.5
        WHEN fuel_type_code_pudl = 'oil'  THEN avg_cost_per_mmbtu * 11.0
        ELSE NULL
    END AS est_cost_per_mwh
FROM module_b_base
WHERE avg_cost_per_mmbtu IS NOT NULL
ORDER BY state, fuel_type_code_pudl, period;

-- avg/min/max/stddev/cv of cost per MWh by state and fuel type
-- zeros excluded, high null combinations flagged
CREATE TABLE module_b_metrics AS
WITH clean_costs AS (
    SELECT *
    FROM module_b_cost_per_mwh
    WHERE est_cost_per_mwh > 0
)
SELECT
    state,
    fuel_type_code_pudl,
    COUNT(*)                                        AS month_count,
    ROUND(AVG(est_cost_per_mwh), 2)                 AS avg_cost_per_mwh,
    ROUND(MIN(est_cost_per_mwh), 2)                 AS min_cost_per_mwh,
    ROUND(MAX(est_cost_per_mwh), 2)                 AS max_cost_per_mwh,
    ROUND(STDDEV(est_cost_per_mwh), 2)              AS std_dev_cost_per_mwh,
    ROUND(MAX(est_cost_per_mwh) -
          MIN(est_cost_per_mwh), 2)                 AS cost_range_per_mwh,
    ROUND(STDDEV(est_cost_per_mwh) /
          NULLIF(AVG(est_cost_per_mwh), 0), 4)      AS cv_cost,
    ROUND(AVG(null_pct), 1)                         AS avg_null_pct,
    CASE WHEN AVG(null_pct) >= 40 THEN 1
         ELSE 0 END                                 AS high_null_flag
FROM clean_costs
GROUP BY state, fuel_type_code_pudl
ORDER BY state, fuel_type_code_pudl;

-- gas vs coal and gas vs oil spread per state
-- only where both fuels exist for that state
CREATE TABLE module_b_cost_spread AS
SELECT
    g.state,
    g.avg_cost_per_mwh                              AS gas_avg_cost_per_mwh,
    c.avg_cost_per_mwh                              AS coal_avg_cost_per_mwh,
    o.avg_cost_per_mwh                              AS oil_avg_cost_per_mwh,
    ROUND(g.avg_cost_per_mwh - 
          c.avg_cost_per_mwh, 2)                    AS gas_coal_spread,
    ROUND(g.avg_cost_per_mwh - 
          o.avg_cost_per_mwh, 2)                    AS gas_oil_spread,
    ROUND(o.avg_cost_per_mwh - 
          c.avg_cost_per_mwh, 2)                    AS oil_coal_spread,
    CASE WHEN g.high_null_flag = 1 
          OR c.high_null_flag = 1 
          OR o.high_null_flag = 1 
         THEN 1 ELSE 0 END                          AS any_high_null_flag
FROM module_b_metrics g
LEFT JOIN module_b_metrics c
    ON g.state = c.state AND c.fuel_type_code_pudl = 'coal'
LEFT JOIN module_b_metrics o
    ON g.state = o.state AND o.fuel_type_code_pudl = 'oil'
WHERE g.fuel_type_code_pudl = 'gas'
ORDER BY oil_coal_spread DESC;