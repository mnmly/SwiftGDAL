import Testing
import Foundation
@testable import SwiftGDAL

@Suite("Vector / OGR")
struct VectorTests {

    @Test
    func geometryRoundTripWKT() throws {
        let g = try Geometry(wkt: "POINT (1 2)")
        #expect(g.type == .point)
        #expect(g.pointCount == 1)
        let p = g.point(at: 0)
        #expect(p.x == 1 && p.y == 2)
        let wkt = try g.toWKT()
        #expect(wkt.contains("POINT"))
    }

    @Test
    func geometryWKBRoundTrip() throws {
        let original = try Geometry(wkt: "LINESTRING (0 0, 1 1, 2 0)")
        let wkb = original.toWKB()
        let reread = try Geometry(wkb: wkb)
        #expect(reread.type == .lineString)
        #expect(reread.pointCount == 3)
    }

    @Test
    func polygonHelper() throws {
        let g = Geometry.polygon(outer: [
            (0, 0), (1, 0), (1, 1), (0, 1),
        ])
        #expect(g.type == .polygon)
        let env = g.envelope
        #expect(env.minX == 0 && env.maxX == 1)
        #expect(env.minY == 0 && env.maxY == 1)
    }

    @Test
    func createGeoJSONLayerWriteReadBack() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftgdal-\(UUID().uuidString).geojson")
        defer { try? FileManager.default.removeItem(at: tmp) }

        // --- write ---
        let ds = try VectorDataset(creating: tmp.path, driver: "GeoJSON")
        let layer = try ds.createLayer(
            name: "points",
            geometryType: .point,
            spatialReference: try SpatialReference(epsg: 4326)
        )
        try layer.createField(FieldDefn(name: "name", type: .string, width: 32))
        try layer.createField(FieldDefn(name: "score", type: .real))

        for (i, pt) in [(10.0, 20.0), (-5.0, 7.5), (0.0, 0.0)].enumerated() {
            let f = Feature(forLayer: layer)
            f[field: "name"] = .string("p\(i)")
            f[field: "score"] = .real(Double(i) * 1.5)
            f.geometry = Geometry.point(x: pt.0, y: pt.1)
            try layer.create(f)
        }
        ds.flush()

        // --- read back ---
        let readDS = try VectorDataset(opening: tmp.path)
        #expect(readDS.layerCount == 1)
        let readLayer = readDS.layer(at: 0)
        #expect(readLayer.featureCount() == 3)

        var seen: [(String, Double, Double, Double)] = []
        for f in readLayer.features() {
            guard case .string(let n) = f[field: "name"],
                  case .real(let s) = f[field: "score"],
                  let g = f.geometry else { continue }
            let p = g.point(at: 0)
            seen.append((n, s, p.x, p.y))
        }
        #expect(seen.count == 3)
        #expect(seen.contains { $0.0 == "p0" && $0.1 == 0.0 && $0.2 == 10.0 })
    }

    @Test
    func updateAndDeleteFeature() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftgdal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let shp = dir.appendingPathComponent("things.gpkg").path

        let ds = try VectorDataset(creating: shp, driver: "GPKG")
        let layer = try ds.createLayer(name: "things", geometryType: .point)
        try layer.createField(FieldDefn(name: "label", type: .string, width: 16))

        let a = Feature(forLayer: layer)
        a[field: "label"] = .string("alpha")
        a.geometry = Geometry.point(x: 0, y: 0)
        try layer.create(a)
        let aFID = a.fid

        let b = Feature(forLayer: layer)
        b[field: "label"] = .string("beta")
        b.geometry = Geometry.point(x: 1, y: 1)
        try layer.create(b)
        let bFID = b.fid
        ds.flush()

        // update alpha
        let reopened = try VectorDataset(opening: shp, access: .update)
        let l = reopened.layer(at: 0)
        // Collect-then-mutate: SetFeature during GetNextFeature iteration can
        // invalidate driver-internal cursors.
        var alpha: Feature?
        for f in l.features() where f.fid == aFID { alpha = f }
        if let f = alpha {
            f[field: "label"] = .string("ALPHA")
            try l.update(f)
        }
        try l.delete(fid: bFID)
        reopened.flush()

        // verify
        let v = try VectorDataset(opening: shp)
        let vl = v.layer(at: 0)
        var labels: Set<String> = []
        for f in vl.features() {
            if case .string(let s) = f[field: "label"] { labels.insert(s) }
        }
        #expect(labels == ["ALPHA"])
    }

    @Test
    func spatialAndAttributeFilters() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftgdal-\(UUID().uuidString).geojson")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let ds = try VectorDataset(creating: tmp.path, driver: "GeoJSON")
        let layer = try ds.createLayer(name: "pts", geometryType: .point)
        try layer.createField(FieldDefn(name: "k", type: .integer))

        for (i, c) in [(0, (0.0, 0.0)), (1, (5.0, 5.0)), (2, (10.0, 10.0))] {
            let f = Feature(forLayer: layer)
            f[field: "k"] = .integer(Int32(i))
            f.geometry = Geometry.point(x: c.0, y: c.1)
            try layer.create(f)
        }
        ds.flush()

        let ro = try VectorDataset(opening: tmp.path)
        let l = ro.layer(at: 0)

        l.setSpatialFilter(envelope: (-1, -1, 6, 6))
        #expect(l.featureCount(forceCompute: true) == 2)

        l.setSpatialFilter(envelope: nil)
        try l.setAttributeFilter("k = 2")
        #expect(l.featureCount(forceCompute: true) == 1)
    }
}
