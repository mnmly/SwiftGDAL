import Foundation
import gdal

/// Wraps an OGR geometry.
///
/// `Geometry` always owns its underlying `OGRGeometryH`. Constructors that
/// read from a foreign handle (e.g. `OGR_F_GetGeometryRef`, which returns a
/// borrowed pointer) clone first, so Swift ownership is unambiguous.
public final class Geometry {

    nonisolated(unsafe) let handle: OGRGeometryH

    /// Internal init that takes ownership of the handle as-is.
    init(owned handle: OGRGeometryH) {
        self.handle = handle
    }

    /// Internal init that clones a borrowed handle.
    init?(cloning borrowed: OGRGeometryH?) {
        guard let borrowed, let cloned = OGR_G_Clone(borrowed) else { return nil }
        self.handle = cloned
    }

    deinit {
        OGR_G_DestroyGeometry(handle)
    }

    // MARK: - Constructors

    public convenience init(wkt: String) throws {
        GDAL.registerAll()
        CPLErrorReset()
        var geom: OGRGeometryH? = nil
        // OGR_G_CreateFromWkt advances the input pointer, so duplicate first.
        let dup = wkt.withCString { strdup($0) }
        defer { free(dup) }
        var cursor: UnsafeMutablePointer<CChar>? = dup
        let err = withUnsafeMutablePointer(to: &cursor) { cursorPtr -> OGRErr in
            OGR_G_CreateFromWkt(cursorPtr, nil, &geom)
        }
        guard err == OGRERR_NONE, let owned = geom else {
            throw GDALError.lastError(fallback: "OGR_G_CreateFromWkt failed")
        }
        self.init(owned: owned)
    }

    public convenience init(wkb: Data) throws {
        GDAL.registerAll()
        CPLErrorReset()
        var ptr: OGRGeometryH? = nil
        let err = wkb.withUnsafeBytes { raw -> OGRErr in
            guard let base = raw.baseAddress else { return OGRERR_FAILURE }
            return OGR_G_CreateFromWkb(base, nil, &ptr, Int32(wkb.count))
        }
        guard err == OGRERR_NONE, let owned = ptr else {
            throw GDALError.lastError(fallback: "OGR_G_CreateFromWkb failed")
        }
        self.init(owned: owned)
    }

    /// Convenience constructor for a 2D point.
    public static func point(x: Double, y: Double) -> Geometry {
        let h = OGR_G_CreateGeometry(wkbPoint).unsafelyUnwrapped
        OGR_G_SetPoint_2D(h, 0, x, y)
        return Geometry(owned: h)
    }

    public static func point(x: Double, y: Double, z: Double) -> Geometry {
        let h = OGR_G_CreateGeometry(wkbPoint25D).unsafelyUnwrapped
        OGR_G_SetPoint(h, 0, x, y, z)
        return Geometry(owned: h)
    }

    /// Builds a polygon from a single outer ring `[(x, y)]`. First and last
    /// coordinates are joined automatically.
    public static func polygon(outer ring: [(x: Double, y: Double)]) -> Geometry {
        polygon(outer: ring, inner: [])
    }

    /// Builds a polygon with an outer ring and zero or more inner (hole) rings.
    /// Each ring is auto-closed.
    public static func polygon(
        outer ring: [(x: Double, y: Double)],
        inner holes: [[(x: Double, y: Double)]]
    ) -> Geometry {
        let p = OGR_G_CreateGeometry(wkbPolygon).unsafelyUnwrapped
        _ = OGR_G_AddGeometryDirectly(p, makeLinearRing(ring))
        for hole in holes {
            _ = OGR_G_AddGeometryDirectly(p, makeLinearRing(hole))
        }
        return Geometry(owned: p)
    }

    /// Builds a `LINESTRING` from a coordinate sequence.
    public static func lineString(_ points: [(x: Double, y: Double)]) -> Geometry {
        let l = OGR_G_CreateGeometry(wkbLineString).unsafelyUnwrapped
        for (i, c) in points.enumerated() {
            OGR_G_SetPoint_2D(l, Int32(i), c.x, c.y)
        }
        return Geometry(owned: l)
    }

    /// Builds a `MULTIPOINT` from a coordinate list.
    public static func multiPoint(_ points: [(x: Double, y: Double)]) -> Geometry {
        let mp = OGR_G_CreateGeometry(wkbMultiPoint).unsafelyUnwrapped
        for c in points {
            let p = OGR_G_CreateGeometry(wkbPoint).unsafelyUnwrapped
            OGR_G_SetPoint_2D(p, 0, c.x, c.y)
            _ = OGR_G_AddGeometryDirectly(mp, p)
        }
        return Geometry(owned: mp)
    }

    /// Builds a `MULTILINESTRING` from a list of coordinate sequences.
    public static func multiLineString(_ lines: [[(x: Double, y: Double)]]) -> Geometry {
        let ml = OGR_G_CreateGeometry(wkbMultiLineString).unsafelyUnwrapped
        for pts in lines {
            let l = OGR_G_CreateGeometry(wkbLineString).unsafelyUnwrapped
            for (i, c) in pts.enumerated() {
                OGR_G_SetPoint_2D(l, Int32(i), c.x, c.y)
            }
            _ = OGR_G_AddGeometryDirectly(ml, l)
        }
        return Geometry(owned: ml)
    }

