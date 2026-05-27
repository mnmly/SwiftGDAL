import gdal

/// Swift mirror of `GDALDataType` with byte-size helpers.
public enum DataType: Sendable, Equatable {
    case unknown
    case byte
    case int8
    case uint16
    case int16
    case uint32
    case int32
    case uint64
    case int64
    case float32
    case float64
    case cint16
    case cint32
    case cfloat32
    case cfloat64

    public var raw: GDALDataType {
        switch self {
        case .unknown: return GDT_Unknown
        case .byte: return GDT_Byte
        case .int8: return GDT_Int8
        case .uint16: return GDT_UInt16
        case .int16: return GDT_Int16
        case .uint32: return GDT_UInt32
        case .int32: return GDT_Int32
        case .uint64: return GDT_UInt64
        case .int64: return GDT_Int64
        case .float32: return GDT_Float32
        case .float64: return GDT_Float64
        case .cint16: return GDT_CInt16
        case .cint32: return GDT_CInt32
        case .cfloat32: return GDT_CFloat32
        case .cfloat64: return GDT_CFloat64
        }
    }

    public init(_ raw: GDALDataType) {
        switch raw {
        case GDT_Byte: self = .byte
        case GDT_Int8: self = .int8
        case GDT_UInt16: self = .uint16
        case GDT_Int16: self = .int16
        case GDT_UInt32: self = .uint32
        case GDT_Int32: self = .int32
        case GDT_UInt64: self = .uint64
        case GDT_Int64: self = .int64
        case GDT_Float32: self = .float32
        case GDT_Float64: self = .float64
        case GDT_CInt16: self = .cint16
        case GDT_CInt32: self = .cint32
        case GDT_CFloat32: self = .cfloat32
        case GDT_CFloat64: self = .cfloat64
        default: self = .unknown
        }
    }

    /// Size in bytes of a single sample of this type.
    public var byteSize: Int {
        Int(GDALGetDataTypeSizeBytes(raw))
    }
}

public enum AccessMode: Sendable {
    case readOnly
    case update

    var raw: GDALAccess { self == .readOnly ? GA_ReadOnly : GA_Update }
}

public enum RWFlag: Sendable {
    case read
    case write

    var raw: GDALRWFlag { self == .read ? GF_Read : GF_Write }
}
