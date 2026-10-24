"""Measures the PDFs the spike wrote (tool input: the pulled `out` folder).

    python tool/analyze.py <out-dir>

For every sheet and every variant (writer raw|lib, mode A|B|C):
  * validity: opens with pypdf and PyMuPDF, page count, no EXIF/GPS anywhere;
  * Unicode: the text a viewer extracts equals the OCR text (spaces ignored);
  * position: for each character, the error of its place in the PDF against
    where it really is in the picture, as a share of the character's width;
  * selection: a simulated drag over the characters of a payment code (the
    selected characters are those whose centre lies between the two ends):
    how often the result is exactly the code, and how often a character is
    missing or added.
Numbers only; the sheets are invented.
"""
import difflib
import json
import math
import os
import random
import re
import statistics
import subprocess
import sys

import fitz  # PyMuPDF
import pypdf

OUT = sys.argv[1]
PT = 595.0  # page width in points, as in the spike


def load(name):
    with open(os.path.join(OUT, name), encoding='utf-8') as f:
        return json.load(f)


def pdf_chars(path):
    """All characters of page 1 as (char, centre_x, centre_y) in picture pixels."""
    doc = fitz.open(path)
    page = doc[0]
    raw = page.get_text('rawdict')
    out = []
    for block in raw['blocks']:
        for line in block.get('lines', []):
            for span in line['spans']:
                for ch in span['chars']:
                    x0, y0, x1, y1 = ch['bbox']
                    out.append((ch['c'], (x0 + x1) / 2, (y0 + y1) / 2, x1 - x0))
    return out, page.rect.width, page.rect.height


def to_picture(chars, pw, img_w):
    k = pw / img_w  # points per pixel
    return [(c, cx / k, cy / k, w / k) for (c, cx, cy, w) in chars]


def associate(truth, chars):
    """Per truth line, the PDF characters that lie on it, ordered along it,
    each with its along-line centre."""
    per = []
    for tl in truth['lines']:
        ca, sa = math.cos(tl['angle']), math.sin(tl['angle'])
        mine = []
        for (c, cx, cy, w) in chars:
            dx, dy = cx - tl['ox'], cy - tl['oy']
            along = dx * ca + dy * sa
            perp = -dx * sa + dy * ca
            if abs(perp) < tl['height'] * 0.6 and -50 < along < 1400:
                mine.append((along, c))
        mine.sort()
        per.append(mine)
    return per


def align_line(tl, mine):
    """Pairs (truth char index, pdf along-centre) by aligning the character
    sequences (spaces ignored)."""
    t_idx = [i for i, c in enumerate(tl['chars']) if c[0] != ' ']
    p = [(a, c) for (a, c) in mine if c != ' ']
    t_str = ''.join(tl['chars'][i][0] for i in t_idx)
    p_str = ''.join(c for (_, c) in p)
    sm = difflib.SequenceMatcher(None, t_str, p_str, autojunk=False)
    pairs = []
    for tag, a0, a1, b0, b1 in sm.get_opcodes():
        if tag in ('equal', 'replace') and (a1 - a0) == (b1 - b0):
            for k in range(a1 - a0):
                pairs.append((t_idx[a0 + k], p[b0 + k][0], tag == 'equal'))
    return pairs, t_str, p_str


def pdf_text_ok(path, ocr):
    doc = fitz.open(path)
    got = re.sub(r'\s', '', doc[0].get_text('text'))
    want = re.sub(r'\s', '', ''.join(l['text'] for l in ocr['lines']))
    return got == want, len(got), len(want), got, want


def jpeg_markers(data):
    """Marker bytes of a JPEG up to the scan (APPn, COM, SOF...)."""
    out, pos = [], 2
    while pos + 4 <= len(data) and data[pos] == 0xFF:
        m = data[pos + 1]
        if m == 0xDA:
            break
        size = (data[pos + 2] << 8) | data[pos + 3]
        out.append((m, data[pos + 4:pos + 4 + min(size - 2, 8)]))
        pos += 2 + size
    return out


def no_metadata(path):
    """No EXIF/GPS/XMP in the embedded picture, no document info (author,
    producer, creation date) in the PDF."""
    r = pypdf.PdfReader(path)
    data = r.pages[0].images[0].data
    marks = jpeg_markers(data)
    bad = [m for (m, head) in marks
           if m in (0xE1, 0xED, 0xFE) or head.startswith(b'Exif')]
    raw = open(path, 'rb').read()
    info = b'/Info' in raw or b'/Author' in raw or b'/CreationDate' in raw
    return (not bad and b'GPS' not in raw and b'Exif' not in raw), bad, info


