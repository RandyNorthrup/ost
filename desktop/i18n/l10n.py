#!/usr/bin/env python3
"""OST's text in Teams' app languages: the developer side.

OST's QML marks its text with qsTr("…") and its Rust (the desktop's and
the engine's) with tr("…") / tr_n("…%n…", n) / tr_id("…", "<ns>:<key>") /
tr_id_n("…%n…", "<ns>:<key>", n) (teams_cli::i18n, the one translator the
QML's qsTr also asks). Each such string is keyed to the Teams string id
whose en-us text it is (OST in place of Teams). OST ships only those ids (ids.json) and where Teams' own
string resources are (teams_resources.json); on first use of an app
language it downloads that locale's resources from Teams' CDN and builds
its catalogue on the device (src/api/teams_strings.rs). No translations
are kept in the repository.

    l10n.py strings <hashed-assets dir> <strings.json>
        Read Teams' string resources (teams_strings.py) into one file.
    l10n.py extra <strings.json> <hashed-assets dir> <cache dir>
        Read the string tables of Teams' other bundles (extra_strings.py,
        extra_sources.json: the clip recorder, OneDrive's web apps) into
        <strings>-extra.json, which `gen` then uses too.
    l10n.py gen <strings.json> [<hashed-assets dir> <Teams version>]
        Key OST's strings to Teams ids (ids.json, untranslated.txt) and,
        given the assets, list each locale's resource files
        (teams_resources.json, its `extra` from <strings>-extra.json).
    l10n.py find <strings.json> <text>
        Teams' en-us strings containing <text> (to pick ids by hand).
    l10n.py flips <hashed-assets dir>
        The icons Teams mirrors right to left (rtl_flip_icons.json).

To refresh after OST's text changes (or for a newer Teams): copy Teams'
`*-locale-*` files out of its install (new Teams:
C:\\Program Files\\WindowsApps\\MSTeams_<version>_x64__8wekyb3d8bbwe\\
desktop-assets\\hashed-assets), run `strings`, then `gen` with the same
folder and the Teams version, and commit ids.json, teams_resources.json
and untranslated.txt (OST's strings with no Teams string; they stay
English).

Teams' texts use {{name}} / {0} placeholders, empty rich-text components
(<0></0>, filled with names or links by its React code) and ICU plural
messages;
OST's sources use Qt's form: %1, %2… in en-us order, %n for the count
(qsTr("…%n…", "", count) for a plural message, keyed by its 'other' form).

An OST string picks its id by its text. Where Teams has several ids for
the same text, the one whose translations agree with the most others is
used; qsTr("text", "<namespace>:<key>") names the id explicitly.
"""

import collections
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
QML = os.path.join(HERE, "..", "qml")
RUST = [os.path.join(HERE, "..", "src"), os.path.join(HERE, "..", "..", "src")]
sys.path.insert(0, HERE)

from qmltok import tokens  # noqa: E402

# ---------------------------------------------------------------- messages


def parse_message(s):
    """Teams' message syntax -> a list of parts: str, ('arg', name),
    ('plural', name, {selector: parts}), ('select', name, {k: parts}),
    ('hash',) for a plural's #. Teams' empty rich-text components
    (`<0></0>`, `<1/>`: names and links its React code fills) are
    placeholders named "<0>", "<1>"."""
    c = components(s)
    parts, i = _parse(c, 0, False)
    # a brace closing nothing is literal
    while i < len(c):
        more, i = _parse(c, i, False)
        parts = parts + ["}"] + more
    return parts


def components(s):
    """`<0></0>` / `<0/>` as `{{<0>}}`; a component wrapping only one
    (`<0><0></0></0>`) is that placeholder."""
    if "<" not in s:
        return s
    t = re.sub(r"<(\d+)>\s*</\1>|<(\d+)\s*/>", lambda m: "{{<%s>}}" % (m.group(1) or m.group(2)), s)
    while True:
        n = re.sub(r"<(\d+)>(\{\{<\d+>\}\})</\1>", r"\2", t)
        if n == t:
            return t
        t = n


