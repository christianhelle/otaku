# Jet: Systems Layer Decisions

**Date:** 2025  
**Author:** Jet (Systems Dev)

## HTTP Client
- Ported argiope's `http.zig` wholesale as `src/http/client.zig`. Proven in production (argiope project), handles redirects, connection pooling via `std.http.Client`.
- Rate limiter uses `std.time.nanoTimestamp()` (i128) and `std.Thread.sleep()` for precise throttling.
- Retry uses exponential backoff: `min(base * 2^attempt, max_delay)`.

## HTML/URL Utilities
- `src/util/html.zig` adapted from argiope's html.zig. Added `extractText` (tag stripping) and public `findAttrValue`.
- `src/util/urls.zig` extends the pre-existing slug/isValid/isFanfox functions with `resolveUrl` and `mangaUrl`.

## Fanfox Parsers
- Chapter parser adapted from argiope's `parseChapterList` (removes verbose logging, returns `[]domain.Chapter` instead of `[]MangafoxChapter`).
- Title parser is resilient: never returns error on partial parse, all fields have empty/null defaults.
- Category and directory parsers share `parseMangaList` — directory.zig delegates to categories.zig.
- Deduplication by slug prevents duplicate entries in listing pages.

## Downloads
- `manifest.zig` uses manual JSON serialization (avoids `std.json` complexity for a small schema). Handles both quoted strings and unquoted integer values in parsing.
- `saver.zig` checks file existence before downloading (skip-existing), creates parent dirs with `makePath`.

## Library Builder
- `builder.zig` discovers manga by iterating subdirectories; chapter dirs named `c{number}`.
- `templates.zig` uses `std.ArrayListUnmanaged(u8)` with `std.fmt.allocPrint` for formatted HTML (no `std.io.bufferedWriter` which doesn't exist in Zig 0.15.2).

## Zig 0.15.2 Compatibility
- All `std.ArrayList(T)` usage replaced with `std.ArrayListUnmanaged(T)` — `ArrayList.init()` does not exist in 0.15.2.
- `std.io.bufferedWriter` does not exist in 0.15.2 — avoid.
- Writer locals must be `const` (not `var`) if the binding itself is never reassigned.
