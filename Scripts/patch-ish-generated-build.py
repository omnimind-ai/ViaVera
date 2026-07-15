#!/usr/bin/env python3
"""Route the generated ARM64 guest VDSO build through the pinned wrapper."""

from __future__ import annotations

import argparse
import pathlib
import re
import shlex


def command_path(path: pathlib.Path) -> str:
    return shlex.quote(str(path)).replace("$", "$$")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--build-ninja", required=True, type=pathlib.Path)
    parser.add_argument("--clang-wrapper", required=True, type=pathlib.Path)
    args = parser.parse_args()

    original_build_text = args.build_ninja.read_text(encoding="utf-8")
    build_text = original_build_text

    vdso_pattern = re.compile(
        r"^(\s*COMMAND = )\S+(?= -target aarch64-linux-gnu .*"
        r"-o vdso/arm64/libvdso\.so\.elf(?:\s|$))",
        re.MULTILINE,
    )
    build_text, vdso_count = vdso_pattern.subn(
        lambda match: match.group(1) + command_path(args.clang_wrapper.resolve()),
        build_text,
    )
    if vdso_count != 1:
        raise SystemExit(f"expected exactly one ARM64 VDSO command, found {vdso_count}")

    if build_text != original_build_text:
        args.build_ninja.write_text(build_text, encoding="utf-8")
    print("Patched generated iSH build: pinned ARM64 VDSO compiler")


if __name__ == "__main__":
    main()
