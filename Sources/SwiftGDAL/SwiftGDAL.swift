import Foundation
import gdal

/// Namespace for one-time process-wide initialization.
public enum GDAL {

    private static let bootstrap: Void = {
        // proj.db lives somewhere inside Bundle.module — exact layout varies
        // by platform (flat vs Contents/Resources) and host (SPM tests vs
        // app bundle). Resolve by searching for the file.
        if let projURL = Bundle.module.url(forResource: "proj", withExtension: "db") {
            let projDir = projURL.deletingLastPathComponent().path
            setenv("PROJ_DATA", projDir, 1)
            setenv("PROJ_LIB", projDir, 1)
        }
        GDALAllRegister()
        Errors.installHandler()
    }()

    /// Registers all GDAL/OGR drivers and configures PROJ data lookup.
    /// Safe to call repeatedly — the registration runs once.
    public static func registerAll() {
        _ = bootstrap
    }

    /// Runtime GDAL version, e.g. "GDAL 3.12.4, released 2025/..."
    public static var versionInfo: String {
        registerAll()
        return GDALVersionInfo("--version").map(String.init(cString:)) ?? ""
    }

    /// Number of registered drivers.
    public static var driverCount: Int {
        registerAll()
        return Int(GDALGetDriverCount())
    }

    /// Names of all registered drivers, in registration order.
    public static func driverNames() -> [String] {
        registerAll()
        return (0..<Int32(GDALGetDriverCount())).compactMap { i in
            guard let d = GDALGetDriver(i), let n = GDALGetDriverShortName(d) else { return nil }
            return String(cString: n)
        }
    }

    /// Sets a GDAL config option for the lifetime of the process.
    ///
    /// Wraps `CPLSetConfigOption`. See the [GDAL config options docs](https://gdal.org/user/configoptions.html)
    /// for known keys.
    ///
    /// - Parameters:
    ///   - key: Config option name, e.g. `"GDAL_CACHEMAX"`, `"CPL_TMPDIR"`.
    ///   - value: New value, or `nil` to clear the override.
    public static func setConfigOption(_ key: String, _ value: String?) {
        registerAll()
        if let value {
            CPLSetConfigOption(key, value)
        } else {
            CPLSetConfigOption(key, nil)
        }
    }
}
