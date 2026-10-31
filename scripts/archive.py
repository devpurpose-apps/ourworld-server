"""Cold snapshots only. No third-party Python packages required."""
import os
import gzip
from pathlib import Path, PurePosixPath
import shutil
import sys
import tarfile
import tempfile


def members(archive):
    entries = archive.getmembers()
    names = set()
    for entry in entries:
        path = PurePosixPath(entry.name)
        if (path.is_absolute() or '..' in path.parts or '\\' in entry.name
                or ':' in entry.name or not path.parts
                or (path.parts[0] != 'data' and entry.name != '.env')
                or not (entry.isfile() or entry.isdir()) or entry.name in names
                or (entry.name == '.env' and not entry.isfile())
                or (entry.name == 'data' and not entry.isdir())):
            raise ValueError(f'Unsafe archive member: {entry.name!r}')
        names.add(entry.name)
    files = {entry.name for entry in entries if entry.isfile()}
    if not {'.env', 'data/server.properties'} <= files:
        raise ValueError('Not a project backup: .env or data/server.properties missing')
    if not any(n.startswith('data/worlds/') and n.endswith('/level.dat') for n in files):
        raise ValueError('No world level.dat in backup')
    return entries


def check(path):
    with tarfile.open(path, 'r:gz') as archive:
        members(archive)
    # Consume the gzip trailer too, before restore stops BDS.
    with gzip.open(path, 'rb') as stream, open(os.devnull, 'wb') as sink:
        shutil.copyfileobj(stream, sink)


def create(root, destination):
    root, destination = Path(root), Path(destination)
    partial = destination.with_suffix(destination.suffix + '.partial')
    opened = False
    try:
        with tarfile.open(partial, 'x:gz', dereference=False) as archive:
            opened = True
            archive.add(root / '.env', arcname='.env')
            archive.add(root / 'data', arcname='data')
        check(partial)
        if destination.exists():
            raise FileExistsError(destination)
        partial.rename(destination)
        destination.chmod(0o600)
    finally:
        if opened:
            partial.unlink(missing_ok=True)


def restore(root, source):
    root = Path(root)
    if (root / 'data').is_symlink() or (root / '.env').is_symlink():
        raise ValueError('data and .env must not be symlinks')
    with tempfile.TemporaryDirectory(prefix='.restore-', dir=root) as temporary:
        stage = Path(temporary)
        with tarfile.open(source, 'r:gz') as archive:
            entries = members(archive)
            # Ubuntu 24.04 Python 3.12 data filter adds a second extraction boundary.
            archive.extractall(stage, members=entries, filter='data')
        (stage / '.env').chmod(0o600)
        rollback = Path(tempfile.mkdtemp(prefix='pre-restore-', dir=root / 'backups'))
        moved, installed = [], []
        try:
            for name in ('data', '.env'):
                if (root / name).exists():
                    (root / name).rename(rollback / name)
                    moved.append(name)
                (stage / name).rename(root / name)
                installed.append(name)
        except BaseException:
            for name in reversed(installed):
                (root / name).rename(stage / name)
            for name in reversed(moved):
                (rollback / name).rename(root / name)
            raise
        print(f'Previous data/config kept at: {rollback}')


if __name__ == '__main__':
    os.umask(0o077)
    try:
        action, *args = sys.argv[1:]
        {'create': create, 'check': check, 'restore': restore}[action](*args)
    except (OSError, EOFError, ValueError, KeyError, TypeError, tarfile.TarError) as error:
        sys.exit(f'Archive error: {error}')
