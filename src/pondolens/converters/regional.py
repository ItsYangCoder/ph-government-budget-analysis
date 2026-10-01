"""Parse B.6.a by word coordinates, excluding unrelated rotated text."""

from decimal import Decimal
import re

from .common import clean, number, record

PAGE1 = ["TOTAL", "Nationwide", "Central Office", "NCR", "I", "CAR", "II", "III", "IV-A", "MIMAROPA"]
PAGE2 = ["V", "VI", "VII", "VIII", "IX", "X", "XI", "XII", "CARAGA", "BARMM"]
GROUPS = {"DEPARTMENTS", "SPECIAL PURPOSE FUNDS", "AUTOMATIC APPROPRIATIONS 1/"}
CAPTIONS = {"TOTAL": "total", "Nationwide": "nationwide", "Central Office": "centraloffice",
            "NCR": "nationalcapitalregion", "CAR": "cordilleraadministrativeregion",
            "IV-A": "regioniva", "MIMAROPA": "regionivb", "NIR": "negrosislandregion",
            "CARAGA": "caraga", "BARMM": "barmm"}
CAPTIONS.update({r: "region" + r.lower() for r in PAGE2 + ["I", "II", "III"] if r not in CAPTIONS})


def lines(words):
    grouped = []
    for word in sorted(words, key=lambda w: (w["top"], w["x0"])):
        if not word.get("upright", True):
            continue
        if grouped and abs(word["top"] - grouped[-1][0]) <= 2:
            grouped[-1][1].append(word)
        else:
            grouped.append((word["top"], [word]))
    return [(top, sorted(ws, key=lambda w: w["x0"])) for top, ws in grouped]


def page_rows(page, regions, controls):
    grouped = lines(page["words"])
    department_line = next((ws for _, ws in grouped if any(w["text"] == "DEPARTMENTS" for w in ws)), None)
    if department_line is None:
        raise ValueError("Regional DEPARTMENTS row not found")
    numeric = [w for w in department_line if re.fullmatch(r"[\d,.-]+", w["text"])]
    fragments = []
    for w in numeric:
        if fragments and w["x0"] - fragments[-1]["end"] < 5:
            fragments[-1]["text"] += w["text"]
            fragments[-1]["end"] = w["x1"]
        else:
            fragments.append(dict(text=w["text"], start=w["x0"], end=w["x1"]))
    if len(fragments) != len(regions):
        raise ValueError(f"Regional anchors: expected {len(regions)}, found {len(fragments)}")
    anchors = [f["end"] for f in fragments]
    first_left = fragments[0]["start"] - 3
    start = min(w["top"] for w in department_line)
    header_words = [[] for _ in regions]
    for top, ws in grouped:
        if start - 50 <= top < start - 3:
            for w in ws:
                if w["x1"] >= first_left:
                    index = min(range(len(anchors)), key=lambda i: abs(w["x1"] - anchors[i]))
                    header_words[index].append(w["text"])
    for region, words in zip(regions, header_words, strict=True):
        caption = "".join(re.findall(r"[a-z0-9]+", " ".join(words).lower()))
        controls.require(caption == CAPTIONS[region], f"PDF region header mismatch: expected {region}, found {caption}")
    results = []
    finished = False
    for top, ws in grouped:
        if top < start - 2 or finished:
            continue
        label_words = [w for w in ws if w["x1"] < first_left]
        label = clean(" ".join(w["text"] for w in label_words))
        if not label:
            raise ValueError(f"Unlabelled regional row page {page['page']} y={top}")
        fields = [[] for _ in regions]
        tokens = []
        for w in ws:
            if w in label_words:
                continue
            controls.require(re.fullmatch(r"[\d,.-]+", w["text"]) is not None,
                             f"Non-numeric PDF token {label}: {w['text']}")
            if tokens and w["x0"] - tokens[-1]["end"] < 5:
                tokens[-1]["text"] += w["text"]
                tokens[-1]["end"] = w["x1"]
            else:
                tokens.append(dict(text=w["text"], end=w["x1"]))
        for token in tokens:
            index = min(range(len(anchors)), key=lambda i: abs(token["end"] - anchors[i]))
            controls.require(not fields[index], f"Two PDF amounts mapped to {label}:{regions[index]}")
            fields[index].append(token["text"])
        fields = ["".join(v) for v in fields]
        results.append((label, top, fields))
        finished = label == "GRAND TOTAL"
    controls.require(finished, f"Regional GRAND TOTAL missing page {page['page']}")
    return results


