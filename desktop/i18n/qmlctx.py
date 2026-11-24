"""Where each string literal of a QML file sits: the binding or object key
it belongs to, the call it is an argument of, and its neighbours.

literals(src) yields Lit records for every quoted string literal.
"""

from dataclasses import dataclass

from qmltok import tokens


@dataclass
class Lit:
    text: str  # decoded text
    start: int  # source span of the literal, quotes included
    end: int
    key: str  # innermost binding / object key ("text", "Accessible.name", "fn:title"), "" if none
    keys: tuple  # every enclosing key, innermost first
    call: str  # innermost call it is an argument of ("backend.openUrl"), "" if none
    calls: tuple  # every enclosing call, innermost first
    prev: str  # previous token
    next: str  # next token
    line: int


_OPEN = {"(": ")", "[": "]", "{": "}"}


def literals(src):
    toks = list(tokens(src))
    line_of = _line_index(src)
    # frames: [opener, key, call]
    frames = [["top", "", ""]]
    out = []
    for i, (kind, val, a, b) in enumerate(toks):
        if kind == "punct" and val in _OPEN:
            call = ""
            fkey = ""
            if val == "(":
                call = _callee(toks, i)
            elif val == "{":
                fkey = _function_name(toks, i)
            frames.append([val, fkey, call])
            continue
        if kind == "punct" and val in (")", "]", "}"):
            if len(frames) > 1:
                frames.pop()
            continue
        # A binding or object key: `name:` / `A.b:` after a statement start.
        if kind == "punct" and val == ":" and i > 0 and toks[i - 1][0] in ("id", "str"):
            j = i - 1
            parts = [toks[j][1]]
            while j >= 2 and toks[j - 1][1] == "." and toks[j - 2][0] == "id":
                parts.insert(0, toks[j - 2][1])
                j -= 2
            before = toks[j - 1] if j > 0 else None
            at_line_start = before is None or src.rfind("\n", 0, toks[j][2]) >= before[3]
            if (before is None or before[1] in ("{", ",", ";") or at_line_start) and (before is None or before[1] not in ("?", "case")):
                frames[-1][1] = ".".join(parts)
            elif before is not None and _is_property_declaration(toks, j):
                frames[-1][1] = ".".join(parts)
            continue
        if kind == "punct" and val == ";" and frames[-1][0] in ("top", "{") and not frames[-1][1].startswith("fn:"):
            # `text: "a"; color: "b"` on one line: the next binding sets its key.
            pass
        if kind != "str":
            continue
        keys = tuple(f[1] for f in reversed(frames) if f[1])
        calls = tuple(f[2] for f in reversed(frames) if f[2])
        # the innermost key at or above the innermost call frame
        key = ""
        for f in reversed(frames):
            if f[1]:
                key = f[1]
                break
            if f[2]:
                break
        call = ""
        for f in reversed(frames):
            if f[2]:
                call = f[2]
                break
            if f[1]:
                break
        prev = toks[i - 1][1] if i > 0 else ""
        nxt = toks[i + 1][1] if i + 1 < len(toks) else ""
        out.append(Lit(val, a, b, key, keys, call, calls, prev, nxt, line_of(a)))
    return out


def _is_property_declaration(toks, j):
    """toks[j] is the name in `[readonly] property <type> name:`."""
    k = j - 1
    # the type: `string`, `var`, `list<string>`, `Foo.Bar`
    if k >= 0 and toks[k][1] == ">":
        while k >= 0 and toks[k][1] != "<":
            k -= 1
        k -= 1
    while k >= 2 and toks[k - 1][1] == "." and toks[k - 2][0] == "id":
        k -= 2
    return k >= 1 and toks[k][0] == "id" and toks[k - 1][1] == "property"


def _callee(toks, i):
    """`foo.bar(` -> 'foo.bar'; '' for `(` that isn't a call."""
    j = i - 1
    if j < 0 or toks[j][0] != "id" or toks[j][1] in ("if", "while", "for", "switch", "return", "function", "catch", "typeof"):
        return ""
    parts = [toks[j][1]]
    while j >= 2 and toks[j - 1][1] in (".", "?.") and toks[j - 2][0] == "id":
        parts.insert(0, toks[j - 2][1])
        j -= 2
    if j >= 1 and toks[j - 1][1] == "function":
        return ""
    return ".".join(parts)


def _function_name(toks, i):
    """For a `{` opening a function body: 'fn:<name>' (or 'fn:' for an
    anonymous function or arrow); '' otherwise."""
    j = i - 1
    if j >= 0 and toks[j][1] == "=>":
        return "fn:"
    if j < 0 or toks[j][1] != ")":
        return ""
    depth = 0
    while j >= 0:
        v = toks[j][1]
        if v == ")":
            depth += 1
        elif v == "(":
            depth -= 1
            if depth == 0:
                break
        j -= 1
    if j >= 1 and toks[j - 1][0] == "id":
        if j >= 2 and toks[j - 2][1] == "function":
            return "fn:" + toks[j - 1][1]
        if toks[j - 1][1] == "function":
            return "fn:"
        if toks[j - 1][1] in ("if", "while", "for", "switch", "catch", "with"):
            return ""
        # a QML signal handler with arguments: onFoo: (a) => {} handled by =>
        return ""
    return ""


def _line_index(src):
    import bisect

    starts = [0] + [i + 1 for i, c in enumerate(src) if c == "\n"]
    return lambda pos: bisect.bisect_right(starts, pos)
