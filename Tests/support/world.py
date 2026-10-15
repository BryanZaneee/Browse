"""Owned disposable Browse bundles. No production path is a cleanup target."""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]

class World:
    def __init__(self, name="test", checkout=ROOT):
        self.checkout = Path(checkout).resolve()
        name = name.lower()
        if not name or any(c not in "abcdefghijklmnopqrstuvwxyz0123456789-" for c in name):
            raise ValueError("world names contain lowercase letters, digits and hyphens")
        self.name = name
        self.tag = hashlib.sha256((str(self.checkout) + "\0" + name).encode()).hexdigest()[:24]
        self.root = Path(f"/tmp/browse-tests-{os.getuid()}") / self.tag
        self.app = self.root / "Browse.app"
        self.data = self.root / "data"
        self.socket = self.data / "bench.sock"
        self.bundle = "com.bryanzaneee.browse.test." + self.tag
        self.lease = None
        self.owner = {"root": str(self.root), "checkout": str(self.checkout), "world": name, "bundle": self.bundle}

    def __del__(self):
        lease = getattr(self, "lease", None)
        if lease is not None: os.close(lease)

    def lock(self):
        if self.lease is not None: return
        if self.root.parent.is_symlink(): raise RuntimeError("symlinked test root")
        self.root.parent.mkdir(mode=0o700, exist_ok=True)
        if self.root.parent.stat().st_uid != os.getuid(): raise RuntimeError("foreign test root")
        self.lease = os.open(str(self.root) + ".lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
        try: fcntl.flock(self.lease, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            os.close(self.lease); self.lease = None
            raise RuntimeError("another test runner owns this world")

    def verify(self):
        if self.root.is_symlink() or self.root.parent.is_symlink():
            raise RuntimeError("test world must not be a symlink")
        if self.root.exists():
            if any(path.is_symlink() for path in (self.data, self.app, self.root / "owner.json")):
                raise RuntimeError("symlinked world resource")
            if self.root.stat().st_uid != os.getuid() or json.loads((self.root / "owner.json").read_text()) != self.owner:
                raise RuntimeError("test world is not owned by this checkout")

    def pids(self):
        # comm is the executable path, without arguments; LaunchServices resolves /tmp.
        listing = subprocess.run(["ps", "-axo", "pid=,comm="], capture_output=True, text=True, check=True).stdout
        executable = (self.app / "Contents/MacOS/Browse").resolve()
        found = []
        for line in listing.splitlines():
            parts = line.strip().split(None, 1)
            if len(parts) == 2 and Path(parts[1]).resolve() == executable:
                found.append(int(parts[0]))
        return found

    def prepare(self):
        self.lock()
        self.verify()
        if self.pids():
            raise RuntimeError("world is already running")
        self.root.mkdir(parents=True, exist_ok=True, mode=0o700)
        os.chmod(self.root.parent, 0o700)
        (self.root / "owner.json").write_text(json.dumps(self.owner))
        self.data.mkdir(exist_ok=True, mode=0o700)
        source = self.checkout / "build" / ("intel/" if os.uname().machine == "x86_64" else "") / "Browse.app"
        if not source.is_dir():
            raise RuntimeError("Build first with ./build.sh debug")
        if self.app.exists(): shutil.rmtree(self.app)
        shutil.copytree(source, self.app, symlinks=True)
        plist = self.app / "Contents/Info.plist"
        info = plistlib.loads(plist.read_bytes())
        info.update(CFBundleIdentifier=self.bundle, BrowseTestRoot=str(self.root), BrowseTestWorld=self.name)
        # A disposable build never claims external links or the production updater identity.
        info.pop("CFBundleURLTypes", None)
        info.pop("CFBundleDocumentTypes", None)
        plist.write_bytes(plistlib.dumps(info))
        subprocess.run(["codesign", "--force", "--deep", "--sign", "-", str(self.app)], check=True, capture_output=True)

    def launch(self, hidden=True):
        self.lock()
        self.verify()
        if self.pids(): raise RuntimeError("world is already running")
        self.socket.unlink(missing_ok=True)
        subprocess.run(["open", "-n", *(["-g", "-j"] if hidden else []), str(self.app)], check=True)
        for _ in range(150):
            if (hidden and self.socket.exists()) or (not hidden and self.pids()): return
            time.sleep(.1)
        raise RuntimeError("test world did not become ready")

    def wipe(self):
        self.lock()
        self.verify()
        if not self.root.exists(): return
        if self.pids(): raise RuntimeError("quit this world's process before cleanup")
        # Entire namespaces belong to the copied bundle; never follow IDs from fixture data.
        home = Path.home()
        targets = [home / "Library" / directory / self.bundle for directory in ("WebKit", "Caches", "HTTPStorages")]
        targets += [home / "Library/HTTPStorages" / (self.bundle + ".binarycookies")]
        targets += [home / "Library/Saved Application State" / (self.bundle + ".savedState")]
        for target in targets:
            if target.parent.is_symlink() or target.is_symlink():
                raise RuntimeError("refusing symlinked cleanup target")
        subprocess.run(["defaults", "delete", self.bundle], capture_output=True)
        for target in targets:
            if target.is_dir(): shutil.rmtree(target)
            elif target.exists(): target.unlink()
        shutil.rmtree(self.root)

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["fresh", "again", "wipe", "info"])
    parser.add_argument("--world", default=os.environ.get("SEARCH_PROBE", "test"))
    parser.add_argument("--visible", action="store_true")
    args = parser.parse_args()
    world = World("test" if args.world in ("", "1") else args.world)
    if args.action == "info": print(json.dumps(world.owner | {"data": str(world.data), "socket": str(world.socket)}))
    elif args.action == "wipe": world.wipe()
    else:
        if args.action == "fresh": world.wipe()
        world.prepare()
        subprocess.run(["defaults", "write", world.bundle, "bench", "-bool", "false" if args.visible else "true"], check=True)
        world.launch(hidden=not args.visible)
