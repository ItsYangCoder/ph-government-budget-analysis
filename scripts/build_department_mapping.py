import csv
import re
import sqlite3
from pathlib import Path


def normalize(name):
    # Remove a trailing abbreviation, such as "(DEPED)".
    name = re.sub(r"\s*\([A-Za-z][A-Za-z0-9&.-]{1,14}\)\s*$", "", name)
    return " ".join(name.casefold().split())


database = Path("outputs/long_form.sqlite").resolve()
output = Path("outputs/department_mapping_review.csv")

if not database.exists():
    raise SystemExit("Missing outputs/long_form.sqlite. Run ingestion first.")

if output.exists():
    raise SystemExit(
        "Review file already exists. Keep it to preserve your review edits."
    )

with sqlite3.connect(database.as_uri() + "?mode=ro", uri=True) as connection:
    actuals = connection.execute("""
        SELECT DISTINCT year, entity
        FROM agency_department_financials
        ORDER BY year, entity
    """).fetchall()

    budgets = connection.execute("""
        SELECT DISTINCT year, department_code, department
        FROM approved_budget
        ORDER BY year, department_code
    """).fetchall()

lookup = {}
for year, code, name in budgets:
    lookup.setdefault((year, normalize(name)), []).append((code, name))

columns = [
    "year",
    "actual_department",
    "candidate_gaa_department_code",
    "candidate_gaa_department",
    "match_method",
    "review_status",
    "scope_verified",
    "review_notes",
]

with output.open("w", encoding="utf-8", newline="") as file:
    writer = csv.DictWriter(file, fieldnames=columns)
    writer.writeheader()

    for year, actual_name in actuals:
        matches = lookup.get((year, normalize(actual_name)), [])

        for code, budget_name in matches or [("", "")]:
            writer.writerow({
                "year": year,
                "actual_department": actual_name,
                "candidate_gaa_department_code": code,
                "candidate_gaa_department": budget_name,
                "match_method": (
                    "normalized_name" if matches else "no_match"
                ),
                "review_status": "REVIEW_REQUIRED",
                "scope_verified": "",
                "review_notes": (
                    "Multiple candidates." if len(matches) > 1 else ""
                ),
            })

print(f"Saved: {output}")
print(f"Actual department/fund entries: {len(actuals)}")