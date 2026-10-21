{# Migration materialization: execute statements in one dbt connection, in order. #}
{% materialization pondolens_script, adapter='databricks' %}
  {% if flags.FULL_REFRESH %}
    {{ exceptions.raise_compiler_error('Full refresh is disabled for ID-preserving script models. Run without --full-refresh.') }}
  {% endif %}
  {% set target_relation = this.incorporate(type='table') %}
  {{ run_hooks(pre_hooks, inside_transaction=False) }}
  {% for part in sql.split('
-- pondolens:statement --
') %}
    {% if part | trim %}
      {{ log('Executing ' ~ model.name ~ ' statement ' ~ loop.index, info=True) }}
      {% call statement('step_' ~ loop.index, fetch_result=True, auto_begin=False) %}
        {{ part }}
      {% endcall %}
    {% endif %}
  {% endfor %}
  {% call statement('main', fetch_result=True, auto_begin=False) %}
    select * from {{ target_relation }} limit 0
  {% endcall %}
  {{ run_hooks(post_hooks, inside_transaction=False) }}
  {{ return({'relations': [target_relation]}) }}
{% endmaterialization %}
