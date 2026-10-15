"""Offline release regressions. Uses disposable keys/files, never user credentials."""
import importlib.util
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest
import sys
sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[1]


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


metadata = load_module("release_metadata", ROOT / "scripts/release_metadata.py")
validator = load_module("release_validator", ROOT / "scripts/validate-release.py")


class ReleaseContractTests(unittest.TestCase):
    def test_metadata(self):
        self.assertEqual(metadata.release_metadata("v1.2.3", "7"), ("1.2.3", "1007"))
        self.assertLess(int(metadata.release_metadata("v1.2.3", "7")[1]), int(metadata.release_metadata("v1.2.4", "8")[1]))
        for tag in ["v1.2.3-beta", "v01.2.3", "../v1.2.3", "v1.2.3\nX=Y", "v1.2.3$(id)", "v10000.2.3", "v1.100.0"]:
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                metadata.release_metadata(tag, "7")
        for run in ["0", "-1", "1\nX=Y", "9000", ""]:
            with self.subTest(run=run), self.assertRaises(ValueError):
                metadata.release_metadata("v1.2.3", run)

    def test_existing_identity_contract(self):
        info = plistlib.loads((ROOT / "Resources/Info.plist").read_bytes())
        self.assertEqual(info["CFBundleIdentifier"], "tw.panh.FreeVoiceType")
        self.assertFalse(info["SUAutomaticallyUpdate"])
        self.assertFalse(info["SUAllowsAutomaticUpdates"])
        self.assertFalse(info["SUEnableSystemProfiling"])
        main = (ROOT / "Sources/GroqVoiceInput/main.swift").read_text()
        for constant in [
            'keychainService = "tw.panh.FreeVoiceType.groq"',
            'keychainAccount = "api-key"',
            'hotKeyCodeDefaultsKey = "recordingHotKeyCode"',
            'hotKeyModifiersDefaultsKey = "recordingHotKeyModifiers"',
            'alternateHotKeyCodeDefaultsKey = "alternateHotKeyCode"',
            'alternateHotKeyModifiersDefaultsKey = "alternateHotKeyModifiers"',
            'relayHotKeyCodeDefaultsKey = "relayHotKeyCode"',
            'relayHotKeyModifiersDefaultsKey = "relayHotKeyModifiers"',
        ]:
            self.assertIn(constant, main)

    def test_release_cannot_downgrade_published_versions(self):
        metadata.validate_progression("v1.3.0", ["v1.2.9", "windows-preview"])
        metadata.validate_progression("v1.3.0", [])
        for published in ["v1.3.0", "v1.3.1", "v2.0.0"]:
            with self.subTest(published=published), self.assertRaises(ValueError):
                metadata.validate_progression("v1.3.0", [published])

    def test_unsigned_release_is_blocked_before_keychain_import(self):
        environment = {"PATH": os.environ["PATH"], "HOME": os.environ["HOME"], "GITHUB_ACTIONS": "true"}
        result = subprocess.run([str(ROOT / "scripts/release-macos.sh")], env=environment, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Missing release credential/config: RELEASE_VERSION", result.stderr)

    def test_real_signed_feed_archive_tampering_and_layout(self):
        tools = ROOT / "build/Sparkle-2.10.0/bin"
        self.assertTrue(tools.is_dir(), "Build/fetch Sparkle before the offline suite")
        with tempfile.TemporaryDirectory(prefix="neko-update-test-") as directory:
            base = Path(directory)
            # Test-only key material never enters Keychain, logs or artifacts.
            generator = base / "test-key.swift"
            generator.write_text('''import Foundation
import CryptoKit
let k = Curve25519.Signing.PrivateKey()
try k.rawRepresentation.base64EncodedString().write(toFile: CommandLine.arguments[1], atomically: true, encoding: .utf8)
try k.publicKey.rawRepresentation.base64EncodedString().write(toFile: CommandLine.arguments[2], atomically: true, encoding: .utf8)
''')
            key = base / "test.key"
            public = base / "test.pub"
            subprocess.run(["swift", str(generator), str(key), str(public)], check=True, capture_output=True)
            key.chmod(0o600)
            app = base / "AI語音輸入.app"
            contents = app / "Contents"
            (contents / "MacOS").mkdir(parents=True)
            (contents / "Resources").mkdir()
            (contents / "Frameworks").mkdir(parents=True)
            subprocess.run(["ditto", str(ROOT / "build/Sparkle-2.10.0/Sparkle.framework"), str(contents / "Frameworks/Sparkle.framework")], check=True)
            shutil.copy("/usr/bin/true", contents / "MacOS/FreeVoiceType")
            shutil.copy(ROOT / "cat.config.json", contents / "Resources/cat.config.json")
            info = plistlib.loads((ROOT / "Resources/Info.plist").read_bytes())
            info["SUPublicEDKey"] = public.read_text()
            (contents / "Info.plist").write_bytes(plistlib.dumps(info))
            subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True, stdout=subprocess.DEVNULL)
            update_dir = base / "archives"
            update_dir.mkdir()
            archive = update_dir / f'Neighbor-macOS-{info["CFBundleShortVersionString"]}.zip'
            subprocess.run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(app), str(archive)], check=True)
            subprocess.run([str(tools / "generate_appcast"), "--ed-key-file", str(key), "--maximum-deltas", "0", "--download-url-prefix", validator.REPOSITORY + "/releases/download/v" + info["CFBundleShortVersionString"] + "/", str(update_dir)], check=True, capture_output=True, timeout=30)
            feed = update_dir / "appcast.xml"
            validator.validate_release(app, feed, archive)
            validator.verify_signatures(app, feed, archive)
            original_archive = archive.read_bytes()
            archive.write_bytes(original_archive + b"tampered")
            with self.assertRaises(subprocess.CalledProcessError):
                validator.verify_signatures(app, feed, archive)
            archive.write_bytes(original_archive)
            original_feed = feed.read_bytes()
            feed.write_bytes(original_feed.replace(b"<title>", b"<TITLE>", 1).replace(b"</title>", b"</TITLE>", 1))
            with self.assertRaises(subprocess.CalledProcessError):
                validator.verify_signatures(app, feed, archive)
            feed.write_bytes(original_feed)
            info["SUAllowsAutomaticUpdates"] = True
            (contents / "Info.plist").write_bytes(plistlib.dumps(info))
            with self.assertRaises(ValueError):
                validator.validate_release(app, feed, archive)


if __name__ == "__main__":
    unittest.main()
