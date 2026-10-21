# Profiling consolidation

The current dataset index, execution instructions, evidence rules and automated checks are in [profiling/README.md](../profiling/README.md). Each dataset retains its own `profiling.sql`, `data_dictionary.md` and `findings.md`.

This replaces the older mixed-source consolidation as the entry point. Historical reviews remain in [archive/profiling](archive/profiling/) and are not current acceptance evidence.

## Corrections

- Hospital SQL now handles Government-only source data without treating missing Private/Total categories as errors or zero. Reconciliation is explicitly NOT_COMPARABLE when required categories are absent.
- Regional Obligations now has dataset-correct findings. The misplaced poverty document is archived; it is not reused as obligations evidence.
- Regional Obligations profiling no longer converts all missing/unparsed amounts into zero, performs an unverified currency conversion, or uses a private hard-coded regional map.
- Regional boundaries folder and service-access filenames are normalized; SQL table names are unchanged.
- Agency Actuals profiling is retained for reference, with existing documented source discrepancies. Service Access is also reference-only for the current analytics scope.

## Validation boundary

Local/CI checks validate file structure, SQL syntax, allowed statements and relative links. Newly revised SQL still requires Databricks execution and source review. No ingestion, Silver transformations, shared crosswalk records or Gold models are changed by this consolidation.
