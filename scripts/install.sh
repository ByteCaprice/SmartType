#!/usr/bin/env bash

set -euo pipefail

APP_NAME="SwiftType"
CONFIGURATION="${CONFIGURATION:-Release}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/build/${CONFIGURATION}"
BUILD_VERSION="$(date -u +%Y%m%d%H%M%S)"
APP_PATH="${BUILD_DIR}/${APP_NAME}.app"
INPUT_METHODS_DIR="${HOME}/Library/Input Methods"
DESTINATION="${INPUT_METHODS_DIR}/${APP_NAME}.app"
STAGING="${INPUT_METHODS_DIR}/.${APP_NAME}.app.installing"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
# shellcheck source=release/pkg-scripts/install-common.sh
source "${SCRIPT_DIR}/release/pkg-scripts/install-common.sh"

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

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
    build

codesign --verify --deep --strict "${APP_PATH}"

mkdir -p "${INPUT_METHODS_DIR}"
rm -rf "${STAGING}"
ditto "${APP_PATH}" "${STAGING}"
codesign --verify --deep --strict "${STAGING}"

killall "${APP_NAME}" 2>/dev/null || true
swifttype_transactional_install \
    "${STAGING}" \
    "${DESTINATION}" \
    "$(id -un):$(id -gn)"
rm -rf "${STAGING}"
touch "${INPUT_METHODS_DIR}"
"${LSREGISTER}" -f -R -trusted "${DESTINATION}"
killall TextInputMenuAgent 2>/dev/null || true
killall TextInputSwitcher 2>/dev/null || true
codesign --verify --deep --strict "${DESTINATION}"

printf 'SmartType installed to %s\n' "${DESTINATION}"
printf 'Add SmartType once in System Settings > Keyboard > Text Input, then log out and back in.\n'
printf 'Quit and reopen apps that were running during this install so they reconnect to SmartType.\n'
