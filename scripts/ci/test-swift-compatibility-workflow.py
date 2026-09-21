#!/usr/bin/env python3

"""Fail-closed fixtures for the pinned Swift compatibility workflow."""

from __future__ import annotations

import hashlib
import os
import re
import shutil
import stat
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github/workflows/swift.yml"
DOCUMENTATION_WORKFLOW = ROOT / ".github/workflows/documentation.yml"
ENVIRONMENT_CHECK = ROOT / "scripts/ci/check-compatibility-environment.sh"


class SwiftCompatibilityWorkflowTests(unittest.TestCase):
    def test_linux_cells_use_the_exact_swift63_toolchain_on_ubuntu22(self) -> None:
        # Issue #133 adopted Swift 6 language mode, which needs a tools-6.0
        # manifest. A Swift 5.9 compiler cannot parse one, so the Linux pair
        # that used to pin 5.9.2 now pins the Swift 6.3.2 archive the
        # repository already verified for its newer-series Linux cell.
        workflow = WORKFLOW.read_text(encoding="utf-8")
        compatibility = workflow.split("\n  compatibility:\n", maxsplit=1)[1]
        matrix = compatibility.split("\n    env:\n", maxsplit=1)[0]

        self.assertNotIn("runner: macos-14", matrix)
        # No cell may claim a Swift 5.x toolchain: the package's tools version
        # is 6.0, so such a cell could not resolve the manifest at all.
        self.assertNotIn('swift_series: "5.', matrix)
        self.assertNotIn("swift-5.9.2-RELEASE", compatibility)
        self.assertEqual(matrix.count('swift_series: "6.3"'), 2)
        self.assertEqual(matrix.count('swift_version: "6.3.2"'), 2)
        # Both Linux cells install their toolchain on PATH.
        self.assertEqual(matrix.count("swift_command_mode: path"), 2)
        self.assertEqual(matrix.count("runner: ubuntu-22.04"), 2)
        self.assertEqual(matrix.count("\n            runner: macos-15\n"), 2)
        self.assertEqual(matrix.count("platform: linux"), 2)
        self.assertEqual(matrix.count("platform: macos"), 2)
        self.assertEqual(matrix.count("image_os: ubuntu22"), 2)
        self.assertEqual(matrix.count("image_os: macos15"), 2)
        self.assertEqual(matrix.count("architecture: x86_64"), 2)
        self.assertEqual(matrix.count("architecture: arm64"), 2)
        self.assertEqual(matrix.count('sqlite_version: "3.53.3"'), 2)

        # Each platform is covered in both resolution modes.
        for platform, resolutions in (("linux", 2), ("macos", 2)):
            cells = [
                entry
                for entry in matrix.split("\n          - name: ")[1:]
                if f"platform: {platform}" in entry
            ]
            self.assertEqual(len(cells), resolutions)
            self.assertEqual(
                sorted(
                    "committed" if "resolution: committed" in cell else "clean"
                    for cell in cells
                ),
                ["clean", "committed"],
            )

        self.assertNotIn("swift-actions/setup-swift", compatibility)
        self.assertIn(
            "if: ${{ matrix.platform == 'linux' }}", compatibility
        )
        self.assertIn(
            "https://download.swift.org/swift-6.3.2-release/ubuntu2204/"
            "swift-6.3.2-RELEASE/"
            "swift-6.3.2-RELEASE-ubuntu22.04.tar.gz",
            compatibility,
        )
        self.assertIn(
            "SWIFT_TOOLCHAIN_SIGNATURE_URL: "
            "${{ matrix.swift_toolchain_url }}.sig",
            compatibility,
        )
        self.assertIn(
            "SWIFT_TOOLCHAIN_SIGNATURE_SHA256: "
            "${{ matrix.swift_toolchain_signature_sha256 }}",
            compatibility,
        )
        self.assertEqual(
            matrix.count(
                "swift_toolchain_signature_sha256: "
                "06fcd8d2f92d9d4b557d3f832efc26a5539f7238d8ed47e0ba4e409477286581"
            ),
            2,
        )
        # The Swift 6.x release signing key, not the 5.x key the 5.9 cells used.
        self.assertEqual(
            matrix.count(
                "swift_signing_fingerprint: "
                "52BB7E3DE28A71BE22EC05FFEF80A866B47A981F"
            ),
            2,
        )
        self.assertNotIn("A62AE125BBBFBB96A6E042EC925CC1CCED3D1561", matrix)
        self.assertIn(
            "SWIFT_SIGNING_FINGERPRINT: ${{ matrix.swift_signing_fingerprint }}",
            compatibility,
        )
        self.assertIn(
            '[[ "$SWIFT_TOOLCHAIN_URL" == "$expected_toolchain_url" ]]',
            compatibility,
        )
        self.assertIn("https://keyserver.ubuntu.com/pks/lookup", compatibility)
        self.assertIn("pinned-fingerprint fallback", compatibility)
        self.assertIn("download_verified()", compatibility)
        self.assertIn("sha256sum --check --status", compatibility)
        self.assertIn("gpg --batch", compatibility)
        self.assertIn("[GNUPG:] VALIDSIG", compatibility)
        self.assertIn(
            "https://www.sqlite.org/2026/sqlite-amalgamation-3530300.zip",
            compatibility,
        )
        self.assertIn(
            "SQLITE_AMALGAMATION_SHA3_256: "
            "d45c688a8cb23f68611a894a756a12d7eb6ab6e9e2468ca70adbeab3808b5ab9",
            compatibility,
        )
        self.assertIn("openssl dgst -sha3-256", compatibility)
        self.assertIn("-DSQLITE_ENABLE_FTS5", compatibility)
        self.assertIn("-DSQLITE_ENABLE_MATH_FUNCTIONS", compatibility)
        self.assertEqual(compatibility.count("-DSQLITE_ENABLE_SNAPSHOT"), 2)
        self.assertIn("libsqlite3.so", compatibility)
        self.assertIn("nm -D --defined-only", compatibility)
        self.assertIn("sqlite3_snapshot_get", compatibility)
        self.assertIn("CPATH=", compatibility)
        self.assertIn("LIBRARY_PATH=", compatibility)
        self.assertIn("LD_LIBRARY_PATH=", compatibility)
        self.assertIn("SWIFTQL_SQLITE_INCLUDE_DIR=", compatibility)
        self.assertIn("SWIFTQL_SQLITE_LIBRARY_DIR=", compatibility)
        self.assertIn(
            '-DSQLITE_ENABLE_SNAPSHOT '
            '-Xcc -I -Xcc "$SWIFTQL_SQLITE_INCLUDE_DIR" '
            '-L "$SWIFTQL_SQLITE_LIBRARY_DIR"',
            compatibility,
        )
        self.assertIn("-DGRDBCUSTOMSQLITE", compatibility)
        self.assertIn("SWIFT_EXEC=", compatibility)
        self.assertIn(
            'compiler_wrapper="$toolchain_bin/swiftql-swiftc"', compatibility
        )
        self.assertIn("SWIFTQL_REAL_SWIFT_FRONTEND=", compatibility)
        self.assertIn('"-modulewrap"', compatibility)
        self.assertIn("os_id: ubuntu", matrix)
        self.assertIn('os_version_id: "22.04"', matrix)
        self.assertIn("target_triple: x86_64-unknown-linux-gnu", matrix)
        self.assertIn(
            "EXPECTED_SWIFT_VERSION: ${{ matrix.swift_version }}", compatibility
        )
        self.assertIn(
            "EXPECTED_SWIFT_COMMAND_MODE: ${{ matrix.swift_command_mode }}",
            compatibility,
        )
        self.assertIn("EXPECTED_IMAGE_OS: ${{ matrix.image_os }}", compatibility)
        self.assertIn(
            "EXPECTED_ARCHITECTURE: ${{ matrix.architecture }}", compatibility
        )
        self.assertIn(
            "EXPECTED_SQLITE_VERSION: ${{ matrix.sqlite_version }}",
            compatibility,
        )
        self.assertIn(
            "SWIFTQL_SQLITE_RUNTIME sqlite_version=$EXPECTED_SQLITE_VERSION ",
            compatibility,
        )
        self.assertIn("Check BETWEEN type safety", compatibility)
        self.assertIn("scripts/ci/check-between-type-safety.sh", compatibility)
        self.assertIn("Check named binding packet type safety", compatibility)
        self.assertIn(
            "scripts/ci/check-named-binding-packet-type-safety.sh", compatibility
        )
        self.assertIn("Verify declared-query discovery end to end", compatibility)
        self.assertIn(
            "IntegrationTests/DeclaredQueryRegistryFixture/verify.sh", compatibility
        )

    def test_linux_swift6_cell_reuses_the_verified_toolchain_bootstrap(
        self,
    ) -> None:
        # Issue #672: one Linux cell on Swift 6, so the OpenCombine bridge and
        # the Foundation-backed codecs run under swift-foundation. It must use
        # the same signature-verified archive path and pinned SQLite build as
        # the Swift 5.9 cells, not an unverified toolchain action.
        workflow = WORKFLOW.read_text(encoding="utf-8")
        compatibility = workflow.split("\n  compatibility:\n", maxsplit=1)[1]
        matrix = compatibility.split("\n    env:\n", maxsplit=1)[0]
        entries = matrix.split("\n          - name: ")[1:]
        linux_swift6 = [
            entry
            for entry in entries
            if "platform: linux" in entry and 'swift_series: "6.' in entry
        ]

        # Two since #133: the Swift 5.9 pair could not parse a tools-6.0
        # manifest, so Linux keeps both resolution modes on this series.
        self.assertEqual(len(linux_swift6), 2)
        self.assertEqual(
            sorted(cell.split("\n", maxsplit=1)[0] for cell in linux_swift6),
            [
                "Swift 6.3 / Linux clean resolution",
                "Swift 6.3 / Linux committed resolution",
            ],
        )
        for cell in linux_swift6:
            self.assertIn("resolution: ", cell)
        cell = linux_swift6[0]
        for expected in (
            'swift_series: "6.3"',
            'swift_version: "6.3.2"',
            "swift_command_mode: path",
            "swift_toolchain_url: https://download.swift.org/swift-6.3.2-release/"
            "ubuntu2204/swift-6.3.2-RELEASE/swift-6.3.2-RELEASE-ubuntu22.04.tar.gz",
            "swift_toolchain_signature_sha256: "
            "06fcd8d2f92d9d4b557d3f832efc26a5539f7238d8ed47e0ba4e409477286581",
            # The Swift 6.x release signing key, not the 5.x key.
            "swift_signing_fingerprint: 52BB7E3DE28A71BE22EC05FFEF80A866B47A981F",
            "runner: ubuntu-22.04",
            'os_version_id: "22.04"',
            "target_triple: x86_64-unknown-linux-gnu",
            'sqlite_version: "3.53.3"',
            "source_coverage: false",
        ):
            for entry in linux_swift6:
                self.assertIn(expected, entry)
        # The macOS-only gates stay off the Linux Swift 6 cell: they are keyed
        # to Swift 6.0, and this cell's series is 6.3.
        self.assertNotIn('swift_series: "6.0"', cell)

    def test_source_coverage_runs_once_inside_the_swift60_committed_cell(
        self,
    ) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertNotIn("\n  coverage:\n", workflow)
        self.assertNotIn("swiftql-coverage-run-2", workflow)
        compatibility = workflow.split("\n  compatibility:\n", maxsplit=1)[1]
        matrix = compatibility.split("\n    env:\n", maxsplit=1)[0]
        entries = matrix.split("\n          - name: ")[1:]
        coverage_cells = [
            entry for entry in entries if "source_coverage: true" in entry
        ]
        self.assertEqual(len(coverage_cells), 1)
        self.assertTrue(
            coverage_cells[0].startswith("Swift 6.0 / committed resolution\n")
        )
        self.assertEqual(matrix.count("source_coverage: false"), len(entries) - 1)

        # The coverage run replaces the plain full-suite run in that cell, so
        # the suite still runs exactly once per cell.
        self.assertIn(
            "      - name: Run full test suite\n"
            "        if: ${{ !matrix.source_coverage }}\n",
            compatibility,
        )
        self.assertIn(
            "        id: coverage-capture\n"
            "        if: ${{ matrix.source_coverage }}\n",
            compatibility,
        )
        self.assertIn(
            'scripts/ci/run-source-coverage.sh "$RUNNER_TEMP/swiftql-coverage"',
            compatibility,
        )
        self.assertIn(
            "scripts/ci/verify-source-coverage-reproducibility.sh",
            compatibility,
        )
        self.assertIn(
            "if: ${{ matrix.source_coverage && "
            "github.event_name != 'pull_request' }}",
            compatibility,
        )

    def test_xcode_free_gates_leave_the_longest_macos_cell(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        compatibility = workflow.split("\n  compatibility:\n", maxsplit=1)[1]

        playground_step = compatibility.split(
            "      - name: Check the Getting Started playground\n", maxsplit=1
        )[1].split("\n      - name: ", maxsplit=1)[0]
        # #133 removed the Swift 5.9 cells, so "the Linux committed cell" is
        # now unique without naming a series.
        self.assertIn(
            "if: ${{ matrix.platform == 'linux' && "
            "matrix.resolution == 'committed' }}",
            playground_step,
        )
        strict_step = compatibility.split(
            "      - name: Check complete strict concurrency\n", maxsplit=1
        )[1].split("\n      - name: ", maxsplit=1)[0]
        self.assertIn(
            "if: ${{ matrix.swift_series == '6.0' && "
            "matrix.resolution == 'clean' }}",
            strict_step,
        )

    def test_newest_series_also_runs_the_strict_concurrency_gate(self) -> None:
        # Issue #546: the compatibility job runs the gate on the pinned Swift
        # 6.0 support point only, where `#SendableMetatypes` does not exist
        # yet, so four first-party captures went unreported until a local run
        # on a newer compiler found them. The newest series runs the gate too.
        workflow = WORKFLOW.read_text(encoding="utf-8")
        swift_series = workflow.split("\n  swift-series:\n", maxsplit=1)[1].split(
            "\n  compatibility:\n", maxsplit=1
        )[0]
        matrix = swift_series.split("\n    env:\n", maxsplit=1)[0]

        # Exactly one cell carries the gate, and it is the newest series in
        # the matrix -- the last entry, which is the order the matrix lists.
        self.assertEqual(matrix.count("strict_concurrency: true"), 1)
        entries = matrix.split("\n          - swift_series: ")[1:]
        self.assertIn("strict_concurrency: true", entries[-1])

        def series(entry: str) -> tuple[int, ...]:
            version = re.match(r'"([\d.]+)"', entry).group(1)
            return tuple(int(part) for part in version.split("."))

        self.assertEqual(series(entries[-1]), max(series(entry) for entry in entries))

        strict_step = swift_series.split(
            "      - name: Check complete strict concurrency\n", maxsplit=1
        )[1].split("\n      - name: ", maxsplit=1)[0]
        self.assertIn("if: ${{ matrix.strict_concurrency }}", strict_step)
        self.assertIn("scripts/ci/check-strict-concurrency.sh", strict_step)

    def test_linux_surface_uses_opencombine_without_conditional_exclusion(self) -> None:
        # Issue #309 replaced the platform-split bridge (a `GRDBOpenCombineValuePublisher`
        # reachable only under `#if !canImport(Combine)`, hence its own coverage carve-out
        # below) with one universal adapter whose only platform-conditional lines are its
        # two `import` statements -- the demand/cancellation logic itself is identical and
        # exercised on every platform, so it needs no coverage exclusion of its own.
        manifest = (ROOT / "Package.swift").read_text(encoding="utf-8")
        bridge = (
            ROOT / "Sources/SwiftQL/XLAsyncStreamPublisher.swift"
        ).read_text(encoding="utf-8")
        coverage_config = (
            ROOT / "scripts/ci/source-coverage-config.json"
        ).read_text(encoding="utf-8")
        root_lockfile = (ROOT / "Package.resolved").read_bytes()
        downstream_lockfile = (
            ROOT / "IntegrationTests/Swift5Client/Package.resolved"
        ).read_bytes()

        self.assertIn(
            '.package(url: "https://github.com/OpenCombine/OpenCombine.git", '
            'from: "0.14.0")',
            manifest,
        )
        # Issue #669: OpenCombine is linked on Linux only. Every product
        # reference must carry the Linux platform condition, so no Apple build
        # compiles or links an OpenCombine module.
        product_references = re.findall(
            r'\.product\(name: "OpenCombine\w*", package: "OpenCombine"[^)]*\)',
            manifest,
        )
        self.assertTrue(product_references)
        for reference in product_references:
            self.assertIn(
                "condition: .when(platforms: [.linux])",
                reference,
            )
        # The committed lockfile keeps the tested 0.14.0 pin.
        self.assertIn(
            b'"location" : "https://github.com/OpenCombine/OpenCombine.git",\n'
            b'      "state" : {\n'
            b'        "revision" : "8576f0d579b27020beccbccc3ea6844f3ddfc2c2",\n'
            b'        "version" : "0.14.0"',
            root_lockfile,
        )
        self.assertIn("import OpenCombine", bridge)
        self.assertIn("remainingDemand", bridge)
        self.assertIn("demandWaiter", bridge)
        self.assertNotIn("XCTSkip", bridge)
        self.assertNotIn(
            "GRDBOpenCombineValuePublisher.swift",
            coverage_config,
        )
        self.assertEqual(downstream_lockfile, root_lockfile)

    def test_swift59_linux_surface_avoids_newer_foundation_url_apis(self) -> None:
        swift_sources = list((ROOT / "Sources").rglob("*.swift"))
        swift_sources.extend((ROOT / "Tests").rglob("*.swift"))
        source = "\n".join(
            path.read_text(encoding="utf-8") for path in swift_sources
        )

        self.assertNotIn(".path(percentEncoded:", source)
        self.assertNotIn(".appending(path:", source)
        self.assertNotIn("formatter.timeZone = .gmt", source)
        self.assertNotIn("import CryptoKit", source)

        benchmark_cli = (
            ROOT / "Benchmarks/Sources/SwiftQLBenchmarkCLI/main.swift"
        ).read_text(encoding="utf-8")
        self.assertIn("#if canImport(Darwin)", benchmark_cli)
        self.assertIn("#elseif canImport(Glibc)", benchmark_cli)

    def test_pull_request_runs_cancel_superseded_and_reduce_to_core_cells(
        self,
    ) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")

        self.assertIn(
            "concurrency:\n"
            "  group: swift-compatibility-${{ github.ref }}\n"
            "  cancel-in-progress: "
            "${{ github.event_name == 'pull_request' }}\n",
            workflow,
        )
        self.assertNotIn("cancel-in-progress: true", workflow)

        release_tooling = workflow.split("\n  release-tooling:\n", maxsplit=1)[1]
        swift_series = release_tooling.split("\n  swift-series:\n", maxsplit=1)[1]
        compatibility = swift_series.split(
            "\n  compatibility:\n", maxsplit=1
        )[1]
        release_tooling = release_tooling.split("\n  swift-series:\n", maxsplit=1)[0]
        swift_series = swift_series.split("\n  compatibility:\n", maxsplit=1)[0]

        # Source coverage is no longer a job of its own (#672); it runs inside
        # the compatibility job's Swift 6.0 committed cell, which pull
        # requests keep.
        self.assertNotIn("\n  coverage:\n", workflow)
        pull_request_skip = "if: ${{ github.event_name != 'pull_request' }}"
        self.assertIn(pull_request_skip, swift_series)
        self.assertNotIn(pull_request_skip, release_tooling)
        self.assertNotIn(pull_request_skip, compatibility)

        # Target membership needs no coverage run, so it runs in the
        # release-tooling job on pull requests instead of after the merge.
        membership_check = "python3 scripts/ci/check-source-target-membership.py"
        self.assertIn(membership_check, release_tooling)
        self.assertNotIn(membership_check, compatibility)

    def test_documentation_runs_cancel_superseded_pull_request_runs(
        self,
    ) -> None:
        workflow = DOCUMENTATION_WORKFLOW.read_text(encoding="utf-8")

        self.assertIn(
            "concurrency:\n"
            "  group: documentation-${{ github.ref }}\n"
            "  cancel-in-progress: "
            "${{ github.event_name == 'pull_request' }}\n",
            workflow,
        )
        self.assertNotIn("cancel-in-progress: true", workflow)
        self.assertIn(
            "concurrency:\n"
            "      group: github-pages\n"
            "      cancel-in-progress: false\n",
            workflow,
        )

    def test_compatibility_commands_use_selected_path_toolchain(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        compatibility = workflow.split("\n  compatibility:\n", maxsplit=1)[1]

        for command in (
            "swift package resolve",
            "swift test --filter XLCompatibilityReportTests",
            "swift run --skip-build swiftql-benchmark",
            "swift test --skip-build -v",
        ):
            self.assertIn(command, compatibility)
        self.assertNotIn("xcrun swift package resolve", compatibility)
        self.assertNotIn("xcrun swift run --skip-build swiftql-benchmark", compatibility)

    def test_documentation_builds_install_the_pinned_hugo_release(self) -> None:
        pin = (ROOT / "scripts/ci/hugo-version.sh").read_text(encoding="utf-8")
        self.assertRegex(pin, r"(?m)^SWIFTQL_HUGO_VERSION=\d+\.\d+\.\d+$")
        self.assertRegex(
            pin, r"(?m)^SWIFTQL_HUGO_DARWIN_UNIVERSAL_SHA256=[0-9a-f]{64}$"
        )

        make_docs = (ROOT / "make-docs.sh").read_text(encoding="utf-8")
        self.assertIn('. "$blog_source_root/scripts/ci/hugo-version.sh"', make_docs)
        self.assertIn(
            'blog_expected_hugo_version="hugo v$SWIFTQL_HUGO_VERSION"', make_docs
        )
        self.assertNotRegex(make_docs, r"hugo v\d")

        for workflow in (
            WORKFLOW,
            ROOT / ".github/workflows/documentation-build.yml",
        ):
            with self.subTest(workflow=workflow.name):
                text = workflow.read_text(encoding="utf-8")
                self.assertIn('scripts/ci/install-hugo.sh "$RUNNER_TEMP/hugo"', text)
                self.assertNotIn("brew install hugo", text)
                self.assertNotIn("brew upgrade hugo", text)


class HugoInstallTests(unittest.TestCase):
    # A copy of install-hugo.sh runs beside a test pin, with fake curl, uname,
    # and pkgutil commands, so the real script logic runs on any host without
    # the network or the real release asset.
    PACKAGE = b"fake hugo package\n"
    VERSION = "0.165.0"

    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory(
            prefix="swiftql-hugo-install."
        )
        self.root = Path(self.temporary_directory.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        scripts = self.root / "scripts"
        scripts.mkdir()
        self.script = scripts / "install-hugo.sh"
        shutil.copy2(ROOT / "scripts/ci/install-hugo.sh", self.script)
        self.pin = scripts / "hugo-version.sh"
        self.write_pin(hashlib.sha256(self.PACKAGE).hexdigest())
        self.fake_hugo = self.root / "fake-hugo"
        self.write_fake_hugo(
            f"hugo v{self.VERSION}-0123456789abcdef+extended+withdeploy "
            "darwin/arm64 BuildDate=2026-08-01T00:00:00Z VendorInfo=gohugoio"
        )
        self.install_directory = self.root / "hugo"
        self.github_path = self.root / "github-path"
        self.install_command(
            "uname",
            r"""
            #!/bin/sh
            printf 'Darwin\n'
            """,
        )
        # Serves the package only for the exact versioned release asset URL, so
        # a wrong tag or asset name fails the download instead of passing.
        expected_url = (
            "https://github.com/gohugoio/hugo/releases/download/"
            f"v{self.VERSION}/hugo_extended_withdeploy_{self.VERSION}"
            "_darwin-universal.pkg"
        )
        self.install_command(
            "curl",
            rf"""
            #!/bin/sh
            output=""
            url=""
            while [ "$#" -gt 0 ]; do
              case "$1" in
                --output) output="$2"; shift 2 ;;
                --retry) shift 2 ;;
                -*) shift ;;
                *) url="$1"; shift ;;
              esac
            done
            if [ -z "$output" ] || [ "$url" != '{expected_url}' ]; then
              printf 'unexpected curl request: %s\n' "$url" >&2
              exit 22
            fi
            printf 'fake hugo package\n' > "$output"
            """,
        )
        # Like `pkgutil --expand-full PACKAGE DESTINATION`, this refuses an
        # existing destination and nests the payload under a component package.
        self.install_command(
            "pkgutil",
            r"""
            #!/bin/sh
            if [ "$#" -ne 3 ] || [ "$1" != --expand-full ] || [ -e "$3" ]; then
              exit 64
            fi
            mkdir -p "$3/hugo.pkg/Payload"
            cp -p "$FAKE_HUGO" "$3/hugo.pkg/Payload/hugo"
            """,
        )

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def install_command(self, name: str, source: str) -> None:
        path = self.bin / name
        path.write_text(textwrap.dedent(source).lstrip(), encoding="utf-8")
        path.chmod(path.stat().st_mode | stat.S_IXUSR)

    def write_pin(self, sha256: str) -> None:
        self.pin.write_text(
            f"SWIFTQL_HUGO_VERSION={self.VERSION}\n"
            f"SWIFTQL_HUGO_DARWIN_UNIVERSAL_SHA256={sha256}\n",
            encoding="utf-8",
        )

    def write_fake_hugo(self, version_output: str) -> None:
        self.fake_hugo.write_text(
            f"#!/bin/sh\nprintf '%s\\n' '{version_output}'\n", encoding="utf-8"
        )
        self.fake_hugo.chmod(0o755)

    def run_install(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        environment = os.environ.copy()
        environment.update(
            {
                "PATH": f"{self.bin}:/usr/bin:/bin",
                "GITHUB_PATH": str(self.github_path),
                "FAKE_HUGO": str(self.fake_hugo),
            }
        )
        return subprocess.run(
            [str(self.script), *arguments],
            cwd=self.root,
            env=environment,
            text=True,
            capture_output=True,
            check=False,
        )

    def assert_nothing_installed(self) -> None:
        self.assertFalse((self.install_directory / "hugo").exists())
        self.assertFalse(self.github_path.exists())

    def test_installs_the_verified_binary_and_prepends_github_path(self) -> None:
        result = self.run_install(str(self.install_directory))

        self.assertEqual(result.returncode, 0, result.stderr)
        installed = self.install_directory / "hugo"
        self.assertTrue(os.access(installed, os.X_OK))
        self.assertEqual(installed.read_bytes(), self.fake_hugo.read_bytes())
        self.assertIn(f"hugo v{self.VERSION}-", result.stdout)
        self.assertEqual(
            self.github_path.read_text(encoding="utf-8"),
            f"{self.install_directory.resolve()}\n",
        )

    def test_checksum_mismatch_fails_closed(self) -> None:
        self.write_pin("0" * 64)

        result = self.run_install(str(self.install_directory))

        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("has SHA-256", result.stderr)
        self.assert_nothing_installed()

    def test_version_mismatch_fails_closed(self) -> None:
        for version_output in (
            "hugo v0.166.0+extended+withdeploy darwin/arm64 VendorInfo=Homebrew",
            f"hugo v{self.VERSION}1-0123456789abcdef+extended darwin/arm64",
        ):
            with self.subTest(version_output=version_output):
                self.write_fake_hugo(version_output)

                result = self.run_install(str(self.install_directory))

                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertIn(f"expected hugo v{self.VERSION}", result.stderr)
                self.assert_nothing_installed()

    def test_missing_install_directory_is_a_usage_error(self) -> None:
        result = self.run_install()

        self.assertEqual(result.returncode, 64, result.stderr)
        self.assertIn("usage:", result.stderr)


class CompatibilityEnvironmentTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory(
            prefix="swiftql-compatibility-environment."
        )
        self.root = Path(self.temporary_directory.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.developer_dir = self.root / "Xcode_16.2.app/Contents/Developer"
        self.developer_dir.mkdir(parents=True)
        self.install_fake_commands(swift_version="5.9.2")

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def install_command(self, name: str, source: str) -> None:
        path = self.bin / name
        path.write_text(textwrap.dedent(source).lstrip(), encoding="utf-8")
        path.chmod(path.stat().st_mode | stat.S_IXUSR)

    def install_fake_commands(self, swift_version: str) -> None:
        self.install_command(
            "xcodebuild",
            """
            #!/bin/sh
            printf 'Xcode 16.2\nBuild version 16C5032a\n'
            """,
        )
        self.install_command(
            "xcrun",
            """
            #!/bin/sh
            case "$*" in
              "--sdk macosx --show-sdk-version") printf '15.2\n' ;;
              "--sdk macosx --show-sdk-path") printf '/fake/MacOSX15.2.sdk\n' ;;
              *) printf 'unexpected xcrun arguments: %s\n' "$*" >&2; exit 64 ;;
            esac
            """,
        )
        self.install_command(
            "swift",
            f"""
            #!/bin/sh
            if [ "$*" = "package tools-version" ]; then
              printf '5.9.0\n'
            else
              printf 'Swift version {swift_version} (swift-{swift_version}-RELEASE)\n'
              printf 'Target: arm64-apple-macosx15.0\n'
            fi
            """,
        )
        self.install_command(
            "swiftc",
            """
            #!/bin/sh
            printf '{"target":{"triple":"arm64-apple-macosx15.0"}}\n'
            """,
        )
        self.install_command(
            "xcode-select",
            f"""
            #!/bin/sh
            printf '%s\n' '{self.developer_dir}'
            """,
        )
        self.install_command(
            "uname",
            """
            #!/bin/sh
            printf 'arm64\n'
            """,
        )
        self.install_command(
            "sw_vers",
            """
            #!/bin/sh
            printf 'ProductName:\tmacOS\nProductVersion:\t15.7\nBuildVersion:\t24G207\n'
            """,
        )

    def run_check(self, **overrides: str) -> subprocess.CompletedProcess[str]:
        environment = os.environ.copy()
        environment.update(
            {
                "PATH": f"{self.bin}:/usr/bin:/bin",
                "DEVELOPER_DIR": str(self.developer_dir),
                "EXPECTED_XCODE_VERSION": "16.2",
                "EXPECTED_XCODE_BUILD": "16C5032a",
                "EXPECTED_SWIFT_SERIES": "5.9",
                "EXPECTED_SWIFT_VERSION": "5.9.2",
                "EXPECTED_SWIFT_COMMAND_MODE": "path",
                "EXPECTED_SDK_VERSION": "15.2",
                "EXPECTED_DEVELOPER_DIR": str(self.developer_dir),
                "EXPECTED_IMAGE_OS": "macos15",
                "EXPECTED_ARCHITECTURE": "arm64",
                "ImageOS": "macos15",
                "ImageVersion": "fixture.1",
            }
        )
        environment.update(overrides)
        return subprocess.run(
            ["/bin/bash", str(ENVIRONMENT_CHECK)],
            cwd=ROOT,
            env=environment,
            text=True,
            capture_output=True,
            check=False,
        )

    def run_linux_check(self, **overrides: str) -> subprocess.CompletedProcess[str]:
        os_release = self.root / "os-release"
        os_release.write_text('ID=ubuntu\nVERSION_ID="22.04"\n', encoding="utf-8")
        self.install_command(
            "swift",
            """
            #!/bin/sh
            if [ "$*" = "package tools-version" ]; then
              printf '5.9.0\n'
            else
              printf 'Swift version 5.9.2 (swift-5.9.2-RELEASE)\n'
              printf 'Target: x86_64-unknown-linux-gnu\n'
            fi
            """,
        )
        self.install_command(
            "swiftc",
            """
            #!/bin/sh
            printf '{"target": {"triple": "x86_64-unknown-linux-gnu"}}\n'
            """,
        )
        self.install_command(
            "uname",
            """
            #!/bin/sh
            printf 'x86_64\n'
            """,
        )

        environment = os.environ.copy()
        environment.update(
            {
                "PATH": f"{self.bin}:/usr/bin:/bin",
                "EXPECTED_PLATFORM": "linux",
                "EXPECTED_SWIFT_SERIES": "5.9",
                "EXPECTED_SWIFT_VERSION": "5.9.2",
                "EXPECTED_SWIFT_COMMAND_MODE": "path",
                "EXPECTED_IMAGE_OS": "ubuntu22",
                "EXPECTED_ARCHITECTURE": "x86_64",
                "EXPECTED_OS_ID": "ubuntu",
                "EXPECTED_OS_VERSION_ID": "22.04",
                "EXPECTED_OS_RELEASE_FILE": str(os_release),
                "EXPECTED_TARGET_TRIPLE": "x86_64-unknown-linux-gnu",
                "ImageOS": "ubuntu22",
                "ImageVersion": "fixture.1",
            }
        )
        environment.update(overrides)
        return subprocess.run(
            ["/bin/bash", str(ENVIRONMENT_CHECK)],
            cwd=ROOT,
            env=environment,
            text=True,
            capture_output=True,
            check=False,
        )

    def test_exact_path_toolchain_environment_passes(self) -> None:
        result = self.run_check()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Swift command mode: path", result.stdout)
        self.assertIn("Swift version 5.9.2", result.stdout)

    def test_patch_drift_fails_closed(self) -> None:
        self.install_fake_commands(swift_version="5.9.1")
        result = self.run_check()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not exactly version 5.9.2", result.stderr)

    def test_runner_family_drift_fails_closed(self) -> None:
        result = self.run_check(ImageOS="macos16")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("ImageOS is 'macos16'; expected 'macos15'", result.stderr)

    def test_architecture_drift_fails_closed(self) -> None:
        result = self.run_check(EXPECTED_ARCHITECTURE="x86_64")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("architecture is 'arm64'; expected 'x86_64'", result.stderr)

    def test_exact_linux_environment_passes(self) -> None:
        result = self.run_linux_check()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Compatibility platform: linux", result.stdout)
        self.assertIn("Linux distribution: ubuntu 22.04", result.stdout)

    def test_linux_distribution_drift_fails_closed(self) -> None:
        result = self.run_linux_check(EXPECTED_OS_VERSION_ID="24.04")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("VERSION_ID is '22.04'; expected '24.04'", result.stderr)


if __name__ == "__main__":
    unittest.main()
