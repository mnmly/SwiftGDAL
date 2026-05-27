import Foundation
import gdal

/// Swift wrappers for GDAL's high-level operations (`gdal_translate`,
/// `gdalwarp`, `gdal_rasterize`, `ogr2ogr`, `gdalbuildvrt`).
///
/// Each operation takes CLI-style options (`[String]`) — the same flags you'd
/// pass to the equivalent command-line tool. This keeps the API tiny and the
/// docs at https://gdal.org/programs/ directly applicable:
///
/// ```swift
/// // Equivalent to: gdal_translate -of PNG -outsize 256 256 src.tif out.png
/// let out = try GDALOps.translate(
///     source: src,
///     destination: "out.png",
///     options: ["-of", "PNG", "-outsize", "256", "256"]
/// )
/// ```
public typealias ProgressCallback = @Sendable (Double) -> Void

public enum GDALOps {

    // MARK: - Translate (raster)

    /// Converts/clips/resamples a raster dataset. See `gdal_translate`.
    ///
    /// - Parameters:
    ///   - source: Open ``Dataset`` to read from.
    ///   - destination: Output path (real filesystem or `/vsimem/…`).
    ///   - options: CLI-style flags passed verbatim to `gdal_translate`,
    ///     e.g. `["-of", "PNG", "-outsize", "256", "256"]`.
    ///   - onProgress: Optional callback invoked from GDAL's working thread
    ///     with completion ratios in `0...1`. Keep it cheap and thread-safe —
    ///     don't touch UI directly; hop to `@MainActor` if needed.
    /// - Returns: The newly-created ``Dataset`` (owned; closes on deinit).
    public static func translate(
        source: Dataset,
        destination: String,
        options: [String] = [],
        onProgress: ProgressCallback? = nil
    ) throws -> Dataset {
        GDAL.registerAll()
        return try withArgv(options) { argv in
            guard let opts = GDALTranslateOptionsNew(argv, nil) else {
                throw GDALError.lastError(fallback: "GDALTranslateOptionsNew failed")
            }
            defer { GDALTranslateOptionsFree(opts) }
            return try withProgress(onProgress) { fn, ctx in
                if let fn { GDALTranslateOptionsSetProgress(opts, fn, ctx) }
                var usageError: Int32 = 0
                CPLErrorReset()
                guard let h = GDALTranslate(destination, source.handle, opts, &usageError) else {
                    throw GDALError.lastError(fallback: "GDALTranslate failed")
                }
                return Dataset(takingOwnershipOf: h, path: destination)
            }
        }
    }

    // MARK: - Warp (raster)

    /// Reprojects/resamples one or more raster datasets. See `gdalwarp`.
    ///
    /// - Parameters:
    ///   - sources: One or more open input rasters. Must be non-empty.
    ///   - destination: Output path (real filesystem or `/vsimem/…`).
    ///   - options: CLI-style flags passed verbatim to `gdalwarp`,
    ///     e.g. `["-t_srs", "EPSG:3857", "-r", "bilinear"]`.
    ///   - onProgress: Optional progress callback. See ``translate(source:destination:options:onProgress:)`` for thread-safety notes.
    /// - Returns: The newly-created warped ``Dataset``.
    public static func warp(
        sources: [Dataset],
        destination: String,
        options: [String] = [],
        onProgress: ProgressCallback? = nil
    ) throws -> Dataset {
        GDAL.registerAll()
        precondition(!sources.isEmpty, "warp requires at least one source")
        return try withArgv(options) { argv in
            guard let opts = GDALWarpAppOptionsNew(argv, nil) else {
                throw GDALError.lastError(fallback: "GDALWarpAppOptionsNew failed")
            }
            defer { GDALWarpAppOptionsFree(opts) }
            return try withProgress(onProgress) { fn, ctx in
                if let fn { GDALWarpAppOptionsSetProgress(opts, fn, ctx) }
                var handles: [GDALDatasetH?] = sources.map { Optional($0.handle) }
                var usageError: Int32 = 0
                CPLErrorReset()
                let result = handles.withUnsafeMutableBufferPointer { buf in
                    GDALWarp(destination, nil, Int32(sources.count), buf.baseAddress, opts, &usageError)
                }
                guard let h = result else {
                    throw GDALError.lastError(fallback: "GDALWarp failed")
                }
                return Dataset(takingOwnershipOf: h, path: destination)
            }
        }
    }

    // MARK: - Rasterize (vector → raster)