def regional(pages, controls, config):
    pages = list(pages)
    controls.require(len(pages) == 2, "Regional PDF must have exactly 2 pages")
    if len(pages) != 2:
        raise ValueError("Unsupported regional PDF page count")
    year_match = re.search(r"20\d{2}", config["source"])
    if not year_match:
        raise ValueError("Regional year missing")
    year = int(year_match[0])
    page2_regions = PAGE2[:2] + (["NIR"] if year == 2025 else []) + PAGE2[2:]
    for page in pages:
        upright_text = " ".join(w["text"] for w in page["words"] if w.get("upright", True))
        controls.require(f"CY {year}" in upright_text and "Thousand Pesos" in upright_text,
                         f"Regional title/unit mismatch page {page['page']}")
    first = page_rows(pages[0], PAGE1, controls)
    second = page_rows(pages[1], page2_regions, controls)
    controls.require([r[0] for r in first] == [r[0] for r in second], "Regional labels/order differ across pages")
    if [r[0] for r in first] != [r[0] for r in second]:
        raise ValueError("Cannot align regional PDF pages")
    totals_by_region = {}
    group = ""
    detail_sums = {}
    printed_groups = {}
    for (label, top1, vals1), (_, top2, vals2) in zip(first, second, strict=True):
        if label in GROUPS:
            group = label
        level = "grand_total" if label == "GRAND TOTAL" else "subtotal" if label in GROUPS else "department_or_fund"
        combined = dict(zip(PAGE1 + page2_regions, vals1 + vals2, strict=True))
        numeric = {region: number(raw)[0] for region, raw in combined.items()}
        # Dashes and empty cells remain explicit source states; only reconciliation treats them as zero.
        amounts = {region: amount if amount is not None else Decimal(0) for region, amount in numeric.items()}
        controls.reconcile(f"regional:{year}:{label}:columns_to_total", numeric["TOTAL"],
                           sum((a for r, a in amounts.items() if r != "TOTAL"), Decimal(0)), "11")
        for region, raw in combined.items():
            pg = 1 if region in PAGE1 else 2
            index = (PAGE1 if pg == 1 else page2_regions).index(region) + 1
            cell = dict(original_value=raw, excel_type="s")
            item = record("regional_actuals", f"page_{pg}", top1 if pg == 1 else top2,
                          index, cell, unit="thousand_PHP", key=[year, label, region],
                          year=year, entity=label, region=region, section=group,
                          measure="obligations", status="actual", record_level=level,
                          geography_basis=f"B6a_CY_{year}")
            item["source_page"] = pg
            item["source_row"] = round(item["source_row"], 4)
            yield item
        if level == "subtotal":
            printed_groups[group] = amounts
        elif level == "department_or_fund":
            target = detail_sums.setdefault(group, {r: Decimal(0) for r in combined})
            for region, amount in amounts.items():
                target[region] += amount
        else:
            totals_by_region = amounts
    for group, expected in printed_groups.items():
        for region in expected:
            controls.reconcile(f"regional:{year}:{group}:{region}:details_to_subtotal",
                               expected[region], detail_sums.get(group, {}).get(region), "25")
    for region, total in totals_by_region.items():
        controls.reconcile(f"regional:{year}:{region}:groups_to_grand_total", total,
                           sum((g[region] for g in printed_groups.values()), Decimal(0)), "3")
    controls.require(bool(totals_by_region), "Regional totals not parsed")
    controls.notes.append("Reconciliation tolerances allow rounding of printed integer thousand-peso amounts; blanks/dashes remain distinct from numeric zero. Cross-year geographic comparability is not established.")
