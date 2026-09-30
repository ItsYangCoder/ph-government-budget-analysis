"""Mappings inspected against the supplied DBM and PSA workbooks."""

from decimal import Decimal
import re

from .common import clean, effective, number, numeric_cell, record, value, year_from_title

SECTORS = {"ECONOMIC SERVICES", "SOCIAL SERVICES", "DEFENSE", "GENERAL PUBLIC SERVICES",
           "NET LENDING", "DEBT SERVICE"}
FUND_LABELS = {"Current Year Budget", "Agency Specific Budget", "Special Purpose Funds",
               "Automatic Appropriations", "Unprogrammed Appropriations", "Unprogrammed Fund",
               "Continuing Appropriation", "Continuing Appropriations", "Unobligated Allotment",
               "Special Appropriations", "Departments", "Special Appropriations, RA No 11494"}
AGENCY_MEASURES = ["base_appropriations", "adjustments", "available_appropriations",
                   "allotments", "obligations", "unobligated_allotments"]
EXPENSES = ["PS", "MOOE", "FINEX", "CO", "TOTAL"]
KNOWN_GAA = {
    "40e48e2b9cdc1ff52119f4b6a7a6bcb67ddce06a07c043f45695876a2ab045dc":
        (2024, "13008421", "https://www.dbm.gov.ph/wp-content/uploads/GAA/GAA2024/VolumeI/CONGRESS/A.pdf"),
    "fac03cb846b498d4b25a6e22fbf44ca4482b5dad7d36e97633e507197e2517e3":
        (2025, "13930174", "https://www.dbm.gov.ph/wp-content/uploads/GAA/GAA2025/VolumeIA/CONGRESS/A.pdf"),
}


