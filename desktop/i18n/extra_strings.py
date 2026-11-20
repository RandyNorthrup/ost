#!/usr/bin/env python3
"""Teams' text from its other bundles (developer side of TASK-0233).

Some of what Teams shows keeps its translations outside Teams' main string
table (teams_strings.py): the clip recorder (OneCamera), OneDrive's web
apps that Teams hosts (file browser, Move/Copy picker, …), Stream, …. Each
such bundle ships one webpack chunk per language whose modules are string
tables. extra_sources.json says where they are; this module downloads the
en-us and every other language's chunk, reads their tables, and gives

    strings: {locale: {"x.<source>": {key: text}}}   (merged into Teams'
             strings by `l10n.py gen`, so OST's text is keyed to them)
    files:   {"x.<source>": {base, kind, ids, files: {locale: path}}}
             (teams_resources.json's `extra`, read by the app at runtime)

No translations are written to the repository: the app downloads the same
files on the device (src/api/teams_strings.rs).

Kinds:
- "json": modules `7680(f){f.exports=JSON.parse('{"a":"…"}')}` (OneDrive's
  `<lang>/initial.resx.js` / `ondemand.resx.js`); keys "<module>.<key>"
  (module ids are the same in every language of one build).
- "esm": an ES module of object literals (`const n={addMusic:"…"};…
  e.common=n`), Teams' `onecamera-locale-<lang>-<hash>.js`; keys
  "<export>.<key path>". Its en-us text sits in the recorder's own bundle
  (`var n0={common:ob,…}`).
"""

import gzip
import json
import os
import re
import sys
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
TEAMS_CDN = "https://statics.teams.cdn.office.net/teams-modular-packages/hashed-assets/"

_ESC = {"n": "\n", "t": "\t", "r": "\r", "b": "\b", "f": "\f", "v": "\v", "0": "\0"}


def js_string(s, i):
    q = s[i]
    i += 1
    out = []
    while True:
        c = s[i]
        if c == "\\":
            n = s[i + 1]
            if n == "u":
                if s[i + 2] == "{":
                    j = s.index("}", i)
                    out.append(chr(int(s[i + 3 : j], 16)))
                    i = j + 1
                else:
                    out.append(chr(int(s[i + 2 : i + 6], 16)))
                    i += 6
                continue
            if n == "x":
                out.append(chr(int(s[i + 2 : i + 4], 16)))
                i += 4
                continue
            out.append(_ESC.get(n, n))
            i += 2
            continue
        if c == q:
            t = "".join(out)
            if any(0xD800 <= ord(x) < 0xE000 for x in t):
                t = t.encode("utf-16", "surrogatepass").decode("utf-16")
            return t, i + 1
        out.append(c)
        i += 1


def _flatten(v, pre, out):
    if isinstance(v, dict):
        for k, x in v.items():
            _flatten(x, f"{pre}.{k}" if pre else k, out)
    elif isinstance(v, str):
        out[pre] = v


_MOD_ID = re.compile(r"(?<![\w$])(\d+)[(:][^{}]{0,40}\{[^{}]{0,40}$")


def parse_json_modules(s, with_ids=True):
    out = {}
    mark = ".exports=JSON.parse("
    i = 0
    while True:
        p = s.find(mark, i)
        if p < 0:
            return out
        i = p + len(mark)
        if s[i] not in "'\"`":
            continue
        text, i = js_string(s, i)
        try:
            v = json.loads(text, strict=False)
        except ValueError:
            continue
        pre = ""
        if with_ids:
            m = _MOD_ID.search(s[max(0, p - 64) : p])
            if not m:
                continue
            pre = m.group(1)
        _flatten(v, pre, out)


def json_parse_holding(s, key):
    """The `JSON.parse('…')` table in `s` that has `key`."""
    i = 0
    while True:
        p = s.find("JSON.parse(", i)
        if p < 0:
            return {}
        i = p + 11
        if s[i] not in "'\"`":
            continue
        text, i = js_string(s, i)
        try:
            v = json.loads(text, strict=False)
        except ValueError:
            continue
        if isinstance(v, dict) and key in v:
            out = {}
            _flatten(v, "", out)
            return out


def parse_flat_json(s):
    """A plain JSON string table (nested objects flattened with dots)."""
    out = {}
    _flatten(json.loads(s, strict=False), "", out)
    return out


def object_literal(s, i):
    """A JS object literal of strings / nested objects at s[i] == "{"."""
    if s[i] != "{":
        return None
    j = i + 1
    d = {}
    while True:
        while s[j].isspace():
            j += 1
        if s[j] == "}":
            return d, j + 1
        if s[j] == ",":
            j += 1
            continue
        if s[j] in "\"'":
            k, j = js_string(s, j)
        else:
            m = re.compile(r"[\w$]+").match(s, j)
            if not m:
                return None
            k, j = m.group(0), m.end()
        while s[j].isspace():
            j += 1
        if s[j] != ":":
            return None
        j += 1
        while s[j].isspace():
            j += 1
        if s[j] in "\"'`":
            v, n = js_string(s, j)
            if not (s[j] == "`" and "${" in v):
                d[k] = v
            j = n
        elif s[j] == "{":
            r = object_literal(s, j)
            if r is None:
                return None
            d[k], j = r
        else:
            while s[j] not in ",}":
                j += 1


