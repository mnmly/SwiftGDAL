# SwiftGDAL

Swift bindings over [GDAL](https://gdal.org/), distributed as a SwiftPM
package. The `gdal.xcframework` and `proj.xcframework` are fetched from
[gdal-xcframework-builder](https://github.com/mnmly/gdal-xcframework-builder)
GitHub releases via URL + checksum — see `Package.swift`.

## Layout

- `Sources/SwiftGDAL/` — public Swift API
  - `Vector/` — OGR types (`VectorDataset`, `Layer`, `Feature`, `Geometry`)
- `Tests/SwiftGDALTests/` — Swift Testing suites
- `Examples/gdalinfo/` — SPM CLI demo (`swift run gdalinfo <path>`)
- `Examples/GDALApp/` — iOS + macOS SwiftUI demo app
- `Scripts/build_docs.sh` — DocC static-site builder

## Concurrency invariant

`Dataset`, `RasterBand`, `VectorDataset`, `Layer`, `Feature`, and
`Geometry` are deliberately **not `Sendable`**. GDAL handles are not safe
to share across threads. Async overloads hop to `Task.detached` via the
internal `UnsafeTransfer` helper so the closure can ferry the
non-Sendable instance across the boundary — the safety invariant is that
only one task touches the handle at a time. Don't relax this without
checking GDAL's thread-safety guarantees for the specific call.

## Local development

```bash
swift build
swift test
```

To iterate against a locally-built xcframework instead of the published
release, swap each `.binaryTarget` in `Package.swift` to `path:
"Frameworks/<name>.xcframework"` and drop a fresh build into
`Frameworks/` (gitignored).

## Documentation

`SwiftGDAL` ships DocC-generated reference docs (see
`Sources/SwiftGDAL/Documentation.docc/` and `Scripts/build_docs.sh`).
**`///` doc comments on public/`open` symbols are published** to the
static site at https://mnmly.github.io/SwiftGDAL/ and (if
`EMIT_LLMS_TXT=1` is used) into `docs/llms.txt`.

When you add or modify a `public` or `open` declaration:

- Write a `///` doc comment. One-sentence summary, then a paragraph if
  the *why* is non-obvious. Skip restating what the signature already
  says.
- Document each parameter with `- Parameter name:` (use the **internal**
  name when there's an external label — DocC warns otherwise).
- Cross-reference related symbols with double-backtick links, e.g.
  `` ``Dataset/band(_:)`` ``. DocC link syntax is signature-sensitive:
  `foo(_:)` and `foo(_:_:)` are different.
- When you add a new top-level symbol that belongs in the curated
  sidebar, add it under the appropriate `## Topics` group in
  `Sources/SwiftGDAL/Documentation.docc/SwiftGDAL.md`. Topics are
  organized by *user task*, not alphabetic order.

Verify before declaring documentation work done:

```bash
Scripts/build_docs.sh
```

Expect exit 0 and no new "doesn't exist at" or "external name used to
document parameter" warnings attributable to your changes.
