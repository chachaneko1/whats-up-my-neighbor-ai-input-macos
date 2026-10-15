"""Verify stable free code-signing identity, without Apple notarization."""
import hashlib
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile


def validate_signing(app: Path, expected_fingerprint: str, bundle_id="tw.panh.FreeVoiceType") -> None:
    if not re.fullmatch(r"[A-F0-9]{40}", expected_fingerprint):
        raise ValueError("Invalid pinned signing fingerprint")
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    if info["CFBundleIdentifier"] != bundle_id:
        raise ValueError("Bundle identity changed")
    requirement = f'identifier "{bundle_id}"'
    subprocess.run(["codesign", "--verify", "--deep", "--strict", "--test-requirement", "=" + requirement, str(app)], check=True)
    result = subprocess.run(["codesign", "-d", "-r-", str(app)], check=True, capture_output=True, text=True)
    if "designated => " + requirement not in result.stdout + result.stderr:
        raise ValueError("Installed designated requirement changed")
    with tempfile.TemporaryDirectory(prefix="neko-public-cert-") as directory:
        prefix = str(Path(directory) / "cert")
        subprocess.run(["codesign", "-d", "--extract-certificates=" + prefix, str(app)], check=True, capture_output=True)
        actual = hashlib.sha1(Path(prefix + "0").read_bytes()).hexdigest().upper()
        if actual != expected_fingerprint:
            raise ValueError("Release certificate differs from the pinned identity")


if __name__ == "__main__":
    validate_signing(Path(sys.argv[1]), sys.argv[2])
    print("Stable signing certificate, designated requirement and strict signature verified")
