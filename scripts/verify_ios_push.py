"""Check the exported IPA's signing, rather than only source entitlements."""
import glob
import plistlib
import subprocess
import tempfile
import zipfile
from pathlib import Path


def validate(info, entitlements, profile):
    bundle = info.get("CFBundleIdentifier")
    if bundle != "com.oto.tag":
        raise ValueError(f"Unexpected bundle identifier: {bundle}")
    allowed = profile.get("Entitlements", {})
    for name, values in (("signed app", entitlements), ("profile", allowed)):
        if values.get("aps-environment") != "production":
            raise ValueError(f"{name}: production Push Notifications entitlement missing")
    if entitlements.get("application-identifier") != allowed.get("application-identifier"):
        raise ValueError("App and provisioning profile application identifiers differ")
    if not entitlements.get("application-identifier", "").endswith("." + bundle):
        raise ValueError("Signing identifier does not match the app bundle")
    if "remote-notification" not in info.get("UIBackgroundModes", []):
        raise ValueError("remote-notification background mode missing")


def main():
    packages = glob.glob("build/ios/ipa/*.ipa")
    if len(packages) != 1:
        raise SystemExit("Expected exactly one exported IPA")
    with tempfile.TemporaryDirectory() as directory:
        with zipfile.ZipFile(packages[0]) as archive:
            archive.extractall(directory)
        apps = list(Path(directory).glob("Payload/*.app"))
        if len(apps) != 1:
            raise SystemExit("Expected exactly one main app")
        app = apps[0]
        info = plistlib.loads((app / "Info.plist").read_bytes())
        entitlements = plistlib.loads(subprocess.check_output(
            ["codesign", "-d", "--entitlements", ":-", str(app)],
            stderr=subprocess.DEVNULL))
        profile = plistlib.loads(subprocess.check_output(
            ["security", "cms", "-D", "-i", str(app / "embedded.mobileprovision")]))
        validate(info, entitlements, profile)
        print(f"iOS push signing verified: {info['CFBundleIdentifier']} "
              f"{info['CFBundleShortVersionString']} ({info['CFBundleVersion']})")


if __name__ == "__main__":
    main()
