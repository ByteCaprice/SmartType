#!/usr/bin/env bash

set -euo pipefail

APP_NAME="SwiftType"
BUNDLE_ID="com.matthew.inputmethod.SwiftType"
INSTALL_PATH="${HOME}/Library/Input Methods/${APP_NAME}.app"
INFO_PLIST="${INSTALL_PATH}/Contents/Info.plist"

redact_home() {
    local value="$1"
    if [[ "${value}" == "${HOME}"* ]]; then
        printf '~%s\n' "${value#"${HOME}"}"
    else
        printf '%s\n' "${value}"
    fi
}

print_plist_value() {
    local key="$1" label="$2" value
    value=$(/usr/bin/plutil -extract "${key}" raw -o - "${INFO_PLIST}" 2>/dev/null || true)
    printf '%-28s %s\n' "${label}:" "${value:-missing}"
}

printf 'SwiftType read-only diagnostic summary\n'
printf '%s\n' '====================================='
printf 'This command does not modify input sources, services, or registrations.\n\n'

printf '%-28s %s\n' 'Expected installation:' '~/Library/Input Methods/SwiftType.app'
if [[ -d "${INSTALL_PATH}" ]]; then
    printf '%-28s %s\n' 'Installed bundle:' 'present'
    print_plist_value CFBundleIdentifier 'Bundle identifier'
    print_plist_value CFBundleShortVersionString 'Version'
    print_plist_value CFBundleVersion 'Build'
    print_plist_value InputMethodConnectionName 'Connection name'
    print_plist_value InputMethodServerControllerClass 'Controller class'
    print_plist_value TICapsLockLanguageSwitchCapable 'Caps Lock capable'
    print_plist_value TISInputSourceID 'Input source ID'
    print_plist_value TISIntendedLanguage 'Intended language'

    if /usr/bin/codesign --verify --deep --strict "${INSTALL_PATH}" >/dev/null 2>&1; then
        printf '%-28s %s\n' 'Code signature:' 'valid'
    else
        printf '%-28s %s\n' 'Code signature:' 'INVALID'
    fi
    architectures=$(/usr/bin/lipo -archs "${INSTALL_PATH}/Contents/MacOS/${APP_NAME}" 2>/dev/null || true)
    printf '%-28s %s\n' 'Architectures:' "${architectures:-unknown}"
else
    printf '%-28s %s\n' 'Installed bundle:' 'missing'
fi

if /usr/bin/pgrep -f "/${APP_NAME}.app/Contents/MacOS/${APP_NAME}$" >/dev/null 2>&1; then
    printf '%-28s %s\n' 'Running process:' 'yes'
else
    printf '%-28s %s\n' 'Running process:' 'no'
fi

if /usr/bin/defaults read com.apple.HIToolbox AppleEnabledInputSources 2>/dev/null \
    | /usr/bin/grep -q "${BUNDLE_ID}"; then
    printf '%-28s %s\n' 'Enabled-source preference:' 'detected'
else
    printf '%-28s %s\n' 'Enabled-source preference:' 'not exposed in readable defaults'
fi

printf '\nClient routing\n'
printf '%s\n' '--------------'
printf '%-28s %s\n' 'Inline:' 'TextEdit, Spotlight, Safari, Edge, native/default clients'
printf '%-28s %s\n' 'Transparent prediction:' 'Chrome/Chromium plus WeCom and DingTalk compatibility commits'
printf '%-28s %s\n' 'Direct input:' 'VS Code printable text; commands remain app-owned'
printf '%-28s %s\n' 'Passthrough:' 'Native terminal families'

custom_clients=$(/usr/bin/defaults read "${BUNDLE_ID}" transparentPredictionBundleIdentifiers 2>/dev/null || true)
custom_direct_clients=$(/usr/bin/defaults read "${BUNDLE_ID}" directInputBundleIdentifiers 2>/dev/null || true)
custom_priming_clients=$(/usr/bin/defaults read "${BUNDLE_ID}" markedTextPrimingBundleIdentifiers 2>/dev/null || true)
printf '%-28s %s\n' 'Custom transparent clients:' "${custom_clients:-none}"
printf '%-28s %s\n' 'Custom direct-input clients:' "${custom_direct_clients:-none}"
printf '%-28s %s\n' 'Custom priming clients:' "${custom_priming_clients:-none}"

printf '\nDiscoverable bundles with the same identifier\n'
printf '%s\n' '---------------------------------------------'
found=0
while IFS= read -r path; do
    [[ -n "${path}" ]] || continue
    found=1
    redact_home "${path}"
done < <(/usr/bin/mdfind "kMDItemCFBundleIdentifier == '${BUNDLE_ID}'" 2>/dev/null || true)
if (( found == 0 )); then
    printf 'none found by Spotlight metadata\n'
fi

printf '\nShare this summary only after reviewing the displayed paths. No typed or document text is collected.\n'
