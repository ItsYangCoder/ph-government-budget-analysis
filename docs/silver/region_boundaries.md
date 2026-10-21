# Region Boundaries — Silver

Documented by: **Rhea Alum**  
Updated: 22 October 2026 (Asia/Manila)  
Table: `pondolens.dev_silver.region_boundaries`  
Source file: `06_geographic_reference/ph_regions_with_nir.geojson`

## Purpose

Provides regional shapes for PondoLens choropleth maps. The geometry draws each region, while budget or indicator values determine its color.

One row represents **one region in the source boundary snapshot**. The profiled source contains 18 regions, including NIR. This is one map snapshot, not a separate boundary version for each year.

## Data dictionary

| Column | Type | Meaning |
|---|---|---|
| region_code | STRING | Standard project region code from the crosswalk. Unique business key and MERGE key. |
| region_name | STRING | Standard region name from the crosswalk. |
| adm1_psgc | STRING | Source identifier labeled PSGC, retained as text and separate from region_code. Its official code version requires verification. |
| geometry_type | STRING | Polygon or MultiPolygon. |
| geometry_json | STRING | Complete GeoJSON geometry containing its type and nested coordinates. Used to draw the regional shape. |
| processed_at | TIMESTAMP | Time the row was inserted or changed. Unchanged rows keep their timestamp. |

All six columns are required. There is no separate numeric record ID; `region_code` identifies each regional record.

## Transformation rules

- Read the source identifiers, names, geometry, and embedded JSON fields from Bronze.
- Trim source identifiers and names. Normalize names by removing punctuation and spaces for crosswalk matching.
- Match against regional crosswalk aliases and keep standard codes and names. National, Nationwide, and Central Office mappings are excluded.
- Match regional identity without applying crosswalk validity years because the boundary effective date is not verified.
- Preserve the original geometry JSON, including Polygon and MultiPolygon structure. Coordinates are parsed temporarily for validation, not flattened in the output.
- Keep properties, complete source features, optional area/length fields, and ingestion metadata in Bronze.

## Quality checks

The SQL blocks the load when it finds:

- Empty input, missing identifiers or names, or rescued data.
- Unsupported geometry types or a feature type other than Feature.
- Mismatched source identifiers, names, geometry types, or parsed coordinates between the JSON fields.
- Empty polygon structures, rings with fewer than four positions, or unclosed rings.
- Invalid coordinate positions, non-finite numbers, longitude outside −180 to 180, or latitude outside −90 to 90. Positions may contain two or three coordinates.
- Duplicate source identifiers or normalized names.
- Conflicting crosswalk aliases, unmapped regions, or mapping that repeats or multiplies regional records.
- Invalid existing target keys or a source identifier already assigned to another region code.

After loading, the SQL checks that every staged region matches the stored target values. [dbt tests](../../dbt/models/silver/schema.yml) also check nonempty output, unique/non-null region codes, and required attributes.

The recorded Bronze snapshot has **18 features: four Polygon and 14 MultiPolygon**, with 403 rings and 13,202 coordinate positions. These are profiling results, not fixed limits for future source files.

## Load and rerun behavior

The model uses a Delta MERGE on `region_code`. New regions are inserted; changed names, identifiers, or geometry are updated. Unchanged rows retain their processing timestamp.

Existing regions missing from a later source are retained. The model does not delete them automatically or keep separate historical shape versions.

Run through dbt after successful Bronze ingestion and crosswalk preparation, with **one target writer**. Keep Bronze and the crosswalk stable during execution. dbt resolves the target catalog and schema from the environment configuration.

For failed runs, follow [pipeline recovery](../ingestion.md#pipeline-failures-and-recovery).

## Choropleth connection

Gold [dim_location](../../dbt/models/gold/dim_location.sql) matches regional `location_code` to Silver `region_code` and carries `geometry_json` and the source identifier into the dimension. Nonregional locations receive no geometry.

Budget and indicator facts connect to `dim_location` through `location_id`. Prepare the selected measure by region and year before combining it with the regional shapes.

Keep the nested JSON intact so island parts and polygon rings remain connected. If a map tool requires a FeatureCollection, build that serving format from the regional geometry and properties.

## Boundary notes

Structural and coordinate checks do not prove complete spatial validity. Confirm the publisher, license, coordinate reference system, topology, and boundary effective date before treating the shapes as verified official boundaries.

This snapshot is not automatically valid for every historical year. Review compatibility before mapping historical measures, especially for NIR, Western Visayas, and Central Visayas. File modification and ingestion timestamps are not boundary effective dates.

## Related files

- [Silver transformation SQL](../../dbt/models/silver/region_boundaries.sql)
- [Silver column definitions and dbt tests](../../dbt/models/silver/schema.yml)
- [Gold location dimension](../../dbt/models/gold/dim_location.sql)
- [Bronze profiling SQL](../../profiling/bronze/region_boundaries/profiling.sql)
- [Bronze data dictionary](../../profiling/bronze/region_boundaries/data_dictionary.md)
- [Bronze findings](../../profiling/bronze/region_boundaries/findings.md)
- [Shared region crosswalk](../shared_region_crosswalk.md)
