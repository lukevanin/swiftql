#!/usr/bin/env python3
"""Paired-control A/B driver for issue #353.

Builds the SwiftQLGRDB6 comparison graph twice -- once per supplied SwiftQL
source tree -- then interleaves timed processes so that thermal and scheduler
drift hits both arms equally. Reuses run.py for fixture verification, graph
preparation, building, and sample parsing so the measured path is the same one
the #250 harness measures.
"""
import argparse, importlib.util, json, shutil, statistics, subprocess, sys, time
from pathlib import Path

def load_run_module(comparison_dir: Path):
    spec = importlib.util.spec_from_file_location("comparison_run", comparison_dir / "run.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules["comparison_run"] = module
    spec.loader.exec_module(module)
    return module

def process_id(pair: int) -> int:
    """Return the executable's process id for a pair index.

    The comparison executable accepts only ids 1 through 3, so a seventh pair
    reuses id 1. The id labels the printed samples and nothing else, and both
    arms of one pair always receive the same id.
    """
    if pair < 1:
        raise ValueError(f"pair index must be positive, got {pair}")
    return ((pair - 1) % 3) + 1


def pair_schedule(pairs: int) -> list:
    """Return the run order as (pair, arm) entries.

    Both arms of a pair run back to back. The arm that runs first alternates
    by pair, so a monotonic drift over the whole run cannot favour one arm.
    """
    if pairs < 1:
        raise ValueError(f"pairs must be positive, got {pairs}")
    order = []
    for pair in range(1, pairs + 1):
        arms = ("baseline", "candidate") if pair % 2 else ("candidate", "baseline")
        order.extend((pair, arm) for arm in arms)
    return order


def percentage_change(baseline: float, candidate: float) -> float:
    """Return the candidate's change against the baseline, as a percentage."""
    if baseline <= 0:
        raise ValueError(f"baseline must be positive, got {baseline}")
    return (candidate - baseline) / baseline * 100.0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--comparison-dir", type=Path, required=True)
    parser.add_argument("--workspace", type=Path, required=True)
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--pairs", type=int, default=3)
    parser.add_argument("--cooldown-seconds", type=float, default=180.0)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--build-only", action="store_true")
    options = parser.parse_args()

    run = load_run_module(options.comparison_dir)
    spec = next(s for s in run.GRAPH_SPECS if s.identifier == "swiftql_grdb6")

    workspace = options.workspace.resolve()
    arms = {"baseline": options.baseline.resolve(), "candidate": options.candidate.resolve()}

    executables = {}
    graphs = {}
    if not (workspace / "built.json").exists():
        run.ensure_empty_workspace(workspace)
        fixture = workspace / "Fixture" / "northwind-performance.sqlite"
        run.decompress_and_verify_fixture(fixture)
        for arm, checkout in arms.items():
            support = workspace / arm / "Sources" / "ComparisonBenchmarkSupport"
            support.parent.mkdir(parents=True, exist_ok=True)
            shutil.copytree(run.SUPPORT_PACKAGE_DIRECTORY, support)
            graph_root = workspace / arm / "Graphs"
            graph_root.mkdir(parents=True)
            graphs[arm] = run.prepare_graph(graph_root, spec, checkout, support, fixture)
        for arm in arms:
            print(f"building {arm}", flush=True)
            executables[arm] = run.build_graph(graphs[arm])
        (workspace / "built.json").write_text(json.dumps(
            {a: {"graph": str(graphs[a]), "exe": str(executables[a])} for a in arms}))
    else:
        built = json.loads((workspace / "built.json").read_text())
        graphs = {a: Path(built[a]["graph"]) for a in arms}
        executables = {a: Path(built[a]["exe"]) for a in arms}
        print("reusing existing build", flush=True)

    for arm, exe in executables.items():
        if not Path(exe).is_file():
            raise SystemExit(f"missing executable for {arm}: {exe}")
    if options.build_only:
        print("built both arms; timing skipped")
        return 0

    if options.cooldown_seconds:
        print(f"cooling down {options.cooldown_seconds:g}s", flush=True)
        time.sleep(options.cooldown_seconds)

    samples = {arm: {} for arm in arms}
    order = pair_schedule(options.pairs)

    for index, (pair, arm) in enumerate(order, start=1):
        identifier = process_id(pair)
        print(f"[{index:02d}/{len(order)}] pair {pair} {arm} (process {identifier})", flush=True)
        completed = subprocess.run(
            [str(executables[arm]), "swiftql", str(identifier)],
            capture_output=True,
        )
        if completed.returncode != 0:
            sys.stderr.write(completed.stderr.decode("utf-8", "replace"))
            raise SystemExit(f"{arm} pair {pair} exited {completed.returncode}")
        samples[arm][pair] = run.parse_samples(
            completed.stdout, implementation="swiftql", process=identifier
        )

    report = {"pairs": options.pairs, "order": [f"{p}:{a}" for p, a in order], "arms": {}}
    for arm in arms:
        process_medians = [run.median(samples[arm][p]) / 1e6 for p in sorted(samples[arm])]
        process_p95 = [run.nearest_rank_p95(samples[arm][p]) / 1e6 for p in sorted(samples[arm])]
        report["arms"][arm] = {
            "checkout": str(arms[arm]),
            "process_medians_ms": process_medians,
            "process_p95_ms": process_p95,
            "headline_median_ms": run.median(process_medians),
            "headline_p95_ms": run.median(process_p95),
            "spread_pct": (max(process_medians) - min(process_medians))
            / run.median(process_medians) * 100.0,
            "samples_ms": {str(p): [v / 1e6 for v in samples[arm][p]] for p in sorted(samples[arm])},
        }

    base = report["arms"]["baseline"]
    cand = report["arms"]["candidate"]
    report["delta"] = {
        "median_pct": percentage_change(
            base["headline_median_ms"], cand["headline_median_ms"]
        ),
        "p95_pct": percentage_change(
            base["headline_p95_ms"], cand["headline_p95_ms"]
        ),
        "per_pair_median_pct": [
            percentage_change(
                run.median(samples["baseline"][p]), run.median(samples["candidate"][p])
            )
            for p in range(1, options.pairs + 1)
        ],
    }
    options.output.parent.mkdir(parents=True, exist_ok=True)
    options.output.write_text(json.dumps(report, indent=2))
    print(json.dumps({k: v for k, v in report.items() if k != "arms"}, indent=2))
    for arm in arms:
        a = report["arms"][arm]
        print(f"{arm:9s} median={a['headline_median_ms']:.2f}ms "
              f"p95={a['headline_p95_ms']:.2f}ms spread={a['spread_pct']:.2f}%")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
