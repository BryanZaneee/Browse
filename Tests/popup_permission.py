#!/usr/bin/env python3
"""Site popup permission through native WebKit in an isolated hidden Search.

Local synthetic pages only. SEARCH_TEST_APP can name an already-built bundle
for runtime checks on older macOS versions, without compiling against their SDK.
"""
import os
import sys
import time
from http.server import BaseHTTPRequestHandler
from pathlib import Path
from urllib.parse import urlparse

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv

sv.use("popup-permission")
sv.APP = os.environ.get("SEARCH_TEST_APP", sv.APP)
posts = []
hits = []


class H(BaseHTTPRequestHandler):
    def do_GET(self):
        path = urlparse(self.path).path
        hits.append(path)
        if path == "/auto":
            body = "<script>setTimeout(()=>window.open('/opened-auto'),300)</script>"
        elif path == "/post":
            body = """<form id="form" method="post" target="_blank" rel="opener" action="/opened-post">
            <input name="assertion" value="fake-test-only"></form>
            <button id="go" onclick="setTimeout(()=>document.getElementById('form').submit(),300)">Sign in</button>"""
        elif path == "/blank":
            body = """<button id="go" onclick="const w=window.open('','_blank');
            window.wasBlocked=!w;if(w){w.document.write('<title>Written popup</title><body>fake-test-only</body>');w.document.close();}">Open</button>"""
        elif path == "/click":
            body = "<button id='go' onclick=\"window.blocked=window.open('/opened-click')===null\">Play</button>"
        elif path == "/third":
            body = f"<iframe src='http://localhost:{sv.srv.server_port}/ad'></iframe>"
        elif path == "/third-click":
            body = f"<iframe style='width:400px;height:200px' src='http://localhost:{sv.srv.server_port}/ad-click'></iframe>"
        elif path == "/ad-click":
            body = "<button style='width:100vw;height:100vh' onclick=\"window.open('/opened-ad-click')\">Open</button>"
        elif path == "/ad":
            body = "<script>setTimeout(()=>window.open('/opened-ad'),300)</script>"
        else:
            body = f"<title>{path}</title><body>local fixture {path}</body>"
        self.send(body)

    def do_POST(self):
        posts.append(self.rfile.read(int(self.headers.get("Content-Length", 0))).decode())
        hits.append(urlparse(self.path).path)
        self.send("<title>POST popup</title><body>fake-test-only</body>")

    def send(self, body):
        data = ("<!doctype html><meta charset='utf-8'>" + body).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *args):
        pass


sv.srv.RequestHandlerClass = H


def tabs():
    return sv.cmd({"do": "tabs"})["tabs"]


def state(tab):
    return sv.cmd({"do": "popups", "id": tab})


def until(condition, seconds=12):
    end = time.time() + seconds
    while time.time() < end:
        if condition():
            return True
        time.sleep(0.1)
    return False


def answer(tab, allow, keep=True):
    assert until(lambda: state(tab)["asking"]), state(tab)
    time.sleep(0.6)  # The same accidental-click guard the visible card uses.
    return sv.cmd({"do": "popups", "id": tab, "action": "once" if not keep else "yes" if allow else "no"})


def reset():
    sv.cmd({"do": "popups", "action": "remove", "site": "127.0.0.1"})


def opened(path):
    return [tab for tab in tabs() if urlparse(tab["url"]).path == path]


def tap(tab):
    sv.cmd({"do": "tap", "id": tab, "selector": "#go"})


