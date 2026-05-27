import Foundation
import gdal

/// A single OGR feature. Owns its underlying `OGRFeatureH` and destroys it on deinit.
public final class Feature {

    nonisolated(unsafe) let handle: OGRFeatureH

    /// Takes ownership of an existing handle (e.g. from `OGR_L_GetNextFeature`).
    init(owned handle: OGRFeatureH) {
        self.handle = handle
    }

    /// Creates a new feature matching a layer's schema. Use this when
    /// appending features to a layer via `Layer.create(_:)`.
    public convenience init(forLayer layer: Layer) {
        let defn = OGR_L_GetLayerDefn(layer.handle).unsafelyUnwrapped
        self.init(owned: OGR_F_Create(defn).unsafelyUnwrapped)
    }

    deinit {
        OGR_F_Destroy(handle)
    }

    /// 64-bit feature ID (FID).
    public var fid: Int64 {
        get { OGR_F_GetFID(handle) }
        set { _ = OGR_F_SetFID(handle, newValue) }
    }

    public var fieldCount: Int { Int(OGR_F_GetFieldCount(handle)) }

    /// Borrowed clone of the feature's geometry, or nil if none set.
    public var geometry: Geometry? {
        get { Geometry(cloning: OGR_F_GetGeometryRef(handle)) }
        set {
            if let newValue {
                _ = OGR_F_SetGeometry(handle, newValue.handle)
            } else {
                _ = OGR_F_SetGeometry(handle, nil)
            }
        }
    }

    // MARK: - Fields by index

    public func fieldName(at index: Int) -> String {
        let defn = OGR_F_GetFieldDefnRef(handle, Int32(index)).unsafelyUnwrapped
        return String(cString: OGR_Fld_GetNameRef(defn))
    }

    public func fieldType(at index: Int) -> FieldType {
        let defn = OGR_F_GetFieldDefnRef(handle, Int32(index)).unsafelyUnwrapped
        return FieldType(OGR_Fld_GetType(defn))
    }

    public func fieldIndex(named name: String) -> Int? {
        let i = OGR_F_GetFieldIndex(handle, name)
        return i >= 0 ? Int(i) : nil
    }

    public func isSet(at index: Int) -> Bool {
        OGR_F_IsFieldSet(handle, Int32(index)) != 0
            && OGR_F_IsFieldNull(handle, Int32(index)) == 0
    }

    public subscript(field index: Int) -> FieldValue {
        get { readField(at: index) }
        set { writeField(at: index, newValue) }
    }

    public subscript(field name: String) -> FieldValue {
        get { fieldIndex(named: name).map(readField) ?? .null }
        set {
            guard let i = fieldIndex(named: name) else { return }
            writeField(at: i, newValue)
        }
    }

    // MARK: - Internal field IO

    private func readField(at index: Int) -> FieldValue {
        guard isSet(at: index) else { return .null }
        let i = Int32(index)
        switch fieldType(at: index) {
        case .integer: return .integer(OGR_F_GetFieldAsInteger(handle, i))
        case .integer64: return .integer64(OGR_F_GetFieldAsInteger64(handle, i))
        case .real: return .real(OGR_F_GetFieldAsDouble(handle, i))
        case .string: return .string(String(cString: OGR_F_GetFieldAsString(handle, i)))
        case .binary:
            var count: Int32 = 0
            guard let ptr = OGR_F_GetFieldAsBinary(handle, i, &count) else { return .null }
            let buf = UnsafeBufferPointer(start: ptr, count: Int(count))
            return .binary(Array(buf))
        case .integerList:
            var count: Int32 = 0
            guard let ptr = OGR_F_GetFieldAsIntegerList(handle, i, &count) else { return .null }
            return .integerList(Array(UnsafeBufferPointer(start: ptr, count: Int(count))))
        case .integer64List:
            var count: Int32 = 0
            guard let ptr = OGR_F_GetFieldAsInteger64List(handle, i, &count) else { return .null }
            return .integer64List(Array(UnsafeBufferPointer(start: ptr, count: Int(count))))
        case .realList:
            var count: Int32 = 0
            guard let ptr = OGR_F_GetFieldAsDoubleList(handle, i, &count) else { return .null }
            return .realList(Array(UnsafeBufferPointer(start: ptr, count: Int(count))))
        case .stringList:
            guard let raw = OGR_F_GetFieldAsStringList(handle, i) else { return .stringList([]) }
            var out: [String] = []
            var k = 0
            while let s = raw[k] { out.append(String(cString: s)); k += 1 }
            return .stringList(out)
        case .dateTime, .date, .time:
            var y: Int32 = 0, m: Int32 = 0, d: Int32 = 0, h: Int32 = 0, mn: Int32 = 0
            var sec: Float = 0, tz: Int32 = 0
            OGR_F_GetFieldAsDateTimeEx(handle, i, &y, &m, &d, &h, &mn, &sec, &tz)
            return .dateTime(
                year: Int(y), month: Int(m), day: Int(d),
                hour: Int(h), minute: Int(mn), second: Double(sec),
                tzFlag: Int(tz)
            )
        }
    }

    private func writeField(at index: Int, _ value: FieldValue) {
        let i = Int32(index)
        switch value {
        case .null: OGR_F_SetFieldNull(handle, i)
        case .integer(let v): OGR_F_SetFieldInteger(handle, i, v)
        case .integer64(let v): OGR_F_SetFieldInteger64(handle, i, v)
        case .real(let v): OGR_F_SetFieldDouble(handle, i, v)
        case .string(let v): v.withCString { OGR_F_SetFieldString(handle, i, $0) }
        case .binary(let bytes):
            var local = bytes
            local.withUnsafeMutableBufferPointer { buf in
                OGR_F_SetFieldBinary(handle, i, Int32(buf.count), buf.baseAddress)
            }
        case .integerList(let vs):
            var local = vs
            local.withUnsafeMutableBufferPointer { buf in
                OGR_F_SetFieldIntegerList(handle, i, Int32(buf.count), buf.baseAddress)
            }
        case .integer64List(let vs):
            var local = vs
            local.withUnsafeMutableBufferPointer { buf in
                OGR_F_SetFieldInteger64List(handle, i, Int32(buf.count), buf.baseAddress)
            }
        case .realList(let vs):
            var local = vs
            local.withUnsafeMutableBufferPointer { buf in
                OGR_F_SetFieldDoubleList(handle, i, Int32(buf.count), buf.baseAddress)
            }
        case .stringList(let vs):
            let list = StringList.cStringList(vs)
            defer { CSLDestroy(list) }
            OGR_F_SetFieldStringList(handle, i, list)
        case .dateTime(let y, let m, let d, let h, let mn, let s, let tz):
            OGR_F_SetFieldDateTimeEx(
                handle, i,
                Int32(y), Int32(m), Int32(d),
                Int32(h), Int32(mn), Float(s), Int32(tz)
            )
        }
    }
}
