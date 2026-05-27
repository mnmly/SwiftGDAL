import Foundation
import gdal

/// Error thrown by SwiftGDAL operations.
///
/// Captures whatever GDAL/CPL recorded in its thread-local error state at
/// the failure site — ``class`` mirrors `CPLErr`, ``code`` is the numeric
/// error number, and ``message`` is GDAL's human-readable text.
public struct GDALError: Error, CustomStringConvertible, Sendable {
    /// Severity / category mirroring GDAL's `CPLErr` values.
    public enum Class: Sendable {
        case none, debug, warning, failure, fatal, appDefined, objectNull, httpResponse, aws, user

        init(_ raw: CPLErr) {
            switch raw {
            case CE_None: self = .none
            case CE_Debug: self = .debug
            case CE_Warning: self = .warning
            case CE_Failure: self = .failure
            case CE_Fatal: self = .fatal
            default: self = .failure
            }
        }
    }

    /// Severity / category of the error.
    public let `class`: Class
    /// Numeric error code as reported by `CPLGetLastErrorNo`.
    public let code: Int32
    /// Human-readable message from GDAL.
    public let message: String

    public var description: String {
        "GDALError(\(`class`), code=\(code)): \(message)"
    }

    /// Captures the last GDAL error (if any) and resets the error state.
    static func lastError(fallback: String) -> GDALError {
        let cls = CPLGetLastErrorType()
        let code = CPLGetLastErrorNo()
        let msg = CPLGetLastErrorMsg().map(String.init(cString:)) ?? fallback
        CPLErrorReset()
        return GDALError(class: Class(cls), code: code, message: msg.isEmpty ? fallback : msg)
    }
}

/// Captures GDAL/CPL errors so we can surface them as Swift errors.
enum Errors {
    private static let installOnce: Void = {
        // Push a quiet error handler so console output stays clean.
        // The last-error state is still available via CPLGetLastError*.
        CPLPushErrorHandler { _, _, _ in /* swallow; callers read via CPLGetLastError* */ }
    }()

    static func installHandler() { _ = installOnce }
}
