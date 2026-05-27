import Testing
import Foundation
@testable import SwiftGDAL

@Suite("GDAL Ops")
struct OpsTests {

    /// Helper: build a small in-memory raster with a known pattern.
    private func makeSourceRaster(
        path: String,
        width: Int = 8,
        height: Int = 8
    ) throws -> Dataset {
        let ds = try Dataset(
            creating: path,
            driver: "GTiff",
            width: width, height: height,
            bands: 1, dataType: .byte
        )
        ds.geoTransform = GeoTransform(
            originX: 0, pixelWidth: 1,
            originY: Double(height), pixelHeight: -1
        )
        ds.projectionWKT = try SpatialReference(epsg: 4326).toWKT()
        let pixels: [UInt8] = (0..<(width * height)).map { UInt8($0 % 250) }
        try ds.band(1).write(pixels, rect: (0, 0, width, height))
        ds.flush()
        return ds
    }

    @Test
    func translateResizesAndConvertsType() throws {
        let src = try makeSourceRaster(path: "/vsimem/ops-src.tif")
        let out = try GDALOps.translate(
            source: src,
            destination: "/vsimem/ops-out.tif",
            options: ["-outsize", "4", "4", "-ot", "Float32"]
        )
        #expect(out.rasterWidth == 4)
        #expect(out.rasterHeight == 4)
        #expect(out.band(1).dataType == .float32)
    }

    @Test
    func warpReprojectsToWebMercator() throws {
        let src = try makeSourceRaster(path: "/vsimem/warp-src.tif")
        let out = try GDALOps.warp(
            sources: [src],
            destination: "/vsimem/warp-out.tif",
            options: ["-t_srs", "EPSG:3857", "-ts", "16", "16"]
        )
        #expect(out.rasterWidth == 16)
        #expect(out.rasterHeight == 16)
        // Projection WKT should now reference a Mercator projection.
        #expect(out.projectionWKT.contains("Mercator") || out.projectionWKT.contains("3857"))
    }

    @Test
    func datasetTranslateConvenience() throws {
        let src = try makeSourceRaster(path: "/vsimem/conv-src.tif")
        let out = try src.translate(to: "/vsimem/conv-out.tif", options: ["-outsize", "2", "2"])
        #expect(out.rasterWidth == 2)
    }

    @Test
    func buildVRTFromHandles() throws {
        let a = try makeSourceRaster(path: "/vsimem/vrt-a.tif")
        let b = try makeSourceRaster(path: "/vsimem/vrt-b.tif")
        let vrt = try GDALOps.buildVRT(
            sources: [a, b],
            destination: "/vsimem/vrt-out.vrt"
        )
        #expect(vrt.rasterCount >= 1)
    }

    @Test
    func vectorTranslateReprojectsShapefile() throws {
        // Build a tiny source shapefile in WGS84, then ogr2ogr it to Web Mercator
        // as GeoJSON.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftgdal-ops-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let shpPath = dir.appendingPathComponent("src.shp").path

        let src = try VectorDataset(creating: shpPath, driver: "ESRI Shapefile")
        let layer = try src.createLayer(
            name: "pts",
            geometryType: .point,
            spatialReference: try SpatialReference(epsg: 4326)
        )
        for (i, c) in [(0.0, 0.0), (10.0, 20.0)].enumerated() {
            let f = Feature(forLayer: layer)
            f.geometry = Geometry.point(x: c.0, y: c.1)
            _ = i
            try layer.create(f)
        }
        src.flush()

        let reopened = try VectorDataset(opening: shpPath)
        let outPath = dir.appendingPathComponent("out.geojson").path
        let translated = try GDALOps.vectorTranslate(
            sources: [reopened],
            destination: outPath,
            options: ["-f", "GeoJSON", "-t_srs", "EPSG:3857"]
        )
        #expect(translated.layerCount == 1)
        translated.flush()

        // GeoJSON serializes on close — reopen to read the written file back.
        let verify = try VectorDataset(opening: outPath)
        let layerV = verify.layer(at: 0)
        var firstPoint: (x: Double, y: Double, z: Double)?
        for f in layerV.features() {
            if let g = f.geometry { firstPoint = g.point(at: 0); break }
        }
        let p = try #require(firstPoint)
        // (0,0) WGS84 → (0,0) in EPSG:3857 within tolerance
        #expect(abs(p.x) < 1e-3)
        #expect(abs(p.y) < 1e-3)
    }

    @Test
    func translateUsageErrorSurfaces() {
        // Bogus flag should produce a GDALError, not a crash.
        do {
            let src = try makeSourceRaster(path: "/vsimem/usage-src.tif")
            _ = try GDALOps.translate(
                source: src,
                destination: "/vsimem/usage-out.tif",
                options: ["--definitely-not-a-real-flag"]
            )
            Issue.record("expected throw")
        } catch is GDALError {
            // pass
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }
}
