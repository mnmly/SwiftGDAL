#!/usr/bin/env bash
# Build the SwiftGDAL DocC site into ./docs (GitHub Pages-ready).
#
# Why this isn't the usual `swift package generate-documentation`:
# the swift-docc-plugin doesn't pass `-F` to `swift-symbolgraph-extract`,
# so the extractor can't resolve `import gdal` (the gdal binaryTarget is
# a framework xcframework). We extract the symbol graph by hand with the
# correct framework search path, then drive `docc convert` directly.
#
# Usage:
#   Scripts/build_docs.sh                # build into ./docs
#   Scripts/build_docs.sh preview        # local preview via `docc preview`
#
# Optional env:
#   HOSTING_BASE_PATH    Pages base, default "SwiftGDAL".
#   REPO_URL             https URL to the repo for source links.
#   REPO_BRANCH          Branch for source links, default main.
#   OUTPUT_DIR           Default: docs
set -euo pipefail
cd "$(dirname "$0")/.."

TARGET="SwiftGDAL"
HOSTING_BASE_PATH="${HOSTING_BASE_PATH:-SwiftGDAL}"
REPO_URL="${REPO_URL:-https://github.com/mnmly/SwiftGDAL}"
REPO_BRANCH="${REPO_BRANCH:-main}"
OUTPUT_DIR="${OUTPUT_DIR:-docs}"

MODE="build"
case "${1:-}" in
    preview) MODE="preview" ;;
esac

# Build the package once so binaryTarget artifacts are extracted and the
# Swift module is up to date.
swift build >/dev/null

ARTIFACTS_DIR=".build/artifacts/swiftgdal"
GDAL_FW_DIR="$(pwd)/$ARTIFACTS_DIR/gdal/gdal.xcframework/macos-arm64"
if [[ ! -d "$GDAL_FW_DIR/gdal.framework" ]]; then
    echo "error: gdal.framework not found at $GDAL_FW_DIR" >&2
    exit 1
fi

# Locate the built .swiftmodule directory so the extractor can find the
# SwiftGDAL module itself.
BUILD_DIR="$(swift build --show-bin-path)"
MODULES_DIR="$BUILD_DIR/Modules"

SYMGRAPH_DIR=".build/symbol-graphs/$TARGET"
rm -rf "$SYMGRAPH_DIR"
mkdir -p "$SYMGRAPH_DIR"

echo ">> Extracting symbol graph for $TARGET"
xcrun swift-symbolgraph-extract \
    -module-name "$TARGET" \
    -F "$GDAL_FW_DIR" \
    -I "$MODULES_DIR" \
    -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
    -target arm64-apple-macosx13.3 \
    -minimum-access-level public \
    -skip-inherited-docs \
    -emit-extension-block-symbols \
    -output-dir "$SYMGRAPH_DIR"

CATALOG="Sources/$TARGET/Documentation.docc"
out="$OUTPUT_DIR/$TARGET"
rm -rf "$out"
mkdir -p "$out"

SOURCE_FLAGS=()
if [[ -n "$REPO_URL" ]]; then
    SOURCE_FLAGS+=(
        --source-service github
        --source-service-base-url "${REPO_URL%/}/blob/${REPO_BRANCH}"
        --checkout-path "$(pwd)"
    )
fi

EXTRA_FLAGS=()
if [[ "${EMIT_MARKDOWN:-0}" == "1" || "${EMIT_LLMS_TXT:-0}" == "1" ]]; then
    EXTRA_FLAGS+=(--enable-experimental-markdown-output)
fi

if [[ "$MODE" == "preview" ]]; then
    echo ">> Previewing $TARGET"
    exec xcrun docc preview "$CATALOG" \
        --fallback-display-name "$TARGET" \
        --fallback-bundle-identifier "$HOSTING_BASE_PATH" \
        --additional-symbol-graph-dir "$SYMGRAPH_DIR"
fi

echo ">> Converting $TARGET → $out"
xcrun docc convert "$CATALOG" \
    --fallback-display-name "$TARGET" \
    --fallback-bundle-identifier "$HOSTING_BASE_PATH" \
    --additional-symbol-graph-dir "$SYMGRAPH_DIR" \
    --output-path "$out" \
    --emit-digest \
    --transform-for-static-hosting \
    --hosting-base-path "${HOSTING_BASE_PATH}/${TARGET}" \
    ${SOURCE_FLAGS[@]+"${SOURCE_FLAGS[@]}"} \
    ${EXTRA_FLAGS[@]+"${EXTRA_FLAGS[@]}"}

# Top-level redirect so visiting Pages root lands on the SwiftGDAL page.
cat > "$OUTPUT_DIR/index.html" <<HTML
<!doctype html>
<meta http-equiv="refresh" content="0; url=./${TARGET}/documentation/$(echo "$TARGET" | tr '[:upper:]' '[:lower:]')/">
<title>${HOSTING_BASE_PATH} docs</title>
HTML

if [[ "${EMIT_LLMS_TXT:-0}" == "1" ]]; then
    LLMS="$OUTPUT_DIR/llms.txt"
    {
        echo "# ${HOSTING_BASE_PATH} — DocC export for LLM consumption"
        echo
        echo "Generated $(date -u +%FT%TZ) from swift-docc."
        echo
        find "$out/data" -name '*.md' -type f 2>/dev/null | sort | while IFS= read -r f; do
            rel="${f#$OUTPUT_DIR/}"
            echo
            echo "---"
            echo "## $rel"
            echo
            cat "$f"
        done
    } > "$LLMS"
    echo "Wrote $LLMS ($(wc -l < "$LLMS" | tr -d ' ') lines)."
fi

echo
echo "Docs written to $out/. Open $out/index.html to preview."
