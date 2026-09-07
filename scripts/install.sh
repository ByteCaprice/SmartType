#!/usr/bin/env bash

set -euo pipefail

APP_NAME="SwiftType"
CONFIGURATION="${CONFIGURATION:-Release}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/build/${CONFIGURATION}"
BUILD_VERSION="$(date -u +%Y%m%d%H%M%S)"
APP_PATH="${BUILD_DIR}/${APP_NAME}.app"
DEBUG_APP_PATH="${PROJECT_DIR}/build/Debug/${APP_NAME}.app"
INPUT_METHODS_DIR="${HOME}/Library/Input Methods"
DESTINATION="${INPUT_METHODS_DIR}/${APP_NAME}.app"
STAGING="${INPUT_METHODS_DIR}/.${APP_NAME}.app.installing"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

# A stale Debug copy with the same bundle ID can shadow the installed input source.
if [[ "${CONFIGURATION}" != "Debug" ]]; then
    rm -rf "${DEBUG_APP_PATH}"
fi

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
    xcodebuild \
    -project "${PROJECT_DIR}/SwiftType.xcodeproj" \
    -scheme "SwiftType" \
    -configuration "${CONFIGURATION}" \
    CONFIGURATION_BUILD_DIR="${BUILD_DIR}" \
    CURRENT_PROJECT_VERSION="${BUILD_VERSION}" \
    CLANG_COVERAGE_MAPPING=NO \
    CLANG_ENABLE_CODE_COVERAGE=NO \
    ENABLE_CODE_COVERAGE=NO \
    REGISTER_WITH_LAUNCH_SERVICES=NO \
    build

codesign --verify --deep --strict "${APP_PATH}"

mkdir -p "${INPUT_METHODS_DIR}"
rm -rf "${STAGING}"
ditto "${APP_PATH}" "${STAGING}"
codesign --verify --deep --strict "${STAGING}"

killall "${APP_NAME}" 2>/dev/null || true
if [[ -d "${DESTINATION}" ]]; then
    rsync -a --delete "${STAGING}/" "${DESTINATION}/"
    rm -rf "${STAGING}"
else
    mv "${STAGING}" "${DESTINATION}"
fi
touch "${INPUT_METHODS_DIR}"
"${LSREGISTER}" -f -R -trusted "${DESTINATION}"
killall imklaunchagent 2>/dev/null || true
killall TextInputMenuAgent 2>/dev/null || true
killall -9 TextInputSwitcher 2>/dev/null || true
killall -9 CursorUIViewService 2>/dev/null || true
codesign --verify --deep --strict "${DESTINATION}"

printf 'SwiftType installed to %s\n' "${DESTINATION}"
printf 'Add it once in System Settings > Keyboard > Text Input, then log out and back in.\n'
printf 'Quit and reopen apps that were running during this install so they reconnect to SwiftType.\n'
