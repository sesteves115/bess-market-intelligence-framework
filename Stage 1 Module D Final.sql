-- ============================================
-- MODULE D | INFRASTRUCTURE AND POLICY
-- Sources: raw_eia860__storage_generators,
--          raw_eia861__yearly_sales,
--          raw_eia861__yearly_reliability,
--          raw_eia861__yearly_energy_efficiency,
--          raw_eia861__yearly_demand_response,
--          out_eia__monthly_generators
-- Final tables: module_d_industrial_load, module_d_storage_deployment,
--               module_d_reliability, module_d_regulatory_receptiveness
-- ============================================

-- industrial MWh as % of total state sales 2024
-- higher % = larger addressable BTM demand charge market
CREATE TABLE module_d_industrial_load AS
SELECT
    state,
    ROUND(SUM(CASE WHEN customer_class = 'industrial' THEN sales_mwh ELSE 0 END), 0) AS industrial_mwh,
    ROUND(SUM(CASE WHEN customer_class IN ('residential', 'commercial', 'industrial') THEN sales_mwh ELSE 0 END), 0) AS total_mwh,
    ROUND(
        SUM(CASE WHEN customer_class = 'industrial' THEN sales_mwh ELSE 0 END) /
        NULLIF(SUM(CASE WHEN customer_class IN ('residential', 'commercial', 'industrial') THEN sales_mwh ELSE 0 END), 0)
        * 100, 2
    ) AS industrial_pct
FROM raw_eia861__yearly_sales
WHERE YEAR(report_date) = 2024
    AND state NOT IN ('AK', 'HI', 'PR')
GROUP BY state
ORDER BY industrial_pct DESC;

-- state-level storage deployment 2024
-- use case breadth across arbitrage, frequency regulation, peak shaving, backup, spinning reserve
CREATE TABLE module_d_storage_deployment AS
SELECT
    p.state,
    COUNT(*)                                AS storage_units,
    ROUND(SUM(s.max_discharge_rate_mw), 0) AS total_discharge_mw,
    SUM(s.served_arbitrage)                 AS units_arbitrage,
    SUM(s.served_frequency_regulation)     AS units_freq_reg,
    SUM(s.served_system_peak_shaving)      AS units_peak_shaving,
    SUM(s.served_backup_power)             AS units_backup_power,
    SUM(s.served_ramping_spinning_reserve) AS units_spinning_reserve,
    (
        COALESCE(SUM(s.served_arbitrage), 0) +
        COALESCE(SUM(s.served_frequency_regulation), 0) +
        COALESCE(SUM(s.served_system_peak_shaving), 0) +
        COALESCE(SUM(s.served_backup_power), 0) +
        COALESCE(SUM(s.served_ramping_spinning_reserve), 0)
    )                                       AS total_use_case_activations
FROM raw_eia860__storage_generators s
JOIN (
    SELECT DISTINCT plant_id_eia, state
    FROM out_eia__monthly_generators
) p ON s.plant_id_eia = p.plant_id_eia
WHERE YEAR(s.report_date) = 2024
    AND p.state NOT IN ('AK', 'HI', 'PR')
GROUP BY p.state
ORDER BY storage_units DESC;

-- customer-weighted SAIDI average by state 2019-2024
-- excludes major storm events per IEEE standard
CREATE TABLE module_d_reliability AS
SELECT
    state,
    ROUND(
        SUM(saidi_wo_major_event_days_minutes * customers) /
        NULLIF(SUM(customers), 0)
    , 1) AS saidi_weighted_avg,
    SUM(customers) AS total_customers,
    COUNT(DISTINCT YEAR(report_date)) AS years_covered
FROM raw_eia861__yearly_reliability
WHERE standard = 'ieee_standard'
    AND saidi_wo_major_event_days_minutes IS NOT NULL
    AND customers > 0
    AND YEAR(report_date) BETWEEN 2019 AND 2024
    AND state NOT IN ('AK', 'HI', 'PR')
GROUP BY state
ORDER BY saidi_weighted_avg DESC;

-- energy efficiency and demand response by state 2024
-- higher EE savings and DR peak reduction = more active regulatory environment
CREATE TABLE module_d_regulatory_receptiveness AS
SELECT
    ee.state,
    ROUND(SUM(ee.incremental_energy_savings_mwh), 0)   AS ee_savings_mwh,
    ROUND(SUM(ee.incremental_peak_reduction_mw), 0)    AS ee_peak_reduction_mw,
    COALESCE(ROUND(SUM(dr.actual_peak_demand_savings_mw), 0), 0) AS dr_peak_reduction_mw,
    COALESCE(ROUND(SUM(dr.energy_savings_mwh), 0), 0)  AS dr_savings_mwh
FROM raw_eia861__yearly_energy_efficiency ee
LEFT JOIN raw_eia861__yearly_demand_response dr
    ON ee.state = dr.state
    AND ee.report_date = dr.report_date
    AND ee.utility_id_eia = dr.utility_id_eia
WHERE YEAR(ee.report_date) = 2024
    AND ee.state NOT IN ('AK', 'HI', 'PR')
GROUP BY ee.state
ORDER BY ee_savings_mwh DESC;