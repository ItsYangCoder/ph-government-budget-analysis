# PondoLens source and long-form verification

Verification date: 2026-10-01 (Asia/Manila). Scope: the user's nine supplied original files and `pondolens-extraction.zip`, using local Python 3.12, openpyxl 3.1.5, and pdfplumber 0.11.8. These results apply to those exact source versions, not every future DBM/PSA publication.

## Original-to-extraction comparison

The original five smaller Excel files and two PDFs were retrieved from the connected source Drive. The large GAA workbooks were retrieved from their official DBM downloads. Both GAA SHA-256 hashes match the uploaded extraction provenance exactly.

Every extracted nonempty cell from all seven Excel files was compared with the original using cell coordinates, original value/type, formula/cache, and number format: **23,707,516 cells, zero mismatches**. Sheet markers also matched. All four PDF pages matched the original page text and page counts. ZIP integrity and structural cell coordinate uniqueness passed.

| Source | Original SHA-256 | Structural cells/pages |
|---|---|---:|
| Agency 2024 | `51618bd1e5333f645401e60d042b6d6116476705bfd0cf61026580889d6957e0` | 124,173 cells |
| Agency 2025 | `f9a95d902481a138a44487b90b157b236ae78430b45a69e31045dbb9984748a0` | 125,264 cells |
| GAA 2024 | `40e48e2b9cdc1ff52119f4b6a7a6bcb67ddce06a07c043f45695876a2ab045dc` | 11,425,797 cells |
| GAA 2025 | `fac03cb846b498d4b25a6e22fbf44ca4482b5dad7d36e97633e507197e2517e3` | 11,843,650 cells |
| Sector | `c8ebe6c7e4d15a99327b4374962c6d3e59c4f868c1958d67f836af945730572d` | 9,506 cells |
| Regional 2024 | `163915054ab9209a1fc9eb40cd90903a2b88e3e65742af69003f3c3c6302cc06` | 2 pages |
| Regional 2025 | `b666be406e792ecceddab9ce35ffbb4ca076aafdc83038083af40a2c2fa6d8fb` | 2 pages |
| Population | `50d43151d11b1e51ff2e4e073b98b0b70800327bfbf9f3f21cabfcffed9ae2d9` | 178,537 cells |
| GRDP | `63630c5ab5ba78bdeffc34041a5de68ba552cf48bdec80f9b8b1ebcff353ab5f` | 589 cells |

Original header/footer parse warnings concern formatting. Original bytes remain preserved. No workbook values were changed to suppress warnings.

## Full long-form run

The complete uploaded ZIP was streamed into the source-specific converters; the multi-gigabyte JSONL files were not extracted onto disk. A separate full run read all nine original Excel/PDF files directly and produced the same per-source row counts. Each source passed business-key and applicable reconciliation gates. Full report/CSV output is generated locally by the CLI; source data is excluded from this repository.

| Source | Long rows, including retained candidates/controls | Status |
|---|---:|---|
| Agency 2024 | 120,162 | PASS |
| Agency 2025 | 121,205 | PASS |
| GAA 2024 | 532,083 | PASS |
| GAA 2025 | 545,876 | PASS |
| Sector | 9,124 | PASS |
| Regional 2024 | 840 | PASS |
| Regional 2025 | 945 | PASS |
| Population | 159,261 | PASS |
| GRDP | 315 | PASS |
| **Total** | **1,489,811** | **9/9 PASS** |

**55,393 reconciliation checks passed; zero duplicate keys at the implemented grains.** This does not mean every source line is independent/additive or that the publisher's data is free of all possible substantive errors.

| Dataset | Rows |
|---|---:|
| Approved budget lines | 1,077,957 |
| GAA workbook control totals | 2 |
| Agency summaries | 4,338 |
| Agency detail hierarchy candidates | 236,830 |
| Sector measures | 8,899 |
| Regional source observations/states | 1,785 |
| Population projections | 159,207 |
| Population growth intervals | 54 |
| GRDP measures | 304 |
| Remaining numeric/header/support candidates | 435 |

For the smaller workbooks, converted values plus retained candidates cover all numeric/error source cells: agency 2024 120,096 numeric + 66 errors; agency 2025 121,144 numeric + 61 errors; sector 9,124 numeric including cached formulas; population 159,261 numeric; GRDP 315 numeric. GAA monetary rows are represented once as budget lines or the separate SUM control; codes remain dimensional text and program headings remain in originals/structural extraction.

The 127 original agency `#DIV/0!` cells are preserved as undefined rates with raw source errors, not converted to zero. PDF dashes/blanks remain explicit nonnumeric source states. The generic PDF table detector had missed the amounts; the new parser uses word coordinates and verifies all regional column captions and financial totals. The rotated unrelated text in the 2025 PDF is excluded from the financial table mapping.

## GAA totals and unit evidence

| Control | FY2024 | FY2025 |
|---|---:|---:|
| Budget-line sum, thousand PHP | 5,767,600,000 | 6,326,324,300 |
| Workbook final SUM, thousand PHP | 5,767,600,000 | 6,326,324,300 |
| Senate agency-specific fund `01101101`, thousand PHP | 13,008,421 | 13,930,174 |
| Official Senate new appropriation, PHP | 13,008,421,000 | 13,930,174,000 |

The official appropriation totals and thousand-peso object tables establish the scale used for these exact input hashes. Retirement/Life Insurance Premiums are a separate fund and were excluded from the agency-specific fund comparison: 180,363 thousand PHP in FY2024 and 208,738 thousand PHP in FY2025. Do not compare all funds against an agency-specific appropriation without matching scope.

Official references inspected:

- [FY2024 Senate GAA](https://www.dbm.gov.ph/wp-content/uploads/GAA/GAA2024/VolumeI/CONGRESS/A.pdf)
- [FY2025 Senate GAA](https://www.dbm.gov.ph/wp-content/uploads/GAA/GAA2025/VolumeIA/CONGRESS/A.pdf)
- [FY2024 GAA Excel](https://www.dbm.gov.ph/wp-content/uploads/GAA/GAA2024/GAA-2024.xlsx)
- [FY2025 GAA Excel](https://www.dbm.gov.ph/wp-content/uploads/GAA/GAA2025/GAA-2025.xlsx)

## Tests and limits

`python -m pytest -q`: **19 passed**. Regression coverage includes original preservation, formula/zero states, failed retry, unchanged reruns, revised-source replacement, duplicate rejection, corrupted CSV/manifest recovery, database repair, publication rollback, PDF split digits/page alignment/changed amounts, sector units/statuses, population grain, agency funding breakdowns, GRDP growth/indices, and duplicate source years.

Real-source rerun evidence for direct-original mode compares table row counts and ordered digests of every stored field before/after reuse. See [machine-readable rerun evidence](long_form_rerun.json); no appended records are permitted.

Agency detail hierarchy and cross-source agency/geographic joins remain pending. `ready_for_source_tables` is true for the verified source run; `ready_for_cross_source_analysis` remains false. Geographic incompatibilities include NIR coverage and must be reviewed before calculating spending per resident or joining GRDP. Tests do not assert Databricks execution, deployment, or a final Gold model.
