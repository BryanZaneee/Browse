#!/usr/bin/env python3
"""Text replacements in pages, checked in a hidden probe.

Build first (`./build.sh`), then run `python3 Tests/text_replacement.py`.

WebKit keeps its text checker's switches in standard defaults. The shared
World launcher gives this probe its own bundle identity and removes its
settings, WebKit folders and copied bundle after the test.

What is typed is the shortcut macOS puts in every Mac's Text Replacements,
"omw" → "On my way!", read here and never written: a Mac without it skips
that check. Nothing here makes, shows or brings forward a window.
"""

import json
import os
import socket
import sqlite3
import subprocess
import sys
import threading
import time
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "Tests/support"))
from world import World
world = World("text-replacement")
HOME = os.path.expanduser("~")
SUITE, SOCK = world.bundle, str(world.socket)

PAGE = b"""<!doctype html><title>typing</title>
<input id=i autocomplete=off><textarea id=t></textarea>"""
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200); self.send_header("Content-Type", "text/html")
        self.send_header("Content-Length", str(len(PAGE))); self.end_headers(); self.wfile.write(PAGE)
    def log_message(self, *a): pass
srv = None
for port in range(8820, 8826):
    try: srv = ThreadingHTTPServer(("127.0.0.1", port), H); break
    except OSError: continue
if not srv: sys.exit("no free port in 8820–8825")
threading.Thread(target=srv.serve_forever, daemon=True).start()
BASE = f"http://127.0.0.1:{srv.server_port}"

def omw():
    """The Mac's own "omw", if it still has it — read only."""
    db = f"{HOME}/Library/KeyboardServices/TextReplacements.db"
    try:
        with sqlite3.connect(f"file:{db}?mode=ro", uri=True) as c:
            row = c.execute("select ZPHRASE from ZTEXTREPLACEMENTENTRY where ZSHORTCUT='omw' and (ZWASDELETED is null or ZWASDELETED=0)").fetchone()
            return row[0] if row else None
    except sqlite3.Error:
        return None

def ours(): return [str(pid) for pid in world.pids()]
def wipe(): world.wipe()

def cmd(req):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as c:
        c.settimeout(30); c.connect(SOCK); c.sendall(json.dumps(req).encode() + b"\n")
        data = b""
        while True:
            ch = c.recv(65536)
            if not ch: break
            data += ch
    return json.loads(data.split(b"\n", 1)[0] or b"{}")

def ev(id, js): return cmd({"do": "eval", "id": id, "js": js}).get("value")

class T:
    passed = failed = 0
    def ok(self, name, cond, extra=""):
        if cond: self.passed += 1; print(f"  ok   {name}")
        else: self.failed += 1; print(f"  FAIL {name} {extra}")

def typed(t, tab, field, text):
    ev(tab, f"(() => {{ const f = document.getElementById('{field}'); f.value = ''; f.focus(); return document.activeElement.id }})()")
    cmd({"do": "key", "id": tab, "text": text})
    time.sleep(1)
    return ev(tab, f"document.getElementById('{field}').value")

def launch():
    """The copy, hidden, never brought forward → a bench tab on the page."""
    world.launch()
    time.sleep(2)
    tab = cmd({"do": "open", "url": f"{BASE}/"})["id"]
    cmd({"do": "wait", "id": tab, "seconds": 10})
    time.sleep(0.5)
    return tab

def quit():
    try: cmd({"do": "quit"})
    except Exception: pass
    for _ in range(30):
        if not ours(): break
        time.sleep(0.2)
    for p in ours(): subprocess.run(["kill", p])
    time.sleep(0.5)

def main():
    if ours(): sys.exit("a copy from this run is already running")
    wipe()
    world.prepare()
    for k in ["bench", "welcomed"]: subprocess.run(["defaults", "write", SUITE, k, "-bool", "true"])
    t = T()
    try:
        tab = launch()
        state = cmd({"do": "textcheck", "id": tab})
        print("textcheck:", json.dumps(state))
        mac = state.get("mac", {})
        page = state.get("page", {})
        if "error" not in state:
            t.ok(f"text replacement in pages follows the Mac ({mac.get('replacement')})", page.get("replacement") == mac.get("replacement"), str(state))
            for name in ("quotes", "dashes"):
                t.ok(f"smart {name} start off (the Mac: {mac.get(name)})", page.get(name) is False and state["kept"][name] is None, str(state))
            menu = state.get("menu", [])
            titles = [m["title"] for m in menu]
            t.ok("Edit › Substitutions lists its items", titles == ["Show Substitutions", "Smart Quotes", "Smart Dashes", "Text Replacement"], str(titles))
            ticks = {m["title"]: m["on"] for m in menu}
            t.ok("its ticks are the page's", ticks.get("Text Replacement") == page.get("replacement")
                 and ticks.get("Smart Quotes") == page.get("quotes") and ticks.get("Smart Dashes") == page.get("dashes"), str(menu))

        phrase = omw()
        if phrase is None:
            print("  skip typing: this Mac has no \"omw\" text replacement")
        else:
            for field in ("i", "t"):
                value = typed(t, tab, field, "omw ")
                expect = mac.get("replacement", True)
                t.ok(f"typing omw in the {'input' if field == 'i' else 'textarea'} matches the read-only system replacement",
                     value == (phrase + " " if expect else "omw "))

        if "error" not in state:
            # The menu's own action: off, typed, back on, typed.
            before = state["page"]["replacement"]
            after = cmd({"do": "textcheck", "id": tab, "toggle": "replacement"})
            t.ok("Text Replacement switches off from the menu", after["page"]["replacement"] == (not before), str(after))
            ticks = {m["title"]: m["on"] for m in after.get("menu", [])}
            t.ok("and the menu's tick follows", ticks.get("Text Replacement") == (not before), str(after.get("menu")))
            if phrase is not None:
                value = typed(t, tab, "t", "omw ")
                t.ok("typing omw with it off matches the expected text", value == ("omw " if before else phrase + " "))
            for name in ("quotes", "dashes"):
                on = cmd({"do": "textcheck", "id": tab, "toggle": name})
                ticks = {m["title"]: m["on"] for m in on.get("menu", [])}
                t.ok(f"smart {name} turn on from the menu, tick and all", on["page"][name] is True
                     and ticks.get(f"Smart {name.capitalize()}") is True, str(on))
            # Choices made in the menu are kept, and outrank where each starts.
            quit()
            tab = launch()
            again = cmd({"do": "textcheck", "id": tab})
            t.ok("text replacement switched off stays off after a relaunch", again["page"]["replacement"] == (not before)
                 and again["kept"]["replacement"] == (not before), str(again))
            for name in ("quotes", "dashes"):
                t.ok(f"smart {name} turned on stay on after a relaunch", again["page"][name] is True
                     and again["kept"][name] is True, str(again))
            back = cmd({"do": "textcheck", "id": tab, "toggle": "replacement"})
            t.ok("text replacement back on", back["page"]["replacement"] == before, str(back))
            for name in ("quotes", "dashes"):
                off = cmd({"do": "textcheck", "id": tab, "toggle": name})
                t.ok(f"smart {name} back off", off["page"][name] is False, str(off))
    finally:
        quit()
        wipe()
        srv.shutdown()
    print(f"{t.passed} passed, {t.failed} failed")
    sys.exit(1 if t.failed else 0)

main()
