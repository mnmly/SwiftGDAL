import Testing
import Foundation
@testable import SwiftGDAL

@Suite("SwiftGDAL")
struct SwiftGDALTests {

    @Test
    func versionInfoNonEmpty() {
        let v = GDAL.versionInfo
        #expect(v.contains("GDAL"))
    }

    @Test
    func createReadWriteRoundTrip() throws {
        // Write a 4×4 Byte raster via MEM driver, then read it back.
        let ds = try Dataset(
            creating: "/vsimem/test.tif",
            driver: "GTiff",
            width: 4,
            height: 4,
            bands: 1,
            dataType: .byte
        )
        ds.geoTransform = GeoTransform(
            originX: 100, pixelWidth: 1,
            originY: 200, pixelHeight: -1
        )

        let pixels: [UInt8] = [
            1, 2, 3, 4,
            5, 6, 7, 8,
            9, 10, 11, 12,
            13, 14, 15, 16,
        ]
        try ds.band(1).write(pixels, rect: (0, 0, 4, 4))
        ds.flush()

        let read = try ds.band(1).read(as: UInt8.self)
        #expect(read == pixels)

        let gt = try #require(ds.geoTransform)
        #expect(gt.originX == 100)
        #expect(gt.pixelHeight == -1)
    }

    @Test
    func asyncReadOffMainActor() async throws {
        let ds = try Dataset(
            creating: "/vsimem/async.tif",
            driver: "GTiff",
            width: 8, height: 8, bands: 1, dataType: .float32
        )
        let pixels = (0..<64).map { Float($0) }
        try await ds.band(1).write(pixels, rect: (0, 0, 8, 8))
        ds.flush()

        let out: [Float] = try await ds.band(1).read(as: Float.self)
        #expect(out == pixels)
    }

    @Test
    func blockStreaming() async throws {
        let ds = try Dataset(
            creating: "/vsimem/blocks.tif",
            driver: "GTiff",
            width: 16, height: 16, bands: 1, dataType: .uint16
        )
        let pixels = (0..<256).map { UInt16($0) }
        try await ds.band(1).write(pixels, rect: (0, 0, 16, 16))
        ds.flush()

        var seenPixels = 0
        for try await block in ds.band(1).blocks(as: UInt16.self) {
            seenPixels += block.pixels.count
        }
        #expect(seenPixels == 256)
    }

    @Test
    func spatialReferenceFromEPSG() throws {
        let srs = try SpatialReference(epsg: 4326)
        let wkt = try srs.toWKT()
        #expect(wkt.contains("WGS"))
    }

    @Test
    func coordinateTransformWGS84toWebMercator() throws {
        let wgs84 = try SpatialReference(epsg: 4326)
        let webMercator = try SpatialReference(epsg: 3857)
        let t = try CoordinateTransform(from: wgs84, to: webMercator)
        // GDAL 3 with EPSG:4326 uses lat/lon axis order by default → pass lat, lon.
        let p = try t.transform(x: 0, y: 0)
        #expect(abs(p.x) < 1e-6)
        #expect(abs(p.y) < 1e-6)
    }

    @Test
    func openFailureSurfacesError() {
        #expect(throws: GDALError.self) {
            _ = try Dataset(opening: "/does/not/exist.tif")
        }
    }
}
