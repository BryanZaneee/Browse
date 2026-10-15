#!/usr/bin/env python3
"""Repeated, owned-world baseline. Build the desired app configuration first."""
import argparse
import hashlib
import http.server
import threading
import functools
import json
import math
import os
import platform
import socket
import statistics
import subprocess
import sys
import tempfile
import time
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from support.world import World, ROOT


def summary(values, percentile=False):
    if not values or any(not math.isfinite(v) or v < 0 for v in values):
        raise ValueError("nonempty finite nonnegative samples required")
    result = {"median": statistics.median(values), "min": min(values), "max": max(values), "n": len(values)}
    if percentile: result["p95_nearest_rank"] = sorted(values)[math.ceil(len(values) * .95) - 1]
    return result


def content_pids(tabs, host):
    # Only WebKit PIDs explicitly reported by this world's tabs are attributable.
    return sorted({t["process"] for t in tabs if isinstance(t.get("process"), int)
                   and t["process"] > 0 and t["process"] != host})


def usage_delta(before, after, elapsed):
    if elapsed <= 0: raise ValueError("positive sampling interval required")
    if any("error" in p for p in before + after): return {"unavailable": "process accounting failed"}
    a = {(p["pid"], p["start"]): p for p in before}
    b = {(p["pid"], p["start"]): p for p in after}
    if a.keys() != b.keys(): return {"unavailable": "process exited, started or PID reused during sample"}
    cpu = sum(b[k]["cpu_ns"] - a[k]["cpu_ns"] for k in a)
    if cpu < 0: return {"unavailable": "CPU counter regressed"}
    return {"physical_footprint_bytes": sum(p["footprint"] for p in after),
            "cpu_percent_one_core": cpu / (elapsed * 1e9) * 100}


def command(world, request):
    with socket.socket(socket.AF_UNIX) as connection:
        connection.settimeout(30); connection.connect(str(world.socket))
        connection.sendall(json.dumps(request).encode() + b"\n")
        data = b""
        while b"\n" not in data:
            chunk = connection.recv(65536)
            if not chunk: break
            data += chunk
    result = json.loads(data.split(b"\n", 1)[0])
    if "error" in result: raise RuntimeError(result["error"])
    return result


