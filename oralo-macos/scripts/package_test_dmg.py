#!/usr/bin/env python3
"""Package an existing universal, ad-hoc Oralo build for manual testing.

Install dmgbuild==1.6.7 in an isolated environment first. This helper never
builds/signs the app, accesses credentials, notarizes, uploads, or runs tests.
"""
import argparse
import hashlib
import json
import plistlib
import re
import subprocess
import tempfile
from pathlib import Path

import dmgbuild


def run(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    app = args.app.resolve(strict=True)
    output = args.output_dir.resolve()
    source = Path(__file__).resolve().parent / "installer"
    if app.name != "Oralo.app":
        parser.error("Expected the built Oralo.app")
    with (app / "Contents/Info.plist").open("rb") as handle:
        info = plistlib.load(handle)
    if info["CFBundleIdentifier"] != "com.ch563.oralo.mac.dev":
        parser.error("This helper is only for the local test identifier")
    version, build = info["CFBundleShortVersionString"], info["CFBundleVersion"]
    if not all(re.fullmatch(r"[0-9.]+", item) for item in [version, build]):
        parser.error("Version and build must be numeric")
    archs = run("/usr/bin/lipo", "-archs", str(app / "Contents/MacOS" / info["CFBundleExecutable"])).split()
    if set(archs) != {"arm64", "x86_64"}:
        parser.error("Build both arm64 and x86_64 before packaging")
    run("/usr/bin/codesign", "--verify", "--deep", "--strict", str(app))
    signature = run("/usr/bin/codesign", "--display", "--verbose=2", str(app))
    if "Signature=adhoc" not in signature:
        parser.error("Expected an explicit ad-hoc test signature; use the formal route for Developer ID")
    # Public artifacts must not embed the build machine's home-directory paths
    # or credentials. Keep dSYMs outside the app and strip Release debug symbols.
    private_patterns = [
        rb"/Users/[^/\s\x00]+/", rb"/home/[^/\s\x00]+/", rb"/private/var/folders/",
        rb"-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----",
        rb"github_pat_[A-Za-z0-9_]{20,}", rb"gh[pousr]_[A-Za-z0-9_]{20,}",
    ]
    for entry in app.rglob("*"):
        if entry.is_file():
            contents = entry.read_bytes()
            if any(re.search(pattern, contents) for pattern in private_patterns):
                parser.error(f"Private path or credential pattern found in {entry.relative_to(app)}; rebuild before publishing")
    output.mkdir(parents=True, exist_ok=True)
    dmg = output / f"Oralo-{version}-{build}-Universal-TEST.dmg"
    if dmg.exists():
        parser.error("Refusing to replace an existing DMG; choose a new output directory")
    artwork = output / "artwork"
    run("/usr/bin/swift", str(source / "render_dmg.swift"), str(artwork),
        str(app / "Contents/Resources/Oralo.icns"), f"{version} ({build})")
    settings = {
        "format": "UDZO", "compression_level": 9, "filesystem": "HFS+",
        "files": [str(app)], "symlinks": {"Applications": "/Applications"},
        "icon": str(app / "Contents/Resources/Oralo.icns"),
        "background": str(artwork / "background.png"),
        "window_rect": ((160, 100), (620, 440)),
        "default_view": "icon-view", "include_icon_view_settings": True,
        "include_list_view_settings": False, "arrange_by": None,
        "show_status_bar": False, "show_tab_view": False, "show_toolbar": False,
        "show_pathbar": False, "show_sidebar": False, "show_item_info": False,
        "show_icon_preview": False, "icon_size": 96, "text_size": 13,
        "label_pos": "bottom", "scroll_position": (0, 0),
        "hide_extensions": [],
        "icon_locations": {"Oralo.app": (164, 198), "Applications": (456, 198)},
        "grid_spacing": 80,
    }
    dmgbuild.build_dmg(str(dmg), "Oralo Test", settings=settings)
    run("/usr/bin/hdiutil", "verify", str(dmg))
    # Finder flags on a signed app can invalidate strict verification. Validate
    # the copy inside the finished DMG, not only the input build.
    with tempfile.TemporaryDirectory(prefix="oralo-dmg-check-") as folder:
        run("/usr/bin/hdiutil", "attach", "-readonly", "-nobrowse", "-noautoopen",
            "-mountpoint", folder, str(dmg))
        try:
            packaged = Path(folder) / "Oralo.app"
            run("/usr/bin/codesign", "--verify", "--deep", "--strict", str(packaged))
            original_binary = app / "Contents/MacOS" / info["CFBundleExecutable"]
            packaged_binary = packaged / "Contents/MacOS" / info["CFBundleExecutable"]
            if hashlib.sha256(original_binary.read_bytes()).digest() != hashlib.sha256(packaged_binary.read_bytes()).digest():
                raise RuntimeError("Packaged executable differs from the input build")
            visible = {entry.name for entry in Path(folder).iterdir() if not entry.name.startswith(".")}
            if visible != {"Oralo.app", "Applications"}:
                raise RuntimeError("Unexpected visible installer content")
            if (Path(folder) / "Applications").readlink() != Path("/Applications"):
                raise RuntimeError("Installer destination link is invalid")
        finally:
            run("/usr/bin/hdiutil", "detach", folder)
    checksum = hashlib.sha256(dmg.read_bytes()).hexdigest()
    (output / f"{dmg.name}.sha256").write_text(f"{checksum}  {dmg.name}\n")
    record = {"app": "Oralo", "version": version, "build": build,
              "bundleIdentifier": info["CFBundleIdentifier"], "architectures": sorted(archs),
              "minimumMacOS": info["LSMinimumSystemVersion"], "signing": "ad-hoc",
              "notarized": False, "automatedAppTestsRun": False,
              "diskImageVerified": True, "packagedAppSignatureVerified": True,
              "privatePathAndCredentialScanPassed": True,
              "filename": dmg.name, "bytes": dmg.stat().st_size, "sha256": checksum}
    (output / "package-info.json").write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(record, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
