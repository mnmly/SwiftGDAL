# ``SwiftGDAL``

Swift bindings for [GDAL](https://gdal.org/) — raster + vector geospatial
I/O for macOS and iOS, backed by an xcframework that bundles GDAL and PROJ.

## Overview

SwiftGDAL wraps GDAL's stable C API in idiomatic Swift: handles become
`final class` types with `deinit`-managed lifetimes, errors raise as
``GDALError``, and blocking I/O has async overloads that hop off the
caller's executor via `Task.detached`.

The xcframework is fetched automatically from
[gdal-xcframework-builder](https://github.com/mnmly/gdal-xcframework-builder)
releases — no vendoring or build-time post-processing is needed.

```swift
import SwiftGDAL

// Inspect a raster
let ds = try Dataset(opening: "/path/to/image.tif")
print("\(ds.rasterWidth) × \(ds.rasterHeight), \(ds.rasterCount) bands")

// Read pixels off the main actor
let pixels: [Float] = try await ds.band(1).read(as: Float.self)

// Reproject via gdalwarp
let webMercator = try ds.warp(
    to: "/tmp/wm.tif",
    options: ["-t_srs", "EPSG:3857"],
    onProgress: { p in print("\(Int(p * 100))%") }
)

// Iterate vector features
let layer = try VectorDataset(opening: "places.geojson").layer(at: 0)
for feature in layer.features() {
    if case .string(let name) = feature[field: "name"] { print(name) }
}
```

### Concurrency model

``Dataset``, ``RasterBand``, ``VectorDataset``, ``Layer``, ``Feature``,
and ``Geometry`` are deliberately **not `Sendable`**. GDAL handles are
not safe to share across threads; keep one per task. The async overloads
(``RasterBand/read(rect:as:)-async``, ``Layer/featuresAsync()``,
``Dataset/warp(to:options:onProgress:)``) hop blocking I/O off the
caller via `Task.detached` so `@MainActor` callers stay responsive — but
the handle itself stays pinned to one task at a time.

## Topics

### Getting Started

- ``GDAL``

### Raster I/O

- ``Dataset``
- ``RasterBand``
- ``RasterBlock``
- ``GeoTransform``
- ``DataType``
- ``AccessMode``
- ``RWFlag``
- ``GDALPixel``

### Vector I/O

- ``VectorDataset``
- ``Layer``
- ``Feature``
- ``Geometry``
- ``GeometryType``
- ``FieldDefn``
- ``FieldType``
- ``FieldValue``
- ``FeatureSequence``
- ``AsyncFeatureSequence``

### Coordinate Systems

- ``SpatialReference``
- ``CoordinateTransform``

### High-Level Operations

- ``GDALOps``
- ``ProgressCallback``

### Errors

- ``GDALError``
