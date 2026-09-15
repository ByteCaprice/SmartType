#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/swifttype-input-source-tests.XXXXXX")
trap 'rm -rf "${TEST_DIR}"' EXIT

# Compile only the diagnostic; never build/register/relaunch the input method.
xcrun swiftc -module-cache-path "${TEST_DIR}/ModuleCache" \
    "${PROJECT_DIR}/scripts/diagnose-input-sources.swift" -o "${TEST_DIR}/diagnose"

output=$("${TEST_DIR}/diagnose" --help)
[[ "${output}" == *"Usage:"* ]]
[[ "${output}" != *"Current source:"* ]]

expect_invalid() {
    local status=0
    "${TEST_DIR}/diagnose" "$@" > "${TEST_DIR}/stdout" 2> "${TEST_DIR}/stderr" || status=$?
    [[ "${status}" -eq 2 ]]
    [[ ! -s "${TEST_DIR}/stdout" ]]
    grep -q 'Usage:' "${TEST_DIR}/stderr"
}

expect_invalid --watch
expect_invalid --watch 0
expect_invalid --watch -1
expect_invalid --watch 301
expect_invalid --watch 1.5
expect_invalid --watch invalid
expect_invalid --watch 1 extra
expect_invalid --unknown

output=$("${TEST_DIR}/diagnose")
[[ "${output}" == *"SwiftType read-only input-source diagnostic"* ]]
[[ "${output}" == *"No input sources, preferences, registrations, or services are changed."* ]]
[[ "${output}" == *"Current source:"* ]]
[[ "${output}" == *"Last-used ASCII source:"* ]]
[[ "${output}" == *"English-language lookup:"* ]]
[[ "${output}" == *"NOT a guaranteed Caps Lock destination"* ]]
[[ "${output}" != *"Watching for"* ]]

# Read-only observation of the live session; do not synthesize or select sources.
output=$("${TEST_DIR}/diagnose" --watch 1)
[[ "${output}" == *"Watching for 1 seconds."* ]]
[[ "${output}" == *"Watch finished."* ]]

printf 'PASS: input-source diagnostic help, 8 invalid arguments, snapshot, and bounded watch.\n'
