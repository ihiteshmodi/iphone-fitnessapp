"""Reads an .ods spreadsheet with the standard library only (an .ods file is a zip with a content.xml)."""
import zipfile
import xml.etree.ElementTree as ET

NS = {
    "office": "urn:oasis:names:tc:opendocument:xmlns:office:1.0",
    "table": "urn:oasis:names:tc:opendocument:xmlns:table:1.0",
    "text": "urn:oasis:names:tc:opendocument:xmlns:text:1.0",
}
TABLE = "{%s}" % NS["table"]
OFFICE = "{%s}" % NS["office"]
NUMERIC_TYPES = {"float", "percentage", "currency"}
MAX_EMPTY_REPEAT = 200


def _cell_text(cell):
    return "\n".join("".join(p.itertext()) for p in cell.findall("text:p", NS))


def _cell_value(cell):
    vtype = cell.get(OFFICE + "value-type")
    raw = cell.get(OFFICE + "value")
    text = _cell_text(cell).strip()
    if vtype in NUMERIC_TYPES and raw is not None:
        return float(raw)
    return text or None


def load(path):
    """Returns {sheet name: list of rows, each row a list of cell values (float, str or None)}."""
    with zipfile.ZipFile(path) as archive:
        root = ET.fromstring(archive.read("content.xml"))
    sheets = {}
    for table in root.iter(TABLE + "table"):
        rows = []
        for row in table.findall(TABLE + "table-row"):
            cells = []
            for cell in row:
                if cell.tag not in (TABLE + "table-cell", TABLE + "covered-table-cell"):
                    continue
                value = _cell_value(cell)
                repeat = int(cell.get(TABLE + "number-columns-repeated", "1"))
                cells.extend([value] * (min(repeat, MAX_EMPTY_REPEAT) if value is None else repeat))
            repeat_rows = int(row.get(TABLE + "number-rows-repeated", "1"))
            blank = all(v is None for v in cells)
            rows.extend([cells] * (1 if blank and repeat_rows > 1 else repeat_rows))
        while rows and all(v is None for v in rows[-1]):
            rows.pop()
        sheets[table.get(TABLE + "name")] = rows
    return sheets
