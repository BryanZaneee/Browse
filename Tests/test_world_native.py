#!/usr/bin/env python3
"""Two owned worlds, local fixtures only. Build first: ./build.sh debug."""
import json
from pathlib import Path
import socket
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
sys.path.insert(0, str(Path(__file__).parent / "support"))
from world import World

class Site(BaseHTTPRequestHandler):
    def do_GET(self):
        body = b"<!doctype html><title>Isolation fixture</title><textarea>synthetic clipboard</textarea>"
        self.send_response(200); self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)
    def log_message(self, *args): pass

def ask(world, **request):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.settimeout(30); client.connect(str(world.socket)); client.sendall(json.dumps(request).encode() + b"\n")
        data = b""
        while b"\n" not in data:
            part = client.recv(65536)
            if not part: break
            data += part
    result = json.loads(data)
    assert "error" not in result, result
    return result

def stop(world):
    if world.pids():
        ask(world, do="quit")
        for _ in range(100):
            if not world.pids(): break
            time.sleep(.1)
        assert not world.pids(), "owned process did not quit"

def start(world):
    world.prepare()
    for key in ("bench", "welcomed"):
        subprocess.run(["defaults", "write", world.bundle, key, "-bool", "true"], check=True)
    world.launch()

def page(world, url):
    tab = ask(world, do="open", url=url)["id"]
    ask(world, do="wait", id=tab)
    return tab

def evaluate(world, tab, js):
    return ask(world, do="eval", id=tab, js=js)["value"]

def production_metadata():
    # Names and metadata only; never read page data or credential contents.
    home = Path.home()
    roots = [home / "Library/Application Support" / n for n in ("Browse", "Search")]
    roots += [home / "Library/WebKit" / n for n in ("com.bryanzaneee.browse", "com.officecommun.search")]
    roots += [home / "Library/Preferences" / (n + ".plist") for n in ("com.bryanzaneee.browse", "com.officecommun.search")]
    result = {}
    for root in roots:
        for path in ([root] + list(root.rglob("*")) if root.is_dir() else [root]):
            if path.exists():
                st = path.stat(); result[str(path)] = (st.st_size, st.st_mtime_ns)
    return result

def check_direct_launch_guard():
    world = World("guard-acceptance")
    world.wipe(); world.prepare()
    foreign = world.root / "foreign-fixture"
    foreign.mkdir(); (foreign / "sentinel").write_text("unchanged")
    world.data.rmdir(); world.data.symlink_to(foreign)
    try:
        result = subprocess.run([str(world.app / "Contents/MacOS/Browse")], capture_output=True, timeout=20)
        assert result.returncode != 0 and b"owned test bundle" in result.stderr
        assert [p.name for p in foreign.iterdir()] == ["sentinel"]
        assert (foreign / "sentinel").read_text() == "unchanged"
    finally:
        world.data.unlink(); world.data.mkdir(); world.wipe()


