import { createRequire } from "node:module";
const require = createRequire(import.meta.url);

export function getBinaryPath() {
  // Lookup table for all platforms and binary distribution packages,
  // keyed by Node's `${process.platform}-${process.arch}`
  const BINARY_DISTRIBUTION_PACKAGES = {
    "darwin-arm64": "pocketbase-server-darwin-arm64",
    "darwin-x64": "pocketbase-server-darwin-x64",
    "linux-arm64": "pocketbase-server-linux-arm64",
    "linux-arm": "pocketbase-server-linux-arm",
    "linux-ppc64": "pocketbase-server-linux-ppc64",
    "linux-s390x": "pocketbase-server-linux-s390x",
    "linux-x64": "pocketbase-server-linux-x64",
    "win32-arm64": "pocketbase-server-win32-arm64",
    "win32-x64": "pocketbase-server-win32-x64",
  };

  // Windows binaries end with .exe so we need to special case them.
  const binaryName =
    process.platform === "win32" ? "pocketbase.exe" : "pocketbase";

  const platformKey = `${process.platform}-${process.arch}`;

  // Determine package name for this platform
  const platformSpecificPackageName = BINARY_DISTRIBUTION_PACKAGES[platformKey];

  if (!platformSpecificPackageName) {
    console.error(`Pocketbase has no prebuilt binary for ${platformKey}.`);
    process.exit(1);
  }

  try {
    // Resolving will fail if the optionalDependency was not installed
    return require.resolve(`${platformSpecificPackageName}/bin/${binaryName}`);
  } catch (e) {
    console.error(
      `Pocketbase binary not found for ${platformKey}, check that optional dependencies for pocketbase-server are installed.`
    );
    process.exit(1);
  }
}
