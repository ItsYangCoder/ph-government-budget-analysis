{% macro generate_schema_name(custom_schema_name, node) -%}
{% if custom_schema_name == 'dev_silver' %}{{ var('silver_schema', 'dev_silver') }}
{% elif custom_schema_name == 'dev_gold' %}{{ var('gold_schema', 'dev_gold') }}
{% else %}{{ custom_schema_name | trim if custom_schema_name else target.schema }}{% endif %}
{%- endmacro %}
