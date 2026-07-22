-- ============================================
-- MODULE A2 | STATE LEVEL HOURLY METRICS
-- Aggregates BA level hourly metrics to state level
-- Weighted averages using avg_hourly_gen_mwh as weight
-- CV recalculated from weighted averages
-- Source: module_a_hourly_final, ba_state_mapping
-- Final table: module_a2_state_hourly_metrics
-- ============================================

CREATE TABLE module_a2_state_hourly_metrics AS
WITH ba_state AS (
    SELECT
        h.*,
        m.state
    FROM module_a_hourly_final h
    JOIN ba_state_mapping m
        ON h.balancing_authority_code_eia = m.balancing_authority_code_eia
),
state_weights AS (
    SELECT
        state,
        SUM(COALESCE(avg_hourly_gen_mwh, 0)) AS total_weight
    FROM ba_state
    GROUP BY state
)
SELECT
    b.state,
    SUM(b.avg_hourly_gen_mwh * b.avg_hourly_gen_mwh) / 
        NULLIF(SUM(b.avg_hourly_gen_mwh), 0)            AS avg_hourly_gen_mwh,
    SUM(b.std_dev_gen_mwh * b.avg_hourly_gen_mwh) / 
        NULLIF(SUM(b.avg_hourly_gen_mwh), 0)            AS std_dev_gen_mwh,
    MAX(b.max_hourly_gen_mwh)                           AS max_hourly_gen_mwh,
    MIN(b.min_hourly_gen_mwh)                           AS min_hourly_gen_mwh,
    MAX(b.max_hourly_gen_mwh) - MIN(b.min_hourly_gen_mwh) AS range_gen_mwh,
    SUM(b.avg_hourly_demand_mwh * b.avg_hourly_gen_mwh) / 
        NULLIF(SUM(b.avg_hourly_gen_mwh), 0)            AS avg_hourly_demand_mwh,
    SUM(b.std_dev_demand_mwh * b.avg_hourly_gen_mwh) / 
        NULLIF(SUM(b.avg_hourly_gen_mwh), 0)            AS std_dev_demand_mwh,
    MAX(b.max_hourly_demand_mwh)                        AS max_hourly_demand_mwh,
    MIN(b.min_hourly_demand_mwh)                        AS min_hourly_demand_mwh,
    SUM(b.avg_gap_mwh * b.avg_hourly_gen_mwh) / 
        NULLIF(SUM(b.avg_hourly_gen_mwh), 0)            AS avg_gap_mwh,
    SUM(b.std_dev_gap_mwh * b.avg_hourly_gen_mwh) / 
        NULLIF(SUM(b.avg_hourly_gen_mwh), 0)            AS std_dev_gap_mwh,
    MAX(b.max_surplus_mwh)                              AS max_surplus_mwh,
    MIN(b.max_deficit_mwh)                              AS max_deficit_mwh,
    SUM(b.avg_interchange_mwh * b.avg_hourly_gen_mwh) / 
        NULLIF(SUM(b.avg_hourly_gen_mwh), 0)            AS avg_interchange_mwh,
    SUM(b.std_dev_interchange_mwh * b.avg_hourly_gen_mwh) / 
        NULLIF(SUM(b.avg_hourly_gen_mwh), 0)            AS std_dev_interchange_mwh,
    MAX(b.max_interchange_mwh)                          AS max_interchange_mwh,
    MIN(b.min_interchange_mwh)                          AS min_interchange_mwh,
    SUM(b.avg_ramp_rate_mwh * b.avg_hourly_gen_mwh) / 
        NULLIF(SUM(b.avg_hourly_gen_mwh), 0)            AS avg_ramp_rate_mwh,
    MAX(b.max_ramp_rate_mwh)                            AS max_ramp_rate_mwh,
    SUM(b.std_dev_ramp_rate_mwh * b.avg_hourly_gen_mwh) / 
        NULLIF(SUM(b.avg_hourly_gen_mwh), 0)            AS std_dev_ramp_rate_mwh,
    SUM(b.avg_demand_ramp_mwh * b.avg_hourly_gen_mwh) / 
        NULLIF(SUM(b.avg_hourly_gen_mwh), 0)            AS avg_demand_ramp_mwh,
    MAX(b.max_demand_ramp_mwh)                          AS max_demand_ramp_mwh,
    SUM(b.std_dev_demand_ramp_mwh * b.avg_hourly_gen_mwh) / 
        NULLIF(SUM(b.avg_hourly_gen_mwh), 0)            AS std_dev_demand_ramp_mwh,
    SUM(b.avg_interchange_ramp_mwh * b.avg_hourly_gen_mwh) / 
        NULLIF(SUM(b.avg_hourly_gen_mwh), 0)            AS avg_interchange_ramp_mwh,
    MAX(b.max_interchange_ramp_mwh)                     AS max_interchange_ramp_mwh,
    SUM(b.std_dev_interchange_ramp_mwh * b.avg_hourly_gen_mwh) / 
        NULLIF(SUM(b.avg_hourly_gen_mwh), 0)            AS std_dev_interchange_ramp_mwh,
    CASE 
        WHEN SUM(b.avg_hourly_gen_mwh * b.avg_hourly_gen_mwh) / 
             NULLIF(SUM(b.avg_hourly_gen_mwh), 0) = 0 THEN NULL
        ELSE (SUM(b.std_dev_gen_mwh * b.avg_hourly_gen_mwh) / 
             NULLIF(SUM(b.avg_hourly_gen_mwh), 0)) /
             (SUM(b.avg_hourly_gen_mwh * b.avg_hourly_gen_mwh) / 
             NULLIF(SUM(b.avg_hourly_gen_mwh), 0))
    END                                                 AS cv_gen,
    CASE
        WHEN SUM(b.avg_hourly_demand_mwh * b.avg_hourly_gen_mwh) / 
             NULLIF(SUM(b.avg_hourly_gen_mwh), 0) = 0 THEN NULL
        ELSE (SUM(b.std_dev_demand_mwh * b.avg_hourly_gen_mwh) / 
             NULLIF(SUM(b.avg_hourly_gen_mwh), 0)) /
             (SUM(b.avg_hourly_demand_mwh * b.avg_hourly_gen_mwh) / 
             NULLIF(SUM(b.avg_hourly_gen_mwh), 0))
    END                                                 AS cv_demand,
    CASE
        WHEN SUM(b.avg_hourly_demand_mwh * b.avg_hourly_gen_mwh) / 
             NULLIF(SUM(b.avg_hourly_gen_mwh), 0) = 0 THEN NULL
        ELSE (SUM(b.std_dev_gap_mwh * b.avg_hourly_gen_mwh) / 
             NULLIF(SUM(b.avg_hourly_gen_mwh), 0)) /
             (SUM(b.avg_hourly_demand_mwh * b.avg_hourly_gen_mwh) / 
             NULLIF(SUM(b.avg_hourly_gen_mwh), 0))
    END                                                 AS cv_gap,
    MIN(b.null_count)                                   AS min_null_count
FROM ba_state b
JOIN state_weights w ON b.state = w.state
GROUP BY b.state
ORDER BY b.state;