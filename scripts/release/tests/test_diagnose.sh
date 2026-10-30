#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
TEST_HOME=$(mktemp -d "${TMPDIR:-/tmp}/swifttype-diagnose-tests.XXXXXX")
trap 'rm -rf "${TEST_HOME}"' EXIT

before=$(/usr/bin/find "${TEST_HOME}" -mindepth 1 -print)
output=$(HOME="${TEST_HOME}" "${PROJECT_DIR}/scripts/diagnose.sh")
after=$(/usr/bin/find "${TEST_HOME}" -mindepth 1 -print)

[[ "${output}" == *"SmartType read-only diagnostic summary"* ]]
[[ "${output}" == *"Installed bundle:            missing"* ]]
[[ "${output}" == *"This command does not modify input sources, services, or registrations."* ]]
[[ "${before}" == "${after}" ]]

printf 'PASS: diagnostic summary handles a missing installation without modifying its test home.\n'
