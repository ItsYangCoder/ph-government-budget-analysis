# Bronze profiling handoff

## Goal

Use Bronze profiling to understand how Philippine government spending is distributed across sectors and regions, where gaps or concentrations may appear, and whether regional budget figures can later be compared fairly with population and economic conditions.

Initial analytical scope is 2024–2025. Preserve other years and reporting statuses, but label them clearly.

Bronze is read-only during this work. Loading fidelity does not establish analytical comparability.

## Team assignments

| Member | Bronze scope | Profiling focus |
|---|---|---|
| Rhea | All assigned Bronze outputs | Coordinate profiling, separate evidence from assumptions, and consolidate proposed Silver rules. |
| MIA | Agency summary, agency detail, SUCs | Measures, years, units, reporting periods, hierarchy, funding categories, subtotals, overlaps, conflicting headers, formulas/errors. |
| RAZZ | Sector and regional budget | Sectors/subsectors, regions, row groups, units, years, statuses, PDF continuation, controls, totals and hierarchy. Keep 2024 actual obligations and 2025 updated GAA distinct. |
| ANJE | Population and PSGC | Population years, projection basis, age/sex groups, totals, regional coverage, NIR/Sulu uncertainties, and dated 2026 PSGC limitations. |
| JOY | Total and per-capita GRDP | Years, measures, units, price bases, revisions, national/regional rows, and geographic/temporal compatibility with regional budget and population. |

## Findings template

Use one row per evidence-backed finding.

| Member | Bronze table | Finding | Source location/evidence | Analytical impact | Proposed Silver rule | Status |
|---|---|---|---|---|---|---|
|  |  |  |  |  |  |  |

Suggested Status values: `Informational`, `Needs source clarification`, `Possible extraction defect`, `Proposed rule`, `Blocked`.

Each member returns:
- profiling results for assigned tables;
- representative source examples;
- proposed rules supported by evidence;
- unresolved questions and the exact additional evidence needed.

## Silver readiness checklist

A source is ready to move toward Silver only when the applicable items below are documented.

- [ ] Correct Bronze table and source revision are identified.
- [ ] Old and revised records have an explicit later selection rule; they will not be added together.
- [ ] Measure meaning is documented.
- [ ] Year and reporting period/status are documented.
- [ ] Unit is documented.
- [ ] Geography and relevant boundary/date limitations are documented.
- [ ] Parent totals, child rows, subtotals, and repeated headers are identified where applicable.
- [ ] Overlapping records that must not be summed are identified.
- [ ] Raw blanks, zeros, dashes, Excel errors, and parsing outcomes are distinguished.
- [ ] Representative records have exact source locations and have been checked against the original.
- [ ] Source controls/totals are understood and are not double-counted with children.
- [ ] Raw-cell row/column mappings needed for financial completeness or business keys are verified.
- [ ] Unresolved source issues are documented separately from possible extraction defects.
- [ ] 2024–2025 comparison uses compatible measures/statuses, or the comparison remains explicitly blocked.
- [ ] Regional comparison has documented geographic and temporal compatibility across budget, population, GRDP, and PSGC references.

## Known comparison cautions

- Regional 2024 is Actual Obligations while regional 2025 is GAA (Updated). Do not treat these as the same measure.
- Sector Program/Proposed values remain separate from Actual values.
- Sector and regional sources use different units.
- Agency detail/SUC, total GRDP, and PSGC are raw-cell extracts; do not infer analytical hierarchy from cell position alone.
- Per-capita GRDP is already per person.
- 2026 PSGC is a dated supporting reference, not proof of historical 2024–2025 boundaries.
- Population projection geography and GRDP geography require review around NIR and Sulu before regional comparisons.
