# Analytics

These SQL files support the three analytical questions. They are separate from dbt and read Gold tables in `pondolens.dev_gold`.

| Focus | Files |
|---|---|
| AP1 — Budget and spending by department | [Appropriations](q1_budget_and_spending_distribution/appropriation_department.sql) · [Obligations](q1_budget_and_spending_distribution/spending_department.sql) |
| AP2 — Spending compared with population | [Population and spending shares](q2_budget_and_population/population_budget_share_gap.sql) · [Per-person benchmark](q2_budget_and_population/regional_obligations_per_capita_benchmark.sql) |
| AP3 — Spending compared with GRDP per capita | [GRDP comparison](q3_budget_and_indicators/budget_vs_grdp.sql) |

Run these after a successful Gold build. Review target names before execution. Files with `%sql` are intended for Databricks notebook cells; remove the magic line in the SQL editor. The AP2 benchmark file contains two separate dashboard queries.

Current limits to resolve before deployment:

- The AP2 benchmark selects a total-age row, but the current population model keeps age-group detail only. Its population calculation needs to match that model.
- AP3 depends on `mv_grdp_spending_population`; its creation SQL is not yet included in this repository.
- These files are not dbt nodes. A successful dbt build does not create or validate these views.

Appropriations are budget allocations; obligations are commitments, not cash payments. Use the same year and region coverage when comparing measures. Sum non-overlapping population age groups once per region-year before joining to budget data. Keep GRDP price bases separate.

See [AP2 definitions](../docs/analytics/AP2_population_vs_spending_gap.md), [AP3 definitions](../docs/analytics/AP3_grdp_vs_obligations_scatter.md), and [dashboard setup](../dashboard/readme.md).
