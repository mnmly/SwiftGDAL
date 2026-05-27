import gdal

/// Top-level OGR geometry type, ignoring Z/M modifiers.
public enum GeometryType: Sendable, Equatable {
    case unknown
    case point
    case lineString
    case polygon
    case multiPoint
    case multiLineString
    case multiPolygon
    case geometryCollection
    case linearRing
    case none

    public var raw: OGRwkbGeometryType {
        switch self {
        case .unknown: return wkbUnknown
        case .point: return wkbPoint
        case .lineString: return wkbLineString
        case .polygon: return wkbPolygon
        case .multiPoint: return wkbMultiPoint
        case .multiLineString: return wkbMultiLineString
        case .multiPolygon: return wkbMultiPolygon
        case .geometryCollection: return wkbGeometryCollection
        case .linearRing: return wkbLinearRing
        case .none: return wkbNone
        }
    }

    public init(_ raw: OGRwkbGeometryType) {
        // Strip Z/M modifiers so callers can switch on the base type.
        switch OGR_GT_Flatten(raw) {
        case wkbPoint: self = .point
        case wkbLineString: self = .lineString
        case wkbPolygon: self = .polygon
        case wkbMultiPoint: self = .multiPoint
        case wkbMultiLineString: self = .multiLineString
        case wkbMultiPolygon: self = .multiPolygon
        case wkbGeometryCollection: self = .geometryCollection
        case wkbLinearRing: self = .linearRing
        case wkbNone: self = .none
        default: self = .unknown
        }
    }
}

/// OGR field data type, mirroring `OGRFieldType`.
///
/// Used by ``FieldDefn`` to describe a layer schema column. See
/// ``FieldValue`` for the runtime variant.
public enum FieldType: Sendable, Equatable {
    case integer
    case integer64
    case real
    case string
    case binary
    case date
    case time
    case dateTime
    case integerList
    case integer64List
    case realList
    case stringList

    public var raw: OGRFieldType {
        switch self {
        case .integer: return OFTInteger
        case .integer64: return OFTInteger64
        case .real: return OFTReal
        case .string: return OFTString
        case .binary: return OFTBinary
        case .date: return OFTDate
        case .time: return OFTTime
        case .dateTime: return OFTDateTime
        case .integerList: return OFTIntegerList
        case .integer64List: return OFTInteger64List
        case .realList: return OFTRealList
        case .stringList: return OFTStringList
        }
    }

    public init(_ raw: OGRFieldType) {
        switch raw {
        case OFTInteger: self = .integer
        case OFTInteger64: self = .integer64
        case OFTReal: self = .real
        case OFTString: self = .string
        case OFTBinary: self = .binary
        case OFTDate: self = .date
        case OFTTime: self = .time
        case OFTDateTime: self = .dateTime
        case OFTIntegerList: self = .integerList
        case OFTInteger64List: self = .integer64List
        case OFTRealList: self = .realList
        case OFTStringList: self = .stringList
        default: self = .string
        }
    }
}

/// Schema definition for a single column on a ``Layer``.
public struct FieldDefn: Sendable, Equatable {
    /// Column name.
    public let name: String
    /// Data type.
    public let type: FieldType
    /// Maximum width (string length, integer digits). `0` for no constraint.
    public var width: Int = 0
    /// Decimal precision for real types. `0` for no constraint.
    public var precision: Int = 0

    /// Builds a field definition.
    ///
    /// - Parameters:
    ///   - name: Column name.
    ///   - type: Data type.
    ///   - width: Max width / digits. Default `0` (driver default).
    ///   - precision: Decimal precision for real types. Default `0`.
    public init(name: String, type: FieldType, width: Int = 0, precision: Int = 0) {
        self.name = name
        self.type = type
        self.width = width
        self.precision = precision
    }
}

/// Runtime sum type for OGR field values.
///
/// Returned by ``Feature/subscript(field:)-(Int)`` and
/// ``Feature/subscript(field:)-(String)``; also accepted by their setters.
public enum FieldValue: Sendable, Equatable {
    case null
    case integer(Int32)
    case integer64(Int64)
    case real(Double)
    case string(String)
    case binary([UInt8])
    case integerList([Int32])
    case integer64List([Int64])
    case realList([Double])
    case stringList([String])
    case dateTime(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Double, tzFlag: Int)
}
