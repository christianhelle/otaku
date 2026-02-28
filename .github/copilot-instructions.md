# Otaku – Copilot Instructions

`otaku` is a high-performance desktop manga reader written in Zig (minimum version 0.15.2). It crawls well-known manga websites, persists data locally in a compact binary database, and renders via an immediate-mode UI designed for maximum throughput.

## Build, run, and test

```sh
zig build              # compile → zig-out/bin/otaku
zig build run          # build + run
zig build test         # run all tests
```

There is no per-file test runner; individual test blocks are inline in their source files.
`main.zig` has a `test "imports compile"` block that imports all other modules,
ensuring the test binary transitively covers all inline tests when `src/main.zig` is the test root.

## Architecture

All source files live flat in `src/`. The data flow is:

```
main.zig  →  database.zig  ←→  manga.zig (types + serialization)
    ↓              ↑
 ui.zig      crawler.zig (MangaDex API)
```

| File | Responsibility |
|---|---|
| `main.zig` | Entry point; owns `GeneralPurposeAllocator`; initializes database and starts UI loop or prints library to stdout |
| `manga.zig` | Core data types (`Manga`, `Chapter`, `Page`, `ReadingProgress`, `Source` enum); binary serialization/deserialization helpers |
| `database.zig` | File-based persistence layer; stores manga, chapters, pages, and reading progress in compact binary `.db` files under `~/.config/otaku/` |
| `crawler.zig` | HTTP crawler targeting the MangaDex public API; lightweight JSON scanner for parsing API responses; builds search/chapter/page URLs |
| `ui.zig` | Application UI state machine (`View` enum: library, search, chapter_list, reader); navigation, scrolling, search, and page controls. Raylib rendering is wired via `build.zig` when the `raylib-zig` dependency is available |

## Database format

Each `.db` file follows this binary layout:

```
Header: "OTKU" (4 bytes magic) | version (u32 LE) | record_count (u32 LE) [ | next_id (u64 LE) ]
Records: [record_count × serialized struct]
```

Strings are length-prefixed: `len (u32 LE) | data ([len]u8)`. Maximum string length is 10 MB (safety limit).

## Key conventions

**Tests are inline.** Every `.zig` file with logic contains `test` blocks directly in that file.
`main.zig` has a single `test "imports compile"` block that imports all modules,
ensuring the test binary transitively covers all inline tests.

**Ownership model:** The `Database` struct owns all string data via heap allocations.
`addManga()`, `addChapter()`, `addPage()` each `dupe` every string field.
Corresponding `deinit` and `remove*` methods free the duplicated strings.

**Crawler is allocation-aware.** Parse methods (`parseSearchResults`, `parseChapterFeed`, `parsePageList`)
return `ArrayList` values. Callers are responsible for freeing both the list and each item's string fields
via the item's `deinit` method.

**The JSON scanner is minimal.** `JsonScanner` is a forward-only, non-allocating scanner designed
for the well-structured MangaDex API responses. It is not a general-purpose JSON parser.

**UI state is decoupled from rendering.** `ui.zig` manages view state, navigation, and input handling
without direct raylib calls. This allows comprehensive testing of all UI logic without a display server.

**Source control:** Commit progress to git in small logical chunks with clear one-liner messages.
Do not change the committer to Copilot and do not add a Co-Author line.
