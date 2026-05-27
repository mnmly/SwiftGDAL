import Foundation
import SwiftGDAL

guard CommandLine.arguments.count > 1 else {
    print("usage: gdalinfo <path>")
    print("       Reports raster shape, geo-transform, projection, and per-band stats.")
    print("       Works on any path GDAL understands: local files, /vsicurl/..., /vsis3/..., etc.")
    exit(2)
}

let path = CommandLine.arguments[1]

print("SwiftGDAL \(GDAL.versionInfo)")
print("---")

do {
    let ds = try Dataset(opening: path)
    print("path:     \(path)")
    print("size:     \(ds.rasterWidth) × \(ds.rasterHeight)")
    print("bands:    \(ds.rasterCount)")

    if let gt = ds.geoTransform {
        print("origin:   (\(gt.originX), \(gt.originY))")
        print("pixel:    \(gt.pixelWidth) × \(gt.pixelHeight)")
    }

    if !ds.projectionWKT.isEmpty,
       let srs = ds.spatialReference,
       let proj4 = try? srs.toPROJ4() {
        print("proj4:    \(proj4.trimmingCharacters(in: .whitespacesAndNewlines))")
    }

    for i in 1...ds.rasterCount {
        let b = ds.band(i)
        let (bw, bh) = b.blockSize
        let no = b.noDataValue.map { String($0) } ?? "nil"
        print("band \(i):   type=\(b.dataType) block=\(bw)×\(bh) nodata=\(no)")
        if let stats = try? b.statistics(approximate: true) {
            print("          min=\(stats.min) max=\(stats.max) mean=\(stats.mean) σ=\(stats.stdDev)")
        }
    }
} catch let error as GDALError {
    print("error: \(error)")
    exit(1)
} catch {
    print("error: \(error)")
    exit(1)
}
