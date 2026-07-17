# Issue #188 codec benchmark evidence

This recipe compares the immutable contextual-codec path with the existing
binding and row-decoding workloads without changing `BenchmarkPhase` or
overwriting the historical files in `Benchmarks/Baselines`.

Build and record at least three independent release processes from a clean,
committed package root. Keep the machine idle and do not mix commits, toolchains,
dependencies, or benchmark configurations within one comparison set. The
comparison script rejects fewer than three runs, repeated run timestamps,
non-release or dirty reports, nonstandard sample counts, and incompatible case
contracts or environments.

```sh
mkdir -p .build/benchmarks/issue-188

swift run -c release swiftql-benchmark \
  --warmups 50 \
  --samples 500 \
  --output .build/benchmarks/issue-188/run-1.json

swift run -c release swiftql-benchmark \
  --warmups 50 \
  --samples 500 \
  --output .build/benchmarks/issue-188/run-2.json

swift run -c release swiftql-benchmark \
  --warmups 50 \
  --samples 500 \
  --output .build/benchmarks/issue-188/run-3.json
```

Render a Markdown comparison from the raw reports:

```sh
python3 Benchmarks/Issue188/compare_codec.py \
  .build/benchmarks/issue-188/run-1.json \
  .build/benchmarks/issue-188/run-2.json \
  .build/benchmarks/issue-188/run-3.json
```

The script also rejects mixed repository revisions, toolchains, dependencies,
SQLite sources, fixtures, schemas, and benchmark case contracts. It recomputes
each compared median from the raw 500-sample array before printing a ratio. Its
binding ratio compares pre-resolved contextual encode, storage validation, and
public `Statement.setArguments` against the existing pre-encoded binding
workload; registry/default resolution and argument construction remain outside
that phase. Its decode ratio compares a one-scalar resolved contextual decode
with two wide result-macro rows, so it is workload-level integration evidence,
not a per-field overhead claim.

Do not copy these reports over the historical baseline. If a reviewed issue
artifact is desired, add the new reports under this directory with their commit,
machine, and run conditions documented separately.

## Recorded evidence

The checked-in reports were captured on 2026-07-17 from clean implementation
commit `6a801ebb78e91caea547b36869f3738048867744` before the evidence files
themselves were added. All three used the standard 50 warmups and 500 samples
in separate release processes on a Mac16,8 (Apple M4 Pro), with Xcode 26.5,
Swift 6.3.2, SDK 26.5, GRDB 6.29.3, and SQLite 3.51.0.

| Run | Resolved codec + bind ns | Simple bind ns | Bind ratio | Contextual scalar decode ns | Wide two-row decode ns | Decode ratio |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| [run-1.json](run-1.json) | 333 | 167 | 1.994x | 209 | 2,166 | 0.096x |
| [run-2.json](run-2.json) | 333 | 167 | 1.994x | 208 | 2,000 | 0.104x |
| [run-3.json](run-3.json) | 292 | 167 | 1.749x | 208 | 1,958 | 0.106x |

Median of per-run ratios: bind 1.994x; decode 0.104x. These are intentionally
workload-level integration comparisons: the bind numerator adds pre-resolved
codec conversion and validation, while the decode denominator covers two wide
rows rather than one scalar.
