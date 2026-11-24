#!/usr/bin/env python3
"""Mark OST's display text for translation: wrap string literals that are
Teams UI text, in display bindings, in qsTr().

    wrap.py <en-us.json> [--dry] [file.qml …]

<en-us.json> is {namespace: {key: text}} (l10n.py strings, en-us part).
Only literals whose text is a Teams en-us string (OST for Teams) are
touched, and only where they are plainly shown: display properties (text,
label, title, Accessible.name …) outside calls. A text that is also used
as a value anywhere (compared, a switch case, an object key, a non-display
call's argument) is left alone for a person to judge, and listed.
"""

import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from l10n import teams_forms  # noqa: E402
from qmlctx import literals  # noqa: E402

QML = os.path.join(HERE, "..", "qml")

DISPLAY_KEYS = {
    "text", "label", "title", "Accessible.name", "Accessible.description", "tip", "accessibleName", "ToolTip.text",
    "detail", "subtitle", "hint", "body", "confirmText", "placeholder", "placeholderText", "sublabel", "header",
    "buttonText", "primaryLabel", "description", "nameError", "errorText", "networkTip", "networkHeading", "subheader",
    "rowLabel", "chevronLabel", "actionText", "tipText", "composeNote", "startLabel", "endLabel", "heading", "about",
    "badge", "info", "empty", "disabledReason", "spoken", "line", "privacyName", "formTitle", "chatLabel", "ownersLabel",
    "paneTitle", "desc", "cancelText", "okText", "subText", "secondaryText", "primaryText", "emptyText", "emptyTitle",
    "message", "caption", "summary", "prompt", "note", "toolTip", "tooltip", "statusText", "titleText", "labelText",
    "headline", "explanation", "warning", "notice", "linkText", "helpText", "input.Accessible.name", "messageText",
    "placeholderLabel", "accessibleDescription", "subLabel", "sectionTitle", "headerText", "bodyText", "footer",
}
DISPLAY_CALLS = {"backend.toast", "root.announce", "announce", "say", "root.say", "contentItem.Accessible.announce", "tabAnnounce", "showToast", "toast", "root.toast"}
VALUE_KEYS = {"key", "kind", "type", "state", "value", "id", "role", "icon", "name", "mode", "page", "objectName", "source", "showAs", "presence", "availability", "act", "action", "contextType", "channelType", "group"}
COMPARE = {"===", "!==", "==", "!=", "case", "in"}


def is_text(s, en):
    if not re.search(r"[A-Za-z]", s) or not (re.search(r"[A-Z]", s) or " " in s.strip()):
        return False
    return any(f in en for f in teams_forms(s))


def value_uses(files, en):
    """Texts used as values anywhere."""
    used = {}
    for f in files:
        src = open(f, encoding="utf-8").read()
        for lit in literals(src):
            if not is_text(lit.text, en):
                continue
            why = None
            if lit.prev in COMPARE or lit.next in COMPARE:
                why = "compared"
            elif lit.next == ":" and lit.prev in ("{", ","):
                why = "object key"
            elif lit.prev == "[" and lit.next == "]":
                why = "index"
            elif lit.call and lit.call not in DISPLAY_CALLS and lit.call != "qsTr":
                why = "argument of " + lit.call
            elif lit.key in VALUE_KEYS:
                why = "value of " + lit.key
            if why:
                used.setdefault(lit.text, f"{os.path.basename(f)}:{lit.line} {why}")
    return used


def main():
    en_path = sys.argv[1]
    dry = "--dry" in sys.argv
    files = [a for a in sys.argv[2:] if a.endswith(".qml")] or [os.path.join(QML, f) for f in sorted(os.listdir(QML)) if f.endswith(".qml")]
    en_tree = json.load(open(en_path, encoding="utf-8"))
    en = {v for t in en_tree.values() for v in t.values()}
    all_files = [os.path.join(QML, f) for f in sorted(os.listdir(QML)) if f.endswith(".qml")]
    used = value_uses(all_files, en)
    total = 0
    held = {}
    for f in files:
        src = open(f, encoding="utf-8").read()
        edits = []
        for lit in literals(src):
            if not is_text(lit.text, en) or lit.call == "qsTr":
                continue
            if lit.prev in COMPARE or lit.next in COMPARE or (lit.next == ":" and lit.prev in ("{", ",")) or lit.prev == "[":
                continue
            if lit.call and lit.call not in DISPLAY_CALLS:
                continue
            if lit.key not in DISPLAY_KEYS:
                continue
            if lit.text in used:
                held.setdefault(lit.text, (f"{os.path.basename(f)}:{lit.line}", used[lit.text]))
                continue
            edits.append((lit.start, lit.end))
        if not edits:
            continue
        out = src
        for a, b in reversed(edits):
            out = out[:a] + "qsTr(" + out[a:b] + ")" + out[b:]
        total += len(edits)
        if not dry:
            open(f, "w", encoding="utf-8").write(out)
    print(f"wrapped {total} literals")
    for t, (where, why) in sorted(held.items()):
        print(f"held\t{t!r}\t{where}\t{why}")


if __name__ == "__main__":
    main()
