#!/usr/bin/env bash
#
# Usage:
#   ./update.sh                 # latest stable release
#   ./update.sh --prerelease    # newest release, including prereleases (betas)
#   ./update.sh v0.40.5-beta.3  # a specific release tag

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_DIR="$(mktemp -d)"
RELEASES_API_URL="https://api.github.com/repos/velastack/velabase/releases"

case "${1:-}" in
  "")
    RELEASE_API_URL="$RELEASES_API_URL/latest"
    ;;
  --prerelease)
    # /releases lists newest first and includes prereleases (but not drafts
    # for anonymous requests); the first entry is picked below
    RELEASE_API_URL="$RELEASES_API_URL?per_page=10"
    ;;
  -*)
    echo "Unknown option: $1 (usage: $0 [--prerelease | <tag>])"
    exit 1
    ;;
  *)
    RELEASE_API_URL="$RELEASES_API_URL/tags/$1"
    ;;
esac

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

for cmd in curl unzip python3; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd"
    exit 1
  fi
done

echo "Fetching release metadata from GitHub ($RELEASE_API_URL)..."
release_json="$(curl -fsSL "$RELEASE_API_URL")"

# --prerelease returns a list: keep the newest non-draft release
release_json="$(printf '%s' "$release_json" | python3 -c '
import json, sys

data = json.load(sys.stdin)
if isinstance(data, list):
    data = next((r for r in data if not r.get("draft")), None)
    if data is None:
        sys.exit("No published releases found")
print(json.dumps(data))
')"

release_tag="$(printf '%s' "$release_json" | python3 -c 'import json, sys; print(json.load(sys.stdin)["tag_name"])')"
release_kind="$(printf '%s' "$release_json" | python3 -c 'import json, sys; print("prerelease" if json.load(sys.stdin).get("prerelease") else "release")')"
version="${release_tag#v}"

echo "Selected velabase $release_kind: $release_tag"
echo "Resolved package version: $version"

declare -A ASSET_URLS=()
while IFS=$'\t' read -r name url; do
  ASSET_URLS["$name"]="$url"
done < <(
  printf '%s' "$release_json" | python3 -c '
import json
import sys

data = json.load(sys.stdin)
for asset in data.get("assets", []):
    print(asset["name"], asset["browser_download_url"], sep="\t")
'
)

download_and_install() {
  local asset_name="$1"
  local package_dir="$2"
  local binary_name="$3"

  local url="${ASSET_URLS[$asset_name]:-}"
  if [[ -z "$url" ]]; then
    echo "Could not find release asset: $asset_name"
    exit 1
  fi

  local zip_path="$TMP_DIR/$asset_name"
  local extract_dir="$TMP_DIR/extract-${asset_name%.zip}"
  local target_dir="$ROOT_DIR/$package_dir/bin"
  local target_path="$target_dir/$binary_name"

  mkdir -p "$extract_dir" "$target_dir"

  echo "Downloading $asset_name..."
  curl -fsSL "$url" -o "$zip_path"

  echo "Extracting $asset_name..."
  unzip -oq "$zip_path" -d "$extract_dir"

  if [[ ! -f "$extract_dir/$binary_name" ]]; then
    echo "Expected binary '$binary_name' not found in $asset_name"
    exit 1
  fi

  rm -f "$target_path"
  cp "$extract_dir/$binary_name" "$target_path"
  chmod +x "$target_path"
  echo "Installed $target_path"
}

download_and_install "pocketbase_${version}_darwin_amd64.zip" "pocketbase-server-darwin-x64" "pocketbase"
download_and_install "pocketbase_${version}_darwin_arm64.zip" "pocketbase-server-darwin-arm64" "pocketbase"
download_and_install "pocketbase_${version}_linux_amd64.zip" "pocketbase-server-linux-x64" "pocketbase"
download_and_install "pocketbase_${version}_linux_armv7.zip" "pocketbase-server-linux-arm" "pocketbase"
download_and_install "pocketbase_${version}_linux_arm64.zip" "pocketbase-server-linux-arm64" "pocketbase"
download_and_install "pocketbase_${version}_linux_ppc64le.zip" "pocketbase-server-linux-ppc64" "pocketbase"
download_and_install "pocketbase_${version}_linux_s390x.zip" "pocketbase-server-linux-s390x" "pocketbase"
download_and_install "pocketbase_${version}_windows_amd64.zip" "pocketbase-server-win32-x64" "pocketbase.exe"
download_and_install "pocketbase_${version}_windows_arm64.zip" "pocketbase-server-win32-arm64" "pocketbase.exe"

echo "Updating package versions to $version..."
python3 - "$ROOT_DIR" "$version" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
version = sys.argv[2]

def write_json(path, data):
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")

for pkg_path in root.glob("pocketbase-server*/package.json"):
    data = json.loads(pkg_path.read_text(encoding="utf-8"))
    data["version"] = version

    if data.get("name") == "pocketbase-server":
        optional = data.get("optionalDependencies", {})
        for dep in optional:
            if dep.startswith("pocketbase-server-"):
                optional[dep] = version

    write_json(pkg_path, data)
    print(f"Updated {pkg_path.relative_to(root)}")
PY

echo "Update complete."
