"""Prevent later online installs from replacing the supplied core wheel versions."""
import json
from importlib.metadata import version
from pathlib import Path
import sys

assert sys.version_info[:3] == (3, 13, 16), sys.version
records = json.loads(Path('/opt/tx_hy/build-info/offline-wheels.json').read_text())
for name, data in records.items():
    actual = version(name)
    if actual != data['version']:
        raise SystemExit(f'{name}: expected {data["version"]}, found {actual}')
    print(f'{name}: {actual} (matches supplied wheel)')
