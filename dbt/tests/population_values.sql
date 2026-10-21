select * from {{ ref('population') }} where population < 0 or age_min < 0 or age_max < age_min
