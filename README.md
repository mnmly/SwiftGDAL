# SwiftGDAL

Swift API over [GDAL](https://gdal.org/) — built on top of an
xcframework that bundles GDAL + PROJ for macOS and iOS. Modelled after
[SwiftPDAL](https://github.com/mnmly/SwiftPDAL).

```swift
import SwiftGDAL

let ds = try Dataset(opening: "/path/to/image.tif")
print("\(ds.rasterWidth)×\(ds.rasterHeight), \(ds.rasterCount) bands")

let pixels: [Float] = try await ds.band(1).read(as: Float.self)

// Block-streaming for large rasters
for try await block in ds.band(1).blocks(as: Float.self) {
    process(block.pixels, at: block.rect)
}
```

## What's covered

- `GDAL` — process-wide registration + version + config options + driver list
- `Dataset` — open/create rasters, geo-transform, projection, metadata
- `RasterBand` — typed sync + async IO, block-level `AsyncThrowingStream`
- `SpatialReference` / `CoordinateTransform` — EPSG / WKT / PROJ.4 in,
  WKT / PROJ.4 out, plus single-point and bulk transforms
- `VectorDataset` / `Layer` / `Feature` / `Geometry` — OGR read + write,
  spatial + attribute filters, transactions
- `GDALOps` — Swift wrappers around `gdal_translate`, `gdalwarp`,
  `gdal_rasterize`, `ogr2ogr`, `gdalbuildvrt`. Options are passed CLI-style:

  ```swift
  let webMercator = try src.warp(
      to: "/vsimem/wm.tif",
      options: ["-t_srs", "EPSG:3857", "-ts", "1024", "1024"]
  )
  ```
- `DataType`, `GeoTransform`, `GDALError`

## Concurrency model

GDAL datasets are **not** thread-safe for concurrent use of the same
handle. `Dataset` and `RasterBand` are deliberately non-`Sendable`. The
async APIs (`read`/`write`/`blocks`) hop work off the caller's executor
via `Task.detached`, so a `@MainActor` caller stays responsive while
GDAL does blocking IO — but the dataset itself stays on one task at a
time.

If you need parallel reads of the same file, open multiple `Dataset`s.

## Local development

`Package.swift` fetches `gdal.xcframework` and `proj.xcframework` from
[`gdal-xcframework-builder`](https://github.com/mnmly/gdal-xcframework-builder)
GitHub releases via URL + checksum — `swift build` / Xcode handle the
download. No vendoring, no patch step.

To iterate against a locally-built xcframework, swap each `.binaryTarget`
in `Package.swift` to `path: "Frameworks/<name>.xcframework"` and drop a
fresh build into `Frameworks/`. Run `swift package compute-checksum
<zip>` to refresh the checksum when bumping the URL.

## Build & test

```bash
swift build
swift test
```

## Examples

See [`Examples/README.md`](Examples/README.md) for two demos:

- **`gdalinfo`** — SPM CLI: `swift run gdalinfo <path>`
- **`GDALApp`** — SwiftUI iOS + macOS app with raster inspection, on-the-fly
  PNG thumbnails, vector layer enumeration, and a warp-with-progress UI
