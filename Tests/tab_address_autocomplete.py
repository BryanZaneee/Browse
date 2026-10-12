#!/usr/bin/env python3
"""Native tab-address typing in this checkout's hidden, isolated Search world.

Build with ./build.sh debug. Text and keys go through the NSTextView, and
row clicks through the popup's hit-tested native view. Only fixtures on this
suite's loopback server are seeded or navigated to.
"""
import json
import statistics
import sys
import time
from pathlib import Path

import split_view as sv

sv.use("tab-address-tests")


def field(action="state", **values):
    state = sv.cmd({"do": "tabfield", "action": action, **values})
    assert not state.get("onScreen"), state["onScreen"]
    return state


def key(name):
    return field("key", key=name)


def loaded(id):
    state = sv.cmd({"do": "wait", "id": id, "seconds": 20})
    assert not state.get("timeout") and not state.get("failure"), state


def main():
    t = sv.T()
    requests = []
    serve = sv.H.do_GET
    def counted(handler):
        requests.append(handler.path)
        serve(handler)
    sv.H.do_GET = counted
    times = []
    try:
        sv.setup()
        # A bounded local history, loaded by the real store before launch.
        Path(sv.SUPPORT).mkdir(parents=True, exist_ok=True)
        history = [{"url": f"{sv.BASE}/fixture-{n}", "key": f"{sv.BASE}/fixture-{n}",
                    "title": f"Fixture {n}", "count": 1, "last": time.time() - 978307200}
                   for n in range(10000)]
        Path(sv.SUPPORT, "history.json").write_text(json.dumps(history))
        sv.launch()
        first = sv.page("start")
        for suffix in ["alpha", "beta"]:
            field("seed", url=f"{sv.BASE}/completion-{suffix}", title=suffix)
        prefix = sv.BASE.removeprefix("http://") + "/completion-"
        for layout in ["top", "side", "split"]:
            sv.cmd({"do": "ui", "sidebar": layout == "side"})
            time.sleep(0.6)
            if layout == "split":
                sv.sp("enabled", on=True)
                other = sv.page("other")
                sv.sp("pair", id=first, **{"with": other})
                sv.sp("focus", id=first)
            state = field("begin", id=first)
            t.ok(f"{layout}: actual native editor", state["native"], state)
            t.ok(f"{layout}: initial edit opens no menu", not state["panel"] and not sv.cmd({"do": "probe"})["siteCard"], state)
            before = len(requests)
            state = field("type", text=prefix, replace=True)
            times.extend(state["typingMS"])
            t.ok(f"{layout}: typing makes no fixture requests", len(requests) == before)
            t.ok(f"{layout}: visible suggestions", state["panel"] and len(state["offers"]) == 2, state)
            t.ok(f"{layout}: inline suffix selected", state["selection"][0] == len(prefix) and state["selection"][1] > 0, state)
            panel_id = state["panelID"]
            px, py, pw, ph = state["panelFrame"]
            ax, ay, aw, ah = state["anchorFrame"]
            t.ok(f"{layout}: popup does not cover its field", py + ph <= ay or py >= ay + ah, state)
            gap = ay - py - ph if py < ay else py - ay - ah
            t.ok(f"{layout}: suggestions stay attached to the field", abs(gap - 3) < 1, state)
            state = key("backspace")
            t.ok(f"{layout}: popup reused while typing", state["panelID"] == panel_id, state)
            t.ok(f"{layout}: deleting suffix leaves typed text", state["field"] == prefix and state["selection"] == [len(prefix), 0], state)
            state = field("type", text="a")
            state = key("tab")
            t.ok(f"{layout}: Tab accepts without navigation", state["editing"] and state["field"].endswith("completion-alpha") and not state["panel"], state)
            state = key("enter")
            loaded(first)
            t.ok(f"{layout}: Enter navigates the edited tab", sv.url(sv.sp("state"), first).endswith("/completion-alpha"), state)
            if layout == "split":
                t.ok("split: other pane unchanged", sv.url(sv.sp("state"), other).endswith("/other"))
            field("begin", id=first)
            field("type", text=prefix, replace=True)
            state = key("down")
            t.ok(f"{layout}: Down selects first row", state["picked"] == 0, state)
            state = key("down")
            t.ok(f"{layout}: Down selects second row", state["picked"] == 1, state)
            state = key("up")
            t.ok(f"{layout}: Up selects previous row", state["picked"] == 0, state)
            state = key("escape")
            t.ok(f"{layout}: Escape dismisses without accepting", not state["panel"] and state["field"] == prefix, state)
            key("escape")
            t.ok(f"{layout}: cancel keeps address", sv.url(sv.sp("state"), first).endswith("/completion-alpha"))
            field("begin", id=first)
            field("type", text=prefix, replace=True)
            output = Path(sv.ROOT) / "build" / f"tab-address-{layout}.png"
            field("picture", path=str(output))
            state = field()
            expected = state["offers"][1]
            field("click", row=1)
            loaded(first)
            t.ok(f"{layout}: mouse row navigates", sv.url(sv.sp("state"), first).removeprefix("http://") == expected)
        field("begin", id=first)
        field("type", text=prefix, replace=True)
        field("blur")
        loaded(first)
        t.ok("blur keeps raw draft, not unseen completion", sv.url(sv.sp("state"), first) == "http://" + prefix)
        # Both appearances and a narrow window at the screen's lower-right edge.
        field("begin", id=first)
        state = field("type", text=prefix, replace=True)
        screen = state["screenFrame"]
        if screen:
            sx, sy, sw, sh = screen
            sv.cmd({"do": "windows", "action": "frame", "n": 1, "frame": [sx + sw - 500, sy, 500, 400]})
            state = field()
            px, py, pw, ph = state["panelFrame"]
            t.ok("narrow/edge: popup remains within visible screen", px >= sx and py >= sy and px + pw <= sx + sw and py + ph <= sy + sh, state)
        for look in ["light", "dark"]:
            sv.cmd({"do": "ui", "look": look})
            time.sleep(0.2)
            field("picture", path=str(Path(sv.ROOT) / "build" / f"tab-address-{look}.png"))
        field("type", text="x", replace=True)
        field("picture", path=str(Path(sv.ROOT) / "build" / "tab-address-icons.png"))
        key("escape")
        key("escape")
        control = sv.cmd({"do": "field", "text": prefix, "type": True})
        t.ok("existing omnibox still completes the same local history", control["field"].startswith(prefix) and len(control["field"]) > len(prefix), control)
        control_ms = [sample[0] for sample in control["ms"]]
        print(f"Existing omnibox native insertion median: {statistics.median(control_ms):.2f} ms")
        ordered = sorted(times)
        print(f"10,000 history rows: native key handling median {statistics.median(times):.2f} ms, "
              f"p95 {ordered[int(len(ordered) * 0.95)]:.2f} ms, max {max(times):.2f} ms (excludes later rendering)")
    finally:
        t.done()
        sv.finish()
    return 1 if t.failed else 0


if __name__ == "__main__":
    sys.exit(main())
