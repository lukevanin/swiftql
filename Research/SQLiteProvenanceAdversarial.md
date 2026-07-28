# Adversarial review: dual SQLite provenance (system compatibility mode + vendored build)

**Proposal under review.** SwiftQL supports two SQLite provenances: a
*compatibility mode* linking system `libsqlite3`, for environments where a
vendored build is technically or contractually impossible; and a *vendored*
amalgamation with SwiftQL-chosen compile options "to enable specific
capabilities and/or improve performance."

**Verdict: the dual-provenance split is right, but the stated rationale for
the vendored build is wrong, and adopting it as stated would break SwiftQL's
conformance claim.** Vendoring should be justified by *determinism and
operational access*, not by capabilities or speed. With that substitution the
proposal is sound and mostly pre-built. Without it, §1 is fatal.

This is a deliberately adversarial reading of
[SQLiteCFeasibility.md §1](SQLiteCFeasibility.md), which recommended "support
both; default to system; make the vendored target the CI and conformance
authority." Two of its conclusions do not survive contact with the proposal as
framed, and one unexamined precondition turns out to be load-bearing.

---

## 1. The central contradiction: capabilities vs. one conformance claim

The proposal wants the vendored build to *enable specific capabilities*.
[SQLiteCFeasibility §1.5](SQLiteCFeasibility.md) states the opposing principle:

> The vendored option set **must not create capabilities that do not exist on
> the system path.** v2.1 requires the shared corpus to pass on both adapters
> ([ROADMAP.md:702-703](../ROADMAP.md)); if a vendored build enables something
> Apple's build omits, the corpus splits and the conformance inventory stops
> meaning one thing.

These cannot both hold. The choice is binary and it should be made explicitly:

- **(a) One conformance claim.** The vendored option set is pinned to the
  *intersection* of what every supported system SQLite provides. SwiftQL's
  documented SQL surface is identical on both paths. Vendoring buys determinism,
  not surface.
- **(b) Vendored-exclusive capabilities.** SwiftQL's SQL surface becomes
  provenance-dependent. The conformance inventory needs one environment record
  per provenance, `Conformance/SQLite/REPORT.md` needs per-provenance claims,
  the combinatorial corpus needs provenance tagging, and every capability-gated
  construct needs a compile-time or runtime gate that does not exist today (§3).

Option (b) is not unreasonable — but it is a *much* larger project than the
proposal implies, and it is the thing that multiplies the support matrix. The
recommendation in §6 is (a), with an explicit escape hatch for later.

**Note what this costs the proposal.** Under (a), the honest answer to "what
does vendoring enable?" is: `SQLITE_DQS=0` at compile time rather than per
connection, `sqlite3_progress_handler` and `sqlite3_trace_v2` guaranteed present
rather than merely usually present, and a pinned `sqlite3_source_id()`. That is a
real and sufficient justification. It is not "specific capabilities."

## 2. "Improve performance" is the weakest leg and should be dropped

Compile options that plausibly affect throughput — `SQLITE_DEFAULT_MEMSTATUS=0`,
various `OMIT_*`, threading-mode selection — produce low-single-digit effects for
SwiftQL-shaped workloads. Three problems:

1. **SwiftQL cannot currently measure it.** The benchmark machine is contended
   enough that sub-10% deltas are not trustworthy; allocation counts are the
   reliable signal, and compile options do not move allocation counts.
2. **The largest real lever is not a compile option.** It is threading mode, and
   that is a per-connection `SQLITE_OPEN_NOMUTEX` decision available on *both*
   provenances ([SQLiteCFeasibility §1.5](SQLiteCFeasibility.md), §3.1).
3. **Apple's build is already tuned.** It ships `DEFAULT_MEMSTATUS=0` and
   `MUTEX_UNFAIR`. A naive vendored build is as likely to be slower.

Keeping "performance" in the rationale invites a benchmark obligation SwiftQL
cannot discharge. Drop it; the determinism argument is strong enough alone.

## 3. The precondition nobody has costed: version gating is unwired and fail-closed

This is the finding that most changes the plan. Compatibility mode is a promise
that SwiftQL behaves correctly on a SQLite it did not choose. The machinery to
keep that promise exists in the type system, is **fail-closed**, and is
**not connected to anything**.

