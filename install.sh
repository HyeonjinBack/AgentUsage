#!/bin/bash
set -euo pipefail

if [ "$(uname -s)" != Darwin ] || [ "$(uname -m)" != arm64 ]; then
    echo "This release requires an Apple Silicon Mac." >&2; exit 1
fi
major="$(sw_vers -productVersion | cut -d. -f1)"
if [ "$major" -lt 14 ]; then echo "macOS 14 or later is required." >&2; exit 1; fi

asset=AgentUsage-macos-arm64.zip
base=https://github.com/HyeonjinBack/AgentUsage/releases/latest/download
work="$(mktemp -d "${TMPDIR:-/tmp}/agentusage-install.XXXXXX")"
trap 'rm -rf "$work"' EXIT
if [ "${1:-}" = --local-release ] && [ "$#" -eq 2 ]; then
    cp "$2/$asset" "$work/$asset"; cp "$2/SHA256SUMS" "$work/SHA256SUMS"
elif [ "$#" -eq 0 ]; then
    for name in "$asset" SHA256SUMS; do
        /usr/bin/curl --proto '=https' --tlsv1.2 --fail --silent --show-error --location "$base/$name" -o "$work/$name"
    done
else
    echo "Usage: bash install.sh [--local-release DIRECTORY]" >&2; exit 1
fi

expected="$(awk -v asset="$asset" '$2 == asset && length($1) == 64 && $1 !~ /[^0-9a-f]/ { print $1; n++ } END { if(n != 1) exit 1 }' "$work/SHA256SUMS")"
actual="$(shasum -a 256 "$work/$asset" | awk '{print $1}')"
if [ "$actual" != "$expected" ]; then echo "Checksum mismatch. Nothing was installed." >&2; exit 1; fi

/usr/bin/unzip -Z -1 "$work/$asset" | awk '
    /^\// || /(^|\/)\.\.(\/|$)/ || !/^AgentMeter\.app\// { bad=1 }
    END { exit bad }
'
mkdir "$work/staging"
/usr/bin/ditto -x -k "$work/$asset" "$work/staging"
app="$work/staging/AgentMeter.app"
/usr/bin/codesign --verify --deep --strict "$app"
/usr/bin/lipo -verify_arch arm64 "$app/Contents/MacOS/AgentMeter"
identifier="$(/usr/bin/plutil -extract CFBundleIdentifier raw "$app/Contents/Info.plist")"
if [ "$identifier" != dev.agentmeter.local ]; then echo "Unexpected app bundle." >&2; exit 1; fi

destination="${AGENTUSAGE_INSTALL_DIR:-$HOME/Applications}"
mkdir -p "$destination"
target="$destination/AgentMeter.app"
if [ -e "$target" ]; then
    backup="$destination/AgentMeter.backup.$(date +%Y%m%d%H%M%S).$$.app"
    mv "$target" "$backup"
    echo "Previous version preserved: $backup"
fi
if ! mv "$app" "$target"; then
    if [ -n "${backup:-}" ]; then mv "$backup" "$target"; fi
    echo "Installation failed." >&2; exit 1
fi
echo "Installed: $target"
echo "Run: open \"$target\""
echo "This preview has an ad-hoc signature and is not Apple-notarized."
