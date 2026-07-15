#!/bin/bash

set -euo pipefail

ISH_SOURCE_ROOT="${PROJECT_DIR}/Vendor/ish-arm64"
ISH_BUILD_ROOT="${TARGET_TEMP_DIR}/ish-meson"
TOOLS_ROOT="${PROJECT_TEMP_DIR}/ish-build-tools"
WRAPPER_ROOT="${PROJECT_TEMP_DIR}/ish-build-wrappers"
PREBUILT_VDSO="${PROJECT_DIR}/RuntimeSupport/ish/arm64/libvdso.so.elf"
PATCH_BUILD_SCRIPT="${PROJECT_DIR}/Scripts/patch-ish-generated-build.py"
FINGERPRINT_FILE="${ISH_BUILD_ROOT}/.omnibot-build-fingerprint"
EXPECTED_VDSO_SHA256="ef9cef6b3e5537071e741958799b17cfb27732731b04df26a38cde965ab87fef"

if [[ ! -f "${ISH_SOURCE_ROOT}/meson.build" ]]; then
    echo "error: ish-arm64 submodule is missing. Run: git submodule update --init --recursive"
    exit 1
fi

if [[ "${CURRENT_ARCH:-arm64}" != "arm64" && "${NATIVE_ARCH_ACTUAL:-arm64}" != "arm64" ]]; then
    echo "error: ish-arm64 requires an Apple Silicon arm64 build host"
    exit 1
fi

if [[ ! -f "${PREBUILT_VDSO}" ]]; then
    echo "error: missing prebuilt ARM64 guest VDSO at ${PREBUILT_VDSO}"
    exit 1
fi
PREBUILT_VDSO_SHA256="$(shasum -a 256 "${PREBUILT_VDSO}" | awk '{print $1}')"
if [[ "${PREBUILT_VDSO_SHA256}" != "${EXPECTED_VDSO_SHA256}" ]]; then
    echo "error: ARM64 guest VDSO checksum mismatch"
    exit 1
fi

ISH_SOURCE_REVISION="$(git -C "${ISH_SOURCE_ROOT}" rev-parse HEAD)"
BUILD_SCRIPT_SHA256="$(shasum -a 256 \
    "${PROJECT_DIR}/Scripts/build-ish-core.sh" \
    "${PROJECT_DIR}/Scripts/ish-clang-wrapper.sh" \
    "${PATCH_BUILD_SCRIPT}" | shasum -a 256 | awk '{print $1}')"
CLANG_VERSION="$(/usr/bin/xcrun clang --version | head -1)"
BUILD_FINGERPRINT="$(printf '%s\n' \
    "source=${ISH_SOURCE_REVISION}" \
    "scripts=${BUILD_SCRIPT_SHA256}" \
    "sdk=${SDKROOT:-unknown}" \
    "sdk_name=${SDK_NAME:-unknown}" \
    "platform=${PLATFORM_NAME:-unknown}" \
    "effective_platform=${EFFECTIVE_PLATFORM_NAME:-unknown}" \
    "arch=${CURRENT_ARCH:-unknown}" \
    "configuration=${CONFIGURATION:-unknown}" \
    "xcode=${XCODE_VERSION_ACTUAL:-unknown}" \
    "clang=${CLANG_VERSION}" | shasum -a 256 | awk '{print $1}')"

if [[ ! -f "${FINGERPRINT_FILE}" ]] || [[ "$(cat "${FINGERPRINT_FILE}")" != "${BUILD_FINGERPRINT}" ]]; then
    rm -rf "${ISH_BUILD_ROOT}"
fi

if [[ ! -x "${TOOLS_ROOT}/bin/meson" || ! -x "${TOOLS_ROOT}/bin/ninja" ]]; then
    rm -rf "${TOOLS_ROOT}"
    /usr/bin/python3 -m venv "${TOOLS_ROOT}"
    "${TOOLS_ROOT}/bin/python" -m pip install \
        --disable-pip-version-check \
        --quiet \
        "meson==1.8.3" \
        "ninja==1.11.1.4"
