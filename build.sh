#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
OUTPUT_ROOT="${1:-${SCRIPT_DIR}/dist}"
APP_DIR="${OUTPUT_ROOT}/Private Prompter.app"
BUILD_DIR="${SCRIPT_DIR}/.build/manual"
MODULE_CACHE="${SCRIPT_DIR}/.build/ModuleCache"

if [[ -n "${PRIVATE_PROMPTER_SDK:-}" ]]; then
    SDK_PATH="${PRIVATE_PROMPTER_SDK}"
elif [[ -d "/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk" ]]; then
    # The current Mac has a newer compiler paired with a partially updated 26.x SDK.
    # The 15.4 SDK is complete and supports every API used by this macOS 15+ app.
    SDK_PATH="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
else
    SDK_PATH="$(xcrun --show-sdk-path)"
fi

cd "${SCRIPT_DIR}"
mkdir -p "${BUILD_DIR}" "${MODULE_CACHE}" "${OUTPUT_ROOT}"

core_sources=(Sources/PrompterCore/*.swift)
app_sources=(Sources/PrivatePrompter/*.swift)

swiftc \
    -sdk "${SDK_PATH}" \
    -module-cache-path "${MODULE_CACHE}" \
    -target arm64-apple-macosx15.0 \
    -parse-as-library \
    -emit-library -static -emit-module \
    -module-name PrompterCore \
    "${core_sources[@]}" \
    -emit-module-path "${BUILD_DIR}/PrompterCore.swiftmodule" \
    -o "${BUILD_DIR}/libPrompterCore.a"

swiftc \
    -sdk "${SDK_PATH}" \
    -module-cache-path "${MODULE_CACHE}" \
    -target arm64-apple-macosx15.0 \
    -swift-version 5 \
    -I "${BUILD_DIR}" \
    -L "${BUILD_DIR}" \
    -lPrompterCore \
    "${app_sources[@]}" \
    -framework AppKit \
    -framework Speech \
    -framework AVFoundation \
    -o "${BUILD_DIR}/PrivatePrompter"

rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"
cp "${BUILD_DIR}/PrivatePrompter" "${APP_DIR}/Contents/MacOS/PrivatePrompter"
cp "Resources/Info.plist" "${APP_DIR}/Contents/Info.plist"
xattr -cr "${APP_DIR}" 2>/dev/null || true
codesign --force --deep --sign - "${APP_DIR}"
xattr -cr "${APP_DIR}" 2>/dev/null || true

echo "Built: ${APP_DIR}"
