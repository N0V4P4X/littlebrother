#!/usr/bin/env python3
#
 
<
<
L
I
C
E
N
S
E
I
N
J
E
C
T
O
R
:
H
E
A
D
E
R
:
S
T
A
R
T
>
>
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 N0V4-N3XU5
#
 
<
<
L
I
C
E
N
S
E
I
N
J
E
C
T
O
R
:
H
E
A
D
E
R
:
E
N
D
>
>

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
OUI_URL_FALLBACK = "https://gitlab.com/wireshark/wireshark/-/raw/master/manuf"
OUT_PATH = Path(__file__).parent.parent / "assets" / "oui" / "oui_table.json"

def fetch(url: str) -> str:
    print(f"  Trying {url} ...")
    req = urllib.request.Request(url, headers={"User-Agent": "LittleBrother/0.1"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode("utf-8", errors="replace")

def parse_ieee(text: str) -> dict:
    table = {}
    # Lines like: AA-BB-CC   (hex)    Vendor Name
    pattern = re.compile(r"^([0-9A-F]{2}-[0-9A-F]{2}-[0-9A-F]{2})\s+\(hex\)\s+(.+)$", re.MULTILINE)
    for m in pattern.finditer(text):
        oui = m.group(1).replace("-", "").upper()
        table[oui] = m.group(2).strip()
    return table

def parse_wireshark(text: str) -> dict:
    table = {}
    # Lines like: AA:BB:CC  VendorName  # comment
    pattern = re.compile(r"^([0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2})\s+(\S+)", re.MULTILINE)
    for m in pattern.finditer(text):
        oui = m.group(1).replace(":", "").upper()
        table[oui] = m.group(2).strip()
    return table

def check_table():
    if not OUT_PATH.exists():
        print("oui_table.json does not exist — run gen_oui.py")
        sys.exit(1)
    data = json.loads(OUT_PATH.read_text())
    print(f"oui_table.json: {len(data)} entries  ({OUT_PATH.stat().st_size // 1024} KB)")
    sys.exit(0)

def main():
    if "--check" in sys.argv:
        check_table()

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)

    table = {}
    errors = []

    for url, parser in [(OUI_URL, parse_ieee), (OUI_URL_FALLBACK, parse_wireshark)]:
        try:
            text = fetch(url)
            table = parser(text)
            if table:
                print(f"Parsed {len(table)} OUI entries from {url}")
                break
        except Exception as e:
            errors.append(f"{url}: {e}")
            print(f"  Failed: {e}", file=sys.stderr)

    if not table:
        print("\nAll OUI sources failed:", file=sys.stderr)
        for e in errors:
            print(f"  {e}", file=sys.stderr)
        print(
            "\nThe app will build with an empty OUI table.\n"
            "Vendor names will be blank and the rogue-AP consumer-OUI\n"
            "heuristic won't fire — everything else works normally.\n"
            "Re-run this script with network access to populate the table.",
            file=sys.stderr,
        )
        # Write empty table so the asset loads without crashing
        OUT_PATH.write_text("{}")
        sys.exit(0)

    OUT_PATH.write_text(json.dumps(table, separators=(",", ":")))
    print(f"Written to {OUT_PATH}  ({OUT_PATH.stat().st_size // 1024} KB)")

if __name__ == "__main__":
    main()
#
 
<
<
L
I
C
E
N
S
E
I
N
J
E
C
T
O
R
:
N
O
T
I
C
E
:
S
T
A
R
T
>
>
_GPLv3_WARRANTY = (
    "THERE IS NO WARRANTY FOR THE PROGRAM, TO THE EXTENT PERMITTED BY\n"
    "APPLICABLE LAW. EXCEPT WHEN OTHERWISE STATED IN WRITING THE COPYRIGHT\n"
    'HOLDERS AND/OR OTHER PARTIES PROVIDE THE PROGRAM \"AS IS\" WITHOUT\n'
    "WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING, BUT NOT\n"
    "LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A\n"
    "PARTICULAR PURPOSE. THE ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE\n"
    "OF THE PROGRAM IS WITH YOU.  (GPL-3.0-or-later §15)"
)

_GPLv3_CONDITIONS = (
    "You may convey verbatim copies of the Program's source code as you\n"
    "receive it, in any medium, provided that you conspicuously and\n"
    "appropriately publish on each copy an appropriate copyright notice and\n"
    "disclaimer of warranty. (See GPL-3.0 §4-6 for full conditions.)\n"
    "Full license: <https://www.gnu.org/licenses/gpl-3.0.html>"
)


def gplv3_notice():
    """Print the short GPLv3 startup notice. Call this at program startup."""
    print("N0V4-N3XU5  Copyright (C) 2026  N0V4-N3XU5")
    print("This program comes with ABSOLUTELY NO WARRANTY; for details type 'show w'.")
    print("This is free software, and you are welcome to redistribute it")
    print("under certain conditions; type 'show c' for details.")


def gplv3_handle(cmd: str) -> bool:
    """
    Check whether *cmd* is a GPLv3 license command and handle it.
    Returns True if the command was consumed (caller should skip normal processing).
    """
    c = cmd.strip().lower()
    if c == "show w":
        print(_GPLv3_WARRANTY)
        return True
    if c == "show c":
        print(_GPLv3_CONDITIONS)
        return True
    return False

#
 
<
<
L
I
C
E
N
S
E
I
N
J
E
C
T
O
R
:
N
O
T
I
C
E
:
E
N
D
>
>