fi

MESON="${TOOLS_ROOT}/bin/meson"
NINJA="${TOOLS_ROOT}/bin/ninja"
CROSS_FILE="${ISH_BUILD_ROOT}/cross.txt"
mkdir -p "${WRAPPER_ROOT}"
cp "${PROJECT_DIR}/Scripts/ish-clang-wrapper.sh" "${WRAPPER_ROOT}/clang"
chmod +x "${WRAPPER_ROOT}/clang"
export OMNIBOT_PREBUILT_VDSO="${PREBUILT_VDSO}"
export PATH="${WRAPPER_ROOT}:${TOOLS_ROOT}/bin:${PATH}"

mkdir -p "${ISH_BUILD_ROOT}"

if ! "${MESON}" introspect "${ISH_BUILD_ROOT}" --buildoptions >/dev/null 2>&1; then
    cat > "${CROSS_FILE}" <<EOF
[binaries]
c = 'clang'
ar = 'ar'

[host_machine]
system = 'darwin'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'

[built-in options]
c_args = ['-arch', 'arm64']

[properties]
needs_exe_wrapper = true
EOF

    CC_FOR_BUILD="env -u SDKROOT -u IPHONEOS_DEPLOYMENT_TARGET -u MACOSX_DEPLOYMENT_TARGET xcrun clang" \
        "${MESON}" setup \
        "${ISH_BUILD_ROOT}" \
        "${ISH_SOURCE_ROOT}" \
        --cross-file "${CROSS_FILE}" \
        -Dguest_arch=arm64 \
        -Dkernel=ish \
        -Dengine=asbestos
fi

BUILD_TYPE=debug
if [[ "${CONFIGURATION}" == "Release" ]]; then
    BUILD_TYPE=debugoptimized
fi

"${MESON}" configure "${ISH_BUILD_ROOT}" \
    -Dbuildtype="${BUILD_TYPE}" \
    -Db_ndebug=false \
    -Db_sanitize=none \
    -Dguest_arch=arm64 \
    -Dkernel=ish \
    -Dengine=asbestos

mkdir -p "${ISH_BUILD_ROOT}/vdso/arm64"
"${TOOLS_ROOT}/bin/python" "${PATCH_BUILD_SCRIPT}" \
    --build-ninja "${ISH_BUILD_ROOT}/build.ninja" \
    --clang-wrapper "${WRAPPER_ROOT}/clang"

if [[ -f "${ISH_BUILD_ROOT}/vdso/arm64/libvdso.so.elf" ]] && \
   [[ "$(shasum -a 256 "${ISH_BUILD_ROOT}/vdso/arm64/libvdso.so.elf" | awk '{print $1}')" != "${EXPECTED_VDSO_SHA256}" ]]; then
    rm -f "${ISH_BUILD_ROOT}/vdso/arm64/libvdso.so.elf"
fi

"${NINJA}" -C "${ISH_BUILD_ROOT}" libish.a libish_emu.a libfakefs.a

ACTUAL_VDSO="${ISH_BUILD_ROOT}/vdso/arm64/libvdso.so.elf"
if [[ ! -f "${ACTUAL_VDSO}" ]]; then
    echo "error: iSH build did not produce the ARM64 guest VDSO"
    exit 1
fi
ACTUAL_VDSO_SHA256="$(shasum -a 256 "${ACTUAL_VDSO}" | awk '{print $1}')"
if [[ "${ACTUAL_VDSO_SHA256}" != "${EXPECTED_VDSO_SHA256}" ]]; then
    echo "error: generated ARM64 guest VDSO bypassed the pinned wrapper"
    exit 1
fi

for library in libish.a libish_emu.a libfakefs.a; do
    if [[ ! -f "${ISH_BUILD_ROOT}/${library}" ]]; then
        echo "error: missing iSH build product ${ISH_BUILD_ROOT}/${library}"
        exit 1
    fi
done

printf '%s' "${BUILD_FINGERPRINT}" > "${FINGERPRINT_FILE}"