def _parse(s, i, in_plural):
    out = []
    buf = []
    n = len(s)
    while i < n:
        c = s[i]
        if s.startswith("{{", i):
            j = s.index("}}", i)
            _flush(buf, out)
            out.append(("arg", s[i + 2 : j].strip()))
            i = j + 2
            continue
        if c == "{":
            _flush(buf, out)
            j = i + 1
            m = re.match(r"\s*([\w.]+)\s*(?:,\s*(plural|select|selectordinal)\s*,)?", s[j:])
            if not m:
                # not a placeholder: a literal brace (Teams' i18next texts,
                # "We don't support these characters: ~#%&*{}+/…")
                buf.append(c)
                i += 1
                continue
            name, kind = m.group(1), m.group(2)
            j += m.end()
            if not kind:
                num = re.match(r"\s*,\s*number\s*(?:,[^{}]*)?\}", s[j:])
                if num:
                    # `{count, number}` (Loop's): the value as it is
                    out.append(("arg", name))
                    i = j + num.end()
                    continue
                if s[j:].lstrip().startswith("}"):
                    j += len(s[j:]) - len(s[j:].lstrip()) + 1
                    out.append(("arg", name))
                    i = j
                    continue
                raise ValueError(f"bad message {s!r}")
            forms = {}
            while True:
                while j < n and s[j] in " \n\t":
                    j += 1
                if s[j] == "}":
                    j += 1
                    break
                m = re.match(r"(=\d+|\w+)\s*\{", s[j:])
                if not m:
                    if s.startswith("offset:", j):
                        raise ValueError("offset unsupported")
                    raise ValueError(f"bad plural {s!r}")
                sel = m.group(1)
                j += m.end()
                body, j = _parse(s, j, kind != "select")
                forms[sel] = body
            out.append(("plural" if kind != "select" else "select", name, forms))
            i = j
            continue
        if c == "}":
            _flush(buf, out)
            return out, i + 1
        if c == "#" and in_plural:
            _flush(buf, out)
            out.append(("hash",))
            i += 1
            continue
        if c == "'" and i + 1 < n and s[i + 1] in "{}#'" and not s.startswith("{{", i + 1):
            # ICU quoting: '{' is a literal brace, '' a quote.
            if s[i + 1] == "'":
                buf.append("'")
                i += 2
                continue
            j = s.find("'", i + 1)
            if j < 0:
                j = n
            buf.append(s[i + 1 : j])
            i = j + 1
            continue
        buf.append(c)
        i += 1
    _flush(buf, out)
    return out, i


def _flush(buf, out):
    if buf:
        out.append("".join(buf))
        buf.clear()


def arg_order(parts, order=None):
    """Placeholder names in order of first appearance."""
    order = [] if order is None else order
    for p in parts:
        if isinstance(p, str) or p[0] == "hash":
            continue
        if p[0] == "arg":
            if p[1] not in order:
                order.append(p[1])
        else:
            # forms: prefer "other" first so its args get the lower numbers
            for sel in sorted(p[2], key=lambda k: (k != "other", k)):
                arg_order(p[2][sel], order)
    return order


def _render(parts, args, plural_var):
    out = []
    for p in parts:
        if isinstance(p, str):
            out.append(p)
        elif p[0] == "hash":
            # `#`: the language's digits (Teams' ICU number format)
            out.append("%n")
        elif p[0] == "arg":
            if p[1] == plural_var:
                # the count named as an argument ({days}): written as it is
                out.append("%N")
            elif p[1] in args:
                out.append("%" + str(args.index(p[1]) + 1))
            else:
                return None
        else:
            return None
    return "".join(out)


def _forms(pl, before, after, args, trim):
    forms = {}
    for sel, body in pl[2].items():
        r = _render(before + body + after, args, pl[1])
        if r is None:
            return None
        forms[sel] = r.strip() if trim else r
    return forms if "other" in forms else None


def to_qt(text, args=None):
    """A Teams message in Qt's form: a string, {selector: string} for a
    plural message, or for several plurals a list of segments (text, and
    {"var": name, "forms": {…}} per count); None for what it can't express
    (selects). `args` fixes placeholder numbering (en-us order)."""
    try:
        parts = parse_message(text)
    except (ValueError, IndexError):
        return None
    if args is None:
        args = [a for a in arg_order(parts)]
    plurals = [p for p in parts if not isinstance(p, str) and p[0] == "plural"]
    if any(not isinstance(p, str) and p[0] == "select" for p in parts):
        return None
    if not plurals:
        return _render(parts, args, None)
    if len(plurals) == 1:
        k = parts.index(plurals[0])
        return _forms(plurals[0], parts[:k], parts[k + 1 :], args, True)
    segs = []
    for p in parts:
        if not isinstance(p, str) and p[0] == "plural":
            f = _forms(p, [], [], args, False)
            if f is None:
                return None
            segs.append({"var": p[1], "forms": f})
        else:
            r = _render([p], args, None)
            if r is None:
                return None
            segs.append(r)
    return segs


