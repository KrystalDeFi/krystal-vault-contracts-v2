// Ensures `@pancakeswap/infinity-periphery` exposes a package.json.
//
// The dependency is installed straight from GitHub ("github:pancakeswap/infinity-periphery"),
// and that repo — unlike infinity-core — does not ship a package.json. Hardhat's library
// resolver treats the remapped import path as an npm package and fails with HH411
// ("library ... is not installed") when shared-vault contracts import infinity-periphery
// sources. Foundry is unaffected because it resolves purely via remappings.txt.
//
// This script is idempotent: it only writes the file when the package directory exists
// and the manifest is missing, so it is safe to run on every install.
const fs = require("fs");
const path = require("path");

const pkgDir = path.join(__dirname, "..", "node_modules", "@pancakeswap", "infinity-periphery");
const pkgJsonPath = path.join(pkgDir, "package.json");

if (fs.existsSync(pkgDir) && !fs.existsSync(pkgJsonPath)) {
  const manifest = {
    name: "infinity-periphery",
    description: "Infinity periphery contracts",
    version: "1.0.0",
    main: "index.js",
    license: "MIT",
  };
  fs.writeFileSync(pkgJsonPath, JSON.stringify(manifest, null, 2) + "\n");
  console.log("[patch-infinity-periphery] wrote missing package.json for @pancakeswap/infinity-periphery");
}
