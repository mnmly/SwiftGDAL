import Foundation
import gdal

/// A single raster band. Lifetime is tied to its parent `Dataset`.
public final class RasterBand {

    nonisolated(unsafe) let handle: GDALRasterBandH

    /// Holding the owner keeps the GDAL handle alive — GDAL bands don't
    /// own their parent dataset.
    private let owner: Dataset

    init(_ handle: GDALRasterBandH, owner: Dataset) {
        self.handle = handle
        self.owner = owner
    }

    public var dataType: DataType { DataType(GDALGetRasterDataType(handle)) }
    public var width: Int { Int(GDALGetRasterBandXSize(handle)) }
    public var height: Int { Int(GDALGetRasterBandYSize(handle)) }

    /// Block size used by GDAL for tiled IO. Reading along these
    /// boundaries is usually the fastest path.
    public var blockSize: (width: Int, height: Int) {
        var bw: Int32 = 0
        var bh: Int32 = 0
        GDALGetBlockSize(handle, &bw, &bh)
        return (Int(bw), Int(bh))
    }

    /// Mask band associated with this raster band, if any.
    ///
    /// GDAL synthesizes a mask band even when no explicit mask is set
    /// (e.g. derived from the nodata value). The returned `RasterBand` pins
    /// its parent `Dataset` for lifetime — the mask handle itself is owned
    /// by GDAL, not by Swift.
    public var maskBand: RasterBand? {
        guard let h = GDALGetMaskBand(handle) else { return nil }
        return RasterBand(h, owner: owner)
    }

    /// Bitwise flags describing what kind of mask the band has (per `GMF_*`
    /// constants in GDAL).
    public var maskFlags: Int32 { GDALGetMaskFlags(handle) }

    /// Per-band "no data" sentinel, if defined.
    public var noDataValue: Double? {
        var has: Int32 = 0
        let v = GDALGetRasterNoDataValue(handle, &has)
        return has != 0 ? v : nil
    }

    /// Min/max/mean/stdDev of the band's pixel values.
    ///
    /// - Parameters:
    ///   - approximate: Compute against a subsample for speed instead of the
    ///     whole band.
    ///   - forceCompute: Recompute even if cached stats are available.
    /// - Throws: ``GDALError`` if GDAL can't compute stats (e.g. band is empty).
    public func statistics(
        approximate: Bool = false,
        forceCompute: Bool = false
    ) throws -> (min: Double, max: Double, mean: Double, stdDev: Double) {
        var mn: Double = 0, mx: Double = 0, mean: Double = 0, sd: Double = 0
        CPLErrorReset()
        let err = GDALGetRasterStatistics(
            handle,
            approximate ? 1 : 0,
            forceCompute ? 1 : 0,
            &mn, &mx, &mean, &sd
        )
        guard err == CE_None else {
            throw GDALError.lastError(fallback: "GDALGetRasterStatistics failed")
        }
        return (mn, mx, mean, sd)
    }

    // MARK: - Synchronous IO

    /// Reads an arbitrary rectangle of pixels into a typed Swift array.
    ///
    /// `T` must match the band's runtime ``dataType`` — there is no implicit
    /// conversion. Pixels are returned in row-major order.
    ///
    /// - Parameters:
    ///   - rect: Sub-rectangle in pixel coordinates as `(x, y, width, height)`.
    ///     Defaults to the entire band when `nil`.
    ///   - as: Element type for the returned array. Conforms to ``GDALPixel``.
    /// - Returns: `rect.width * rect.height` samples in row-major order.
    /// - Throws: ``GDALError`` if the read fails.
    public func read<T: GDALPixel>(
        rect: (x: Int, y: Int, width: Int, height: Int)? = nil,
        as: T.Type = T.self
    ) throws -> [T] {
        let r = rect ?? (0, 0, width, height)
        precondition(T.gdalType == dataType, "T (\(T.gdalType)) does not match band type (\(dataType))")

        let count = r.width * r.height
        var buffer = [T](repeating: T.zero, count: count)
        CPLErrorReset()
        let err = buffer.withUnsafeMutableBufferPointer { ptr -> CPLErr in
            GDALRasterIO(
                handle,
                GF_Read,
                Int32(r.x), Int32(r.y),
                Int32(r.width), Int32(r.height),
                ptr.baseAddress,
                Int32(r.width), Int32(r.height),
                T.gdalType.raw,
                0, 0
            )
        }
        guard err == CE_None else {
            throw GDALError.lastError(fallback: "GDALRasterIO read failed")
        }
        return buffer
    }

    /// Writes a typed Swift array into an arbitrary rectangle of the band.
    ///
    /// - Parameters:
    ///   - buffer: Pixels in row-major order. Must have exactly
    ///     `rect.width * rect.height` elements.
    ///   - rect: Destination rectangle in pixel coordinates.
    /// - Throws: ``GDALError`` if the band can't be written (e.g. read-only
    ///   dataset, type mismatch).
    public func write<T: GDALPixel>(
        _ buffer: [T],
        rect: (x: Int, y: Int, width: Int, height: Int)
    ) throws {
        precondition(T.gdalType == dataType, "T (\(T.gdalType)) does not match band type (\(dataType))")
        precondition(buffer.count == rect.width * rect.height, "buffer size mismatch")
        var local = buffer
        CPLErrorReset()
        let err = local.withUnsafeMutableBufferPointer { ptr -> CPLErr in
            GDALRasterIO(
                handle,
                GF_Write,
                Int32(rect.x), Int32(rect.y),
                Int32(rect.width), Int32(rect.height),
                ptr.baseAddress,
                Int32(rect.width), Int32(rect.height),
                T.gdalType.raw,
                0, 0
            )
        }
        guard err == CE_None else {
            throw GDALError.lastError(fallback: "GDALRasterIO write failed")
        }
    }