def _objects(s):
    objs = {}
    for m in re.finditer(r"(?<![\w$.])([\w$]+)=\{", s):
        try:
            r = object_literal(s, m.end() - 1)
        except IndexError:
            r = None
        if r:
            objs[m.group(1)] = r[0]
    return objs


def parse_esm_tables(s):
    """`const n={…};…e.common=n` (a language chunk)."""
    objs = _objects(s)
    out = {}
    for m in re.finditer(r"(?<=[\w$])\.([\w$]+)=([\w$]+)(?=[,};])", s):
        if m.group(2) in objs:
            _flatten(objs[m.group(2)], m.group(1), out)
    return out


def parse_esm_english(s, first_key):
    """The en-us tables in the bundle that embeds them: the object literal
    of variables (`var n0={common:ob,colors:ab,…}`) whose first entry is
    `first_key`."""
    m = re.search(r"\{" + re.escape(first_key) + r":([\w$]+),([\w$]+:[\w$]+,?)+\}", s)
    if not m:
        raise ValueError(f"no {first_key} table")
    names = dict(kv.split(":") for kv in m.group(0)[1:-1].split(","))
    want = set(names.values())
    objs = {}
    for mm in re.finditer(r"(?<![\w$.])([\w$]+)=\{", s):
        if mm.group(1) in want and mm.group(1) not in objs:
            r = object_literal(s, mm.end() - 1)
            if r:
                objs[mm.group(1)] = r[0]
    out = {}
    for name, var in names.items():
        if var in objs:
            _flatten(objs[var], name, out)
    return out


def get(url, cache):
    """A URL's text (cached in `cache`); None for a 404."""
    path = os.path.join(cache, re.sub(r"[^\w.-]+", "_", url.split("//", 1)[1]))
    if os.path.exists(path):
        raw = open(path, "rb").read()
        return None if raw == b"404" else raw.decode("utf-8")
    try:
        raw = urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"}), timeout=60).read()
    except urllib.error.HTTPError as e:
        if e.code in (403, 404):
            open(path, "wb").write(b"404")
            return None
        raise
    if raw[:2] == b"\x1f\x8b":
        raw = gzip.decompress(raw)
    open(path, "wb").write(raw)
    return raw.decode("utf-8")


def _runtime_chunks(runtime_js):
    """Teams' webpack runtime: chunk file names (`a.un` names, `a.uh` hashes)."""
    s = open(runtime_js, encoding="utf-8").read()

    def table(name):
        i = s.index(f"a.{name}={{")
        j = s.index("}", i)
        return dict(re.findall(r'(\d+):"([^"]*)"', s[i:j]))

    un, uh = table("un"), table("uh")
    return {un[k]: f"{un[k]}-{uh[k]}.js" for k in un if k in uh}


def _lang_candidates(loc):
    lang = loc.split("-")[0]
    special = {"zh-cn": ["zh-Hans"], "zh-tw": ["zh-Hant"], "zh-hk": ["zh-Hant"], "sr-latn-rs": ["sr-Latn-RS"], "sr-cyrl-rs": ["sr-Cyrl-RS"], "nn-no": ["nn-np"]}
    return [loc] + special.get(loc, []) + [lang]


