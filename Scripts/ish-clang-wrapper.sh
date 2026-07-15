#!/bin/bash

set -euo pipefail

OUTPUT_PATH=""
PREVIOUS_ARGUMENT=""
IS_LINUX_ARM64=0

for argument in "$@"; do
    if [[ "${PREVIOUS_ARGUMENT}" == "-o" ]]; then
        OUTPUT_PATH="${argument}"
    fi
    if [[ "${argument}" == "aarch64-linux-gnu" ]]; then
        IS_LINUX_ARM64=1
    fi
    PREVIOUS_ARGUMENT="${argument}"
done

if [[ ${IS_LINUX_ARM64} -eq 1 && "${OUTPUT_PATH}" == *"libvdso.so.elf" ]]; then
    if [[ -z "${OMNIBOT_PREBUILT_VDSO:-}" || ! -f "${OMNIBOT_PREBUILT_VDSO}" ]]; then
        echo "error: OMNIBOT_PREBUILT_VDSO is missing" >&2
        exit 1
    fi
    cp "${OMNIBOT_PREBUILT_VDSO}" "${OUTPUT_PATH}"
    exit 0
fi

exec /usr/bin/xcrun clang "$@"