def agency(rows, controls, config):
    year = None
    summary = {}
    funding = False
    context = ""
    section = "departments"
    department_totals = []
    summary_year = None
    for sheet, row, cells in rows:
        label_raw = value(cells, 1)
        label = clean(label_raw)
        if row == 1:
            year = year_from_title(cells)
            controls.require(year in {2024, 2025}, f"Unexpected agency year in {sheet}")
            context = ""
            funding = False
            section = "departments"
        if row == 3:
            controls.require("thousand pesos" in label.lower(), f"Agency unit changed: {sheet}")
        if row == 4:
            controls.require("ALLOTMENTS" in clean(value(cells, 17)) and
                             "OBLIGATIONS" in clean(value(cells, 22)), f"Agency columns changed: {sheet}")
        if row < 7 or not label:
            continue
        if "BY FUNDING SOURCE" in label.upper():
            funding = True
        is_summary = sheet in {"SUMMARY", "SUM"}
        has_money = any(numeric_cell(cells, c) is not None for c in range(2, 32))
        if not has_money:
            continue
        if is_summary:
            if label.startswith("B. SPECIAL PURPOSE"):
                section = "special_purpose_funds"
            if label.startswith("C. AUTOMATIC"):
                section = "automatic_appropriations"
            level = "funding_breakdown" if funding or label in FUND_LABELS else (
                "grand_total" if label.upper() == "GRAND TOTAL" else
                "subtotal" if re.match(r"[ABC]\. ", label) else "department_or_fund")
            dataset = "agency_summary"
            context = label
        else:
            dataset = "agency_detail_candidates"
            level = "unmapped_hierarchy"
            if label not in FUND_LABELS:
                context = label
        for column in range(2, 37):
            if column not in cells:
                continue
            if column <= 31:
                measure = AGENCY_MEASURES[(column - 2) // 5]
                expense = EXPENSES[(column - 2) % 5]
                unit = "thousand_PHP"
            else:
                measure = {32: "obligation_rate", 33: "disbursements", 34: "disbursement_obligation_rate",
                           35: "disbursement_appropriation_rate", 36: "unreleased_appropriations"}[column]
                expense = "TOTAL"
                unit = "ratio" if column in {32, 34, 35} else "thousand_PHP"
            eligible = is_summary and level != "funding_breakdown"
            key = [year, label, level, section, measure, expense] if eligible else [year, sheet, row, column]
            item = record(dataset, sheet, row, column, cells[column], unit=unit, key=key,
                         eligible=eligible, year=year, entity=label, parent_entity=context,
                         measure=measure, expense_class=expense, record_level=level, section=section,
                         reporting_basis="agency_financial_statement", status="actual")
            if unit == "ratio" and item["value_status"] == "source_excel_error" and value(cells, column) == "#DIV/0!":
                item["value_status"] = "undefined_rate"
            yield item
        if is_summary and not funding:
            summary_year = year
            summary[label] = {c: numeric_cell(cells, c) for c in range(2, 37)}
            if section == "departments" and level == "department_or_fund":
                department_totals.append(summary[label])
            for start in range(2, 32, 5):
                parts = [numeric_cell(cells, c) for c in range(start, start + 4)]
                if all(x is not None for x in parts):
                    controls.reconcile(f"{year}:{label}:expense_total:{start}",
                                       numeric_cell(cells, start + 4), sum(parts, Decimal(0)))
    # Summary preserves the workbook's department/SPF reporting level; detail is retained separately.
    controls.require(bool(summary), "No agency summary rows")
    agency_total = next((v for k, v in summary.items() if k.startswith("A. TOTAL NATIONAL GOVERNMENT")), None)
    controls.require(agency_total is not None, "Agency summary department subtotal missing")
    if agency_total:
        for column in list(range(2, 32)) + [33, 36]:
            values = [r[column] for r in department_totals]
            controls.reconcile(f"{summary_year}:departments_to_NGA_total:{column}", agency_total[column],
                               sum(values, Decimal(0)) if all(x is not None for x in values) else None)
    for label, amounts in summary.items():
        for offset in range(5):
            a, b, total = amounts[2 + offset], amounts[7 + offset], amounts[12 + offset]
            if all(x is not None for x in [a, b, total]):
                controls.reconcile(f"{summary_year}:{label}:available:{offset}", total, a + b)
            allotment, obligation, balance = amounts[17 + offset], amounts[22 + offset], amounts[27 + offset]
            if all(x is not None for x in [allotment, obligation, balance]):
                controls.reconcile(f"{summary_year}:{label}:balance:{offset}", balance, allotment - obligation)
    controls.notes.append("Agency details remain hierarchy candidates and are excluded from analytical views.")


def gaa(rows, controls, config):
    headers = {}
    year = None
    amount_count = 0
    amount_sum = Decimal(0)
    control_totals = []
    known = KNOWN_GAA.get(config.get("source_sha256"))
    unit = config.get("gaa_unit") or ("thousand_PHP" if known else "unverified")
    evidence = config.get("gaa_unit_evidence") or (known[2] if known else None)
    controls.require(unit != "unverified" and bool(evidence),
                     "GAA AMT unit requires documented verification (--gaa-unit and --gaa-unit-evidence).")
    if known:
        controls.require(unit == "thousand_PHP", "Known GAA source uses thousand pesos; conflicting unit override")
    unit_sample_sum = Decimal(0)
    mapping = {"DEPARTMENT": "department_code", "UACS_DPT_DSC": "department",
               "AGENCY": "agency_code", "UACS_AGY_DSC": "entity", "PREXC_FPAP_ID": "program_code",
               "PREXC_LEVEL": "program_level", "DSC": "program", "OPERUNIT": "operating_unit",
               "UACS_OPER_DSC": "operating_unit_name", "UACS_REG_ID": "region_code",
               "UACS_OPERDIV_ID": "division_code", "UACS_DIV_DSC": "division",
               "FUNDCD": "fund_code", "UACS_FUNDSUBCAT_DSC": "fund",
               "UACS_EXP_CD": "expense_code", "UACS_EXP_DSC": "expense_class",
               "UACS_SOBJ_CD": "subobject_code", "UACS_SOBJ_DSC": "subobject", "SORDER": "source_order"}
    for sheet, row, cells in rows:
        if row == 1:
            headers = {clean(effective(c)): col for col, c in cells.items()}
            controls.require({"AMT", "DEPARTMENT", "AGENCY", "PREXC_FPAP_ID", "FUNDCD",
                              "UACS_SOBJ_CD"} <= headers.keys(), "GAA headers changed")
            if "AMT" not in headers:
                raise ValueError("GAA AMT header missing")
            year_match = re.search(r"20\d{2}", config["source"])
            year = known[0] if known else int(year_match[0]) if year_match else None
            controls.require(year in {2024, 2025}, "GAA year not identified")
            continue
        column = headers["AMT"]
        if column not in cells:
            continue  # Program headings have no monetary amount and remain in originals/structure.
        dims = {target: clean(value(cells, headers[name])) if name in headers else ""
                for name, target in mapping.items()}
        if not any(dims[k] for k in ["department_code", "agency_code", "program_code", "fund_code", "subobject_code"]):
            control_totals.append(numeric_cell(cells, column))
            yield record("approved_budget_controls", sheet, row, column, cells[column], unit=unit,
                         key=[year, "grand_total", row], eligible=False, year=year,
                         measure="approved_appropriations", record_level="grand_total", status="approved")
            continue
        if "YEAR" in headers:
            controls.require(clean(value(cells, headers["YEAR"])) == f"GAA-{year}", f"GAA year mismatch row {row}")
        key = [year, *[dims[k] for k in ["department_code", "agency_code", "program_code", "program_level",
                                       "operating_unit", "region_code", "division_code", "fund_code",
                                       "expense_code", "subobject_code"]]]
        yield record("approved_budget", sheet, row, column, cells[column], unit=unit, key=key,
                     year=year, measure="approved_appropriations", status="approved",
                     record_level="budget_line", **dims)
        amount_count += 1
        amount = numeric_cell(cells, column)
        if amount is not None:
            amount_sum += amount
            if dims["department_code"] == "01" and dims["agency_code"] == "001" and dims["fund_code"] == "01101101":
                unit_sample_sum += amount
    controls.require(amount_count > 0, "No GAA amount rows")
    controls.require(len(control_totals) == 1, f"Expected one GAA control total, found {len(control_totals)}")
    if len(control_totals) == 1:
        controls.reconcile(f"GAA:{year}:budget_lines_to_workbook_total", control_totals[0], amount_sum, "0")
    if known:
        controls.reconcile(f"GAA:{year}:Senate_specific_budget_to_official_GAA", Decimal(known[1]), unit_sample_sum, "0")
    if evidence:
        controls.notes.append(f"GAA amount unit: {unit}. Verification reference: {evidence}")
    controls.notes.append("GAA is already long. Workbook SUM control is excluded from budget lines. Its AMT header does not specify units; external verification is required.")


def sector(rows, controls, config):
    metric = None
    unit = None
    headers = {}
    basis = {}
    statuses = {}
    periods = {}
    parent = ""
    amounts = {}
    sections = 0
    for sheet, row, cells in rows:
        label_raw = value(cells, 1)
        label = clean(label_raw)
        if "NATIONAL GOVERNMENT" in label and "BY SECTOR" in label:
            sections += 1
            metric = ("real_growth_rate" if "REAL LEVELS GROWTH" in label else
                      "real_expenditure" if "REAL LEVELS" in label else
                      "expenditure_share" if "PERCENT DISTRIBUTION" in label else
                      "growth_rate" if "GROWTH RATES" in label else
                      "expenditure_gdp_share" if "PERCENTAGE OF GDP" in label else
                      "expenditure_per_capita" if "PER CAPITA" in label else "expenditure")
            unit = "percent" if "rate" in metric or "share" in metric else (
                "PHP_per_person" if "per_capita" in metric else "million_PHP")
            headers, basis, statuses, periods, parent = {}, {}, {}, {}, ""
            continue
        year_candidates = {col: int(value(cells, col)) for col in cells
                           if isinstance(value(cells, col), (int, float)) and 1983 <= value(cells, col) <= 2027}
        if not label and len(year_candidates) >= 40 and list(year_candidates.values()) == sorted(set(year_candidates.values())):
            headers = year_candidates
        intervals = {col: re.fullmatch(r"(19\d{2}|20\d{2})-(19\d{2}|20\d{2})", clean(value(cells, col))) for col in cells}
        intervals = {col: match for col, match in intervals.items() if match}
        if not label and len(intervals) >= 40:
            headers = {col: int(match[2]) for col, match in intervals.items()}
            periods = {col: f"{match[1]}-{match[2]}" for col, match in intervals.items()}
        if any("based" in clean(value(cells, col)).lower() for col in cells):
            active = ""
            for col in range(4, 49):
                if "based" in clean(value(cells, col)).lower():
                    active = clean(value(cells, col))
                basis[col] = active
        for col in headers:
            if clean(value(cells, col)) in {"Program", "Proposed"}:
                statuses[col] = clean(value(cells, col)).lower()
        if not metric or not headers or not label:
            continue
        context = label.startswith("Nominal GDP") or label.startswith("Population (") or label.startswith("Implicit") or label == "IPINa/"
        level = "sector" if label in SECTORS else "grand_total" if label == "TOTAL" else (
            "context" if context else "subsector")
        if level == "sector":
            parent = label
        if level == "subsector" and not (str(label_raw).startswith(" ") or label.startswith("*")):
            continue
        for col, year in headers.items():
            if col not in cells:
                continue
            actual_unit = ("million_persons" if label.startswith("Population (") else
                           "million_PHP" if label.startswith("Nominal GDP") else
                           "index_source_base" if label == "IPINa/" else unit)
            actual_metric = clean(label) if context else metric
            yield record("sector_expenditure", sheet, row, col, cells[col], unit=actual_unit,
                         key=[actual_metric, year, label, parent if level == "subsector" else ""],
                         year=year, entity=label, parent_entity=parent if level == "subsector" else "",
                         period=periods.get(col, ""),
                         measure=actual_metric, record_level=level, reporting_basis=basis.get(col, ""),
                         status=statuses.get(col, "actual"), price_basis="real_source_basis" if "real" in metric else "")
            if metric == "expenditure" and level in {"sector", "grand_total"}:
                amounts[(year, label)] = numeric_cell(cells, col)
    controls.require(sections == 7, f"Expected 7 sector sections, found {sections}")
    for year in range(1983, 2028):
        parts = [amounts.get((year, label)) for label in SECTORS]
        controls.reconcile(f"sector:{year}:six_sectors_to_total", amounts.get((year, "TOTAL")),
                           sum(parts, Decimal(0)) if all(x is not None for x in parts) else None, "3")


def population(rows, controls, config):
    headers = {}
    label_columns = []
    regions = set()
    geography = region = province = ""
    level = ""
    grouped = {}
    table1 = {}
    table4 = {}
    for sheet, row, cells in rows:
        if row == 1:
            headers, label_columns, geography, region, province = {}, [], "", "", ""
        if sheet == "Table 2":
            if row == 3:
                headers = {col: clean(effective(c)) for col, c in cells.items() if col > 1}
            elif row > 3 and value(cells, 1) is not None:
                for col, period in headers.items():
                    if col in cells:
                        yield record("population_growth", sheet, row, col, cells[col], unit="percent",
                                     key=[clean(value(cells, 1)), period], entity=clean(value(cells, 1)),
                                     period=period, measure="projected_annual_population_growth", status="projected",
                                     record_level="country" if clean(value(cells, 1)) == "PHILIPPINES" else "region")
            continue
        if row == 4:
            for col, cell in cells.items():
                match = re.fullmatch(r"01 July (20\d{2})", clean(effective(cell)))
                if match:
                    for offset, sex in enumerate(["Both sexes", "Male", "Female"]):
                        headers[col + offset] = (int(match[1]), sex)
        if row == 3:
            label_columns = [col for col in cells if clean(value(cells, col)).startswith("Region,")]
        if row < 7 or not headers:
            continue
        label_col = 2 if sheet == "Table 4" else 1
        label = clean(value(cells, label_col))
        if not label:
            continue
        if sheet == "Table 4":
            flag = clean(value(cells, 1))
            if flag not in {"PH", "R", "P", "C"}:
                continue
            level = {"PH": "country", "R": "region", "P": "province_or_huc", "C": "city_or_municipality"}[flag]
            geography = label
            if flag == "R":
                region, province = label, ""
            if flag == "P":
                province = label
            age = "Total"
        else:
            if not any(col in cells for col in headers):
                geography = label
                if sheet == "Table 1":
                    regions.add(label)
                level = "country" if label == "PHILIPPINES" else "region" if label in regions else "province_or_huc"
                if level == "region":
                    region = label
                continue
            age = label
            if not (age == "Total" or re.fullmatch(r"\d+\s*-\s*\d+|\d+\s*(?:and over|\+)", age, re.I)):
                continue
        controls.require(bool(geography), f"Population geography missing {sheet}:{row}")
        # Repeated side-by-side labels must agree; they identify different years, not duplicates.
        for col in label_columns:
            controls.require(clean(value(cells, col)) == label, f"Population repeated label mismatch {sheet}:{row}:{col}")
        for col, (year, sex) in headers.items():
            if col not in cells:
                continue
            key = [sheet, year, geography, region, province if sheet == "Table 4" else "", age, sex]
            yield record("population_projection", sheet, row, col, cells[col], unit="persons", key=key,
                         year=year, entity=geography, region=region, province=province if sheet == "Table 4" else "",
                         geo_level=level, age_group=age, sex=sex, measure="projected_midyear_population",
                         status="projected", record_level="total_age" if age == "Total" else "age_group",
                         geography_basis="2020_based_projection")
            amount = numeric_cell(cells, col)
            grouped.setdefault((sheet, year, geography, region, province, age), {})[sex] = amount
            if level in {"country", "region"} and age == "Total" and sex == "Both sexes":
                (table4 if sheet == "Table 4" else table1 if sheet == "Table 1" else {})[(year, geography)] = amount
    for key, amounts in grouped.items():
        if all(amounts.get(s) is not None for s in ["Both sexes", "Male", "Female"]):
            controls.reconcile(f"population:{key}:sex_total", amounts["Both sexes"],
                               amounts["Male"] + amounts["Female"], "100")
    for key in sorted(table4):
        controls.reconcile(f"population:table1_table4:{key}", table1.get(key), table4[key], "0")
    controls.require(bool(table4) and bool(table1), "Population tables 1 and 4 not mapped")
    controls.notes.append("Population is projected mid-year, not an observed census count. Geographic joins require a reviewed boundary crosswalk.")


def grdp(rows, controls, config):
    section = None
    price_basis = ""
    headers = {}
    section_count = 0
    declared_years = None
    amounts = {}
    for sheet, row, cells in rows:
        label = clean(value(cells, 1))
        match = re.match(r"Table 2\.([1-6])\b", label)
        if match:
            section = int(match[1]); section_count += 1; headers = {}; price_basis = ""; declared_years = None
            continue
        annual = re.fullmatch(r"Annual (20\d{2}) to (20\d{2})", label)
        if annual:
            declared_years = list(range(int(annual[1]), int(annual[2]) + 1))
        if "Prices" in label:
            price_basis = "constant_2018" if "2018" in label else "current"
        if any(value(cells, c) in {2023, 2024, 2025} for c in range(3, 6)):
            headers = {c: int(value(cells, c)) for c in range(3, 6)
                       if value(cells, c) in {2023, 2024, 2025}}
            if section == 6 and value(cells, 3) == "Annual" and headers == {4: 2024, 5: 2025} and declared_years == [2023, 2024, 2025]:
                headers[3] = 2023
                controls.notes.append("Table 2.6 C183 says Annual instead of 2023. Mapped to 2023 using its Annual 2023 to 2025 title and adjacent 2024/2025 headers.")
        if section in {3, 4}:
            for col in range(3, 6):
                interval = re.fullmatch(r"(20\d{2}) - (20\d{2})", clean(value(cells, col)))
                if interval:
                    headers[col] = int(interval[2])
        entity = clean(value(cells, 2))
        if not section or not entity or not headers:
            continue
        metric = "per_capita_grdp" if section <= 2 else "per_capita_grdp_growth" if section <= 4 else "per_capita_national_index"
        unit = "PHP_per_person" if section <= 2 else "percent" if section <= 4 else "index_national_100"
        for col, year in headers.items():
            if col in cells:
                amounts[(section, entity, year)] = numeric_cell(cells, col)
                yield record("development_indicator", sheet, row, col, cells[col], unit=unit,
                             key=[year, entity, metric, price_basis], year=year, entity=entity,
                             region_code=clean(value(cells, 1)), measure=metric, price_basis=price_basis,
                             record_level="country" if entity == "Philippines" else "region",
                             status="actual", geography_basis="PSA_April_2026_regional_accounts")
    controls.require(section_count == 6, f"Expected 6 GRDP sections, found {section_count}")
    for (sec, entity, year), amount in amounts.items():
        if sec in {3, 4}:
            current, previous = amounts.get((sec - 2, entity, year)), amounts.get((sec - 2, entity, year - 1))
            controls.reconcile(f"GRDP:{sec}:{entity}:{year}:growth", amount,
                               (current / previous - 1) * 100 if current is not None and previous else None, "0.000001")
        if sec in {5, 6}:
            regional, national = amounts.get((sec - 4, entity, year)), amounts.get((sec - 4, "Philippines", year))
            controls.reconcile(f"GRDP:{sec}:{entity}:{year}:national_index", amount,
                               regional / national * 100 if regional is not None and national else None, "0.000001")
    controls.notes.append("Per-capita values and indices cannot be summed across regions. NIR coverage differs from older population layouts.")
