#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
root="$PWD"
repository=HyeonjinBack/AgentUsage
version=v0.2.0

gh auth status --hostname github.com
if gh release view "$version" --repo "$repository" >/dev/null 2>&1; then
    echo "Release $version already exists; refusing to replace it." >&2; exit 1
fi
swift test
bash Scripts/build-app.sh
python3 Scripts/package-release.py
python3 Scripts/privacy-audit.py

checkout="$(mktemp -d "${TMPDIR:-/tmp}/AgentUsage-publish.XXXXXX")"
trap 'rm -rf "$checkout"' EXIT
git -c 'credential.helper=!gh auth git-credential' clone "https://github.com/$repository.git" "$checkout/repo"
cd "$checkout/repo"
if git show-ref --verify --quiet refs/remotes/origin/main; then
    git checkout -B main origin/main
else
    git checkout -B main
fi
files=(Package.swift README.md LICENSE .gitignore install.sh RELEASE_NOTES.md Sources Tests Scripts .github docs/privacy.md docs/releasing.md)
for item in "${files[@]}"; do
    mkdir -p "$(dirname "$item")"
    if [ -d "$root/$item" ]; then
        /usr/bin/ditto --norsrc --noextattr "$root/$item" "$item"
    else
        cp "$root/$item" "$item"
    fi
done
# Public GitHub noreply identity: no personal email is added to commit metadata.
git config user.name HyeonjinBack
git config user.email 88670321+HyeonjinBack@users.noreply.github.com
git add -- "${files[@]}"
git diff --cached --check
if ! git diff --cached --quiet; then
    git commit -m "Publish standalone quota monitor and terminal installer"
fi
git -c 'credential.helper=!gh auth git-credential' push origin HEAD:main
gh release create "$version" \
    "$root/dist/release/AgentUsage-macos-arm64.zip" \
    "$root/dist/release/install.sh" \
    "$root/dist/release/SHA256SUMS" \
    --repo "$repository" --target "$(git rev-parse HEAD)" --latest \
    --title "AgentUsage $version" --notes-file "$root/RELEASE_NOTES.md"
gh release view "$version" --repo "$repository" --json url,assets
