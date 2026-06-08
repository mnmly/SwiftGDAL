import Foundation

// Human-readable descriptions for the GDAL wrapper types. Without these,
// `print(layer)` / `po feature` fall back to the bare type name
// (`SwiftGDAL.Layer`), which says nothing about the underlying handle.
//
// Descriptions stick to cheap, side-effect-free accessors so logging an
// object never triggers a full-layer scan. `Layer.featureCount` is called
// with `forceCompute: false`, so a driver that can't answer in O(1)
// reports `features: ?` rather than scanning.

extension Dataset: CustomStringConvertible {
    /// Path, raster dimensions, and band count, e.g.
    /// `Dataset(path: "dem.tif", 512×512, bands: 1)`.
    public var description: String {
        "Dataset(path: \"\(path)\", \(rasterWidth)×\(rasterHeight), bands: \(rasterCount))"
    }
}

extension RasterBand: CustomStringConvertible {
    /// Dimensions and sample type, e.g. `RasterBand(512×512, type: float32)`.
    public var description: String {
        "RasterBand(\(width)×\(height), type: \(dataType))"
    }
}

extension VectorDataset: CustomStringConvertible {
    /// Path and layer count, e.g. `VectorDataset(path: "roads.gpkg", layers: 2)`.
    public var description: String {
        "VectorDataset(path: \"\(path)\", layers: \(layerCount))"
    }
}

extension Layer: CustomStringConvertible {
    /// Name, geometry type, feature count, and field count, e.g.
    /// `Layer(name: "roads", type: lineString, features: 128, fields: 5)`.
    ///
    /// `features:` is `?` when the driver can't return a count without a
    /// full scan (`featureCount(forceCompute:)` returned `-1`).
    public var description: String {
        let n = featureCount()
        let features = n >= 0 ? String(n) : "?"
        return "Layer(name: \"\(name)\", type: \(geometryType), features: \(features), fields: \(fieldDefinitions.count))"
    }
}

extension Feature: CustomStringConvertible {
    /// FID, field count, and geometry type, e.g.
    /// `Feature(fid: 12, fields: 5, geometry: polygon)`.
    public var description: String {
        let geom = geometry.map { "\($0.type)" } ?? "none"
        return "Feature(fid: \(fid), fields: \(fieldCount), geometry: \(geom))"
    }
}

extension Geometry: CustomStringConvertible, CustomDebugStringConvertible {
    /// Geometry type and point count, e.g. `Geometry(polygon, points: 5)`.
    public var description: String {
        "Geometry(\(type), points: \(pointCount))"
    }

    /// Same as ``description`` but appends the geometry's WKT, truncated to
    /// keep large geometries from flooding the debugger.
    public var debugDescription: String {
        guard let wkt = try? toWKT() else { return description }
        let preview = wkt.count > 120 ? wkt.prefix(120) + "…" : wkt[...]
        return "Geometry(\(type), points: \(pointCount), wkt: \(preview))"
    }
}

extension FeatureSequence: CustomStringConvertible {
    /// Names the layer being iterated, e.g. `FeatureSequence(layer: "roads")`.
    public var description: String {
        "FeatureSequence(layer: \"\(layer.name)\")"
    }
}

extension AsyncFeatureSequence: CustomStringConvertible {
    /// Names the layer being iterated, e.g. `AsyncFeatureSequence(layer: "roads")`.
    public var description: String {
        "AsyncFeatureSequence(layer: \"\(layer.name)\")"
    }
}
