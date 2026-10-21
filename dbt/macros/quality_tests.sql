{% test nonempty(model) %}
select 1 as empty_table where not exists (select 1 from {{ model }})
{% endtest %}

{% test unique_grain(model, columns) %}
select {% for column in columns %}{{ adapter.quote(column) }}{% if not loop.last %}, {% endif %}{% endfor %}, count(*) as row_count
from {{ model }}
group by {% for column in columns %}{{ adapter.quote(column) }}{% if not loop.last %}, {% endif %}{% endfor %}
having count(*) > 1
{% endtest %}
