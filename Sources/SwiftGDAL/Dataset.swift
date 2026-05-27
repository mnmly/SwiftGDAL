import Foundation
import gdal

/// A GDAL raster (or vector) dataset.
///
/// `Dataset` is intentionally **not** `Sendable`. GDAL datasets are not
/// safe to use concurrently from multiple threads on the same handle —
/// keep one `Dataset` per task. Use the `async` reads on `RasterBand` to
/// hop blocking I/O off the caller.
public final class Dataset {

    /// Opaque GDAL handle. `nonisolated(unsafe)` because the type is not
    /// Sendable; the handle stays pinned to whichever task owns the dataset.
    nonisolated(unsafe) let handle: GDALDatasetH

    public let path: String

    /// Takes ownership of a raw GDAL handle. Used by `GDALOps` helpers that
    /// receive a freshly-created dataset from `GDALTranslate` / `GDALWarp` / etc.
    init(takingOwnershipOf handle: GDALDatasetH, path: String) {
        self.handle = handle
        self.path = path
    }

    /// Opens an existing dataset.
    public init(opening path: String, access: AccessMode = .readOnly) throws {
        GDAL.registerAll()
        CPLErrorReset()
        guard let h = GDALOpen(path, access.raw) else {
            throw GDALError.lastError(fallback: "Failed to open \(path)")
        }
        self.handle = h
        self.path = path
    }

    /// Creates a new dataset using the named driver (e.g. "GTiff", "MEM", "PNG").
    public init(
        creating path: String,
        driver: String,
        width: Int,
        height: Int,
        bands: Int,
        dataType: DataType,
        options: [String: String] = [:]
    ) throws {
        GDAL.registerAll()
        CPLErrorReset()
        guard let drv = GDALGetDriverByName(driver) else {
            throw GDALError.lastError(fallback: "Unknown driver \(driver)")
        }
        let opts = StringList(options)
        defer { opts.dispose() }
        guard let h = GDALCreate(
            drv,
            path,
            Int32(width),
            Int32(height),
            Int32(bands),
            dataType.raw,
            opts.pointer
        ) else {
            throw GDALError.lastError(fallback: "Failed to create \(path)")
        }
        self.handle = h
        self.path = path
    }

    deinit {
        GDALClose(handle)
    }

    // MARK: - Raster shape

    public var rasterWidth: Int { Int(GDALGetRasterXSize(handle)) }
    public var rasterHeight: Int { Int(GDALGetRasterYSize(handle)) }
    public var rasterCount: Int { Int(GDALGetRasterCount(handle)) }

    /// Returns the dataset's affine transform, or nil if none is set.
    public var geoTransform: GeoTransform? {
        get {
            var buf = [Double](repeating: 0, count: 6)
            let err = buf.withUnsafeMutableBufferPointer {
                GDALGetGeoTransform(handle, $0.baseAddress)
            }
            return err == CE_None ? GeoTransform(buf) : nil
        }
        set {
            guard var gt = newValue?.array else { return }
            gt.withUnsafeMutableBufferPointer { _ = GDALSetGeoTransform(handle, $0.baseAddress) }
        }
    }

    /// WKT of the dataset's spatial reference, if any.
    public var projectionWKT: String {
        get { GDALGetProjectionRef(handle).map(String.init(cString:)) ?? "" }
        set { _ = GDALSetProjection(handle, newValue) }
    }

    public var spatialReference: SpatialReference? {
        get {
            let wkt = projectionWKT
            guard !wkt.isEmpty else { return nil }
            return try? SpatialReference(wkt: wkt)
        }
        set {
            if let wkt = try? newValue?.toWKT() {
                projectionWKT = wkt
            }
        }
    }

    /// Returns band at 1-based index (GDAL convention).
    public func band(_ index: Int) -> RasterBand {
        precondition(index >= 1 && index <= rasterCount, "band index out of range")
        let bandH = GDALGetRasterBand(handle, Int32(index)).unsafelyUnwrapped
        return RasterBand(bandH, owner: self)
    }

    /// Flushes any pending writes to disk.
    public func flush() {
        GDALFlushCache(handle)
    }

    /// Dataset-level metadata for the given domain (nil → default domain).
    public func metadata(domain: String? = nil) -> [String: String] {
        let raw = GDALGetMetadata(handle, domain)
        return StringList.dictionary(from: raw)
    }
}