def qt_args(text):
    """en-us placeholder order for a Teams message (plural variable excluded)."""
    try:
        parts = parse_message(text)
    except (ValueError, IndexError):
        return None
    plural_vars = {p[1] for p in parts if not isinstance(p, str) and p[0] == "plural"}
    return [a for a in arg_order(parts) if a not in plural_vars]


# ------------------------------------------------------------ Teams' names

# OST's text names OST where Teams' names Teams.
def teams_forms(s):
    if "OST" not in s:
        return [s]
    return [s.replace("OST", "Teams"), s.replace("OST", "Microsoft Teams"), s]


# How a language joins an inflection to an abbreviation ("Teamsista" ->
# "OST:ista" in Finnish, "Teamsbe" -> "OST-be" in Hungarian); others attach
# it directly ("Teams를" -> "OST를").
_SUFFIX_JOINER = {"fi": ":", "et": ":", "hu": "-", "uz": "-", "kk": "-"}


def ostify(text, locale="en-us"):
    """Teams' product name in a translation as OST: "Microsoft Teams" and
    "Teams", inflected forms included."""
    if isinstance(text, dict):
        return {k: v if k == "var" else ostify(v, locale) for k, v in text.items()}
    if isinstance(text, list):
        return [ostify(v, locale) for v in text]
    if text is None:
        return None
    joiner = _SUFFIX_JOINER.get(locale.split("-")[0], "")
    sub = lambda m: "OST" + (joiner + m.group(1) if m.group(1) else "")  # noqa: E731
    t = re.sub(r"Microsoft\s+Teams(\w*)", sub, text)
    t = re.sub(r"(?<![\w])Teams(\w*)", sub, t)
    return t


# ------------------------------------------------------------- OST's text


def qml_strings():
    """qsTr calls in OST's QML: {(source, disambiguation): [file:line]}."""
    found = collections.defaultdict(list)
    for f in sorted(os.listdir(QML)):
        if not f.endswith(".qml"):
            continue
        src = open(os.path.join(QML, f), encoding="utf-8").read()
        toks = list(tokens(src))
        for i, (kind, val, a, b) in enumerate(toks):
            if kind == "id" and val in ("qsTr", "qsTrId") and i + 2 < len(toks) and toks[i + 1][1] == "(" and toks[i + 2][0] == "str":
                if val == "qsTrId":
                    continue
                dis = ""
                if i + 4 < len(toks) and toks[i + 3][1] == "," and toks[i + 4][0] == "str":
                    dis = toks[i + 4][1]
                found[(toks[i + 2][1], dis)].append(f"{f}:{src.count(chr(10), 0, a) + 1}")
    # Rust: tr("…") / tr_n("…", n) / tr_id("…", "ns:key") / tr_id_n("…", "ns:key", n)
    pat = re.compile(r'\btr(?:_n|_id|_id_n|_id_counts)?\(\s*"((?:[^"\\]|\\.)*)"(?:\s*,\s*"([^"]*)")?')
    for root in RUST:
        for d, _, files in os.walk(root):
            for f in files:
                if not f.endswith(".rs"):
                    continue
                src = open(os.path.join(d, f), encoding="utf-8").read()
                # not the tests' strings
                cut = src.find("#[cfg(test)]\nmod tests")
                if cut >= 0:
                    src = src[:cut]
                for m in pat.finditer(src):
                    s = m.group(1).encode().decode("unicode_escape").encode("latin-1").decode("utf-8")
                    found[(s, m.group(2) or "")].append(f"{f}:{src.count(chr(10), 0, m.start()) + 1}")
    return found


# ---------------------------------------------------------------- catalogue


def _norm(v):
    """A Teams en-us text in Qt's form, for matching (the 'other' form of a
    plural)."""
    q = to_qt(v)
    if isinstance(q, list):
        return None
    if isinstance(q, dict):
        q = q.get("other")
    # OST's sources write a count as %n either way
    return q.replace("%N", "%n") if q else q


def index_en(teams):
    by_text = collections.defaultdict(list)
    for ns, t in teams["en-us"].items():
        for k, v in t.items():
            n = _norm(v)
            if n is not None:
                by_text[n].append(f"{ns}:{k}")
                # OneDrive's texts with a trailing space or zero-width space
                t = n.strip(" \u200b")
                if t != n:
                    by_text[t].append(f"{ns}:{k}")
                if isinstance(to_qt(v), dict):
                    by_text[("plural", n)].append(f"{ns}:{k}")
    return by_text


