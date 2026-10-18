"""Offline release regressions. Uses disposable keys/files, never user credentials."""
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest
import sys
from unittest.mock import patch
sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[1]


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


metadata = load_module("release_metadata", ROOT / "scripts/release_metadata.py")
validator = load_module("release_validator", ROOT / "scripts/validate-release.py")
signing = load_module("signing_validator", ROOT / "scripts/validate-signing.py")
temporary_keychain = load_module("temporary_keychain", ROOT / "scripts/temporary-keychain.py")


class ReleaseContractTests(unittest.TestCase):
    def test_publication_timeout_reconciles_server_state_without_masking_failure(self):
        # Exercise the actual workflow shell, including macOS's Bash behavior.
        parsed = subprocess.check_output([
            'ruby', '-r', 'yaml', '-r', 'json', '-e',
            'data = YAML.load_file(ARGV[0]); puts JSON.generate(data["jobs"]["release"]["steps"].map { |step| step["run"] }.compact)',
            str(ROOT / '.github/workflows/release-macos.yml'),
        ], text=True)
        steps = json.loads(parsed)
        for step in steps:
            subprocess.run(['bash', '-n'], input=step, text=True, check=True)
        publish = next(step for step in steps if 'if ! gh release edit' in step)
        reconcile = publish[publish.index('if ! gh release edit'):]
        with tempfile.TemporaryDirectory(prefix='neko-publish-response-') as directory:
            gh = Path(directory) / 'gh'
            gh.write_text('''#!/usr/bin/env python3
import os, sys
if sys.argv[1:3] == ['release', 'edit']: sys.exit(int(os.environ['EDIT_RESULT']))
if sys.argv[1:3] == ['release', 'view']: print(os.environ['PUBLISHED_STATE'])
elif sys.argv[1] == 'api': print(os.environ['LATEST_TAG'])
else: sys.exit(99)
''')
            gh.chmod(0o700)
            cases = [(0, 'false', 'old', True), (1, 'true', 'v1.3.2', True),
                     (1, 'false', 'v1.3.2', False), (1, 'true', 'v1.3.1', False)]
            for edit, published, latest, accepted in cases:
                with self.subTest(edit=edit, published=published, latest=latest):
                    environment = dict(os.environ, PATH=directory + ':' + os.environ['PATH'],
                                       RELEASE_TAG='v1.3.2', GITHUB_REPOSITORY='example/repo',
                                       EDIT_RESULT=str(edit), PUBLISHED_STATE=published, LATEST_TAG=latest)
                    result = subprocess.run(['bash', '-e', '-c', reconcile], env=environment, capture_output=True)
                    self.assertEqual(result.returncode == 0, accepted)

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
        credentials = (ROOT / "Sources/GroqVoiceInput/KeychainStore.swift").read_text()
        settings = (ROOT / "Sources/GroqVoiceInput/SettingsStore.swift").read_text()
        for value in ["tw.panh.FreeVoiceType.groq", "api-key"]:
            self.assertIn('"' + value + '"', credentials)
        for value in ["recordingHotKeyCode", "recordingHotKeyModifiers", "alternateHotKeyCode", "alternateHotKeyModifiers", "relayHotKeyCode", "relayHotKeyModifiers", "clipboardHotKeyCode", "clipboardHotKeyModifiers"]:
            self.assertIn('"' + value + '"', settings)

    def test_release_uses_source_version_and_build(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Info.plist"
            info = {"CFBundleShortVersionString": "1.3.2", "CFBundleVersion": "1004"}
            path.write_bytes(plistlib.dumps(info))
            self.assertEqual(metadata.source_metadata(path), ("1.3.2", "1004"))
            self.assertEqual(metadata.source_metadata(path, "v1.3.2"), ("1.3.2", "1004"))
            with self.assertRaises(ValueError):
                metadata.source_metadata(path, "v1.3.1")
            for build in ["0", "01004", "10000", "1004.1", "1004\nX=Y", 1004]:
                with self.subTest(build=build), self.assertRaises(ValueError):
                    path.write_bytes(plistlib.dumps(dict(info, CFBundleVersion=build)))
                    metadata.source_metadata(path)

    def test_release_build_must_exceed_published_feed(self):
        with tempfile.TemporaryDirectory() as directory:
            feed = Path(directory) / "appcast.xml"
            feed.write_text('<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><sparkle:version>1002</sparkle:version></item><item><sparkle:version>1003</sparkle:version></item></channel></rss>')
            metadata.validate_build_progression("1004", feed)
            for build in ["1002", "1003", "0", "01004", "10000"]:
                with self.subTest(build=build), self.assertRaises(ValueError):
                    metadata.validate_build_progression(build, feed)
            feed.write_text('<rss><channel/></rss>')
            with self.assertRaises(ValueError):
                metadata.validate_build_progression("1004", feed)

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

    def test_free_release_requires_stable_certificate_not_paid_membership(self):
        environment = {"PATH": os.environ["PATH"], "RELEASE_VERSION": "1.3.0", "RELEASE_BUILD": "1001"}
        result = subprocess.run([str(ROOT / "scripts/release-macos.sh")], env=environment, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Missing release credential/config: MACOS_CERTIFICATE_P12_BASE64", result.stderr)
        self.assertNotIn("Developer ID", result.stderr)
        self.assertNotIn("APPLE_NOTARY", result.stderr)

    def test_temporary_keychain_search_list_is_restored_exactly(self):
        with tempfile.TemporaryDirectory(prefix="neko-keychain-snapshot-") as directory:
            snapshot = Path(directory) / "search.json"
            original = ['/Users/test/Library/Keychains/login.keychain-db', '/private/test with spaces/other.keychain-db']
            with patch.object(temporary_keychain.subprocess, "check_output", return_value='    "' + original[0] + '"\n    "' + original[1] + '"\n'), patch.object(temporary_keychain.subprocess, "run") as run:
                temporary_keychain.add("/private/release.keychain-db", snapshot)
                self.assertEqual(snapshot.stat().st_mode & 0o777, 0o600)
                self.assertEqual(run.call_args.args[0][-3:], ["/private/release.keychain-db", *original])
                temporary_keychain.restore(snapshot)
                self.assertEqual(run.call_args.args[0], ["security", "list-keychains", "-d", "user", "-s", *original])
                self.assertFalse(snapshot.exists())
                temporary_keychain.restore(snapshot)  # Cleanup is idempotent.

    def test_installer_reuses_location_and_preserves_profile(self):
        with tempfile.TemporaryDirectory(prefix="neko-install-test-") as directory:
            base = Path(directory)
            profile = base / "profile"
            package = base / "package"
            package.mkdir()
            installer = package / "安裝.command"
            shutil.copy(ROOT / "Packaging/安裝.command", installer)
            old_app = profile / "Library/Application Support/AI語音輸入/AI語音輸入.app"
            source_app = package / "AI語音輸入.app"
            for app, marker in [(old_app, b"old"), (source_app, b"new")]:
                (app / "Contents/MacOS").mkdir(parents=True)
                (app / "Contents/Resources").mkdir()
                shutil.copy("/usr/bin/true", app / "Contents/MacOS/FreeVoiceType")
                (app / "Contents/Info.plist").write_bytes((ROOT / "Resources/Info.plist").read_bytes())
                (app / "Contents/Resources/version-marker").write_bytes(marker)
                subprocess.run(["codesign", "--force", "--sign", "-", "--requirements", '=designated => identifier "tw.panh.FreeVoiceType"', str(app)], check=True, capture_output=True)
            preserved = {
                "Library/Application Support/tw.panh.FreeVoiceType/cat.config.json": '{"version":1,"reply":"保留我的貓🐈"}'.encode(),
                "Library/Application Support/tw.panh.FreeVoiceType/custom-cat.png": b"test-image-snapshot",
                "Library/Preferences/tw.panh.FreeVoiceType.plist": plistlib.dumps({"recordingHotKeyCode": 97, "recordingHotKeyModifiers": 768}),
                "Library/Keychains/login.keychain-db": b"synthetic-keychain-sentinel-not-a-real-keychain",
                "Library/Application Support/com.apple.TCC/TCC.db": b"synthetic-permission-sentinel-not-a-real-TCC-db",
                "Library/LaunchAgents/tw.panh.FreeVoiceType.plist": plistlib.dumps({"Label": "tw.panh.FreeVoiceType", "ProgramArguments": ["/usr/bin/open", "-gj", str(old_app)], "RunAtLoad": False}),
            }
            for relative, data in preserved.items():
                path = profile / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(data)
            environment = dict(os.environ, NEKO_INSTALL_TEST_PROFILE=str(profile))
            result = subprocess.run(["zsh", str(installer)], env=environment, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((old_app / "Contents/Resources/version-marker").read_bytes(), b"new")
            self.assertFalse((profile / "Applications/AI語音輸入.app").exists())
            backups = list(old_app.parent.glob(".neighbor-update.*/Previous.app/Contents/Resources/version-marker"))
            self.assertEqual(len(backups), 1)
            self.assertEqual(backups[0].read_bytes(), b"old")
            for relative, data in preserved.items():
                self.assertEqual((profile / relative).read_bytes(), data, relative)
            # A corrupted replacement must fail before touching the working app.
            (source_app / "Contents/Resources/version-marker").write_bytes(b"tampered")
            result = subprocess.run(["zsh", str(installer)], env=environment, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual((old_app / "Contents/Resources/version-marker").read_bytes(), b"new")
            for relative, data in preserved.items():
                self.assertEqual((profile / relative).read_bytes(), data, relative)

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
            subprocess.run(["codesign", "--force", "--sign", "-", "--requirements", '=designated => identifier "tw.panh.FreeVoiceType"', str(app)], check=True, stdout=subprocess.DEVNULL)
            # An ad-hoc CI bundle is not eligible to masquerade as a stable
            # certificate-signed release, even with a matching requirement.
            with self.assertRaises((ValueError, FileNotFoundError, subprocess.CalledProcessError)):
                signing.validate_signing(app, "0" * 40)
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
            # Repository migration must not invalidate historical signed assets,
            # or allow old URLs in newly built packages without explicit opt-in.
            info["SUAllowsAutomaticUpdates"] = False
            info["SUFeedURL"] = validator.LEGACY_REPOSITORY + "/releases/latest/download/appcast.xml"
            (contents / "Info.plist").write_bytes(plistlib.dumps(info))
            archive.unlink()
            feed.unlink()
            subprocess.run(["codesign", "--force", "--sign", "-", "--requirements", '=designated => identifier "tw.panh.FreeVoiceType"', str(app)], check=True, stdout=subprocess.DEVNULL)
            subprocess.run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(app), str(archive)], check=True)
            subprocess.run([str(tools / "generate_appcast"), "--ed-key-file", str(key), "--maximum-deltas", "0", "--download-url-prefix", validator.LEGACY_REPOSITORY + "/releases/download/v" + info["CFBundleShortVersionString"] + "/", str(update_dir)], check=True, capture_output=True, timeout=30)
            with self.assertRaisesRegex(ValueError, "Unexpected update repository"):
                validator.validate_release(app, feed, archive)
            validator.validate_release(app, feed, archive, allow_legacy_repository=True)
            validator.verify_signatures(app, feed, archive)
            # Explicit compatibility never accepts an unrelated repository.
            info["SUFeedURL"] = "https://github.com/unrelated/repository/releases/latest/download/appcast.xml"
            (contents / "Info.plist").write_bytes(plistlib.dumps(info))
            with self.assertRaisesRegex(ValueError, "Unexpected update repository"):
                validator.validate_release(app, feed, archive, allow_legacy_repository=True)


if __name__ == "__main__":
    unittest.main()