def stop(world):
    if world.pids(): command(world, {"do": "quit"})
    for _ in range(100):
        if not world.pids(): return
        time.sleep(.1)
    raise RuntimeError("owned app did not quit; world retained for inspection")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--repetitions", type=int, default=3)
    parser.add_argument("--configuration", choices=["debug", "release"], required=True)
    parser.add_argument("--smoke", action="store_true", help="validate fixtures quickly; results are not performance evidence")
    args = parser.parse_args()
    if args.smoke: args.repetitions = 1
    if not args.smoke and args.repetitions < 3: parser.error("at least three repetitions required")
    def revision():
        if subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True).strip():
            raise RuntimeError("performance runs require a clean committed checkout")
        return subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    source = revision()
    subprocess.run(["./build.sh", args.configuration], cwd=ROOT,
                   env=os.environ | {"BROWSE_ARCH": platform.machine()}, check=True)
    if revision() != source: raise RuntimeError("source changed while building")
    report = {"schema": 1, "smoke_only": args.smoke, "revision": source,
              "platform": platform.platform(), "architecture": platform.machine(),
              "configuration": args.configuration,
              "mode": "hidden; SEARCH_MEASURE=1; default preferences",
              "settle_seconds": .5 if args.smoke else 60, "sample_seconds": .1 if args.smoke else 5, "runs": [],
              "limitations": ["Socket readiness is not rendered first-frame latency or cold-disk launch.",
                 "Content accounting includes only tab-reported PIDs; GPU/network processes remain unattributed.",
                 "Footprints summed across processes can include shared mappings; not a total system memory cost.",
                 "Hidden pages cannot establish visible heavy-page, video/PiP, high-refresh or frame timing performance.",
                 "Saved group reopen, profile switching and translation are not yet baseline workloads.",
                 "CPU is not battery life; other Macs and OS versions are unmeasured."]}
    report["hardware"] = subprocess.check_output(["sysctl", "-n", "hw.model", "hw.memsize", "hw.logicalcpu"], text=True).splitlines()
    app = ROOT / "build" / ("intel/" if platform.machine() == "x86_64" else "") / "Browse.app"
    report["app_logical_disk_bytes"] = sum(p.stat().st_size for p in app.rglob("*") if p.is_file())
    report["executable_sha256"] = hashlib.sha256((app / "Contents/MacOS/Browse").read_bytes()).hexdigest()
    class Handler(http.server.SimpleHTTPRequestHandler):
        def log_message(self, *args): pass
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(Handler, directory=str(Path(__file__).parent)))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    base_url = f"http://127.0.0.1:{server.server_port}"
    with tempfile.TemporaryDirectory(prefix="browse-perf-helper-") as folder:
        helper = Path(folder) / "metrics"
        subprocess.run(["clang", "-Wall", "-Wextra", "-Werror", str(Path(__file__).with_name("metrics.c")), "-o", str(helper)], check=True)
        def sample(pids): return json.loads(subprocess.check_output([str(helper), *map(str, pids)], text=True))
        def resource_sample(world, settle=10):
            time.sleep(.5 if args.smoke else settle)
            hosts = world.pids()
            if len(hosts) != 1: raise RuntimeError("expected one owned process")
            contents = content_pids(command(world, {"do": "tabs"})["tabs"], hosts[0])
            before_host, before_content = sample(hosts), sample(contents)
            started = time.monotonic(); time.sleep(.1 if args.smoke else 5)
            after_host, after_content = sample(hosts), sample(contents)
            elapsed = time.monotonic() - started
            content = usage_delta(before_content, after_content, elapsed)
            if contents != content_pids(command(world, {"do": "tabs"})["tabs"], hosts[0]):
                content = {"unavailable": "tab process membership changed"}
            return {"settle_seconds": .5 if args.smoke else settle, "host": usage_delta(before_host, after_host, elapsed), "content": content}
        for count in (1, 20, 100):
            for repeat in range(args.repetitions):
                world = World(f"performance-{count}-{repeat}")
                world.wipe(); world.prepare()
                try:
                    # about:blank is deterministic and offline; restoration tests lazy tab cost, not web page load.
                    (world.data / "session.json").write_text(json.dumps({"tabs": [{"url": "about:blank", "title": f"Fixture {n}"} for n in range(count)], "active": 0, "splits": []}))
                    subprocess.run(["defaults", "write", world.bundle, "bench", "-bool", "true"], check=True)
                    started = time.monotonic(); world.launch(measuring=True)
                    launch_ms = (time.monotonic() - started) * 1000
                    if not command(world, {"do": "probe"}).get("measuring"): raise RuntimeError("measurement overrides not enabled")
                    tabs = command(world, {"do": "tabs"})["tabs"]
                    if len(tabs) != count: raise RuntimeError(f"expected {count} restored tabs, got {len(tabs)}")
                    time.sleep(.5 if args.smoke else 60)
                    hosts = world.pids()
                    if len(hosts) != 1: raise RuntimeError("expected exactly one owned app process")
                    contents = content_pids(command(world, {"do": "tabs"})["tabs"], hosts[0])
                    before_host, before_content = sample(hosts), sample(contents)
                    start = time.monotonic(); time.sleep(.1 if args.smoke else 5)
                    after_host, after_content = sample(hosts), sample(contents)
                    elapsed = time.monotonic() - start
                    after_pids = content_pids(command(world, {"do": "tabs"})["tabs"], hosts[0])
                    content = usage_delta(before_content, after_content, elapsed)
                    if contents != after_pids: content = {"unavailable": "tab process membership changed"}
                    row = {"tabs": count, "repeat": repeat + 1, "launch_socket_ms": launch_ms,
                           "host": usage_delta(before_host, after_host, elapsed), "content": content,
                           "content_processes": len(contents)}
                    # Native editor callbacks and socket round trips are not display frames.
                    typed = command(world, {"do": "field", "text": "performance fixture query", "type": True})
                    if not typed.get("ms") or typed.get("field") != "performance fixture query":
                        raise RuntimeError("typing workload did not reach the native field")
                    row["typing_insert_ms"] = summary([pair[0] for pair in typed["ms"]], percentile=True)
                    row["typing_runloop_rest_ms"] = summary([pair[1] for pair in typed["ms"]], percentile=True)
                    command(world, {"do": "press", "code": 53, "chars": "\u001b"})
                    if count == 1:
                        durations = []
                        for _ in range(20):
                            started = time.monotonic()
                            state = command(world, {"do": "windows", "action": "new"})["windows"]
                            command(world, {"do": "windows", "action": "close", "n": len(state)})
                            durations.append((time.monotonic() - started) * 1000)
                        row["window_cycle_command_ms"] = summary(durations, percentile=True)
                        row["window_cycle_note"] = "Includes bench's fixed response delays; not window render latency."
                    if count == 1:
                        extra = row["workloads"] = {}
                        opened = command(world, {"do": "split", "action": "open", "url": base_url + "/heavy.html"})
                        heavy = opened["resultID"]
                        command(world, {"do": "select", "id": heavy})
                        command(world, {"do": "wait", "id": heavy})
                        ready = command(world, {"do": "eval", "id": heavy, "js": "window.fixtureReady === true"})
                        if ready.get("value") is not True: raise RuntimeError("heavy fixture did not finish")
                        extra["hidden_heavy_page"] = resource_sample(world)
                        command(world, {"do": "group", "id": heavy, "new": True, "name": "Fixture"})
                        command(world, {"do": "group", "fold": True, "name": "Fixture"})
                        extra["collapsed_group"] = resource_sample(world)
                        command(world, {"do": "group", "fold": True, "name": "Fixture"})
                        command(world, {"do": "select", "id": tabs[0]["id"]})
                        asleep = command(world, {"do": "sleep", "id": heavy})
                        if not asleep.get("asleep"): raise RuntimeError(f"fixture did not suspend: {asleep}")
                        extra["suspended_page"] = resource_sample(world)
                        command(world, {"do": "select", "id": heavy})
                        command(world, {"do": "wait", "id": heavy})
                        extra["resumed_page"] = resource_sample(world)
                        command(world, {"do": "group", "close": True, "name": "Fixture"})
                        extra["closed_group"] = resource_sample(world)
                        # Availability is an OS limit; installation failures on supported OS fail the run.
                        if tuple(map(int, platform.mac_ver()[0].split('.')[:2])) >= (15, 4):
                            command(world, {"do": "ext-folder", "path": str(Path(__file__).parent / "extension"), "yes": True})
                            installed = []
                            for _ in range(100):
                                installed = command(world, {"do": "extensions"})["extensions"]
                                if installed and installed[0]["loaded"]: break
                                time.sleep(.1)
                            if len(installed) != 1 or not installed[0]["loaded"]: raise RuntimeError("extension fixture did not load")
                            extra["extension_on"] = resource_sample(world)
                            command(world, {"do": "ext-enable", "id": installed[0]["id"], "on": False})
                            extra["extension_off"] = resource_sample(world)
                        else: extra["extensions"] = {"unavailable": "requires macOS 15.4"}
                    report["runs"].append(row)
                    print(json.dumps(row), flush=True)
                finally:
                    stop(world); world.wipe()
        report["summary"] = {}
        for count in (1, 20, 100):
            rows = [r for r in report["runs"] if r["tabs"] == count]
            totals = {"launch_socket_ms": summary([r["launch_socket_ms"] for r in rows])}
            for kind in ("host", "content"):
                for metric in ("physical_footprint_bytes", "cpu_percent_one_core"):
                    values = [r[kind][metric] for r in rows if metric in r[kind]]
                    totals[kind + "_" + metric] = summary(values) if len(values) == args.repetitions else {"unavailable": "incomplete repetitions"}
            report["summary"][str(count)] = totals
    server.shutdown(); server.server_close()
    if revision() != source: raise RuntimeError("source changed during measurement")
    args.output.write_text(json.dumps(report, indent=2) + "\n")

if __name__ == "__main__": main()
