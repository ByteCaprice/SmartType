#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../pkg-scripts/install-common.sh
source "${SCRIPT_DIR}/../pkg-scripts/install-common.sh"

TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/swifttype-installer-tests.XXXXXX")
trap 'rm -rf "${TEST_ROOT}"' EXIT
OWNER_GROUP="$(id -un):$(id -gn)"
PASSED=0

make_bundle() {
    local bundle="$1" marker="$2"
    mkdir -p "${bundle}/Contents/MacOS" "${bundle}/Contents/Resources"
    cat > "${bundle}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.matthew.inputmethod.SwiftType</string>
<key>CFBundleExecutable</key><string>SwiftType</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
    cp /usr/bin/true "${bundle}/Contents/MacOS/SwiftType"
    printf '%s\n' "${marker}" > "${bundle}/Contents/Resources/marker"
    codesign --force --deep --sign - "${bundle}" >/dev/null 2>&1
}

assert_file_contains() {
    local file="$1" expected="$2"
    [[ -f "${file}" ]] || { printf 'FAIL: missing %s\n' "${file}" >&2; exit 1; }
    [[ "$(cat "${file}")" == "${expected}" ]] || {
        printf 'FAIL: expected %s in %s\n' "${expected}" "${file}" >&2
        exit 1
    }
}

run_test() {
    local name="$1"
    shift
    "$@"
    PASSED=$((PASSED + 1))
    printf 'PASS: %s\n' "${name}"
}

test_missing_payload_preserves_old_install() {
    local root="${TEST_ROOT}/missing"
    local destination="${root}/Input Methods/SwiftType.app"
    make_bundle "${destination}" old
    if swifttype_transactional_install "${root}/missing.app" "${destination}" "${OWNER_GROUP}"; then
        printf 'FAIL: missing payload unexpectedly succeeded\n' >&2
        return 1
    fi
    assert_file_contains "${destination}/Contents/Resources/marker" old
}

test_success_replaces_old_install() {
    local root="${TEST_ROOT}/success"
    local source="${root}/source/SwiftType.app"
    local destination="${root}/Input Methods/SwiftType.app"
    make_bundle "${source}" new
    make_bundle "${destination}" old
    swifttype_transactional_install "${source}" "${destination}" "${OWNER_GROUP}"
    assert_file_contains "${destination}/Contents/Resources/marker" new
    [[ -z "$(find "${root}/Input Methods" -maxdepth 1 -name '.SwiftType.*' -print -quit)" ]]
}

test_post_swap_failure_restores_old_install() {
    local root="${TEST_ROOT}/rollback"
    local source="${root}/source/SwiftType.app"
    local destination="${root}/Input Methods/SwiftType.app"
    make_bundle "${source}" new
    make_bundle "${destination}" old
    swifttype_post_swap_hook() { return 1; }
    if swifttype_transactional_install "${source}" "${destination}" "${OWNER_GROUP}"; then
        printf 'FAIL: injected post-swap failure unexpectedly succeeded\n' >&2
        return 1
    fi
    swifttype_post_swap_hook() { return 0; }
    assert_file_contains "${destination}/Contents/Resources/marker" old
    [[ -z "$(find "${root}/Input Methods" -maxdepth 1 -name '.SwiftType.*' -print -quit)" ]]
}

test_invalid_identifier_preserves_old_install() {
    local root="${TEST_ROOT}/identifier"
    local source="${root}/source/SwiftType.app"
    local destination="${root}/Input Methods/SwiftType.app"
    make_bundle "${source}" new
    make_bundle "${destination}" old
    /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.example.Invalid' "${source}/Contents/Info.plist"
    if swifttype_transactional_install "${source}" "${destination}" "${OWNER_GROUP}"; then
        printf 'FAIL: invalid bundle identifier unexpectedly succeeded\n' >&2
        return 1
    fi
    assert_file_contains "${destination}/Contents/Resources/marker" old
}

test_corrupt_signature_preserves_old_install() {
    local root="${TEST_ROOT}/signature"
    local source="${root}/source/SwiftType.app"
    local destination="${root}/Input Methods/SwiftType.app"
    make_bundle "${source}" new
    make_bundle "${destination}" old
    printf 'tampered\n' >> "${source}/Contents/Resources/marker"
    if swifttype_transactional_install "${source}" "${destination}" "${OWNER_GROUP}"; then
        printf 'FAIL: corrupt signature unexpectedly succeeded\n' >&2
        return 1
    fi
    assert_file_contains "${destination}/Contents/Resources/marker" old
}

