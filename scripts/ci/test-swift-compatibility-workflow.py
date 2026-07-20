#!/usr/bin/env python3

"""Fail-closed fixtures for the pinned Swift compatibility workflow."""

from __future__ import annotations

import os
import stat
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github/workflows/swift.yml"
ENVIRONMENT_CHECK = ROOT / "scripts/ci/check-compatibility-environment.sh"


class SwiftCompatibilityWorkflowTests(unittest.TestCase):
    def test_swift59_cells_use_exact_toolchain_on_ubuntu22(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        compatibility = workflow.split("\n  compatibility:\n", maxsplit=1)[1]
        matrix = compatibility.split("\n    env:\n", maxsplit=1)[0]

        self.assertNotIn("runner: macos-14", matrix)
        self.assertEqual(matrix.count('swift_series: "5.9"'), 2)
        self.assertEqual(matrix.count('swift_version: "5.9.2"'), 2)
        self.assertEqual(matrix.count("swift_command_mode: path"), 2)
        self.assertEqual(matrix.count("runner: ubuntu-22.04"), 2)
        self.assertEqual(matrix.count("\n            runner: macos-15\n"), 2)
        self.assertEqual(matrix.count("platform: linux"), 2)
        self.assertEqual(matrix.count("platform: macos"), 2)
        self.assertEqual(matrix.count("image_os: ubuntu22"), 2)
        self.assertEqual(matrix.count("image_os: macos15"), 2)
        self.assertEqual(matrix.count("architecture: x86_64"), 2)
        self.assertEqual(matrix.count("architecture: arm64"), 2)

        self.assertNotIn("swift-actions/setup-swift", compatibility)
        self.assertIn(
            "if: ${{ matrix.platform == 'linux' }}", compatibility
        )
        self.assertIn(
            "https://download.swift.org/swift-5.9.2-release/ubuntu2204/"
            "swift-5.9.2-RELEASE/"
            "swift-5.9.2-RELEASE-ubuntu22.04.tar.gz",
            compatibility,
        )
        self.assertIn("SWIFT_TOOLCHAIN_SIGNATURE_URL", compatibility)
        self.assertIn(
            "SWIFT_TOOLCHAIN_SIGNATURE_SHA256: "
            "325657c10c0a917cb0126aaf2ce0fe1c72bb9bf14657a89f82330839003959ed",
            compatibility,
        )
        self.assertIn(
            "SWIFT_SIGNING_FINGERPRINT: "
            "A62AE125BBBFBB96A6E042EC925CC1CCED3D1561",
            compatibility,
        )
        self.assertIn("https://keyserver.ubuntu.com/pks/lookup", compatibility)
        self.assertIn("pinned-fingerprint fallback", compatibility)
        self.assertIn("download_verified()", compatibility)
        self.assertIn("sha256sum --check --status", compatibility)
        self.assertIn("gpg --batch", compatibility)
        self.assertIn("[GNUPG:] VALIDSIG", compatibility)
        self.assertIn("-DGRDBCUSTOMSQLITE", compatibility)
        self.assertIn("SWIFT_EXEC=", compatibility)
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

    def test_linux_surface_uses_opencombine_without_conditional_exclusion(self) -> None:
        manifest = (ROOT / "Package.swift").read_text(encoding="utf-8")
        bridge = (
            ROOT / "Sources/SwiftQL/GRDBOpenCombineValuePublisher.swift"
        ).read_text(encoding="utf-8")

        self.assertIn(
            '.package(url: "https://github.com/OpenCombine/OpenCombine.git", '
            'exact: "0.14.0")',
            manifest,
        )
        self.assertIn("case waiting", bridge)
        self.assertIn("remainingDemand", bridge)
        self.assertNotIn("XCTSkip", bridge)

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
