#!/usr/bin/env python3

import os
from pathlib import Path, PurePosixPath
import shutil
import sys
import tarfile


def fail(message: str) -> None:
    raise SystemExit(f"error: {message}")


def canonical_member_name(name: str) -> str:
    path = PurePosixPath(name)
    if path.is_absolute() or ".." in path.parts:
        fail(f"archive contains an unsafe path: {name}")
    parts = [part for part in path.parts if part not in ("", ".")]
    if not parts:
        return ""
    canonical = PurePosixPath(*parts).as_posix()
    if "\n" in canonical or "\r" in canonical:
        fail(f"archive path contains a line break: {name!r}")
    return canonical


def extract_archive(archive_path: Path, output_directory: Path) -> None:
    output_directory.mkdir(parents=True, exist_ok=True)
    seen = set()
    with tarfile.open(archive_path, mode="r:") as archive:
        for member in archive.getmembers():
            name = canonical_member_name(member.name)
            if not name:
                if not member.isdir():
                    fail("archive root entry is not a directory")
                continue
            if name in seen:
                fail(f"archive contains a duplicate path: {name}")
            seen.add(name)
            if not (member.isdir() or member.isfile()):
                fail(f"archive contains a non-regular entry: {name}")

            destination = output_directory.joinpath(*PurePosixPath(name).parts)
            destination.parent.mkdir(parents=True, exist_ok=True)
            if member.isdir():
                destination.mkdir(exist_ok=True)
                os.chmod(destination, 0o755)
                continue

            source = archive.extractfile(member)
            if source is None:
                fail(f"archive file has no readable bytes: {name}")
            try:
                with destination.open("xb") as output:
                    shutil.copyfileobj(source, output)
            finally:
                source.close()
            os.chmod(destination, 0o644)


def create_archive(source_directory: Path, archive_path: Path) -> None:
    if not source_directory.is_dir() or source_directory.is_symlink():
        fail(f"archive source is not a safe directory: {source_directory}")
    archive_path.parent.mkdir(parents=True, exist_ok=True)
    source_real = source_directory.resolve()
    destination_real = archive_path.parent.resolve() / archive_path.name
    if os.path.commonpath((str(source_real), str(destination_real))) == str(
        source_real
    ):
        fail("archive output must be outside its source directory")
    if archive_path.exists() or archive_path.is_symlink():
        fail(f"archive output already exists: {archive_path}")

    entries = sorted(
        source_directory.rglob("*"),
        key=lambda path: path.relative_to(source_directory).as_posix().encode("utf-8"),
    )
    with tarfile.open(archive_path, mode="w:", format=tarfile.PAX_FORMAT) as archive:
        for path in entries:
            relative_name = path.relative_to(source_directory).as_posix()
            canonical_member_name(relative_name)
            metadata = path.lstat()
            if path.is_symlink() or not (path.is_dir() or path.is_file()):
                fail(f"archive source contains a non-regular entry: {relative_name}")
            if path.is_file() and metadata.st_nlink != 1:
                fail(f"archive source contains a hard-linked file: {relative_name}")

            info = tarfile.TarInfo(
                relative_name + ("/" if path.is_dir() else "")
            )
            info.uid = 0
            info.gid = 0
            info.uname = "root"
            info.gname = "root"
            info.mtime = 0
            info.pax_headers = {}
            if path.is_dir():
                info.type = tarfile.DIRTYPE
                info.mode = 0o755
                info.size = 0
                archive.addfile(info)
            else:
                info.type = tarfile.REGTYPE
                info.mode = 0o644
                info.size = metadata.st_size
                with path.open("rb") as contents:
                    archive.addfile(info, contents)


def main() -> None:
    if len(sys.argv) != 4 or sys.argv[1] not in ("create", "extract"):
        fail(f"usage: {sys.argv[0]} create|extract INPUT OUTPUT")
    operation = sys.argv[1]
    source = Path(sys.argv[2])
    destination = Path(sys.argv[3])
    if operation == "create":
        create_archive(source, destination)
    else:
        extract_archive(source, destination)


if __name__ == "__main__":
    main()
