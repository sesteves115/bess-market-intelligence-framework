-- ============================================
-- MODULE F | C&I AND DATA CENTER MARKET
-- Sources: raw_dc_metrics, raw_eia861__yearly_sales,
--          market_structure_ref, integration_scores,
--          module_f_dc_score
-- Final tables: module_f_dc_score, module_f_ci_market,
--               module_f_ci_score
-- ============================================

-- data center composite score
-- dc_growth_flag manually verified and corrected post-build
CREATE TABLE module_f_dc_score AS
WITH base AS (
    SELECT
        d.state,
        d.dc_facilities,
        d.dc_twh_per_year,
        d.dc_inventory_mw,
        d.dc_announced_investment_usd_b,
        d.dc_under_construction_mw,
        d.dc_grid_constraint_flag,
        d.dc_fossil_delay_flag,
        d.dc_onsite_gen_flag,
        d.major_hubs,
        d.major_operators,
        m.iso_rto,
        CASE
            WHEN COALESCE(d.dc_announced_investment_usd_b, 0) >= 5
                 OR COALESCE(d.dc_under_construction_mw, 0) >= 500
                 OR (COALESCE(d.dc_grid_constraint_flag, 0) +
                     COALESCE(d.dc_fossil_delay_flag, 0) +
                     COALESCE(d.dc_onsite_gen_flag, 0)) >= 2
                 THEN 'High'
            WHEN COALESCE(d.dc_announced_investment_usd_b, 0) BETWEEN 1 AND 4.9
                 OR (COALESCE(d.dc_grid_constraint_flag, 0) +
                     COALESCE(d.dc_fossil_delay_flag, 0) +
                     COALESCE(d.dc_onsite_gen_flag, 0)) = 1
                 THEN 'Medium'
            ELSE 'Low'
        END AS dc_growth_flag,
        CASE
            WHEN d.dc_twh_per_year < 0.5 THEN 0
            ELSE
                COALESCE(d.dc_grid_constraint_flag, 0) * 3 +
                COALESCE(d.dc_fossil_delay_flag, 0) * 2 +
                COALESCE(d.dc_onsite_gen_flag, 0) * 2 +
                CASE m.iso_rto
                    WHEN 'PJM'    THEN 2
                    WHEN 'MISO'   THEN 1
                    WHEN 'ISO_NE' THEN 1
                    WHEN 'NYISO'  THEN 1
                    WHEN 'ERCOT'  THEN 0
                    ELSE 0
                END
        END AS constraint_raw
    FROM raw_dc_metrics d
    JOIN market_structure_ref m ON d.state = m.state
)
SELECT
    state,
    dc_facilities,
    dc_twh_per_year,
    dc_inventory_mw,
    dc_announced_investment_usd_b,
    dc_grid_constraint_flag,
    dc_fossil_delay_flag,
    dc_onsite_gen_flag,
    major_hubs,
    major_operators,
    dc_growth_flag,
    NTILE(5) OVER (ORDER BY dc_twh_per_year)     AS dc_capacity_score,
    NTILE(5) OVER (ORDER BY dc_facilities)       AS dc_facilities_score,
    NTILE(5) OVER (ORDER BY constraint_raw)      AS dc_power_constraint_score,
    ROUND((
        NTILE(5) OVER (ORDER BY dc_twh_per_year) +
        NTILE(5) OVER (ORDER BY dc_facilities) +
        NTILE(5) OVER (ORDER BY constraint_raw)
    ) / 3.0, 2)                                  AS dc_composite_score
FROM base
ORDER BY dc_composite_score DESC, dc_twh_per_year DESC;

-- manual dc_growth_flag corrections after research verification
SET SQL_SAFE_UPDATES = 0;

UPDATE module_f_dc_score SET dc_growth_flag = 'High'
WHERE state IN ('VA', 'IL', 'NJ', 'WA', 'IA');

UPDATE module_f_dc_score SET dc_growth_flag = 'Medium'
WHERE state = 'CA';

SET SQL_SAFE_UPDATES = 1;

