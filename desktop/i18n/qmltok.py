"""A small QML/JavaScript tokenizer: enough to find string literals and
what surrounds them.

tokens(src) yields (kind, value, start, end) with kind one of
'str' (a quoted string; value is its decoded text), 'tmpl' (a template
literal; value is its raw source), 'id', 'num', 'punct', 'regex'.
Comments and whitespace are skipped.
"""

import re

_ID = re.compile(r"[A-Za-z_$][\w$]*")
_NUM = re.compile(r"0[xX][0-9a-fA-F]+|(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?")
_PUNCT = ["===", "!==", ">>>=", "...", "**=", "<<=", ">>=", ">>>", "&&=", "||=", "??=", "=>", "==", "!=", "<=", ">=", "&&", "||", "??", "?.", "++", "--", "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=", "<<", ">>", "**"]
_ESC = {"n": "\n", "t": "\t", "r": "\r", "b": "\b", "f": "\f", "v": "\v", "0": "\0"}
# After these a '/' starts a regex, not a division.
_REGEX_AFTER_ID = {"return", "typeof", "case", "do", "else", "in", "instanceof", "new", "delete", "void", "throw"}


def decode(raw):
    """Decode the body of a JS string literal (without its quotes)."""
    out, i = [], 0
    while i < len(raw):
        c = raw[i]
        if c != "\\":
            out.append(c)
            i += 1
            continue
        n = raw[i + 1]
        if n == "u":
            if raw[i + 2] == "{":
                j = raw.index("}", i)
                out.append(chr(int(raw[i + 3 : j], 16)))
                i = j + 1
            else:
                out.append(chr(int(raw[i + 2 : i + 6], 16)))
                i += 6
        elif n == "x":
            out.append(chr(int(raw[i + 2 : i + 4], 16)))
            i += 4
        elif n == "\n":
            i += 2
        else:
            out.append(_ESC.get(n, n))
            i += 2
    return "".join(out)


def _skip_string(src, i):
    q = src[i]
    i += 1
    while src[i] != q:
        if src[i] == "\\":
            i += 1
        i += 1
    return i + 1


def _skip_template(src, i):
    i += 1
    while src[i] != "`":
        if src[i] == "\\":
            i += 2
            continue
        if src.startswith("${", i):
            i = _skip_braces(src, i + 2)
            continue
        i += 1
    return i + 1


def _skip_braces(src, i):
    depth = 1
    for kind, _, a, b in tokens(src, i):
        if kind == "punct" and src[a] == "{":
            depth += 1
        elif kind == "punct" and src[a] == "}":
            depth -= 1
            if depth == 0:
                return b
    raise ValueError("unbalanced ${")


def tokens(src, i=0):
    n = len(src)
    prev = None  # (kind, value)
    while i < n:
        c = src[i]
        if c in " \t\r\n":
            i += 1
            continue
        if src.startswith("//", i):
            j = src.find("\n", i)
            i = n if j < 0 else j
            continue
        if src.startswith("/*", i):
            i = src.index("*/", i) + 2
            continue
        if c in "\"'":
            j = _skip_string(src, i)
            tok = ("str", decode(src[i + 1 : j - 1]), i, j)
        elif c == "`":
            j = _skip_template(src, i)
            tok = ("tmpl", src[i:j], i, j)
        elif c == "/" and (prev is None or (prev[0] == "punct" and prev[1] not in (")", "]", "}")) or (prev[0] == "id" and prev[1] in _REGEX_AFTER_ID)):
            j = i + 1
            cls = False
            while True:
                ch = src[j]
                if ch == "\\":
                    j += 2
                    continue
                if ch == "[":
                    cls = True
                elif ch == "]":
                    cls = False
                elif ch == "/" and not cls:
                    break
                elif ch == "\n":
                    raise ValueError(f"bad regex at {i}: {src[i:i+40]!r}")
                j += 1
            j += 1
            while j < n and (src[j].isalnum()):
                j += 1
            tok = ("regex", src[i:j], i, j)
        elif (m := _ID.match(src, i)) :
            tok = ("id", m.group(0), i, m.end())
        elif (m := _NUM.match(src, i)) and (c.isdigit() or (c == "." and i + 1 < n and src[i + 1].isdigit())):
            tok = ("num", m.group(0), i, m.end())
        else:
            p = next((p for p in _PUNCT if src.startswith(p, i)), c)
            tok = ("punct", p, i, i + len(p))
        yield tok
        prev = (tok[0], tok[1])
        i = tok[3]