`XLDialectRequirement.validate`
([SQLDialect.swift:143-152](../Sources/SwiftQLCore/SQLDialect.swift#L143)):

```swift
if let minimumVersion {
    guard let actualVersion = descriptor.version, actualVersion >= minimumVersion else {
        throw XLDatabaseContractError.versionMismatch(…, actual: descriptor.version)
    }
}
```

A `nil` actual version does not pass — it throws. And the actual version is
always `nil`, because the only production construction site omits it
([GRDBSQLDatabase.swift:941-943](../Sources/SwiftQL/GRDBSQLDatabase.swift#L941)):

```swift
let dialect = XLSQLiteDialect(
    identifierFormattingOptions: formatter.identifierFormattingOptions
)   // version: defaults to nil
```

Three consequences:

1. **No production statement declares a minimum version.** `minimumVersion:` is
   set in exactly 10 places, all under `Tests/`. If any real construct declared
   one it would throw on every database SwiftQL opens. The mechanism is dormant,
   and its dormancy is currently invisible because nothing uses it.
2. **Nothing probes the runtime SQLite version.** The only `sqlite_version()`
   call in the entire package is in the build-validation runtime
   ([SQLiteBuildValidationRuntime.swift:209](../Sources/SwiftQLSQLiteBuildValidationValidator/SQLiteBuildValidationRuntime.swift#L209)),
   which runs at *build* time on the *developer's* machine.
3. **`XLDialectCapabilities` cannot express SQL features.** It has exactly two
   members, `namedBindings` and `indexedBindings`
   ([SQLDialect.swift:89-91](../Sources/SwiftQLCore/SQLDialect.swift#L89)). It is
   a binding-style flag set, not a feature-capability system. Every
   version-sensitive or option-sensitive SQL construct in SwiftQL is presently
   ungated on both provenances.

Meanwhile the conformance inventory *already records* per-feature minimum
versions spanning 3.24.0 → 3.42.0. So SwiftQL knows, as data, that its surface is
version-sensitive, and enforces none of it in code. Compatibility mode does not
create this gap — it makes it load-bearing, because a vendored-only world can
pin the version and ignore the whole problem.

**Cost.** Wiring `descriptor.version` from `sqlite3_libversion()`, extending
capabilities to model SQL features and compile options, and annotating every
version-sensitive construct is a cross-cutting change touching the dialect, the
driver, the descriptor, the macros, and the inventory. It is a prerequisite for
an honest compatibility mode, and it is not in
[SQLiteCFeasibility §6](SQLiteCFeasibility.md)'s staging plan.

## 4. You cannot enumerate the set you are promising to support

Compatibility mode's support set is "every system SQLite on every OS SwiftQL
targets" — iOS 16+ and macOS 13+ ([Package.swift:8](../Package.swift)), plus
Linux distro libsqlite3. **That set is not publicly documented.** Apple publishes
no per-OS-release SQLite version table; the community reference everyone cites
([GRDB's SQLite versions wiki](https://github.com/groue/GRDB.swift/wiki/SQLite-versions))
was last updated in 2019 and stops at iOS 13. Measured locally, the current SDK
header pins 3.51.0 for both `iphoneos` and `macosx`, but the SDK header is a
*build-time* constant — a device running iOS 16 links whatever shipped with iOS 16.

This is not a documentation nuisance; it is a testability blocker. You cannot
write a matrix cell for a version you cannot name, and you cannot CI-verify a
device SQLite from a Mac. Compatibility mode is therefore **structurally
untestable at its edges**, and any claim about it is inference, not evidence —
which is precisely the standard `Conformance/SQLite/REPORT.md` exists to hold.

The repo has already hit the hard end of this. Ubuntu 22.04's system SQLite 3.37
predates `UNIXEPOCH`, a required capability in the conformance corpus
([COMPATIBILITY.md:129-131](../COMPATIBILITY.md)); CI's response was to stop using
the system library and build the amalgamation. **On one of its two pinned support
points, the project has already rejected compatibility mode.** That is the
strongest single piece of evidence in this document, and it cuts against the
proposal: SwiftQL's own CI could not live with system SQLite.

## 5. The selection mechanism is unsolved on the current toolchain

How does a client *choose*? SwiftPM offers no good answer at
`swift-tools-version: 5.9`:

| Mechanism | Verdict |
|---|---|
| Package traits ([SE-0450](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0450-swiftpm-package-traits.md)) | The designed answer — `.when(traits:)` gates a dependency edge out of the build plan entirely. **Landed in SwiftPM 6.1**, above SwiftQL 1.x's 5.9 floor. |
| Two products / duplicated target trees | Two module names, so `import` sites and macro-generated code diverge. Source-incompatible between modes. |
| Environment variable read in `Package.swift` | Breaks resolution reproducibility and is unreliable under Xcode. |
| Separate C package behind a shared module name | Impossible; C module identity is fixed at compile time. |
| `.unsafeFlags` | Poisons downstream resolution — dependent packages cannot depend on SwiftQL at all. |

Ecosystem precedent is discouraging. GRDB — the most mature Swift SQLite library,
a decade in — implements custom SQLite via cloning the repo, initialising a
submodule, authoring four config files, embedding an Xcode project, and adding a
pre-action script, and documents plainly that **"the technique described here is
not compatible with the Swift Package Manager."** If GRDB has not solved this
with SwiftPM, SwiftQL should not assume it will fall out cheaply.

**Consequence for sequencing.** A clean provenance selector requires Swift 6.1
traits, which ties this decision to the same Swift-6 milestone as
[#133](https://github.com/lukevanin/swiftql/issues/133) and the async-contract
decision. Attempting dual provenance on the 5.9 line means picking one of the bad
mechanisms above.

## 6. Two hazards the original report understates

**6.1 Symbol prefixing forecloses handle sharing.**
[SQLiteCFeasibility §1.3](SQLiteCFeasibility.md) correctly makes prefixing
mandatory for the vendored build, to stop static definitions from silently
capturing GRDB's dynamic `sqlite3_*` references. The unstated consequence: a
prefixed vendored SQLite **cannot share a connection handle with anything else** —
not GRDB, not Core Data, not SQLCipher, not a system-mode SwiftQL database in the
same process. Vendored mode is therefore not merely a different build, it is an
isolation boundary. Any client with a mixed stack is pushed onto compatibility
mode whether they wanted it or not — which is an argument *for* keeping
compatibility mode genuinely first-class, and against treating it as a fallback.

**6.2 The regulatory argument runs both directions.** The proposal assumes
compliance pressure favours system SQLite. Often it favours vendoring: an SBOM
can state exactly which SQLite ships, and builds are reproducible. What vendoring
actually transfers is **CVE response**. On the system path an OS update patches
users; on the vendored path a SQLite CVE obliges SwiftQL to cut a release, and
every client to adopt it. For a single-maintainer project that is a standing,
unbounded commitment, and it is the strongest cost of vendoring — stronger than
binary size. It also argues that vendored should track upstream SQLite on a
schedule, which is new release-process work.

## 7. What survives — the steelman

The proposal is correct in its core instinct, and more of it is pre-built than
the objections above suggest:

- **The data model already anticipated dual provenance.** The conformance
  inventory's `sqlite_environments` is a **list**, and each entry carries
  `sqlite_version`, `sqlite_source_id`, and `compile-option:*` capability strings.
  It currently holds one element (`sqlite-3.51.0-macos-arm64`). Adding a second
  environment is a data change, not a schema redesign — genuinely good
  foresight in the existing design.
- **`SQLiteBuildValidationRuntime` already captures provenance identity** —
  `compile_options`, `sqlite_version`, `sqlite_source_id` per run — so mismatch
  *detection* needs no new design.
- **CI already builds the amalgamation** with a SHA3-256-pinned source and a
  chosen option set ([swift.yml:494-516](../.github/workflows/swift.yml)). Moving
  that into a SwiftPM target using `.define` is mechanical, and `.define` is not
  an unsafe flag, so downstream resolution is unaffected.
- **A conformance claim requires a pinned library.** "Evidence-backed conformance"
  against whatever SQLite the OS happens to ship is not a claim anyone can audit.
  This alone justifies a vendored target existing, independent of whether any
  client ever selects it.
- **Compatibility mode is genuinely necessary** — §6.1 shows mixed-stack clients
  are forced onto it regardless of preference.

## 8. Recommendation

**Support both. Invert the report's default. Justify vendoring by determinism,
not capability. Gate the whole thing on version wiring.**

1. **Vendored is the default for the native adapter, and the conformance
   authority.** [SQLiteCFeasibility §1.6](SQLiteCFeasibility.md) recommended
   defaulting to system; that is wrong for the *native* adapter specifically,
   whose entire purpose is determinism. A native adapter defaulting to an
   unpinnable, unenumerable library inherits the problem it was built to solve.
   Binary size (~0.75–1 MB) is the price of the guarantee.

2. **Adopt option (a) from §1: no vendored-exclusive SQL capabilities.** Pin the
   vendored option set to the intersection, per
   [SQLiteCFeasibility §1.5](SQLiteCFeasibility.md). Revisit only when a concrete
   feature request justifies splitting the corpus — and cost that split honestly
   when it comes.

3. **Compatibility mode ships with a deliberately weaker, separately worded
   claim.** Not "conformant" — something like *supported, version-probed,
   best-effort*, with conformance evidence explicitly scoped to the vendored
   environment. §4 shows the stronger claim cannot be substantiated.

4. **Make version wiring a precondition, not a follow-up (§3).** Populate
   `descriptor.version` from `sqlite3_libversion()`; extend
   `XLDialectCapabilities` to model SQL features and compile options; annotate
   version-sensitive constructs using the minimums the inventory already records.
   Until this lands, compatibility mode is a promise with no mechanism behind it.
   This belongs in [SQLiteCFeasibility §6](SQLiteCFeasibility.md)'s staging plan,
   early.

5. **Defer the selection mechanism to Swift 6.1 traits (§5).** Do not attempt
   dual provenance on the 5.9 line. Until traits are available, ship the vendored
   target only, and treat compatibility mode as designed-for but not yet
   selectable — which is honest, and costs nothing that is not already owed.

6. **Drop "performance" from the rationale (§2).** Keep `PROGRESS_CALLBACK`,
   `TRACE`, and `DQS=0` — those are operational access, and they are the real win.

### What would change this recommendation

A concrete requirement for a SQL feature Apple's build omits — the plausible
candidate is runtime extension loading, which Apple omits via
`SQLITE_OMIT_LOAD_EXTENSION` and which no per-connection setting can restore.
That would force option (b) and, with it, a genuinely provenance-dependent SQL
surface. If that requirement is foreseeable, it is much cheaper to design the
capability system for it now (§3) than to retrofit it after the conformance
corpus has been published as a single claim.
