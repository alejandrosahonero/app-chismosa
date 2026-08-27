#!/usr/bin/env python3
"""Validates researched fact batches and merges them into the bundled catalogue.

Research lands in a staging directory as one JSON array per category, each entry
carrying an extra `_evidence` field with the sentence copied from the page that
backs the claim. That field never ships: it exists so a human can audit the batch
without opening a hundred tabs, and this script strips it on the way in.

Nothing here trusts the researcher. Every entry is re-checked against the same
rules the Dart parser applies, plus the editorial gates from §3.2 of CLAUDE.md
that the parser cannot express: a live https source, a question that fits on a
card, no id that already exists.

Usage
-----
    # Report what the batch looks like, changing nothing
    python3 tool/ingest_facts.py --check

    # Same, and hit every sourceUrl to find dead links (slow, worth it)
    python3 tool/ingest_facts.py --check --links

    # Merge the entries that pass into assets/data/facts.json
    python3 tool/ingest_facts.py --apply
"""

from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.request
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BUNDLED = ROOT / "assets" / "data" / "facts.json"

CATEGORIES = {"cuerpo", "lenguaje", "historia", "ciencia"}
REQUIRED = {"id", "category", "question", "answer", "detail", "source", "sourceUrl"}
LOCALIZED = ("question", "answer", "detail")

# The card and the 1080x1920 story image both shrink text to fit, but only down
# to a floor (34pt); past it the question is clipped instead. These ceilings sit
# a little above the longest entry in the hand-written catalogue — question 84,
# answer 164, detail 328 — so a batch that blows past them is writing essays,
# not cards.
MAX_QUESTION = 110
MAX_ANSWER = 170
MAX_DETAIL = 460

# Sources that have already produced fabricated citations in this project, or
# that are aggregators with no primary reporting behind them.
BANNED_HOSTS = (
    "reddit.com",
    "quora.com",
    "pinterest.",
    "medium.com",
    "buzzfeed.com",
    "listverse.com",
    "factretriever.com",
    "thefactsite.com",
    "chatgpt.com",
    "claude.ai",
)

# The reading order the user gets. §3.2: a run of same-category cards under the
# "all" filter reads like the app got stuck, so new entries are woven in the
# same rotation as the existing file rather than appended in blocks.
ROTATION = ("cuerpo", "ciencia", "historia", "lenguaje")


def load_json(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        sys.exit(f"error: {path} is not valid JSON — {exc}")


def check_entry(fact, where: str, known_ids: set[str]) -> list[str]:
    """Everything that can be judged without touching the network."""
    problems: list[str] = []

    if not isinstance(fact, dict):
        return [f"{where}: not an object"]

    missing = REQUIRED - set(fact)
    if missing:
        return [f"{where}: missing {sorted(missing)}"]

    fid = str(fact["id"])
    where = fid

    if fid in known_ids:
        problems.append(f"{where}: id already exists in the catalogue")
    if not fid.replace("-", "").isalnum() or fid != fid.lower():
        problems.append(f"{where}: id must be lowercase kebab-case, ascii only")

    if fact["category"] not in CATEGORIES:
        problems.append(f"{where}: unknown category {fact['category']!r}")

    for key in LOCALIZED:
        value = fact[key]
        if not isinstance(value, dict) or not {"es", "en"} <= set(value):
            problems.append(f"{where}: {key} needs both 'es' and 'en'")
            continue
        for lang, text in value.items():
            if not str(text).strip():
                problems.append(f"{where}: {key}.{lang} is empty")

    question = fact.get("question", {})
    if isinstance(question, dict):
        for lang, text in question.items():
            if len(str(text)) > MAX_QUESTION:
                problems.append(
                    f"{where}: question.{lang} is {len(text)} chars "
                    f"(max {MAX_QUESTION}) — it will clip on the story image"
                )
        # Spanish opens the interrogative clause, not necessarily the sentence:
        # "Si el hielo es sólido, ¿por qué resbala?" is correct punctuation.
        if isinstance(question.get("es"), str) and not (
            "¿" in question["es"] and question["es"].rstrip().endswith("?")
        ):
            problems.append(f"{where}: question.es must contain '¿' and end in '?'")
        if isinstance(question.get("en"), str) and not question["en"].endswith("?"):
            problems.append(f"{where}: question.en must be interrogative")

    for key, limit in (("answer", MAX_ANSWER), ("detail", MAX_DETAIL)):
        value = fact.get(key, {})
        if isinstance(value, dict):
            for lang, text in value.items():
                if len(str(text)) > limit:
                    problems.append(
                        f"{where}: {key}.{lang} is {len(text)} chars (max {limit})"
                    )

    if not str(fact["source"]).strip():
        problems.append(f"{where}: empty source — no fact ships unsourced")

    url = str(fact["sourceUrl"])
    if not url.startswith("https://"):
        problems.append(f"{where}: sourceUrl must be an https link")
    if any(host in url for host in BANNED_HOSTS):
        problems.append(f"{where}: {url} is not an acceptable source")

    if not str(fact.get("_evidence", "")).strip():
        problems.append(
            f"{where}: no _evidence — the quoted sentence from the page is how "
            f"a human audits this without reopening every tab"
        )

    return problems


def check_link(url: str) -> tuple[str, str | None]:
    """Returns (url, problem) — a 404 here means the entry cannot ship."""
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "Mozilla/5.0 (compatible; aja-catalogue-check/1.0)"},
        method="GET",
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            response.read(1024)
            return url, None
    except urllib.error.HTTPError as exc:
        # 403 is usually a bot wall, not a dead page; flag it as needing eyes
        # rather than failing it outright.
        kind = "blocks bots, open it by hand" if exc.code in (403, 429) else "dead"
        return url, f"HTTP {exc.code} ({kind})"
    except Exception as exc:  # noqa: BLE001 - any failure is a link to look at
        return url, f"unreachable: {type(exc).__name__}"