def collect(locales, assets_dir, cache):
    src = json.load(open(os.path.join(HERE, "extra_sources.json"), encoding="utf-8"))
    os.makedirs(cache, exist_ok=True)
    strings = {}
    files = {}
    runtime = None
    for ns, cfg in src["sources"].items():
        kind = cfg.get("kind", "json")
        entry = {"base": "", "kind": kind, "ids": bool(cfg.get("ids")), "files": {}}
        if "odsp" in cfg:
            entry["base"] = src["odspBase"] + cfg["odsp"] + "/"
            for loc in locales:
                for lang in [loc] + ([loc.split("-")[0]] if loc != "en-us" else []):
                    path = f"{lang}/{cfg['chunk']}.resx.js"
                    text = get(entry["base"] + path, cache)
                    if text is not None:
                        strings.setdefault(loc, {})[ns] = parse_json_modules(text, entry["ids"])
                        if loc != "en-us":
                            entry["files"][loc] = path
                        break
        elif "runtime" in cfg:
            # a web app's own webpack runtime names its chunks:
            # `.u=e=>"js/"+({id:"name",…}[e]||e)+"."+{id:"hash",…}[e]+".chunk.js"`
            entry["base"] = cfg["base"]
            rt = get(cfg["base"] + cfg["runtime"], cache)
            m = re.search(r'\.u=\w=>"([^"]*)"\+\(\{(.*?)\}\[\w\]\|\|\w\)\+"\."\+\{(.*?)\}\[\w\]\+"([^"]*)"', rt)
            num = lambda k: str(int(float(k)))  # noqa: E731
            names = {num(k): v for k, v in re.findall(r'([\d.e]+):"([^"]*)"', m.group(2))}
            hashes = {num(k): v for k, v in re.findall(r'([\d.e]+):"([^"]*)"', m.group(3))}
            by_name = {n: f"{m.group(1)}{n}.{hashes[k]}{m.group(4)}" for k, n in names.items() if k in hashes}
            for loc in locales:
                if loc == "en-us":
                    continue
                cands = [cfg["langMap"][loc]] if loc in cfg.get("langMap", {}) else [loc, loc.split("-")[0]]
                for lang in cands:
                    file = by_name.get(cfg["chunk"].replace("{lang}", lang))
                    if file:
                        text = get(cfg["base"] + file, cache)
                        if text is not None:
                            strings.setdefault(loc, {})[ns] = parse_json_modules(text, False)
                            entry["files"][loc] = file
                        break
            text = get(cfg["base"] + cfg["englishFile"], cache)
            if "englishKey" in cfg:
                # the en-us table is a JSON.parse('…') inside a module
                strings.setdefault("en-us", {})[ns] = json_parse_holding(text, cfg["englishKey"])
            else:
                pre = cfg["englishModule"] + "."
                strings.setdefault("en-us", {})[ns] = {k[len(pre):]: v for k, v in parse_json_modules(text, True).items() if k.startswith(pre)}
        elif "path" in cfg:
            # one file per language at base + path ({lang}: the bundle's
            # folder name; langMap names those that aren't the locale or
            # its language)
            entry["base"] = cfg["base"]
            for loc in locales:
                cands = [cfg["english"]] if loc == "en-us" else ([cfg["langMap"][loc]] if loc in cfg.get("langMap", {}) else [loc, loc.split("-")[0]])
                for lang in cands:
                    path = cfg["path"].replace("{lang}", lang)
                    text = get(entry["base"] + path, cache)
                    if text is not None:
                        strings.setdefault(loc, {})[ns] = parse_flat_json(text) if kind == "flatjson" else parse_json_modules(text, entry["ids"])
                        if loc != "en-us":
                            entry["files"][loc] = path
                        break
        elif "teamsChunks" in cfg:
            if runtime is None:
                rt = [f for f in os.listdir(assets_dir) if f.startswith("runtime-") and f.endswith(".js")]
                runtime = {}
                for f in rt:
                    runtime.update(_runtime_chunks(os.path.join(assets_dir, f)))
            entry["base"] = TEAMS_CDN
            # chunk names: "<prefix><lang>" or a pattern with {lang}
            pat = cfg["teamsChunks"] if "{lang}" in cfg["teamsChunks"] else cfg["teamsChunks"] + "{lang}"
            rx = re.compile("^" + re.escape(pat).replace(re.escape("{lang}"), "(.+)") + "$")
            have = {m.group(1).lower(): file for name, file in runtime.items() for m in [rx.match(name)] if m}
            for loc in locales:
                if loc == "en-us":
                    continue
                for lang in _lang_candidates(loc):
                    file = have.get(lang.lower())
                    if file:
                        text = get(TEAMS_CDN + file, cache)
                        if text is not None:
                            strings.setdefault(loc, {})[ns] = parse_esm_tables(text) if kind == "esm" else parse_json_modules(text, entry["ids"])
                            entry["files"][loc] = file
                        break
            # en-us: the bundle that embeds it
            if kind == "esm":
                bundle = [f for f in os.listdir(assets_dir) if re.fullmatch(cfg["englishBundle"], f)]
                if bundle:
                    text = open(os.path.join(assets_dir, bundle[0]), encoding="utf-8").read()
                    strings.setdefault("en-us", {})[ns] = parse_esm_english(text, cfg["englishFirstKey"])
            else:
                file = runtime.get(cfg["englishChunk"])
                text = file and get(TEAMS_CDN + urllib.request.quote(file), cache)
                if text:
                    strings.setdefault("en-us", {})[ns] = parse_json_modules(text, entry["ids"])
        files[ns] = entry
        print(ns, len(strings.get("en-us", {}).get(ns, {})), "en-us strings,", len(entry["files"]), "languages")
    return strings, files


if __name__ == "__main__":
    # extra_strings.py <strings.json> <hashed-assets dir> <cache dir> <out.json>
    teams = json.load(open(sys.argv[1], encoding="utf-8"))
    s, f = collect(sorted(teams), sys.argv[2], sys.argv[3])
    json.dump({"strings": s, "files": f}, open(sys.argv[4], "w", encoding="utf-8"), ensure_ascii=False)
