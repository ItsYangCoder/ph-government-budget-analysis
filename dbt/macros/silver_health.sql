{# Current source contracts: keep these scopes aligned with Silver SQL when adding releases. #}
{% macro silver_health_metric(dataset, metric, numerator, denominator, rule, source,
                              excluded='0', unresolved='0', invalid='0', missing='0', status=none) %}
SELECT
    {{ dq_literal(dataset) }} AS dataset,
    {{ dq_literal(metric) }} AS metric,
    observed_rows,
    CAST({{ numerator }} AS BIGINT) AS numerator,
    CAST({{ denominator }} AS BIGINT) AS denominator,
    ROUND(100.0 * ({{ numerator }}) / NULLIF(({{ denominator }}), 0), 2) AS percentage,
    CAST({{ excluded }} AS BIGINT) AS excluded_rows,
    CAST({{ unresolved }} AS BIGINT) AS unresolved_rows,
    CAST({{ invalid }} AS BIGINT) AS invalid_rows,
    CAST({{ missing }} AS BIGINT) AS missing_expected_rows,
    source_unavailable_rows,
    unclassified_rows,
    exception_rows,
    {% if status %}{{ dq_literal(status) }}{% else %}
    CASE WHEN ({{ denominator }})=0 THEN 'Not assessed - empty eligible population'
         WHEN ({{ unresolved }})>0 THEN 'Assessed - review unresolved rows'
         ELSE 'Assessed' END{% endif %} AS assessment_status,
    {{ dq_literal(rule) }} AS rule_description,
    CURRENT_TIMESTAMP() AS assessed_at
FROM {{ source }}
{% endmacro %}

{% macro silver_health_sql() %}
{% set definitions = [
  {
    "name": "completion_rate",
    "keys": [
      "year",
      "region_code",
      "indicator",
      "level_of_education",
      "sex"
    ],
    "required": [
      "year",
      "region_code",
      "indicator",
      "level_of_education",
      "sex",
      "region_name"
    ],
    "key_incomplete": "f.`year` IS NULL OR NULLIF(TRIM(f.`region_code`), '') IS NULL OR NULLIF(TRIM(f.`indicator`), '') IS NULL OR NULLIF(TRIM(f.`level_of_education`), '') IS NULL OR NULLIF(TRIM(f.`sex`), '') IS NULL",
    "core_incomplete": "f.`year` IS NULL OR NULLIF(TRIM(f.`region_code`), '') IS NULL OR NULLIF(TRIM(f.`indicator`), '') IS NULL OR NULLIF(TRIM(f.`level_of_education`), '') IS NULL OR NULLIF(TRIM(f.`sex`), '') IS NULL OR NULLIF(TRIM(f.`region_name`), '') IS NULL",
    "measurement_state": "CASE WHEN f.value_status='available' AND f.completion_rate IS NOT NULL THEN 'available' WHEN f.value_status IN ('source_marker_two_dots','source_marker_three_dots') AND f.completion_rate IS NULL THEN 'source_unavailable' ELSE 'unclassified' END",
    "value_valid": "f.completion_rate BETWEEN 0 AND 100",
    "exception": "FALSE",
    "expected": "SELECT y.year, r.region_code, '4.1.2 Completion rate' AS indicator, e.level_of_education, s.sex FROM expected_years y CROSS JOIN (SELECT region_code FROM expected_regions UNION ALL SELECT 'PHL') r CROSS JOIN (SELECT level_of_education FROM VALUES ('Elementary'), ('Secondary (Junior High School)'), ('Secondary (Senior High School)') AS v(level_of_education)) e CROSS JOIN (SELECT sex FROM VALUES ('Both Sexes'), ('Female'), ('Male') AS v(sex)) s"
  },
  {
    "name": "grdp_per_capita",
    "keys": [
      "year",
      "region_code",
      "price_basis",
      "geographic_level"
    ],
    "required": [
      "year",
      "region_code",
      "price_basis",
      "geographic_level",
      "region_name"
    ],
    "key_incomplete": "f.`year` IS NULL OR NULLIF(TRIM(f.`region_code`), '') IS NULL OR f.`price_basis` IS NULL OR NULLIF(TRIM(f.`geographic_level`), '') IS NULL",
    "core_incomplete": "f.`year` IS NULL OR NULLIF(TRIM(f.`region_code`), '') IS NULL OR f.`price_basis` IS NULL OR NULLIF(TRIM(f.`geographic_level`), '') IS NULL OR NULLIF(TRIM(f.`region_name`), '') IS NULL",
    "measurement_state": "CASE WHEN f.`grdp_per_capita` IS NOT NULL THEN 'available' ELSE 'unclassified' END",
    "value_valid": "f.grdp_per_capita > 0",
    "exception": "f.region_code='NIR' AND f.year IN (2021,2022,2023)",
    "expected": "SELECT y.year, r.region_code, CASE WHEN b.basis = 'constant' THEN 2018 ELSE y.year END AS price_basis, 'region' AS geographic_level FROM expected_years y CROSS JOIN expected_regions r CROSS JOIN (SELECT basis FROM VALUES ('constant'), ('current') AS v(basis)) b UNION ALL SELECT year, 'PHL', year, 'national' FROM expected_years"
  },
  {
    "name": "hospital",
    "keys": [
      "year",
      "region_code",
      "hospital_type"
    ],
    "required": [
      "year",
      "region_code",
      "hospital_type",
      "region_name"
    ],
    "key_incomplete": "f.`year` IS NULL OR NULLIF(TRIM(f.`region_code`), '') IS NULL OR NULLIF(TRIM(f.`hospital_type`), '') IS NULL",
    "core_incomplete": "f.`year` IS NULL OR NULLIF(TRIM(f.`region_code`), '') IS NULL OR NULLIF(TRIM(f.`hospital_type`), '') IS NULL OR NULLIF(TRIM(f.`region_name`), '') IS NULL",
    "measurement_state": "CASE WHEN f.`regulated_hospital_count` IS NOT NULL THEN 'available' ELSE 'unclassified' END",
    "value_valid": "f.regulated_hospital_count >= 0",
    "exception": "FALSE",
    "expected": "SELECT y.year, r.region_code, 'Government' AS hospital_type FROM expected_years y CROSS JOIN expected_regions r WHERE y.year <= 2024 AND r.region_code <> 'NIR'"
  },
  {
    "name": "population",
    "keys": [
      "year",
      "region_code",
      "age_group",
      "sex"
    ],
    "required": [
      "year",
      "region_code",
      "age_group",
      "sex",
      "region_name"
    ],
    "key_incomplete": "f.`year` IS NULL OR NULLIF(TRIM(f.`region_code`), '') IS NULL OR NULLIF(TRIM(f.`age_group`), '') IS NULL OR NULLIF(TRIM(f.`sex`), '') IS NULL",
    "core_incomplete": "f.`year` IS NULL OR NULLIF(TRIM(f.`region_code`), '') IS NULL OR NULLIF(TRIM(f.`age_group`), '') IS NULL OR NULLIF(TRIM(f.`sex`), '') IS NULL OR NULLIF(TRIM(f.`region_name`), '') IS NULL",
    "measurement_state": "CASE WHEN f.`population` IS NOT NULL THEN 'available' ELSE 'unclassified' END",
    "value_valid": "f.population >= 0",
    "exception": "FALSE",
    "expected": "SELECT y.year, r.region_code, a.age_group, 'Both' AS sex FROM expected_years y CROSS JOIN expected_regions r CROSS JOIN (SELECT age_group FROM VALUES ('0 - 4'), ('5 - 9'), ('10 - 14'), ('15 - 19'), ('20 - 24'), ('25 - 29'), ('30 - 34'), ('35 - 39'), ('40 - 44'), ('45 - 49'), ('50 - 54'), ('55 - 59'), ('60 - 64'), ('65 - 69'), ('70 - 74'), ('75 - 79'), ('80 - 84'), ('85 and over') AS v(age_group)) a WHERE r.region_code <> 'NIR'"
  },
  {
    "name": "poverty_incidence",
    "keys": [
      "year",
      "region_code",
      "indicator"
    ],
    "required": [
      "year",
      "region_code",
      "indicator",
      "region_name"
    ],
    "key_incomplete": "f.`year` IS NULL OR NULLIF(TRIM(f.`region_code`), '') IS NULL OR NULLIF(TRIM(f.`indicator`), '') IS NULL",
    "core_incomplete": "f.`year` IS NULL OR NULLIF(TRIM(f.`region_code`), '') IS NULL OR NULLIF(TRIM(f.`indicator`), '') IS NULL OR NULLIF(TRIM(f.`region_name`), '') IS NULL",
    "measurement_state": "CASE WHEN f.value_status IN ('available','below_0_05_pct') AND f.poverty_incidence_pct IS NOT NULL THEN 'available' ELSE 'unclassified' END",
    "value_valid": "f.poverty_incidence_pct BETWEEN 0 AND 100",
    "exception": "f.region_code='NIR' AND f.year IN (2021,2023) AND f.region_mapping_source='poverty_override'",
    "expected": "SELECT y.year, r.region_code, i.indicator FROM expected_years y CROSS JOIN expected_regions r CROSS JOIN (SELECT indicator FROM VALUES ('poverty_incidence_families'), ('poverty_incidence_population') AS v(indicator)) i WHERE y.year IN (2021, 2023, 2025)"
  },
  {
    "name": "region_boundaries",
    "keys": [
      "region_code"
    ],
    "required": [
      "region_code",
      "region_name"
    ],
    "key_incomplete": "NULLIF(TRIM(f.`region_code`), '') IS NULL",
    "core_incomplete": "NULLIF(TRIM(f.`region_code`), '') IS NULL OR NULLIF(TRIM(f.`region_name`), '') IS NULL",
    "measurement_state": "CASE WHEN NULLIF(TRIM(f.geometry_json),'') IS NOT NULL THEN 'available' ELSE 'unclassified' END",
    "value_valid": "GET_JSON_OBJECT(f.geometry_json, '$.type') = f.geometry_type AND ((f.geometry_type = 'Polygon' AND SIZE(FROM_JSON(GET_JSON_OBJECT(f.geometry_json, '$.coordinates'), 'ARRAY<ARRAY<ARRAY<DOUBLE>>>')) > 0) OR (f.geometry_type = 'MultiPolygon' AND SIZE(FROM_JSON(GET_JSON_OBJECT(f.geometry_json, '$.coordinates'), 'ARRAY<ARRAY<ARRAY<ARRAY<DOUBLE>>>>')) > 0))",
    "exception": "FALSE",
    "expected": "SELECT region_code FROM expected_regions"
  },
  {
    "name": "regional_appropriations",
    "keys": [
      "year",
      "category",
      "particular",
      "region_code"
    ],
    "required": [
      "year",
      "category",
      "particular",
      "region_code",
      "region_name"
    ],
    "key_incomplete": "f.`year` IS NULL OR NULLIF(TRIM(f.`category`), '') IS NULL OR NULLIF(TRIM(f.`particular`), '') IS NULL OR NULLIF(TRIM(f.`region_code`), '') IS NULL",
    "core_incomplete": "f.`year` IS NULL OR NULLIF(TRIM(f.`category`), '') IS NULL OR NULLIF(TRIM(f.`particular`), '') IS NULL OR NULLIF(TRIM(f.`region_code`), '') IS NULL OR NULLIF(TRIM(f.`region_name`), '') IS NULL",
    "measurement_state": "CASE WHEN f.`appropriation_amount` IS NOT NULL THEN 'available' ELSE 'unclassified' END",
    "value_valid": "f.appropriation_amount >= 0",
    "exception": "FALSE",
    "expected": ""
  },
  {
    "name": "regional_obligations",
    "keys": [
      "year",
      "category",
      "particular",
      "region_code"
    ],
    "required": [
      "year",
      "category",
      "particular",
      "region_code",
      "region_name"
    ],
    "key_incomplete": "f.`year` IS NULL OR NULLIF(TRIM(f.`category`), '') IS NULL OR NULLIF(TRIM(f.`particular`), '') IS NULL OR NULLIF(TRIM(f.`region_code`), '') IS NULL",
    "core_incomplete": "f.`year` IS NULL OR NULLIF(TRIM(f.`category`), '') IS NULL OR NULLIF(TRIM(f.`particular`), '') IS NULL OR NULLIF(TRIM(f.`region_code`), '') IS NULL OR NULLIF(TRIM(f.`region_name`), '') IS NULL",
    "measurement_state": "CASE WHEN f.value_status='numeric' AND f.expenditure_amount IS NOT NULL THEN 'available' WHEN f.value_status IN ('dash','blank') AND (f.expenditure_amount IS NULL OR f.expenditure_amount=0) THEN 'source_unavailable' ELSE 'unclassified' END",
    "value_valid": "f.expenditure_amount >= 0",
    "exception": "FALSE",
    "expected": ""
  },
  {
    "name": "unemployment_rate",
    "keys": [
      "year",
      "region_code"
    ],
    "required": [
      "year",
      "region_code",
      "region_name"
    ],
    "key_incomplete": "f.`year` IS NULL OR NULLIF(TRIM(f.`region_code`), '') IS NULL",
    "core_incomplete": "f.`year` IS NULL OR NULLIF(TRIM(f.`region_code`), '') IS NULL OR NULLIF(TRIM(f.`region_name`), '') IS NULL",
    "measurement_state": "CASE WHEN f.`unemployment_rate` IS NOT NULL THEN 'available' ELSE 'unclassified' END",
    "value_valid": "f.unemployment_rate BETWEEN 0 AND 100",
    "exception": "FALSE",
    "expected": "SELECT y.year, r.region_code FROM expected_years y CROSS JOIN expected_regions r WHERE r.region_code <> 'NIR' OR y.year >= 2024"
  },
  {
    "name": "service_access",
    "keys": [
      "year",
      "service_measure",
      "region_code",
      "breakdown_type",
      "breakdown_value"
    ],
    "required": [
      "year",
      "service_measure",
      "region_code",
      "breakdown_type",
      "breakdown_value",
      "region_name"
    ],
    "key_incomplete": "f.`year` IS NULL OR NULLIF(TRIM(f.`service_measure`), '') IS NULL OR NULLIF(TRIM(f.`region_code`), '') IS NULL OR NULLIF(TRIM(f.`breakdown_type`), '') IS NULL OR NULLIF(TRIM(f.`breakdown_value`), '') IS NULL",
    "core_incomplete": "f.`year` IS NULL OR NULLIF(TRIM(f.`service_measure`), '') IS NULL OR NULLIF(TRIM(f.`region_code`), '') IS NULL OR NULLIF(TRIM(f.`breakdown_type`), '') IS NULL OR NULLIF(TRIM(f.`breakdown_value`), '') IS NULL OR NULLIF(TRIM(f.`region_name`), '') IS NULL",
    "measurement_state": "CASE WHEN f.`value` IS NOT NULL THEN 'available' ELSE 'unclassified' END",
    "value_valid": "f.value BETWEEN 0 AND 100",
    "exception": "FALSE",
    "expected": "SELECT y.year, m.service_measure, r.region_code, 'Total' AS breakdown_type, m.breakdown_value FROM expected_years y CROSS JOIN expected_regions r CROSS JOIN (SELECT service_measure, breakdown_value FROM VALUES ('at_least_basic_drinking_water_access', 'All families'), ('basic_sanitation_access', 'All families'), ('basic_handwashing_facilities', 'Consenting families') AS v(service_measure, breakdown_value)) m WHERE y.year IN (2022, 2024) AND r.region_code <> 'NIR'"
  },
  {
    "name": "shared_region_crosswalk",
    "keys": [
      "source_region",
      "region_code",
      "region_name"
    ],
    "required": [
      "source_region",
      "region_code",
      "region_name"
    ],
    "key_incomplete": "NULLIF(TRIM(f.`source_region`), '') IS NULL OR NULLIF(TRIM(f.`region_code`), '') IS NULL OR NULLIF(TRIM(f.`region_name`), '') IS NULL",
    "core_incomplete": "NULLIF(TRIM(f.`source_region`), '') IS NULL OR NULLIF(TRIM(f.`region_code`), '') IS NULL OR NULLIF(TRIM(f.`region_name`), '') IS NULL",
    "measurement_state": "'available'",
    "value_valid": "f.valid_from_year IS NULL OR f.valid_to_year IS NULL OR f.valid_from_year <= f.valid_to_year",
    "exception": "FALSE",
    "expected": ""
  }
] %}
WITH
expected_regions AS (
    SELECT region_code FROM VALUES
        ('I'), ('II'), ('III'), ('IVA'), ('IVB'), ('V'), ('VI'), ('VII'), ('VIII'),
        ('IX'), ('X'), ('XI'), ('XII'), ('XIII'), ('NCR'), ('CAR'), ('BARMM'), ('NIR') AS r(region_code)
),
expected_years AS (SELECT EXPLODE(SEQUENCE(2021, 2025)) AS year)
{% for d in definitions %}
, {{ d.name }}_flags AS (
    SELECT f.*,
        STRUCT({% for k in d['keys'] %}f.`{{ k }}`{% if not loop.last %}, {% endif %}{% endfor %}) AS business_key,
        ({{ d.key_incomplete }}) AS key_incomplete,
        ({{ d.core_incomplete }}) AS core_incomplete,
        {{ d.measurement_state }} AS measurement_state,
        COALESCE(({{ d.value_valid }}), FALSE) AS value_valid,
        (NULLIF(TRIM(f.region_code),'') IS NOT NULL AND EXISTS (
            SELECT 1 FROM {{ ref('shared_region_crosswalk') }} c
            WHERE c.region_code=f.region_code)) AS code_known,
        {% if d.name in ['region_boundaries', 'shared_region_crosswalk'] %}
        'not_applicable'
        {% else %}
        CASE
            WHEN NULLIF(TRIM(f.region_code),'') IS NULL THEN 'invalid'
            WHEN NOT EXISTS (SELECT 1 FROM {{ ref('shared_region_crosswalk') }} c
                             WHERE c.region_code=f.region_code) THEN 'invalid'
            WHEN f.year IS NULL THEN 'unresolved'
            WHEN EXISTS (SELECT 1 FROM {{ ref('shared_region_crosswalk') }} c
                         WHERE c.region_code=f.region_code
                           AND f.year BETWEEN COALESCE(c.valid_from_year,1900)
                                          AND COALESCE(c.valid_to_year,9999)) THEN 'year_valid'
            WHEN {{ d.exception }} THEN 'approved_exception'
            {% if d.name == 'completion_rate' %}
            WHEN f.completion_rate IS NULL AND f.value_status IN
                ('source_marker_two_dots','source_marker_three_dots','missing_blank') THEN 'missing_placeholder'
            {% endif %}
            ELSE 'unresolved'
        END
        {% endif %} AS mapping_state
    FROM {{ ref(d.name) }} f
),
{{ d.name }}_stats AS (
    SELECT COUNT(*) AS observed_rows,
        COALESCE(COUNT_IF(NOT core_incomplete), 0) AS complete_rows,
        COALESCE(COUNT_IF(NOT key_incomplete), 0) AS complete_keys,
        COUNT(DISTINCT CASE WHEN NOT key_incomplete THEN business_key END) AS distinct_keys,
        COALESCE(COUNT_IF(measurement_state='available'), 0) AS available_rows,
        COALESCE(COUNT_IF(measurement_state='source_unavailable'), 0) AS source_unavailable_rows,
        COALESCE(COUNT_IF(measurement_state='unclassified'), 0) AS unclassified_rows,
        COALESCE(COUNT_IF(measurement_state='available' AND value_valid), 0) AS valid_rows,
        COALESCE(COUNT_IF(code_known), 0) AS known_codes,
        COALESCE(COUNT_IF(mapping_state IN ('year_valid','approved_exception')), 0) AS mapped_rows,
        COALESCE(COUNT_IF(mapping_state='approved_exception'), 0) AS exception_rows,
        COALESCE(COUNT_IF(mapping_state='missing_placeholder'), 0) AS placeholder_rows,
        COALESCE(COUNT_IF(mapping_state='unresolved'), 0) AS unresolved_mapping_rows,
        COALESCE(COUNT_IF(mapping_state='invalid'), 0) AS invalid_mapping_rows
    FROM {{ d.name }}_flags
)
{% if d.expected %}
, {{ d.name }}_expected AS ({{ d.expected }}),
{{ d.name }}_coverage AS (
    SELECT s.*,
        (SELECT COUNT(*) FROM {{ d.name }}_expected) AS expected_rows,
        (SELECT COUNT(*) FROM {{ d.name }}_expected e WHERE EXISTS (
            SELECT 1 FROM {{ d.name }}_flags f WHERE NOT f.key_incomplete
              AND f.business_key=STRUCT({% for k in d['keys'] %}e.`{{ k }}`{% if not loop.last %}, {% endif %}{% endfor %})
        )) AS present_expected_rows,
        (SELECT COUNT(DISTINCT f.business_key) FROM {{ d.name }}_flags f
         WHERE NOT f.key_incomplete AND NOT EXISTS (
            SELECT 1 FROM {{ d.name }}_expected e
            WHERE f.business_key=STRUCT({% for k in d['keys'] %}e.`{{ k }}`{% if not loop.last %}, {% endif %}{% endfor %})
        )) AS unexpected_keys
    FROM {{ d.name }}_stats s
)
{% endif %}
{% endfor %}
, boundary_presence_flags AS (
    SELECT EXISTS (SELECT 1 FROM {{ ref('region_boundaries') }} b
                   WHERE b.region_code=e.region_code
                     AND NULLIF(TRIM(b.geometry_json),'') IS NOT NULL) AS has_geometry
    FROM expected_regions e
)
{% for d in definitions %}
{% set src=d.name ~ '_stats' %}
{% if not loop.first %}UNION ALL{% endif %}
{{ silver_health_metric(d.name, 'required_identity_completeness', 'complete_rows', 'observed_rows',
    'Required identity fields: ' ~ d.required | join(', ') ~ '. Row-based completeness; optional measures and metadata are not included.', src,
    invalid='observed_rows-complete_rows') }}
UNION ALL
{% if d.name == 'shared_region_crosswalk' %}
{{ silver_health_metric(d.name, 'business_key_uniqueness', 'NULL', 'NULL',
    'No approved unique alias key. Repeated aliases across years are not automatically duplicates.', src,
    excluded='observed_rows', status='Not assessed - key not established') }}
UNION ALL
{{ silver_health_metric(d.name, 'measurement_availability', 'NULL', 'NULL',
    'Reference table has no primary measurement.', src, excluded='observed_rows', status='Not applicable') }}
{% else %}
{{ silver_health_metric(d.name, 'business_key_uniqueness', 'distinct_keys', 'complete_keys',
    'Distinct typed business keys divided by complete-key rows. Duplicate excess rows reduce the percentage; missing keys are excluded and measured separately.', src,
    excluded='observed_rows-complete_keys', invalid='complete_keys-distinct_keys') }}
UNION ALL
{{ silver_health_metric(d.name, 'measurement_availability', 'available_rows', 'observed_rows',
    'Reported primary measure among stored rows. Numeric zero is present. Confirmed source-unavailable markers remain separate; unknown statuses are unclassified.', src,
    unresolved='unclassified_rows') }}
{% endif %}
UNION ALL
{% set metric='primary_value_validity' %}
{% set rule='Primary numeric measure only: ' ~ d.value_valid ~ '. Missing/unavailable or unclassified measurements are excluded; this is not independent source accuracy.' %}
{% if d.name == 'region_boundaries' %}
{% set metric='geometry_structure_validity' %}
{% set rule='Nonempty typed Polygon/MultiPolygon coordinate array with matching geometry_type. Does not validate every ring, topology, CRS, or positional accuracy.' %}
{% elif d.name == 'shared_region_crosswalk' %}
{% set metric='interval_validity' %}
{% set rule='Validity interval is ordered when both endpoints exist; NULL endpoints follow unbounded mapping behavior.' %}
{% endif %}
{{ silver_health_metric(d.name, metric, 'valid_rows', 'available_rows', rule, src,
    excluded='observed_rows-available_rows', unresolved='unclassified_rows', invalid='available_rows-valid_rows') }}
{% if d.name != 'shared_region_crosswalk' %}
UNION ALL
{{ silver_health_metric(d.name, 'canonical_code_membership', 'known_codes', 'observed_rows',
    'Canonical code exists in shared crosswalk; EXISTS prevents alias multiplication. Does not prove year applicability, matched source names, or boundary comparability.', src,
    invalid='observed_rows-known_codes') }}
{% if d.name != 'region_boundaries' %}
UNION ALL
{{ silver_health_metric(d.name, 'year_mapping_applicability', 'mapped_rows', 'observed_rows-placeholder_rows',
    'Year-valid code or exact Silver-approved historical NIR exception. Completion missing-source placeholders outside validity are excluded. GRDP provenance is established by its Silver transformation, not independently rechecked here.', src,
    excluded='placeholder_rows', unresolved='unresolved_mapping_rows', invalid='invalid_mapping_rows') }}
{% endif %}
{% endif %}
UNION ALL
{% if d.expected %}
{{ silver_health_metric(d.name, 'expected_key_coverage', 'present_expected_rows', 'expected_rows',
    'Expected distinct keys from fixed 2021-2025 project/source contract, not inferred from present rows. Source-unavailable placeholder rows count as present; measurement availability is separate. Unexpected keys are reported for review.', d.name ~ '_coverage',
    excluded='observed_rows-complete_keys', unresolved='unexpected_keys', missing='expected_rows-present_expected_rows') }}
{% else %}
{{ silver_health_metric(d.name, 'expected_key_coverage', 'NULL', 'NULL',
    'No approved independent expected key list for budget details or crosswalk aliases. Not inferred from existing rows.', src,
    status='Not assessed - expected key reference needed') }}
{% endif %}
{% endfor %}
UNION ALL
SELECT 'region_boundaries' AS dataset, 'boundary_presence' AS metric,
    (SELECT COUNT(*) FROM {{ ref('region_boundaries') }}) AS observed_rows,
    COUNT_IF(has_geometry) AS numerator,
    COUNT(*) AS denominator,
    ROUND(100.0 * COUNT_IF(has_geometry) / NULLIF(COUNT(*),0),2) AS percentage,
    0 AS excluded_rows, 0 AS unresolved_rows, 0 AS invalid_rows,
    COUNT_IF(NOT has_geometry) AS missing_expected_rows,
    0 AS source_unavailable_rows, 0 AS unclassified_rows, 0 AS exception_rows,
    'Assessed' AS assessment_status,
    'Nonblank geometry for each of 18 expected regional codes in this source snapshot. CO, NW, and PHL are not polygon requirements; presence is not geometry accuracy.' AS rule_description,
    CURRENT_TIMESTAMP() AS assessed_at
FROM boundary_presence_flags
{% endmacro %}

{% macro create_silver_health_view(results) %}
  {% if not execute or flags.WHICH != 'build' or not var('enable_dq_monitoring', true) %}
    {{ return('') }}
  {% endif %}
  {% set required = ['completion_rate','grdp_per_capita','hospital','population','poverty_incidence','region_boundaries','regional_appropriations','regional_obligations','unemployment_rate','service_access','shared_region_crosswalk'] %}
  {% set successful = [] %}
  {% for res in results %}
    {% if res.node.resource_type == 'model' and res.status | string == 'success' %}
      {% do successful.append(res.node.name) %}
    {% endif %}
  {% endfor %}
  {% for name in required %}
    {% if name not in successful %}
      {{ log('Silver health view not refreshed: build must include all 11 successful Silver models.', info=true) }}
      {{ return('') }}
    {% endif %}
  {% endfor %}
  {% set gold = var('gold_schema', 'dev_gold') %}
  {% set default_schema = gold[:-5] ~ '_monitoring' if gold.endswith('_gold') else gold ~ '_monitoring' %}
  {% set ns = adapter.quote(var('pondolens_catalog')) ~ '.' ~ adapter.quote(var('monitoring_schema', default_schema)) %}
  {% do run_query('CREATE SCHEMA IF NOT EXISTS ' ~ ns) %}
  {% do run_query('CREATE OR REPLACE VIEW ' ~ ns ~ '.`dq_silver_health` AS ' ~ silver_health_sql()) %}
  {{ log('Silver health view ready: ' ~ ns ~ '.dq_silver_health', info=true) }}
  {{ return('SELECT 1') }}
{% endmacro %}
