#!/usr/bin/env python3
"""Strings from the Edge WebView2 runtime's locale .pak files, read out of
Microsoft's WebView2 Fixed Version cabinet (developer side of TASK-0233).

Teams' Downloads panel is WebView2's own downloads hub
(edge://downloads-hub); its text lives only in the runtime's
`Locales/<lang>.pak` resource packs, which no web CDN serves on their own.
Microsoft does serve the whole runtime: the Fixed Version cabinet
(`Microsoft.WebView2.FixedVersionRuntime.<version>.x64.cab`, about 300 MB,
links on developer.microsoft.com/microsoft-edge/webview2), one MSZIP
folder in which the locale packs sit at known offsets (its CFFILE table).
The server takes HTTP range requests, so the app fetches only the few
compressed blocks holding the strings it needs:

- MSZIP blocks (CFDATA: checksum, compressed size, uncompressed size,
  "CK" + a deflate stream) keep a 32 KiB history from the block before,
  so a block can't be inflated alone. Inflating from a few blocks earlier
  with an unknown history works for most bytes; which ones are exact is
  known by inflating twice, with histories of all 0x00 and all 0xFF: a
  byte that is the same both times owes nothing to the unknown history.
- Here (once per runtime version) the whole cabinet is read, the blocks'
  offsets indexed, and for each language the block ranges ("segments",
  with enough lead blocks that the needed strings come out exact) and the
  needed resources' offsets in the folder are written to
  teams_resources.json; the app inflates those ranges the same way
  (src/api/teams_strings.rs).

Edge's pak format (version 5 with 32-bit ids): u32 version, u32 encoding,
u32 resource count, u32 alias count, then (u32 id, u32 offset) per
resource plus one end entry, then (u32 id, u32 entry index) per alias.
Its strings use $1, $2… placeholders ($$ a dollar), turned into {0}, {1}….
"""

import os
import re
import shutil
import struct
import urllib.request
import zlib

HIST = 32768


def download(url, path):
    if os.path.exists(path):
        return path
    tmp = path + ".part"
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=120) as r, open(tmp, "wb") as out:
        shutil.copyfileobj(r, out, 1 << 20)
    os.replace(tmp, path)
    return path


def cab_header(f):
    """(folder's first CFDATA offset, block count, compression, files): files
    as {name: (uncompressed offset, size)} (one-folder cabinets)."""
    head = f.read(36)
    sig, _, _, _, coff_files, _, _, _, n_folders, n_files, flags = struct.unpack_from("<4sIIIIIBBHHH", head)
    if sig != b"MSCF" or n_folders != 1:
        raise ValueError("not a one-folder cabinet")
    off = 36
    cb_folder = cb_data = 0
    if flags & 4:
        f.seek(off)
        cb_res, cb_folder, cb_data = struct.unpack("<HBB", f.read(4))
        off += 4 + cb_res
    if cb_data:
        raise ValueError("per-block reserve unsupported")
    f.seek(off)
    first, n_blocks, comp = struct.unpack("<IHH", f.read(8))
    if comp & 0xF != 1:
        raise ValueError("not MSZIP")
    f.seek(coff_files)
    raw = f.read(1 << 20)
    files = {}
    p = 0
    for _ in range(n_files):
        size, uoff, _, _, _, _ = struct.unpack_from("<IIHHHH", raw, p)
        p += 16
        e = raw.index(b"\0", p)
        files[raw[p:e].decode("latin-1").replace("\\", "/")] = (uoff, size)
        p = e + 1
    return first, n_blocks, files


def blocks(f, first, n):
    """[(compressed offset of the CFDATA header, uncompressed offset)]."""
    out = []
    pos, uoff = first, 0
    for _ in range(n):
        f.seek(pos)
        _, cb, ucb = struct.unpack("<IHH", f.read(8))
        out.append((pos, uoff))
        pos += 8 + cb
        uoff += ucb
    out.append((pos, uoff))
    return out


