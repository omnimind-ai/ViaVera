# ARM64 guest VDSO

`libvdso.so.elf` is the AArch64 Linux VDSO embedded by the pinned
`XuYouo/ish-arm64` guest runtime. Keeping the 2.9 KB product in the repository
means normal Xcode builds do not need Homebrew LLVM/LLD merely to link this one
guest ELF file.

`Scripts/build-ish-core.sh` patches only the generated Ninja graph so the VDSO
custom target always runs through `Scripts/ish-clang-wrapper.sh`, then verifies
the produced ELF against the SHA below. The same generated-build patch also
applies the pinned iSH task/thread-start safety fixes without modifying the
submodule.

- Source inputs: `Vendor/ish-arm64/vdso/arm64/{vdso.S,vdso.c,vdso.lds}`
- SHA-256: `ef9cef6b3e5537071e741958799b17cfb27732731b04df26a38cde965ab87fef`
- License: same GPL terms as the pinned iSH source

Rebuild command (LLVM 22.1.8 and LLD 22.1.8):

```bash
PATH="/opt/homebrew/opt/lld/bin:$PATH" \
  /opt/homebrew/opt/llvm/bin/clang \
  -target aarch64-linux-gnu -fuse-ld=lld \
  -o RuntimeSupport/ish/arm64/libvdso.so.elf \
  Vendor/ish-arm64/vdso/arm64/vdso.S \
  Vendor/ish-arm64/vdso/arm64/vdso.c \
  -nostdlib \
  -Wl,-T,Vendor/ish-arm64/vdso/arm64/vdso.lds \
  -Wl,--hash-style,sysv \
  -shared -fPIC -ffreestanding
```
