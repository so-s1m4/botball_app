#!/usr/bin/env python3
"""Import ECER 2026 PDF tables using Poppler's layout-preserving text extraction."""
import csv
import hashlib
import json
import re
import subprocess
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / 'data' / 'parts'
BASE = 'https://ecer.eraa.at/documents/2026/botball/parts-lists/'
TABLES = [('electronics', 'Electronics Kit'), ('metal', 'KIPR Metal Parts'), ('lego', 'Lego Parts')]
HEADINGS = {'SENSORS', 'ANALOG', 'DIGITAL', 'MOTION', 'CONTROLLER', 'MISC.', 'KIPR Metal', 'Screws, Nuts, and Standoffs', 'AXLES', 'Connectors', 'Liftarms Thick', 'Pins', 'Gears', 'Liftarms Thin', 'Plates / Tiles', 'Bricks', 'Wheels'}


def parse(text, group, source):
    rows, pending, part_number = [], [], None
    for page_number, page in enumerate(text.split('\f'), 1):
        for line in page.splitlines():
            line = line.strip()
            if not line or line in HEADINGS or line.startswith('Description'):
                continue
            if line == '(not useable on robot)':
                rows[-1]['usable_on_robot'] = False
                continue
            if group == 'lego':
                if re.fullmatch(r'\d+', line):
                    if pending and part_number is None:
                        part_number = line
                        continue
                    if not pending:
                        raise ValueError(f'Missing LEGO description/part number on page {page_number}')
                    rows.append(dict(id='lego_' + part_number, name=' '.join(pending), part_number=part_number, quantity=int(line), group=group, source=source, source_page=page_number, usable_on_robot=True))
                    pending, part_number = [], None
                else:
                    match = re.search(r'(?:^|\s{2,})([0-9]+[a-z]?|x[0-9]+)$', line)
                    if match:
                        part_number = match[1]
                        line = line[:match.start()].strip()
                    if line:
                        pending.append(line)
    if pending:
        raise ValueError(f'Unparsed text: {pending}')
    return rows


def parse_bbox(pdf, group):
    xml = subprocess.check_output(['pdftotext', '-bbox', str(pdf), '-'])
    rows = []
    for page_number, page in enumerate(ET.fromstring(xml).findall('.//{*}page'), 1):
        words = [(w.text, float(w.attrib['xMin']), float(w.attrib['yMin'])) for w in page.findall('{*}word')]
        quantities = [w for w in words if w[0].isdigit() and (420 < w[1] < 440 if group == 'electronics' else 390 < w[1] < 420) and not (page_number == 1 and w[2] < 100)]
        descriptions = [[] for _ in quantities]
        for word in words:
            text, x, y = word
            if x >= (280 if group == 'electronics' else 250) or (page_number == 1 and y < 100):
                continue
            same_line = ' '.join(w[0] for w in words if abs(w[2] - y) < 2)
            if same_line in HEADINGS:
                continue
            nearest = min(range(len(quantities)), key=lambda i: abs(quantities[i][2] - y))
            descriptions[nearest].append(word)
        for qty, description in zip(quantities, descriptions):
            # PDF word order follows description lines, including lines below the quantity.
            name = ' '.join(w[0] for w in description)
            usable = '(not useable on robot)' not in name
            name = name.replace('(not useable on robot)', '').strip()
            row = dict(id=f'{group}_{len(rows)+1:03}', name=name, quantity=int(qty[0]), group=group, source=group, source_page=page_number, usable_on_robot=usable)
            nearest_flags = [w[0] for w in words if w[0] in ('Yes', 'No') and abs(w[2] - qty[2]) < 3]
            if nearest_flags:
                row['bendable'] = nearest_flags[0] == 'Yes'
            if 'Camera' in name:
                row['notes'] = 'PDF shows alternative camera images separated by “or”; quantity 1 is shared. Model not specified in text.'
            rows.append(row)
    return rows

def main():
    (ROOT / 'sources').mkdir(parents=True, exist_ok=True)
    parts, sources = [], []
    for group, title in TABLES:
        filename = '2026 ' + title + '.pdf'
        url = BASE + urllib.parse.quote(filename)
        pdf = ROOT / 'sources' / filename
        if not pdf.exists():
            urllib.request.urlretrieve(url, pdf)
        txt = pdf.with_suffix('.txt')
        subprocess.run(['pdftotext', '-layout', str(pdf), str(txt)], check=True)
        rows = parse(txt.read_text(), group, group) if group == 'lego' else parse_bbox(pdf, group)
        sources.append(dict(id=group, url=url, local_file='sources/' + filename, sha256=hashlib.sha256(pdf.read_bytes()).hexdigest()))
        parts.extend(rows)
        print(f'{group}: {len(rows)} entries, {sum(r["quantity"] for r in rows)} items')
    assert len({r['id'] for r in parts}) == len(parts)
    assert all(r['quantity'] > 0 for r in parts)
    catalog = dict(schema_version=1, kit='Botball 2026', inventory_scope='Standard kit listed by ECER; personal inventory not verified', source_page='https://ecer.eraa.at/archive/ecer-2026/', sources=sources, parts=parts)
    (ROOT / 'botball_2026.json').write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + '\n')
    with (ROOT / 'botball_2026.csv').open('w', newline='') as file:
        writer = csv.DictWriter(file, fieldnames=['id', 'group', 'name', 'part_number', 'quantity', 'usable_on_robot', 'bendable', 'source', 'source_page', 'notes'], extrasaction='ignore')
        writer.writeheader()
        writer.writerows(parts)


if __name__ == '__main__':
    main()
