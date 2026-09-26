#!/bin/sh
set -eu
repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$repo_dir"
mkdir -p .build
xcrun --sdk macosx swiftc -parse-as-library -framework RealityKit \
  Prospector/TerrainConfiguration.swift Prospector/TerrainLayer.swift \
  Prospector/LandscapeEnvironment.swift Prospector/ProspectorDocument.swift \
  Prospector/ModelCatalog.swift Prospector/PositionPersistence.swift \
  Tools/NavigationChecks/main.swift -o .build/navigation-checks
.build/navigation-checks
