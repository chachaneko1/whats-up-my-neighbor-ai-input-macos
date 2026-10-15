"""Temporarily expose a release keychain to codesign; restore the exact list."""
import json
from pathlib import Path
import shlex
import subprocess
import sys


def add(keychain: str, snapshot: Path) -> None:
    original = shlex.split(subprocess.check_output(["security", "list-keychains", "-d", "user"], text=True))
    with snapshot.open("x") as output:
        json.dump(original, output)
    snapshot.chmod(0o600)
    subprocess.run(["security", "list-keychains", "-d", "user", "-s", keychain, *original], check=True)


def restore(snapshot: Path) -> None:
    if not snapshot.exists():
        return
    original = json.loads(snapshot.read_text())
    if not isinstance(original, list) or not all(isinstance(path, str) for path in original):
        raise ValueError("Invalid keychain search snapshot")
    subprocess.run(["security", "list-keychains", "-d", "user", "-s", *original], check=True)
    snapshot.unlink()


if __name__ == "__main__":
    if sys.argv[1] == "add":
        add(sys.argv[2], Path(sys.argv[3]))
    elif sys.argv[1] == "restore":
        restore(Path(sys.argv[2]))
    else:
        raise ValueError("Use add or restore")
