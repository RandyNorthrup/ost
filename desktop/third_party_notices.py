#!/usr/bin/env python3
"""Write desktop/THIRD-PARTY-NOTICES.md: what OST desktop is built from.

Settings ▸ About OST ▸ Third party notice ▸ Desktop shows this file, as Teams
shows its own notices. Run it after changing dependencies:
`python3 desktop/third_party_notices.py` (needs cargo).

Lists every crate the desktop app links (normal dependencies of ost-desktop,
followed through the lock file; build and dev tools left out), then Qt and
the bundled assets (desktop/assets/NOTICE.md).
"""
import json
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent.parent


def crates():
    meta = json.loads(
        subprocess.run(
            ["cargo", "metadata", "--format-version", "1", "--manifest-path", str(ROOT / "desktop" / "Cargo.toml")],
            check=True, capture_output=True, text=True,
        ).stdout
    )
    packages = {p["id"]: p for p in meta["packages"]}
    nodes = {n["id"]: n for n in meta["resolve"]["nodes"]}
    root = meta["resolve"]["root"]
    local = {p["id"] for p in meta["packages"] if p.get("source") is None}
    seen, todo = set(), [root]
    while todo:
        node = nodes[todo.pop()]
        for dep in node["deps"]:
            if not any(k.get("kind") is None for k in dep["dep_kinds"]):
                continue  # only build or dev
            if dep["pkg"] not in seen:
                seen.add(dep["pkg"])
                todo.append(dep["pkg"])
    rows = [packages[i] for i in seen if i not in local]
    return sorted(rows, key=lambda p: (p["name"].lower(), p["version"]))


def main():
    out = [
        "# Third-party notices: OST desktop",
        "",
        "OST desktop is open source (MIT, see LICENSE). It is built with the",
        "software below, each under its own licence. OST is not affiliated with",
        "or endorsed by Microsoft.",
        "",
        "## Qt",
        "",
        "Qt 6 (Qt Quick, Qt Multimedia and their modules), by The Qt Company and",
        "contributors, used under the GNU Lesser General Public License v3",
        "(https://www.qt.io/licensing/, source: https://code.qt.io/).",
        "",
        "## Rust crates",
        "",
        "| Crate | Version | Licence | Source |",
        "|---|---|---|---|",
    ]
    for p in crates():
        source = p.get("repository") or p.get("homepage") or f"https://crates.io/crates/{p['name']}"
        out.append(f"| {p['name']} | {p['version']} | {p.get('license') or 'see source'} | {source} |")
    out += ["", "## Bundled assets", ""]
    notice = (ROOT / "desktop" / "assets" / "NOTICE.md").read_text().splitlines()
    out += [line for line in notice if not line.startswith("# ")]
    (ROOT / "desktop" / "THIRD-PARTY-NOTICES.md").write_text("\n".join(out).rstrip() + "\n")


if __name__ == "__main__":
    main()
