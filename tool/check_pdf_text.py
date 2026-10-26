"""Checks the text layer of the PDFs the Phase 3 integration test pulled.

    python tool/check_pdf_text.py build/pdf_it

Needs PyMuPDF (`pip install pymupdf`), outside the repo's dependencies on
purpose: it is a check tool for the person running the test, not part of the
app. `pdftotext` (poppler) is used as a second reader when it is installed.

The pages are the invented documents of
`integration_test/support/synthetic_pages.dart` (Greek receipt, Latin with
accents), drawn 1240 px wide with 36 px letters, 68.4 px per line, so the
expected place of every line on the PDF page is known. For each PDF it prints
numbers only:

  * pages, size, and whether it opens in PyMuPDF and in pdftotext;
  * how many of the key words are found by an exact search (Greek accents
    and Latin accents included) and by a text extraction;
  * how many of the found words lie on the line where they are printed.

Nothing here is a real document; no text of a document is ever printed except
the invented key words.
"""
import os
import re
import shutil
import subprocess
import sys
import unicodedata

import pymupdf

GREEK = [
    'ΠΑΡΑΔΕΙΓΜΑ', 'Δοκιμής', 'Αθήνα', '123456789', '000482', '12/03/2026',
    'Γάλα', 'Ψωμί', 'Ελαιόλαδο', 'Ευχαριστούμε', 'Total', '45,90', 'EUR',
    'info@example.com',
]
# (line index, word) for the position check of the Greek receipt.
GREEK_LINES = {
    'ΠΑΡΑΔΕΙΓΜΑ': 0, 'Δοκιμής': 1, 'Αθήνα': 1, '123456789': 2, '000482': 3,
    '12/03/2026': 4, 'Γάλα': 5, 'Ψωμί': 6, 'Ελαιόλαδο': 7, 'Ευχαριστούμε': 8,
    'Total': 9, '45,90': 9, 'EUR': 9, 'info@example.com': 10,
}
LATIN = [
    'Müller', 'Straße', 'Größe', 'Übung', 'Café', 'crème', 'brûlée',
    'française', 'Año', 'niño', 'señor', 'Città', 'perché', 'così', 'più',
    'Informação', 'coração', 'não', '20260312', '128.40',
]
LATIN_LINES = {
    'Müller': 0, 'Straße': 0, 'Größe': 0, 'Übung': 0, 'Café': 1, 'crème': 1,
    'brûlée': 1, 'française': 1, 'Año': 2, 'niño': 2, 'señor': 2, 'Città': 3,
    'perché': 3, 'così': 3, 'più': 3, 'Informação': 4, 'coração': 4, 'não': 4,
    '20260312': 5, '128.40': 5,
}

# file -> kind per page. 'g' Greek receipt, 'l' Latin, '-' no text expected,
# '?' text expected but not checked word by word (the Latin page of the
# 3-page files is read with the GREEK pack on purpose: accents come out wrong,
# ADR-011).
EXPECTED = {
    'flow_1page.pdf': 'g',
    'flow_3pages.pdf': 'g?g',
    'engine_greek.pdf': 'g',
    'engine_latin.pdf': 'l',
    'engine_exif6.pdf': 'g',
    'engine_3pages.pdf': 'g?g',
    'engine_bigphoto.pdf': '?',
    'engine_timeout.pdf': '-',
}

# Geometry of renderDocument: 1240 px wide, font 36, line height 36 * 1.9.
PAGE_PX_WIDTH = 1240
LINE_PX = 36 * 1.9
FIRST_LINE_PX = 36


def norm(s):
    return unicodedata.normalize('NFC', s)


def band(page, line):
    """Vertical band (points) where printed line [line] lies."""
    k = page.rect.width / PAGE_PX_WIDTH
    top = (FIRST_LINE_PX + line * LINE_PX) * k
    return top - 0.15 * LINE_PX * k, top + 1.15 * LINE_PX * k


def check_page(page, kind, label):
    words = GREEK if kind == 'g' else LATIN
    lines = GREEK_LINES if kind == 'g' else LATIN_LINES
    text = norm(page.get_text('text'))
    flat = re.sub(r'\s+', ' ', text)
    in_text = sum(1 for w in words if norm(w) in flat)
    searched = 0
    placed = 0
    for w in words:
        hits = page.search_for(w)
        if hits:
            searched += 1
            lo, hi = band(page, lines[w])
            if any(lo <= (r.y0 + r.y1) / 2 <= hi for r in hits):
                placed += 1
    print(f'  {label}: extract {in_text}/{len(words)}, '
          f'search {searched}/{len(words)}, on the right line {placed}/{len(words)}')
    return in_text, searched, placed, len(words)


def pdftotext_text(path):
    exe = shutil.which('pdftotext')
    if not exe:
        return None
    out = subprocess.run([exe, '-enc', 'UTF-8', path, '-'], capture_output=True)
    return out.stdout.decode('utf-8', errors='replace')


def main():
    folder = sys.argv[1] if len(sys.argv) > 1 else 'build/pdf_it'
    failures = 0
    for name in sorted(os.listdir(folder)):
        if not name.endswith('.pdf'):
            continue
        path = os.path.join(folder, name)
        doc = pymupdf.open(path)
        images = sum(len(p.get_images()) for p in doc)
        print(f'{name}: {os.path.getsize(path)} bytes, {doc.page_count} pages, '
              f'{images} pictures, metadata {dict((k, v) for k, v in doc.metadata.items() if v)}')
        pdftotext = pdftotext_text(path)
        kinds = EXPECTED.get(name)
        if kinds is None:
            print('  (no expectation for this file)')
            continue
        if len(kinds) == 1 and doc.page_count > 1:
            kinds = kinds * doc.page_count
        if len(kinds) != doc.page_count:
            print(f'  FAIL: expected {len(kinds)} pages')
            failures += 1
            continue
        if images != doc.page_count:
            print('  FAIL: not one picture per page')
            failures += 1
        for i, (page, kind) in enumerate(zip(doc, kinds), 1):
            label = f'page {i}'
            if kind == '-':
                got = page.get_text('text').strip()
                print(f'  {label}: text characters {len(got)} (expected none)')
                if got:
                    failures += 1
            elif kind == '?':
                got = page.get_text('text').strip()
                print(f'  {label}: text characters {len(got)}')
                if not got:
                    failures += 1
            else:
                found, searched, placed, total = check_page(page, kind, label)
                # Recall at the level the OCR achieved on the emulator.
                if found < total * 0.9 or searched < total * 0.85:
                    failures += 1
                    print('  FAIL: too few words found')
                if placed < searched * 0.9:
                    failures += 1
                    print('  FAIL: words are not where they are printed')
        if pdftotext is not None:
            words = GREEK + LATIN
            n = sum(1 for w in words if norm(w) in norm(pdftotext))
            print(f'  pdftotext: {len(pdftotext.strip())} characters, '
                  f'{n} key words found')
    print('FAILURES' if failures else 'ALL OK', failures)
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
