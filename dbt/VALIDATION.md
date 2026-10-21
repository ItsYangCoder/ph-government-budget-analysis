# Offline verification

- dbt Core 1.10.15 and dbt-databricks 1.10.15.
- `dbt parse`: passed.
- `dbt compile --no-introspect --no-populate-cache --threads 1`: passed.
- Isolated-schema compilation: passed for all 19 models and 235 data tests. Compiled model SQL uses dbt_test_silver/dbt_test_gold, not the existing development destinations.
- Materialization control-flow tests: 3 passed (statement order/result fetching, stop-on-failure, full-refresh rejection).
- 19 archived original SQL/notebook files match the uploaded ZIP byte-for-byte.
- No warehouse connection, table build, SQL engine validation, connected data tests, or live rerun was performed.

The code is prepared for a connected acceptance run; offline compilation is not production certification. Authentication and warehouse selection remain workspace-specific. Read MIGRATION.md for the exact transformation changes and inherited behavior.
