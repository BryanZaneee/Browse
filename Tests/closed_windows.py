#!/usr/bin/env python3
"""Closed-window lifetime, focus and reopen checks in an owned hidden world.

Adapted from driceroland/Search PR #549 at 1d9c103f; cleanup uses Browse's
owned World harness, never upstream's Trash override.
"""
import sys
import time
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv

sv.use("closed-windows")
def windows(action, **fields):
    return sv.cmd({"do": "windows", "action": action, **fields})["windows"]
def alive(): return len(sv.cmd({"do": "probe"})["windows"])
def lights(number): return sv.cmd({"do": "probe", "window": number}).get("lights")

t = sv.T()
try:
    sv.setup(); sv.launch()
    first = lights(1)
    counts, misplaced = [], []
    for cycle in range(20):
        number = len(windows("new"))
        if lights(number) != first: misplaced.append(cycle + 1)
        windows("close", n=number)
        counts.append(alive())
    t.ok("closed-window counts plateau across 20 cycles", max(counts[-5:]) <= max(counts[:5]), counts)
    t.ok("traffic lights remain aligned", bool(first) and not misplaced, misplaced)
    windows("new"); windows("front", n=1)
    sv.cmd({"do": "press", "window": 2, "code": 37, "chars": "l", "mods": ["cmd"]})
    time.sleep(.4)
    fields = [sv.cmd({"do": "probe", "window": n}).get("field") for n in (1, 2)]
    t.ok("background window keeps its own Command-L handler", fields == [False, True], fields)
    fixture = sv.BASE + "/reopen-fixture"
    submission = sv.cmd({"do": "field", "window": 2, "text": fixture, "go": True})
    assert "error" not in submission, submission
    before = windows("state")[-1]["tabs"]
    assert fixture in before, "local fixture must load before testing restoration"
    windows("close", n=2)
    restored = windows("reopen")
    t.ok("closed window reopens with its tabs", len(restored) == 2 and fixture in restored[-1]["tabs"] and restored[-1]["tabs"] == before)
    windows("close", n=2)
    last = windows("state")[0]["tabs"]
    closed = windows("close", n=1)
    t.ok("last window retains its browser and tabs", len(closed) == 1 and closed[0]["tabs"] == last)
    reopened = windows("new")
    t.ok("New Window restores the retained last window", len(reopened) == 1 and reopened[0]["tabs"] == last)
    print("window counts:", counts)
finally:
    t.done(); sv.finish()
sys.exit(1 if t.failed else 0)
