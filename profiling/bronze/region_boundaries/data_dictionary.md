# Region Boundaries — Bronze Data Dictionary

Assigned to: Rhea Alum  
Updated: 20 October 2026 (Asia/Manila)  
Table: `pondolens.dev_bronze.region_boundaries`  
Source: `06_geographic_reference/ph_regions_with_nir.geojson`

## Purpose

Provides regional boundary shapes for PondoLens choropleth maps.

After crosswalk mapping in Silver, `region_code` connects each shape to budget or indicator results. The geometry draws the region, while the selected measure determines its color.

## What one row means

One row is one source regional map feature. The current snapshot contains 18 regions, including NIR. A region may have several polygon parts representing its separate land areas and islands.

## Source columns

| Column | Type | Meaning |
|---|---|---|
| adm1_psgc | STRING | Source regional identifier labeled PSGC. Keep as text and separate from project region_code. Official code/version verification is pending. |
| adm1_en | STRING | Source region name used for crosswalk matching. |
| geometry_json | STRING | GeoJSON shape used to draw the region on a choropleth map. Contains Polygon or MultiPolygon coordinates. Keep its nested structure intact. |
| properties_json | STRING | Feature attributes, including adm1_psgc, adm1_en, and geo_level. |
| feature_json | STRING | Complete GeoJSON Feature containing the region's geometry and properties. |

## Ingestion columns

| Column | Type | Meaning |
|---|---|---|
| _rescued_data | STRING | Ingestion rescue payload. Review any nonblank value. |
| _drive_file_id | STRING | Google Drive source file ID. |
| _source_file | STRING | Relative source path recorded by ingestion. |
| _landing_file | STRING | Landed file path in the Unity Catalog volume. |
| _source_modified_at | STRING | File modification timestamp, not the boundary effective date. |
| _source_sheet | STRING | Sheet selection; NULL is expected for GeoJSON. |
| _content_hash | STRING | Source-content fingerprint. |
| _header_map | STRING | Serialized source-to-normalized header mapping. |
| _dataset_hash | STRING | Dataset fingerprint recorded by ingestion. |
| _run_id | STRING | Ingestion run ID shared by multiple records. |
| _ingested_at | TIMESTAMP | Time the record was ingested. |

## Embedded properties

| Property | Meaning |
|---|---|
| adm1_psgc | Numeric identifier inside the JSON; the extracted Bronze column is STRING. |
| adm1_en | Source region name. |
| geo_level | Reg in the supplied records. |
| len_crs, area_crs, len_km, area_km2 | Present only for CAR in the supplied output. Treat as optional until their calculation method, units, and CRS are verified. |

## Geometry and mapping notes

- Polygon contains rings of coordinate positions. MultiPolygon groups several polygon parts into one regional feature.
- Keep the nested geometry intact so rings, boundaries, and island components remain connected correctly.
- Coordinates may be expanded temporarily for validation. The final boundary record keeps the complete regional shape.
- Rings include closing positions; interior rings may also be present.
- Coordinate-range checks do not verify the coordinate reference system (CRS), topology, or positional accuracy.
- Use the shared crosswalk for canonical region_code and region_name. All 18 source features matched exactly one distinct pair in the reported check.
- Crosswalk validity years were not applied because the boundary reference date is not yet verified.
- Verify boundary compatibility before displaying historical budget or indicator values, especially for NIR, VI, and VII.
- Keep source geometry and ingestion metadata unchanged in Bronze.

## Related files

- [Profiling SQL](profiling.sql)
- [Findings](findings.md)