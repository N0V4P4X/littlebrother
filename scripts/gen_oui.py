#!/usr/bin/env python3
"""
Generate assets/oui/oui_table.json from IEEE OUI registry.
Run once during project setup or CI: python3 scripts/gen_oui.py

Downloads the latest IEEE MA-L (OUI) registry and converts it
to a flat JSON map: { "AABBCC": "Vendor Name", ... }

Output: assets/oui/oui_table.json (~2.5 MB uncompressed)
"""

import json
import re
import sys
import urllib.request
from pathlib import Path

OUI_URL  = "https://standards-oui.ieee.org/oui/oui.txt"
OUT_PATH = Path(__file__).parent.parent / "assets" / "oui" / "oui_table.json"

def fetch_oui():
    print(f"Fetching OUI registry from {OUI_URL} ...")
    req = urllib.request.Request(OUI_URL, headers={"User-Agent": "LittleBrother/0.1"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode("utf-8", errors="replace")

def parse_oui(text: str) -> dict:
    table = {}
    # Lines like: AA-BB-CC   (hex)		Vendor Name
    pattern = re.compile(r"^([0-9A-F]{2}-[0-9A-F]{2}-[0-9A-F]{2})\s+\(hex\)\s+(.+)$", re.MULTILINE)
    for m in pattern.finditer(text):
        oui = m.group(1).replace("-", "").upper()
        vendor = m.group(2).strip()
        table[oui] = vendor
    return table

def main():
    try:
        text = fetch_oui()
    except Exception as e:
        print(f"Download failed: {e}", file=sys.stderr)
        # Fall back to empty table so the app still builds
        OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
        OUT_PATH.write_text("{}")
        sys.exit(0)

    table = parse_oui(text)
    print(f"Parsed {len(table)} OUI entries")

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_text(json.dumps(table, separators=(",", ":")))
    print(f"Written to {OUT_PATH}  ({OUT_PATH.stat().st_size // 1024} KB)")

if __name__ == "__main__":
    main()
