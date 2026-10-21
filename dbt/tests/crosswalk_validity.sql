select * from {{ ref('shared_region_crosswalk') }} where valid_from_year > valid_to_year
