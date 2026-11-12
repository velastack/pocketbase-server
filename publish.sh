#!/usr/bin/env bash

set -euo pipefail

# Usage:
#   ./publish.sh                    # publish under the "latest" dist-tag
#   NPM_DIST_TAG=next ./publish.sh  # publish under another dist-tag
#
# Locally this prompts for npm 2FA. In GitHub Actions it authenticates with
# npm trusted publishing (OIDC), see .github/workflows/release.yaml.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NPM_DIST_TAG="${NPM_DIST_TAG:-latest}"

# Publish platform packages first, then the meta package.
PACKAGES=(
  "pocketbase-server-darwin-arm64"
  "pocketbase-server-darwin-x64"
  "pocketbase-server-linux-arm"
  "pocketbase-server-linux-arm64"
  "pocketbase-server-linux-ppc64"
  "pocketbase-server-linux-s390x"
  "pocketbase-server-linux-x64"
  "pocketbase-server-win32-arm64"
  "pocketbase-server-win32-x64"
  "pocketbase-server"
)

for cmd in npm node; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd"
    exit 1
  fi
done

echo "Publishing ${#PACKAGES[@]} packages from: $ROOT_DIR"
echo "Dist-tag: $NPM_DIST_TAG"
if [[ -z "${CI:-}" ]]; then
  echo "npm 2FA prompts are interactive and will appear during each publish."
fi
echo

for i in "${!PACKAGES[@]}"; do
  pkg_dir="$ROOT_DIR/${PACKAGES[$i]}"
  pkg_json="$pkg_dir/package.json"

  if [[ ! -d "$pkg_dir" ]]; then
    echo "Package directory not found: $pkg_dir"
    exit 1
  fi

  if [[ ! -f "$pkg_json" ]]; then
    echo "Missing package.json: $pkg_json"
    exit 1
  fi

  pkg_name="$(node -p "require('$pkg_json').name")"
  pkg_version="$(node -p "require('$pkg_json').version")"

  # Skip versions already on the registry so a failed run can be resumed.
  if [[ -n "$(npm view "$pkg_name@$pkg_version" version 2>/dev/null || true)" ]]; then
    echo "[$((i + 1))/${#PACKAGES[@]}] Skipping $pkg_name@$pkg_version (already published)"
    continue
  fi

  echo "[$((i + 1))/${#PACKAGES[@]}] Publishing $pkg_name@$pkg_version"
  echo "Directory: $pkg_dir"
  (
    cd "$pkg_dir"
    npm publish --tag "$NPM_DIST_TAG"
  )
  echo "Published $pkg_name@$pkg_version"
done

echo "All packages published."