    /// Rasterizes vector layers into a raster. See `gdal_rasterize`.
    ///
    /// - Parameters:
    ///   - source: Open vector dataset whose features get burned into raster cells.
    ///   - destination: Output raster path. May be an existing raster (to burn
    ///     into) or a new path (combined with `-ts`/`-te`/`-burn` options).
    ///   - options: CLI-style flags passed verbatim to `gdal_rasterize`.
    ///   - onProgress: Optional progress callback. See ``translate(source:destination:options:onProgress:)`` for thread-safety notes.
    public static func rasterize(
        source: VectorDataset,
        destination: String,
        options: [String] = [],
        onProgress: ProgressCallback? = nil
    ) throws -> Dataset {
        GDAL.registerAll()
        return try withArgv(options) { argv in
            guard let opts = GDALRasterizeOptionsNew(argv, nil) else {
                throw GDALError.lastError(fallback: "GDALRasterizeOptionsNew failed")
            }
            defer { GDALRasterizeOptionsFree(opts) }
            return try withProgress(onProgress) { fn, ctx in
                if let fn { GDALRasterizeOptionsSetProgress(opts, fn, ctx) }
                var usageError: Int32 = 0
                CPLErrorReset()
                guard let h = GDALRasterize(destination, nil, source.handle, opts, &usageError) else {
                    throw GDALError.lastError(fallback: "GDALRasterize failed")
                }
                return Dataset(takingOwnershipOf: h, path: destination)
            }
        }
    }

    // MARK: - VectorTranslate (ogr2ogr)

    /// Converts / reprojects / filters one or more vector datasets. See `ogr2ogr`.
    ///
    /// - Parameters:
    ///   - sources: One or more open input vector datasets. Must be non-empty.
    ///   - destination: Output path for the new vector dataset.
    ///   - options: CLI-style flags passed verbatim to `ogr2ogr`,
    ///     e.g. `["-f", "GeoJSON", "-t_srs", "EPSG:3857"]`.
    ///   - onProgress: Optional progress callback. See ``translate(source:destination:options:onProgress:)`` for thread-safety notes.
    public static func vectorTranslate(
        sources: [VectorDataset],
        destination: String,
        options: [String] = [],
        onProgress: ProgressCallback? = nil
    ) throws -> VectorDataset {
        GDAL.registerAll()
        precondition(!sources.isEmpty, "vectorTranslate requires at least one source")
        return try withArgv(options) { argv in
            guard let opts = GDALVectorTranslateOptionsNew(argv, nil) else {
                throw GDALError.lastError(fallback: "GDALVectorTranslateOptionsNew failed")
            }
            defer { GDALVectorTranslateOptionsFree(opts) }
            return try withProgress(onProgress) { fn, ctx in
                if let fn { GDALVectorTranslateOptionsSetProgress(opts, fn, ctx) }
                var handles: [GDALDatasetH?] = sources.map { Optional($0.handle) }
                var usageError: Int32 = 0
                CPLErrorReset()
                let result = handles.withUnsafeMutableBufferPointer { buf in
                    GDALVectorTranslate(destination, nil, Int32(sources.count), buf.baseAddress, opts, &usageError)
                }
                guard let h = result else {
                    throw GDALError.lastError(fallback: "GDALVectorTranslate failed")
                }
                return VectorDataset(takingOwnershipOf: h, path: destination)
            }
        }
    }

    // MARK: - BuildVRT (mosaic / virtual stack)

    /// Builds a virtual mosaic over one or more rasters. See `gdalbuildvrt`.
    ///
    /// Either pass open `sources` (their handles are used directly) **or**
    /// `sourcePaths` (GDAL opens them itself). Don't pass both.
    ///
    /// - Parameters:
    ///   - sources: Open input rasters (mutually exclusive with `sourcePaths`).
    ///   - sourcePaths: Input file paths for GDAL to open (mutually exclusive
    ///     with `sources`).
    ///   - destination: Output `.vrt` path.
    ///   - options: CLI-style flags passed verbatim to `gdalbuildvrt`.
    ///   - onProgress: Optional progress callback. See ``translate(source:destination:options:onProgress:)`` for thread-safety notes.
    public static func buildVRT(
        sources: [Dataset] = [],
        sourcePaths: [String] = [],
        destination: String,
        options: [String] = [],
        onProgress: ProgressCallback? = nil
    ) throws -> Dataset {
        precondition(sources.isEmpty != sourcePaths.isEmpty,
                     "pass exactly one of `sources` or `sourcePaths`")
        GDAL.registerAll()
        return try withArgv(options) { argv in
            guard let opts = GDALBuildVRTOptionsNew(argv, nil) else {
                throw GDALError.lastError(fallback: "GDALBuildVRTOptionsNew failed")
            }
            defer { GDALBuildVRTOptionsFree(opts) }
            return try withProgress(onProgress) { fn, ctx in
                if let fn { GDALBuildVRTOptionsSetProgress(opts, fn, ctx) }
                var usageError: Int32 = 0
                CPLErrorReset()
                let result: GDALDatasetH?
                if !sources.isEmpty {
                    var handles: [GDALDatasetH?] = sources.map { Optional($0.handle) }
                    result = handles.withUnsafeMutableBufferPointer { buf in
                        GDALBuildVRT(destination, Int32(sources.count), buf.baseAddress, nil, opts, &usageError)
                    }
                } else {
                    result = try withCStringArray(sourcePaths) { pathsPtr in
                        GDALBuildVRT(destination, Int32(sourcePaths.count), nil, pathsPtr, opts, &usageError)
                    }
                }
                guard let h = result else {
                    throw GDALError.lastError(fallback: "GDALBuildVRT failed")
                }
                return Dataset(takingOwnershipOf: h, path: destination)
            }
        }
    }
}

