#!/usr/bin/env python3
"""Exercise the production clipboard seam without a browsing profile."""
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import uuid

root = Path(__file__).resolve().parents[2]
identity = "com.bryanzaneee.browse.clipboard-test." + uuid.uuid4().hex
with tempfile.TemporaryDirectory(prefix="browse-clipboard-") as temporary:
    app = Path(temporary) / "Clipboard.app"
    binary = app / "Contents/MacOS/Clipboard"
    binary.parent.mkdir(parents=True)
    (app / "Contents/Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": identity, "CFBundleExecutable": "Clipboard", "CFBundlePackageType": "APPL"}))
    subprocess.run(["swiftc", str(root / "Sources/Search/TestPasteboard.swift"), str(Path(__file__).with_name("main.swift")), "-o", str(binary)], check=True)
    subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True, capture_output=True)
    try:
        subprocess.run([str(binary)], check=True, timeout=45)
    finally:
        # These exact namespaces were created solely by this helper's random bundle ID.
        for directory in ("WebKit", "Caches", "HTTPStorages"):
            path = Path.home() / "Library" / directory / identity
            if path.is_dir(): shutil.rmtree(path)
        (Path.home() / "Library/HTTPStorages" / (identity + ".binarycookies")).unlink(missing_ok=True)
        subprocess.run(["defaults", "delete", identity], capture_output=True)
