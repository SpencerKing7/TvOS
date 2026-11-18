#!/usr/bin/env python3
"""Numbers the next TvOS release: adds it to the top of versions.json and sets pubspec.yaml.

    scripts/bump-version.py "One-line summary"

A release is one promotion (a batch installed as the real app), not one pull request, so this
runs once per promote, on the branch that ships it. test/versions_test.dart checks the result.
"""

import datetime
import json
import pathlib
import re
import sys

# Upstream LTvLauncher's last build number; TvOS's must stay above it to install over it.
UPSTREAM_BUILD = 8114

root = pathlib.Path(__file__).resolve().parent.parent
summary = " ".join(sys.argv[1:]).split("\n")[0].strip()
if not summary:
    sys.exit("bump-version: give a one-line summary")

versions = root / "versions.json"
entries = json.loads(versions.read_text()) if versions.exists() else []
version = entries[0]["version"] + 1 if entries else 1
entries.insert(0, {"version": version, "date": datetime.date.today().isoformat(), "summary": summary})
versions.write_text(json.dumps(entries, indent=2, ensure_ascii=False) + "\n")

pubspec = root / "pubspec.yaml"
text, count = re.subn(
    r"^version: .*$", f"version: {version}.0.0+{UPSTREAM_BUILD + version}", pubspec.read_text(), count=1, flags=re.M
)
if count != 1:
    sys.exit("bump-version: no version line in pubspec.yaml")
pubspec.write_text(text)
print(f"bump-version: v{version}")
