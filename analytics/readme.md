# Analytics

These SQL files support the three analytical questions. They are separate from dbt and read Gold tables in `pondolens.dev_gold`.

| Focus | Files |
|---|---|
| AP1 — Budget and spending by department | [Appropriations](q1_budget_and_spending_distribution/budget_department.sql) · [Obligations](q1_budget_and_spending_distribution/spending_department.sql) |
| AP2 — Spending compared with population | [Population and spending shares](q2_budget_and_population/population_budget_share_gap.sql) · [Per-person benchmark](q2_budget_and_population/regional_obligations_per_capita_benchmark.sql) |
| AP3 — Spending compared with GRDP per capita | [GRDP comparison](q3_budget_and_indicators/budget_vs_grdp.sql) |

Run these after a successful Gold build. Review target names before execution. Files with `%sql` are intended for Databricks notebook cells; remove the magic line in the SQL editor. The AP2 benchmark file contains two separate dashboard queries.

Setup:

- AP2 benchmark queries sum the non-overlapping population age groups once per region/year. They exclude missing or nonpositive population and null obligations.
- Run the complete AP3 SQL file in order. It creates the base GRDP/spending/population view, then the NCR-excluded view with yearly median guides. Both are ordinary views despite their mv_ names.
- Match the warehouse catalog/schema to the Gold build. These files use pondolens.dev_gold; edit the targets for isolated test schemas.
- Analytics files are not dbt nodes. A successful dbt build does not execute these queries. Preview each dashboard dataset after setup.

Appropriations are budget allocations; obligations are commitments, not cash payments. Use the same year and region coverage when comparing measures. Sum non-overlapping population age groups once per region-year before joining to budget data. Keep GRDP price bases separate.

See [AP2 definitions](../docs/analytics/AP2_population_vs_spending_gap.md), [AP3 definitions](../docs/analytics/AP3_grdp_vs_obligations_scatter.md), and [dashboard setup](../dashboard/PondoLens_Dashboard.md).