// MARK: - Ergonomic methods

extension Dataset {
    /// Convenience that forwards to ``GDALOps/translate(source:destination:options:onProgress:)``
    /// with `self` as the source.
    ///
    /// - Parameters:
    ///   - destination: Output path.
    ///   - options: CLI-style flags for `gdal_translate`.
    ///   - onProgress: Optional progress callback.
    public func translate(
        to destination: String,
        options: [String] = [],
        onProgress: ProgressCallback? = nil
    ) throws -> Dataset {
        try GDALOps.translate(source: self, destination: destination, options: options, onProgress: onProgress)
    }

    /// Convenience that forwards to ``GDALOps/warp(sources:destination:options:onProgress:)``
    /// with `[self]` as the source list.
    ///
    /// - Parameters:
    ///   - destination: Output path.
    ///   - options: CLI-style flags for `gdalwarp`.
    ///   - onProgress: Optional progress callback.
    public func warp(
        to destination: String,
        options: [String] = [],
        onProgress: ProgressCallback? = nil
    ) throws -> Dataset {
        try GDALOps.warp(sources: [self], destination: destination, options: options, onProgress: onProgress)
    }
}

extension VectorDataset {
    /// Convenience that forwards to ``GDALOps/vectorTranslate(sources:destination:options:onProgress:)``
    /// with `[self]` as the source list.
    ///
    /// - Parameters:
    ///   - destination: Output path.
    ///   - options: CLI-style flags for `ogr2ogr`.
    ///   - onProgress: Optional progress callback.
    public func translate(
        to destination: String,
        options: [String] = [],
        onProgress: ProgressCallback? = nil
    ) throws -> VectorDataset {
        try GDALOps.vectorTranslate(sources: [self], destination: destination, options: options, onProgress: onProgress)
    }
}

// MARK: - Internals

/// Provides a NULL-terminated mutable `char**` argv for the duration of `body`.
/// Each string is strdup'd and freed on exit; the buffer pointer is valid
/// only inside the closure.
private func withArgv<R>(
    _ args: [String],
    _ body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) throws -> R
) throws -> R {
    var dups: [UnsafeMutablePointer<CChar>?] = args.map { $0.withCString { strdup($0) } }
    dups.append(nil)
    defer { for p in dups where p != nil { free(p) } }
    return try dups.withUnsafeMutableBufferPointer { buf in
        try body(buf.baseAddress!)
    }
}

private final class ProgressBox {
    let cb: @Sendable (Double) -> Void
    init(_ cb: @escaping @Sendable (Double) -> Void) { self.cb = cb }
}

/// Bridges an optional Swift progress closure to GDAL's C callback. If
/// `cb` is nil, runs `body` with `nil` function pointer. Otherwise, retains
/// the closure in a refcount box for the call's lifetime, forwards
/// `0.0...1.0` progress to it, and releases the box on exit.
private func withProgress<R>(
    _ cb: (@Sendable (Double) -> Void)?,
    _ body: (GDALProgressFunc?, UnsafeMutableRawPointer?) throws -> R
) throws -> R {
    guard let cb else { return try body(nil, nil) }

    let box = ProgressBox(cb)
    let ctx = Unmanaged.passRetained(box).toOpaque()
    defer { Unmanaged<ProgressBox>.fromOpaque(ctx).release() }

    let fn: GDALProgressFunc = { complete, _, opaque in
        guard let opaque else { return 1 }
        let b = Unmanaged<ProgressBox>.fromOpaque(opaque).takeUnretainedValue()
        b.cb(complete)
        return 1 // non-zero → continue; zero would abort the op
    }
    return try body(fn, ctx)
}

/// Same as `withArgv` but for `const char *const *` (e.g. `GDALBuildVRT`'s
/// source-paths argument).
private func withCStringArray<R>(
    _ args: [String],
    _ body: (UnsafePointer<UnsafePointer<CChar>?>) throws -> R
) throws -> R {
    var dups: [UnsafeMutablePointer<CChar>?] = args.map { $0.withCString { strdup($0) } }
    dups.append(nil)
    defer { for p in dups where p != nil { free(p) } }
    return try dups.withUnsafeMutableBufferPointer { buf in
        try buf.baseAddress!.withMemoryRebound(to: UnsafePointer<CChar>?.self, capacity: buf.count) { rebound in
            try body(rebound)
        }
    }
}