test_signal_during_swap_restores_old_install() {
    local root="${TEST_ROOT}/signal"
    local source="${root}/source/SwiftType.app"
    local destination="${root}/Input Methods/SwiftType.app"
    make_bundle "${source}" new
    make_bundle "${destination}" old
    swifttype_post_swap_hook() {
        /bin/sh -c '/bin/kill -TERM "$PPID"'
        /bin/sleep 1
        return 1
    }
    if swifttype_transactional_install "${source}" "${destination}" "${OWNER_GROUP}"; then
        printf 'FAIL: interrupted swap unexpectedly succeeded\n' >&2
        return 1
    fi
    swifttype_post_swap_hook() { return 0; }
    assert_file_contains "${destination}/Contents/Resources/marker" old
}

test_failure_without_previous_install_leaves_destination_absent() {
    local root="${TEST_ROOT}/new-install-rollback"
    local source="${root}/source/SwiftType.app"
    local destination="${root}/Input Methods/SwiftType.app"
    make_bundle "${source}" new
    swifttype_post_swap_hook() { return 1; }
    if swifttype_transactional_install "${source}" "${destination}" "${OWNER_GROUP}"; then
        printf 'FAIL: injected new-install failure unexpectedly succeeded\n' >&2
        return 1
    fi
    swifttype_post_swap_hook() { return 0; }
    [[ ! -e "${destination}" ]]
}

test_unwritable_destination_preserves_old_install() {
    local root="${TEST_ROOT}/unwritable"
    local source="${root}/source/SwiftType.app"
    local destination_dir="${root}/Input Methods"
    local destination="${destination_dir}/SwiftType.app"
    make_bundle "${source}" new
    make_bundle "${destination}" old
    chmod 500 "${destination_dir}"
    if swifttype_transactional_install "${source}" "${destination}" "${OWNER_GROUP}"; then
        chmod 700 "${destination_dir}"
        printf 'FAIL: unwritable destination unexpectedly succeeded\n' >&2
        return 1
    fi
    chmod 700 "${destination_dir}"
    assert_file_contains "${destination}/Contents/Resources/marker" old
}

test_destination_directory_symlink_is_rejected() {
    local root="${TEST_ROOT}/directory-symlink"
    local source="${root}/source/SwiftType.app"
    local real_directory="${root}/real-input-methods"
    local linked_directory="${root}/Input Methods"
    make_bundle "${source}" new
    mkdir -p "${real_directory}"
    ln -s "${real_directory}" "${linked_directory}"
    if swifttype_transactional_install "${source}" "${linked_directory}/SwiftType.app" "${OWNER_GROUP}"; then
        printf 'FAIL: symlink destination directory unexpectedly succeeded\n' >&2
        return 1
    fi
    [[ ! -e "${real_directory}/SwiftType.app" ]]
}

test_destination_symlink_is_rejected() {
    local root="${TEST_ROOT}/symlink"
    local source="${root}/source/SwiftType.app"
    local real_destination="${root}/elsewhere/SwiftType.app"
    local destination="${root}/Input Methods/SwiftType.app"
    make_bundle "${source}" new
    make_bundle "${real_destination}" old
    mkdir -p "$(dirname "${destination}")"
    ln -s "${real_destination}" "${destination}"
    if swifttype_transactional_install "${source}" "${destination}" "${OWNER_GROUP}"; then
        printf 'FAIL: symlink destination unexpectedly succeeded\n' >&2
        return 1
    fi
    [[ -L "${destination}" ]]
    assert_file_contains "${real_destination}/Contents/Resources/marker" old
}

run_test 'missing payload preserves old installation' test_missing_payload_preserves_old_install
run_test 'successful replacement removes temporary artifacts' test_success_replaces_old_install
run_test 'post-swap failure restores old installation' test_post_swap_failure_restores_old_install
run_test 'invalid bundle identifier preserves old installation' test_invalid_identifier_preserves_old_install
run_test 'corrupt signature preserves old installation' test_corrupt_signature_preserves_old_install
run_test 'signal interruption restores old installation' test_signal_during_swap_restores_old_install
run_test 'failed first installation leaves destination absent' test_failure_without_previous_install_leaves_destination_absent
run_test 'unwritable destination preserves old installation' test_unwritable_destination_preserves_old_install
run_test 'symlink destination directory is rejected' test_destination_directory_symlink_is_rejected
run_test 'symlink destination is rejected' test_destination_symlink_is_rejected

printf '%d installer tests passed.\n' "${PASSED}"
