# Initial implementation snapshot — historical

This report covers the original eight-unit pilot, not current 18-unit coverage. Refer to ../verification_status.md for latest reported evidence. The run_artifacts paths below refer to the original delivery archive, not files committed to Git.

# Execution report

..........................                                               [100%]
26 passed in 1.05s

First final run: 8 processing keys committed. Rerun: 8 skipped, 0 new outputs.
Total retained source measures/physical cells: 9868. Final source failures: 0.

| Source | Records | SHA-256 |
|---|---:|---|
| agency_2024_summary | 2664 | `51618bd1e5333f645401e60d042b6d6116476705bfd0cf61026580889d6957e0` |
| agency_2025_summary | 2952 | `f9a95d902481a138a44487b90b157b236ae78430b45a69e31045dbb9984748a0` |
| per_capita_grdp | 76 | `63630c5ab5ba78bdeffc34041a5de68ba552cf48bdec80f9b8b1ebcff353ab5f` |
| population_projection | 2052 | `2e9e69f3856ff8b1b04d133e156effef8596738bd0cc94f9925640b8a309c34a` |
| regional_2024 | 840 | `163915054ab9209a1fc9eb40cd90903a2b88e3e65742af69003f3c3c6302cc06` |
| regional_2025 | 960 | `85342c5c7e5c232987463683e81e3e40c58bb6aa665dc439af2f7b2a19f11729` |
| sector_2024 | 162 | `14ff96ea6587bcee687951385ac7edc26a07b71a7898a6ed9fd12d3d4fbc6753` |
| sector_2025 | 162 | `09f0e99e562206bfa953282af264d55d413a3f302ccf093de451a3f40cfa7e2b` |

All original/output digests, Parquet row counts and manifests verified before packaging.
All records retain declared source interpretation flags. Successful extraction does not resolve geographic or financial comparability.
Databricks helper syntax compiled locally but no Spark/Delta workspace run was performed.
Agency extraction is limited to summary sheets. Additional indicators/PSGC are deferred.

During development, merged-cell handling failed and was fixed with a regression test. A subsequent clean final run processed both agency summaries successfully.
Ledger persistence was hardened using SQLite rollback-journal mode under the local writer lock; cross-process reruns are tested.

Machine-readable detail: audit_summary.json. Run-level evidence: run_artifacts/audit/.
