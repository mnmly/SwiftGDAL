import Foundation
import gdal

/// Wrapper over `OGRSpatialReferenceH`.
public final class SpatialReference {

    nonisolated(unsafe) let handle: OGRSpatialReferenceH

    public init() {
        GDAL.registerAll()
        self.handle = OSRNewSpatialReference(nil)
    }

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

    /// Builds an SRS from an EPSG code, e.g. 4326 for WGS84.
    public convenience init(epsg: Int) throws {
        self.init()
        CPLErrorReset()
        let err = OSRImportFromEPSG(handle, Int32(epsg))
        guard err == OGRERR_NONE else {
            throw GDALError.lastError(fallback: "OSRImportFromEPSG(\(epsg)) failed")
        }
    }

    /// Builds an SRS from a PROJ.4 string.
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

    public var authorityCode: Int? {
        guard let raw = OSRGetAuthorityCode(handle, nil) else { return nil }
        return Int(String(cString: raw))
    }
}

/// A coordinate transformer between two SRSs.
public final class CoordinateTransform {

    nonisolated(unsafe) let handle: OGRCoordinateTransformationH
    private let source: SpatialReference
    private let target: SpatialReference

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

    /// Transforms a single (x, y) — optionally with z.
    public func transform(x: Double, y: Double, z: Double = 0) throws -> (x: Double, y: Double, z: Double) {
        var X = x, Y = y, Z = z
        let ok = OCTTransform(handle, 1, &X, &Y, &Z)
        guard ok != 0 else {
            throw GDALError.lastError(fallback: "OCTTransform failed")
        }
        return (X, Y, Z)
    }

    /// Bulk transform — modifies arrays in place.
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
