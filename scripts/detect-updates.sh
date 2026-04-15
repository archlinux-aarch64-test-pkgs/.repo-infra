#!/bin/bash
set -euo pipefail

ORG="archlinux-aarch64-test-pkgs"
STATE_FILE="state/build-state.json"
PACKAGES_FILE="config/packages.json"

[[ -f "$STATE_FILE" ]] || echo '{}' > "$STATE_FILE"

pkg_count=$(jq '.packages | length' "$PACKAGES_FILE")
if (( pkg_count == 0 )); then
    echo "No packages registered in $PACKAGES_FILE"
    exit 0
fi

triggered=0
skipped=0

jq -c '.packages[]' "$PACKAGES_FILE" | while read -r pkg; do
    repo=$(echo "$pkg" | jq -r '.repo')
    name=$(echo "$pkg" | jq -r '.name')
    runner=$(echo "$pkg" | jq -r '.runner // "ubuntu-24.04-arm"')

    echo "--- Checking $repo ($name) ---"

    default_branch=$(gh api "repos/$ORG/$repo" --jq '.default_branch' 2>/dev/null || true)
    if [[ -z "$default_branch" ]]; then
        echo "  WARNING: Could not determine default branch for $repo, skipping"
        continue
    fi

    latest_sha=$(gh api "repos/$ORG/$repo/commits/$default_branch" --jq '.sha' 2>/dev/null || true)
    if [[ ! "$latest_sha" =~ ^[0-9a-f]{40}$ ]]; then
        echo "  WARNING: Could not fetch latest commit for $repo (got: '${latest_sha:0:60}'), skipping"
        continue
    fi

    built_sha=$(jq -r --arg r "$repo" '.[$r] // ""' "$STATE_FILE")

    if [[ "$latest_sha" != "$built_sha" ]]; then
        echo "  New commits detected: ${built_sha:0:7}... → ${latest_sha:0:7}..."
        echo "  Triggering build with runner=$runner"
        gh workflow run build-package.yml \
            -f package="$repo" \
            -f runner="$runner"

        jq --arg r "$repo" --arg s "$latest_sha" '.[$r] = $s' "$STATE_FILE" > tmp_state.json \
            && mv tmp_state.json "$STATE_FILE"
        ((triggered++)) || true
    else
        echo "  Up to date (${latest_sha:0:7}...)"
        ((skipped++)) || true
    fi
done

echo ""
echo "==> Done. Triggered: $triggered, Skipped: $skipped"
