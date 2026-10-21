with mappings as (
select distinct upper(trim(source_region)) as alias, region_code, region_name, valid_from_year, valid_to_year
from {{ ref('shared_region_crosswalk') }}
)
select a.* from mappings a join mappings b on a.alias = b.alias
and a.valid_from_year <= b.valid_to_year and b.valid_from_year <= a.valid_to_year
where not (a.region_code <=> b.region_code) or not (a.region_name <=> b.region_name)
