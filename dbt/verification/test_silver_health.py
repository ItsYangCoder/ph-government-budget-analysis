"""Execute metric fixtures offline; this does not replace a connected Databricks build."""
from pathlib import Path
from types import SimpleNamespace

import duckdb
import pytest
import sqlglot
from jinja2 import Environment
from sqlglot import exp

MACROS = Path(__file__).resolve().parents[1] / 'macros'
NAMES = ['completion_rate', 'grdp_per_capita', 'hospital', 'population',
         'poverty_incidence', 'region_boundaries', 'regional_appropriations',
         'regional_obligations', 'unemployment_rate', 'service_access', 'shared_region_crosswalk']


class Returned(Exception):
    pass


def module(**context):
    source = '\n'.join((MACROS / name).read_text() for name in ('dq_monitoring.sql', 'silver_health.sql'))
    return Environment(extensions=['jinja2.ext.do']).from_string(source).make_module(
        {'ref': lambda name: name, **context})


@pytest.fixture(scope='module')
def parsed_query():
    tree = sqlglot.parse_one(str(module().silver_health_sql()), read='databricks',
                             error_level=sqlglot.ErrorLevel.RAISE)
    assert isinstance(tree, exp.Query)
    assert not list(tree.find_all(exp.Insert, exp.Delete, exp.Update, exp.Create))
    assert {t.name for t in tree.find_all(exp.Table)}.issuperset(NAMES)
    return tree


@pytest.fixture
def warehouse(parsed_query):
    con = duckdb.connect()
    con.execute("SET TimeZone='UTC'")
    integers = {'year', 'price_basis', 'valid_from_year', 'valid_to_year'}
    numbers = {'completion_rate', 'grdp_per_capita', 'regulated_hospital_count', 'population',
               'poverty_incidence_pct', 'appropriation_amount', 'expenditure_amount', 'unemployment_rate', 'value'}
    for cte in parsed_query.args['with_'].expressions:
        if cte.alias not in {name + '_flags' for name in NAMES}:
            continue
        cols = {c.name for c in cte.this.find_all(exp.Column) if c.table == 'f' and c.name != '*'}
        definitions = [f'"{c}" ' + ('INTEGER' if c in integers else 'DOUBLE' if c in numbers else 'VARCHAR')
                       for c in sorted(cols)]
        con.execute('CREATE TABLE ' + cte.alias[:-6] + '(' + ','.join(definitions) + ')')
    # Translate syntax, not business rules. Spark and DuckDB accept different FROM_JSON type strings.
    tree = parsed_query.copy()
    for node in list(tree.walk()):
        if isinstance(node, exp.Anonymous) and node.name.upper() == 'FROM_JSON':
            depth = node.expressions[1].this.count('ARRAY')
            node.expressions[1].replace(exp.Literal.string('[' * depth + '"DOUBLE"' + ']' * depth))
    sql = tree.sql(dialect='duckdb')

    def insert(table, **row):
        columns = ','.join('"' + k + '"' for k in row)
        con.execute(f'INSERT INTO {table} ({columns}) VALUES (' + ','.join('?' for _ in row) + ')', list(row.values()))

    def metrics():
        cursor = con.execute(sql)
        columns = [c[0] for c in cursor.description]
        rows = [dict(zip(columns, r)) for r in cursor.fetchall()]
        assert len(rows) == len({(r['dataset'], r['metric']) for r in rows})
        return {(r['dataset'], r['metric']): r for r in rows}

    yield insert, metrics
    con.close()


def test_empty_sources_are_not_100_percent(warehouse):
    _, metrics = warehouse
    rows = metrics()
    for dataset in NAMES:
        row = rows[dataset, 'required_identity_completeness']
        assert row['percentage'] is None and row['numerator'] == row['denominator'] == 0
        assert row['assessment_status'].startswith('Not assessed')
    for dataset, expected in {'completion_rate': 855, 'grdp_per_capita': 185, 'hospital': 68,
                              'population': 1530, 'poverty_incidence': 108, 'region_boundaries': 18,
                              'unemployment_rate': 87, 'service_access': 102}.items():
        row = rows[dataset, 'expected_key_coverage']
        assert row['denominator'] == expected
        assert row['numerator'] == 0 and row['percentage'] == 0
        assert row['missing_expected_rows'] == expected and row['invalid_rows'] == 0
    assert rows['regional_obligations', 'expected_key_coverage']['percentage'] is None


def test_aliases_do_not_multiply_rows_and_zero_is_present(warehouse):
    insert, metrics = warehouse
    for alias in ('Region I', 'REGION I (ILOCOS REGION)', 'I'):
        insert('shared_region_crosswalk', source_region=alias, region_code='I', region_name='Ilocos Region',
               valid_from_year=2021, valid_to_year=2025)
    insert('hospital', year=2021, region_code='I', region_name='Ilocos Region',
           hospital_type='Government', regulated_hospital_count=0)
    rows = metrics()
    for metric in ('canonical_code_membership', 'year_mapping_applicability', 'measurement_availability',
                   'primary_value_validity', 'business_key_uniqueness'):
        assert rows['hospital', metric]['denominator'] == 1
        assert rows['hospital', metric]['percentage'] == 100
    coverage = rows['hospital', 'expected_key_coverage']
    assert coverage['numerator'] == 1 and coverage['missing_expected_rows'] == 67


