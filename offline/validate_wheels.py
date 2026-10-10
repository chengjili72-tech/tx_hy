"""Inspect local wheels before installation; run using target Python in build."""
import email
import hashlib
import json
from pathlib import Path
import sys
import zipfile

from packaging.tags import sys_tags
from packaging.utils import canonicalize_name, parse_wheel_filename
from packaging.version import Version


def inspect_wheels(root):
    supported = set(sys_tags())
    records = {}
    for package in ('torch', 'torch-npu', 'triton-ascend', 'triton'):
        files = sorted((root / package).glob('*.whl'))
        if package == 'triton' and not files:
            continue
        if len(files) != 1:
            raise ValueError(f'{package}: expected exactly one wheel, got {len(files)}')
        path = files[0]
        filename_name, filename_version, _, tags = parse_wheel_filename(path.name)
        if not supported.intersection(tags):
            raise ValueError(f'{path.name}: incompatible with this Python/platform')
        with zipfile.ZipFile(path) as archive:
            names = [n for n in archive.namelist() if n.endswith('.dist-info/METADATA')]
            if len(names) != 1:
                raise ValueError(f'{path.name}: expected one METADATA')
            metadata = email.message_from_bytes(archive.read(names[0]))
        name = canonicalize_name(metadata['Name'])
        version = Version(metadata['Version'])
        if name != package or filename_name != name or filename_version != version:
            raise ValueError(f'{path.name}: wrong package or inconsistent metadata')
        if package in ('torch', 'torch-npu') and version.release != (2, 10, 0):
            raise ValueError(f'{package}: requires 2.10.0 series, got {version}')
        digest = hashlib.sha256()
        with path.open('rb') as file:
            for block in iter(lambda: file.read(8 * 1024 * 1024), b''):
                digest.update(block)
        records[package] = {'version': str(version), 'filename': path.name,
                            'sha256': digest.hexdigest()}
    return records


def main():
    root, report, constraints = map(Path, sys.argv[1:])
    records = inspect_wheels(root)
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text(json.dumps(records, indent=2) + '\n')
    with constraints.open('a') as file:
        for name, data in records.items():
            file.write(f"{name}==={data['version']}\n")
    print(json.dumps(records, indent=2))


if __name__ == '__main__':
    main()
