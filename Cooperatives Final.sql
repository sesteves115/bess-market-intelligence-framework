-- ============================================
-- COOPERATIVES | UTILITY CHANNEL ANALYSIS
-- Sources: raw_eia861__yearly_sales,
--          module_d_reliability
-- Final tables: module_ref_cooperative_density
-- ============================================

-- cooperative customer and MWh share by state, cross-referenced with SAIDI
CREATE TABLE module_ref_cooperative_density AS
SELECT 
    s.state,
    ROUND(SUM(CASE WHEN s.entity_type = 'cooperative' 
                   THEN s.customers ELSE 0 END) / 
          SUM(s.customers) * 100, 1)              AS cooperative_customer_pct,
    ROUND(SUM(CASE WHEN s.entity_type = 'cooperative' 
                   THEN s.sales_mwh ELSE 0 END) / 
          SUM(s.sales_mwh) * 100, 1)              AS cooperative_mwh_pct,
    r.saidi_weighted_avg
FROM raw_eia861__yearly_sales s
JOIN module_d_reliability r ON s.state = r.state
WHERE YEAR(s.report_date) = 2024
  AND s.state != 'US'
GROUP BY s.state, r.saidi_weighted_avg
HAVING SUM(s.customers) > 0
ORDER BY cooperative_customer_pct DESC;