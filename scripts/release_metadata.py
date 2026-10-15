"""Validate release input before it reaches filenames or plist commands."""
import re


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


if __name__ == "__main__":
    import sys
    if sys.argv[1] == "--check-progression":
        from pathlib import Path
        validate_progression(sys.argv[2], Path(sys.argv[3]).read_text().splitlines())
    else:
        version, build = release_metadata(*sys.argv[1:])
        print(f"RELEASE_VERSION={version}\nRELEASE_BUILD={build}")
