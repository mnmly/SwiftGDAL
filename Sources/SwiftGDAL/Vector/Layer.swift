import Foundation
import gdal

/// A vector layer inside a `VectorDataset`. Lifetime is tied to its owner —
/// the layer handle itself is not owned by Swift.
public final class Layer {

    nonisolated(unsafe) let handle: OGRLayerH
    private let owner: VectorDataset

    init(_ handle: OGRLayerH, owner: VectorDataset) {
        self.handle = handle
        self.owner = owner
    }

    public var name: String {
        String(cString: OGR_L_GetName(handle))
    }

    public var geometryType: GeometryType {
        GeometryType(OGR_L_GetGeomType(handle))
    }

    public var spatialReference: SpatialReference? {
        guard let h = OGR_L_GetSpatialRef(handle) else { return nil }
        var ptr: UnsafeMutablePointer<CChar>?
        guard OSRExportToWkt(h, &ptr) == OGRERR_NONE, let ptr else { return nil }
        defer { VSIFree(ptr) }
        return try? SpatialReference(wkt: String(cString: ptr))
    }

    /// Number of features. Pass `forceCompute: true` to scan the whole layer
    /// if the driver can't answer in O(1).
    public func featureCount(forceCompute: Bool = false) -> Int64 {
        OGR_L_GetFeatureCount(handle, forceCompute ? 1 : 0)
    }

    public var fieldDefinitions: [FieldDefn] {
        let defn = OGR_L_GetLayerDefn(handle).unsafelyUnwrapped
        let count = Int(OGR_FD_GetFieldCount(defn))
        return (0..<count).map { i in
            let f = OGR_FD_GetFieldDefn(defn, Int32(i)).unsafelyUnwrapped
            return FieldDefn(
                name: String(cString: OGR_Fld_GetNameRef(f)),
                type: FieldType(OGR_Fld_GetType(f)),
                width: Int(OGR_Fld_GetWidth(f)),
                precision: Int(OGR_Fld_GetPrecision(f))
            )
        }
    }

    // MARK: - Filters

    /// Restricts subsequent reads to features intersecting the bbox.
    /// Pass `nil` to clear.
    public func setSpatialFilter(envelope: (minX: Double, minY: Double, maxX: Double, maxY: Double)?) {
        if let e = envelope {
            let ring = Geometry.polygon(outer: [
                (e.minX, e.minY), (e.maxX, e.minY),
                (e.maxX, e.maxY), (e.minX, e.maxY),
                (e.minX, e.minY),
            ])
            OGR_L_SetSpatialFilter(handle, ring.handle)
        } else {
            OGR_L_SetSpatialFilter(handle, nil)
        }
    }

    /// Restricts reads to features matching an SQL-like WHERE clause.
    /// Pass `nil` to clear.
    public func setAttributeFilter(_ where_: String?) throws {
        CPLErrorReset()
        let err = OGR_L_SetAttributeFilter(handle, where_)
        guard err == OGRERR_NONE else {
            throw GDALError.lastError(fallback: "OGR_L_SetAttributeFilter failed")
        }
    }

    public func resetReading() {
        OGR_L_ResetReading(handle)
    }

    /// Returns the next feature in iteration order, or nil at end.
    /// Owns the returned `Feature`.
    public func nextFeature() -> Feature? {
        guard let raw = OGR_L_GetNextFeature(handle) else { return nil }
        return Feature(owned: raw)
    }

    /// Sequence over all features in the current filter. Calls `resetReading()`
    /// at the start.
    ///
    /// > Important: Do **not** call `update(_:)`, `create(_:)`, or
    /// > `delete(fid:)` on the same layer while iterating this sequence —
    /// > GDAL's driver-internal cursor can be invalidated by writes. Collect
    /// > FIDs (or features) first, then mutate after iteration ends.
    public func features() -> FeatureSequence {
        resetReading()
        return FeatureSequence(layer: self)
    }

    /// Async sequence over all features. Each `next()` hops to a detached
    /// task so blocking IO doesn't stall the caller's executor (typically
    /// `@MainActor`). Same iteration-vs-mutation caveat as `features()`.
    public func featuresAsync() -> AsyncFeatureSequence {
        resetReading()
        return AsyncFeatureSequence(layer: self)
    }

    // MARK: - Writes

    /// Adds a new field definition to the layer's schema.
    public func createField(_ def: FieldDefn) throws {
        CPLErrorReset()
        let h = OGR_Fld_Create(def.name, def.type.raw).unsafelyUnwrapped
        defer { OGR_Fld_Destroy(h) }
        if def.width > 0 { OGR_Fld_SetWidth(h, Int32(def.width)) }
        if def.precision > 0 { OGR_Fld_SetPrecision(h, Int32(def.precision)) }
        let err = OGR_L_CreateField(handle, h, 1)
        guard err == OGRERR_NONE else {
            throw GDALError.lastError(fallback: "OGR_L_CreateField failed")
        }
    }

    /// Inserts a feature. Updates the feature's FID on success.
    public func create(_ feature: Feature) throws {
        CPLErrorReset()
        let err = OGR_L_CreateFeature(handle, feature.handle)
        guard err == OGRERR_NONE else {
            throw GDALError.lastError(fallback: "OGR_L_CreateFeature failed")
        }
    }

    /// Updates an existing feature in place (matches by FID).
    public func update(_ feature: Feature) throws {
        CPLErrorReset()
        let err = OGR_L_SetFeature(handle, feature.handle)
        guard err == OGRERR_NONE else {
            throw GDALError.lastError(fallback: "OGR_L_SetFeature failed")
        }
    }

    public func delete(fid: Int64) throws {
        CPLErrorReset()
        let err = OGR_L_DeleteFeature(handle, fid)
        guard err == OGRERR_NONE else {
            throw GDALError.lastError(fallback: "OGR_L_DeleteFeature failed")
        }
    }
}

/// Synchronous sequence of features. Use `for feature in layer.features() { ... }`.
///
/// Non-Sendable on purpose: GDAL layer iteration mutates the layer's
/// internal cursor — keep iteration on one task.
public struct FeatureSequence: Sequence, IteratorProtocol {
    private let layer: Layer

    init(layer: Layer) { self.layer = layer }

    public mutating func next() -> Feature? {
        layer.nextFeature()
    }

    public func makeIterator() -> FeatureSequence { self }
}

/// Async sequence wrapper around `Layer.nextFeature()`. Each `next()` call
/// hops to a detached task so a `@MainActor` caller stays responsive while
/// a driver does blocking IO. The underlying cursor is still owned by one
/// layer, so do not iterate concurrently from multiple tasks.
public struct AsyncFeatureSequence: AsyncSequence {
    public typealias Element = Feature

    private let layer: Layer
    init(layer: Layer) { self.layer = layer }

    public struct AsyncIterator: AsyncIteratorProtocol {
        let layer: Layer
        public mutating func next() async -> Feature? {
            let unsafe = UnsafeTransfer(layer)
            // Wrap the Feature in UnsafeTransfer to ferry it back across the
            // detached-task boundary — Feature is intentionally non-Sendable
            // because each feature is logically owned by one task at a time,
            // and that invariant still holds here (the caller awaits before
            // touching it).
            let result = await Task.detached { () -> UnsafeTransfer<Feature?> in
                UnsafeTransfer(unsafe.value.nextFeature())
            }.value
            return result.value
        }
    }

    public func makeAsyncIterator() -> AsyncIterator { AsyncIterator(layer: layer) }
}
