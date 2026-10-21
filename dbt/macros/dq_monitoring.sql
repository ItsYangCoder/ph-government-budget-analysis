{% macro dq_literal(value) -%}
'{{ (value | string).replace("'", "''") }}'
{%- endmacro %}

{% macro record_dq_results(results) %}
  {% if not execute or flags.WHICH not in ['build', 'run', 'test'] or not var('enable_dq_monitoring', true) or not results %}
    {{ return('') }}
  {% endif %}
  {% set gold = var('gold_schema', 'dev_gold') %}
  {% set default_schema = gold[:-5] ~ '_monitoring' if gold.endswith('_gold') else gold ~ '_monitoring' %}
  {% set monitoring = var('monitoring_schema', default_schema) %}
  {% set ns = adapter.quote(var('pondolens_catalog')) ~ '.' ~ adapter.quote(monitoring) %}
  {% set history = ns ~ '.`dq_results`' %}
  {% set rows = [] %}
  {% set selected = namespace(count=0, total=0) %}
  {% for n in graph.nodes.values() %}
    {% if n.resource_type in ['model', 'test'] %}{% set selected.total = selected.total + 1 %}{% endif %}
  {% endfor %}
  {% for uid in selected_resources %}
    {% set n = graph.nodes.get(uid) %}
    {% if n and n.resource_type in ['model', 'test'] %}{% set selected.count = selected.count + 1 %}{% endif %}
  {% endfor %}
  {% for res in results %}
    {% set node = res.node %}
    {% if node.resource_type in ['model', 'test'] %}
      {% set datasets = [] %}
      {% set parents = [node.unique_id] if node.resource_type == 'model' else node.depends_on.nodes %}
      {% for uid in parents %}
        {% set parent = graph.nodes.get(uid) or graph.sources.get(uid) %}
        {% if parent and parent.resource_type in ['model', 'source'] %}
          {% set relation = parent.database ~ '.' ~ parent.schema ~ '.' ~ (parent.identifier if parent.resource_type == 'source' else parent.alias) %}
          {% if relation not in datasets %}{% do datasets.append(relation) %}{% endif %}
        {% endif %}
      {% endfor %}
      {% set row %}
        SELECT {{ dq_literal(invocation_id) }} AS invocation_id,
          {{ dq_literal(node.unique_id) }} AS node_id,
          {{ dq_literal(node.name) }} AS check_name,
          {{ dq_literal(node.resource_type) }} AS resource_type,
          {{ dq_literal(res.status | string | lower) }} AS status,
          CAST({{ res.failures if res.failures is not none else 'NULL' }} AS BIGINT) AS failures,
          CAST({{ res.execution_time }} AS DOUBLE) AS execution_seconds,
          FROM_JSON({{ dq_literal(tojson(datasets)) }}, 'ARRAY<STRING>') AS datasets,
          {{ dq_literal(flags.WHICH) }} AS command,
          {{ selected.count }} AS expected_nodes,
          {{ selected.total }} AS project_nodes,
          {{ dq_literal(var('bronze_schema', 'dev_bronze')) }} AS bronze_schema,
          {{ dq_literal(var('silver_schema', 'dev_silver')) }} AS silver_schema,
          {{ dq_literal(gold) }} AS gold_schema,
          {{ dq_literal(dbt_version) }} AS dbt_version,
          CAST({{ dq_literal(run_started_at.isoformat()) }} AS TIMESTAMP) AS run_started_at,
          CURRENT_TIMESTAMP() AS recorded_at
      {% endset %}
      {% do rows.append(row) %}
    {% endif %}
  {% endfor %}
  {% if not rows %}{{ return('') }}{% endif %}
  {% do run_query('CREATE SCHEMA IF NOT EXISTS ' ~ ns) %}
  {% set ddl %}
    CREATE TABLE IF NOT EXISTS {{ history }} (
      invocation_id STRING, node_id STRING, check_name STRING, resource_type STRING,
      status STRING, failures BIGINT, execution_seconds DOUBLE, datasets ARRAY<STRING>,
      command STRING, expected_nodes INT, project_nodes INT, bronze_schema STRING, silver_schema STRING,
      gold_schema STRING, dbt_version STRING, run_started_at TIMESTAMP, recorded_at TIMESTAMP
    ) USING DELTA
  {% endset %}
  {% do run_query(ddl) %}
  {% for chunk in rows | batch(50) %}
    {% set merge %}
      MERGE INTO {{ history }} t USING ({{ chunk | join('\nUNION ALL\n') }}) s
      ON t.invocation_id = s.invocation_id AND t.node_id = s.node_id
      WHEN NOT MATCHED THEN INSERT *
    {% endset %}
    {% do run_query(merge) %}
  {% endfor %}
  {% set summary %}
    CREATE OR REPLACE VIEW {{ ns }}.`dq_run_summary` AS
    SELECT invocation_id, command, bronze_schema, silver_schema, gold_schema,
      MAX(dbt_version) AS dbt_version, MIN(run_started_at) AS run_started_at,
      MAX(recorded_at) AS recorded_at, MAX(expected_nodes) AS expected_nodes,
      MAX(project_nodes) AS project_nodes, COUNT(*) AS recorded_nodes,
      COUNT_IF(resource_type = 'model') AS model_count,
      COUNT_IF(resource_type = 'test') AS test_count,
      COUNT_IF(resource_type = 'test' AND status = 'pass') AS passed_tests,
      COUNT_IF(status IN ('error', 'fail', 'runtime error')) AS error_count,
      COUNT_IF(status = 'warn') AS warning_count,
      COUNT_IF(status = 'skipped') AS skipped_count,
      CASE
        WHEN COUNT_IF(status IN ('error', 'fail', 'runtime error')) > 0 THEN 'FAIL'
        WHEN COUNT(*) < MAX(expected_nodes) OR COUNT_IF(status NOT IN ('success', 'pass', 'warn')) > 0 THEN 'INCOMPLETE'
        WHEN command <> 'build' THEN 'PARTIAL_COMMAND'
        WHEN MAX(expected_nodes) < MAX(project_nodes) THEN 'PARTIAL_SELECTION'
        WHEN COUNT_IF(status = 'warn') > 0 THEN 'WARN'
        ELSE 'PASS'
      END AS run_status
    FROM {{ history }}
    GROUP BY invocation_id, command, bronze_schema, silver_schema, gold_schema
  {% endset %}
  {% do run_query(summary) %}
  {% set latest %}
    CREATE OR REPLACE VIEW {{ ns }}.`dq_latest_status` AS
    SELECT * EXCEPT (rn) FROM (
      SELECT *, ROW_NUMBER() OVER (
        PARTITION BY node_id, bronze_schema, silver_schema, gold_schema
        ORDER BY run_started_at DESC, invocation_id DESC
      ) AS rn FROM {{ history }} WHERE command = 'build'
    ) WHERE rn = 1
  {% endset %}
  {% do run_query(latest) %}
  {% set dataset_summary %}
    CREATE OR REPLACE VIEW {{ ns }}.`dq_dataset_summary` AS
    WITH latest_build AS (
      SELECT invocation_id, run_status, bronze_schema, silver_schema, gold_schema
      FROM {{ ns }}.`dq_run_summary`
      WHERE command = 'build'
      QUALIFY ROW_NUMBER() OVER (
        PARTITION BY bronze_schema, silver_schema, gold_schema
        ORDER BY run_started_at DESC, invocation_id DESC
      ) = 1
    ), expanded AS (
      SELECT h.*, b.run_status, EXPLODE(h.datasets) AS dataset
      FROM {{ history }} h JOIN latest_build b ON h.invocation_id = b.invocation_id
    )
    SELECT invocation_id, dataset,
      MAX(CASE
        WHEN SPLIT(dataset, '\\.')[1] = bronze_schema THEN 'bronze'
        WHEN SPLIT(dataset, '\\.')[1] = silver_schema THEN 'silver'
        WHEN SPLIT(dataset, '\\.')[1] = gold_schema THEN 'gold'
        ELSE 'other'
      END) AS layer,
      MAX(recorded_at) AS recorded_at,
      MAX(run_status) AS run_status,
      COUNT_IF(resource_type = 'test') AS test_count,
      COUNT_IF(resource_type = 'test' AND status = 'pass') AS passed_tests,
      COUNT_IF(status IN ('error', 'fail', 'runtime error')) AS error_count,
      COUNT_IF(status = 'warn') AS warning_count,
      COUNT_IF(status = 'skipped') AS skipped_count,
      CASE
        WHEN COUNT_IF(status IN ('error', 'fail', 'runtime error')) > 0 THEN 'FAIL'
        WHEN MAX(run_status) IN ('INCOMPLETE', 'PARTIAL_SELECTION') OR COUNT_IF(status = 'skipped') > 0 THEN 'INCOMPLETE'
        WHEN COUNT_IF(status = 'warn') > 0 THEN 'WARN'
        WHEN COUNT_IF(resource_type = 'test') = 0 THEN 'NO_TESTS'
        ELSE 'PASS'
      END AS dataset_status
    FROM expanded GROUP BY invocation_id, dataset
  {% endset %}
  {% do run_query(dataset_summary) %}
  {{ log('DQ results saved to ' ~ ns ~ '.dq_results', info=true) }}
  {{ return('SELECT 1') }}
{% endmacro %}
