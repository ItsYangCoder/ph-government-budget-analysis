# Data sources

Use this guide to find the government reports and tables behind PondoLens. **DBM** publishes budget data. **PSA** publishes population and regional statistics, including tables available through **OpenSTAT**.

The links below point to official publications or source portals. They do not provide ready-to-load copies of the project's prepared files. New releases may contain revisions, different boundaries, or different years.

## What to download

The scope column describes the project's current Silver selection, not everything available on the source website. Open each dataset guide for its transformation rules and coverage notes.

| Dataset | Where to get it | Report or table to look for | Project scope and selection |
|---|---|---|---|
| [Regional appropriations](silver/regional_appropriations.md) | [DBM — Budget of Expenditures and Sources of Financing (BESF)](https://www.dbm.gov.ph/index.php/test/1205-budget-of-expenditures-and-sources-of-financing) | Regional Allocation of the Expenditure Program, by Department/Special Purpose Fund. Select the **GAA (Updated)** series recorded in the source headings. | 2021–2025; amounts in thousand pesos before Silver conversion. Keep approved allocations separate from actual obligations. |
| [Regional obligations](silver/regional_obligations.md) | [DBM — BESF](https://www.dbm.gov.ph/index.php/test/1205-budget-of-expenditures-and-sources-of-financing) | Regional allocation tables, **Actual Obligations** columns. For example, [FY 2027 BESF](https://www.dbm.gov.ph/index.php/2027/budget-of-expenditures-and-sources-of-financing-fy-2027), Table B.6.a, covers FY 2025. | 2021–2025; commitments, not cash payments. Keep Central Office and Nationwide records identifiable. |
| [Population](silver/population.md) | [PSA — Population Projections](https://psa.gov.ph/statistics/census/projected-population) | **2020 Census-Based Population Projections, Table 1**; regional projections by age group, sex, and year. | 2021–2025; Both sexes and age bands for 17 source regions. These are projections, not annual census counts. |
| [GRDP per capita](silver/grdp_per_capita.md) | [PSA — GRDP Data Series](https://psa.gov.ph/statistics/grdp/data-series) | **2018–2025 GRDP by Region, with NIR as of April 2026**; Capita sheet, Table 2.1 (current prices) and Table 2.2 (constant 2018 prices). | 2021–2025; pesos per person. Silver keeps both price bases; Gold comparisons use constant 2018 prices. |
| [Unemployment rate](silver/unemployment_rate.md) | [PSA — Annual Provincial Labor Market Statistics](https://psa.gov.ph/content/2025-annual-provincial-labor-market-statistics-preliminary-results) | Annual releases, **Table 3: Total Number of Unemployed Persons and Unemployment Rate**. Download the matching releases for earlier years too. | Regional annual percentages for 2021–2025. Select Final for 2022–2024, Preliminary for 2025; 2021 status is not specified in the prepared source. Do not substitute monthly rates or unemployed-person counts. |
| [Poverty incidence](silver/poverty_incidence.md) | [PSA — Poverty Statistics](https://psa.gov.ph/statistics/poverty/index) | Tables for **poverty incidence among families** and **among population**, including annual per-capita poverty thresholds, CV, standard errors, confidence intervals, and footnotes. | Prepared source has 2021, 2023, and 2025. Keep both indicators separate. The exact 2025 publication and estimate reference period still need verification; an annual threshold heading alone does not establish a full-year estimate. |
| [Completion rate](silver/completion_rate.md) | [PSA OpenSTAT — SDG Goal 4](https://openstat.psa.gov.ph/PXWeb/pxweb/en/DB/DB__3I__G04/?tablelist=true) | **4.1.2 Completion rate**; select Elementary, Junior High School, Senior High School, and sex breakdowns. | 2021–2025; regional and national rows. Preserve unavailable-value markers. Bronze expects separate year columns; Silver reshapes them into rows. |
| [Hospital](silver/hospital.md) | [PSA — Philippine Statistical Yearbook](https://psa.gov.ph/philippine-statistical-yearbook) | **2025 Philippine Statistical Yearbook, Table 9.18**. The recorded data provider is DOH's Health Facilities and Services Regulatory Bureau. | Government regulated hospitals only, 2021–2024, for 17 source regions. The prepared dataset does not contain Private, Total, or 2025 counts. |
| [Service access](silver/service_access.md) | [PSA — APIS Statistical Tables](https://psa.gov.ph/statistics/income-expenditure/apis/stat-tables) | **Annual Poverty Indicators Survey (APIS), WASH** tables for 2022 and 2024: drinking water, sanitation, and handwashing. | Three family-based measures for 17 regions. Keep handwashing's consenting-family denominator and the water-service derivation. Do not substitute JMP population-based estimates. |
| [Region boundaries](silver/region_boundaries.md) | Prepared file: `ph_regions_with_nir.geojson`; original download link is not verified. | Regional GeoJSON with 18 features, including NIR. | Map shapes for choropleth charts. Original publisher, license, CRS, and boundary reference date are not yet verified; see [profiling findings](../profiling/bronze/region_boundaries/findings.md). |
| [Shared region crosswalk](shared_region_crosswalk.md) | Maintained in the [project SQL](../dbt/models/silver/shared_region_crosswalk.sql); no external download required. | Region aliases, project codes, canonical names, and validity years. | Used to standardize joins. Project codes such as IVA and IVB are not PSGC identifiers. Historical exceptions stay in the relevant dataset transformation. |

**DBM edition year and data year can differ.** Read the table heading and column basis before selecting a file. A proposed expenditure program, updated appropriation, and actual obligation are different measures.

## Prepare the files before ingestion

1. Download the matching reports or exported tables. Keep their titles, release dates, table names, units, footnotes, and reference periods with your source records.
2. Follow the [Bronze data dictionaries](../profiling/README.md#dataset-index) for the required fields. Prepare most tabular inputs in long form: one observation per row. **Completion rate uses wide year columns; regional boundaries stay in GeoJSON.**
3. Match the file names, folder layout, and parsing rules in the [ingestion guide](ingestion.md). PDF extraction and source-specific reshaping scripts are not included in this repository.
4. Upload the prepared files to your own Google Drive folder, configure your own credentials, and run ingestion with `dry_run=true` before loading.

## How the datasets connect

Silver maps source region labels through the shared crosswalk and validates each dataset at its own level of detail. Gold connects the cleaned data through shared region and year keys. Budget details also use the particular dimension; population keeps its age-group breakdown.

Aggregate each dataset to the required region/year level before comparing measures. Match units, price basis, reference periods, and boundary coverage. Do not join detailed age, sex, or education rows directly to budget rows: that can repeat amounts. A region-name match alone does not prove that historical boundaries match.

For table keys and relationships, see the [data model](data_model.md). For the three analysis questions, see [Analytics](../analytics/readme.md). These comparisons describe patterns; they do not establish that spending caused an indicator to change.