    // MARK: - Async wrappers
    //
    // GDAL IO is blocking; hop off the caller's executor via Task.detached
    // so the caller's actor (e.g. @MainActor) stays responsive.

    /// Async variant that hops the blocking GDAL call off the caller's
    /// executor via `Task.detached`. Same semantics as the synchronous
    /// `read(rect:as:)`.
    ///
    /// - Parameters:
    ///   - rect: Sub-rectangle to read. `nil` reads the whole band.
    ///   - type: Element type for the returned array.
    public func read<T: GDALPixel>(
        rect: (x: Int, y: Int, width: Int, height: Int)? = nil,
        as type: T.Type = T.self
    ) async throws -> [T] {
        let unsafe = UnsafeTransfer(self)
        return try await Task.detached {
            try unsafe.value.read(rect: rect, as: type)
        }.value
    }

    /// Async variant of the synchronous `write(_:rect:)` — same semantics,
    /// hopped onto a detached task so the caller's executor stays free.
    ///
    /// - Parameters:
    ///   - buffer: Pixels in row-major order.
    ///   - rect: Destination rectangle.
    public func write<T: GDALPixel>(
        _ buffer: [T],
        rect: (x: Int, y: Int, width: Int, height: Int)
    ) async throws {
        let unsafe = UnsafeTransfer(self)
        let payload = UnsafeTransfer(buffer)
        try await Task.detached {
            try unsafe.value.write(payload.value, rect: rect)
        }.value
    }

    /// Streams the band block-by-block.
    ///
    /// Each yielded ``RasterBlock`` is sized to GDAL's native ``blockSize`` —
    /// for tiled formats (COG, BigTIFF, GeoPackage rasters) this is usually
    /// the cheapest read pattern. The work runs on a detached task; cancelling
    /// the consuming Task aborts the stream.
    ///
    /// - Parameter type: Element type for each block. Must match ``dataType``.
    public func blocks<T: GDALPixel>(as type: T.Type = T.self) -> AsyncThrowingStream<RasterBlock<T>, Error> {
        let unsafe = UnsafeTransfer(self)
        return AsyncThrowingStream { continuation in
            Task.detached {
                let self_ = unsafe.value
                do {
                    let (bw, bh) = self_.blockSize
                    let w = self_.width, h = self_.height
                    var y = 0
                    while y < h {
                        var x = 0
                        let curH = min(bh, h - y)
                        while x < w {
                            if Task.isCancelled { continuation.finish(); return }
                            let curW = min(bw, w - x)
                            let rect = (x: x, y: y, width: curW, height: curH)
                            let data = try self_.read(rect: rect, as: type)
                            continuation.yield(RasterBlock(rect: rect, pixels: data))
                            x += bw
                        }
                        y += bh
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

}

/// One chunk yielded by ``RasterBand/blocks(as:)``.
public struct RasterBlock<T: GDALPixel>: Sendable {
    /// Block position and size in the parent band, in pixel coordinates.
    public let rect: (x: Int, y: Int, width: Int, height: Int)
    /// Pixel samples in row-major order.
    public let pixels: [T]
}

// MARK: - GDALPixel

/// Conformed by Swift element types that have a matching GDAL ``DataType``.
///
/// Used by ``RasterBand``'s `read` / `write` overloads to choose the right
/// C-side type at the IO boundary. Stock conformances cover
/// `UInt8`/`Int8`/`UInt16`/`Int16`/`UInt32`/`Int32`/`UInt64`/`Int64`/`Float`/`Double`.
public protocol GDALPixel: Sendable {
    /// The matching GDAL data type for this Swift type.
    static var gdalType: DataType { get }
    /// Zero value used to size read buffers.
    static var zero: Self { get }
}

extension UInt8: GDALPixel { public static let gdalType: DataType = .byte; public static let zero: UInt8 = 0 }
extension Int8:  GDALPixel { public static let gdalType: DataType = .int8; public static let zero: Int8 = 0 }
extension UInt16: GDALPixel { public static let gdalType: DataType = .uint16; public static let zero: UInt16 = 0 }
extension Int16:  GDALPixel { public static let gdalType: DataType = .int16; public static let zero: Int16 = 0 }
extension UInt32: GDALPixel { public static let gdalType: DataType = .uint32; public static let zero: UInt32 = 0 }
extension Int32:  GDALPixel { public static let gdalType: DataType = .int32; public static let zero: Int32 = 0 }
extension UInt64: GDALPixel { public static let gdalType: DataType = .uint64; public static let zero: UInt64 = 0 }
extension Int64:  GDALPixel { public static let gdalType: DataType = .int64; public static let zero: Int64 = 0 }
extension Float:  GDALPixel { public static let gdalType: DataType = .float32; public static let zero: Float = 0 }
extension Double: GDALPixel { public static let gdalType: DataType = .float64; public static let zero: Double = 0 }

/// Tiny helper to move a non-Sendable closure across an isolation boundary.
/// Safe here because each `Task.detached` owns the closure for the duration
/// of its work — see usage in `RasterBand.withDatasetIO`.
struct UnsafeTransfer<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