def inflate_run(data, hist_byte):
    """Inflate consecutive CFDATA blocks (bytes starting at a header) with
    an unknown first history filled with `hist_byte`."""
    hist = bytes([hist_byte]) * HIST
    out = bytearray()
    p = 0
    while p + 8 <= len(data):
        _, cb, ucb = struct.unpack_from("<IHH", data, p)
        body = data[p + 8 : p + 8 + cb]
        if len(body) < cb or body[:2] != b"CK":
            break
        d = zlib.decompressobj(-15, zdict=hist)
        chunk = d.decompress(body[2:]) + d.flush()
        if len(chunk) != ucb:
            raise ValueError("bad MSZIP block")
        out += chunk
        hist = (hist + chunk)[-HIST:]
        p += 8 + cb
    return bytes(out)


def inflate_known(data):
    """(bytes, known mask) for blocks inflated with an unknown history."""
    a = inflate_run(data, 0)
    b = inflate_run(data, 255)
    return a, bytes(x == y for x, y in zip(a, b))


def read_pak(b):
    ver, enc, n, na = struct.unpack_from("<IIII", b, 0)
    if ver != 5:
        raise ValueError(f"pak version {ver}")
    ents = [struct.unpack_from("<II", b, 16 + 8 * i) for i in range(n + 1)]
    out = {}
    for i in range(n):
        out[ents[i][0]] = (ents[i][1], ents[i + 1][1] - ents[i][1])
    ao = 16 + 8 * (n + 1)
    for i in range(na):
        rid, idx = struct.unpack_from("<II", b, ao + 8 * i)
        out[rid] = (ents[idx][1], ents[idx + 1][1] - ents[idx][1])
    return out


def pak_text(s):
    """Edge's $1 placeholders as {0}; $$ a dollar."""
    return re.sub(r"\$(\$|\d)", lambda m: "$" if m.group(1) == "$" else "{%d}" % (int(m.group(1)) - 1), s)


def pak_file(loc, names):
    """The runtime's pack for a Teams locale (`Locales/de.pak`)."""
    special = {"sr-cyrl-rs": "sr", "es-mx": "es-419", "zh-hk": "zh-TW", "nb-no": "nb", "nn-no": "nn"}
    lang, _, region = loc.partition("-")
    cands = [special.get(loc, ""), f"{lang}-{region.upper()}", loc, lang]
    if region in ("latn-rs", "latn-ba"):
        cands.insert(0, "sr-Latn-RS")
    have = {n.lower(): n for n in names}
    for c in cands:
        if c and c.lower() in have:
            return have[c.lower()]
    return None


def segments(index, ranges, data_known, max_lead=256):
    """Block ranges covering `ranges` ([(uoff, size)]) with enough lead that
    every byte of them comes out exact: [(cab start, cab end, uoff of the
    first block)]. `data_known(i0, i1)` inflates blocks i0..i1 with an
    unknown history and gives (uoff, bytes, mask)."""
    ub = [u for _, u in index]
    import bisect

    def block_of(u):
        return bisect.bisect_right(ub, u) - 1

    # merge ranges that share or neighbour blocks
    spans = sorted((block_of(u), block_of(u + s - 1), u, s) for u, s in ranges)
    groups = []
    for b0, b1, u, s in spans:
        if groups and b0 <= groups[-1][1] + 2:
            g = groups[-1]
            groups[-1] = (g[0], max(g[1], b1), g[2] + [(u, s)])
        else:
            groups.append((b0, b1, [(u, s)]))
    out = []
    for b0, b1, rs in groups:
        lead = 0
        while True:
            s0 = max(0, b0 - lead)
            u0, _, mask = data_known(s0, b1)
            if all(all(mask[u - u0 : u - u0 + s]) for u, s in rs) or s0 == 0:
                break
            if lead >= max_lead:
                raise ValueError("strings don't come out exact")
            lead = lead * 2 if lead else 1
        out.append((index[s0][0], index[b1 + 1][0], index[s0][1]))
    # one range for overlapping ones (their lead blocks)
    merged = []
    for a, b, u in sorted(out):
        if merged and a <= merged[-1][1]:
            merged[-1] = (merged[-1][0], max(merged[-1][1], b), merged[-1][2])
        else:
            merged.append((a, b, u))
    return merged


