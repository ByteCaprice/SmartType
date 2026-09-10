#!/usr/bin/env bash
# scripts/release/release.sh — Build SwiftType and package it into a
# distributable PKG installer.
#
# Usage:
#   ./scripts/release/release.sh [version]
#
# Produces:  dist/SwiftType-<version>.pkg
# Installs:  ~/Library/Input Methods/SwiftType.app  (no admin required)
#
# Requirements: Xcode command-line tools (xcodebuild, codesign, pkgbuild)
# No Apple Developer account needed — uses ad-hoc signing.

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
APP_NAME="SwiftType"
SCHEME="SwiftType"
VERSION="${1:-$(TZ=UTC0 date +"%Y.%m.%d.%H%M%S")}"  # Auto-generates UTC timestamp if no arg given
BUNDLE_ID="com.matthew.inputmethod.SwiftType"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/build/Release"
DIST_DIR="${PROJECT_DIR}/dist"
PKG_ROOT="${PROJECT_DIR}/build/pkg_root"
PKG_SCRIPTS="${PROJECT_DIR}/build/pkg_scripts"
COMPONENT_PLIST="${PROJECT_DIR}/build/pkg_components.plist"
# Staging path on the install target — must match --install-location below.
# installd does not expose $INSTALL_DEST to scripts, so we hardcode this in both places.
STAGING_DIR="/private/tmp/swifttype_pkg_payload"
PKG_NAME="${APP_NAME}-${VERSION}.pkg"
PKG_OUT="${DIST_DIR}/${PKG_NAME}"
# ── Helpers ───────────────────────────────────────────────────────────────────
info()  { echo "  ▸ $*"; }
step()  { echo; echo "▶ $*"; }
die()   { echo "✗ ERROR: $*" >&2; exit 1; }

# ── Step 1: Sanity checks ─────────────────────────────────────────────────────
step "Checking tools"
for cmd in xcodebuild codesign pkgbuild; do
    command -v "$cmd" >/dev/null 2>&1 || die "'$cmd' not found. Install Xcode command-line tools."
done
info "All required tools found."

# ── Step 2: Clean old artifacts ───────────────────────────────────────────────
step "Cleaning previous build artifacts"
# A previous failed install may leave root-owned files; fix permissions first.
chmod -R u+w "${PROJECT_DIR}/build" 2>/dev/null || true
rm -rf "${PROJECT_DIR}/build" "${PKG_OUT}"
mkdir -p "${BUILD_DIR}" "${DIST_DIR}" "${PKG_ROOT}" "${PKG_SCRIPTS}"
touch "${PROJECT_DIR}/build/.metadata_never_index"
info "Cleaned."

# ── Step 3: Build Release ─────────────────────────────────────────────────────
step "Building ${APP_NAME} (Release)"
# Use ad-hoc identity (-) so Xcode signs the app binary in one pass.
xcodebuild \
    -project "${PROJECT_DIR}/SwiftType.xcodeproj" \
    -scheme "${SCHEME}" \
    -configuration Release \
    -derivedDataPath "${PROJECT_DIR}/build/DerivedData" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="-" \
    CONFIGURATION_BUILD_DIR="${BUILD_DIR}" \
    CLANG_COVERAGE_MAPPING=NO \
    CLANG_ENABLE_CODE_COVERAGE=NO \
    ENABLE_CODE_COVERAGE=NO \
    ONLY_ACTIVE_ARCH=NO \
    build

# Confirm the .app was produced
APP_PATH="${BUILD_DIR}/${APP_NAME}.app"
[[ -d "${APP_PATH}" ]] || die ".app not found at ${APP_PATH}. Check xcodebuild output above."
info "Built: ${APP_PATH}"

# ── Step 4: Stamp version into app bundle ────────────────────────────────────
# Override the project defaults with the release version.
step "Setting version to ${VERSION}"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${APP_PATH}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VERSION}" "${APP_PATH}/Contents/Info.plist"
info "Version stamped."

# Re-sign after modifying the plist (invalidates the previous signature).
codesign --force --sign - --deep "${APP_PATH}"
info "Re-signed."

# ── Step 5: Verify signing ────────────────────────────────────────────────────
step "Verifying signature"
if codesign --verify --deep --strict "${APP_PATH}"; then
    info "Signature verified."
else
    die "Signature verification failed."
fi

# ── Step 6: Stage PKG payload ─────────────────────────────────────────────────
step "Staging PKG payload"
cp -R "${APP_PATH}" "${PKG_ROOT}/${APP_NAME}.app"
info "Staged."

# ── Step 7: Disable bundle relocation ────────────────────────────────────────
step "Configuring bundle options"
# pkgbuild records the original build path and will "relocate" the bundle to
# any matching path on the install target. Disabling relocation ensures the
# payload always lands at STAGING_DIR, where the postinstall expects it.
pkgbuild --analyze --root "${PKG_ROOT}" "${COMPONENT_PLIST}"
/usr/libexec/PlistBuddy -c "Set :0:BundleIsRelocatable false" "${COMPONENT_PLIST}"
info "Relocation disabled."

# ── Step 8: Write installer scripts ───────────────────────────────────────────
step "Writing installer scripts"

# Keep the package scripts as checked-in, independently testable files. The
# preinstall is deliberately non-destructive; postinstall validates and swaps
# the user-level bundle transactionally.
cp "${SCRIPT_DIR}/pkg-scripts/preinstall" "${PKG_SCRIPTS}/preinstall"
cp "${SCRIPT_DIR}/pkg-scripts/postinstall" "${PKG_SCRIPTS}/postinstall"
cp "${SCRIPT_DIR}/pkg-scripts/install-common.sh" "${PKG_SCRIPTS}/install-common.sh"
chmod +x "${PKG_SCRIPTS}/preinstall" "${PKG_SCRIPTS}/postinstall"

info "Scripts written."

# ── Step 9: Build PKG ─────────────────────────────────────────────────────────
step "Building PKG → ${PKG_NAME}"
pkgbuild \
    --root "${PKG_ROOT}" \
    --component-plist "${COMPONENT_PLIST}" \
    --scripts "${PKG_SCRIPTS}" \
    --identifier "${BUNDLE_ID}" \
    --version "${VERSION}" \
    --ownership recommended \
    --install-location "${STAGING_DIR}" \
    "${PKG_OUT}"

# ── Step 10: Clean up build staging ──────────────────────────────────────────
rm -rf "${PKG_ROOT}" "${PKG_SCRIPTS}" "${COMPONENT_PLIST}"

# ── Done ──────────────────────────────────────────────────────────────────────
echo
echo "✓ PKG ready: ${PKG_OUT}"
echo "  Size: $(du -sh "${PKG_OUT}" | cut -f1)"
echo
echo "Distribute ${PKG_NAME} to other Macs."
