import simd

/// GDAL's affine geo-transform: maps pixel/line (column, row) to projected (x, y).
///
///     x = originX + col * pixelWidth  + row * rowRotation
///     y = originY + col * colRotation + row * pixelHeight   // typically negative
public struct GeoTransform: Sendable, Equatable {
    public var originX: Double
    public var pixelWidth: Double
    public var rowRotation: Double
    public var originY: Double
    public var colRotation: Double
    public var pixelHeight: Double

    /// Builds a geo-transform from its six affine coefficients.
    ///
    /// - Parameters:
    ///   - originX: Top-left X (projected units).
    ///   - pixelWidth: X-resolution per pixel column.
    ///   - rowRotation: Off-diagonal X term; `0` for axis-aligned rasters.
    ///   - originY: Top-left Y (projected units).
    ///   - colRotation: Off-diagonal Y term; `0` for axis-aligned rasters.
    ///   - pixelHeight: Y-resolution per row. Typically **negative** (Y axis
    ///     decreases as rows increase) for top-down rasters.
    public init(
        originX: Double,
        pixelWidth: Double,
        rowRotation: Double = 0,
        originY: Double,
        colRotation: Double = 0,
        pixelHeight: Double
    ) {
        self.originX = originX
        self.pixelWidth = pixelWidth
        self.rowRotation = rowRotation
        self.originY = originY
        self.colRotation = colRotation
        self.pixelHeight = pixelHeight
    }

    init(_ a: [Double]) {
        precondition(a.count == 6)
        self.init(
            originX: a[0],
            pixelWidth: a[1],
            rowRotation: a[2],
            originY: a[3],
            colRotation: a[4],
            pixelHeight: a[5]
        )
    }

    var array: [Double] {
        [originX, pixelWidth, rowRotation, originY, colRotation, pixelHeight]
    }

    /// Projects pixel coordinates to projected (x, y).
    ///
    /// - Parameters:
    ///   - col: Pixel column (0-based, fractional).
    ///   - row: Pixel row (0-based, fractional).
    /// - Returns: Coordinate in the dataset's CRS units.
    public func apply(col: Double, row: Double) -> (x: Double, y: Double) {
        (
            originX + col * pixelWidth  + row * rowRotation,
            originY + col * colRotation + row * pixelHeight
        )
    }
}