def lookup(teams, loc, sid):
    ns, k = sid.split(":", 1)
    return teams.get(loc, {}).get(ns, {}).get(k)


def choose(teams, cands, locales):
    """The id whose translations agree with the most other candidates."""
    if len(cands) == 1:
        return cands[0]
    score = collections.Counter()
    for loc in locales:
        vals = {c: lookup(teams, loc, c) for c in cands}
        counts = collections.Counter(vals.values())
        for c in cands:
            score[c] += counts[vals[c]]
    return sorted(cands, key=lambda c: (-score[c], c))[0]


# Teams' public path for its hashed assets (its webpack runtime's .p).
TEAMS_CDN = "https://statics.teams.cdn.office.net/teams-modular-packages/hashed-assets/"


def extra_path(strings_path):
    return os.path.splitext(strings_path)[0] + "-extra.json"


def gen(strings_path, assets_dir=None, teams_version=""):
    teams = json.load(open(strings_path, encoding="utf-8"))
    locales = sorted(teams)
    # Teams' other bundles ("x.…" namespaces): only for text its main
    # table doesn't have.
    extra = {"strings": {}, "files": {}}
    if os.path.exists(extra_path(strings_path)):
        extra = json.load(open(extra_path(strings_path), encoding="utf-8"))
        for loc, nss in extra["strings"].items():
            if loc in teams:
                # Their texts aren't ICU: an apostrophe is just one
                # ("Filter by '{0}'"), so it is quoted as ICU's ''.
                teams[loc].update({ns: {k: v.replace("'", "''") for k, v in t.items()} for ns, t in nss.items()})
    by_text = index_en(teams)
    found = qml_strings()
    srcs = json.load(open(os.path.join(HERE, "extra_sources.json"), encoding="utf-8"))["sources"]
    used_in = {ns: set(cfg.get("usedIn", [])) for ns, cfg in srcs.items()}
    prefer = {ns for ns, cfg in srcs.items() if cfg.get("prefer")}
    ids = []
    missing = []
    replied = 0
    for (source, dis) in sorted(found):
        sid = None
        if dis.startswith("reply:"):
            # Teams' text from a service reply in the app language (meeting
            # options' translations): OST's is only a fallback
            replied += 1
            continue
        if re.fullmatch(r"[\w.-]+:\w+", dis or ""):
            if lookup(teams, "en-us", dis) is not None:
                sid = dis
            else:
                missing.append((source, dis, found[(source, dis)][:3], "unknown id"))
                continue
        else:
            where = {w.split(":")[0] for w in found[(source, dis)]}
            for form in teams_forms(source):
                cands = by_text.get(form)
                # a screen that is another app's (the Downloads panel is
                # WebView2's) takes that app's text first
                own = [c for c in cands or [] if c.split(":")[0] in prefer and where <= used_in[c.split(":")[0]]]
                if own:
                    cands = own
                elif cands and any(not c.startswith("x.") for c in cands):
                    cands = [c for c in cands if not c.startswith("x.")]
                # another bundle's text only on the screens that bundle is
                # (OneDrive's for OneDrive's views, Outlook's for Calendar)
                if cands:
                    cands = [c for c in cands if not c.startswith("x.") or where <= used_in.get(c.split(":")[0], set())]
                if cands:
                    # By text, Teams' plain-text strings first (its rich-text
                    # ones, with <0></0> components, are named by id).
                    plain = [c for c in cands if "<" not in lookup(teams, "en-us", c)]
                    sid = choose(teams, plain or cands, locales)
                    break
        if not sid:
            missing.append((source, dis, found[(source, dis)][:3], ""))
            continue
        ids.append((source, dis, sid))
    # ids.json: OST's string, its disambiguation, the Teams id, the id's
    # placeholders in en-us order (a translation's {{name}} becomes %N by
    # this list), and for a plural message OST's own English forms (so
    # English needs no download). No translations: OST builds those from
    # Teams' resources on the device (src/api/teams_strings.rs).
    rows = []
    for source, dis, sid in ids:
        en_text = lookup(teams, "en-us", sid)
        row = [source, dis, sid, qt_args(en_text) or []]
        q = to_qt(en_text)
        if isinstance(q, (dict, list)):
            row.append(ostify(q) if "OST" in source else q)
        rows.append(row)
    with open(os.path.join(HERE, "ids.json"), "w", encoding="utf-8") as out:
        out.write("[\n" + ",\n".join(json.dumps(r, ensure_ascii=False) for r in rows) + "\n]\n")
    # teams_resources.json: where Teams' string resources for each locale
    # are (the files holding the namespaces OST's ids use), pinned to the
    # Teams build they come from: their names carry their content hash.
    if assets_dir:
        needed = {sid.split(":", 1)[0] for _, _, sid in ids}
        files = collections.defaultdict(list)
        import gzip
        import teams_strings
        for f in sorted(os.listdir(assets_dir)):
            if "-locale-" not in f or ".worker." in f or not (f.endswith(".js") or f.endswith(".js.gz")):
                continue
            path = os.path.join(assets_dir, f)
            raw = gzip.open(path).read() if f.endswith(".gz") else open(path, "rb").read()
            got = {}
            teams_strings.parse_chunk(raw.decode("utf-8"), got)
            for loc, nss in got.items():
                if loc != "en-us" and needed & set(nss):
                    files[loc].append(f[:-3] if f.endswith(".gz") else f)
        manifest = {"teamsVersion": teams_version, "base": TEAMS_CDN, "files": {k: sorted(v) for k, v in sorted(files.items())}}
        used = {sid.split(":", 1)[0] for _, _, sid in ids if sid.startswith("x.")}
        manifest["extra"] = {ns: {**e, "files": dict(sorted(e["files"].items()))} for ns, e in sorted(extra["files"].items()) if ns in used}
        with open(os.path.join(HERE, "teams_resources.json"), "w", encoding="utf-8") as out:
            json.dump(manifest, out, indent=1)
            out.write("\n")
    with open(os.path.join(HERE, "untranslated.txt"), "w", encoding="utf-8") as out:
        out.write("# OST strings with no Teams string (left in English), with where they are used\n")
        for source, dis, where, why in missing:
            out.write(f"{json.dumps(source, ensure_ascii=False)}\t{dis}\t{' '.join(where)}\t{why}\n")
    print(f"{len(ids)} strings keyed to Teams ids, {replied} from service replies, {len(missing)} without one")