def test_marker_availability_validity_and_placeholder_are_separate(warehouse):
    insert, metrics = warehouse
    insert('shared_region_crosswalk', source_region='NIR', region_code='NIR', region_name='Negros Island Region',
           valid_from_year=2024, valid_to_year=2025)
    for year, value, status in ((2021, None, 'source_marker_three_dots'), (2024, 0, 'available'),
                                (2025, 101, 'available'), (2025, None, 'unknown')):
        insert('completion_rate', year=year, region_code='NIR', region_name='Negros Island Region',
               indicator='4.1.2 Completion rate', level_of_education='Elementary', sex='Both Sexes',
               completion_rate=value, value_status=status)
    rows = metrics()
    availability = rows['completion_rate', 'measurement_availability']
    assert availability['numerator'] == 2 and availability['denominator'] == 4
    assert availability['source_unavailable_rows'] == 1 and availability['unclassified_rows'] == 1
    validity = rows['completion_rate', 'primary_value_validity']
    assert validity['numerator'] == 1 and validity['denominator'] == 2
    assert validity['invalid_rows'] == 1 and validity['excluded_rows'] == 2
    mapping = rows['completion_rate', 'year_mapping_applicability']
    assert mapping['denominator'] == 3 and mapping['excluded_rows'] == 1
    unique = rows['completion_rate', 'business_key_uniqueness']
    assert unique['numerator'] == 3 and unique['denominator'] == 4


def test_nir_exception_is_exact_and_other_windows_need_review(warehouse):
    insert, metrics = warehouse
    for code in ('NIR', 'I'):
        insert('shared_region_crosswalk', source_region=code, region_code=code, region_name=code,
               valid_from_year=2024, valid_to_year=2025)
    for code, year, provenance in (('NIR', 2021, 'poverty_override'), ('NIR', 2023, 'crosswalk'),
                                    ('I', 2021, 'poverty_override'), ('BAD', 2025, 'crosswalk')):
        insert('poverty_incidence', year=year, region_code=code, region_name=code,
               indicator='poverty_incidence_population', poverty_incidence_pct=0,
               value_status='below_0_05_pct', region_mapping_source=provenance)
    for year in (2021, 2020):
        insert('grdp_per_capita', year=year, region_code='NIR', region_name='NIR',
               grdp_per_capita=100, price_basis=2018, geographic_level='region')
    rows = metrics()
    poverty = rows['poverty_incidence', 'year_mapping_applicability']
    assert poverty['exception_rows'] == poverty['numerator'] == 1
    assert poverty['unresolved_rows'] == 2 and poverty['invalid_rows'] == 1
    grdp = rows['grdp_per_capita', 'year_mapping_applicability']
    assert grdp['exception_rows'] == grdp['numerator'] == 1 and grdp['unresolved_rows'] == 1


def test_typed_keys_avoid_delimiter_collisions_and_exclude_blank_keys(warehouse):
    insert, metrics = warehouse
    for category, particular in (('A|B', 'C'), ('A', 'B|C'), ('A', 'B|C'), ('', 'Missing category')):
        insert('regional_obligations', year=2025, region_code='I', region_name='Ilocos Region',
               category=category, particular=particular, expenditure_amount=10, value_status='numeric')
    rows = metrics()
    row = rows['regional_obligations', 'business_key_uniqueness']
    assert row['numerator'] == 2 and row['denominator'] == 3
    assert row['excluded_rows'] == 1 and row['invalid_rows'] == 1
    assert rows['regional_obligations', 'required_identity_completeness']['percentage'] == 75


def test_obligation_markers_are_not_fabricated_measurements(warehouse):
    insert, metrics = warehouse
    for amount, status in ((0, 'numeric'), (0, 'dash'), (None, 'blank'), (12, 'dash'), (None, 'numeric')):
        insert('regional_obligations', year=2025, region_code='I', region_name='Ilocos Region',
               category='A', particular='B', expenditure_amount=amount, value_status=status)
    row = metrics()['regional_obligations', 'measurement_availability']
    assert row['numerator'] == 1 and row['denominator'] == 5 and row['percentage'] == 20
    assert row['source_unavailable_rows'] == 2 and row['unclassified_rows'] == 2


