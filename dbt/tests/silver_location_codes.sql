{% set names = ['completion_rate','grdp_per_capita','hospital','population','poverty_incidence','region_boundaries','regional_appropriations','regional_obligations','unemployment_rate','service_access'] %}
{% for name in names %}
select '{{ name }}' as dataset, s.region_code
from {{ ref(name) }} s
left anti join {{ ref('shared_region_crosswalk') }} x
on s.region_code = x.region_code
where s.region_code <> 'NW'
{% if not loop.last %}union all{% endif %}
{% endfor %}
