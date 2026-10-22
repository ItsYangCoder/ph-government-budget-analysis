-- Live Silver metrics. Change the catalog/schema here if your build uses another target.
-- Each row is one dataset + metric; do not average different metrics into an overall score.
SELECT
    dataset,
    metric,
    numerator,
    denominator,
    percentage,
    observed_rows,
    excluded_rows,
    unresolved_rows,
    invalid_rows,
    missing_expected_rows,
    source_unavailable_rows,
    unclassified_rows,
    exception_rows,
    assessment_status,
    rule_description,
    assessed_at
FROM pondolens.prod_monitoring.dq_silver_health
ORDER BY dataset, metric;