def test_geometry_presence_does_not_imply_validity(warehouse):
    insert, metrics = warehouse
    insert('region_boundaries', region_code='I', region_name='Ilocos', geometry_type='Polygon',
           geometry_json='{"type":"Polygon","coordinates":[]}')
    insert('region_boundaries', region_code='II', region_name='Cagayan', geometry_type='Polygon',
           geometry_json='{"type":"Polygon","coordinates":[[[120,15],[121,15],[120,15]]]}')
    rows = metrics()
    assert rows['region_boundaries', 'boundary_presence']['numerator'] == 2
    assert rows['region_boundaries', 'geometry_structure_validity']['numerator'] == 1
    assert rows['region_boundaries', 'boundary_presence']['missing_expected_rows'] == 16


def hook(command='build', names=NAMES, gold='prod_gold', enabled=True, execute=True, fail=False):
    calls = []
    results = [SimpleNamespace(node=SimpleNamespace(name=n, resource_type='model'), status='success') for n in names]
    def run_query(sql):
        if fail:
            raise RuntimeError('warehouse error')
        calls.append(sql)
    def returned(value):
        raise Returned(value)
    m = module(execute=execute, flags=SimpleNamespace(WHICH=command),
               var=lambda n, d=None: {'gold_schema': gold, 'pondolens_catalog': 'pondolens',
                                       'enable_dq_monitoring': enabled}.get(n, d),
               adapter=SimpleNamespace(quote=lambda s: '`' + s + '`'),
               run_query=run_query, log=lambda *a, **k: '', **{'return': returned})
    with pytest.raises(Returned):
        m.create_silver_health_view(results)
    return calls


@pytest.mark.parametrize('options', [{'command': 'compile'}, {'command': 'parse'}, {'command': 'test'},
                                     {'names': ['hospital']}, {'enabled': False}, {'execute': False}])
def test_hook_does_not_write_for_partial_or_offline_commands(options):
    assert hook(**options) == []


def test_hook_namespace_and_failure_propagation():
    calls = hook(gold='dbt_test_gold')
    assert len(calls) == 2 and '`pondolens`.`dbt_test_monitoring`' in calls[0]
    assert 'CREATE OR REPLACE VIEW' in calls[1] and 'dq_silver_health' in calls[1]
    for sql in calls:
        sqlglot.parse_one(sql, read='databricks', error_level=sqlglot.ErrorLevel.RAISE)
    with pytest.raises(RuntimeError, match='warehouse error'):
        hook(fail=True)


def test_completion_snapshot_reproduces_availability_without_fixed_score(warehouse):
    insert, metrics = warehouse
    regions = ['I', 'II', 'III', 'IVA', 'IVB', 'V', 'VI', 'VII', 'VIII', 'IX',
               'X', 'XI', 'XII', 'XIII', 'NCR', 'CAR', 'BARMM', 'NIR', 'PHL']
    for year in range(2021, 2026):
        for region in regions:
            for level in ('Elementary', 'Secondary (Junior High School)', 'Secondary (Senior High School)'):
                for sex in ('Both Sexes', 'Female', 'Male'):
                    unavailable = year == 2025 or (region == 'NIR' and year < 2024)
                    insert('completion_rate', year=year, region_code=region, region_name=region,
                           indicator='4.1.2 Completion rate', level_of_education=level, sex=sex,
                           completion_rate=None if unavailable else 90,
                           value_status='source_marker_three_dots' if unavailable else 'available')
    rows = metrics()
    row = rows['completion_rate', 'measurement_availability']
    assert (row['numerator'], row['denominator'], row['percentage']) == (657, 855, 76.84)
    assert row['source_unavailable_rows'] == 198
    assert rows['completion_rate', 'expected_key_coverage']['percentage'] == 100
    # Adding a reported value changes the result on the next query, without rebuilding the view.
    insert('completion_rate', year=2026, region_code='I', region_name='Ilocos',
           indicator='4.1.2 Completion rate', level_of_education='Elementary', sex='Both Sexes',
           completion_rate=0, value_status='available')
    rows = metrics()
    assert rows['completion_rate', 'measurement_availability']['numerator'] == 658
    assert rows['completion_rate', 'measurement_availability']['denominator'] == 856
    assert rows['completion_rate', 'expected_key_coverage']['unresolved_rows'] == 1


@pytest.mark.parametrize('dataset,measure', [('regional_appropriations', 'appropriation_amount'),
                                           ('regional_obligations', 'expenditure_amount')])
def test_budget_only_nationwide_code_is_not_an_invalid_region(warehouse, dataset, measure):
    insert, metrics = warehouse
    row = dict(year=2025, region_code='NW', region_name='NATIONWIDE', category='A', particular='B')
    row[measure] = 0
    if dataset == 'regional_obligations':
        row['value_status'] = 'numeric'
    insert(dataset, **row)
    rows = metrics()
    canonical = rows[dataset, 'canonical_code_membership']
    assert canonical['denominator'] == 0 and canonical['excluded_rows'] == 1
    assert canonical['invalid_rows'] == 0 and canonical['percentage'] is None
    mapping = rows[dataset, 'year_mapping_applicability']
    assert mapping['numerator'] == 1 and mapping['exception_rows'] == 1
    assert mapping['percentage'] == 100 and mapping['invalid_rows'] == 0
