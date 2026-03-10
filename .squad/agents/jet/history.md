# Jet — History

## Core Context

**Project:** otaku — terminal-based manga browser and downloader  
**Language:** Zig (0.15.2)  
**User:** Christian Helle  
**Build:** `zig build` | **Test:** `zig build test`  
**Stack:** Zig, terminal UI (TUI), HTTP client, manga scraping  
**Sources:** MangaFox/FanFox and other manga websites  
**Repo:** C:\projects\christianhelle\otaku  

**Team:**
- Spike — Lead (architecture, reviews)
- Jet (me) — Systems Dev
- Faye — TUI Dev
- Ed — Tester

**Key files (src/):** main.zig, cli.zig, http.zig, html.zig, fanfox.zig, tui.zig, browser.zig

## Learnings

### Session: Systems Layer Implementation (2025)

**Zig 0.15.2 API gotchas:**
- `std.ArrayList(u8).init(allocator)` does NOT work — use `std.ArrayListUnmanaged(u8).empty` with explicit allocator in every method call
- `std.io.bufferedWriter` does NOT exist — build strings with `ArrayListUnmanaged` or use `std.fmt.allocPrint`
- Writer pattern: `const fw = std.fs.File.stderr().writer(&buf);` (must be `const`, not `var`)
- `std.ascii.lowerString(output, input)` requires `[]u8` output (mutable, not `*const [N]u8`)
- `var` vs `const` for array buffers: Zig 0.15.2 requires `const` if the binding itself is never reassigned, even if contents are mutated via a slice passed to another function

**Architecture decisions:**
- `src/util/html.zig` — extracted from argiope, added `extractText`, `findAttrValue`, `asciiEqlIgnoreCase`
- `src/util/urls.zig` — already had `extractSlug`, `isValidSlug`, `isFanfoxUrl`; added `resolveUrl`, `mangaUrl`
- `src/util/strings.zig` — already had core funcs; added `splitOnce`
- `src/http/client.zig` — direct port of argiope's http.zig
- `src/fanfox/parsers/chapters.zig` — adapted from argiope mangafox.zig's `parseChapterList`, uses `[]domain.Chapter`
- `src/fanfox/parsers/categories.zig` — shared `parseMangaList`; directory.zig delegates to it
- `src/downloads/manifest.zig` — manual JSON serialization (simpler than `std.json` for this small schema)
- `src/library/builder.zig` — walks directory tree, generates HTML; uses `std.fs.Dir.iterate`

**What was implemented (fully):**
- `http/client.zig` — complete HTTP client with redirect following (ported from argiope)
- `http/rate_limiter.zig` — delay enforcement with nanosecond timestamps
- `http/retry.zig` — exponential backoff retry
- `util/html.zig` — link extraction, text extraction, attribute lookup
- `util/urls.zig` — slug extraction, URL resolution, fanfox URL construction
- `util/strings.zig` — string utilities including `splitOnce`
- `fanfox/endpoints.zig` — URL constants and builder functions
- `fanfox/parsers/chapters.zig` — chapter list parser (adapts argiope logic)
- `fanfox/parsers/title.zig` — title detail page parser (resilient, never errors on partial parse)
- `fanfox/parsers/categories.zig` — category/listing page parser
- `fanfox/parsers/directory.zig` — delegates to categories parser
- `fanfox/client.zig` — high-level client wrapping HTTP + rate limiter + retry + parsers
- `downloads/manifest.zig` — JSON manifest with save/load, manual JSON parser
- `downloads/saver.zig` — image downloader with skip-existing behavior
- `library/templates.zig` — HTML templates for library index, title pages, reader pages
- `library/builder.zig` — directory walker that generates full HTML library

**Build result:** `zig build` ✅ | `zig build test` ✅ — 95/95 tests pass