-- C&I market base table
CREATE TABLE module_f_ci_market AS
SELECT
    state,
    SUM(CASE WHEN customer_class = 'commercial' THEN customers ELSE 0 END)      AS commercial_customers,
    SUM(CASE WHEN customer_class = 'commercial' THEN sales_mwh ELSE 0 END)      AS commercial_mwh,
    SUM(CASE WHEN customer_class = 'commercial' THEN sales_revenue ELSE 0 END)  AS commercial_revenue,
    SUM(CASE WHEN customer_class = 'industrial' THEN customers ELSE 0 END)      AS industrial_customers,
    SUM(CASE WHEN customer_class = 'industrial' THEN sales_mwh ELSE 0 END)      AS industrial_mwh,
    SUM(CASE WHEN customer_class = 'industrial' THEN sales_revenue ELSE 0 END)  AS industrial_revenue,
    SUM(CASE WHEN customer_class IN ('commercial','industrial') THEN customers ELSE 0 END)      AS ci_customers,
    SUM(CASE WHEN customer_class IN ('commercial','industrial') THEN sales_mwh ELSE 0 END)      AS ci_mwh,
    SUM(CASE WHEN customer_class IN ('commercial','industrial') THEN sales_revenue ELSE 0 END)  AS ci_revenue
FROM raw_eia861__yearly_sales
WHERE YEAR(report_date) = 2024
  AND state != 'US'
GROUP BY state
HAVING state IN (
    SELECT DISTINCT state FROM integration_scores
)
ORDER BY state;

-- derived price and consumption metrics
ALTER TABLE module_f_ci_market
    ADD COLUMN avg_commercial_price_per_mwh       DOUBLE,
    ADD COLUMN avg_industrial_price_per_mwh       DOUBLE,
    ADD COLUMN avg_ci_price_per_mwh               DOUBLE,
    ADD COLUMN avg_mwh_per_commercial_customer    DOUBLE,
    ADD COLUMN avg_mwh_per_industrial_customer    DOUBLE,
    ADD COLUMN avg_mwh_per_ci_customer            DOUBLE;

SET SQL_SAFE_UPDATES = 0;

UPDATE module_f_ci_market
SET
    avg_commercial_price_per_mwh    = CASE WHEN commercial_mwh > 0 
                                          THEN commercial_revenue / commercial_mwh 
                                          ELSE NULL END,
    avg_industrial_price_per_mwh    = CASE WHEN industrial_mwh > 0 
                                          THEN industrial_revenue / industrial_mwh 
                                          ELSE NULL END,
    avg_ci_price_per_mwh            = CASE WHEN ci_mwh > 0 
                                          THEN ci_revenue / ci_mwh 
                                          ELSE NULL END,
    avg_mwh_per_commercial_customer = CASE WHEN commercial_customers > 0 
                                          THEN commercial_mwh / commercial_customers 
                                          ELSE NULL END,
    avg_mwh_per_industrial_customer = CASE WHEN industrial_customers > 0 
                                          THEN industrial_mwh / industrial_customers 
                                          ELSE NULL END,
    avg_mwh_per_ci_customer         = CASE WHEN ci_customers > 0 
                                          THEN ci_mwh / ci_customers 
                                          ELSE NULL END;

SET SQL_SAFE_UPDATES = 1;

-- C&I composite score | 6 dimensions equal weight
CREATE TABLE module_f_ci_score AS
SELECT
    c.state,
    c.ci_customers,
    c.avg_ci_price_per_mwh,
    c.avg_mwh_per_ci_customer,
    c.commercial_customers,
    c.industrial_customers,
    NTILE(5) OVER (ORDER BY c.avg_ci_price_per_mwh)           AS ci_price_score,
    NTILE(5) OVER (ORDER BY c.ci_customers)                   AS ci_market_size_score,
    NTILE(5) OVER (ORDER BY c.avg_mwh_per_ci_customer)        AS ci_consumption_score,
    i.reliability_score,
    CASE
        WHEN m.ci_choice_pct >= 50  THEN 5
        WHEN m.ci_choice_pct >= 30  THEN 4
        WHEN m.ci_choice_pct >= 15  THEN 3
        WHEN m.ci_choice_pct >= 5   THEN 2
        ELSE 1
    END                                                        AS ci_access_score,
    d.dc_composite_score                                       AS dc_opportunity_score,
    ROUND((
        NTILE(5) OVER (ORDER BY c.avg_ci_price_per_mwh) +
        NTILE(5) OVER (ORDER BY c.ci_customers) +
        NTILE(5) OVER (ORDER BY c.avg_mwh_per_ci_customer) +
        i.reliability_score +
        CASE
            WHEN m.ci_choice_pct >= 50  THEN 5
            WHEN m.ci_choice_pct >= 30  THEN 4
            WHEN m.ci_choice_pct >= 15  THEN 3
            WHEN m.ci_choice_pct >= 5   THEN 2
            ELSE 1
        END +
        d.dc_composite_score
    ) / 6.0, 2)                                               AS ci_composite_score
FROM module_f_ci_market c
JOIN integration_scores i  ON c.state = i.state
JOIN market_structure_ref m ON c.state = m.state
JOIN module_f_dc_score d   ON c.state = d.state
ORDER BY ci_composite_score DESC;