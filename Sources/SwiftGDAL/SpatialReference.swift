import Foundation
import gdal

/// A coordinate reference system (CRS) — wraps `OGRSpatialReferenceH`.
///
/// Use one of the convenience initializers (``init(epsg:)``,
/// ``init(wkt:)``, ``init(proj4:)``) to load a known CRS, then export to
/// WKT or PROJ.4 via ``toWKT()`` / ``toPROJ4()``. Pair two of them with
/// ``CoordinateTransform`` for point reprojection.
public final class SpatialReference {

    nonisolated(unsafe) let handle: OGRSpatialReferenceH

    /// Creates an empty spatial reference. Most callers should use one of
    /// the parsing initializers below.
    public init() {
        GDAL.registerAll()
        self.handle = OSRNewSpatialReference(nil)
    }

    /// Parses a WKT representation.
    ///
    /// - Parameter wkt: Well-Known Text spatial reference string.
    /// - Throws: ``GDALError`` if `wkt` is invalid.
    public convenience init(wkt: String) throws {
        self.init()
        CPLErrorReset()
        var mutWkt = wkt.cString(using: .utf8) ?? []
        let err = mutWkt.withUnsafeMutableBufferPointer { buf -> OGRErr in
            var ptr: UnsafeMutablePointer<CChar>? = buf.baseAddress
            return withUnsafeMutablePointer(to: &ptr) { OSRImportFromWkt(handle, $0) }
        }
        guard err == OGRERR_NONE else {
            throw GDALError.lastError(fallback: "OSRImportFromWkt failed")
        }
    }

    /// Builds an SRS from an EPSG code.
    ///
    /// - Parameter epsg: EPSG numeric code, e.g. `4326` (WGS84), `3857`
    ///   (Web Mercator).
    /// - Throws: ``GDALError`` if the code is unknown to PROJ.
    public convenience init(epsg: Int) throws {
        self.init()
        CPLErrorReset()
        let err = OSRImportFromEPSG(handle, Int32(epsg))
        guard err == OGRERR_NONE else {
            throw GDALError.lastError(fallback: "OSRImportFromEPSG(\(epsg)) failed")
        }
    }

    /// Builds an SRS from a PROJ.4 string.
    ///
    /// - Parameter proj4: PROJ.4 definition (e.g. `"+proj=utm +zone=33 +datum=WGS84"`).
    /// - Throws: ``GDALError`` if the string can't be parsed.
    public convenience init(proj4: String) throws {
        self.init()
        CPLErrorReset()
        let err = OSRImportFromProj4(handle, proj4)
        guard err == OGRERR_NONE else {
            throw GDALError.lastError(fallback: "OSRImportFromProj4 failed")
        }
    }

    deinit {
        OSRDestroySpatialReference(handle)
    }

    /// Exports the CRS as a WKT string.
    /// - Throws: ``GDALError`` if export fails.
    public func toWKT() throws -> String {
        var out: UnsafeMutablePointer<CChar>?
        CPLErrorReset()
        let err = OSRExportToWkt(handle, &out)
        guard err == OGRERR_NONE, let out else {
            throw GDALError.lastError(fallback: "OSRExportToWkt failed")
        }
        defer { VSIFree(out) }
        return String(cString: out)
    }

    /// Exports the CRS as a PROJ.4 string.
    /// - Throws: ``GDALError`` if export fails.
    public func toPROJ4() throws -> String {
        var out: UnsafeMutablePointer<CChar>?
        CPLErrorReset()
        let err = OSRExportToProj4(handle, &out)
        guard err == OGRERR_NONE, let out else {
            throw GDALError.lastError(fallback: "OSRExportToProj4 failed")
        }
        defer { VSIFree(out) }
        return String(cString: out)
    }

    /// EPSG (or other authority) numeric code for this CRS, if it has one.
    public var authorityCode: Int? {
        guard let raw = OSRGetAuthorityCode(handle, nil) else { return nil }
        return Int(String(cString: raw))
    }
}

/// A reusable transformer between two ``SpatialReference``s.
///
/// Build once, reuse for many points. Used by ``Geometry/transform(_:)``
/// for in-place geometry reprojection.
public final class CoordinateTransform {

    nonisolated(unsafe) let handle: OGRCoordinateTransformationH
    private let source: SpatialReference
    private let target: SpatialReference

    /// Builds a transformer.
    ///
    /// - Parameters:
    ///   - source: Source CRS.
    ///   - target: Target CRS.
    /// - Throws: ``GDALError`` if PROJ can't build a path between the two.
    public init(from source: SpatialReference, to target: SpatialReference) throws {
        CPLErrorReset()
        guard let h = OCTNewCoordinateTransformation(source.handle, target.handle) else {
            throw GDALError.lastError(fallback: "OCTNewCoordinateTransformation failed")
        }
        self.handle = h
        self.source = source
        self.target = target
    }

    deinit {
        OCTDestroyCoordinateTransformation(handle)
    }

    /// Transforms a single point.
    ///
    /// > Note: For EPSG:4326 inputs GDAL 3 uses lat/lon axis order by
    /// > default — pass latitude as `x` and longitude as `y`, or set
    /// > `OGR_OSR_TRADITIONAL_GIS_ORDER=lon,lat` for legacy behavior.
    ///
    /// - Parameters:
    ///   - x: Source X (axis order depends on source CRS).
    ///   - y: Source Y.
    ///   - z: Optional elevation. Defaults to `0`.
    /// - Returns: Transformed coordinate in the target CRS.
    public func transform(x: Double, y: Double, z: Double = 0) throws -> (x: Double, y: Double, z: Double) {
        var X = x, Y = y, Z = z
        let ok = OCTTransform(handle, 1, &X, &Y, &Z)
        guard ok != 0 else {
            throw GDALError.lastError(fallback: "OCTTransform failed")
        }
        return (X, Y, Z)
    }

    /// Bulk transform — modifies coordinate arrays in place.
    ///
    /// - Parameters:
    ///   - xs: X (or first axis) coordinates. Mutated to the target CRS.
    ///   - ys: Y (or second axis) coordinates. Same length as `xs`.
    ///   - zs: Elevations. Same length as `xs`.
    public func transform(xs: inout [Double], ys: inout [Double], zs: inout [Double]) throws {
        precondition(xs.count == ys.count && ys.count == zs.count)
        let count = Int32(xs.count)
        let ok = xs.withUnsafeMutableBufferPointer { xp in
            ys.withUnsafeMutableBufferPointer { yp in
                zs.withUnsafeMutableBufferPointer { zp in
                    OCTTransform(handle, count, xp.baseAddress, yp.baseAddress, zp.baseAddress)
                }
            }
        }
        guard ok != 0 else {
            throw GDALError.lastError(fallback: "OCTTransform failed")
        }
    }
}
