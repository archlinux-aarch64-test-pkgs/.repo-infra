#!/bin/bash
set -euo pipefail

ORG="archlinux-aarch64-test-pkgs"
PACKAGES_FILE="config/packages.json"

echo "==> Fetching all pkg-* repos from org $ORG ..."
all_repos=$(gh api --paginate "orgs/$ORG/repos?per_page=100" \
    --jq '.[] | select(.archived == false) | .name' | grep '^pkg-' | sort)

if [[ -z "$all_repos" ]]; then
    echo "No pkg-* repos found in $ORG"
    echo "added=0" >> "$GITHUB_OUTPUT"
    exit 0
fi

registered_repos=$(jq -r '.packages[].repo' "$PACKAGES_FILE" | sort)

new_repos=$(comm -23 <(echo "$all_repos") <(echo "$registered_repos")) || true

if [[ -z "$new_repos" ]]; then
    echo "All pkg-* repos are already registered."
    echo "added=0" >> "$GITHUB_OUTPUT"
    exit 0
fi

echo "==> Found $(echo "$new_repos" | wc -l) unregistered repo(s):"
echo "$new_repos"
echo ""

added=0
skipped=0

while IFS= read -r repo; do
    [[ -z "$repo" ]] && continue
    name="${repo#pkg-}"

    echo "--- Processing $repo ($name) ---"

    pkgbuild_resp=$(gh api "repos/$ORG/$repo/contents/PKGBUILD" 2>/dev/null || true)
    if [[ -z "$pkgbuild_resp" ]] || echo "$pkgbuild_resp" | jq -e '.message' &>/dev/null; then
        echo "  SKIP: No PKGBUILD found (repo not ready)"
        ((skipped++)) || true
        continue
    fi

    arch='["aarch64"]'
    pkgbuild=$(echo "$pkgbuild_resp" | jq -r '.content' | base64 -d 2>/dev/null || true)
    if [[ -n "$pkgbuild" ]]; then
        arch_block=$(echo "$pkgbuild" | sed -n "/^arch=(/,/)/p" | tr '\n' ' ')
        arch_values=$(echo "$arch_block" | grep -oP '\(\K[^)]*' | tr -d "'" | tr -d '"' | xargs)
        if [[ -n "$arch_values" ]]; then
            arch=$(echo "$arch_values" | tr ' ' '\n' | jq -R . | jq -sc .)
            echo "  Detected arch: $arch"
        else
            echo "  Could not parse arch from PKGBUILD, using default: $arch"
        fi
    else
        echo "  Could not decode PKGBUILD content, using default: $arch"
    fi

    jq --arg name "$name" --arg repo "$repo" --argjson arch "$arch" \
        '.packages += [{"name": $name, "repo": $repo, "arch": $arch}]' \
        "$PACKAGES_FILE" > "$PACKAGES_FILE.tmp" && mv "$PACKAGES_FILE.tmp" "$PACKAGES_FILE"

    echo "  Added: name=$name repo=$repo arch=$arch"
    ((added++)) || true
done <<< "$new_repos"

echo ""
echo "==> Done. Added: $added, Skipped: $skipped"
echo "added=$added" >> "$GITHUB_OUTPUT"