    /// Builds a `MULTIPOLYGON` from a list of polygons. Each polygon is
    /// `(outer, [holes...])`.
    public static func multiPolygon(
        _ polys: [(outer: [(x: Double, y: Double)], inner: [[(x: Double, y: Double)]])]
    ) -> Geometry {
        let mp = OGR_G_CreateGeometry(wkbMultiPolygon).unsafelyUnwrapped
        for spec in polys {
            let poly = OGR_G_CreateGeometry(wkbPolygon).unsafelyUnwrapped
            _ = OGR_G_AddGeometryDirectly(poly, makeLinearRing(spec.outer))
            for hole in spec.inner {
                _ = OGR_G_AddGeometryDirectly(poly, makeLinearRing(hole))
            }
            _ = OGR_G_AddGeometryDirectly(mp, poly)
        }
        return Geometry(owned: mp)
    }

    /// Builds a `GEOMETRYCOLLECTION` from heterogeneous child geometries.
    /// Children are cloned so the caller keeps ownership of their `Geometry`s.
    public static func collection(_ children: [Geometry]) -> Geometry {
        let c = OGR_G_CreateGeometry(wkbGeometryCollection).unsafelyUnwrapped
        for child in children {
            if let dup = OGR_G_Clone(child.handle) {
                _ = OGR_G_AddGeometryDirectly(c, dup)
            }
        }
        return Geometry(owned: c)
    }

    private static func makeLinearRing(_ pts: [(x: Double, y: Double)]) -> OGRGeometryH {
        let r = OGR_G_CreateGeometry(wkbLinearRing).unsafelyUnwrapped
        for (i, c) in pts.enumerated() {
            OGR_G_SetPoint_2D(r, Int32(i), c.x, c.y)
        }
        if let first = pts.first, let last = pts.last, (first.x != last.x || first.y != last.y) {
            OGR_G_SetPoint_2D(r, Int32(pts.count), first.x, first.y)
        }
        return r
    }

    // MARK: - Shape

    public var type: GeometryType { GeometryType(OGR_G_GetGeometryType(handle)) }

    public var pointCount: Int { Int(OGR_G_GetPointCount(handle)) }

    public var dimension: Int { Int(OGR_G_GetCoordinateDimension(handle)) }

    public var isEmpty: Bool { OGR_G_IsEmpty(handle) != 0 }

    public var envelope: (minX: Double, maxX: Double, minY: Double, maxY: Double) {
        var env = OGREnvelope()
        OGR_G_GetEnvelope(handle, &env)
        return (env.MinX, env.MaxX, env.MinY, env.MaxY)
    }

    /// Point accessor for `.point` / `.lineString` geometries. Index must be
    /// `0..<pointCount`.
    public func point(at index: Int) -> (x: Double, y: Double, z: Double) {
        var x: Double = 0, y: Double = 0, z: Double = 0
        OGR_G_GetPoint(handle, Int32(index), &x, &y, &z)
        return (x, y, z)
    }

    /// Same as `point(at:)` but as a `SIMD2<Double>` (x, y).
    public func point2(at index: Int) -> SIMD2<Double> {
        let p = point(at: index)
        return SIMD2(p.x, p.y)
    }

    /// Same as `point(at:)` but as a `SIMD3<Double>` (x, y, z).
    public func point3(at index: Int) -> SIMD3<Double> {
        let p = point(at: index)
        return SIMD3(p.x, p.y, p.z)
    }

    /// All points of a `.point` / `.lineString` / `.linearRing` geometry as
    /// `SIMD2<Double>`. Returns an empty array for other geometry types.
    public func points2() -> [SIMD2<Double>] {
        let n = pointCount
        guard n > 0 else { return [] }
        return (0..<n).map { point2(at: $0) }
    }

    // MARK: - SRS

    public var spatialReference: SpatialReference? {
        get {
            guard let h = OGR_G_GetSpatialReference(handle) else { return nil }
            // OGR_G_GetSpatialReference is borrowed — wrap WKT to get an owned copy.
            var ptr: UnsafeMutablePointer<CChar>?
            guard OSRExportToWkt(h, &ptr) == OGRERR_NONE, let ptr else { return nil }
            defer { VSIFree(ptr) }
            return try? SpatialReference(wkt: String(cString: ptr))
        }
        set {
            OGR_G_AssignSpatialReference(handle, newValue?.handle)
        }
    }

    /// Transforms the geometry in place using a prepared `CoordinateTransform`.
    public func transform(_ ct: CoordinateTransform) throws {
        CPLErrorReset()
        let err = OGR_G_Transform(handle, ct.handle)
        guard err == OGRERR_NONE else {
            throw GDALError.lastError(fallback: "OGR_G_Transform failed")
        }
    }

    // MARK: - Export

    public func toWKT() throws -> String {
        var ptr: UnsafeMutablePointer<CChar>?
        CPLErrorReset()
        let err = OGR_G_ExportToWkt(handle, &ptr)
        guard err == OGRERR_NONE, let ptr else {
            throw GDALError.lastError(fallback: "OGR_G_ExportToWkt failed")
        }
        defer { VSIFree(ptr) }
        return String(cString: ptr)
    }

    public func toWKB() -> Data {
        let size = Int(OGR_G_WkbSize(handle))
        var data = Data(count: size)
        data.withUnsafeMutableBytes { raw in
            if let base = raw.baseAddress {
                _ = OGR_G_ExportToWkb(handle, wkbNDR, base.assumingMemoryBound(to: UInt8.self))
            }
        }
        return data
    }

    public func toGeoJSON() -> String {
        guard let ptr = OGR_G_ExportToJson(handle) else { return "" }
        defer { VSIFree(ptr) }
        return String(cString: ptr)
    }
}

