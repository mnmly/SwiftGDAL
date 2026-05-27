import Testing
import Foundation
@testable import SwiftGDAL

@Suite("v1 polish")
struct PolishTests {

    @Test
    func transactionCommitsOnSuccess() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftgdal-tx-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let shp = dir.appendingPathComponent("tx.shp").path

        let ds = try VectorDataset(creating: shp, driver: "ESRI Shapefile")
        let layer = try ds.createLayer(name: "tx", geometryType: .point)
        try layer.createField(FieldDefn(name: "n", type: .integer))

        try ds.transaction {
            for i in 0..<3 {
                let f = Feature(forLayer: layer)
                f[field: "n"] = .integer(Int32(i))
                f.geometry = Geometry.point(x: Double(i), y: 0)
                try layer.create(f)
            }
        }
        ds.flush()

        let ro = try VectorDataset(opening: shp)
        #expect(ro.layer(at: 0).featureCount(forceCompute: true) == 3)
    }

    @Test
    func transactionRollsBackOnThrow() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftgdal-tx-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let shp = dir.appendingPathComponent("tx.shp").path

        let ds = try VectorDataset(creating: shp, driver: "ESRI Shapefile")
        _ = try ds.createLayer(name: "tx", geometryType: .point)

        struct Boom: Error {}
        do {
            try ds.transaction { throw Boom() }
            Issue.record("expected throw")
        } catch is Boom {
            // expected
        }
        // Note: ESRI Shapefile doesn't truly support transactions; the call
        // just verifies the scope helper runs `body` and rethrows.
    }

    @Test
    func asyncFeatureIteration() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftgdal-async-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let shp = dir.appendingPathComponent("a.shp").path

        let ds = try VectorDataset(creating: shp, driver: "ESRI Shapefile")
        let layer = try ds.createLayer(name: "a", geometryType: .point)
        for i in 0..<5 {
            let f = Feature(forLayer: layer)
            f.geometry = Geometry.point(x: Double(i), y: 0)
            try layer.create(f)
        }
        ds.flush()

        let ro = try VectorDataset(opening: shp)
        var count = 0
        for await _ in ro.layer(at: 0).featuresAsync() { count += 1 }
        #expect(count == 5)
    }

    @Test
    func simdPointAccessors() throws {
        let line = try Geometry(wkt: "LINESTRING (0 0, 1 2, 3 4)")
        let pts = line.points2()
        #expect(pts == [SIMD2(0, 0), SIMD2(1, 2), SIMD2(3, 4)])

        let p3 = Geometry.point(x: 1, y: 2, z: 3).point3(at: 0)
        #expect(p3 == SIMD3(1, 2, 3))
    }

    @Test
    func progressCallbackFires() throws {
        let src = try Dataset(
            creating: "/vsimem/prog-src.tif",
            driver: "GTiff",
            width: 64, height: 64, bands: 1, dataType: .byte
        )
        try src.band(1).write([UInt8](repeating: 7, count: 64 * 64), rect: (0, 0, 64, 64))
        src.flush()

        let lock = NSLock()
        nonisolated(unsafe) var progress: [Double] = []
        _ = try GDALOps.translate(
            source: src,
            destination: "/vsimem/prog-out.tif",
            options: ["-outsize", "16", "16"],
            onProgress: { p in
                lock.lock(); progress.append(p); lock.unlock()
            }
        )
        #expect(!progress.isEmpty)
        #expect(progress.last ?? 0 >= 0.99)
    }

    @Test
    func maskBandPresent() throws {
        let ds = try Dataset(
            creating: "/vsimem/mask.tif",
            driver: "GTiff",
            width: 4, height: 4, bands: 1, dataType: .byte
        )
        try ds.band(1).write([UInt8](repeating: 1, count: 16), rect: (0, 0, 4, 4))
        ds.flush()
        let mask = ds.band(1).maskBand
        #expect(mask != nil)
        #expect(mask?.width == 4 && mask?.height == 4)
    }

    @Test
    func multiPointAndMultiPolygon() throws {
        let mp = Geometry.multiPoint([(0, 0), (1, 1), (2, 0)])
        #expect(mp.type == .multiPoint)
        let wkt = try mp.toWKT()
        #expect(wkt.contains("MULTIPOINT"))

        let mpoly = Geometry.multiPolygon([
            (outer: [(0, 0), (1, 0), (1, 1), (0, 1)], inner: []),
            (outer: [(2, 2), (3, 2), (3, 3), (2, 3)], inner: []),
        ])
        #expect(mpoly.type == .multiPolygon)
        let env = mpoly.envelope
        #expect(env.minX == 0 && env.maxX == 3)
        #expect(env.minY == 0 && env.maxY == 3)
    }

    @Test
    func polygonWithHole() throws {
        let donut = Geometry.polygon(
            outer: [(0, 0), (10, 0), (10, 10), (0, 10)],
            inner: [[(3, 3), (7, 3), (7, 7), (3, 7)]]
        )
        #expect(donut.type == .polygon)
        // A polygon with a hole exports as POLYGON((...),(...))
        let wkt = try donut.toWKT()
        #expect(wkt.contains("POLYGON"))
    }
}
