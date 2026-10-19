# Region Boundaries — Bronze Findings

Assigned to: Rhea Alum 
Updated: 20 October 2026 (Asia/Manila)  
Table: `pondolens.dev_bronze.region_boundaries`  
Source: `06_geographic_reference/ph_regions_with_nir.geojson`

## What this data contains

Each row is one regional map feature. The current file has 18 regions, including NIR. One region can contain several polygon parts, so multiple parts do not mean duplicate regions.

This file is one boundary snapshot. It does not provide separate maps for each year.

## Results

These results were checked in Databricks and shared by Rhea.

| Check | Result |
|---|---:|
| Regional features | 18 |
| Unique source codes | 18 |
| Unique source names | 18 |
| Missing codes, names, geometry, properties, or feature text | 0 |
| Duplicate source-code groups | 0 |
| Rescued rows | 0 |
| Polygon features | 4 |
| MultiPolygon features | 14 |
| Features with parsed coordinate structures | 18 |
| Rings | 403 |
| Rings with fewer than four positions | 0 |
| Unclosed rings | 0 |
| Rings with invalid positions | 0 |
| Coordinate positions | 13,202 |
| Invalid longitude/latitude positions | 0 |
| Features with exactly one crosswalk mapping | 18 |
| Incomplete lineage rows | 0 |

The reported JSON checks found no mismatches between extracted codes/names and embedded properties. Geometry type labels also match between geometry_json and feature_json. Full coordinate-array equality was not checked.

Coordinate positions include repeated points used to close rings. These checks confirm readable structure and coordinate ranges, not complete spatial validity.

## Coordinate extent

| Measure | Value |
|---|---:|
| Minimum longitude | 116.92886449600009 |
| Maximum longitude | 126.59877445500003 |
| Minimum latitude | 4.642097964000073 |
| Maximum latitude | 20.836012216000025 |

## What to carry into Silver

| Finding | Treatment |
|---|---|
| All 18 regions match the shared crosswalk. | Use its canonical region_code and region_name. Require one distinct mapping per feature. |
| Source adm1_psgc differs from project codes such as I or IVA. | Keep it as a separate STRING identifier. Verify the official code version before reformatting it. |
| Both Polygon and MultiPolygon occur. | Preserve the source geometry type unless the dashboard needs a consistent representation. |
| NIR is included. | Keep the feature and review its boundary version before historical budget joins. |
| Only CAR has area/length properties. | Treat them as optional metadata. Do not fill missing areas with zero. |
| Boundary reference date is unknown. | Keep it unknown until verified. File timestamps are not effective dates. |
| Future files may change regional shapes. | Define how boundary versions will be tracked before updating historical maps. |

## Source and lineage

| Field | Recorded value |
|---|---|
| Source file | 06_geographic_reference/ph_regions_with_nir.geojson |
| Ingestion run | 06348391a60e4b3bb71634792d2a6f73 |
| Ingested at | 2026-10-18T19:00:23.044Z |
| File modified at | 2026-10-18T12:00:50.383Z |

All 18 records have the required ingestion metadata. A NULL source sheet is fine for GeoJSON.

## Still needs checking

- Original publisher, license, official code version, and boundary reference date.
- CRS and axis order from the original source metadata.
- Self-intersections, hole placement, degenerate geometry, overlaps, and coverage gaps.
- Full geometry consistency between geometry_json and feature_json.
- The separate normalized-name duplicate query added to profiling.sql; its output has not yet been supplied.

Do not silently repair or simplify Bronze geometry. Keep the original and make any approved changes downstream.

## Readiness

The reported completeness, uniqueness, JSON consistency, coordinate structure, mapping, and lineage checks passed. We can proceed with Silver design. Production spatial use still needs the pending CRS, topology, and boundary-version checks above.

The 18-row count describes this snapshot; it is not a permanent limit for future boundary files.

## Related files

- [Profiling SQL](profiling.sql)
- [Data dictionary](data_dictionary.md)

Repository location: `profiling/bronze/region_boundaries/`.