def valid(path):
    try:
        r = pypdf.PdfReader(path, strict=True)
        n = len(r.pages)
        d = fitz.open(path)
        return n == d.page_count, n
    except Exception as e:  # noqa: BLE001
        return False, str(e)


def simulate_selection(truth_line, aligned, rng, jitter, trials, targets):
    """aligned: {truth index: pdf along-centre}. Returns counters."""
    res = dict(exact=0, missing=0, extra=0, wrong=0, total=0)
    chars = truth_line['chars']
    widths = [c[2] - c[1] for c in chars]
    avg_w = sum(widths) / len(widths)
    for (a, b) in targets:  # truth char index range [a, b]
        want = ''.join(c[0] for c in chars[a:b + 1])
        for _ in range(trials):
            s = chars[a][1] + rng.uniform(-jitter, jitter) * avg_w
            e = chars[b][2] + rng.uniform(-jitter, jitter) * avg_w
            got_idx = [i for i, along in sorted(aligned.items())
                       if s <= along <= e]
            got = ''.join(chars[i][0] for i in got_idx)
            res['total'] += 1
            if got == want:
                res['exact'] += 1
            elif len(got) < len(want):
                res['missing'] += 1
            elif len(got) > len(want):
                res['extra'] += 1
            else:
                res['wrong'] += 1
    return res


def code_targets(tl):
    """Index ranges to select: each whole code token, and 40 random sub-ranges
    of 5..18 characters inside tokens that contain digits (seeded)."""
    text = tl['text']
    targets = []
    rng = random.Random(5)
    for m in re.finditer(r'\S*\d\S*', text):
        a, b = m.start(), m.end() - 1
        if b - a + 1 < 6 or text[a:b + 1] != ''.join(c[0] for c in tl['chars'][a:b + 1]):
            continue
        targets.append((a, b))
        for _ in range(8):
            n = rng.randint(5, min(18, b - a + 1))
            s = rng.randint(a, b - n + 1)
            targets.append((s, s + n - 1))
    return targets


def main():
    summary = json.load(open(os.path.join(OUT, 'bench_summary.json')))
    names = [s['name'] for s in summary['sheets']]
    rows = []
    for name in names:
        truth, ocr = load(f'{name}_truth.json'), load(f'{name}_ocr.json')
        # OCR accuracy of the lines (engine, not the PDF)
        t_text = [l['text'] for l in truth['lines']]
        o_text = [l['text'] for l in ocr['lines']]
        exact_lines = sum(1 for t in t_text if t in o_text)
        for writer in ('type3', 'glyphless', 'lib'):
            for mode in 'ABC':
                path = os.path.join(OUT, f'{name}_{writer}_{mode}.pdf')
                if not os.path.exists(path):
                    continue
                ok, pages = valid(path)
                clean, bad, info = no_metadata(path)
                same, got_n, want_n, got, want = pdf_text_ok(path, ocr)
                chars, pw, ph = pdf_chars(path)
                chars = to_picture(chars, pw, truth['width'])
                per = associate(truth, chars)
                errs, lines_used = [], 0
                sel = {j: dict(exact=0, missing=0, extra=0, wrong=0, total=0)
                       for j in (0.0, 0.25)}
                rng = random.Random(1)
                for tl, mine in zip(truth['lines'], per):
                    pairs, t_str, p_str = align_line(tl, mine)
                    if not pairs:
                        continue
                    lines_used += 1
                    aligned = {}
                    for (ti, along, equal) in pairs:
                        c = tl['chars'][ti]
                        centre = (c[1] + c[2]) / 2
                        if equal:
                            errs.append(abs(along - centre) / (c[2] - c[1]))
                            aligned[ti] = along
                    if t_str == p_str and any(ch.isdigit() for ch in t_str):
                        for j in sel:
                            r = simulate_selection(
                                tl, aligned, rng, j, 25, code_targets(tl))
                            for k in r:
                                sel[j][k] += r[k]
                rows.append(dict(
                    sheet=name, writer=writer, mode=mode, valid=ok, pages=pages,
                    clean=clean, has_info=info, text_equal=same, got=got_n, want=want_n,
                    err_mean=statistics.mean(errs) if errs else None,
                    err_median=statistics.median(errs) if errs else None,
                    err_p95=sorted(errs)[int(len(errs) * .95)] if errs else None,
                    err_max=max(errs) if errs else None,
                    ocr_exact_lines=exact_lines, lines=len(t_text),
                    sel0=sel[0.0], sel25=sel[0.25],
                    bytes=os.path.getsize(path)))
    json.dump(rows, open(os.path.join(OUT, 'analysis.json'), 'w'), indent=1)
    print(len(rows), 'rows')


main()
