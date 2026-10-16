"""Validate release input before it reaches filenames or plist commands."""
import re
from pathlib import Path
import plistlib
import xml.etree.ElementTree as ET
from typing import Optional


def release_metadata(tag: str, run_number: str) -> tuple[str, str]:
    match = re.fullmatch(r"v([1-9][0-9]{0,3})\.(0|[1-9][0-9]?)\.(0|[1-9][0-9]?)", tag)
    if not match:
        raise ValueError("Use a stable Apple-compatible tag such as v1.2.0")
    if not re.fullmatch(r"[1-9][0-9]*", run_number):
        raise ValueError("Invalid CI run number")
    build = int(run_number) + 1000
    if build > 9999:
        raise ValueError("Build numbering needs an explicit migration before 9999")
    return ".".join(match.groups()), str(build)


def validate_progression(tag: str, published_tags: list[str]) -> None:
    candidate = tuple(map(int, release_metadata(tag, "1")[0].split(".")))
    for published in published_tags:
        try:
            previous = tuple(map(int, release_metadata(published, "1")[0].split(".")))
        except ValueError:
            continue  # Other products may use a distinct tag prefix.
        if candidate <= previous:
            raise ValueError(f"Release {tag} must be newer than published {published}")


def source_metadata(plist: Path, tag: Optional[str] = None) -> tuple[str, str]:
    info = plistlib.loads(plist.read_bytes())
    version = info.get("CFBundleShortVersionString")
    build = info.get("CFBundleVersion")
    if not isinstance(version, str) or not isinstance(build, str):
        raise ValueError("Source version and build must be strings")
    release_metadata("v" + version, "1")
    if tag is not None and tag != "v" + version:
        raise ValueError("Release tag must match Resources/Info.plist")
    if not re.fullmatch(r"[1-9][0-9]{0,3}", build):
        raise ValueError("Source build must be a positive integer below 10000")
    return version, build


def validate_build_progression(build: str, feed: Path) -> None:
    if not re.fullmatch(r"[1-9][0-9]{0,3}", build):
        raise ValueError("Invalid candidate build")
    namespace = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
    versions = ET.fromstring(feed.read_bytes()).findall("channel/item/" + namespace + "version")
    if not versions:
        raise ValueError("Published feed has no build number")
    for previous in versions:
        value = previous.text or ""
        if not re.fullmatch(r"[1-9][0-9]{0,3}", value) or int(build) <= int(value):
            raise ValueError("Release build must exceed every published feed build")


if __name__ == "__main__":
    import sys
    if sys.argv[1] == "--check-progression":
        validate_progression(sys.argv[2], Path(sys.argv[3]).read_text().splitlines())
    elif sys.argv[1] == "--check-build":
        validate_build_progression(sys.argv[2], Path(sys.argv[3]))
    elif sys.argv[1] == "--from-plist":
        version, build = source_metadata(Path(sys.argv[2]), sys.argv[3] if len(sys.argv) > 3 else None)
        print(f"RELEASE_VERSION={version}\nRELEASE_BUILD={build}")
    else:
        version, build = release_metadata(*sys.argv[1:])
        print(f"RELEASE_VERSION={version}\nRELEASE_BUILD={build}")
