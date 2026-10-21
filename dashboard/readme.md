# Budget analysis dashboard

[Budget analysis.lvdash.json](Budget%20analysis.lvdash.json) is the Databricks AI/BI dashboard export. Import it in Databricks, select the SQL warehouse, and review data sources and permissions before publishing.

The export references these existing views in `pondolens.dev_gold`:

- `mv_population_spending_alignment`
- `mv_grdp_spending_population`
- `mv_grdp_spending_population_without_ncr`

Importing the dashboard does not create those views or run ingestion/dbt. Build Gold first, then prepare the views. The base GRDP view’s creation SQL is not yet included; see the [analytics guide](../analytics/readme.md) for setup limits.

Check year filters, region coverage, units, and totals against query results before publishing. Display obligations as commitments, not payments. The AP3 chart excludes NCR; keep that exclusion visible.

Metric definitions: [AP2](../docs/analytics/AP2_population_vs_spending_gap.md) · [AP3](../docs/analytics/AP3_grdp_vs_obligations_scatter.md).
