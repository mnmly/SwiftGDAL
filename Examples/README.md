# SwiftGDAL Examples

Two demos:

## `gdalinfo` (CLI)

SPM executable target — built from the root package.

```bash
swift run gdalinfo /path/to/raster.tif
```

Prints raster shape, geo-transform, projection, and per-band stats. Source:
`Examples/gdalinfo/main.swift`.

## `GDALApp` (SwiftUI, iOS + macOS)

Multi-tab SwiftUI app demonstrating most of SwiftGDAL's public surface.
References the parent `SwiftGDAL` package via `XCLocalSwiftPackageReference`,
so changes to the library are picked up automatically.

```bash
open Examples/GDALApp/GDALApp.xcodeproj
```

Or build headless:

```bash
# macOS (arm64 only — gdal.xcframework's macOS slice is arm64)
xcodebuild -project Examples/GDALApp/GDALApp.xcodeproj \
    -scheme GDALApp -destination 'generic/platform=macOS' \
    ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build

# iOS Simulator (arm64 only)
xcodebuild -project Examples/GDALApp/GDALApp.xcodeproj \
    -scheme GDALApp -destination 'generic/platform=iOS Simulator' \
    ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build

# iOS device (skip signing for a quick smoke build)
xcodebuild -project Examples/GDALApp/GDALApp.xcodeproj \
    -scheme GDALApp -destination 'generic/platform=iOS' \
    CODE_SIGNING_ALLOWED=NO build
```

Tabs:

- **Raster** — `.fileImporter` → `Dataset` → dimensions, projection,
  GeoTransform, per-band stats. Renders a 256-px PNG thumbnail via
  `GDALOps.translate(..., "-of", "PNG", "-outsize", ...)`.
- **Vector** — `.fileImporter` → `VectorDataset` → layer enumeration,
  feature count, field schemas, first three features as a preview.
- **Warp** — runs `gdalwarp -t_srs EPSG:3857` on a picked raster with the
  progress callback bound to a SwiftUI `ProgressView`. Demonstrates hopping
  from GDAL's working thread back to `@MainActor` for UI updates.

### macOS arm64-only caveat

`gdal.xcframework`'s macOS slice ships arm64 only (no Intel slice from the
current builder config). On an Apple Silicon Mac, `ARCHS=arm64
ONLY_ACTIVE_ARCH=YES` is the right invocation; opening the project in Xcode
on Apple Silicon "just works" because the active arch is already arm64.
