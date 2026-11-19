#!/usr/bin/env python3
"""Read Teams' UI string resources.

Teams (new Teams, `desktop-assets/hashed-assets/` in its install) ships its
UI text as `<namespace>-locale-<locale>-<hash>.js[.gz]` webpack chunks, one
per namespace and locale (`main-locale-*` bundles many namespaces). Each
holds `{namespace:"…",locale:"…",translations:{<key>:"<text>",…}}`, where
keys are Teams' string ids (`k` + base36 hash) and texts use `{{name}}`
placeholders and ICU `{n, plural, …}` messages.

usage: teams_strings.py <hashed-assets dir> <out.json>
writes {locale: {namespace: {key: text}}}.
"""

import gzip
import json
import os
import re
import sys

_ESC = {"n": "\n", "t": "\t", "r": "\r", "b": "\b", "f": "\f", "v": "\v", "0": "\0"}
_HEAD = re.compile(r'namespace:"([^"]+)",locale:"([^"]+)",translations:\{')


def _js_string(s, i):
    """The JS string literal at s[i] (its quote), and the index after it."""
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
            return "".join(out), i + 1
        out.append(c)
        i += 1


def _surrogates(t):
    """JS strings are UTF-16: join \\ud83d\\ude00 pairs."""
    return t.encode("utf-16", "surrogatepass").decode("utf-16") if any(0xD800 <= ord(c) < 0xE000 for c in t) else t


def parse_chunk(s, res):
    for m in _HEAD.finditer(s):
        ns, loc = m.group(1), m.group(2)
        t = res.setdefault(loc, {}).setdefault(ns, {})
        i = m.end()
        while True:
            while s[i] in " ,\n":
                i += 1
            if s[i] == "}":
                break
            if s[i] in "\"'":
                k, i = _js_string(s, i)
            else:
                j = s.index(":", i)
                k, i = s[i:j], j
            if s[i] != ":":
                raise ValueError(f"unexpected {s[i - 20 : i + 20]!r}")
            i += 1
            if s[i] not in "\"'`":
                raise ValueError(f"unexpected value {s[i - 40 : i + 40]!r}")
            v, i = _js_string(s, i)
            t[k] = _surrogates(v)


def read_dir(d):
    res = {}
    for f in sorted(os.listdir(d)):
        if "-locale-" not in f or ".worker." in f or not (f.endswith(".js") or f.endswith(".js.gz")):
            continue
        p = os.path.join(d, f)
        raw = gzip.open(p).read() if f.endswith(".gz") else open(p, "rb").read()
        parse_chunk(raw.decode("utf-8"), res)
    return res


if __name__ == "__main__":
    res = read_dir(sys.argv[1])
    with open(sys.argv[2], "w", encoding="utf-8") as out:
        json.dump(res, out, ensure_ascii=False)
    for loc in sorted(res):
        print(loc, len(res[loc]), sum(len(v) for v in res[loc].values()))
