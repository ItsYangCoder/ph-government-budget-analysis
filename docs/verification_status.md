# Verification status — October 6, 2026

## Current local results

The following evidence was reported by Rhea from the project Mac terminal:

| Check | Result |
|---|---|
| Automated tests | 26 passed in 13.55s during initial local setup |
| Configured extraction units | 18 processed across four configs |
| Identical reruns | 18 skipped in total; no new extraction |
| Committed-output integrity | 18 passed, 0 failed |
| Excel source-to-output comparison | 796,316 records compared; 0 raw-value mismatches |
| Raw-cell sheet coverage | 0 populated cells outside extracted locations |

These are dated terminal observations, not a new test run of this repository commit.

## Review limits

The Excel comparison used the preserved workbook and the same raw representation helper as extraction. It compared values, types, number formats, formulas, and cached values. It is useful fidelity evidence, not an independent implementation of every parsing rule.

Full-sheet coverage was checked only for raw-cell outputs. Population and per-capita GRDP select configured measures, so their printed zero uncovered counts did not establish full-sheet coverage.

The 11 uploaded initial CSV previews (9,868 records) matched retained reference Parquet values, dimensions, flags, and locations, with no duplicate IDs within each table. This did not independently verify every PDF value visually.

PDF continuation/control checks passed. Full independent source-page value review remains outstanding.

## Unresolved source issues

- Population 2024: regional sum differs from national total by 100 persons; preserved.
- 2025 SUCs: 2025 title conflicts with 2024 appropriation headers; preserved.
- PSGC Q2 2026: provincial-summary heading says June 2020; preserved.
- Coding Structure has no observed cell values; non-cell objects remain in the original workbook.
- Financial reconciliation of agency detail/SUC rows and raw GRDP/PSGC is not completed. Generic record-count logging alone is not accuracy validation.

## Next milestone

Load into Databricks Bronze with source issues retained. Verify uploaded checksums, table counts, and a zero-insert rerun. No Databricks workspace execution has yet been confirmed.

Initial execution artifacts under history/ document the earlier eight-unit implementation pilot and must not be read as current coverage.
