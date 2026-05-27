import Foundation
import gdal

/// A vector dataset (e.g. Shapefile, GeoPackage, GeoJSON).
///
/// Like `Dataset`, this is intentionally **not** `Sendable`. Use one
/// `VectorDataset` per task.
public final class VectorDataset {

    nonisolated(unsafe) let handle: GDALDatasetH
    public let path: String

    /// Takes ownership of a raw GDAL handle returned by `GDALVectorTranslate` etc.
    init(takingOwnershipOf handle: GDALDatasetH, path: String) {
        self.handle = handle
        self.path = path
    }

    /// Opens an existing vector dataset.
    public init(opening path: String, access: AccessMode = .readOnly) throws {
        GDAL.registerAll()
        CPLErrorReset()
        let flags = UInt32(GDAL_OF_VECTOR) |
            UInt32(access == .update ? GDAL_OF_UPDATE : GDAL_OF_READONLY)
        guard let h = GDALOpenEx(path, flags, nil, nil, nil) else {
            throw GDALError.lastError(fallback: "Failed to open vector \(path)")
        }
        self.handle = h
        self.path = path
    }

    /// Creates a new vector dataset using the named driver (e.g. "GPKG", "ESRI Shapefile", "GeoJSON").
    public init(creating path: String, driver: String, options: [String: String] = [:]) throws {
        GDAL.registerAll()
        CPLErrorReset()
        guard let drv = GDALGetDriverByName(driver) else {
            throw GDALError.lastError(fallback: "Unknown driver \(driver)")
        }
        let opts = StringList(options)
        defer { opts.dispose() }
        guard let h = GDALCreate(drv, path, 0, 0, 0, GDT_Unknown, opts.pointer) else {
            throw GDALError.lastError(fallback: "Failed to create vector \(path)")
        }
        self.handle = h
        self.path = path
    }

    deinit {
        GDALClose(handle)
    }

    public var layerCount: Int { Int(GDALDatasetGetLayerCount(handle)) }

    public func layer(at index: Int) -> Layer {
        precondition(index >= 0 && index < layerCount, "layer index out of range")
        let h = GDALDatasetGetLayer(handle, Int32(index)).unsafelyUnwrapped
        return Layer(h, owner: self)
    }

    public func layer(named name: String) -> Layer? {
        guard let h = GDALDatasetGetLayerByName(handle, name) else { return nil }
        return Layer(h, owner: self)
    }

    /// Creates a new layer. The dataset must have been opened or created in
    /// update mode and its driver must support layer creation.
    public func createLayer(
        name: String,
        geometryType: GeometryType,
        spatialReference: SpatialReference? = nil,
        options: [String: String] = [:]
    ) throws -> Layer {
        let opts = StringList(options)
        defer { opts.dispose() }
        CPLErrorReset()
        guard let h = GDALDatasetCreateLayer(
            handle, name, spatialReference?.handle, geometryType.raw, opts.pointer
        ) else {
            throw GDALError.lastError(fallback: "GDALDatasetCreateLayer(\(name)) failed")
        }
        return Layer(h, owner: self)
    }

    public func flush() {
        GDALFlushCache(handle)
    }

    // MARK: - Transactions

    /// Starts a driver-level transaction. Pair with `commit()` or `rollback()`.
    public func startTransaction(force: Bool = false) throws {
        CPLErrorReset()
        let err = GDALDatasetStartTransaction(handle, force ? 1 : 0)
        guard err == OGRERR_NONE else {
            throw GDALError.lastError(fallback: "StartTransaction failed")
        }
    }

    public func commitTransaction() throws {
        CPLErrorReset()
        let err = GDALDatasetCommitTransaction(handle)
        guard err == OGRERR_NONE else {
            throw GDALError.lastError(fallback: "CommitTransaction failed")
        }
    }

    public func rollbackTransaction() throws {
        CPLErrorReset()
        let err = GDALDatasetRollbackTransaction(handle)
        guard err == OGRERR_NONE else {
            throw GDALError.lastError(fallback: "RollbackTransaction failed")
        }
    }

    /// Runs `body` inside a transaction. Commits on success; rolls back if
    /// `body` throws. Drivers that don't support transactions silently no-op.
    ///
    /// ```swift
    /// try ds.transaction {
    ///     for record in records {
    ///         let f = Feature(forLayer: layer)
    ///         f[field: "id"] = .integer64(record.id)
    ///         try layer.create(f)
    ///     }
    /// }
    /// ```
    public func transaction<R>(force: Bool = false, _ body: () throws -> R) throws -> R {
        guard supportsTransactions else {
            return try body()
        }
        try startTransaction(force: force)
        do {
            let result = try body()
            try commitTransaction()
            return result
        } catch {
            try? rollbackTransaction()
            throw error
        }
    }

    /// True if the underlying driver supports `StartTransaction`/`CommitTransaction`.
    public var supportsTransactions: Bool {
        GDALDatasetTestCapability(handle, "Transactions") != 0
    }
}