def collect(url, version, locales, cache, wanted, id_ranges=None):
    """{locale: {id: text}} for the resources whose en-US text `wanted(text)`
    accepts (within `id_ranges`, [[first, last]], when given: one screen's
    resources), and {locale: {"file", "segments", "res"}} for the app."""
    os.makedirs(cache, exist_ok=True)
    path = download(url, os.path.join(cache, f"webview2-{version}-x64.cab"))
    with open(path, "rb") as f:
        first, n, files = cab_header(f)
        index = blocks(f, first, n)
        packs = {name.rsplit("/", 1)[1][:-4]: (u, s) for name, (u, s) in files.items() if "/Locales/" in name and name.endswith(".pak") and "copilot" not in name}

        def read_range(i0, i1):
            f.seek(index[i0][0])
            return f.read(index[i1 + 1][0] - index[i0][0])

        # the locale packs' bytes, exact: the folder inflated from its start
        lo = min(u for u, _ in packs.values())
        hi = max(u + s for u, s in packs.values())
        f.seek(index[0][0])
        hist = b""
        keep = bytearray()
        for i in range(n):
            pos, uoff = index[i]
            f.seek(pos)
            _, cb, ucb = struct.unpack("<IHH", f.read(8))
            body = f.read(cb)
            d = zlib.decompressobj(-15, zdict=hist) if hist else zlib.decompressobj(-15)
            chunk = d.decompress(body[2:]) + d.flush()
            hist = (hist + chunk)[-HIST:]
            if uoff + ucb > lo and uoff < hi:
                keep += chunk if uoff >= lo else chunk[lo - uoff :]
            if uoff >= hi:
                break

        def folder_bytes(u, s):
            return bytes(keep[u - lo : u - lo + s])

        def data_known(i0, i1):
            d, m = inflate_known(read_range(i0, i1))
            return index[i0][1], d, m

        en = packs["en-US"]
        en_pak = folder_bytes(*en)
        en_res = read_pak(en_pak)
        ids = sorted(rid for rid, (o, s) in en_res.items() if (not id_ranges or any(a <= rid <= b for a, b in id_ranges)) and s and _utf8(en_pak[o : o + s]) and wanted(pak_text(_utf8(en_pak[o : o + s]))))
        strings = {"en-us": {str(rid): pak_text(_utf8(en_pak[en_res[rid][0] : sum(en_res[rid])])) for rid in ids}}
        parts = {}
        for loc in locales:
            if loc == "en-us":
                continue
            name = pak_file(loc, packs)
            if not name:
                continue
            u, s = packs[name]
            head = folder_bytes(u, 16)
            cnt, na = struct.unpack_from("<II", head, 8)
            res = read_pak(folder_bytes(u, 16 + 8 * (cnt + 1) + 8 * na))
            got = {}
            ranges = []
            for rid in ids:
                if rid in res and res[rid][1]:
                    o, sz = res[rid]
                    got[rid] = (u + o, sz)
                    ranges.append((u + o, sz))
            if not ranges:
                continue
            segs = segments(index, ranges, data_known)
            texts = {}
            for rid, (uo, sz) in got.items():
                t = _utf8(folder_bytes(uo, sz))
                if t is not None:
                    texts[str(rid)] = pak_text(t)
            strings[loc] = texts
            parts[loc] = {"file": f"Locales/{name}.pak", "segments": [list(x) for x in segs], "res": {str(r): list(v) for r, v in sorted(got.items())}}
    return strings, parts


def _utf8(b):
    try:
        return b.decode("utf-8")
    except UnicodeDecodeError:
        return None
