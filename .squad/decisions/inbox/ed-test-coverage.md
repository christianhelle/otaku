# Ed — Test Coverage Report

**Date:** 2026-03-10  
**Author:** Ed (Tester)

## Summary

Added comprehensive test coverage across the otaku codebase. Total test count grew to **69 tests, all passing**.

## Changes Made

### New implementations with tests
- **`src/util/strings.zig`** — Implemented `trimWhitespace`, `containsIgnoreCase`, `parseChapterRange`, `formatFileSize`. 10 tests covering normal paths, edge cases (empty strings, invalid format errors, all size units).
- **`src/util/urls.zig`** — Implemented `extractSlug`, `isValidSlug`, `isFanfoxUrl`. 9 tests covering URL parsing, null returns for invalid inputs, slug validation edge cases.

### Augmented existing modules
- **`src/domain/chapter.zig`** — Added `filterChaptersInRange(allocator, chapters, from, to)` function. 4 tests: basic range, single chapter, no matches, empty input.
- **`src/domain/manga.zig`** — 5 new tests: deinit with null optionals, deinit with all fields populated, empty CategoryFeed deinit, full MangaStatus/CategoryKind enum coverage.
- **`src/domain/filters.zig`** — 4 new tests: SortOrder all query params, GenreFilter field, BrowseFilter with genre/page/sort, default sort order.
- **`src/storage/config.zig`** — 4 new tests: non-empty user agent, delay/concurrency/retries defaults, relative library root path, cache dir value.

### HTML Fixture files
Created `src/fanfox/parsers/fixtures/` with 5 files for parser testing:
- `chapter_list.html` — realistic chapter list with decimal chapter (5.5), title spans, and duplicate entry
- `title_detail.html` — full title detail page with author, genres, summary, cover image
- `category_list.html` — category listing with two manga entries
- `empty_page.html` — edge case: no results page
- `malformed.html` — edge case: broken/unclosed HTML tags

## Critical Zig 0.15.2 Finding

**`std.ArrayList` is now unmanaged.** There is no `init(allocator)` method. The correct pattern is:
```zig
var list: std.ArrayList(T) = .empty;
defer list.deinit(allocator);
try list.append(allocator, item);
const slice = try list.toOwnedSlice(allocator);
```
This differs from 0.13/0.14 patterns. All future Zig code using dynamic arrays must use this form.

## Edge Cases Identified

1. `MangaTitle.deinit` — null optional fields handled correctly (no crash on null cover_url/author/summary)
2. `CategoryFeed.deinit` — safe on empty titles slice
3. `parseChapterRange` — returns `error.InvalidFormat` for non-numeric input
4. `extractSlug` — returns null for empty string and URLs without `/manga/` segment
5. `filterChaptersInRange` — correctly handles empty chapter list (returns empty slice, no allocation)

## Recommendation

Parser tests (categories, chapters, title, reader parsers) cannot be meaningfully unit-tested yet — they require HTTP responses or a DOM parser. The fixture files are ready for when that infrastructure is added. A future task should implement parser tests using the fixtures in `src/fanfox/parsers/fixtures/`.
