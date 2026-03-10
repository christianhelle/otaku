# Jet — History

## Core Context

**Project:** otaku — terminal-based manga browser and downloader  
**Language:** Zig (0.15.2)  
**User:** Christian Helle  
**Build:** zig build | **Test:** zig build test  
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
- std.ArrayList(u8).init(allocator) does NOT work — use std.ArrayListUnmanaged(u8).empty with explicit allocator in every method call
- std.io.bufferedWriter does NOT exist — build strings with ArrayListUnmanaged or use std.fmt.allocPrint
- Writer pattern: const fw = std.fs.File.stderr().writer(&buf); (must be const, not var)
- std.ascii.lowerString(output, input) requires []u8 output (mutable, not *const [N]u8)
- var vs const for array buffers: Zig 0.15.2 requires const if the binding itself is never reassigned

**Architecture decisions:**
- src/util/html.zig — extracted from argiope, added extractText, findAttrValue, asciiEqlIgnoreCase
- src/util/urls.zig — already had extractSlug, isValidSlug, isFanfoxUrl; added resolveUrl, mangaUrl
- src/util/strings.zig — already had core funcs; added splitOnce
- src/http/client.zig — direct port of argiope's http.zig
- src/fanfox/parsers/chapters.zig — adapted from argiope mangafox.zig's parseChapterList
- src/fanfox/parsers/categories.zig — shared parseMangaList; directory.zig delegates
- src/downloads/manifest.zig — manual JSON serialization (simpler than std.json)
- src/library/builder.zig — walks directory tree, generates HTML; uses std.fs.Dir.iterate

**What was implemented (fully):**
- http/client.zig — complete HTTP client with redirect following
- http/rate_limiter.zig — delay enforcement with nanosecond timestamps
- http/retry.zig — exponential backoff retry
- util/html.zig — link extraction, text extraction, attribute lookup
- util/urls.zig — slug extraction, URL resolution, fanfox URL construction
- util/strings.zig — string utilities including splitOnce
- fanfox/endpoints.zig — URL constants and builder functions
- fanfox/parsers/chapters.zig — chapter list parser
- fanfox/parsers/title.zig — title detail page parser (resilient)
- fanfox/parsers/categories.zig — category/listing page parser
- fanfox/parsers/directory.zig — delegates to categories parser
- fanfox/client.zig — high-level client wrapping HTTP + rate limiter + retry + parsers
- downloads/manifest.zig — JSON manifest with save/load
- downloads/saver.zig — image downloader with skip-existing behavior
- library/templates.zig — HTML templates for library index, title pages, reader pages
- library/builder.zig — directory walker that generates full HTML library

**Build result:** zig build ✅ | zig build test ✅ — 95/95 tests pass

### Session: Downloads Manager/Queue + CLI Commands Implementation (2025)

**Phase 5-6 Implementation:**
- src/downloads/manager.zig — implemented DownloadManager with init, deinit, downloadChapter, downloadAll
- src/downloads/queue.zig — implemented DownloadQueue with init, deinit, enqueue, dequeue, len
- src/main.zig — wired up all CLI commands: browse, search, title, download, library_build

**CLI Commands Wired:**
1. .browse — fetches category feeds, prints title list with status and author
2. .search — searches manga by query string, prints results
3. .title — fetches title details and chapter list, handles both URL and slug
4. .download — queues chapters for download, builds directory structure, defers image fetch
5. .library_build — builds HTML library from local manga directory

**Architecture notes:**
- Each CLI command creates fresh GPA allocator for isolation
- Each command creates own FanfoxClient instance
- Download manager creates chapter directories, image fetching deferred (reader parser TODO)
- Chapter filtering by range (--chapters N-M) noted as TODO

**Zig 0.15.2 patterns used:**
- std.ArrayListUnmanaged(T).empty for queue initialization (not .init())
- Writer pattern: var fw = std.fs.File.stdout().writer(&buf); with fw.interface.print() and fw.interface.flush()
- @constCast(ptr).deinit() for deallocating items in const slices
- Test cleanup with defer std.fs.cwd().deleteTree(path) catch {}

**Tests added:**
- DownloadManager: init/deinit, downloadChapter creates directory
- DownloadQueue: init/deinit, enqueue/dequeue FIFO, len tracking

**Build result:** zig build ✅ | zig build test ✅ — 100/100 tests pass

### Phase 4-5 Coordination with Spike
- Spike wired TUI layer to FanfoxClient for live network data
- My CLI commands reuse same FanfoxClient initialization pattern
- Memory management aligned: commands handle allocators independently
- Download queue mirrors Spike's TUI queue (both use DownloadJob structs)
- Ready for Phase 7: download engine processing queued jobs