def main():
    t = sv.T()
    try:
        sv.setup(); sv.launch()
        page = sv.page("auto")
        t.ok("unsolicited popup asks on its own site", until(lambda: state(page)["asking"]))
        t.ok("no popup or destination request before consent", not opened("/opened-auto") and "/opened-auto" not in hits)
        time.sleep(6)
        answer(page, True)
        t.ok("Allow resumes the pending popup after more than five seconds", until(lambda: len(opened("/opened-auto")) == 1))
        made = opened("/opened-auto")[0]
        t.ok("the original opener is preserved", sv.ev(made["id"], "window.opener !== null") is True)
        t.ok("allow choice is saved", state(page)["allowed"] == ["127.0.0.1"])

        reset()
        page = sv.page("post"); tap(page)
        t.ok("delayed POST asks", until(lambda: state(page)["asking"]))
        t.ok("POST is not sent before consent", posts == [])
        answer(page, True)
        t.ok("Allow preserves the actual POST body", until(lambda: posts == ["assertion=fake-test-only"]))
        t.ok("POST keeps its requested opener", sv.ev(opened("/opened-post")[0]["id"], "window.opener !== null") is True)

        reset()
        page = sv.page("blank"); tap(page)
        t.ok("blank popup asks", until(lambda: state(page)["asking"]))
        before = len(tabs())
        answer(page, True)
        t.ok("Allow creates exactly the requested blank popup", until(lambda: len(tabs()) == before + 1))
        made = next(tab for tab in tabs() if tab["active"])
        t.ok("opener can fill the original blank window", until(lambda: sv.ev(made["id"], "document.body.innerText") == "fake-test-only"))

        reset()
        page = sv.page("click"); before = len(tabs()); tap(page)
        answer(page, True, keep=False)
        t.ok("Allow this time opens the pending popup immediately", until(lambda: len(tabs()) == before + 1))
        t.ok("Allow this time saves no site choice", state(page)["allowed"] == [] and state(page)["denied"] == [])
        sv.sp("select", id=page); tap(page)
        t.ok("the next popup asks again after Allow this time", until(lambda: state(page)["asking"]))
        answer(page, False)

        reset()
        page = sv.page("click"); before = len(tabs()); tap(page)
        t.ok("a real click does not bypass the site question", until(lambda: state(page)["asking"]) and len(tabs()) == before)
        answer(page, False)
        t.ok("Don't allow returns null without opening", until(lambda: sv.ev(page, "window.blocked") is True) and len(tabs()) == before)
        t.ok("denial is saved", state(page)["denied"] == ["127.0.0.1"])
        tap(page); time.sleep(0.5)
        t.ok("denied site cannot repeatedly prompt", not state(page)["pending"] and len(tabs()) == before)

        reset()
        page = sv.page("auto")
        t.ok("another unknown request asks", until(lambda: state(page)["asking"]))
        before = len(tabs())
        sv.cmd({"do": "go", "id": page, "url": f"{sv.BASE}/next"})
        t.ok("navigation cancels the pending request", until(lambda: not state(page)["pending"]) and len(tabs()) == before)
        t.ok("navigation does not remember consent", state(page)["allowed"] == [] and state(page)["denied"] == [])

        page = sv.page("auto")
        t.ok("a new document can ask again", until(lambda: state(page)["asking"]))
        sv.page("other")
        t.ok("switching away dismisses the old question", not state(page)["pending"])

        anchor = sv.page("plain")
        sv.cmd({"do": "popups", "id": anchor, "action": "allow"})
        page = sv.page("third"); time.sleep(1)
        t.ok("allowing the top site does not authorize an ad frame", not opened("/opened-ad") and not state(page)["asking"])

        page = sv.page("third-click")
        sv.cmd({"do": "tap", "id": page, "selector": "iframe"})
        t.ok("a clicked third-party frame asks for its own site", until(lambda: state(page)["asking"]) and state(page)["askingHost"] == "localhost")
        answer(page, False)
        t.ok("a clicked ad frame cannot bypass denial", not opened("/opened-ad-click"))
        sv.cmd({"do": "popups", "action": "remove", "site": "localhost"})

        sv.sp("private")
        private = next(tab["id"] for tab in tabs() if tab["active"] and tab["shy"])
        sv.cmd({"do": "go", "id": private, "url": f"{sv.BASE}/auto"})
        t.ok("private tab does not inherit the saved allow choice", until(lambda: state(private)["asking"]))
        answer(private, False)
        t.ok("private denial stays in this tab", state(private)["tabDenied"] == ["127.0.0.1"] and state(private)["denied"] == [])
        sv.sp("select", id=anchor)
        sv.quit(); sv.launch()
        sites = sv.cmd({"do": "popups", "action": "sites"})
        t.ok("normal choice survives restart without saving private denial", sites == {"allowed": ["127.0.0.1"], "denied": []}, sites)
    finally:
        t.done(); sv.finish()
    return 1 if t.failed else 0


if __name__ == "__main__":
    sys.exit(main())
