#!/usr/bin/env python3
"""Builds and validates the remote catalogue published to GitHub Pages.

The app merges this file over the one bundled in the APK: same id replaces,
ids under "removed" disappear, new ids are appended. See §3.7 of CLAUDE.md.

Usage
-----
    # Validate what is in docs/facts.json and bump its version
    python3 tool/build_remote_catalog.py --bump

    # Just check it, changing nothing
    python3 tool/build_remote_catalog.py --check

Refuses to write anything that the app would then have to drop: every entry is
checked against the same rules the Dart parser applies, so a mistake is caught
here rather than silently skipped on a hundred thousand phones.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BUNDLED = ROOT / "assets" / "data" / "facts.json"
REMOTE = ROOT / "docs" / "facts.json"

CATEGORIES = {"cuerpo", "lenguaje", "historia", "ciencia"}
REQUIRED = {"id", "category", "question", "answer", "detail", "source", "sourceUrl"}
LOCALIZED = ("question", "answer", "detail")


def load(path: Path) -> dict:
    if not path.exists():
        sys.exit(f"error: {path.relative_to(ROOT)} does not exist")
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        sys.exit(f"error: {path.relative_to(ROOT)} is not valid JSON — {exc}")


def check(remote: dict, bundled: dict) -> list[str]:
    problems: list[str] = []

    if not isinstance(remote.get("version"), int):
        problems.append('"version" must be an integer')

    facts = remote.get("facts", [])
    if not isinstance(facts, list):
        problems.append('"facts" must be a list')
        return problems

    bundled_ids = {f["id"] for f in bundled["facts"]}
    seen: set[str] = set()

    for i, fact in enumerate(facts):
        where = f"facts[{i}]"
        if not isinstance(fact, dict):
            problems.append(f"{where}: not an object")
            continue

        missing = REQUIRED - set(fact)
        if missing:
            problems.append(f"{where}: missing {sorted(missing)}")
            continue

        fid = fact["id"]
        where = f"{fid}"
        if fid in seen:
            problems.append(f"{where}: duplicate id inside this file")
        seen.add(fid)

        if fact["category"] not in CATEGORIES:
            problems.append(
                f"{where}: unknown category {fact['category']!r} "
                f"(must be one of {sorted(CATEGORIES)})"
            )

        for key in LOCALIZED:
            value = fact[key]
            if not isinstance(value, dict) or set(value) < {"es", "en"}:
                problems.append(f"{where}: {key} needs both 'es' and 'en'")
            elif not all(str(v).strip() for v in value.values()):
                problems.append(f"{where}: {key} has an empty language")

        if not str(fact["source"]).strip():
            problems.append(f"{where}: empty source — no fact ships unsourced")

        # Editorial gate, stricter than the app's parser on purpose. The parser
        # tolerates a missing link because a bad remote file must not brick the
        # installed copies; this script is where a human publishes, and here an
        # unverifiable claim simply does not go out.
        if not str(fact["sourceUrl"]).startswith("https://"):
            problems.append(
                f"{where}: sourceUrl must be an https link you actually opened"
            )

    removed = remote.get("removed", [])
    if not isinstance(removed, list):
        problems.append('"removed" must be a list of ids')
    else:
        for rid in removed:
            if rid not in bundled_ids and rid not in seen:
                problems.append(f"removed: {rid!r} is not an id that exists")

    return problems


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bump", action="store_true", help="increment version")
    parser.add_argument("--check", action="store_true", help="validate only")
    args = parser.parse_args()

    bundled = load(BUNDLED)
    remote = load(REMOTE)

    problems = check(remote, bundled)
    if problems:
        print(f"{len(problems)} problem(s) in docs/facts.json:\n", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        sys.exit(1)

    added = [f for f in remote["facts"] if f["id"] not in {b["id"] for b in bundled["facts"]}]
    replaced = [f for f in remote["facts"] if f["id"] in {b["id"] for b in bundled["facts"]}]
    removed = remote.get("removed", [])

    if args.bump:
        remote["version"] = int(remote["version"]) + 1
        REMOTE.write_text(
            json.dumps(remote, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )

    total = len(bundled["facts"]) + len(added) - len(removed)
    print(f"OK  version {remote['version']}")
    print(f"    {len(added)} new, {len(replaced)} corrected, {len(removed)} removed")
    print(f"    users end up with {total} questions")
    if args.bump:
        print("\n    version bumped and written. Now commit and push docs/facts.json.")


if __name__ == "__main__":
    main()
