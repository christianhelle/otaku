# Ed — History

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
- Jet — Systems Dev (HTTP, scraping)
- Faye — TUI Dev
- Ed (me) — Tester

**Test command:** `zig build test`

## Learnings

### 2026-03-10 — Comprehensive test coverage pass

**Zig 0.15.2 ArrayList API change (critical):**  
`std.ArrayList(T)` is now unmanaged — no `init(allocator)`. Use `.empty` for initialization and pass allocator to every call: `append(allocator, item)`, `deinit(allocator)`, `toOwnedSlice(allocator)`. The old `AlignedManaged` pattern (with stored allocator) still exists as deprecated.

**Test count:** Grew from baseline to **69 tests, all passing**.

**Files added/modified:**
- `src/util/strings.zig` — implemented `trimWhitespace`, `containsIgnoreCase`, `parseChapterRange`, `formatFileSize` + 10 tests
- `src/util/urls.zig` — implemented `extractSlug`, `isValidSlug`, `isFanfoxUrl` + 9 tests
- `src/domain/chapter.zig` — added `filterChaptersInRange` function + 4 tests
- `src/domain/manga.zig` — added deinit edge case tests (null optionals, empty feed) + enum coverage
- `src/domain/filters.zig` — added SortOrder, GenreFilter, BrowseFilter tests
- `src/storage/config.zig` — added user agent, library root, cache dir validation tests
- `src/fanfox/parsers/fixtures/` — created 5 HTML fixture files for parser testing

**Edge cases found:**
- `MangaTitle.deinit` correctly handles null `cover_url`, `author`, `summary` and empty `genres` slice
- `CategoryFeed.deinit` safely handles empty `titles` slice
- `parseChapterRange("abc")` correctly returns `error.InvalidFormat`
- `extractSlug("")` returns null without panicking
