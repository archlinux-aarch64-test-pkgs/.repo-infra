#!/bin/bash
set -euo pipefail

ORG="archlinux-aarch64-test-pkgs"
PACKAGES_FILE="config/packages.json"

echo "==> Fetching all pkg-* repos from org $ORG ..."
all_repos=$(gh api --paginate "orgs/$ORG/repos?per_page=100" \
    --jq '.[] | select(.archived == false) | .name' | grep '^pkg-' | sort || true)

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

extract_arch() {
    awk '
        function strip_comments(s, out, i, c, q, prev) {
            out = ""
            q = ""
            for (i = 1; i <= length(s); i++) {
                c = substr(s, i, 1)
                prev = i > 1 ? substr(s, i - 1, 1) : ""
                if (q == "") {
                    if (c == "#") break
                    if (c == "\047" || c == "\"") q = c
                } else if (c == q && prev != "\\") {
                    q = ""
                }
                out = out c
            }
            return out
        }

        /^[[:space:]]*arch[[:space:]]*=/ {
            in_arch = 1
            line = $0
            sub(/^[[:space:]]*arch[[:space:]]*=[[:space:]]*\(/, "", line)
        }

        in_arch {
            done = 0
            line = strip_comments(line)
            if (line ~ /\)/) {
                sub(/\).*/, "", line)
                done = 1
            }
            gsub(/[()]/, " ", line)
            gsub(/["\047]/, "", line)
            for (i = 1; i <= split(line, values, /[[:space:]]+/); i++) {
                if (values[i] != "") print values[i]
            }
            if (done) exit
            line = ""
        }
    '
}

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
        arch_values=$(echo "$pkgbuild" | extract_arch | xargs || true)
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
