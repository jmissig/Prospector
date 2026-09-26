#!/bin/sh
set -eu
repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$repo_dir"
mkdir -p .build/terrain-check-fixtures
usdzip .build/terrain-check-fixtures/terrain.usdz --asset Tools/TerrainChecks/fixture.usda
xcrun --sdk macosx swiftc -parse-as-library -framework RealityKit \
  Prospector/TerrainConfiguration.swift Prospector/TerrainLayer.swift \
  Prospector/LandscapeEnvironment.swift Prospector/ProspectorDocument.swift \
  Prospector/ModelCatalog.swift Prospector/PositionPersistence.swift Prospector/NavigationDiagnostics.swift \
  Tools/TerrainChecks/NavigationDiagnosticsChecks.swift Tools/TerrainChecks/main.swift -o .build/terrain-checks
.build/terrain-checks "$repo_dir/.build/terrain-check-fixtures/terrain.usdz"
