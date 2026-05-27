import gdal

/// Bridges Swift `[String: String]` <-> GDAL's `KEY=VALUE` `char**` lists.
struct StringList {
    var pointer: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?

    init(_ dict: [String: String]) {
        var list: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>? = nil
        for (k, v) in dict {
            list = CSLSetNameValue(list, k, v)
        }
        self.pointer = list
    }

    func dispose() {
        if let pointer { CSLDestroy(pointer) }
    }

    /// Builds a NULL-terminated `char**` list from `[String]`. Caller owns
    /// the result and must `CSLDestroy` it.
    static func cStringList(_ values: [String]) -> UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>? {
        var list: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>? = nil
        for v in values { list = CSLAddString(list, v) }
        return list
    }

    /// Reads a borrowed GDAL `char**` (e.g. from `GDALGetMetadata`) into a Swift dict.
    /// Does NOT take ownership — caller must not free the input.
    static func dictionary(from raw: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> [String: String] {
        guard let raw else { return [:] }
        var out: [String: String] = [:]
        var i = 0
        while let cstr = raw[i] {
            let s = String(cString: cstr)
            if let eq = s.firstIndex(of: "=") {
                out[String(s[..<eq])] = String(s[s.index(after: eq)...])
            }
            i += 1
        }
        return out
    }
}
