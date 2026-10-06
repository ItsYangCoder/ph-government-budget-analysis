# Source review

Reviewed the supplied completed team workbook and inspected actual Excel/PDF
sources from the provided dataset folder. Input files are not modified.

## Team handoff findings

- MIA contained only template samples: no sample entry was treated as verified.
  Agency SUMMARY/SUM headers and control cells were checked independently for the
  limited raw-cell pilot. Agency detail sheets/SUCs remain outside the pilot.
- RAZZ documented PDF units, sector hierarchy, source statuses, totals and page
  continuation. The actual PDFs expose repeated row-name text on page 2, including
  text with negative/off-page x coordinates. The regional adapter checks that
  retained text against page 1 rather than trusting row order alone.
- ANJE provided population block/column structure and geographic risks. Inventory
  date-serial/boundary errors were not used as extraction rules. Original rows and
  headers confirmed the configured layout.
- JOY provided exact current/constant per-capita GRDP locations, measures and flags.
  Additional indicator entries are pending and are not ingested.

## Verified pilot controls

| Source / locator | Value | Unit |
|---|---:|---|
| Population Table 1 O8 | 112884800 | persons, 2024 national |
| Population Table 1 R8 | 113863100 | persons, 2025 national |
| Population Table 1 O28 | 13787800 | persons, 2024 NCR |
| Capita D12 | 595591.0690145937 | PHP/person, 2024 current NCR |
| Capita D47 | 503423.60173946404 | PHP/person, 2024 constant-2018 NCR |
| B5 2024 actual GRAND TOTAL | 6273082 | million PHP |
| B5 2025 actual GRAND TOTAL | 6392668 | million PHP |
| B6a 2024 GRAND TOTAL | 6273082250 | thousand PHP, actual obligations |
| B6b 2025 GRAND TOTAL | 6326324300 | thousand PHP, updated GAA |
| Agency 2024 SUMMARY Z61 | 6273082250.348979 | thousand PHP, obligations |
| Agency 2025 SUM Z61 | 6392668440.412667 | thousand PHP, obligations |

The population extraction retains 19 age rows × 18 national/regional blocks ×
3 sexes × 2 years = 2052 source measures. The analytical subset of regional
all-age/both-sex totals is 34, but no analytical filtering is implemented.
GRDP retains (18 regional + 1 national) × 2 years × 2 price bases = 76 values.
Sector retains 27 source rows × 6 source measure columns per PDF. Program/proposed
columns are retained with their labels, not reclassified or used as actuals.

All non-blocking interpretation risks remain in quality_flags and preserved notes.
The original Drive folder was inspected read-only. No Google files were changed.
