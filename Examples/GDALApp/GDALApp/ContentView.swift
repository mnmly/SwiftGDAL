//
//  ContentView.swift
//  GDALApp
//
//  Smoke-test app for SwiftGDAL. Demonstrates raster inspection, on-the-fly
//  PNG thumbnailing via GDALOps.translate, vector layer enumeration, and
//  gdalwarp with a SwiftUI progress bar.
//

import SwiftUI
import SwiftGDAL
import UniformTypeIdentifiers

#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
extension Image {
    init(platformImage: PlatformImage) { self.init(uiImage: platformImage) }
}
#else
import AppKit
typealias PlatformImage = NSImage
extension Image {
    init(platformImage: PlatformImage) { self.init(nsImage: platformImage) }
}
#endif

struct ContentView: View {
    var body: some View {
        TabView {
            NavigationStack { RasterTab() }
                .tabItem { Label("Raster", systemImage: "photo") }
            NavigationStack { VectorTab() }
                .tabItem { Label("Vector", systemImage: "point.3.filled.connected.trianglepath.dotted") }
            NavigationStack { WarpTab() }
                .tabItem { Label("Warp", systemImage: "arrow.triangle.2.circlepath") }
        }
    }
}

// MARK: - Raster tab

@MainActor
private struct RasterTab: View {
    @State private var pickerOpen = false
    @State private var info: RasterInfo?
    @State private var thumbnail: PlatformImage?
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                Button("Open raster…") { pickerOpen = true }
                Text("GDAL \(GDAL.versionInfo)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            if let info {
                Section("Dataset") {
                    LabeledContent("path", value: info.path).font(.caption.monospaced())
                    LabeledContent("size", value: "\(info.width) × \(info.height)")
                    LabeledContent("bands", value: "\(info.bandCount)")
                    if !info.projection.isEmpty {
                        LabeledContent("CRS", value: info.projection).font(.caption.monospaced())
                    }
                    if let gt = info.geoTransform {
                        LabeledContent("origin", value: "(\(gt.originX), \(gt.originY))")
                        LabeledContent("pixel", value: "\(gt.pixelWidth) × \(gt.pixelHeight)")
                    }
                }

                Section("Bands") {
                    ForEach(info.bands, id: \.index) { b in
                        VStack(alignment: .leading) {
                            Text("band \(b.index): \(b.dataType)")
                            if let s = b.stats {
                                Text("min=\(s.min, specifier: "%.3g") max=\(s.max, specifier: "%.3g") mean=\(s.mean, specifier: "%.3g")")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if let thumbnail {
                Section("Thumbnail (via GDALOps.translate)") {
                    Image(platformImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 256)
                }
            }

            if let error {
                Section("Error") {
                    Text(error).font(.caption.monospaced()).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Raster")
        .fileImporter(
            isPresented: $pickerOpen,
            allowedContentTypes: [.image, .data]
        ) { result in
            switch result {
            case .success(let url): load(url: url)
            case .failure(let err): error = err.localizedDescription
            }
        }
    }

    private func load(url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        let path = url.path
        Task {
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                let loaded = try await Task.detached { try RasterInfo.read(path: path) }.value
                let thumb = try await Task.detached { try renderThumbnail(path: path, max: 256) }.value
                await MainActor.run {
                    self.info = loaded
                    self.thumbnail = thumb
                    self.error = nil
                }
            } catch {
                await MainActor.run { self.error = "\(error)" }
            }
        }
    }
}

private struct RasterInfo: Sendable {
    let path: String
    let width: Int
    let height: Int
    let bandCount: Int
    let projection: String
    let geoTransform: GeoTransform?
    let bands: [BandInfo]

    struct BandInfo: Sendable {
        let index: Int
        let dataType: String
        let stats: (min: Double, max: Double, mean: Double, stdDev: Double)?
    }

    static func read(path: String) throws -> RasterInfo {
        let ds = try Dataset(opening: path)
        let bands = (1...max(1, ds.rasterCount)).map { i -> BandInfo in
            let b = ds.band(i)
            return BandInfo(
                index: i,
                dataType: "\(b.dataType)",
                stats: try? b.statistics(approximate: true)
            )
        }
        let projShort: String = (try? ds.spatialReference?.toPROJ4()) ?? ds.projectionWKT
        return RasterInfo(
            path: path,
            width: ds.rasterWidth,
            height: ds.rasterHeight,
            bandCount: ds.rasterCount,
            projection: projShort.trimmingCharacters(in: .whitespacesAndNewlines),
            geoTransform: ds.geoTransform,
            bands: bands
        )
    }
}

/// Uses GDALOps.translate to render a thumbnail, then loads it back as
/// a platform image. Picks the first available output driver — the iOS slice
/// of gdal.xcframework ships a reduced driver set, so PNG isn't guaranteed.
/// PlatformImage(data:) handles all of these via ImageIO.
private func renderThumbnail(path: String, max maxDim: Int) throws -> PlatformImage? {
    let src = try Dataset(opening: path)
    let scale = Double(maxDim) / Double(Swift.max(src.rasterWidth, src.rasterHeight))
    let w = Swift.max(1, Int(Double(src.rasterWidth) * scale))
    let h = Swift.max(1, Int(Double(src.rasterHeight) * scale))

    // Prefer compact formats; fall back to GTiff (universally available).
    // Some drivers (e.g. JPEG) reject certain band counts or dtypes even
    // with -scale, so try each in turn and keep the first that succeeds.
    let candidates: [(driver: String, ext: String)] = [
        ("JPEG", "jpg"),
        ("PNG", "png"),
        ("GTiff", "tif"),
    ]
    let available = Set(GDAL.driverNames())

    for pick in candidates where available.contains(pick.driver) {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("thumb-\(UUID().uuidString).\(pick.ext)")
        do {
            _ = try GDALOps.translate(
                source: src,
                destination: tmpURL.path,
                options: ["-of", pick.driver, "-outsize", "\(w)", "\(h)", "-ot", "Byte", "-scale"]
            )
            defer { try? FileManager.default.removeItem(at: tmpURL) }
            return PlatformImage(data: try Data(contentsOf: tmpURL))
        } catch {
            try? FileManager.default.removeItem(at: tmpURL)
            continue
        }
    }
    return nil
}

// MARK: - Vector tab

@MainActor
private struct VectorTab: View {
    @State private var pickerOpen = false
    @State private var layers: [LayerSummary] = []
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                Button("Open vector dataset…") { pickerOpen = true }
            }
            ForEach(layers) { layer in
                Section(layer.name) {
                    LabeledContent("features", value: "\(layer.featureCount)")
                    LabeledContent("geometry", value: "\(layer.geometryType)")
                    if !layer.fields.isEmpty {
                        LabeledContent("fields", value: layer.fields.joined(separator: ", "))
                            .font(.caption.monospaced())
                    }
                    if !layer.preview.isEmpty {
                        ForEach(Array(layer.preview.enumerated()), id: \.offset) { _, row in
                            Text(row).font(.caption.monospaced())
                        }
                    }
                }
            }
            if let error {
                Section("Error") {
                    Text(error).font(.caption.monospaced()).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Vector")
        .fileImporter(
            isPresented: $pickerOpen,
            allowedContentTypes: [.json, .data, UTType(filenameExtension: "shp") ?? .data]
        ) { result in
            switch result {
            case .success(let url): load(url: url)
            case .failure(let err): error = err.localizedDescription
            }
        }
    }

    private func load(url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        let path = url.path
        Task {
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                let summaries = try await Task.detached { try LayerSummary.read(path: path) }.value
                await MainActor.run {
                    self.layers = summaries
                    self.error = nil
                }
            } catch {
                await MainActor.run { self.error = "\(error)" }
            }
        }
    }
}

private struct LayerSummary: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let featureCount: Int
    let geometryType: String
    let fields: [String]
    let preview: [String]

    static func read(path: String) throws -> [LayerSummary] {
        let ds = try VectorDataset(opening: path)
        return (0..<ds.layerCount).map { i in
            let l = ds.layer(at: i)
            let count = Int(l.featureCount(forceCompute: true))
            let fields = l.fieldDefinitions.map { "\($0.name):\($0.type)" }
            // Pull up to 3 features for a preview.
            var preview: [String] = []
            l.resetReading()
            for _ in 0..<3 {
                guard let f = l.nextFeature() else { break }
                var pairs: [String] = ["fid=\(f.fid)"]
                for d in l.fieldDefinitions {
                    if let i = f.fieldIndex(named: d.name) {
                        pairs.append("\(d.name)=\(f[field: i])")
                    }
                }
                preview.append(pairs.joined(separator: " "))
            }
            return LayerSummary(
                name: l.name,
                featureCount: count,
                geometryType: "\(l.geometryType)",
                fields: fields,
                preview: preview
            )
        }
    }
}

// MARK: - Warp tab

@MainActor
private struct WarpTab: View {
    @State private var pickerOpen = false
    @State private var progress: Double = 0
    @State private var status: String = "idle"
    @State private var error: String?
    @State private var resultPath: String?

    var body: some View {
        Form {
            Section {
                Button("Warp raster to EPSG:3857…") { pickerOpen = true }
                ProgressView(value: progress)
                LabeledContent("status", value: status)
            }
            if let resultPath {
                Section("Result") {
                    Text(resultPath).font(.caption.monospaced())
                }
            }
            if let error {
                Section("Error") {
                    Text(error).font(.caption.monospaced()).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Warp")
        .fileImporter(
            isPresented: $pickerOpen,
            allowedContentTypes: [.image, .data]
        ) { result in
            switch result {
            case .success(let url): warp(url: url)
            case .failure(let err): error = err.localizedDescription
            }
        }
    }

    private func warp(url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        let path = url.path
        let dest = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("warped-\(UUID().uuidString).tif")
        progress = 0
        status = "running…"
        error = nil
        resultPath = nil

        Task.detached {
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                let src = try Dataset(opening: path)
                _ = try src.warp(
                    to: dest,
                    options: ["-t_srs", "EPSG:3857", "-r", "bilinear"],
                    onProgress: { p in
                        // GDAL invokes this from its working thread; hop
                        // to MainActor for the UI update.
                        Task { @MainActor in self.progress = p }
                    }
                )
                await MainActor.run {
                    self.status = "done"
                    self.progress = 1.0
                    self.resultPath = dest
                }
            } catch {
                await MainActor.run {
                    self.status = "failed"
                    self.error = "\(error)"
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