def main():
    def clipboard_count():
        return int(subprocess.run(["swift", "-e", "import AppKit; print(NSPasteboard.general.changeCount)"], check=True, capture_output=True, text=True).stdout.strip())
    check_direct_launch_guard()
    clipboard_before = clipboard_count()
    before = production_metadata()
    worlds = [World("acceptance-a"), World("acceptance-b")]
    site = ThreadingHTTPServer(("127.0.0.1", 0), Site)
    threading.Thread(target=site.serve_forever, daemon=True).start()
    url = f"http://127.0.0.1:{site.server_port}/"
    try:
        for world in worlds:
            world.wipe(); start(world)
        a, b = worlds
        ta, tb = page(a, url), page(b, url)
        assert evaluate(a, ta, "document.cookie = 'world=A; max-age=3600'; localStorage.world = 'A'; localStorage.world") == "A"
        assert evaluate(b, tb, "document.cookie + ':' + (localStorage.world || '')") == ":"
        assert evaluate(b, tb, "document.cookie = 'world=B; max-age=3600'; localStorage.world = 'B'; localStorage.world") == "B"
        assert evaluate(a, ta, "document.cookie") == "world=A"
        for world, secret in ((a, "synthetic-A"), (b, "synthetic-B")):
            fixture = world.data / "passwords.csv"
            fixture.write_text("url,username,password\nhttps://isolation.example.test,fixture," + secret + "\n")
            result = ask(world, do="import-file", path=str(fixture))
            assert result["kept"] == 1, result
        extension = a.root / "extension-fixture"
        extension.mkdir()
        (extension / "manifest.json").write_text(json.dumps({"manifest_version": 3, "name": "Isolation fixture", "version": "1.0", "permissions": ["storage", "clipboardWrite"]}))
        (extension / "page.html").write_text("<!doctype html><title>Extension fixture</title><body>synthetic</body>")
        extension_ids = []
        for world, value in ((a, "A"), (b, "B")):
            ask(world, do="ext-folder", path=str(extension), yes=True)
            for _ in range(100):
                installed = ask(world, do="extensions")["extensions"]
                if installed and installed[0]["loaded"]: break
                time.sleep(.1)
            assert installed and installed[0]["loaded"], "extension failed to load"
            extension_id = installed[0]["id"]
            extension_ids.append(extension_id)
            tab = ask(world, do="ext-page", id=extension_id, path="page.html")["id"]
            ask(world, do="wait", id=tab)
            evaluate(world, tab, "chrome.storage.local.set({world: '" + value + "'}); true")
            evaluate(world, tab, "navigator.clipboard.writeText('synthetic extension clipboard').then(() => document.body.textContent='copied'); true")
            for _ in range(50):
                if evaluate(world, tab, "document.body.textContent") == "copied": break
                time.sleep(.1)
            assert evaluate(world, tab, "document.body.textContent") == "copied"
        assert extension_ids[0] == extension_ids[1], "same extension identity required"
        try: a.wipe(); raise AssertionError("wiped a live world")
        except RuntimeError: pass
        for world in worlds: stop(world)
        for world in worlds: start(world)
        ta, tb = page(a, url), page(b, url)
        assert evaluate(a, ta, "document.cookie + ':' + localStorage.world") == "world=A:A"
        assert evaluate(b, tb, "document.cookie + ':' + localStorage.world") == "world=B:B"
        for world, extension_id, expected in ((a, extension_ids[0], "A"), (b, extension_ids[1], "B")):
            tab = ask(world, do="ext-page", id=extension_id, path="page.html")["id"]
            ask(world, do="wait", id=tab)
            evaluate(world, tab, "chrome.storage.local.get('world').then(x => document.body.textContent=x.world); true")
            for _ in range(50):
                if evaluate(world, tab, "document.body.textContent") == expected: break
                time.sleep(.1)
            assert evaluate(world, tab, "document.body.textContent") == expected
        stop(a); a.wipe()
        assert evaluate(b, tb, "document.cookie + ':' + localStorage.world") == "world=B:B"
        tab = ask(b, do="ext-page", id=extension_ids[1], path="page.html")["id"]
        ask(b, do="wait", id=tab)
        evaluate(b, tab, "chrome.storage.local.get('world').then(x => document.body.textContent=x.world); true")
        for _ in range(50):
            if evaluate(b, tab, "document.body.textContent") == "B": break
            time.sleep(.1)
        assert evaluate(b, tab, "document.body.textContent") == "B"
        assert clipboard_before == clipboard_count(), "system clipboard changeCount changed"
        after = production_metadata()
        changed = [path for path in before.keys() | after.keys() if before.get(path) != after.get(path)]
        if changed:
            # Report only owned application categories, never domain names or file contents.
            categories = sorted({"/".join(Path(path).relative_to(Path.home() / "Library").parts[:2]) for path in changed})
            raise AssertionError("production metadata changed in " + str(categories))
        print("PASS two simultaneous worlds, credentials, cookie/extension-storage relaunch, live-wipe refusal, independent cleanup, production metadata and system clipboard unchanged")
    finally:
        for world in worlds:
            stop(world); world.wipe()
        site.shutdown()

if __name__ == "__main__": main()