def interleave(existing: list[dict], new: list[dict]) -> list[dict]:
    """Appends `new` to `existing`, keeping the category rotation going."""
    buckets: dict[str, list[dict]] = defaultdict(list)
    for fact in new:
        buckets[fact["category"]].append(fact)

    merged = list(existing)
    # Resume the rotation where the current file leaves off, so the seam between
    # the old catalogue and the new batch is not itself a repeated category.
    start = 0
    if existing:
        last = existing[-1]["category"]
        if last in ROTATION:
            start = (ROTATION.index(last) + 1) % len(ROTATION)

    step = 0
    while any(buckets.values()):
        category = ROTATION[(start + step) % len(ROTATION)]
        if buckets[category]:
            merged.append(buckets[category].pop(0))
        step += 1
    return merged


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", type=Path, required=True, help="staging directory")
    parser.add_argument("--check", action="store_true", help="validate only")
    parser.add_argument("--apply", action="store_true", help="merge into the asset")
    parser.add_argument("--links", action="store_true", help="also fetch every url")
    args = parser.parse_args()

    if not args.check and not args.apply:
        sys.exit("error: pass --check or --apply")

    bundled = load_json(BUNDLED)
    known_ids = {f["id"] for f in bundled["facts"]}

    batches = sorted(p for p in args.stage.glob("*.json"))
    if not batches:
        sys.exit(f"error: no .json batches in {args.stage}")

    accepted: list[dict] = []
    rejected: list[str] = []
    seen: set[str] = set()

    for path in batches:
        entries = load_json(path)
        if not isinstance(entries, list):
            rejected.append(f"{path.name}: root must be a JSON array")
            continue
        for i, fact in enumerate(entries):
            problems = check_entry(fact, f"{path.name}[{i}]", known_ids | seen)
            if problems:
                rejected.extend(problems)
                continue
            seen.add(fact["id"])
            accepted.append(fact)

    if args.links and accepted:
        print(f"fetching {len(accepted)} sources...", file=sys.stderr)
        urls = {f["sourceUrl"] for f in accepted}
        with ThreadPoolExecutor(max_workers=12) as pool:
            results = dict(pool.map(check_link, urls))
        still_good = []
        for fact in accepted:
            problem = results.get(fact["sourceUrl"])
            if problem:
                rejected.append(f"{fact['id']}: {fact['sourceUrl']} — {problem}")
            else:
                still_good.append(fact)
        accepted = still_good

    by_category = Counter(f["category"] for f in accepted)
    print(f"batches:  {', '.join(p.name for p in batches)}")
    print(f"accepted: {len(accepted)}  ({dict(by_category)})")
    print(f"rejected: {len(rejected)}")
    for problem in rejected[:60]:
        print(f"  - {problem}")
    if len(rejected) > 60:
        print(f"  ... and {len(rejected) - 60} more")

    if not args.apply:
        return

    for fact in accepted:
        fact.pop("_evidence", None)

    bundled["facts"] = interleave(bundled["facts"], accepted)
    BUNDLED.write_text(
        json.dumps(bundled, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"\nwritten: {len(bundled['facts'])} questions in assets/data/facts.json")


if __name__ == "__main__":
    main()
