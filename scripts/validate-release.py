"""Fail closed on mismatched release metadata, layout, URLs or missing signatures."""
import base64
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
import zipfile

SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
REPOSITORY = "https://github.com/yuipan0611/groq-ai-voice-input-macos"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def validate_release(app: Path, feed: Path, archive: Path) -> None:
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    require(info['CFBundleIdentifier'] == 'tw.panh.FreeVoiceType', 'Bundle identity changed')
    require(info['SUFeedURL'] == REPOSITORY + '/releases/latest/download/appcast.xml', 'Release contract validation failed')
    require(info['SUAllowsAutomaticUpdates'] is False, 'Silent updates must be disabled')
    require(info['SUAutomaticallyUpdate'] is False, 'Release contract validation failed')
    require(info['SURequireSignedFeed'] is True, 'Release contract validation failed')
    require(info['SUVerifyUpdateBeforeExtraction'] is True, 'Release contract validation failed')
    require(len(base64.b64decode(info['SUPublicEDKey'], validate=True)) == 32, 'Release contract validation failed')
    require((app / 'Contents/Frameworks/Sparkle.framework').is_dir(), 'Release contract validation failed')
    require((app / 'Contents/Resources/cat.config.json').is_file(), 'Release contract validation failed')
    data = feed.read_bytes()
    signature = re.search(rb"<!-- sparkle-signatures:\nedSignature: ([A-Za-z0-9+/=]+)\nlength: ([0-9]+)\n-->\s*$", data)
    require(signature is not None, 'Appcast signature missing')
    require(int(signature[2]) == signature.start(), 'Feed signature length mismatch')
    root = ET.fromstring(data)
    items = root.findall("channel/item")
    require(len(items) == 1, 'One release per atomic publication')
    item = items[0]
    require(item.findtext(SPARKLE + 'version') == info['CFBundleVersion'], 'Release contract validation failed')
    require(item.findtext(SPARKLE + 'shortVersionString') == info['CFBundleShortVersionString'], 'Release contract validation failed')
    enclosure = item.find("enclosure")
    require(enclosure is not None, 'Release contract validation failed')
    require(enclosure.attrib['url'] == REPOSITORY + '/releases/download/v' + info['CFBundleShortVersionString'] + '/' + archive.name, 'Release contract validation failed')
    require(int(enclosure.attrib['length']) == archive.stat().st_size, 'Release contract validation failed')
    require(len(base64.b64decode(enclosure.attrib[SPARKLE + 'edSignature'], validate=True)) == 64, 'Release contract validation failed')
    with zipfile.ZipFile(archive) as zipped:
        # Apple's ditto emits UTF-8 names without the ZIP UTF-8 flag. Decode
        # those names explicitly; zipfile otherwise interprets them as CP437.
        entries = {
            entry.filename if entry.flag_bits & 0x800 else entry.filename.encode("cp437").decode("utf-8"): entry
            for entry in zipped.infolist()
        }
        names = [name for name in entries if not name.startswith("__MACOSX/")]
        require(names and all((name.startswith(app.name + '/') for name in names)), 'Update must contain only the app')
        bundled = plistlib.loads(zipped.read(entries[app.name + "/Contents/Info.plist"]))
        require(bundled == info, 'Archive does not match the validated bundle')


def verify_signatures(app: Path, feed: Path, archive: Path) -> None:
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    key = info["SUPublicEDKey"]
    verifier = str(Path(__file__).with_name("verify-ed25519.swift"))
    enclosure = ET.fromstring(feed.read_bytes()).find("channel/item/enclosure")
    signature = re.search(rb"<!-- sparkle-signatures:\nedSignature: ([A-Za-z0-9+/=]+)\nlength: ([0-9]+)\n-->\s*$", feed.read_bytes())
    subprocess.run(["swift", verifier, key, enclosure.attrib[SPARKLE + "edSignature"], str(archive), str(archive.stat().st_size)], check=True)
    subprocess.run(["swift", verifier, key, signature[1].decode(), str(feed), signature[2].decode()], check=True)


if __name__ == "__main__":
    validate_release(*(Path(arg) for arg in sys.argv[1:]))
    verify_signatures(*(Path(arg) for arg in sys.argv[1:]))
    print("Release metadata, approval policy, app-only archive and Ed25519 signatures verified")