def find(strings_path, text):
    teams = json.load(open(strings_path, encoding="utf-8"))
    t = text.lower()
    for ns, d in teams["en-us"].items():
        for k, v in d.items():
            if t in v.lower():
                print(f"{ns}:{k}\t{v!r}")


def flips(assets_dir):
    """Fluent icons Teams mirrors in right-to-left languages: its icon
    library marks them {flipInRtl: true} (`("ArrowReply20Regular", "20",
    [paths], {flipInRtl: !0})` in its bundles). Writes their OST names'
    stems ("arrow-reply") to rtl_flip_icons.json."""
    import gzip

    pat = re.compile(rb'\("([A-Z][A-Za-z0-9]+)","[0-9a-z]+",\[(?:"[^"]*",?)+\],\{flipInRtl:!0\}')
    names = set()
    for f in sorted(os.listdir(assets_dir)):
        if "-locale-" in f or not (f.endswith(".js") or f.endswith(".js.gz")):
            continue
        p = os.path.join(assets_dir, f)
        raw = gzip.open(p).read() if f.endswith(".gz") else open(p, "rb").read()
        for m in pat.finditer(raw):
            n = re.sub(r"\d*(Regular|Filled|Light|Color)$", "", m.group(1).decode())
            names.add(re.sub(r"(?<=[a-z0-9])(?=[A-Z])", "-", n).lower())
    with open(os.path.join(HERE, "rtl_flip_icons.json"), "w", encoding="utf-8") as out:
        out.write(json.dumps(sorted(names), indent=0) + "\n")
    print(f"{len(names)} icons flip in right-to-left languages")


if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "flips":
        flips(sys.argv[2])
        sys.exit()
    if cmd == "strings":
        import teams_strings

        res = teams_strings.read_dir(sys.argv[2])
        with open(sys.argv[3], "w", encoding="utf-8") as out:
            json.dump(res, out, ensure_ascii=False)
    elif cmd == "extra":
        import extra_strings

        teams = json.load(open(sys.argv[2], encoding="utf-8"))
        s, f = extra_strings.collect(sorted(teams), sys.argv[3], sys.argv[4])
        with open(extra_path(sys.argv[2]), "w", encoding="utf-8") as out:
            json.dump({"strings": s, "files": f}, out, ensure_ascii=False)
    elif cmd == "gen":
        gen(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None, sys.argv[4] if len(sys.argv) > 4 else "")
    elif cmd == "find":
        find(sys.argv[2], " ".join(sys.argv[3:]))
    else:
        sys.exit(__doc__)
