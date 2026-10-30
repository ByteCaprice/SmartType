#!/usr/bin/env bash

# Shared transactional installer used by the development installer and the PKG.
# Callers must enable their preferred strict-shell settings before sourcing it.

swifttype_validate_bundle() {
    local bundle="$1"
    local expected_identifier="com.matthew.inputmethod.SwiftType"
    local identifier

    [[ -d "${bundle}" && ! -L "${bundle}" ]] || {
        printf 'ERROR: SmartType bundle is missing or is a symlink: %s\n' "${bundle}" >&2
        return 1
    }
    [[ -x "${bundle}/Contents/MacOS/SwiftType" ]] || {
        printf 'ERROR: SmartType executable is missing from: %s\n' "${bundle}" >&2
        return 1
    }
    identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
        "${bundle}/Contents/Info.plist" 2>/dev/null) || {
        printf 'ERROR: SmartType bundle metadata is unreadable: %s\n' "${bundle}" >&2
        return 1
    }
    [[ "${identifier}" == "${expected_identifier}" ]] || {
        printf 'ERROR: Unexpected bundle identifier %s in %s\n' "${identifier}" "${bundle}" >&2
        return 1
    }
    /usr/bin/codesign --verify --deep --strict "${bundle}" || {
        printf 'ERROR: SmartType signature verification failed: %s\n' "${bundle}" >&2
        return 1
    }
}

# Tests may override this function after sourcing the file to inject a failure at
# the only point where the previous installation has already been moved aside.
swifttype_post_swap_hook() {
    return 0
}

swifttype_transactional_install() (
    local source_bundle="$1"
    local destination="$2"
    local owner_group="$3"
    local destination_dir work_dir candidate backup had_previous=0 swap_complete=0 rollback_failed=0

    destination_dir=$(/usr/bin/dirname "${destination}")
    swifttype_validate_bundle "${source_bundle}" || return 1

    /bin/mkdir -p "${destination_dir}" || return 1
    if [[ -L "${destination_dir}" || -L "${destination}" ]]; then
        printf 'ERROR: Refusing to replace an installation through a symlink: %s\n' "${destination}" >&2
        return 1
    fi
    /usr/sbin/chown "${owner_group}" "${destination_dir}" || return 1

    work_dir=$(/usr/bin/mktemp -d "${destination_dir}/.SwiftType.installing.XXXXXX") || return 1
    candidate="${work_dir}/SwiftType.app"
    backup="${work_dir}/PreviousSwiftType.app"

    swifttype_rollback_install() {
        local status=$?
        trap - EXIT HUP INT TERM
        if (( swap_complete )); then
            /bin/rm -rf "${destination}" 2>/dev/null || rollback_failed=1
        fi
        if (( had_previous )) && [[ -e "${backup}" || -L "${backup}" ]]; then
            if [[ ! -e "${destination}" && ! -L "${destination}" ]]; then
                /bin/mv "${backup}" "${destination}" 2>/dev/null || rollback_failed=1
            else
                rollback_failed=1
            fi
        fi
        if [[ ! -e "${backup}" && ! -L "${backup}" ]]; then
            /bin/rm -rf "${work_dir}" 2>/dev/null || true
        fi
        if (( status != 0 )); then
            if [[ -e "${backup}" || -L "${backup}" ]]; then
                printf 'ERROR: Installation failed; recovery needs attention. The previous installation remains at %s.\n' \
                    "${backup}" >&2
            elif (( rollback_failed )); then
                printf 'ERROR: Installation failed and cleanup was incomplete; inspect %s before retrying.\n' \
                    "${destination}" >&2
            else
                printf 'ERROR: Installation failed; the previous SmartType installation was preserved.\n' >&2
            fi
        fi
        exit "${status}"
    }
    trap swifttype_rollback_install EXIT
    trap 'exit 1' HUP INT TERM

    /usr/bin/ditto "${source_bundle}" "${candidate}" || return 1
    /usr/sbin/chown -R "${owner_group}" "${candidate}" || return 1
    swifttype_validate_bundle "${candidate}" || return 1

    if [[ -e "${destination}" ]]; then
        had_previous=1
        /bin/mv "${destination}" "${backup}" || return 1
    fi
    swap_complete=1
    /bin/mv "${candidate}" "${destination}" || return 1

    swifttype_validate_bundle "${destination}" || return 1
    swifttype_post_swap_hook || return 1

    # The installed bundle is now fully validated. Commit before best-effort
    # cleanup so a cleanup error can never remove the working replacement.
    swap_complete=0
    trap - EXIT HUP INT TERM
    /bin/rm -rf "${backup}" "${work_dir}" || {
        printf 'WARNING: SmartType was installed, but temporary backup cleanup failed.\n' >&2
    }
)
