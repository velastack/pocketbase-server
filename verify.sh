#!/usr/bin/env bash
#
# Verify the packages before publishing (a published version can't be
# replaced, so an empty or mismatched one is permanent):
#
#   1. every package.json is at the expected version;
#   2. every platform package tarball contains its binary;
#   3. the meta package + this machine's platform package install from their
#      tarballs and `pocketbase-server --version` reports the expected version.
#
# Usage:
#   ./verify.sh            # expect the version in pocketbase-server/package.json
#   ./verify.sh 0.42.2     # expect a specific version

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

die() { echo "error: $*" >&2; exit 1; }

version="${1:-$(node -p "require('$ROOT_DIR/pocketbase-server/package.json').version")}"
version="${version#v}"
echo "Verifying packages at version $version"

for pkg_json in "$ROOT_DIR"/pocketbase-server*/package.json; do
  pkg_dir="$(dirname "$pkg_json")"
  name="$(node -p "require('$pkg_json').name")"

  [[ "$name" == "$(basename "$pkg_dir")" ]] || die "$pkg_dir is named $name"
  [[ "$(node -p "require('$pkg_json').version")" == "$version" ]] || \
    die "$name is not at version $version"

  if [[ "$name" == "pocketbase-server" ]]; then
    node -e '
      const [pkgJson, version] = process.argv.slice(1);
      const deps = require(pkgJson).optionalDependencies;
      const bad = Object.entries(deps).filter(([, v]) => v !== version);
      if (bad.length) { console.error("optionalDependencies not at " + version, bad); process.exit(1); }
    ' "$pkg_json" "$version" || die "pocketbase-server optionalDependencies mismatch"
    continue
  fi

  binary="bin/pocketbase"
  [[ "$name" == *-win32-* ]] && binary="bin/pocketbase.exe"

  # the binary must be in the tarball and be a real executable, not a stub
  (cd "$pkg_dir" && npm pack --dry-run --json 2>/dev/null) | node -e '
    const [binary] = process.argv.slice(1);
    const [pack] = JSON.parse(require("fs").readFileSync(0, "utf8"));
    const file = pack.files.find((f) => f.path === binary);
    if (!file) { console.error(`${pack.name}: ${binary} missing from the tarball`); process.exit(1); }
    if (file.size < 10 * 1024 * 1024) { console.error(`${pack.name}: ${binary} is only ${file.size} bytes`); process.exit(1); }
    console.log(`ok ${pack.name}@${pack.version} ${binary} (${(file.size / 1048576).toFixed(1)} MB)`);
  ' "$binary" || die "$name tarball check failed"
done

# install the real tarballs the way a user would (the other platforms'
# optional dependencies aren't on the registry yet, hence --omit=optional)
platform_pkg="pocketbase-server-$(node -p 'process.platform + "-" + process.arch')"
[[ -d "$ROOT_DIR/$platform_pkg" ]] || die "no platform package for this machine ($platform_pkg)"

echo "Smoke testing pocketbase-server + $platform_pkg..."
mkdir "$TMP_DIR/tarballs" "$TMP_DIR/app"
for pkg in pocketbase-server "$platform_pkg"; do
  (cd "$ROOT_DIR/$pkg" && npm pack --silent --pack-destination "$TMP_DIR/tarballs" > /dev/null)
done

cd "$TMP_DIR/app"
npm init -y > /dev/null
npm install --silent --no-audit --no-fund --omit=optional "$TMP_DIR"/tarballs/*.tgz

reported="$(npx --no-install pocketbase-server --version)"
echo "    $reported"
[[ "$reported" == *" $version" ]] || die "expected version $version, the binary reports: $reported"

# the wrapper must pass through pocketbase's exit code
if npx --no-install pocketbase-server not-a-command > /dev/null 2>&1; then
  die "the wrapper exited 0 for a failing pocketbase command"
fi

echo "All packages verified."
