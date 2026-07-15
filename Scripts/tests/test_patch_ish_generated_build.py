from __future__ import annotations

import pathlib
import subprocess
import sys
import tempfile
import unittest


SCRIPT = pathlib.Path(__file__).parents[1] / "patch-ish-generated-build.py"


class PatchISHGeneratedBuildTests(unittest.TestCase):
    def test_routes_vdso_build_through_pinned_compiler(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = pathlib.Path(temporary_directory)
            build_ninja = root / "build.ninja"
            wrapper = root / "clang-wrapper"
            build_ninja.write_text(
                "rule c_COMPILER\n"
                " command = clang $ARGS\n"
                "build vdso/arm64/libvdso.so.elf: CUSTOM_COMMAND vdso.S | /opt/clang\n"
                " COMMAND = /opt/clang -target aarch64-linux-gnu -o "
                "vdso/arm64/libvdso.so.elf vdso.S\n"
                "build libish.a.p/kernel_task.c.o: c_COMPILER ../../kernel/task.c\n",
                encoding="utf-8",
            )
            wrapper.write_text("#!/bin/sh\n", encoding="utf-8")
            subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--build-ninja",
                    str(build_ninja),
                    "--clang-wrapper",
                    str(wrapper),
                ],
                check=True,
                capture_output=True,
                text=True,
            )

            generated_build = build_ninja.read_text(encoding="utf-8")
            self.assertIn(f"COMMAND = {wrapper.resolve()} -target", generated_build)
            self.assertIn("../../kernel/task.c", generated_build)


if __name__ == "__main__":
    unittest.main()
