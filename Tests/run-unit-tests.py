#!/usr/bin/env python3
"""Run swift test with an owned persistent WebKit store and clean it after exit."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import uuid

if any(arg == "--parallel" or arg.startswith("--parallel=") for arg in sys.argv[1:]):
    sys.exit("The isolated XCTest runner is serial; --parallel would share its owned store.")

identity = str(uuid.uuid4())
root = Path(tempfile.gettempdir()) / ("browse-unit-" + identity)
assert not root.exists()
environment = os.environ | {"BROWSE_UNIT_ID": identity}
try:
    result = subprocess.run(["swift", "test", *sys.argv[1:]], env=environment)
finally:
    marker = root / "webkit-owner.json"
    if marker.exists():
        if root.is_symlink() or marker.is_symlink(): raise RuntimeError("symlinked unit ownership")
        owner = json.loads(marker.read_text())
        if owner["id"] != identity or not owner["bundle"] or any(c not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-" for c in owner["bundle"]):
            raise RuntimeError("unexpected unit store ownership")
        if subprocess.run(["ps", "-p", owner["pid"], "-o", "pid="], capture_output=True).returncode == 0:
            raise RuntimeError("unit process still running")
        store = Path.home() / "Library/WebKit" / owner["bundle"] / "WebsiteDataStore" / identity
        if any(path.is_symlink() for path in (store, store.parent, store.parent.parent)):
            raise RuntimeError("symlinked unit store")
        if store.exists(): shutil.rmtree(store)
    if root.exists(): shutil.rmtree(root)
sys.exit(result.returncode)
