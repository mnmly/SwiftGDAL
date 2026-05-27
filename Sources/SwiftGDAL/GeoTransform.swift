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

    /// Project (column, row) → (x, y).
    public func apply(col: Double, row: Double) -> (x: Double, y: Double) {
        (
            originX + col * pixelWidth  + row * rowRotation,
            originY + col * colRotation + row * pixelHeight
        )
    }
}
