# BESS Market Intelligence Framework

A market intelligence framework identifying battery energy storage deployment opportunity across 49 scoreable U.S. states. Built on a MySQL analytical pipeline, Python spatial analysis, and an interactive Power BI dashboard.

## Overview

This project produces three parallel composite scoring models covering grid-scale, residential, and commercial and industrial BESS deployment markets. Each model surfaces business model pathway recommendations, regulatory access conditions, and market entry strategies by state. A fourth analytical layer covers the cooperative channel, identifying electric cooperatives as a distinct deployment pathway grounded in NREL cooperative modernization research and a USC Marshall 2026 study on data center load growth and cooperative electricity prices.

The pipeline processes over 10 million rows of EIA and PUDL federal energy data across six analytical modules covering grid stress, fuel cost volatility, market concentration, renewable transition trajectories, reliability, and retail market access.

## Data Sources

- EIA-923 Monthly Generation and Fuel Consumption
- EIA-930 Hourly Electric Grid Monitor
- EIA-860 Annual Electric Generator Report
- EIA-861 Annual Electric Power Industry Report
- PUDL Public Utility Data Liberation Project
- DSIRE Database of State Incentives for Renewables and Efficiency
- HIFLD Homeland Infrastructure Foundation-Level Data cooperative service territory shapefiles
- PNNL Open Source Data Center Atlas
- DOE OSTI Projected Data Center Location Models

## Key Analytical Decisions

The cooperative spatial join filtered to cooperative polygons only before running, which eliminated investor-owned utility envelope overlap concerns entirely. The deduplication fix for Texas overlapping HIFLD polygons was identified analytically and applied before aggregation.

The scoring methodology calibrates every threshold to observed data distribution rather than industry standards. Traffic light opportunity signal thresholds differ by composite because the residential market is structurally harder than grid-scale and applying uniform cutoffs would misrepresent opportunity tiers.

The Michigan retail access correction flags states where formal deregulation does not reflect practical market accessibility, implemented as a calculated column in Power BI using the gap between market structure score and residential access score.

## Outputs

Interactive Power BI dashboard:
https://app.powerbi.com/view?r=eyJrIjoiY2Y0ZmI3N2EtMGUyMS00YzliLWFjZDYtYjZjMzdjNjEyZTQwIiwidCI6IjY4NGVmMGQ1LTExNjMtNDljMS05MjM3LTA3N2U3NmJmMDA1ZSJ9&pageName=d775b3f81470abcd46c0

Full technical methodology and documentation:
https://quaint-scapula-529.notion.site/Sebastian-Esteves-PORTFOLIO-69faab345a588384b75301afea8239eb

Published analysis and industry thinking:
https://sesteves115.medium.com/

## Author

Sebastian Esteves
M.S. Financial Analytics, University of South Florida, May 2026
linkedin.com/in/sebastian-esteves

## License

Creative Commons BY-NC-ND 4.0
