-- ============================================
-- MODULE E | RESIDENTIAL MARKET
-- Sources: raw_eia861__yearly_sales, integration_scores,
--          market_structure_ref
-- Final tables: module_e_residential_market,
--               module_e_residential_score
-- ============================================

CREATE TABLE module_e_residential_market AS
SELECT
    state,
    ROUND(SUM(customers), 0)                                        AS residential_customers,
    ROUND(SUM(sales_mwh), 0)                                        AS residential_mwh,
    ROUND(SUM(sales_revenue), 0)                                    AS residential_revenue,
    ROUND(SUM(sales_revenue) / NULLIF(SUM(sales_mwh), 0), 2)       AS avg_retail_price_per_mwh,
    ROUND(SUM(sales_mwh) / NULLIF(SUM(customers), 0), 2)           AS avg_mwh_per_customer
FROM raw_eia861__yearly_sales
WHERE YEAR(report_date) = 2024
    AND customer_class = 'residential'
    AND state NOT IN ('AK', 'HI', 'PR')
GROUP BY state
ORDER BY residential_customers DESC;

ALTER TABLE market_structure_ref
    ADD COLUMN residential_access_score  INT NULL,
    ADD COLUMN wholesale_complexity_score INT NULL;

SET SQL_SAFE_UPDATES = 0;

UPDATE market_structure_ref SET residential_access_score =
    CASE
        WHEN state IN ('TX','OH','PA','IL','NH','RI','MA') THEN 5
        WHEN state IN ('NY','NJ','MD','CT','ME','DC')      THEN 4
        WHEN state IN ('DE')                               THEN 3
        WHEN state IN ('OR','NV','CA')                     THEN 2
        ELSE                                                    1
    END;

UPDATE market_structure_ref SET wholesale_complexity_score =
    CASE
        WHEN iso_rto = 'ERCOT'                             THEN 5
        WHEN iso_rto IN ('PJM','MISO','NYISO','ISO_NE')    THEN 3
        ELSE                                                    1
    END;

SET SQL_SAFE_UPDATES = 1;

CREATE TABLE module_e_residential_score AS
SELECT
    e.state,
    e.residential_customers,
    e.avg_retail_price_per_mwh,
    e.avg_mwh_per_customer,
    e.residential_mwh,
    NTILE(5) OVER (ORDER BY e.avg_retail_price_per_mwh)        AS residential_price_score,
    NTILE(5) OVER (ORDER BY e.residential_customers)           AS residential_market_size_score,
    NTILE(5) OVER (ORDER BY e.avg_mwh_per_customer)            AS residential_consumption_score,
    i.reliability_score,
    i.market_structure_score,
    m.residential_access_score,
    m.wholesale_complexity_score,
    ROUND((
        NTILE(5) OVER (ORDER BY e.avg_retail_price_per_mwh) +
        NTILE(5) OVER (ORDER BY e.residential_customers) +
        NTILE(5) OVER (ORDER BY e.avg_mwh_per_customer) +
        i.reliability_score +
        i.market_structure_score +
        m.residential_access_score +
        m.wholesale_complexity_score
    ) / 7.0, 2)                                                AS residential_composite_score
FROM module_e_residential_market e
JOIN integration_scores i ON e.state = i.state
JOIN market_structure_ref m ON e.state = m.state
ORDER BY residential_composite_score DESC;